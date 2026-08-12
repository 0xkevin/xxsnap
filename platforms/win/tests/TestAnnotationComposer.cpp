#include "export/AnnotationComposer.h"

#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <vector>

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

void testMarkerUsesMultiplyAndDarkBackgroundFallback()
{
    MemoryBudget budget(1024U * 1024U);
    auto white = PixelBuffer::allocate(120, 80, budget);
    CHECK(white.value != nullptr);
    if (!white.value) {
        return;
    }
    std::memset(white.value->data(), 0xFF, white.value->byteCount());
    for (std::int64_t x = 55; x <= 65; ++x) {
        auto* pixel = white.value->data()
            + 30U * white.value->stride() + static_cast<std::uint64_t>(x) * 4U;
        pixel[0] = std::byte{0};
        pixel[1] = std::byte{0};
        pixel[2] = std::byte{0};
        pixel[3] = std::byte{0xFF};
    }
    AnnotationStyle style;
    style.strokeColor = {179, 235, 0, 255};
    style.strokeWidthDip = 18.0F;
    AnnotationRenderPlan plan;
    const MarkerLine line{{10, 30}, {110, 30}};
    plan.items.push_back({ShapeAnnotation{
        1, AnnotationKind::marker, markerLineBounds(line), style, 0,
        std::nullopt, std::nullopt, line}, false});
    CHECK(!composeAnnotations(*white.value, plan, 96, 96).has_value());
    const auto* highlightedWhite = white.value->data()
        + 30U * white.value->stride() + 30U * 4U;
    CHECK(static_cast<unsigned>(highlightedWhite[1]) > 220U);
    CHECK(static_cast<unsigned>(highlightedWhite[2]) > 170U);
    CHECK(static_cast<unsigned>(highlightedWhite[0]) < 80U);
    const auto* highlightedText = white.value->data()
        + 30U * white.value->stride() + 60U * 4U;
    CHECK(highlightedText[0] == std::byte{0});
    CHECK(highlightedText[1] == std::byte{0});
    CHECK(highlightedText[2] == std::byte{0});

    MemoryBudget darkBudget(1024U * 1024U);
    auto dark = PixelBuffer::allocate(120, 80, darkBudget);
    CHECK(dark.value != nullptr);
    if (!dark.value) {
        return;
    }
    std::memset(dark.value->data(), 0, dark.value->byteCount());
    for (std::int64_t y = 0; y < dark.value->height(); ++y) {
        for (std::int64_t x = 0; x < dark.value->width(); ++x) {
            dark.value->data()[static_cast<std::uint64_t>(y) * dark.value->stride()
                + static_cast<std::uint64_t>(x) * 4U + 3U] = std::byte{0xFF};
        }
    }
    style.strokeColor = {0, 0, 0, 255};
    plan.items[0].annotation.style = style;
    CHECK(!composeAnnotations(*dark.value, plan, 96, 96).has_value());
    const auto* visible = dark.value->data()
        + 30U * dark.value->stride() + 60U * 4U;
    CHECK(static_cast<unsigned>(visible[0]) > 180U);
    CHECK(static_cast<unsigned>(visible[1]) > 180U);
    CHECK(static_cast<unsigned>(visible[2]) > 180U);
}

void testMarkerBatchingPreservesAnnotationOrder()
{
    const auto composeAtCenter = [](bool markerFirst) {
        MemoryBudget budget(1024U * 1024U);
        auto allocation = PixelBuffer::allocate(80, 60, budget);
        if (!allocation.value) {
            return 0U;
        }
        std::memset(
            allocation.value->data(), 0xFF, allocation.value->byteCount());

        AnnotationStyle markerStyle;
        markerStyle.strokeColor = {179, 235, 0, 255};
        markerStyle.strokeWidthDip = 18.0F;
        const MarkerLine line{{10, 30}, {70, 30}};
        AnnotationRenderItem markerItem{ShapeAnnotation{
            1, AnnotationKind::marker, markerLineBounds(line), markerStyle, 0,
            std::nullopt, std::nullopt, line}, false};

        AnnotationStyle rectangleStyle;
        rectangleStyle.strokeColor = {255, 0, 0, 255};
        rectangleStyle.fillColor = rectangleStyle.strokeColor;
        rectangleStyle.fillEnabled = true;
        AnnotationRenderItem rectangleItem{ShapeAnnotation{
            2, AnnotationKind::rectangle, {20, 20, 40, 20},
            rectangleStyle, 0}, false};

        AnnotationRenderPlan plan;
        plan.items = markerFirst
            ? std::vector<AnnotationRenderItem>{markerItem, rectangleItem}
            : std::vector<AnnotationRenderItem>{rectangleItem, markerItem};
        if (composeAnnotations(*allocation.value, plan, 96, 96).has_value()) {
            return 0U;
        }
        const auto* center = allocation.value->data()
            + 30U * allocation.value->stride() + 40U * 4U;
        return static_cast<unsigned>(center[2]);
    };

    CHECK(composeAtCenter(true) == 255U);
    const auto markerOverRectangleRed = composeAtCenter(false);
    CHECK(markerOverRectangleRed > 170U);
    CHECK(markerOverRectangleRed < 230U);
}

void fillTestGradient(PixelBuffer& pixels)
{
    for (std::int64_t y = 0; y < pixels.height(); ++y) {
        for (std::int64_t x = 0; x < pixels.width(); ++x) {
            auto* pixel = pixels.data()
                + static_cast<std::uint64_t>(y) * pixels.stride()
                + static_cast<std::uint64_t>(x) * 4U;
            pixel[0] = static_cast<std::byte>((x * 7 + y * 3) % 256);
            pixel[1] = static_cast<std::byte>((x * 2 + y * 9) % 256);
            pixel[2] = static_cast<std::byte>((x * 11 + y) % 256);
            pixel[3] = std::byte{0xFF};
        }
    }
}

void testMosaicPixelAndGaussianRespectMasksAndOrder()
{
    MemoryBudget budget(4U * 1024U * 1024U);
    auto pixelated = PixelBuffer::allocate(80, 60, budget);
    CHECK(pixelated.value != nullptr);
    if (!pixelated.value) {
        return;
    }
    fillTestGradient(*pixelated.value);
    std::vector<std::byte> original(
        pixelated.value->data(),
        pixelated.value->data() + pixelated.value->byteCount());

    ShapeAnnotation rectangle;
    rectangle.id = 1;
    rectangle.kind = AnnotationKind::mosaicRectangle;
    rectangle.rect = {20, 15, 35, 25};
    rectangle.mosaicRedaction = MosaicRedaction{
        MosaicRedactionType::pixelMosaic, 8};
    AnnotationRenderPlan plan;
    plan.items.push_back({rectangle, false});
    CHECK(!composeAnnotations(*pixelated.value, plan, 96, 96).has_value());
    const auto outsideOffset = 4U * pixelated.value->stride() + 4U * 4U;
    CHECK(std::memcmp(pixelated.value->data() + outsideOffset,
        original.data() + outsideOffset, 4U) == 0);
    const auto insideOffset = 25U * pixelated.value->stride() + 30U * 4U;
    CHECK(std::memcmp(pixelated.value->data() + insideOffset,
        original.data() + insideOffset, 4U) != 0);

    auto blurred = PixelBuffer::allocate(80, 60, budget);
    CHECK(blurred.value != nullptr);
    if (!blurred.value) {
        return;
    }
    fillTestGradient(*blurred.value);
    MosaicStroke stroke{{{10, 30}, {70, 30}}};
    ShapeAnnotation brush;
    brush.id = 2;
    brush.kind = AnnotationKind::mosaicStroke;
    brush.rect = brushPathBounds(stroke);
    brush.style.strokeWidthDip = 15.0F;
    brush.mosaicStroke = stroke;
    brush.mosaicRedaction = MosaicRedaction{
        MosaicRedactionType::gaussianBlur, 8};
    plan.items = {{brush, false}};
    CHECK(!composeAnnotations(*blurred.value, plan, 96, 96).has_value());
    const auto strokeOffset = 30U * blurred.value->stride() + 40U * 4U;
    const auto untouchedOffset = 5U * blurred.value->stride() + 40U * 4U;
    CHECK(std::memcmp(blurred.value->data() + strokeOffset,
        original.data() + strokeOffset, 4U) != 0);
    CHECK(std::memcmp(blurred.value->data() + untouchedOffset,
        original.data() + untouchedOffset, 4U) == 0);

    auto ordered = PixelBuffer::allocate(80, 60, budget);
    CHECK(ordered.value != nullptr);
    if (!ordered.value) {
        return;
    }
    fillTestGradient(*ordered.value);
    AnnotationStyle red;
    red.fillEnabled = true;
    red.fillColor = {255, 0, 0, 255};
    red.strokeColor = red.fillColor;
    ShapeAnnotation redRectangle;
    redRectangle.id = 3;
    redRectangle.kind = AnnotationKind::rectangle;
    redRectangle.rect = {20, 15, 35, 25};
    redRectangle.style = red;
    plan.items = {{redRectangle, false}, {rectangle, false}};
    CHECK(!composeAnnotations(*ordered.value, plan, 96, 96).has_value());
    const auto* orderedPixel = ordered.value->data() + insideOffset;
    const auto* pixelOnly = pixelated.value->data() + insideOffset;
    CHECK(std::memcmp(orderedPixel, pixelOnly, 4U) != 0);
}

} // namespace

int main()
{
    testAnnotationsAreBurnedIntoExportPixels();
    testEmptyPlanLeavesPixelsUntouched();
    testMarkerUsesMultiplyAndDarkBackgroundFallback();
    testMarkerBatchingPreservesAnnotationOrder();
    testMosaicPixelAndGaussianRespectMasksAndOrder();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
