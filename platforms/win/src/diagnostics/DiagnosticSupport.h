#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>

#include <cstddef>
#include <string>
#include <vector>

namespace xxsnap::win {

class DiagnosticLogStore final {
public:
    explicit DiagnosticLogStore(std::wstring directory = {}) noexcept;

    void record(const char* category, const char* level,
        const char* event) noexcept;
    const std::wstring& directory() const noexcept;
    std::vector<std::wstring> logFiles() const noexcept;

private:
    void maintain() const noexcept;

    std::wstring directory_;
};

struct DiagnosticBundleLimits final {
    std::size_t maximumFileCount = 5U;
    std::size_t maximumFileBytes = 5U * 1024U * 1024U;
    std::size_t maximumTotalBytes = 20U * 1024U * 1024U;
};

class DiagnosticBundleExporter final {
public:
    explicit DiagnosticBundleExporter(
        DiagnosticLogStore& store,
        DiagnosticBundleLimits limits = {}) noexcept;

    bool exportTo(const std::wstring& destination) noexcept;
    static std::wstring suggestedArchiveName(const SYSTEMTIME& time);

private:
    DiagnosticLogStore& store_;
    DiagnosticBundleLimits limits_;
};

class DiagnosticSupportController final {
public:
    DiagnosticSupportController(HWND owner, DiagnosticLogStore& store) noexcept;

    void exportDiagnostics() noexcept;

private:
    HWND owner_ = nullptr;
    DiagnosticLogStore& store_;
};

} // namespace xxsnap::win
