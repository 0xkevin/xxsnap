#pragma once

#include "capture/CaptureBackend.h"
#include "support/WinHandle.h"

#include <functional>

namespace xxsnap::win {

struct GdiCaptureApis {
    std::function<HDC(HWND)> getDc;
    ReleaseDcFunction releaseDc;
    std::function<HDC(HDC)> createCompatibleDc;
    DeleteDcFunction deleteDc;
    std::function<HBITMAP(HDC, const BITMAPINFO*, UINT, void**, HANDLE, DWORD)>
        createDibSection;
    DeleteObjectFunction deleteObject;
    SelectObjectFunction selectObject;
    std::function<BOOL(HDC, int, int, int, int, HDC, int, int, DWORD)> bitBlt;
    std::function<BOOL()> gdiFlush;
    std::function<void(DWORD)> setLastError;
    std::function<DWORD()> getLastError;
};

GdiCaptureApis systemGdiCaptureApis();

class GdiCaptureBackend final : public CaptureBackend {
public:
    GdiCaptureBackend();
    explicit GdiCaptureBackend(GdiCaptureApis apis);

    CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget) noexcept override;

private:
    GdiCaptureApis apis_;
};

} // namespace xxsnap::win
