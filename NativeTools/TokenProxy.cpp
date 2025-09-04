/*
TokenProxy - Lettvekts lokal HTTP-mikrotjeneste for Make/Airtable m.fl.
Formål:
  - Eksponere sikre, temporære autorisasjons-headere uten at Make lagrer rå secrets
  - Signere kall med HMAC-SHA256 (base64url) via X-Signature og X-Timestamp
  - KUN lokal binding (127.0.0.1). Krever API-nøkkel i header X-Proxy-Key

Bygg:
  - Windows (MSVC):
      cl /std:c++17 /EHsc /O2 TokenProxy.cpp /link Ws2_32.lib
  - MinGW (Windows):
      g++ -std=c++17 -O2 -lws2_32 TokenProxy.cpp -o token-proxy.exe

Kjør:
  - Sett ENV:
      set TOKEN_PROXY_KEY=velg-en-sterk-lokal-nokkel
      set TOKEN_PROXY_PORT=7071           (valgfritt, default 7071)
      set MAKE_API_TOKEN=...              (valgfritt)
      set AIRTABLE_API_KEY=...            (valgfritt)
      set MISTRAL_API_KEY=...             (valgfritt)
      set MAKE_HMAC_SECRET=...            (valgfritt, aktiverer signering)
  - Start:
      token-proxy.exe

Endepunkter (alle krever header X-Proxy-Key: <TOKEN_PROXY_KEY>):
  - GET /health
      -> { "status":"ok", "ts": 1730000000 }
  - GET /v1/headers?target=make|airtable|mistral
      -> returnerer passende "Authorization" header som JSON:
         { "headers": { "Authorization":"Bearer <...>", "X-Signature":"...", "X-Timestamp":"..." } }
         Hvis MAKE_HMAC_SECRET er satt, legges X-Signature og X-Timestamp ved (signert: "<ts>::GET::/v1/headers::<target>")
  - GET /v1/sign?payload=<urlencoded>
      -> { "alg":"HS256", "sig":"<base64url>", "ts":"<epoch-seconds>" }
*/

#define _WINSOCK_DEPRECATED_NO_WARNINGS
#include <winsock2.h>
#include <ws2tcpip.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <thread>
#include <unordered_map>
#include <chrono>
#include <sstream>
#include <iomanip>
#include <algorithm>

#pragma comment(lib, "Ws2_32.lib")

// ========== Util: trim, url-decode, split, time ==========
static inline std::string ltrim(const std::string& s) {
    size_t i=0; while (i<s.size() && (s[i]==' '||s[i]=='\t'||s[i]=='\r'||s[i]=='\n')) ++i; return s.substr(i);
}
static inline std::string rtrim(const std::string& s) {
    if (s.empty()) return s;
    size_t i=s.size()-1; while (i>0 && (s[i]==' '||s[i]=='\t'||s[i]=='\r'||s[i]=='\n')) --i;
    return s.substr(0, s[i]==' '||s[i]=='\t'||s[i]=='\r'||s[i]=='\n' ? i : i+1);
}
static inline std::string trim(const std::string& s){ return rtrim(ltrim(s)); }

static inline int from_hex(char ch) {
    if (ch>='0'&&ch<='9') return ch - '0';
    if (ch>='a'&&ch<='f') return ch - 'a' + 10;
    if (ch>='A'&&ch<='F') return ch - 'A' + 10;
    return -1;
}
static std::string url_decode(const std::string& in) {
    std::string out; out.reserve(in.size());
    for (size_t i=0;i<in.size();++i) {
        char c = in[i];
        if (c=='%' && i+2<in.size()) {
            int hi=from_hex(in[i+1]); int lo=from_hex(in[i+2]);
            if (hi>=0 && lo>=0) { out.push_back(char((hi<<4)|lo)); i+=2; }
            else out.push_back(c);
        } else if (c=='+') out.push_back(' ');
        else out.push_back(c);
    }
    return out;
}
static std::unordered_map<std::string,std::string> parse_query(const std::string& query) {
    std::unordered_map<std::string,std::string> m;
    size_t start=0;
    while (start<query.size()) {
        size_t amp = query.find('&', start);
        std::string kv = query.substr(start, amp==std::string::npos? std::string::npos : amp-start);
        size_t eq = kv.find('=');
        std::string k = url_decode(eq==std::string::npos? kv : kv.substr(0,eq));
        std::string v = url_decode(eq==std::string::npos? "" : kv.substr(eq+1));
        if (!k.empty()) m[k]=v;
        if (amp==std::string::npos) break;
        start = amp+1;
    }
    return m;
}
static inline long long epoch_sec() {
    using namespace std::chrono;
    return duration_cast<seconds>(system_clock::now().time_since_epoch()).count();
}

// ========== Util: base64url ==========
static const char b64tab[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static std::string base64(const std::vector<uint8_t>& data) {
    std::string out; out.reserve(((data.size()+2)/3)*4);
    size_t i=0; while (i+2<data.size()) {
        uint32_t n = (data[i]<<16) | (data[i+1]<<8) | data[i+2];
        out.push_back(b64tab[(n>>18)&63]);
        out.push_back(b64tab[(n>>12)&63]);
        out.push_back(b64tab[(n>>6)&63]);
        out.push_back(b64tab[n&63]);
        i+=3;
    }
    if (i+1==data.size()) {
        uint32_t n = (data[i]<<16);
        out.push_back(b64tab[(n>>18)&63]);
        out.push_back(b64tab[(n>>12)&63]);
        out.push_back('=');
        out.push_back('=');
    } else if (i+2==data.size()) {
        uint32_t n = (data[i]<<16) | (data[i+1]<<8);
        out.push_back(b64tab[(n>>18)&63]);
        out.push_back(b64tab[(n>>12)&63]);
        out.push_back(b64tab[(n>>6)&63]);
        out.push_back('=');
    }
    return out;
}
static std::string base64url(const std::vector<uint8_t>& data) {
    std::string b = base64(data);
    for (auto& c : b) { if (c=='+') c='-'; else if (c=='/') c='_'; }
    while (!b.empty() && b.back()=='=') b.pop_back();
    return b;
}
static std::string base64url_str(const std::string& s) {
    std::vector<uint8_t> v(s.begin(), s.end());
    return base64url(v);
}

// ========== SHA256 (compact) + HMAC-SHA256 ==========
// (Kompakt SHA-256 implementasjon, public domain-stil)
struct SHA256_CTX {
    uint64_t bitlen;
    uint32_t state[8];
    uint8_t data[64];
    size_t datalen;
};
static const uint32_t K256[64] = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};
static inline uint32_t ROTR(uint32_t x, uint32_t n){ return (x>>n) | (x<<(32-n)); }
static inline uint32_t CH(uint32_t x,uint32_t y,uint32_t z){ return (x & y) ^ (~x & z); }
static inline uint32_t MAJ(uint32_t x,uint32_t y,uint32_t z){ return (x & y) ^ (x & z) ^ (y & z); }
static inline uint32_t EP0(uint32_t x){ return ROTR(x,2)^ROTR(x,13)^ROTR(x,22); }
static inline uint32_t EP1(uint32_t x){ return ROTR(x,6)^ROTR(x,11)^ROTR(x,25); }
static inline uint32_t SIG0(uint32_t x){ return ROTR(x,7)^ROTR(x,18)^(x>>3); }
static inline uint32_t SIG1(uint32_t x){ return ROTR(x,17)^ROTR(x,19)^(x>>10); }

static void sha256_transform(SHA256_CTX* ctx, const uint8_t data[]) {
    uint32_t m[64];
    for (int i=0;i<16;i++){
        m[i] = (data[i*4]<<24)|(data[i*4+1]<<16)|(data[i*4+2]<<8)|(data[i*4+3]);
    }
    for (int i=16;i<64;i++){
        m[i] = SIG1(m[i-2]) + m[i-7] + SIG0(m[i-15]) + m[i-16];
    }
    uint32_t a=ctx->state[0],b=ctx->state[1],c=ctx->state[2],d=ctx->state[3],
             e=ctx->state[4],f=ctx->state[5],g=ctx->state[6],h=ctx->state[7];

    for(int i=0;i<64;i++){
        uint32_t t1 = h + EP1(e) + CH(e,f,g) + K256[i] + m[i];
        uint32_t t2 = EP0(a) + MAJ(a,b,c);
        h=g; g=f; f=e; e=d + t1; d=c; c=b; b=a; a=t1 + t2;
    }
    ctx->state[0]+=a; ctx->state[1]+=b; ctx->state[2]+=c; ctx->state[3]+=d;
    ctx->state[4]+=e; ctx->state[5]+=f; ctx->state[6]+=g; ctx->state[7]+=h;
}

static void sha256_init(SHA256_CTX* ctx) {
    ctx->datalen=0; ctx->bitlen=0;
    ctx->state[0]=0x6a09e667; ctx->state[1]=0xbb67ae85; ctx->state[2]=0x3c6ef372; ctx->state[3]=0xa54ff53a;
    ctx->state[4]=0x510e527f; ctx->state[5]=0x9b05688c; ctx->state[6]=0x1f83d9ab; ctx->state[7]=0x5be0cd19;
}
static void sha256_update(SHA256_CTX* ctx, const uint8_t data[], size_t len) {
    for (size_t i=0;i<len;i++){
        ctx->data[ctx->datalen++] = data[i];
        if (ctx->datalen==64){
            sha256_transform(ctx, ctx->data);
            ctx->bitlen += 512;
            ctx->datalen = 0;
        }
    }
}
static void sha256_final(SHA256_CTX* ctx, uint8_t hash[]) {
    size_t i = ctx->datalen;
    // pad
    ctx->data[i++] = 0x80;
    if (i > 56) {
        while (i<64) ctx->data[i++] = 0x00;
        sha256_transform(ctx, ctx->data);
        i=0;
    }
    while (i<56) ctx->data[i++] = 0x00;
    ctx->bitlen += ctx->datalen * 8ULL;
    // append length big-endian
    for (int j=7;j>=0;--j){
        ctx->data[56+(7-j)] = (uint8_t)((ctx->bitlen >> (j*8)) & 0xff);
    }
    sha256_transform(ctx, ctx->data);
    for (int j=0;j<8;j++){
        hash[j*4]   = (uint8_t)((ctx->state[j]>>24)&0xff);
        hash[j*4+1] = (uint8_t)((ctx->state[j]>>16)&0xff);
        hash[j*4+2] = (uint8_t)((ctx->state[j]>>8)&0xff);
        hash[j*4+3] = (uint8_t)(ctx->state[j]&0xff);
    }
}
static std::vector<uint8_t> sha256(const std::string& data) {
    SHA256_CTX c; sha256_init(&c);
    sha256_update(&c, (const uint8_t*)data.data(), data.size());
    std::vector<uint8_t> out(32); sha256_final(&c, out.data());
    return out;
}
static std::vector<uint8_t> hmac_sha256(const std::string& key, const std::string& msg) {
    const size_t block = 64;
    std::string k = key;
    if (k.size()>block) { auto h=sha256(k); k.assign((const char*)h.data(), h.size()); }
    if (k.size()<block) k.append(block - k.size(), '\0');

    std::string o(block,'\0'), i(block,'\0');
    for (size_t idx=0; idx<block; ++idx) {
        o[idx] = (char)( ((unsigned char)k[idx]) ^ 0x5c );
        i[idx] = (char)( ((unsigned char)k[idx]) ^ 0x36 );
    }
    std::string inner = i + msg;
    auto ih = sha256(inner);
    std::string outer = o + std::string((const char*)ih.data(), ih.size());
    auto oh = sha256(outer);
    return oh;
}

// ========== JSON helper ==========
static std::string json_escape(const std::string& s) {
    std::ostringstream oss; oss << '"';
    for (char c : s) {
        switch (c) {
        case '\\': oss << "\\\\"; break;
        case '"':  oss << "\\\""; break;
        case '\b': oss << "\\b";  break;
        case '\f': oss << "\\f";  break;
        case '\n': oss << "\\n";  break;
        case '\r': oss << "\\r";  break;
        case '\t': oss << "\\t";  break;
        default:
            if ((unsigned char)c < 0x20) { oss << "\\u" << std::hex << std::setw(4) << std::setfill('0') << (int)(unsigned char)c; }
            else oss << c;
        }
    }
    oss << '"';
    return oss.str();
}

// ========== HTTP minimal ==========
struct Request {
    std::string method;
    std::string path;
    std::string query;
    std::unordered_map<std::string,std::string> headers;
};
static inline std::string tolower_str(std::string s){ for(char& c:s) c=(char)tolower((unsigned char)c); return s; }

static bool recv_line(SOCKET s, std::string& out) {
    out.clear();
    char c; int n;
    while (true) {
        n = recv(s, &c, 1, 0);
        if (n<=0) return false;
        if (c=='\r') continue;
        if (c=='\n') break;
        out.push_back(c);
        if (out.size()>8192) break;
    }
    return true;
}
static bool read_request(SOCKET s, Request& req) {
    std::string line;
    if (!recv_line(s, line)) return false;
    std::istringstream iss(line);
    iss >> req.method;
    std::string uri; iss >> uri;
    size_t qm = uri.find('?');
    if (qm==std::string::npos) { req.path=uri; req.query=""; }
    else { req.path=uri.substr(0,qm); req.query=uri.substr(qm+1); }
    // headers
    while (true) {
        if (!recv_line(s, line)) return false;
        if (line.empty()) break;
        size_t col = line.find(':');
        if (col!=std::string::npos) {
            std::string k = tolower_str(trim(line.substr(0,col)));
            std::string v = trim(line.substr(col+1));
            req.headers[k]=v;
        }
    }
    return true;
}
static void http_write(SOCKET s, const std::string& status, const std::string& body, const std::string& ctype="application/json") {
    std::ostringstream oss;
    oss << "HTTP/1.1 " << status << "\r\n";
    oss << "Content-Type: " << ctype << "\r\n";
    oss << "Content-Length: " << body.size() << "\r\n";
    oss << "Connection: close\r\n\r\n";
    auto head = oss.str();
    send(s, head.c_str(), (int)head.size(), 0);
    if (!body.empty()) send(s, body.c_str(), (int)body.size(), 0);
}

static std::string getenv_str(const char* k) {
    const char* v = std::getenv(k);
    return v? std::string(v) : std::string();
}

// Compose headers JSON with optional signature.
static std::string make_headers_payload(const std::string& target, long long ts, const std::string& method, const std::string& path, const std::string& secret) {
    std::string auth;
    if (target=="make")      auth = getenv_str("MAKE_API_TOKEN");
    else if (target=="airtable") auth = getenv_str("AIRTABLE_API_KEY");
    else if (target=="mistral")  auth = getenv_str("MISTRAL_API_KEY");

    std::ostringstream headers;
    headers << "{ \"headers\":{";

    bool first=true;
    if (!auth.empty()) {
        headers << "\"Authorization\":" << json_escape(std::string("Bearer ")+auth);
        first=false;
    }

    std::string sig;
    if (!secret.empty()) {
        std::ostringstream msg;
        msg << ts << "::" << method << "::" << path << "::" << target;
        auto mac = hmac_sha256(secret, msg.str());
        sig = base64url(mac);
        if (!first) headers << ",";
        headers << "\"X-Signature\":" << json_escape(sig) << ",\"X-Timestamp\":" << json_escape(std::to_string(ts));
        first=false;
    }

    headers << "} }";
    return headers.str();
}

static void handle_client(SOCKET cs) {
    Request req;
    if (!read_request(cs, req)) { closesocket(cs); return; }

    // Only allow localhost (this is ensured by bind), but keep API key check:
    std::string need_key = getenv_str("TOKEN_PROXY_KEY");
    if (need_key.empty()) {
        // fail closed
        std::string body = "{ \"error\":\"server not configured (TOKEN_PROXY_KEY missing)\" }";
        http_write(cs, "503 Service Unavailable", body);
        closesocket(cs);
        return;
    }
    auto it = req.headers.find("x-proxy-key");
    if (it==req.headers.end() || it->second != need_key) {
        std::string body = "{ \"error\":\"unauthorized\" }";
        http_write(cs, "401 Unauthorized", body);
        closesocket(cs);
        return;
    }

    // Routes
    if (req.method=="GET" && req.path=="/health") {
        std::ostringstream body;
        body << "{ \"status\":\"ok\", \"ts\":" << epoch_sec() << " }";
        http_write(cs, "200 OK", body.str());
        closesocket(cs);
        return;
    }

    if (req.method=="GET" && req.path=="/v1/headers") {
        auto q = parse_query(req.query);
        std::string target = "make";
        auto itq = q.find("target");
        if (itq!=q.end() && !itq->second.empty()) target = tolower_str(itq->second);
        long long ts = epoch_sec();
        std::string secret = getenv_str("MAKE_HMAC_SECRET");
        std::string body = make_headers_payload(target, ts, req.method, req.path, secret);
        http_write(cs, "200 OK", body);
        closesocket(cs);
        return;
    }

    if (req.method=="GET" && req.path=="/v1/sign") {
        auto q = parse_query(req.query);
        std::string payload = "";
        auto itp = q.find("payload");
        if (itp!=q.end()) payload = itp->second;

        std::string secret = getenv_str("MAKE_HMAC_SECRET");
        if (secret.empty()) {
            http_write(cs, "400 Bad Request", "{ \"error\":\"MAKE_HMAC_SECRET missing\" }");
            closesocket(cs);
            return;
        }
        long long ts = epoch_sec();
        std::ostringstream msg; msg << ts << "::" << payload;
        auto mac = hmac_sha256(secret, msg.str());
        std::string sig = base64url(mac);
        std::ostringstream out;
        out << "{ \"alg\":\"HS256\", \"sig\":" << json_escape(sig) << ", \"ts\":" << json_escape(std::to_string(ts)) << " }";
        http_write(cs, "200 OK", out.str());
        closesocket(cs);
        return;
    }

    // Not found
    http_write(cs, "404 Not Found", "{ \"error\":\"not found\" }");
    closesocket(cs);
}

int main() {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2,2), &wsa)!=0) {
        return 1;
    }

    std::string portStr = getenv_str("TOKEN_PROXY_PORT");
    int port = portStr.empty()? 7071 : std::stoi(portStr);

    SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (s==INVALID_SOCKET) { WSACleanup(); return 1; }

    BOOL yes = 1;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (const char*)&yes, sizeof(yes));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons((u_short)port);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (bind(s, (sockaddr*)&addr, sizeof(addr))==SOCKET_ERROR) {
        closesocket(s); WSACleanup(); return 1;
    }
    if (listen(s, SOMAXCONN)==SOCKET_ERROR) {
        closesocket(s); WSACleanup(); return 1;
    }

    // Basic accept loop, thread-per-connection
    for (;;) {
        SOCKET cs = accept(s, nullptr, nullptr);
        if (cs==INVALID_SOCKET) break;
        std::thread t(handle_client, cs);
        t.detach();
    }

    closesocket(s);
    WSACleanup();
    return 0;
}
