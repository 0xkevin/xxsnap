#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "capture/CaptureBackend.h"

#include <Windows.h>

#include <memory>

namespace xxsnap::win {

class PinnedImageHost final {
public:
    explicit PinnedImageHost(HINSTANCE instance, HWND dialogOwner);
    ~PinnedImageHost();

    PinnedImageHost(const PinnedImageHost&) = delete;
    PinnedImageHost& operator=(const PinnedImageHost&) = delete;

    bool pin(PixelBuffer pixels, PixelRect sourceRect) noexcept;
    std::size_t count() const noexcept;
    bool restoreMostRecentlyHidden() noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
