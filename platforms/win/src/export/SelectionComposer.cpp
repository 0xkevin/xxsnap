#include "export/SelectionComposer.h"

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <optional>
#include <utility>

namespace xxsnap::win {
namespace {

SelectionCompositionResult error(
    CaptureErrorCode code,
    HRESULT nativeCode) noexcept
{
    return CaptureError{code, nativeCode};
}

SelectionCompositionResult allocationError(
    snipory::core::portable::PixelBufferError failure) noexcept
{
    using snipory::core::portable::PixelBufferError;
    switch (failure) {
    case PixelBufferError::invalidSize:
        return error(CaptureErrorCode::invalidSize, E_INVALIDARG);
    case PixelBufferError::arithmeticOverflow:
        return error(
            CaptureErrorCode::arithmeticOverflow,
            HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    case PixelBufferError::budgetExceeded:
        return error(CaptureErrorCode::memoryLimit, E_OUTOFMEMORY);
    case PixelBufferError::allocationFailed:
        return error(CaptureErrorCode::systemFailure, E_OUTOFMEMORY);
    }
    return error(CaptureErrorCode::systemFailure, E_FAIL);
}

CaptureError invalidSizeError() noexcept
{
    return {CaptureErrorCode::invalidSize, E_INVALIDARG};
}

CaptureError overflowError() noexcept
{
    return {
        CaptureErrorCode::arithmeticOverflow,
        HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW),
    };
}

bool hasRepresentablePositiveEndpoint(
    std::int64_t origin,
    std::int64_t extent) noexcept
{
    return extent > 0
        && origin <= std::numeric_limits<std::int64_t>::max() - extent;
}

bool checkedMultiply(
    std::uint64_t lhs,
    std::uint64_t rhs,
    std::uint64_t& result) noexcept
{
    if (rhs != 0U && lhs > std::numeric_limits<std::uint64_t>::max() / rhs) {
        return false;
    }
    result = lhs * rhs;
    return true;
}

bool checkedAdd(
    std::uint64_t lhs,
    std::uint64_t rhs,
    std::uint64_t& result) noexcept
{
    if (lhs > std::numeric_limits<std::uint64_t>::max() - rhs) {
        return false;
    }
    result = lhs + rhs;
    return true;
}

std::uint64_t nonnegativeDistance(
    std::int64_t upper,
    std::int64_t lower) noexcept
{
    return static_cast<std::uint64_t>(upper)
        - static_cast<std::uint64_t>(lower);
}

std::optional<CaptureError> validateDisplay(
    const FrozenDisplay& display) noexcept
{
    const auto& bounds = display.descriptor.pixelBounds;
    if (bounds.width <= 0 || bounds.height <= 0
        || display.pixels.width() != bounds.width
        || display.pixels.height() != bounds.height
        || display.pixels.format()
            != snipory::core::portable::PixelFormat::bgra8Premultiplied) {
        return invalidSizeError();
    }

    if (!hasRepresentablePositiveEndpoint(bounds.x, bounds.width)
        || !hasRepresentablePositiveEndpoint(bounds.y, bounds.height)) {
        return overflowError();
    }

    constexpr std::uint64_t bytesPerPixel = 4U;
    std::uint64_t rowBytes = 0;
    if (!checkedMultiply(
            static_cast<std::uint64_t>(bounds.width),
            bytesPerPixel,
            rowBytes)) {
        return overflowError();
    }
    if (display.pixels.stride() < rowBytes) {
        return invalidSizeError();
    }

    std::uint64_t lastRowOffset = 0;
    std::uint64_t requiredBytes = 0;
    if (!checkedMultiply(
            static_cast<std::uint64_t>(bounds.height - 1),
            display.pixels.stride(),
            lastRowOffset)
        || !checkedAdd(lastRowOffset, rowBytes, requiredBytes)) {
        return overflowError();
    }
    if (requiredBytes > display.pixels.byteCount()) {
        return invalidSizeError();
    }

    return std::nullopt;
}

std::optional<CaptureError> rowRange(
    std::uint64_t y,
    std::uint64_t stride,
    std::uint64_t x,
    std::uint64_t rowBytes,
    std::size_t byteCount,
    std::uint64_t& offset) noexcept
{
    constexpr std::uint64_t bytesPerPixel = 4U;
    std::uint64_t rowOffset = 0;
    std::uint64_t columnOffset = 0;
    std::uint64_t rowEnd = 0;
    if (!checkedMultiply(y, stride, rowOffset)
        || !checkedMultiply(x, bytesPerPixel, columnOffset)
        || !checkedAdd(rowOffset, columnOffset, offset)
        || !checkedAdd(offset, rowBytes, rowEnd)) {
        return overflowError();
    }
    if (rowEnd > byteCount) {
        return invalidSizeError();
    }
    return std::nullopt;
}

} // namespace

SelectionCompositionResult composeSelection(
    PixelRect selection,
    const FrozenDesktop& desktop,
    MemoryBudget& budget) noexcept
{
    if (selection.width <= 0 || selection.height <= 0) {
        return error(CaptureErrorCode::invalidSize, E_INVALIDARG);
    }

    if (!hasRepresentablePositiveEndpoint(selection.x, selection.width)
        || !hasRepresentablePositiveEndpoint(selection.y, selection.height)) {
        return overflowError();
    }

    for (const auto& display : desktop.displays) {
        const auto validationError = validateDisplay(display);
        if (validationError.has_value()) {
            return *validationError;
        }
    }

    auto allocation = PixelBuffer::allocate(selection.width, selection.height, budget);
    if (!allocation.value) {
        return allocationError(allocation.error.value_or(
            snipory::core::portable::PixelBufferError::allocationFailed));
    }
    std::memset(
        allocation.value->data(),
        0,
        allocation.value->byteCount());

    for (const auto& display : desktop.displays) {
        const auto overlap = snipory::core::portable::intersection(
            selection,
            display.descriptor.pixelBounds);
        if (overlap.has_value()) {
            constexpr std::uint64_t bytesPerPixel = 4U;
            const auto sourceX = nonnegativeDistance(
                overlap->x, display.descriptor.pixelBounds.x);
            const auto sourceY = nonnegativeDistance(
                overlap->y, display.descriptor.pixelBounds.y);
            const auto destinationX = nonnegativeDistance(
                overlap->x, selection.x);
            const auto destinationY = nonnegativeDistance(
                overlap->y, selection.y);
            std::uint64_t rowBytes = 0;
            if (!checkedMultiply(
                    static_cast<std::uint64_t>(overlap->width),
                    bytesPerPixel,
                    rowBytes)) {
                return overflowError();
            }

            for (std::uint64_t row = 0;
                 row < static_cast<std::uint64_t>(overlap->height);
                 ++row) {
                std::uint64_t sourceRowIndex = 0;
                std::uint64_t destinationRowIndex = 0;
                std::uint64_t sourceOffset = 0;
                std::uint64_t destinationOffset = 0;
                if (!checkedAdd(sourceY, row, sourceRowIndex)
                    || !checkedAdd(destinationY, row, destinationRowIndex)) {
                    return overflowError();
                }
                const auto sourceRangeError = rowRange(
                    sourceRowIndex,
                    display.pixels.stride(),
                    sourceX,
                    rowBytes,
                    display.pixels.byteCount(),
                    sourceOffset);
                if (sourceRangeError.has_value()) {
                    return *sourceRangeError;
                }
                const auto destinationRangeError = rowRange(
                    destinationRowIndex,
                    allocation.value->stride(),
                    destinationX,
                    rowBytes,
                    allocation.value->byteCount(),
                    destinationOffset);
                if (destinationRangeError.has_value()) {
                    return *destinationRangeError;
                }

                const auto* sourceRow = display.pixels.data()
                    + static_cast<std::size_t>(sourceOffset);
                auto* destinationRow = allocation.value->data()
                    + static_cast<std::size_t>(destinationOffset);
                std::memcpy(
                    destinationRow,
                    sourceRow,
                    static_cast<std::size_t>(rowBytes));
            }
        }
    }

    return SelectionCompositionResult{
        std::in_place_type<PixelBuffer>,
        std::move(*allocation.value),
    };
}

} // namespace xxsnap::win
