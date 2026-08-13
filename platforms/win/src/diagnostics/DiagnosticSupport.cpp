#include "diagnostics/DiagnosticSupport.h"

#include <commdlg.h>
#include <shlobj.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cwchar>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace xxsnap::win {
namespace {

constexpr std::size_t maximumLogFileSize = 5U * 1024U * 1024U;
constexpr std::size_t maximumLogFileCount = 5U;

std::wstring defaultLogDirectory() noexcept
{
    std::array<wchar_t, MAX_PATH> path{};
    if (FAILED(SHGetFolderPathW(nullptr, CSIDL_LOCAL_APPDATA | CSIDL_FLAG_CREATE,
            nullptr, SHGFP_TYPE_CURRENT, path.data()))) {
        return {};
    }
    return std::wstring(path.data()) + L"\\XxSnap\\Logs";
}

void ensureDirectory(const std::wstring& directory) noexcept
{
    const auto separator = directory.find_last_of(L"\\/");
    if (separator != std::wstring::npos) {
        CreateDirectoryW(directory.substr(0, separator).c_str(), nullptr);
    }
    CreateDirectoryW(directory.c_str(), nullptr);
}

std::string jsonEscaped(const char* value)
{
    std::string result;
    if (value == nullptr) return result;
    for (const auto* current = value; *current != '\0'; ++current) {
        const auto byte = static_cast<unsigned char>(*current);
        if (byte == '"' || byte == '\\') result.push_back('\\');
        if (byte >= 0x20U) result.push_back(static_cast<char>(byte));
    }
    return result;
}

std::string isoTimestamp(const SYSTEMTIME& time)
{
    std::array<char, 32> value{};
    std::snprintf(value.data(), value.size(),
        "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
        time.wYear, time.wMonth, time.wDay,
        time.wHour, time.wMinute, time.wSecond, time.wMilliseconds);
    return value.data();
}

bool appendFile(const std::wstring& path, const std::string& data) noexcept
{
    const auto file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
        FILE_SHARE_READ, nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    const auto succeeded = data.size() <= std::numeric_limits<DWORD>::max()
        && WriteFile(file, data.data(), static_cast<DWORD>(data.size()),
            &written, nullptr) != FALSE
        && written == data.size();
    CloseHandle(file);
    return succeeded;
}

std::uint64_t fileSize(const std::wstring& path) noexcept
{
    WIN32_FILE_ATTRIBUTE_DATA data{};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) {
        return 0U;
    }
    return (static_cast<std::uint64_t>(data.nFileSizeHigh) << 32U)
        | data.nFileSizeLow;
}

bool safeLogName(const wchar_t* name) noexcept
{
    if (name == nullptr) return false;
    const std::wstring value{name};
    if (value.size() <= 6U || value.size() > 180U
        || value.substr(value.size() - 6U) != L".jsonl") {
        return false;
    }
    return std::all_of(value.begin(), value.end() - 6,
        [](wchar_t character) {
            return (character >= L'a' && character <= L'z')
                || (character >= L'A' && character <= L'Z')
                || (character >= L'0' && character <= L'9')
                || character == L'-' || character == L'_';
        });
}

std::vector<unsigned char> readBounded(
    const std::wstring& path, std::size_t limit) noexcept
{
    const auto file = CreateFileW(path.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr);
    if (file == INVALID_HANDLE_VALUE) return {};
    BY_HANDLE_FILE_INFORMATION information{};
    if (!GetFileInformationByHandle(file, &information)
        || (information.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY
            | FILE_ATTRIBUTE_REPARSE_POINT)) != 0U
        || information.nNumberOfLinks != 1U) {
        CloseHandle(file);
        return {};
    }
    const auto size = (static_cast<std::uint64_t>(information.nFileSizeHigh) << 32U)
        | information.nFileSizeLow;
    if (size > limit || size > std::numeric_limits<DWORD>::max()) {
        CloseHandle(file);
        return {};
    }
    std::vector<unsigned char> result(static_cast<std::size_t>(size));
    DWORD read = 0;
    const auto succeeded = result.empty()
        || (ReadFile(file, result.data(), static_cast<DWORD>(result.size()),
                &read, nullptr) != FALSE && read == result.size());
    CloseHandle(file);
    if (!succeeded) result.clear();
    return result;
}

std::string executableVersion()
{
    std::array<wchar_t, MAX_PATH> path{};
    if (GetModuleFileNameW(nullptr, path.data(),
            static_cast<DWORD>(path.size())) == 0U) return "0.0.0";
    DWORD ignored = 0;
    const auto size = GetFileVersionInfoSizeW(path.data(), &ignored);
    if (size == 0U) return "0.0.0";
    std::vector<unsigned char> data(size);
    VS_FIXEDFILEINFO* information = nullptr;
    UINT informationSize = 0;
    if (!GetFileVersionInfoW(path.data(), 0, size, data.data())
        || !VerQueryValueW(data.data(), L"\\",
            reinterpret_cast<void**>(&information), &informationSize)
        || information == nullptr || informationSize < sizeof(*information)) {
        return "0.0.0";
    }
    std::array<char, 48> version{};
    std::snprintf(version.data(), version.size(), "%u.%u.%u",
        HIWORD(information->dwFileVersionMS), LOWORD(information->dwFileVersionMS),
        HIWORD(information->dwFileVersionLS));
    return version.data();
}

std::string architecture()
{
#if defined(_M_X64)
    return "x86_64";
#elif defined(_M_IX86)
    return "x86";
#else
    return "unknown";
#endif
}

std::string windowsVersion()
{
    using RtlGetVersionFn = LONG(WINAPI*)(OSVERSIONINFOW*);
    const auto module = GetModuleHandleW(L"ntdll.dll");
    const auto function = module == nullptr ? nullptr
        : reinterpret_cast<RtlGetVersionFn>(GetProcAddress(module, "RtlGetVersion"));
    OSVERSIONINFOW value{};
    value.dwOSVersionInfoSize = sizeof(value);
    if (function == nullptr || function(&value) != 0) return "unknown";
    std::array<char, 64> result{};
    std::snprintf(result.data(), result.size(), "%lu.%lu.%lu",
        value.dwMajorVersion, value.dwMinorVersion, value.dwBuildNumber);
    return result.data();
}

std::uint32_t crc32(const std::vector<unsigned char>& bytes) noexcept
{
    std::uint32_t crc = 0xFFFFFFFFU;
    for (const auto byte : bytes) {
        crc ^= byte;
        for (int bit = 0; bit < 8; ++bit) {
            crc = (crc >> 1U) ^ (0xEDB88320U &
                (0U - static_cast<std::uint32_t>(crc & 1U)));
        }
    }
    return ~crc;
}

void append16(std::vector<unsigned char>& output, std::uint16_t value)
{
    output.push_back(static_cast<unsigned char>(value));
    output.push_back(static_cast<unsigned char>(value >> 8U));
}

void append32(std::vector<unsigned char>& output, std::uint32_t value)
{
    append16(output, static_cast<std::uint16_t>(value));
    append16(output, static_cast<std::uint16_t>(value >> 16U));
}

struct ZipEntry final {
    std::string name;
    std::vector<unsigned char> contents;
    std::uint32_t crc = 0;
    std::uint32_t offset = 0;
};

bool writeZip(const std::wstring& destination,
    std::vector<ZipEntry> entries) noexcept
{
    std::vector<unsigned char> output;
    for (auto& entry : entries) {
        if (entry.name.size() > std::numeric_limits<std::uint16_t>::max()
            || entry.contents.size() > std::numeric_limits<std::uint32_t>::max()
            || output.size() > std::numeric_limits<std::uint32_t>::max()) {
            return false;
        }
        entry.crc = crc32(entry.contents);
        entry.offset = static_cast<std::uint32_t>(output.size());
        append32(output, 0x04034B50U);
        append16(output, 20U);
        append16(output, 0x0800U);
        append16(output, 0U);
        append16(output, 0U);
        append16(output, 0U);
        append32(output, entry.crc);
        append32(output, static_cast<std::uint32_t>(entry.contents.size()));
        append32(output, static_cast<std::uint32_t>(entry.contents.size()));
        append16(output, static_cast<std::uint16_t>(entry.name.size()));
        append16(output, 0U);
        output.insert(output.end(), entry.name.begin(), entry.name.end());
        output.insert(output.end(), entry.contents.begin(), entry.contents.end());
    }
    if (output.size() > std::numeric_limits<std::uint32_t>::max()) return false;
    const auto centralOffset = static_cast<std::uint32_t>(output.size());
    for (const auto& entry : entries) {
        append32(output, 0x02014B50U);
        append16(output, 20U);
        append16(output, 20U);
        append16(output, 0x0800U);
        append16(output, 0U);
        append16(output, 0U);
        append16(output, 0U);
        append32(output, entry.crc);
        append32(output, static_cast<std::uint32_t>(entry.contents.size()));
        append32(output, static_cast<std::uint32_t>(entry.contents.size()));
        append16(output, static_cast<std::uint16_t>(entry.name.size()));
        append16(output, 0U);
        append16(output, 0U);
        append16(output, 0U);
        append16(output, 0U);
        append32(output, 0U);
        append32(output, entry.offset);
        output.insert(output.end(), entry.name.begin(), entry.name.end());
    }
    const auto centralSize = static_cast<std::uint32_t>(output.size()) - centralOffset;
    append32(output, 0x06054B50U);
    append16(output, 0U);
    append16(output, 0U);
    append16(output, static_cast<std::uint16_t>(entries.size()));
    append16(output, static_cast<std::uint16_t>(entries.size()));
    append32(output, centralSize);
    append32(output, centralOffset);
    append16(output, 0U);

    const auto file = CreateFileW(destination.c_str(), GENERIC_WRITE, 0, nullptr,
        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    DWORD written = 0;
    const auto succeeded = output.size() <= std::numeric_limits<DWORD>::max()
        && WriteFile(file, output.data(), static_cast<DWORD>(output.size()),
            &written, nullptr) != FALSE && written == output.size()
        && FlushFileBuffers(file) != FALSE;
    CloseHandle(file);
    if (!succeeded) DeleteFileW(destination.c_str());
    return succeeded;
}

} // namespace

DiagnosticLogStore::DiagnosticLogStore(std::wstring directory) noexcept
    : directory_(directory.empty() ? defaultLogDirectory() : std::move(directory))
{
    maintain();
}

void DiagnosticLogStore::record(const char* category, const char* level,
    const char* event) noexcept
{
    if (directory_.empty()) return;
    maintain();
    SYSTEMTIME time{};
    GetSystemTime(&time);
    const auto line = std::string{"{\"schemaVersion\":1,\"timestamp\":\""}
        + isoTimestamp(time) + "\",\"category\":\"" + jsonEscaped(category)
        + "\",\"level\":\"" + jsonEscaped(level) + "\",\"event\":\""
        + jsonEscaped(event) + "\",\"metadata\":{}}\n";
    const auto current = directory_ + L"\\xxsnap-current.jsonl";
    if (fileSize(current) + line.size() > maximumLogFileSize) {
        std::array<wchar_t, 96> rotated{};
        std::swprintf(rotated.data(), rotated.size(),
            L"\\xxsnap-%04u%02u%02u-%02u%02u%02u-%03u.jsonl",
            time.wYear, time.wMonth, time.wDay, time.wHour, time.wMinute,
            time.wSecond, time.wMilliseconds);
        MoveFileExW(current.c_str(), (directory_ + rotated.data()).c_str(),
            MOVEFILE_REPLACE_EXISTING);
    }
    appendFile(current, line);
    maintain();
}

const std::wstring& DiagnosticLogStore::directory() const noexcept
{
    return directory_;
}

std::vector<std::wstring> DiagnosticLogStore::logFiles() const noexcept
{
    std::vector<std::wstring> result;
    if (directory_.empty()) return result;
    WIN32_FIND_DATAW data{};
    const auto search = FindFirstFileW((directory_ + L"\\*.jsonl").c_str(), &data);
    if (search == INVALID_HANDLE_VALUE) return result;
    do {
        if ((data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0U
            && safeLogName(data.cFileName)) {
            result.push_back(directory_ + L"\\" + data.cFileName);
        }
    } while (FindNextFileW(search, &data));
    FindClose(search);
    std::sort(result.begin(), result.end());
    return result;
}

void DiagnosticLogStore::maintain() const noexcept
{
    if (directory_.empty()) return;
    ensureDirectory(directory_);
    auto files = logFiles();
    while (files.size() > maximumLogFileCount) {
        DeleteFileW(files.front().c_str());
        files.erase(files.begin());
    }
}

DiagnosticBundleExporter::DiagnosticBundleExporter(
    DiagnosticLogStore& store, DiagnosticBundleLimits limits) noexcept
    : store_(store), limits_(limits)
{
}

bool DiagnosticBundleExporter::exportTo(
    const std::wstring& destination) noexcept
{
    store_.record("export", "info", "diagnostic_export_started");
    SYSTEMTIME time{};
    GetSystemTime(&time);
    auto files = store_.logFiles();
    if (files.size() > limits_.maximumFileCount) {
        files.erase(files.begin(), files.end()
            - static_cast<std::ptrdiff_t>(limits_.maximumFileCount));
    }
    std::vector<ZipEntry> entries;
    std::size_t totalBytes = 0U;
    for (const auto& file : files) {
        if (totalBytes >= limits_.maximumTotalBytes) break;
        const auto remaining = limits_.maximumTotalBytes - totalBytes;
        const auto bytes = readBounded(file,
            (std::min)(limits_.maximumFileBytes, remaining));
        if (bytes.empty() && fileSize(file) != 0U) continue;
        totalBytes += bytes.size();
        entries.push_back(ZipEntry{
            "logs/diagnostic-log-" + std::to_string(entries.size() + 1U)
                + ".jsonl",
            bytes});
    }
    const auto manifest = std::string{"{\n  \"schemaVersion\": 1,\n"}
        + "  \"generatedAt\": \"" + isoTimestamp(time) + "\",\n"
        + "  \"appVersion\": \"" + executableVersion() + "\",\n"
        + "  \"windowsVersion\": \"" + windowsVersion() + "\",\n"
        + "  \"architecture\": \"" + architecture() + "\",\n"
        + "  \"logFileCount\": " + std::to_string(entries.size()) + "\n}\n";
    entries.insert(entries.begin(), ZipEntry{"manifest.json",
        std::vector<unsigned char>(manifest.begin(), manifest.end())});
    const auto succeeded = writeZip(destination, std::move(entries));
    store_.record("export", succeeded ? "info" : "error",
        succeeded ? "diagnostic_export_completed" : "diagnostic_export_failed");
    return succeeded;
}

std::wstring DiagnosticBundleExporter::suggestedArchiveName(
    const SYSTEMTIME& time)
{
    std::array<wchar_t, 64> value{};
    std::swprintf(value.data(), value.size(),
        L"XxSnap-Diagnostics-%04u%02u%02u-%02u%02u%02u.zip",
        time.wYear, time.wMonth, time.wDay,
        time.wHour, time.wMinute, time.wSecond);
    return value.data();
}

DiagnosticSupportController::DiagnosticSupportController(
    HWND owner, DiagnosticLogStore& store) noexcept
    : owner_(owner), store_(store)
{
}

void DiagnosticSupportController::exportDiagnostics() noexcept
{
    SYSTEMTIME time{};
    GetLocalTime(&time);
    auto path = DiagnosticBundleExporter::suggestedArchiveName(time);
    path.resize(1024U, L'\0');
    OPENFILENAMEW dialog{};
    dialog.lStructSize = sizeof(dialog);
    dialog.hwndOwner = owner_;
    dialog.lpstrFilter = L"ZIP 压缩包 (*.zip)\0*.zip\0\0";
    dialog.lpstrFile = path.data();
    dialog.nMaxFile = static_cast<DWORD>(path.size());
    dialog.lpstrDefExt = L"zip";
    dialog.lpstrTitle = L"导出诊断日志";
    dialog.Flags = OFN_NOCHANGEDIR | OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
    if (!GetSaveFileNameW(&dialog)) return;
    path.resize(std::wcslen(path.c_str()));
    DiagnosticBundleExporter exporter(store_);
    const auto succeeded = exporter.exportTo(path);
    MessageBoxW(owner_, succeeded
            ? L"诊断压缩包已生成，可以发送给技术支持。"
            : L"诊断日志导出失败，请重试。",
        succeeded ? L"诊断日志已导出" : L"无法导出诊断日志",
        MB_OK | (succeeded ? MB_ICONINFORMATION : MB_ICONERROR)
            | MB_SETFOREGROUND);
}

} // namespace xxsnap::win
