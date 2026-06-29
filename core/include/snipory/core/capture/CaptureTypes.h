#pragma once

#include <QImage>
#include <QRect>

#include <utility>

namespace snipory::core {

class CaptureRegion final {
public:
    static CaptureRegion fromDevicePixels(int x, int y, int width, int height)
    {
        return CaptureRegion(QRect(x, y, width, height));
    }

    QRect devicePixelRect() const
    {
        return m_devicePixelRect;
    }

    bool isValid() const
    {
        return m_devicePixelRect.isValid();
    }

private:
    explicit CaptureRegion(QRect devicePixelRect)
        : m_devicePixelRect(std::move(devicePixelRect))
    {
    }

    QRect m_devicePixelRect;
};

enum class CaptureStatus {
    Success,
    PermissionDenied,
    Unavailable,
    EmptyRegion
};

struct CaptureResult final {
    CaptureStatus status = CaptureStatus::Unavailable;
    QImage image;

    static CaptureResult success(QImage capturedImage)
    {
        return CaptureResult{CaptureStatus::Success, std::move(capturedImage)};
    }

    static CaptureResult failure(CaptureStatus failureStatus)
    {
        return CaptureResult{failureStatus, QImage()};
    }
};

} // namespace snipory::core
