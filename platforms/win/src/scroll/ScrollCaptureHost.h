#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "capture/CaptureBackend.h"
#include "snipory/core/scroll/ScrollFrame.h"

#include <Windows.h>

#include <cstddef>
#include <functional>
#include <memory>
#include <optional>

namespace xxsnap::win {

enum class ScrollCaptureHostStatus {
    completed,
    cancelled,
    failed,
};

enum class ScrollCaptureHostExportAction {
    copy,
    pin,
    save,
};

struct ScrollCaptureHostResult {
    ScrollCaptureHostStatus status = ScrollCaptureHostStatus::failed;
    std::optional<PixelBuffer> pixels;
    ScrollCaptureHostExportAction action = ScrollCaptureHostExportAction::copy;
};

class ScrollCaptureHost final {
public:
    using CompletionCallback = std::function<void(ScrollCaptureHostResult)>;

    ~ScrollCaptureHost();
    ScrollCaptureHost(const ScrollCaptureHost&) = delete;
    ScrollCaptureHost& operator=(const ScrollCaptureHost&) = delete;

    static std::unique_ptr<ScrollCaptureHost> create(
        HINSTANCE instance,
        PixelRect selection,
        DWORD targetProcessId,
        UINT dpiX,
        UINT dpiY,
        std::size_t maximumAcceptedBytes,
        CompletionCallback callback) noexcept;

private:
    struct Impl;
    explicit ScrollCaptureHost(std::unique_ptr<Impl> impl) noexcept;
    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
