#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifdef min
#undef min
#endif
#ifdef max
#undef max
#endif

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "snipory/core/portable/Geometry.h"

#include <Windows.h>

namespace xxsnap::win {

using snipory::core::portable::PixelRect;

struct DisplayDescriptor {
    std::wstring deviceName;
    PixelRect pixelBounds;
    UINT dpiX;
    UINT dpiY;
    DISPLAYCONFIG_ROTATION rotation;
};

inline bool operator==(const DisplayDescriptor& lhs, const DisplayDescriptor& rhs) noexcept
{
    return lhs.deviceName == rhs.deviceName
        && lhs.pixelBounds == rhs.pixelBounds
        && lhs.dpiX == rhs.dpiX
        && lhs.dpiY == rhs.dpiY
        && lhs.rotation == rhs.rotation;
}

inline bool operator!=(const DisplayDescriptor& lhs, const DisplayDescriptor& rhs) noexcept
{
    return !(lhs == rhs);
}

class DisplayTopologyResult;
struct DisplayTopologySnapshotData;

class DisplayTopologySnapshot final {
public:
    DisplayTopologySnapshot(const DisplayTopologySnapshot&) = default;
    DisplayTopologySnapshot(DisplayTopologySnapshot&& other) noexcept;
    ~DisplayTopologySnapshot() = default;

    DisplayTopologySnapshot& operator=(const DisplayTopologySnapshot&) = delete;
    DisplayTopologySnapshot& operator=(DisplayTopologySnapshot&&) = delete;

    const std::vector<DisplayDescriptor>& displays() const noexcept;
    PixelRect virtualBounds() const noexcept;
    std::uint64_t fingerprint() const noexcept;

private:
    friend DisplayTopologyResult buildDisplayTopologySnapshot(
        std::vector<DisplayDescriptor> displays);

    explicit DisplayTopologySnapshot(
        std::shared_ptr<const DisplayTopologySnapshotData> data) noexcept;

    std::shared_ptr<const DisplayTopologySnapshotData> data_;
};

} // namespace xxsnap::win
