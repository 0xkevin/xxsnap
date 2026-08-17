#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "capture/CaptureTypes.h"

#include <Windows.h>

#include <memory>

namespace xxsnap::win {

class OcrResultPresenter final {
public:
    OcrResultPresenter(HINSTANCE instance, HWND owner);
    ~OcrResultPresenter();

    OcrResultPresenter(const OcrResultPresenter&) = delete;
    OcrResultPresenter& operator=(const OcrResultPresenter&) = delete;

    void showSuccess(PixelRect selection) noexcept;
    void showFailure(PixelRect selection) noexcept;
    void close() noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
