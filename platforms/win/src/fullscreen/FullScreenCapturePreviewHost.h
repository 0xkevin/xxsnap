#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "capture/CaptureBackend.h"

#include <Windows.h>

#include <memory>

namespace xxsnap::win {

class PinnedImageHost;

PixelRect fullScreenPreviewRect(
    std::int64_t imageWidth,
    std::int64_t imageHeight,
    PixelRect workArea) noexcept;

class FullScreenCapturePreviewHost final {
public:
    FullScreenCapturePreviewHost(
        HINSTANCE instance,
        HWND dialogOwner,
        PinnedImageHost& pinnedImages);
    ~FullScreenCapturePreviewHost();

    FullScreenCapturePreviewHost(
        const FullScreenCapturePreviewHost&) = delete;
    FullScreenCapturePreviewHost& operator=(
        const FullScreenCapturePreviewHost&) = delete;

    bool show(PixelBuffer pixels, PixelRect sourceRect) noexcept;
    void close() noexcept;
    bool visible() const noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
