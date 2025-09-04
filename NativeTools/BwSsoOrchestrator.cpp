// BwSsoOrchestrator.cpp
// Automatiserer Bitwarden SSO-innlogging og henter Mistral API-nøkkel til MISTRAL_API_KEY.
// For Windows. Bygg med MSVC: cl /EHsc BwSsoOrchestrator.cpp /link User32.lib
// Avhengigheter: Bitwarden CLI ("bw") installert og tilgjengelig i PATH.
//
// Flyt:
// 1) Sjekk bw tilstede og status (authenticated/unlocked)
// 2) Hvis ikke authenticated: bw login --sso --raw (åpner nettleser og returnerer BW_SESSION)
// 3) Hvis ikke unlocked: be bruker låse opp i eget konsollvindu, poller status til unlocked
// 4) Hent passordfeltet fra element "Mistral API Key" (kan overstyres med --item)
// 5) Sett MISTRAL_API_KEY (bruker-omfang), skriv sikker lokal fil og logg
//
// Merk: Dette verktøyet unngår JSON-parsing ved å bruke "bw get password <search>".

#include <windows.h>
#include <shlwapi.h>
#include <shlobj.h>
#include <string>
#include <vector>
#include <iostream>
#include <sstream>
#include <fstream>
#include <ctime>

#pragma comment(lib, "Shlwapi.lib")
#pragma comment(lib, "User32.lib")
#pragma comment(lib, "Shell32.lib")

namespace {

std::wstring nowStamp() {
    SYSTEMTIME st{};
    GetLocalTime(&st);
    wchar_t buf[64]{};
    swprintf_s(buf, L"%04d%02d%02d_%02d%02d%02d",
               st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
    return buf;
}

std::wstring getLocalAppData() {
    wchar_t path[MAX_PATH]{};
    if (SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA, nullptr, SHGFP_TYPE_CURRENT, path) == S_OK) {
        return path;
    }
    // Fallback til %USERPROFILE%\AppData\Local
    wchar_t profile[MAX_PATH]{};
    DWORD n = GetEnvironmentVariableW(L"USERPROFILE", profile, MAX_PATH);
    if (n > 0 && n < MAX_PATH) {
        std::wstring p(profile);
        if (!p.empty() && p.back() != L'\\') p += L'\\';
        p += L"AppData\\Local";
        return p;
    }
    return L".";
}

std::wstring ensureDir(const std::wstring& base, const std::wstring& rel) {
    std::wstring full = base;
    if (!full.empty() && full.back() != L'\\') full += L'\\';
    full += rel;
    // Lag alle mellomliggende mapper
    std::wstring acc;
    for (wchar_t ch : full) {
        acc.push_back(ch);
        if (ch == L'\\' || ch == L'/') {
            CreateDirectoryW(acc.c_str(), nullptr);
        }
    }
    CreateDirectoryW(full.c_str(), nullptr);
    return full;
}

struct RunResult {
    int exitCode = -1;
    std::string stdoutText;
};

RunResult runCommandCapture(const std::wstring& cmdLine, DWORD creationFlags = 0, bool newConsole = false) {
    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE hRead = nullptr, hWrite = nullptr;
    CreatePipe(&hRead, &hWrite, &sa, 0);
    SetHandleInformation(hRead, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.hStdError = hWrite;
    si.hStdOutput = hWrite;
    si.dwFlags |= STARTF_USESTDHANDLES;

    PROCESS_INFORMATION pi{};
    std::wstring cmd = L"cmd.exe /C " + cmdLine;

    DWORD flags = creationFlags;
    if (newConsole) flags |= CREATE_NEW_CONSOLE;

    // CreateProcessW krever non-const LPWSTR for cmdLine
    std::vector<wchar_t> cmdBuffer(cmd.begin(), cmd.end());
    cmdBuffer.push_back(L'\0');

    BOOL ok = CreateProcessW(
        nullptr,
        cmdBuffer.data(),
        nullptr,
        nullptr,
        TRUE,
        flags,
        nullptr,
        nullptr,
        &si,
        &pi
    );

    CloseHandle(hWrite);

    RunResult rr{};
    if (!ok) {
        rr.exitCode = (int)GetLastError();
        CloseHandle(hRead);
        return rr;
    }

    // Les stdout/stderr
    std::string buffer;
    const DWORD BUFSZ = 8192;
    char tmp[BUFSZ];
    DWORD read = 0;
    while (ReadFile(hRead, tmp, BUFSZ, &read, nullptr) && read > 0) {
        buffer.append(tmp, tmp + read);
    }
    rr.stdoutText = buffer;

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    rr.exitCode = (int)code;

    CloseHandle(hRead);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return rr;
}

void writeLog(const std::wstring& msg) {
    static std::wofstream logFile;
    static bool init = false;
    if (!init) {
        init = true;
        std::wstring base = getLocalAppData();
        std::wstring logDir = ensureDir(base, L"MistralSuite\\logs");
        std::wstring path = logDir + L"\\orchestrator-" + nowStamp() + L".log";
        logFile.open(path, std::ios::out | std::ios::app);
    }
    if (logFile.is_open()) {
        logFile << msg << std::endl;
    }
}

void broadcastEnvChange() {
    SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0, (LPARAM)L"Environment",
                        SMTO_ABORTIFHUNG, 5000, nullptr);
}

bool setUserEnvVar(const std::wstring& name, const std::wstring& value) {
    // Sett i gjeldende prosess
    SetEnvironmentVariableW(name.c_str(), value.c_str());

    // Vedvar i HKCU\Environment
    HKEY hKey = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Environment", 0, KEY_SET_VALUE, &hKey) != ERROR_SUCCESS) {
        return false;
    }
    LONG r = RegSetValueExW(hKey, name.c_str(), 0, REG_EXPAND_SZ,
                            reinterpret_cast<const BYTE*>(value.c_str()),
                            DWORD((value.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(hKey);
    if (r == ERROR_SUCCESS) {
        broadcastEnvChange();
        return true;
    }
    return false;
}

bool fileWriteAllText(const std::wstring& path, const std::string& data) {
    std::ofstream f(path, std::ios::out | std::ios::binary | std::ios::trunc);
    if (!f.is_open()) return false;
    f.write(data.data(), (std::streamsize)data.size());
    f.close();
    return true;
}

bool ensureBwPresent() {
    auto res = runCommandCapture(L"bw --version");
    writeLog(L"bw --version exit=" + std::to_wstring(res.exitCode) + L" out=" + std::wstring(res.stdoutText.begin(), res.stdoutText.end()));
    return res.exitCode == 0;
}

struct BwStatus {
    bool authenticated = false;
    bool unlocked = false;
};

BwStatus getBwStatus() {
    BwStatus st{};
    auto res = runCommandCapture(L"bw status --raw");
    std::string s = res.stdoutText;
    // Enkelt søk (unngå full JSON-parsing)
    if (s.find("\"authenticated\": true") != std::string::npos) st.authenticated = true;
    if (s.find("\"unlocked\": true") != std::string::npos) st.unlocked = true;
    writeLog(L"bw status -> auth=" + std::to_wstring(st.authenticated) + L" unlocked=" + std::to_wstring(st.unlocked));
    return st;
}

std::wstring trim(const std::wstring& in) {
    size_t start = 0, end = in.size();
    while (start < end && iswspace(in[start])) ++start;
    while (end > start && iswspace(in[end - 1])) --end;
    return in.substr(start, end - start);
}

bool tryBwLoginSso(std::wstring& outSession) {
    // --raw gir BW_SESSION på stdout
    auto res = runCommandCapture(L"bw login --sso --raw");
    if (res.exitCode == 0) {
        std::wstring session(res.stdoutText.begin(), res.stdoutText.end());
        outSession = trim(session);
        if (!outSession.empty()) {
            SetEnvironmentVariableW(L"BW_SESSION", outSession.c_str());
            writeLog(L"bw login --sso OK. BW_SESSION mottatt.");
            return true;
        }
    }
    writeLog(L"bw login --sso feilet eller ga ingen session. exit=" + std::to_wstring(res.exitCode));
    return false;
}

bool ensureUnlockedInteractive() {
    BwStatus st = getBwStatus();
    if (st.unlocked) return true;

    writeLog(L"Starter interaktiv 'bw unlock' i nytt konsollvindu.");
    // Åpne nytt konsollvindu hvor bruker kan skrive master passord/PIN.
    // Bruk "start" for å holde vinduet åpent om nødvendig.
    runCommandCapture(L"start \"Bitwarden Unlock\" cmd /k bw unlock", 0, true);

    // Poll status i opptil 5 minutter
    const int maxTries = 60; // 60 * 5s = 300s
    for (int i = 0; i < maxTries; ++i) {
        Sleep(5000);
        BwStatus s = getBwStatus();
        if (s.unlocked) {
            writeLog(L"Bitwarden er nå unlocked.");
            return true;
        }
    }
    writeLog(L"Timeout: Bitwarden ble ikke unlocked innen tidsfrist.");
    return false;
}

bool tryFetchMistralKey(const std::wstring& itemName, std::string& outKey) {
    std::wstring cmd = L"bw get password \"" + itemName + L"\"";
    auto res = runCommandCapture(cmd);
    if (res.exitCode == 0) {
        std::string key = res.stdoutText;
        // Trim CRLF
        while (!key.empty() && (key.back() == '\r' || key.back() == '\n')) key.pop_back();
        outKey = key;
        return !outKey.empty();
    }
    // Fall-back: forsøk alternativt søk uten anførselstegn
    auto res2 = runCommandCapture(L"bw get password " + itemName);
    if (res2.exitCode == 0) {
        std::string key = res2.stdoutText;
        while (!key.empty() && (key.back() == '\r' || key.back() == '\n')) key.pop_back();
        outKey = key;
        return !outKey.empty();
    }
    return false;
}

} // namespace

int wmain(int argc, wchar_t* argv[]) {
    std::wstring desiredItem = L"Mistral API Key"; // kan overstyres med --item "Navn"
    for (int i = 1; i < argc; ++i) {
        std::wstring a = argv[i];
        if ((a == L"--item" || a == L"-i") && i + 1 < argc) {
            desiredItem = argv[++i];
        }
    }

    std::wcout << L"[Orchestrator] Starter..." << std::endl;
    writeLog(L"Orchestrator start. Item=" + desiredItem);

    if (!ensureBwPresent()) {
        std::wcerr << L"Bitwarden CLI (bw) ikke funnet i PATH. Installer Bitwarden CLI og prøv igjen." << std::endl;
        writeLog(L"bw ikke funnet.");
        return 2;
    }

    BwStatus status = getBwStatus();

    if (!status.authenticated) {
        std::wcout << L"[Orchestrator] Ikke autentisert mot Bitwarden. Starter SSO..." << std::endl;
        std::wstring session;
        if (!tryBwLoginSso(session)) {
            std::wcerr << L"SSO-innlogging mislyktes. Prøv å kjøre 'bw login --sso' manuelt og forsøk igjen." << std::endl;
            return 3;
        }
        // Oppdater status
        status = getBwStatus();
    }

    if (!status.unlocked) {
        std::wcout << L"[Orchestrator] Hvelvet er låst. Et nytt konsollvindu åpnes for 'bw unlock'." << std::endl;
        std::wcout << L"Fullfør opplåsing der, dette vinduet venter inntil 5 minutter..." << std::endl;
        if (!ensureUnlockedInteractive()) {
            std::wcerr << L"Kunne ikke bekrefte at hvelvet ble låst opp. Avbryter." << std::endl;
            return 4;
        }
    }

    std::wcout << L"[Orchestrator] Henter Mistral API-nøkkel fra Bitwarden element: " << desiredItem << std::endl;
    std::string apiKey;
    if (!tryFetchMistralKey(desiredItem, apiKey)) {
        std::wcerr << L"Fant ikke Mistral API-nøkkel. Kontroller at elementet \"" << desiredItem
                   << L"\" eksisterer og at passordfeltet inneholder API-nøkkelen." << std::endl;
        writeLog(L"Kunne ikke hente API-nøkkel.");
        return 5;
    }

    // Lagre som bruker-miljøvariabel
    std::wstring wKey(apiKey.begin(), apiKey.end());
    if (setUserEnvVar(L"MISTRAL_API_KEY", wKey)) {
        std::wcout << L"[Orchestrator] Satt bruker-miljøvariabel MISTRAL_API_KEY." << std::endl;
        writeLog(L"MISTRAL_API_KEY satt i HKCU\\Environment og prosess.");
    } else {
        std::wcerr << L"Advarsel: Klarte ikke å persistere MISTRAL_API_KEY i brukeromgivelsene." << std::endl;
        writeLog(L"Feil ved setting av HKCU\\Environment.");
    }

    // Skriv sikker lokal fil
    std::wstring base = getLocalAppData();
    std::wstring secDir = ensureDir(base, L"MistralSuite\\secrets");
    std::wstring secPath = secDir + L"\\mistral.key";
    if (fileWriteAllText(secPath, apiKey)) {
        SetFileAttributesW(secPath.c_str(), FILE_ATTRIBUTE_HIDDEN);
        std::wcout << L"[Orchestrator] Skrev nøkkel til " << secPath << L" (skjult fil)." << std::endl;
        writeLog(L"Nøkkel skrevet til: " + secPath);
    } else {
        std::wcerr << L"Advarsel: Klarte ikke å skrive nøkkelfilen til " << secPath << std::endl;
        writeLog(L"Feil ved skriving av nøkkelfil.");
    }

    std::wcout << L"[Orchestrator] Ferdig. Start/omstart Mistral-appen for å ta i bruk nøkkelen." << std::endl;
    writeLog(L"Orchestrator ferdig.");
    return 0;
}
