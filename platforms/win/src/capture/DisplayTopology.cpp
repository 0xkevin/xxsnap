#include "capture/DisplayTopology.h"

#include "support/RuntimeApis.h"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <map>
#include <memory>
#include <new>
#include <optional>
#include <string>
#include <tuple>
#include <type_traits>
#include <utility>
#include <vector>

namespace xxsnap::win {

struct DisplayTopologySnapshotData final {
    DisplayTopologySnapshotData(
        std::vector<DisplayDescriptor> sourceDisplays,
        PixelRect sourceVirtualBounds,
        std::uint64_t sourceFingerprint)
        : displays(std::move(sourceDisplays))
        , virtualBounds(sourceVirtualBounds)
        , fingerprint(sourceFingerprint)
    {
    }

    const std::vector<DisplayDescriptor> displays;
    const PixelRect virtualBounds;
    const std::uint64_t fingerprint;
};

DisplayTopologySnapshot::DisplayTopologySnapshot(
    std::shared_ptr<const DisplayTopologySnapshotData> data) noexcept
    : data_(std::move(data))
{
}

DisplayTopologySnapshot::DisplayTopologySnapshot(
    DisplayTopologySnapshot&& other) noexcept
    : data_(other.data_)
{
}

const std::vector<DisplayDescriptor>& DisplayTopologySnapshot::displays() const noexcept
{
    return data_->displays;
}

PixelRect DisplayTopologySnapshot::virtualBounds() const noexcept
{
    return data_->virtualBounds;
}

std::uint64_t DisplayTopologySnapshot::fingerprint() const noexcept
{
    return data_->fingerprint;
}

DisplayTopologyResult::DisplayTopologyResult(
    DisplayTopologySnapshot snapshot) noexcept
    : storage_(std::move(snapshot))
{
}

DisplayTopologyResult::DisplayTopologyResult(TopologyError error) noexcept
    : storage_(error)
{
}

bool DisplayTopologyResult::hasValue() const noexcept
{
    return std::holds_alternative<DisplayTopologySnapshot>(storage_);
}

const DisplayTopologySnapshot* DisplayTopologyResult::value() const noexcept
{
    return std::get_if<DisplayTopologySnapshot>(&storage_);
}

const TopologyError* DisplayTopologyResult::error() const noexcept
{
    return std::get_if<TopologyError>(&storage_);
}

namespace {

constexpr std::uint64_t fnvOffsetBasis = 14695981039346656037ULL;
constexpr std::uint64_t fnvPrime = 1099511628211ULL;
constexpr UINT defaultDpi = 96U;

std::int64_t saturatingAdd(std::int64_t lhs, std::int64_t rhs) noexcept
{
    constexpr auto minimum = std::numeric_limits<std::int64_t>::min();
    constexpr auto maximum = std::numeric_limits<std::int64_t>::max();
    if (rhs > 0 && lhs > maximum - rhs) {
        return maximum;
    }
    if (rhs < 0 && lhs < minimum - rhs) {
        return minimum;
    }
    return lhs + rhs;
}

std::int64_t nonnegativeDifference(std::int64_t upper, std::int64_t lower) noexcept
{
    const auto difference = static_cast<std::uint64_t>(upper)
        - static_cast<std::uint64_t>(lower);
    constexpr auto maximum =
        static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max());
    return difference > maximum
        ? std::numeric_limits<std::int64_t>::max()
        : static_cast<std::int64_t>(difference);
}

PixelRect unionBounds(const std::vector<DisplayDescriptor>& displays) noexcept
{
    auto bounds = snipory::core::portable::standardized(displays.front().pixelBounds);
    auto left = bounds.x;
    auto top = bounds.y;
    auto right = saturatingAdd(bounds.x, bounds.width);
    auto bottom = saturatingAdd(bounds.y, bounds.height);

    for (std::size_t index = 1U; index < displays.size(); ++index) {
        bounds = snipory::core::portable::standardized(displays[index].pixelBounds);
        left = (std::min)(left, bounds.x);
        top = (std::min)(top, bounds.y);
        right = (std::max)(right, saturatingAdd(bounds.x, bounds.width));
        bottom = (std::max)(bottom, saturatingAdd(bounds.y, bounds.height));
    }
    return {
        left,
        top,
        nonnegativeDifference(right, left),
        nonnegativeDifference(bottom, top),
    };
}

void hashByte(std::uint64_t& hash, std::uint8_t byte) noexcept
{
    hash ^= byte;
    hash *= fnvPrime;
}

template <typename Unsigned>
void hashLittleEndian(std::uint64_t& hash, Unsigned value) noexcept
{
    static_assert(std::is_unsigned_v<Unsigned>);
    for (std::size_t index = 0U; index < sizeof(Unsigned); ++index) {
        hashByte(hash, static_cast<std::uint8_t>(value & 0xFFU));
        value >>= 8U;
    }
}

void hashSigned64(std::uint64_t& hash, std::int64_t value) noexcept
{
    hashLittleEndian(hash, static_cast<std::uint64_t>(value));
}

std::uint64_t topologyFingerprint(std::vector<DisplayDescriptor> displays)
{
    std::sort(displays.begin(), displays.end(), [](const auto& lhs, const auto& rhs) {
        return std::tie(
                   lhs.deviceName,
                   lhs.pixelBounds.x,
                   lhs.pixelBounds.y,
                   lhs.pixelBounds.width,
                   lhs.pixelBounds.height,
                   lhs.dpiX,
                   lhs.dpiY,
                   lhs.rotation)
            < std::tie(
                   rhs.deviceName,
                   rhs.pixelBounds.x,
                   rhs.pixelBounds.y,
                   rhs.pixelBounds.width,
                   rhs.pixelBounds.height,
                   rhs.dpiX,
                   rhs.dpiY,
                   rhs.rotation);
    });

    std::uint64_t hash = fnvOffsetBasis;
    hashByte(hash, 1U);
    hashLittleEndian(hash, static_cast<std::uint64_t>(displays.size()));
    for (const auto& display : displays) {
        static_assert(sizeof(wchar_t) == sizeof(std::uint16_t));
        hashLittleEndian(hash, static_cast<std::uint64_t>(display.deviceName.size()));
        for (const wchar_t codeUnit : display.deviceName) {
            hashLittleEndian(hash, static_cast<std::uint16_t>(codeUnit));
        }
        hashSigned64(hash, display.pixelBounds.x);
        hashSigned64(hash, display.pixelBounds.y);
        hashSigned64(hash, display.pixelBounds.width);
        hashSigned64(hash, display.pixelBounds.height);
        hashLittleEndian(hash, static_cast<std::uint32_t>(display.dpiX));
        hashLittleEndian(hash, static_cast<std::uint32_t>(display.dpiY));
        hashLittleEndian(hash, static_cast<std::uint32_t>(display.rotation));
    }
    return hash;
}

std::uint64_t unsignedMagnitude(std::int64_t value) noexcept
{
    return value < 0
        ? std::uint64_t{0} - static_cast<std::uint64_t>(value)
        : static_cast<std::uint64_t>(value);
}

std::int64_t scaleNearest(
    std::int64_t value,
    std::uint32_t numerator,
    std::uint32_t denominator) noexcept
{
    if (denominator == 0U) {
        denominator = defaultDpi;
    }
    const auto magnitude = unsignedMagnitude(value);
    const auto whole = magnitude / denominator;
    const auto remainder = magnitude % denominator;
    constexpr auto positiveLimit =
        static_cast<std::uint64_t>(std::numeric_limits<std::int64_t>::max());
    const auto resultLimit = value < 0 ? positiveLimit + 1U : positiveLimit;

    if (numerator != 0U && whole > resultLimit / numerator) {
        return value < 0
            ? std::numeric_limits<std::int64_t>::min()
            : std::numeric_limits<std::int64_t>::max();
    }
    auto scaled = whole * numerator;
    const auto remainderProduct = remainder * static_cast<std::uint64_t>(numerator);
    const auto fractional = remainderProduct / denominator;
    const auto fractionalRemainder = remainderProduct % denominator;
    const auto roundedFractional = fractional
        + (fractionalRemainder >= (static_cast<std::uint64_t>(denominator) + 1U) / 2U
                ? 1U
                : 0U);
    if (roundedFractional > resultLimit - scaled) {
        return value < 0
            ? std::numeric_limits<std::int64_t>::min()
            : std::numeric_limits<std::int64_t>::max();
    }
    scaled += roundedFractional;

    if (value >= 0) {
        return static_cast<std::int64_t>(scaled);
    }
    if (scaled == positiveLimit + 1U) {
        return std::numeric_limits<std::int64_t>::min();
    }
    return -static_cast<std::int64_t>(scaled);
}

DISPLAYCONFIG_ROTATION normalizedRotation(DISPLAYCONFIG_ROTATION rotation) noexcept
{
    switch (rotation) {
    case DISPLAYCONFIG_ROTATION_IDENTITY:
    case DISPLAYCONFIG_ROTATION_ROTATE90:
    case DISPLAYCONFIG_ROTATION_ROTATE180:
    case DISPLAYCONFIG_ROTATION_ROTATE270:
        return rotation;
    default:
        return DISPLAYCONFIG_ROTATION_IDENTITY;
    }
}

struct RotationAssociation {
    DISPLAYCONFIG_ROTATION rotation = DISPLAYCONFIG_ROTATION_IDENTITY;
    bool ambiguous = false;
};

using RotationMap = std::map<std::wstring, RotationAssociation>;

struct RotationQueryResult {
    std::optional<RotationMap> rotations;
    DWORD systemError;
};

RotationQueryResult queryActiveRotations(const DisplayConfigApis& apis)
{
    if (!apis.getDisplayConfigBufferSizes) {
        return {std::nullopt, ERROR_PROC_NOT_FOUND};
    }

    UINT32 pathCount = 0U;
    UINT32 modeCount = 0U;
    LONG queryResult = ERROR_SUCCESS;
    std::vector<DISPLAYCONFIG_PATH_INFO> paths;
    std::vector<DISPLAYCONFIG_MODE_INFO> modes;

    for (int attempt = 0; attempt < 3; ++attempt) {
        queryResult = apis.getDisplayConfigBufferSizes(
            QDC_ONLY_ACTIVE_PATHS, &pathCount, &modeCount);
        if (queryResult != ERROR_SUCCESS) {
            return {std::nullopt, static_cast<DWORD>(queryResult)};
        }
        if (!apis.queryDisplayConfig) {
            return {std::nullopt, ERROR_PROC_NOT_FOUND};
        }
        paths.resize(pathCount);
        modes.resize(modeCount);
        queryResult = apis.queryDisplayConfig(
            QDC_ONLY_ACTIVE_PATHS,
            &pathCount,
            paths.data(),
            &modeCount,
            modes.data(),
            nullptr);
        if (queryResult != ERROR_INSUFFICIENT_BUFFER) {
            break;
        }
    }
    if (queryResult != ERROR_SUCCESS) {
        return {std::nullopt, static_cast<DWORD>(queryResult)};
    }
    paths.resize(pathCount);

    RotationMap rotations;
    for (const auto& path : paths) {
        if ((path.flags & DISPLAYCONFIG_PATH_ACTIVE) == 0U) {
            continue;
        }
        DISPLAYCONFIG_SOURCE_DEVICE_NAME sourceName{};
        sourceName.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
        sourceName.header.size = sizeof(sourceName);
        sourceName.header.adapterId = path.sourceInfo.adapterId;
        sourceName.header.id = path.sourceInfo.id;
        if (!apis.displayConfigGetDeviceInfo) {
            return {std::nullopt, ERROR_PROC_NOT_FOUND};
        }
        const auto deviceInfoResult =
            apis.displayConfigGetDeviceInfo(&sourceName.header);
        if (deviceInfoResult != ERROR_SUCCESS) {
            return {std::nullopt, static_cast<DWORD>(deviceInfoResult)};
        }
        if (sourceName.viewGdiDeviceName[0] == L'\0') {
            continue;
        }

        const std::wstring deviceName(sourceName.viewGdiDeviceName);
        const auto rotation = normalizedRotation(path.targetInfo.rotation);
        const auto existing = rotations.find(deviceName);
        if (existing == rotations.end()) {
            rotations.emplace(deviceName, RotationAssociation{rotation, false});
        } else {
            // A cloned source has more than one target path. It cannot be associated
            // with one EnumDisplayMonitors result without guessing.
            existing->second.ambiguous = true;
            existing->second.rotation = DISPLAYCONFIG_ROTATION_IDENTITY;
        }
    }
    return {std::move(rotations), ERROR_SUCCESS};
}

struct EnumerationContext {
    const RuntimeApis& runtimeApis;
    const RotationMap& rotations;
    const MonitorEnumerationApis& monitorEnumerationApis;
    std::vector<DisplayDescriptor> displays;
    DWORD systemError = ERROR_SUCCESS;
};

BOOL CALLBACK appendMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM parameter)
{
    auto& context = *reinterpret_cast<EnumerationContext*>(parameter);
    if (context.systemError != ERROR_SUCCESS) {
        return FALSE;
    }

    try {
        if (!context.monitorEnumerationApis.getMonitorInfo) {
            context.systemError = ERROR_PROC_NOT_FOUND;
            return FALSE;
        }
        MONITORINFOEXW monitorInfo{};
        monitorInfo.cbSize = sizeof(monitorInfo);
        if (context.monitorEnumerationApis.getMonitorInfo(
                monitor, reinterpret_cast<LPMONITORINFO>(&monitorInfo))
            == FALSE) {
            context.systemError = GetLastError();
            if (context.systemError == ERROR_SUCCESS) {
                context.systemError = ERROR_GEN_FAILURE;
            }
            return FALSE;
        }

        const std::wstring deviceName(monitorInfo.szDevice);
        const auto dpi = context.runtimeApis.dpiForMonitor(monitor, deviceName);
        auto rotation = DISPLAYCONFIG_ROTATION_IDENTITY;
        const auto rotationEntry = context.rotations.find(deviceName);
        if (rotationEntry != context.rotations.end()
            && !rotationEntry->second.ambiguous) {
            rotation = rotationEntry->second.rotation;
        }

        context.displays.push_back({
            deviceName,
            {static_cast<std::int64_t>(monitorInfo.rcMonitor.left),
             static_cast<std::int64_t>(monitorInfo.rcMonitor.top),
             static_cast<std::int64_t>(monitorInfo.rcMonitor.right)
                 - static_cast<std::int64_t>(monitorInfo.rcMonitor.left),
             static_cast<std::int64_t>(monitorInfo.rcMonitor.bottom)
                 - static_cast<std::int64_t>(monitorInfo.rcMonitor.top)},
            dpi.x,
            dpi.y,
            rotation,
        });
        return TRUE;
    } catch (const std::bad_alloc&) {
        context.systemError = ERROR_NOT_ENOUGH_MEMORY;
        return FALSE;
    } catch (...) {
        context.systemError = ERROR_UNHANDLED_EXCEPTION;
        return FALSE;
    }
}

} // namespace

DisplayTopologyResult buildDisplayTopologySnapshot(
    std::vector<DisplayDescriptor> displays)
{
    if (displays.empty()) {
        return DisplayTopologyResult(
            TopologyError{TopologyErrorCode::noDisplays, ERROR_SUCCESS});
    }

    const auto virtualBounds = unionBounds(displays);
    const auto fingerprint = topologyFingerprint(displays);
    auto data = std::make_shared<const DisplayTopologySnapshotData>(
        std::move(displays), virtualBounds, fingerprint);
    return DisplayTopologyResult(DisplayTopologySnapshot(std::move(data)));
}

DisplayConfigApis systemDisplayConfigApis()
{
    DisplayConfigApis apis;
    apis.getDisplayConfigBufferSizes = [](UINT32 flags, UINT32* pathCount, UINT32* modeCount) {
        return GetDisplayConfigBufferSizes(flags, pathCount, modeCount);
    };
    apis.queryDisplayConfig = [](
                                  UINT32 flags,
                                  UINT32* pathCount,
                                  DISPLAYCONFIG_PATH_INFO* paths,
                                  UINT32* modeCount,
                                  DISPLAYCONFIG_MODE_INFO* modes,
                                  DISPLAYCONFIG_TOPOLOGY_ID* topologyId) {
        return QueryDisplayConfig(
            flags, pathCount, paths, modeCount, modes, topologyId);
    };
    apis.displayConfigGetDeviceInfo = [](DISPLAYCONFIG_DEVICE_INFO_HEADER* request) {
        return DisplayConfigGetDeviceInfo(request);
    };
    return apis;
}

MonitorEnumerationApis systemMonitorEnumerationApis()
{
    MonitorEnumerationApis apis;
    apis.enumDisplayMonitors = [](
                                   HDC deviceContext,
                                   LPCRECT clipRect,
                                   MONITORENUMPROC callback,
                                   LPARAM context) {
        return EnumDisplayMonitors(deviceContext, clipRect, callback, context);
    };
    apis.getMonitorInfo = [](HMONITOR monitor, LPMONITORINFO monitorInfo) {
        return GetMonitorInfoW(monitor, monitorInfo);
    };
    return apis;
}

DisplayTopologyResult snapshotDisplayTopology(const RuntimeApis& runtimeApis)
{
    return snapshotDisplayTopology(
        runtimeApis, systemDisplayConfigApis(), systemMonitorEnumerationApis());
}

DisplayTopologyResult snapshotDisplayTopology(
    const RuntimeApis& runtimeApis,
    const DisplayConfigApis& displayConfigApis)
{
    return snapshotDisplayTopology(
        runtimeApis, displayConfigApis, systemMonitorEnumerationApis());
}

DisplayTopologyResult snapshotDisplayTopology(
    const RuntimeApis& runtimeApis,
    const DisplayConfigApis& displayConfigApis,
    const MonitorEnumerationApis& monitorEnumerationApis)
{
    auto rotationResult = queryActiveRotations(displayConfigApis);
    if (!rotationResult.rotations.has_value()) {
        return DisplayTopologyResult(TopologyError{
            TopologyErrorCode::systemFailure, rotationResult.systemError});
    }

    EnumerationContext context{
        runtimeApis,
        *rotationResult.rotations,
        monitorEnumerationApis,
        {},
        ERROR_SUCCESS};
    if (!monitorEnumerationApis.enumDisplayMonitors) {
        return DisplayTopologyResult(TopologyError{
            TopologyErrorCode::systemFailure, ERROR_PROC_NOT_FOUND});
    }

    SetLastError(ERROR_SUCCESS);
    BOOL enumerationResult = FALSE;
    try {
        enumerationResult = monitorEnumerationApis.enumDisplayMonitors(
            nullptr, nullptr, appendMonitor, reinterpret_cast<LPARAM>(&context));
    } catch (const std::bad_alloc&) {
        return DisplayTopologyResult(TopologyError{
            TopologyErrorCode::systemFailure, ERROR_NOT_ENOUGH_MEMORY});
    } catch (...) {
        return DisplayTopologyResult(TopologyError{
            TopologyErrorCode::systemFailure, ERROR_UNHANDLED_EXCEPTION});
    }
    if (enumerationResult == FALSE) {
        auto systemError = context.systemError;
        if (systemError == ERROR_SUCCESS) {
            systemError = GetLastError();
        }
        if (systemError == ERROR_SUCCESS) {
            systemError = ERROR_GEN_FAILURE;
        }
        return DisplayTopologyResult(
            TopologyError{TopologyErrorCode::systemFailure, systemError});
    }
    return buildDisplayTopologySnapshot(std::move(context.displays));
}

std::int64_t dipsToPhysicalPixels(std::int64_t dips, UINT dpi) noexcept
{
    return scaleNearest(dips, dpi == 0U ? defaultDpi : dpi, defaultDpi);
}

std::int64_t physicalPixelsToDips(std::int64_t pixels, UINT dpi) noexcept
{
    return scaleNearest(pixels, defaultDpi, dpi == 0U ? defaultDpi : dpi);
}

} // namespace xxsnap::win
