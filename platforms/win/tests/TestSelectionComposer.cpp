#include "capture/DisplayTopology.h"
#include "export/SelectionComposer.h"

#include <chrono>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <memory>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

namespace {

using namespace xxsnap::win;
using snipory::core::portable::MemoryBudget;
using snipory::core::portable::PixelBuffer;
using snipory::core::portable::PixelRect;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

DisplayDescriptor descriptor(
    const wchar_t* name,
    PixelRect bounds)
{
    return {
        name,
        bounds,
        96U,
        96U,
        DISPLAYCONFIG_ROTATION_IDENTITY,
    };
}

DisplayTopologySnapshot snapshotFor(std::vector<DisplayDescriptor> displays)
{
    const auto result = buildDisplayTopologySnapshot(std::move(displays));
    CHECK(result.hasValue());
    return *result.value();
}

void setPixel(
    PixelBuffer& pixels,
    std::int64_t x,
    std::int64_t y,
    std::byte blue,
    std::byte green,
    std::byte red,
    std::byte alpha)
{
    const auto row = static_cast<std::uint64_t>(y) * pixels.stride();
    const auto column = static_cast<std::uint64_t>(x) * 4U;
    auto* pixel = pixels.data() + static_cast<std::size_t>(row + column);
    pixel[0] = blue;
    pixel[1] = green;
    pixel[2] = red;
    pixel[3] = alpha;
}

const std::byte* pixelAt(
    const PixelBuffer& pixels,
    std::int64_t x,
    std::int64_t y)
{
    const auto row = static_cast<std::uint64_t>(y) * pixels.stride();
    const auto column = static_cast<std::uint64_t>(x) * 4U;
    return pixels.data() + static_cast<std::size_t>(row + column);
}

void testCropsOneFrozenDisplayInPhysicalPixels()
{
    constexpr PixelRect bounds{0, 0, 8, 6};
    MemoryBudget sourceBudget(8U * 6U * 4U);
    auto source = PixelBuffer::allocate(bounds.width, bounds.height, sourceBudget);
    CHECK(source.value != nullptr);
    if (!source.value) {
        return;
    }

    for (std::int64_t y = 0; y < bounds.height; ++y) {
        for (std::int64_t x = 0; x < bounds.width; ++x) {
            setPixel(
                *source.value,
                x,
                y,
                std::byte{static_cast<unsigned char>(x)},
                std::byte{static_cast<unsigned char>(y)},
                std::byte{static_cast<unsigned char>(x + y * bounds.width)},
                std::byte{static_cast<unsigned char>(200 + y)});
        }
    }

    auto display = descriptor(L"single", bounds);
    FrozenDesktop desktop{
        snapshotFor({display}),
        std::vector<FrozenDisplay>{},
        std::chrono::steady_clock::now(),
    };
    desktop.displays.emplace_back(display, std::move(*source.value));

    MemoryBudget outputBudget(3U * 4U * 4U);
    auto result = composeSelection(PixelRect{2, 1, 3, 4}, desktop, outputBudget);

    const auto* output = std::get_if<PixelBuffer>(&result);
    CHECK(output != nullptr);
    if (output == nullptr) {
        return;
    }
    CHECK(output->width() == 3);
    CHECK(output->height() == 4);
    CHECK(output->stride() == 12U);
    for (std::int64_t y = 0; y < output->height(); ++y) {
        for (std::int64_t x = 0; x < output->width(); ++x) {
            const auto* pixel = pixelAt(*output, x, y);
            CHECK(pixel[0] == std::byte{static_cast<unsigned char>(x + 2)});
            CHECK(pixel[1] == std::byte{static_cast<unsigned char>(y + 1)});
            CHECK(pixel[2]
                == std::byte{static_cast<unsigned char>((x + 2) + (y + 1) * 8)});
            CHECK(pixel[3] == std::byte{static_cast<unsigned char>(201 + y)});
        }
    }
}

void fillDisplay(
    PixelBuffer& pixels,
    PixelRect bounds,
    unsigned char displayCode)
{
    for (std::int64_t y = 0; y < bounds.height; ++y) {
        for (std::int64_t x = 0; x < bounds.width; ++x) {
            const auto virtualX = bounds.x + x;
            const auto virtualY = bounds.y + y;
            setPixel(
                pixels,
                x,
                y,
                std::byte{static_cast<unsigned char>(virtualX + 20)},
                std::byte{static_cast<unsigned char>(virtualY + 30)},
                std::byte{displayCode},
                std::byte{255U});
        }
    }
}

void checkPixel(
    const PixelBuffer& pixels,
    std::int64_t x,
    std::int64_t y,
    std::byte blue,
    std::byte green,
    std::byte red,
    std::byte alpha)
{
    const auto* pixel = pixelAt(pixels, x, y);
    CHECK(pixel[0] == blue);
    CHECK(pixel[1] == green);
    CHECK(pixel[2] == red);
    CHECK(pixel[3] == alpha);
}

void testComposesAcrossNegativeCoordinatesAndLeavesDesktopHolesTransparent()
{
    constexpr PixelRect leftBounds{-4, 0, 4, 4};
    constexpr PixelRect rightBounds{2, 0, 4, 4};
    auto leftDescriptor = descriptor(L"left", leftBounds);
    auto rightDescriptor = descriptor(L"right", rightBounds);

    MemoryBudget sourceBudget(2U * 4U * 4U * 4U);
    auto left = PixelBuffer::allocate(4, 4, sourceBudget);
    auto right = PixelBuffer::allocate(4, 4, sourceBudget);
    CHECK(left.value != nullptr);
    CHECK(right.value != nullptr);
    if (!left.value || !right.value) {
        return;
    }
    fillDisplay(*left.value, leftBounds, 41U);
    fillDisplay(*right.value, rightBounds, 82U);

    FrozenDesktop desktop{
        snapshotFor({leftDescriptor, rightDescriptor}),
        std::vector<FrozenDisplay>{},
        std::chrono::steady_clock::now(),
    };
    desktop.displays.emplace_back(leftDescriptor, std::move(*left.value));
    desktop.displays.emplace_back(rightDescriptor, std::move(*right.value));

    MemoryBudget outputBudget(7U * 2U * 4U);
    auto result = composeSelection(PixelRect{-2, 1, 7, 2}, desktop, outputBudget);

    const auto* output = std::get_if<PixelBuffer>(&result);
    CHECK(output != nullptr);
    if (output == nullptr) {
        return;
    }
    CHECK(output->width() == 7);
    CHECK(output->height() == 2);
    CHECK(output->stride() == 28U);
    for (std::int64_t y = 0; y < 2; ++y) {
        checkPixel(
            *output,
            0,
            y,
            std::byte{18U},
            std::byte{static_cast<unsigned char>(31 + y)},
            std::byte{41U},
            std::byte{255U});
        checkPixel(
            *output,
            1,
            y,
            std::byte{19U},
            std::byte{static_cast<unsigned char>(31 + y)},
            std::byte{41U},
            std::byte{255U});
        for (std::int64_t x = 2; x < 4; ++x) {
            checkPixel(
                *output,
                x,
                y,
                std::byte{0U},
                std::byte{0U},
                std::byte{0U},
                std::byte{0U});
        }
        for (std::int64_t x = 4; x < 7; ++x) {
            checkPixel(
                *output,
                x,
                y,
                std::byte{static_cast<unsigned char>(18 + x)},
                std::byte{static_cast<unsigned char>(31 + y)},
                std::byte{82U},
                std::byte{255U});
        }
    }
}

const CaptureError* resultError(const SelectionCompositionResult& result)
{
    const auto* resultValue = std::get_if<CaptureError>(&result);
    CHECK(resultValue != nullptr);
    return resultValue;
}

void testRejectsNonPositiveSelections()
{
    const auto display = descriptor(L"display", PixelRect{0, 0, 1, 1});
    FrozenDesktop desktop{
        snapshotFor({display}),
        std::vector<FrozenDisplay>{},
        std::chrono::steady_clock::now(),
    };
    MemoryBudget budget(16U);

    for (const auto selection : {
             PixelRect{0, 0, 0, 1},
             PixelRect{0, 0, 1, 0},
             PixelRect{0, 0, -1, 1},
             PixelRect{0, 0, 1, -1},
         }) {
        const auto result = composeSelection(selection, desktop, budget);
        const auto* failure = resultError(result);
        if (failure != nullptr) {
            CHECK(failure->code == CaptureErrorCode::invalidSize);
            CHECK(failure->nativeCode == E_INVALIDARG);
        }
        CHECK(budget.usedBytes() == 0U);
    }
}

void testMapsOutputOverflowAndBudgetFailures()
{
    const auto display = descriptor(L"display", PixelRect{0, 0, 1, 1});
    FrozenDesktop desktop{
        snapshotFor({display}),
        std::vector<FrozenDisplay>{},
        std::chrono::steady_clock::now(),
    };

    MemoryBudget overflowBudget(std::numeric_limits<std::uint64_t>::max());
    const auto overflow = composeSelection(
        PixelRect{0, 0, std::numeric_limits<std::int64_t>::max(), 2},
        desktop,
        overflowBudget);
    const auto* overflowFailure = resultError(overflow);
    if (overflowFailure != nullptr) {
        CHECK(overflowFailure->code == CaptureErrorCode::arithmeticOverflow);
        CHECK(overflowFailure->nativeCode
            == HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    }
    CHECK(overflowBudget.usedBytes() == 0U);

    MemoryBudget smallBudget(15U);
    const auto overBudget = composeSelection(
        PixelRect{0, 0, 2, 2},
        desktop,
        smallBudget);
    const auto* budgetFailure = resultError(overBudget);
    if (budgetFailure != nullptr) {
        CHECK(budgetFailure->code == CaptureErrorCode::memoryLimit);
        CHECK(budgetFailure->nativeCode == E_OUTOFMEMORY);
    }
    CHECK(smallBudget.usedBytes() == 0U);
}

void testCompletelyDisjointSelectionIsTransparentAtRequestedSize()
{
    constexpr PixelRect bounds{-10, -10, 2, 2};
    const auto display = descriptor(L"far", bounds);
    MemoryBudget sourceBudget(16U);
    auto source = PixelBuffer::allocate(2, 2, sourceBudget);
    CHECK(source.value != nullptr);
    if (!source.value) {
        return;
    }
    fillDisplay(*source.value, bounds, 77U);

    FrozenDesktop desktop{
        snapshotFor({display}),
        std::vector<FrozenDisplay>{},
        std::chrono::steady_clock::now(),
    };
    desktop.displays.emplace_back(display, std::move(*source.value));

    MemoryBudget outputBudget(3U * 2U * 4U);
    const auto result = composeSelection(PixelRect{100, 200, 3, 2}, desktop, outputBudget);
    const auto* output = std::get_if<PixelBuffer>(&result);
    CHECK(output != nullptr);
    if (output == nullptr) {
        return;
    }
    CHECK(output->width() == 3);
    CHECK(output->height() == 2);
    CHECK(output->stride() == 12U);
    for (std::size_t index = 0; index < output->byteCount(); ++index) {
        CHECK(output->data()[index] == std::byte{0U});
    }
}

void testRejectsDescriptorAndPixelBufferSizeMismatchBeforeCopying()
{
    constexpr PixelRect claimedBounds{0, 0, 3, 2};
    const auto display = descriptor(L"mismatch", claimedBounds);
    MemoryBudget sourceBudget(2U * 2U * 4U);
    auto source = PixelBuffer::allocate(2, 2, sourceBudget);
    CHECK(source.value != nullptr);
    if (!source.value) {
        return;
    }

    FrozenDesktop desktop{
        snapshotFor({display}),
        std::vector<FrozenDisplay>{},
        std::chrono::steady_clock::now(),
    };
    desktop.displays.emplace_back(display, std::move(*source.value));

    MemoryBudget outputBudget(3U * 2U * 4U);
    const auto result = composeSelection(claimedBounds, desktop, outputBudget);
    const auto* failure = resultError(result);
    if (failure != nullptr) {
        CHECK(failure->code == CaptureErrorCode::invalidSize);
        CHECK(failure->nativeCode == E_INVALIDARG);
    }
    CHECK(outputBudget.usedBytes() == 0U);
}

void testRejectsCoordinateEndpointOverflow()
{
    const auto display = descriptor(L"display", PixelRect{0, 0, 1, 1});
    FrozenDesktop desktop{
        snapshotFor({display}),
        std::vector<FrozenDisplay>{},
        std::chrono::steady_clock::now(),
    };
    MemoryBudget budget(4U);

    const auto result = composeSelection(
        PixelRect{std::numeric_limits<std::int64_t>::max(), 0, 1, 1},
        desktop,
        budget);
    const auto* failure = resultError(result);
    if (failure != nullptr) {
        CHECK(failure->code == CaptureErrorCode::arithmeticOverflow);
        CHECK(failure->nativeCode
            == HRESULT_FROM_WIN32(ERROR_ARITHMETIC_OVERFLOW));
    }
    CHECK(budget.usedBytes() == 0U);
}

void testLaterFrozenDisplayOverwritesEarlierDisplay()
{
    constexpr PixelRect bounds{-1, -1, 2, 2};
    auto firstDescriptor = descriptor(L"first", bounds);
    auto secondDescriptor = descriptor(L"second", bounds);
    MemoryBudget sourceBudget(2U * 2U * 2U * 4U);
    auto first = PixelBuffer::allocate(2, 2, sourceBudget);
    auto second = PixelBuffer::allocate(2, 2, sourceBudget);
    CHECK(first.value != nullptr);
    CHECK(second.value != nullptr);
    if (!first.value || !second.value) {
        return;
    }
    fillDisplay(*first.value, bounds, 11U);
    fillDisplay(*second.value, bounds, 22U);

    FrozenDesktop desktop{
        snapshotFor({firstDescriptor, secondDescriptor}),
        std::vector<FrozenDisplay>{},
        std::chrono::steady_clock::now(),
    };
    desktop.displays.emplace_back(firstDescriptor, std::move(*first.value));
    desktop.displays.emplace_back(secondDescriptor, std::move(*second.value));

    MemoryBudget outputBudget(2U * 2U * 4U);
    const auto result = composeSelection(bounds, desktop, outputBudget);
    const auto* output = std::get_if<PixelBuffer>(&result);
    CHECK(output != nullptr);
    if (output == nullptr) {
        return;
    }
    for (std::int64_t y = 0; y < 2; ++y) {
        for (std::int64_t x = 0; x < 2; ++x) {
            CHECK(pixelAt(*output, x, y)[2] == std::byte{22U});
        }
    }
}

void testOutputBudgetReservationIsReleasedWithResult()
{
    const auto display = descriptor(L"display", PixelRect{0, 0, 1, 1});
    FrozenDesktop desktop{
        snapshotFor({display}),
        std::vector<FrozenDisplay>{},
        std::chrono::steady_clock::now(),
    };
    MemoryBudget budget(24U);
    {
        const auto result = composeSelection(PixelRect{10, 20, 3, 2}, desktop, budget);
        CHECK(std::holds_alternative<PixelBuffer>(result));
        CHECK(budget.usedBytes() == 24U);
    }
    CHECK(budget.usedBytes() == 0U);
}

} // namespace

int main()
{
    static_assert(!std::is_copy_constructible_v<SelectionCompositionResult>);
    static_assert(!std::is_copy_assignable_v<SelectionCompositionResult>);
    static_assert(std::is_move_constructible_v<SelectionCompositionResult>);

    testCropsOneFrozenDisplayInPhysicalPixels();
    testComposesAcrossNegativeCoordinatesAndLeavesDesktopHolesTransparent();
    testRejectsNonPositiveSelections();
    testMapsOutputOverflowAndBudgetFailures();
    testCompletelyDisjointSelectionIsTransparentAtRequestedSize();
    testRejectsDescriptorAndPixelBufferSizeMismatchBeforeCopying();
    testRejectsCoordinateEndpointOverflow();
    testLaterFrozenDisplayOverwritesEarlierDisplay();
    testOutputBudgetReservationIsReleasedWithResult();
    return failureCount == 0 ? 0 : 1;
}
