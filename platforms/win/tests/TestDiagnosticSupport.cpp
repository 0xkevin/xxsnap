#include "diagnostics/DiagnosticSupport.h"

#include <Windows.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

using namespace xxsnap::win;

namespace {

int failures = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            std::cerr << __FILE__ << ':' << __LINE__                           \
                      << ": CHECK failed: " #condition << '\n';                \
            ++failures;                                                        \
        }                                                                       \
    } while (false)

std::wstring makeTemporaryDirectory()
{
    std::array<wchar_t, MAX_PATH> root{};
    std::array<wchar_t, MAX_PATH> path{};
    CHECK(GetTempPathW(static_cast<DWORD>(root.size()), root.data()) != 0U);
    CHECK(GetTempFileNameW(root.data(), L"xxd", 0, path.data()) != 0U);
    DeleteFileW(path.data());
    CHECK(CreateDirectoryW(path.data(), nullptr) != FALSE);
    return path.data();
}

std::vector<unsigned char> readFile(const std::wstring& path)
{
    const auto file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ,
        nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    CHECK(file != INVALID_HANDLE_VALUE);
    if (file == INVALID_HANDLE_VALUE) return {};
    LARGE_INTEGER size{};
    CHECK(GetFileSizeEx(file, &size) != FALSE);
    std::vector<unsigned char> bytes(static_cast<std::size_t>(size.QuadPart));
    DWORD read = 0;
    CHECK(ReadFile(file, bytes.data(), static_cast<DWORD>(bytes.size()),
        &read, nullptr) != FALSE);
    CHECK(read == bytes.size());
    CloseHandle(file);
    return bytes;
}

bool contains(const std::vector<unsigned char>& bytes, const char* value)
{
    const std::string needle{value};
    return std::search(bytes.begin(), bytes.end(), needle.begin(), needle.end())
        != bytes.end();
}

void removeTemporaryDirectory(const std::wstring& directory)
{
    WIN32_FIND_DATAW data{};
    const auto search = FindFirstFileW((directory + L"\\*").c_str(), &data);
    if (search != INVALID_HANDLE_VALUE) {
        do {
            if (std::wcscmp(data.cFileName, L".") != 0
                && std::wcscmp(data.cFileName, L"..") != 0) {
                DeleteFileW((directory + L"\\" + data.cFileName).c_str());
            }
        } while (FindNextFileW(search, &data));
        FindClose(search);
    }
    RemoveDirectoryW(directory.c_str());
}

void testLogAndBundleContract()
{
    const auto directory = makeTemporaryDirectory();
    DiagnosticLogStore store(directory);
    store.record("application", "info", "application_launched");
    store.record("capture", "warning", "capture_failed");
    const auto files = store.logFiles();
    CHECK(files.size() == 1U);
    const auto log = readFile(files.front());
    CHECK(contains(log, "\"schemaVersion\":1"));
    CHECK(contains(log, "\"event\":\"application_launched\""));
    CHECK(contains(log, "\"event\":\"capture_failed\""));

    const auto archive = directory + L"\\diagnostics.zip";
    DiagnosticBundleExporter exporter(store);
    CHECK(exporter.exportTo(archive));
    const auto zip = readFile(archive);
    CHECK(zip.size() > 100U);
    CHECK(zip[0] == 0x50U && zip[1] == 0x4BU
        && zip[2] == 0x03U && zip[3] == 0x04U);
    CHECK(contains(zip, "manifest.json"));
    CHECK(contains(zip, "logs/diagnostic-log-1.jsonl"));
    CHECK(contains(zip, "\"windowsVersion\""));
    CHECK(contains(zip, "diagnostic_export_started"));

    removeTemporaryDirectory(directory);
}

void testSuggestedFilename()
{
    SYSTEMTIME time{};
    time.wYear = 2026;
    time.wMonth = 8;
    time.wDay = 13;
    time.wHour = 9;
    time.wMinute = 7;
    time.wSecond = 5;
    CHECK(DiagnosticBundleExporter::suggestedArchiveName(time)
        == L"XxSnap-Diagnostics-20260813-090705.zip");
}

} // namespace

int main()
{
    testLogAndBundleContract();
    testSuggestedFilename();
    return failures == 0 ? 0 : 1;
}
