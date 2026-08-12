#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "capture/DisplayTopology.h"
#include "capture/FallbackCaptureBackend.h"
#include "ocr/OcrResultPresenter.h"

#include <Windows.h>

#include <memory>
#include <thread>

namespace xxsnap::win {

class OverlayHost;
class RuntimeApis;

class OcrCaptureHost final {
public:
    OcrCaptureHost(HINSTANCE instance, HWND owner, RuntimeApis& runtimeApis);
    ~OcrCaptureHost();

    OcrCaptureHost(const OcrCaptureHost&) = delete;
    OcrCaptureHost& operator=(const OcrCaptureHost&) = delete;

    bool start() noexcept;
    void cancel() noexcept;
    bool busy() const noexcept;

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
