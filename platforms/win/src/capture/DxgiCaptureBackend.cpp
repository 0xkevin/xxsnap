#include "capture/DxgiCaptureBackend.h"

#include <d3d11.h>
#include <dxgi1_2.h>
#include <wrl/client.h>

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <cwchar>
#include <limits>
#include <memory>
#include <new>
#include <utility>
#include <variant>
#include <vector>

namespace xxsnap::win {
namespace {

using Microsoft::WRL::ComPtr;

constexpr UINT acquireTimeoutMilliseconds = 100U;

CaptureResult error(CaptureErrorCode code, HRESULT nativeCode) noexcept
{
    return CaptureError{code, nativeCode};
}

CaptureResult allocationError(
    snipory::core::portable::PixelBufferError allocationFailure) noexcept
{
    using snipory::core::portable::PixelBufferError;
    switch (allocationFailure) {
    case PixelBufferError::invalidSize:
        return error(CaptureErrorCode::invalidSize, E_INVALIDARG);
    case PixelBufferError::arithmeticOverflow:
        return error(
            CaptureErrorCode::arithmeticOverflow,
            HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    case PixelBufferError::budgetExceeded:
    case PixelBufferError::allocationFailed:
        return error(CaptureErrorCode::memoryLimit, E_OUTOFMEMORY);
    }
    return error(CaptureErrorCode::systemFailure, E_FAIL);
}

bool isSupportedRotation(DISPLAYCONFIG_ROTATION rotation) noexcept
{
    switch (rotation) {
    case DISPLAYCONFIG_ROTATION_IDENTITY:
    case DISPLAYCONFIG_ROTATION_ROTATE90:
    case DISPLAYCONFIG_ROTATION_ROTATE180:
    case DISPLAYCONFIG_ROTATION_ROTATE270:
        return true;
    default:
        return false;
    }
}

DISPLAYCONFIG_ROTATION displayRotation(DXGI_MODE_ROTATION rotation) noexcept
{
    switch (rotation) {
    case DXGI_MODE_ROTATION_IDENTITY:
        return DISPLAYCONFIG_ROTATION_IDENTITY;
    case DXGI_MODE_ROTATION_ROTATE90:
        return DISPLAYCONFIG_ROTATION_ROTATE90;
    case DXGI_MODE_ROTATION_ROTATE180:
        return DISPLAYCONFIG_ROTATION_ROTATE180;
    case DXGI_MODE_ROTATION_ROTATE270:
        return DISPLAYCONFIG_ROTATION_ROTATE270;
    default:
        return static_cast<DISPLAYCONFIG_ROTATION>(0U);
    }
}

class FrameReleaseGuard final {
public:
    explicit FrameReleaseGuard(IDXGIOutputDuplication* duplication) noexcept
        : duplication_(duplication)
    {
    }

    ~FrameReleaseGuard()
    {
        if (duplication_ != nullptr) {
            static_cast<void>(duplication_->ReleaseFrame());
        }
    }

    FrameReleaseGuard(const FrameReleaseGuard&) = delete;
    FrameReleaseGuard& operator=(const FrameReleaseGuard&) = delete;

private:
    IDXGIOutputDuplication* duplication_;
};

class TextureMapGuard final {
public:
    TextureMapGuard(ID3D11DeviceContext* context, ID3D11Resource* resource) noexcept
        : context_(context)
        , resource_(resource)
    {
    }

    ~TextureMapGuard()
    {
        context_->Unmap(resource_, 0U);
    }

    TextureMapGuard(const TextureMapGuard&) = delete;
    TextureMapGuard& operator=(const TextureMapGuard&) = delete;

private:
    ID3D11DeviceContext* context_;
    ID3D11Resource* resource_;
};

struct DeviceState final {
    DxgiCaptureCacheKey cacheKey;
    ComPtr<IDXGIAdapter1> adapter;
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    ComPtr<IDXGIOutputDuplication> duplication;
};

struct DeviceStateResult final {
    DeviceState* value = nullptr;
    std::optional<CaptureError> failure;
};

} // namespace

DxgiCaptureCacheDecision decideDxgiCaptureCache(
    const DisplayDescriptor& requested,
    const DxgiCaptureCacheKey& cached) noexcept
{
    if (requested.deviceName != cached.deviceName) {
        return DxgiCaptureCacheDecision::noMatch;
    }
    if (requested.pixelBounds == cached.pixelBounds
        && requested.rotation == cached.rotation) {
        return DxgiCaptureCacheDecision::reuse;
    }
    return DxgiCaptureCacheDecision::rebuild;
}

CaptureError mapDxgiError(HRESULT nativeCode) noexcept
{
    switch (nativeCode) {
    case DXGI_ERROR_ACCESS_LOST:
        return {CaptureErrorCode::deviceLost, nativeCode};
    case DXGI_ERROR_WAIT_TIMEOUT:
        return {CaptureErrorCode::noFrame, nativeCode};
    case E_ACCESSDENIED:
        return {CaptureErrorCode::accessDenied, nativeCode};
    default:
        return {CaptureErrorCode::systemFailure, nativeCode};
    }
}

std::optional<CaptureError> copyMappedBgra(
    const std::byte* source,
    std::size_t sourceRowPitch,
    std::int64_t sourceWidth,
    std::int64_t sourceHeight,
    DISPLAYCONFIG_ROTATION rotation,
    PixelBuffer& destination) noexcept
{
    if (source == nullptr) {
        return CaptureError{CaptureErrorCode::systemFailure, E_POINTER};
    }
    if (sourceWidth <= 0 || sourceHeight <= 0
        || destination.width() <= 0 || destination.height() <= 0
        || !isSupportedRotation(rotation)) {
        return CaptureError{CaptureErrorCode::invalidSize, E_INVALIDARG};
    }

    const bool swapsDimensions = rotation == DISPLAYCONFIG_ROTATION_ROTATE90
        || rotation == DISPLAYCONFIG_ROTATION_ROTATE270;
    const auto expectedWidth = swapsDimensions ? sourceHeight : sourceWidth;
    const auto expectedHeight = swapsDimensions ? sourceWidth : sourceHeight;
    if (destination.width() != expectedWidth
        || destination.height() != expectedHeight) {
        return CaptureError{CaptureErrorCode::invalidSize, E_INVALIDARG};
    }

    const auto unsignedSourceWidth = static_cast<std::uint64_t>(sourceWidth);
    if (unsignedSourceWidth > std::numeric_limits<std::size_t>::max() / 4U) {
        return CaptureError{
            CaptureErrorCode::arithmeticOverflow,
            HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW),
        };
    }
    const auto tightSourceRowBytes = static_cast<std::size_t>(unsignedSourceWidth) * 4U;
    if (sourceRowPitch < tightSourceRowBytes
        || static_cast<std::uint64_t>(sourceHeight)
            > std::numeric_limits<std::size_t>::max() / sourceRowPitch) {
        return CaptureError{CaptureErrorCode::invalidSize, E_INVALIDARG};
    }

    for (std::int64_t destinationY = 0;
         destinationY < destination.height();
         ++destinationY) {
        for (std::int64_t destinationX = 0;
             destinationX < destination.width();
             ++destinationX) {
            std::int64_t sourceX = destinationX;
            std::int64_t sourceY = destinationY;
            switch (rotation) {
            case DISPLAYCONFIG_ROTATION_IDENTITY:
                break;
            case DISPLAYCONFIG_ROTATION_ROTATE90:
                sourceX = sourceWidth - 1 - destinationY;
                sourceY = destinationX;
                break;
            case DISPLAYCONFIG_ROTATION_ROTATE180:
                sourceX = sourceWidth - 1 - destinationX;
                sourceY = sourceHeight - 1 - destinationY;
                break;
            case DISPLAYCONFIG_ROTATION_ROTATE270:
                sourceX = destinationY;
                sourceY = sourceHeight - 1 - destinationX;
                break;
            default:
                return CaptureError{CaptureErrorCode::invalidSize, E_INVALIDARG};
            }

            const auto sourceOffset = static_cast<std::size_t>(sourceY) * sourceRowPitch
                + static_cast<std::size_t>(sourceX) * 4U;
            const auto destinationOffset
                = static_cast<std::size_t>(destinationY) * destination.stride()
                + static_cast<std::size_t>(destinationX) * 4U;
            std::memcpy(destination.data() + destinationOffset, source + sourceOffset, 3U);
            destination.data()[destinationOffset + 3U] = std::byte{255U};
        }
    }
    return std::nullopt;
}

class DxgiCaptureBackend::Impl final {
public:
    CaptureResult capture(
        const DisplayTopologySnapshot& snapshot,
        MemoryBudget& budget)
    {
        std::vector<FrozenDisplay> frozenDisplays;
        frozenDisplays.reserve(snapshot.displays().size());

        for (const auto& display : snapshot.displays()) {
            if (display.pixelBounds.width <= 0 || display.pixelBounds.height <= 0
                || !isSupportedRotation(display.rotation)) {
                return error(CaptureErrorCode::invalidSize, E_INVALIDARG);
            }

            const auto stateResult = stateFor(display);
            if (stateResult.failure.has_value()) {
                return *stateResult.failure;
            }
            auto& state = *stateResult.value;
            if (decideDxgiCaptureCache(display, state.cacheKey)
                != DxgiCaptureCacheDecision::reuse) {
                reset();
                return error(CaptureErrorCode::topologyChanged, DXGI_ERROR_ACCESS_LOST);
            }

            DXGI_OUTDUPL_FRAME_INFO frameInfo{};
            ComPtr<IDXGIResource> frameResource;
            const auto acquireResult = state.duplication->AcquireNextFrame(
                acquireTimeoutMilliseconds,
                &frameInfo,
                frameResource.GetAddressOf());
            if (FAILED(acquireResult)) {
                return mapDxgiError(acquireResult);
            }
            FrameReleaseGuard frameGuard(state.duplication.Get());
            if (!frameResource) {
                return error(CaptureErrorCode::systemFailure, E_POINTER);
            }

            ComPtr<ID3D11Texture2D> frameTexture;
            const auto textureResult = frameResource.As(&frameTexture);
            if (FAILED(textureResult)) {
                return mapDxgiError(textureResult);
            }

            D3D11_TEXTURE2D_DESC textureDescription{};
            frameTexture->GetDesc(&textureDescription);
            if (textureDescription.Format != DXGI_FORMAT_B8G8R8A8_UNORM
                || textureDescription.MipLevels != 1U
                || textureDescription.ArraySize != 1U
                || textureDescription.SampleDesc.Count != 1U) {
                return error(CaptureErrorCode::unsupported, DXGI_ERROR_UNSUPPORTED);
            }

            auto allocation = PixelBuffer::allocate(
                display.pixelBounds.width,
                display.pixelBounds.height,
                budget);
            if (!allocation.value) {
                return allocationError(*allocation.error);
            }

            auto stagingDescription = textureDescription;
            stagingDescription.Usage = D3D11_USAGE_STAGING;
            stagingDescription.BindFlags = 0U;
            stagingDescription.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
            stagingDescription.MiscFlags = 0U;

            ComPtr<ID3D11Texture2D> stagingTexture;
            const auto createTextureResult = state.device->CreateTexture2D(
                &stagingDescription,
                nullptr,
                stagingTexture.GetAddressOf());
            if (FAILED(createTextureResult)) {
                return mapDxgiError(createTextureResult);
            }

            state.context->CopyResource(stagingTexture.Get(), frameTexture.Get());

            D3D11_MAPPED_SUBRESOURCE mapped{};
            const auto mapResult = state.context->Map(
                stagingTexture.Get(),
                0U,
                D3D11_MAP_READ,
                0U,
                &mapped);
            if (FAILED(mapResult)) {
                return mapDxgiError(mapResult);
            }
            TextureMapGuard mapGuard(state.context.Get(), stagingTexture.Get());

            const auto copyFailure = copyMappedBgra(
                static_cast<const std::byte*>(mapped.pData),
                mapped.RowPitch,
                textureDescription.Width,
                textureDescription.Height,
                display.rotation,
                *allocation.value);
            if (copyFailure.has_value()) {
                return *copyFailure;
            }

            frozenDisplays.emplace_back(display, std::move(*allocation.value));
        }

        return FrozenDesktop{
            snapshot,
            std::move(frozenDisplays),
            std::chrono::steady_clock::now(),
        };
    }

    void reset() noexcept
    {
        states_.clear();
        factory_.Reset();
    }

private:
    DeviceStateResult stateFor(const DisplayDescriptor& display)
    {
        for (auto state = states_.begin(); state != states_.end(); ++state) {
            const auto decision = decideDxgiCaptureCache(display, (*state)->cacheKey);
            if (decision == DxgiCaptureCacheDecision::reuse) {
                return {state->get(), std::nullopt};
            }
            if (decision == DxgiCaptureCacheDecision::rebuild) {
                states_.erase(state);
                break;
            }
        }

        if (!factory_) {
            const auto factoryResult = CreateDXGIFactory1(
                IID_PPV_ARGS(factory_.ReleaseAndGetAddressOf()));
            if (FAILED(factoryResult)) {
                return {nullptr, mapDxgiError(factoryResult)};
            }
        }

        for (UINT adapterIndex = 0U;; ++adapterIndex) {
            ComPtr<IDXGIAdapter1> adapter;
            const auto adapterResult = factory_->EnumAdapters1(
                adapterIndex,
                adapter.GetAddressOf());
            if (adapterResult == DXGI_ERROR_NOT_FOUND) {
                break;
            }
            if (FAILED(adapterResult)) {
                return {nullptr, mapDxgiError(adapterResult)};
            }

            for (UINT outputIndex = 0U;; ++outputIndex) {
                ComPtr<IDXGIOutput> output;
                const auto outputResult = adapter->EnumOutputs(
                    outputIndex,
                    output.GetAddressOf());
                if (outputResult == DXGI_ERROR_NOT_FOUND) {
                    break;
                }
                if (FAILED(outputResult)) {
                    return {nullptr, mapDxgiError(outputResult)};
                }

                DXGI_OUTPUT_DESC outputDescription{};
                const auto descriptionResult = output->GetDesc(&outputDescription);
                if (FAILED(descriptionResult)) {
                    return {nullptr, mapDxgiError(descriptionResult)};
                }
                if (std::wcscmp(outputDescription.DeviceName, display.deviceName.c_str()) != 0) {
                    continue;
                }

                auto state = std::make_unique<DeviceState>();
                const auto& coordinates = outputDescription.DesktopCoordinates;
                state->cacheKey.deviceName = display.deviceName;
                state->cacheKey.pixelBounds = {
                    coordinates.left,
                    coordinates.top,
                    static_cast<std::int64_t>(coordinates.right)
                        - static_cast<std::int64_t>(coordinates.left),
                    static_cast<std::int64_t>(coordinates.bottom)
                        - static_cast<std::int64_t>(coordinates.top),
                };
                state->adapter = adapter;

                D3D_FEATURE_LEVEL featureLevel{};
                const auto deviceResult = D3D11CreateDevice(
                    adapter.Get(),
                    D3D_DRIVER_TYPE_UNKNOWN,
                    nullptr,
                    D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                    nullptr,
                    0U,
                    D3D11_SDK_VERSION,
                    state->device.GetAddressOf(),
                    &featureLevel,
                    state->context.GetAddressOf());
                if (FAILED(deviceResult)) {
                    return {nullptr, mapDxgiError(deviceResult)};
                }

                ComPtr<IDXGIOutput1> output1;
                const auto output1Result = output.As(&output1);
                if (FAILED(output1Result)) {
                    return {nullptr, mapDxgiError(output1Result)};
                }
                const auto duplicationResult = output1->DuplicateOutput(
                    state->device.Get(),
                    state->duplication.GetAddressOf());
                if (FAILED(duplicationResult)) {
                    return {nullptr, mapDxgiError(duplicationResult)};
                }

                DXGI_OUTDUPL_DESC duplicationDescription{};
                state->duplication->GetDesc(&duplicationDescription);
                state->cacheKey.rotation = displayRotation(duplicationDescription.Rotation);

                auto* value = state.get();
                states_.push_back(std::move(state));
                return {value, std::nullopt};
            }
        }

        return {
            nullptr,
            CaptureError{CaptureErrorCode::unsupported, DXGI_ERROR_NOT_FOUND},
        };
    }

    ComPtr<IDXGIFactory1> factory_;
    std::vector<std::unique_ptr<DeviceState>> states_;
};

DxgiCaptureBackend::DxgiCaptureBackend()
    : impl_(std::make_unique<Impl>())
{
}

DxgiCaptureBackend::~DxgiCaptureBackend() = default;

CaptureResult DxgiCaptureBackend::capture(
    const DisplayTopologySnapshot& snapshot,
    MemoryBudget& budget) noexcept
{
    try {
        return impl_->capture(snapshot, budget);
    } catch (const std::bad_alloc&) {
        return error(CaptureErrorCode::memoryLimit, E_OUTOFMEMORY);
    } catch (...) {
        return error(CaptureErrorCode::systemFailure, E_FAIL);
    }
}

void DxgiCaptureBackend::reset() noexcept
{
    impl_->reset();
}

} // namespace xxsnap::win
