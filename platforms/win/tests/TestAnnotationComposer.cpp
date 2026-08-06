#include "export/AnnotationComposer.h"

#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <iostream>

namespace {

using namespace xxsnap::win;
using snipory::core::portable::MemoryBudget;
using snipory::core::portable::PixelBuffer;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

void testAnnotationsAreBurnedIntoExportPixels()
{
    MemoryBudget budget(1024U * 1024U);
    auto allocation = PixelBuffer::allocate(100, 80, budget);
    CHECK(allocation.value != nullptr);
    if (!allocation.value) {
        return;
    }
    std::memset(allocation.value->data(), 0xFF, allocation.value->byteCount());

    AnnotationStyle style;
    style.strokeColor = {255, 0, 0, 255};
    style.strokeWidthDip = 4.0F;
    AnnotationRenderPlan plan;
    plan.items.push_back({
        ShapeAnnotation{
            1,
            AnnotationKind::rectangle,
            {10.0F, 10.0F, 40.0F, 30.0F},
            style,
            0.0F,
        },
        false,
    });

    CHECK(!composeAnnotations(*allocation.value, plan, 96, 96).has_value());
    std::size_t changedPixels = 0;
    for (std::int64_t y = 0; y < allocation.value->height(); ++y) {
        const auto* row = allocation.value->data()
            + static_cast<std::uint64_t>(y) * allocation.value->stride();
        for (std::int64_t x = 0; x < allocation.value->width(); ++x) {
            const auto offset = static_cast<std::size_t>(x * 4);
            if (row[offset] != std::byte{0xFF}
                || row[offset + 1] != std::byte{0xFF}
                || row[offset + 2] != std::byte{0xFF}) {
                ++changedPixels;
            }
        }
    }
    CHECK(changedPixels > 100U);

    const auto* center = allocation.value->data()
        + 25U * allocation.value->stride() + 30U * 4U;
    CHECK(center[0] == std::byte{0xFF});
    CHECK(center[1] == std::byte{0xFF});
    CHECK(center[2] == std::byte{0xFF});
}

void testEmptyPlanLeavesPixelsUntouched()
{
    MemoryBudget budget(1024U);
    auto allocation = PixelBuffer::allocate(4, 4, budget);
    CHECK(allocation.value != nullptr);
    if (!allocation.value) {
        return;
    }
    std::memset(allocation.value->data(), 0x5A, allocation.value->byteCount());
    CHECK(!composeAnnotations(
        *allocation.value, AnnotationRenderPlan{}, 144, 144).has_value());
    for (std::size_t index = 0; index < allocation.value->byteCount(); ++index) {
        CHECK(allocation.value->data()[index] == std::byte{0x5A});
    }
}

} // namespace

int main()
{
    testAnnotationsAreBurnedIntoExportPixels();
    testEmptyPlanLeavesPixelsUntouched();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
