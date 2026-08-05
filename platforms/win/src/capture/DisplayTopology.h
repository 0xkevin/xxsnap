#pragma once

#include "capture/CaptureTypes.h"

#include <cstdint>
#include <functional>
#include <variant>
#include <vector>

namespace xxsnap::win {

class RuntimeApis;

enum class TopologyErrorCode {
    noDisplays,
    systemFailure,
};

struct TopologyError {
    TopologyErrorCode code;
    DWORD systemError;
};

class DisplayTopologyResult final {
public:
    explicit DisplayTopologyResult(DisplayTopologySnapshot snapshot) noexcept;
    explicit DisplayTopologyResult(TopologyError error) noexcept;

    DisplayTopologyResult(const DisplayTopologyResult&) = default;
    DisplayTopologyResult(DisplayTopologyResult&&) noexcept = default;
    DisplayTopologyResult& operator=(const DisplayTopologyResult&) = delete;
    DisplayTopologyResult& operator=(DisplayTopologyResult&&) = delete;

    bool hasValue() const noexcept;
    const DisplayTopologySnapshot* value() const noexcept;
    const TopologyError* error() const noexcept;

private:
    std::variant<DisplayTopologySnapshot, TopologyError> storage_;
};

struct DisplayConfigApis {
    std::function<LONG(UINT32, UINT32*, UINT32*)> getDisplayConfigBufferSizes;
    std::function<LONG(
        UINT32,
        UINT32*,
        DISPLAYCONFIG_PATH_INFO*,
        UINT32*,
        DISPLAYCONFIG_MODE_INFO*,
        DISPLAYCONFIG_TOPOLOGY_ID*)>
        queryDisplayConfig;
    std::function<LONG(DISPLAYCONFIG_DEVICE_INFO_HEADER*)>
        displayConfigGetDeviceInfo;
};

struct MonitorEnumerationApis {
    std::function<BOOL(HDC, LPCRECT, MONITORENUMPROC, LPARAM)>
        enumDisplayMonitors;
    std::function<BOOL(HMONITOR, LPMONITORINFO)> getMonitorInfo;
};

DisplayTopologyResult buildDisplayTopologySnapshot(
    std::vector<DisplayDescriptor> displays);
DisplayConfigApis systemDisplayConfigApis();
MonitorEnumerationApis systemMonitorEnumerationApis();
DisplayTopologyResult snapshotDisplayTopology(const RuntimeApis& runtimeApis);
DisplayTopologyResult snapshotDisplayTopology(
    const RuntimeApis& runtimeApis,
    const DisplayConfigApis& displayConfigApis);
DisplayTopologyResult snapshotDisplayTopology(
    const RuntimeApis& runtimeApis,
    const DisplayConfigApis& displayConfigApis,
    const MonitorEnumerationApis& monitorEnumerationApis);

// Matches MulDiv-style nearest rounding, with exact halves rounded away from zero.
// A zero DPI is normalized to the Windows baseline of 96 DPI.
std::int64_t dipsToPhysicalPixels(std::int64_t dips, UINT dpi) noexcept;
std::int64_t physicalPixelsToDips(std::int64_t pixels, UINT dpi) noexcept;

} // namespace xxsnap::win
