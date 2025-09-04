// BwServiceLogin.cpp
// Headless Bitwarden-CLI innlogging for CI/CD med service-konto (apikey) og valgfri henting av passord.
// Bygg (Windows, MSVC): cl /EHsc BwServiceLogin.cpp
// Bygg (Linux/macOS): g++ -std=c++17 BwServiceLogin.cpp -o BwServiceLogin
//
// Forutsetninger:
//   - Bitwarden CLI ("bw") i PATH
//   - Miljøvariabler i pipeline:
//       BW_CLIENTID, BW_CLIENTSECRET  (service-konto / Secrets Manager API key-par)
//       BW_PASSWORD (valgfri; masterpassord for brukerhvelv når du trenger "unlock" i ikke-interaktivt miljø)
//       BW_HOST (valgfri; f.eks. https://vault.bitwarden.com eller selvhost)
//
// Bruk:
//   1) Kun autentisere og skrive BW_SESSION til stdout (rå):
//        BwServiceLogin --print-session
//      (Returnerer kun token-linjen; egnet for `export BW_SESSION=$(...)` i shell.)
//   2) Hent passord for et element (krever unlock):
//        BwServiceLogin --get-password "Mistral API Key"
//      (Skriver passordet til stdout, ingen ekstra tekst.)
//
// Merk:
//   - Programmet skriver kun resultater til stdout (token/passord). Feil går til stderr.

#include <cstdlib>
#include <cstdio>
#include <iostream>
#include <string>
#include <vector>
#include <array>
#include <stdexcept>
#include <algorithm>

#if defined(_WIN32)
#include <windows.h>
#endif

static std::string trim(const std::string& s) {
    size_t b = 0, e = s.size();
    while (b < e && (s[b] == ' ' || s[b] == '\t' || s[b] == '\r' || s[b] == '\n')) ++b;
    while (e > b && (s[e - 1] == ' ' || s[e - 1] == '\t' || s[e - 1] == '\r' || s[e - 1] == '\n')) --e;
    return s.substr(b, e - b);
}

static std::string run(const std::string& cmd, int* exitCode = nullptr) {
#if defined(_WIN32)
    std::string full = cmd + " 2>&1";
    FILE* pipe = _popen(full.c_str(), "r");
#else
    std::string full = cmd + " 2>&1";
    FILE* pipe = popen(full.c_str(), "r");
#endif
    if (!pipe) throw std::runtime_error("Kunne ikke starte kommando: " + cmd);

    std::string out;
    std::array<char, 4096> buf{};
    while (fgets(buf.data(), (int)buf.size(), pipe)) {
        out.append(buf.data());
    }
#if defined(_WIN32)
    int rc = _pclose(pipe);
#else
    int rc = pclose(pipe);
#endif
    if (exitCode) *exitCode = rc;
    return out;
}

static void setEnvLocal(const std::string& k, const std::string& v) {
#if defined(_WIN32)
    _putenv_s(k.c_str(), v.c_str());
#else
    setenv(k.c_str(), v.c_str(), 1);
#endif
}

struct Options {
    bool printSession = false;
    bool wantPassword = false;
    std::string passwordQuery; // item id/label
    std::string host;
};

static void printUsage() {
    std::cerr
        << "Bruk:\n"
        << "  BwServiceLogin --print-session [--host <url>]\n"
        << "  BwServiceLogin --get-password <item> [--host <url>]\n"
        << "Miljo:\n"
        << "  BW_CLIENTID, BW_CLIENTSECRET  (paakrevd)\n"
        << "  BW_PASSWORD (valgfri for ikke-interaktiv unlock)\n"
        << "  BW_HOST (valgfri)\n";
}

static bool parseArgs(int argc, char** argv, Options& opt) {
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        if (a == "--print-session") {
            opt.printSession = true;
        } else if (a == "--get-password") {
            if (i + 1 >= argc) return false;
            opt.wantPassword = true;
            opt.passwordQuery = argv[++i];
        } else if (a == "--host") {
            if (i + 1 >= argc) return false;
            opt.host = argv[++i];
        } else if (a == "--help" || a == "-h") {
            return false;
        } else {
            // ukjent flagg -> feil
            return false;
        }
    }
    if (!opt.printSession && !opt.wantPassword) {
        // Default til print-session for enkel bruk i CI
        opt.printSession = true;
    }
    return true;
}

int main(int argc, char** argv) {
    Options opt{};
    if (!parseArgs(argc, argv, opt)) {
        printUsage();
        return 2;
    }

    const char* cid = std::getenv("BW_CLIENTID");
    const char* csec = std::getenv("BW_CLIENTSECRET");
    if (!cid || !csec || std::string(cid).empty() || std::string(csec).empty()) {
        std::cerr << "Feil: BW_CLIENTID/BW_CLIENTSECRET mangler.\n";
        return 2;
    }
    if (!opt.host.empty()) {
        setEnvLocal("BW_HOST", opt.host);
    }

    // Beste innsats: logg ut stille hvis allerede logget inn
    try { run("bw logout"); } catch (...) {}

    // Login --apikey leser BW_CLIENTID/BW_CLIENTSECRET fra miljø
    int rc = 0;
    std::string out = run("bw login --apikey", &rc);
    if (rc != 0) {
        std::cerr << "Innlogging feilet (bw login --apikey). Output:\n" << out;
        return 1;
    }

    // Unlock for tilgang til hvelv (noedvendig for get password)
    // Bruk BW_PASSWORD fra miljø hvis satt i CI for ikke-interaktiv mode.
    bool haveBWPass = (std::getenv("BW_PASSWORD") != nullptr) && std::string(std::getenv("BW_PASSWORD")).size() > 0;
    std::string unlockCmd = "bw unlock --raw";
    if (haveBWPass) {
        unlockCmd += " --passwordenv BW_PASSWORD";
    }

    out = run(unlockCmd, &rc);
    if (rc != 0) {
        std::cerr << "Unlock feilet. Output:\n" << out;
        return 1;
    }
    std::string session = trim(out);
    if (session.empty()) {
        std::cerr << "Unlock lyktes, men tom session mottatt.\n";
        return 1;
    }
    setEnvLocal("BW_SESSION", session);

    if (opt.printSession && !opt.wantPassword) {
        // Print bare token til stdout (ingen ekstra tekst)
        std::cout << session << std::endl;
        return 0;
    }

    if (opt.wantPassword) {
        // Hent passord for gitt item-id/navn
        std::string cmd = "bw get password \"" + opt.passwordQuery + "\"";
        out = run(cmd, &rc);
        if (rc != 0) {
            // Fall-back uten anfoerselstegn
            cmd = "bw get password " + opt.passwordQuery;
            out = run(cmd, &rc);
            if (rc != 0) {
                std::cerr << "bw get password feilet. Output:\n" << out;
                return 1;
            }
        }
        std::cout << trim(out) << std::endl;
        return 0;
    }

    // Skulle ikke na hit
    return 0;
}
