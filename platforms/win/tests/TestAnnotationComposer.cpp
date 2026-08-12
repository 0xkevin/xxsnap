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

void testNumberMarksAreBurnedIntoExportPixels()
{
    MemoryBudget budget(1024U * 1024U);
    auto allocation = PixelBuffer::allocate(220, 80, budget);
    CHECK(allocation.value != nullptr);
    if (!allocation.value) return;
    std::memset(allocation.value->data(), 0xFF, allocation.value->byteCount());
    AnnotationStyle style;
    style.strokeColor = {255, 0, 0, 255};
    style.textSize = 10.0F;
    AnnotationRenderPlan plan;
    ShapeAnnotation number;
    number.id = 1;
    number.kind = AnnotationKind::numberSequence;
    number.rect = numberMarkRect({40, 40}, 10.0F);
    number.style = style;
    number.numberMarkType = NumberMarkType::number;
    number.numberSequenceIndex = 123;
    number.numberSequenceGroupId = 1;
    plan.items.push_back({number, false});
    ShapeAnnotation checkMark = number;
    checkMark.id = 2;
    checkMark.rect = numberMarkRect({100, 40}, 10.0F);
    checkMark.numberMarkType = NumberMarkType::check;
    checkMark.numberSequenceIndex.reset();
    checkMark.numberSequenceGroupId = 0;
    plan.items.push_back({checkMark, false});
    ShapeAnnotation crossMark = checkMark;
    crossMark.id = 3;
    crossMark.rect = numberMarkRect({170, 40}, 10.0F);
    crossMark.numberMarkType = NumberMarkType::cross;
    plan.items.push_back({crossMark, false});
    CHECK(!composeAnnotations(*allocation.value, plan, 96, 96).has_value());
    std::size_t coloredPixels = 0U;
    for (std::int64_t y = 0; y < allocation.value->height(); ++y) {
        const auto* row = allocation.value->data()
            + static_cast<std::uint64_t>(y) * allocation.value->stride();
        for (std::int64_t x = 0; x < allocation.value->width(); ++x) {
            const auto offset = static_cast<std::size_t>(x * 4);
            if (std::to_integer<unsigned>(row[offset + 2U]) > 0xC0U
                && std::to_integer<unsigned>(row[offset + 1U]) < 0x80U) {
                ++coloredPixels;
            }
        }
    }
    CHECK(coloredPixels > 500U);
    std::size_t crossPixels = 0U;
    for (std::int64_t y = 15; y < 65; ++y) {
        const auto* row = allocation.value->data()
            + static_cast<std::uint64_t>(y) * allocation.value->stride();
        for (std::int64_t x = 145; x < 195; ++x) {
            const auto offset = static_cast<std::size_t>(x * 4);
            if (std::to_integer<unsigned>(row[offset + 2U]) > 0xC0U
                && std::to_integer<unsigned>(row[offset + 1U]) < 0x80U) {
                ++crossPixels;
            }
        }
    }
    CHECK(crossPixels > 30U);
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

void testMagnifierSamplesOriginalWithMacOffsetAndNearestFiltering()
{
    MemoryBudget budget(4U * 1024U * 1024U);
    auto raw = PixelBuffer::allocate(120, 80, budget);
    auto allocation = PixelBuffer::allocate(120, 80, budget);
    CHECK(raw.value != nullptr);
    CHECK(allocation.value != nullptr);
    if (!raw.value || !allocation.value) return;
    for (std::int64_t y = 0; y < raw.value->height(); ++y) {
        for (std::int64_t x = 0; x < raw.value->width(); ++x) {
            auto* pixel = raw.value->data()
                + static_cast<std::uint64_t>(y) * raw.value->stride()
                + static_cast<std::uint64_t>(x) * 4U;
            pixel[0] = static_cast<std::byte>(x);
            pixel[1] = static_cast<std::byte>(y);
            pixel[2] = std::byte{0};
            pixel[3] = std::byte{0xFF};
        }
    }
    std::memcpy(allocation.value->data(), raw.value->data(),
        raw.value->byteCount());
    AnnotationStyle red;
    red.fillEnabled = true;
    red.fillColor = {255, 0, 0, 255};
    red.strokeColor = red.fillColor;
    ShapeAnnotation cover;
    cover.id = 1;
    cover.kind = AnnotationKind::rectangle;
    cover.rect = {40, 20, 40, 40};
    cover.style = red;
    ShapeAnnotation magnifier;
    magnifier.id = 2;
    magnifier.kind = AnnotationKind::magnifier;
    magnifier.rect = {40, 20, 40, 40};
    magnifier.style.strokeColor = {0, 122, 255, 255};
    magnifier.style.strokeWidthDip = 2.0F;
    magnifier.magnifierShape = MagnifierShape::rectangle;
    magnifier.magnifierZoom = 2.0F;
    AnnotationRenderPlan plan;
    plan.items = {{cover, false}, {magnifier, false}};
    CHECK(!composeAnnotations(
        *allocation.value, plan, 96, 96, 0, 0, raw.value.get()).has_value());
    const auto* center = allocation.value->data()
        + 40U * allocation.value->stride() + 60U * 4U;
    CHECK(static_cast<unsigned>(center[0]) == 54U);
    CHECK(static_cast<unsigned>(center[1]) == 41U);
    CHECK(static_cast<unsigned>(center[2]) == 0U);

    auto fallback = PixelBuffer::allocate(120, 80, budget);
    CHECK(fallback.value != nullptr);
    if (!fallback.value) return;
    std::memcpy(fallback.value->data(), raw.value->data(),
        raw.value->byteCount());
    CHECK(!composeAnnotations(*fallback.value, plan, 96, 96).has_value());
    CHECK(std::memcmp(fallback.value->data(), allocation.value->data(),
        fallback.value->byteCount()) == 0);

    auto circle = PixelBuffer::allocate(120, 80, budget);
    CHECK(circle.value != nullptr);
    if (!circle.value) return;
    std::memcpy(circle.value->data(), raw.value->data(), raw.value->byteCount());
    magnifier.magnifierShape = MagnifierShape::circle;
    plan.items = {{magnifier, false}};
    CHECK(!composeAnnotations(
        *circle.value, plan, 96, 96, 0, 0, raw.value.get()).has_value());
    const auto* corner = circle.value->data()
        + 21U * circle.value->stride() + 41U * 4U;
    CHECK(corner[0] == std::byte{41});
    CHECK(corner[1] == std::byte{21});
    CHECK(corner[2] == std::byte{0});

    auto clipped = PixelBuffer::allocate(120, 80, budget);
    CHECK(clipped.value != nullptr);
    if (!clipped.value) return;
    std::memcpy(clipped.value->data(), raw.value->data(), raw.value->byteCount());
    magnifier.magnifierShape = MagnifierShape::rectangle;
    magnifier.rect = {-25, 20, 40, 40};
    magnifier.style.strokeWidthDip = 0.0F;
    plan.items = {{magnifier, false}};
    CHECK(!composeAnnotations(
        *clipped.value, plan, 96, 96, 0, 0, raw.value.get()).has_value());
    const auto* clippedLeft = clipped.value->data()
        + 40U * clipped.value->stride() + 2U * 4U;
    const auto* clippedInner = clipped.value->data()
        + 40U * clipped.value->stride() + 8U * 4U;
    CHECK(static_cast<unsigned>(clippedLeft[0]) == 1U);
    CHECK(static_cast<unsigned>(clippedInner[0]) == 4U);

    MemoryBudget scaledBudget(4U * 1024U * 1024U);
    auto scaledRaw = PixelBuffer::allocate(180, 120, scaledBudget);
    auto scaled = PixelBuffer::allocate(180, 120, scaledBudget);
    CHECK(scaledRaw.value != nullptr);
    CHECK(scaled.value != nullptr);
    if (!scaledRaw.value || !scaled.value) return;
    for (std::int64_t y = 0; y < scaledRaw.value->height(); ++y) {
        for (std::int64_t x = 0; x < scaledRaw.value->width(); ++x) {
            auto* pixel = scaledRaw.value->data()
                + static_cast<std::uint64_t>(y) * scaledRaw.value->stride()
                + static_cast<std::uint64_t>(x) * 4U;
            pixel[0] = static_cast<std::byte>(x);
            pixel[1] = static_cast<std::byte>(y);
            pixel[2] = std::byte{0};
            pixel[3] = std::byte{0xFF};
        }
    }
    std::memcpy(scaled.value->data(), scaledRaw.value->data(),
        scaledRaw.value->byteCount());
    magnifier.rect = {40, 20, 40, 40};
    plan.items = {{magnifier, false}};
    CHECK(!composeAnnotations(
        *scaled.value, plan, 144, 144, 0, 0,
        scaledRaw.value.get()).has_value());
    const auto* scaledCenter = scaled.value->data()
        + 60U * scaled.value->stride() + 90U * 4U;
    CHECK(static_cast<unsigned>(scaledCenter[0]) == 81U);
    CHECK(static_cast<unsigned>(scaledCenter[1]) == 62U);
}

void testEraserMaskClearsOnlyItsAffectedAnnotationLayer()
{
    MemoryBudget budget(2U * 1024U * 1024U);
    auto pixels = PixelBuffer::allocate(80, 80, budget);
    CHECK(pixels.value != nullptr);
    if (!pixels.value) return;
    std::memset(pixels.value->data(), 0xFF, pixels.value->byteCount());

    const auto filled = [](AnnotationId id, AnnotationRect rect,
                            AnnotationColor color) {
        ShapeAnnotation annotation;
        annotation.id = id;
        annotation.kind = AnnotationKind::rectangle;
        annotation.rect = rect;
        annotation.style.fillEnabled = true;
        annotation.style.fillColor = color;
        annotation.style.strokeColor = color;
        annotation.style.strokeWidthDip = 1.0F;
        return annotation;
    };
    AnnotationRenderPlan plan;
    plan.items = {
        {filled(1, {10, 10, 60, 60}, {255, 0, 0, 255}), false},
        {filled(2, {20, 20, 40, 40}, {0, 0, 255, 255}), false},
        {filled(3, {36, 36, 8, 8}, {0, 255, 0, 255}), false},
    };
    const std::vector<EraserMask> masks{{{30, 30, 20, 20}, {2}}};
    CHECK(!composeAnnotations(
        *pixels.value, plan, 96, 96, 0, 0, nullptr, masks).has_value());
    const auto pixelAt = [&pixels](int x, int y) {
        return pixels.value->data()
            + static_cast<std::size_t>(y) * pixels.value->stride()
            + static_cast<std::size_t>(x) * 4U;
    };
    const auto* blue = pixelAt(25, 25);
    CHECK(static_cast<unsigned>(blue[0]) == 255U);
    CHECK(static_cast<unsigned>(blue[1]) == 0U);
    CHECK(static_cast<unsigned>(blue[2]) == 0U);
    const auto* revealedRed = pixelAt(32, 32);
    CHECK(static_cast<unsigned>(revealedRed[0]) == 0U);
    CHECK(static_cast<unsigned>(revealedRed[1]) == 0U);
    CHECK(static_cast<unsigned>(revealedRed[2]) == 255U);
    const auto* laterGreen = pixelAt(40, 40);
    CHECK(static_cast<unsigned>(laterGreen[0]) == 0U);
    CHECK(static_cast<unsigned>(laterGreen[1]) == 255U);
    CHECK(static_cast<unsigned>(laterGreen[2]) == 0U);
}

void testEraserMasksMatchMacDpiAndCpuLayerSemantics()
{
    const auto filled = [](AnnotationId id, AnnotationRect rect,
                            AnnotationColor color) {
        ShapeAnnotation annotation;
        annotation.id = id;
        annotation.kind = AnnotationKind::rectangle;
        annotation.rect = rect;
        annotation.style.fillEnabled = true;
        annotation.style.fillColor = color;
        annotation.style.strokeColor = color;
        annotation.style.strokeWidthDip = 1.0F;
        return annotation;
    };
    const auto pixelAt = [](PixelBuffer& pixels, int x, int y) {
        return pixels.data() + static_cast<std::size_t>(y) * pixels.stride()
            + static_cast<std::size_t>(x) * 4U;
    };

    MemoryBudget d2dBudget(2U * 1024U * 1024U);
    auto d2d = PixelBuffer::allocate(120, 120, d2dBudget);
    CHECK(d2d.value != nullptr);
    if (!d2d.value) return;
    std::memset(d2d.value->data(), 0xFF, d2d.value->byteCount());
    AnnotationRenderPlan plan;
    plan.items = {
        {filled(1, {5, 5, 60, 60}, {255, 0, 0, 255}), false},
        {filled(2, {5, 5, 60, 60}, {0, 0, 255, 255}), false},
        {filled(3, {24, 24, 4, 4}, {0, 255, 0, 255}), false},
    };
    const std::vector<EraserMask> d2dMasks{{{20, 20, 10, 10}, {1, 2}}};
    CHECK(!composeAnnotations(
        *d2d.value, plan, 144, 144, 0, 0, nullptr, d2dMasks).has_value());
    const auto* oneDipExpanded = pixelAt(*d2d.value, 28, 40);
    CHECK(oneDipExpanded[0] == std::byte{0xFF});
    CHECK(oneDipExpanded[1] == std::byte{0xFF});
    CHECK(oneDipExpanded[2] == std::byte{0xFF});
    const auto* outsideMask = pixelAt(*d2d.value, 70, 40);
    CHECK(outsideMask[0] == std::byte{0xFF});
    CHECK(outsideMask[1] == std::byte{0});
    CHECK(outsideMask[2] == std::byte{0});
    const auto* laterLayer = pixelAt(*d2d.value, 39, 39);
    CHECK(laterLayer[0] == std::byte{0});
    CHECK(laterLayer[1] == std::byte{0xFF});
    CHECK(laterLayer[2] == std::byte{0});

    MemoryBudget markerBudget(2U * 1024U * 1024U);
    auto markerPixels = PixelBuffer::allocate(120, 90, markerBudget);
    CHECK(markerPixels.value != nullptr);
    if (!markerPixels.value) return;
    std::memset(markerPixels.value->data(), 0xFF,
        markerPixels.value->byteCount());
    AnnotationStyle markerStyle;
    markerStyle.strokeColor = {179, 235, 0, 255};
    markerStyle.strokeWidthDip = 14.0F;
    const MarkerLine markerLine{{10, 30}, {70, 30}};
    ShapeAnnotation marker{
        4, AnnotationKind::marker, markerLineBounds(markerLine), markerStyle,
        0, std::nullopt, std::nullopt, markerLine};
    plan.items = {{marker, false}};
    const std::vector<EraserMask> markerMasks{{{30, 25, 10, 10}, {4}}};
    CHECK(!composeAnnotations(*markerPixels.value, plan,
        144, 144, 0, 0, nullptr, markerMasks).has_value());
    const auto* erasedMarker = pixelAt(*markerPixels.value, 50, 45);
    CHECK(erasedMarker[0] == std::byte{0xFF});
    CHECK(erasedMarker[1] == std::byte{0xFF});
    CHECK(erasedMarker[2] == std::byte{0xFF});
    const auto* visibleMarker = pixelAt(*markerPixels.value, 25, 45);
    CHECK(visibleMarker[1] != std::byte{0xFF}
        || visibleMarker[2] != std::byte{0xFF});

    MemoryBudget mosaicBudget(2U * 1024U * 1024U);
    auto mosaicPixels = PixelBuffer::allocate(100, 80, mosaicBudget);
    CHECK(mosaicPixels.value != nullptr);
    if (!mosaicPixels.value) return;
    fillTestGradient(*mosaicPixels.value);
    std::vector<std::byte> mosaicOriginal(mosaicPixels.value->data(),
        mosaicPixels.value->data() + mosaicPixels.value->byteCount());
    ShapeAnnotation mosaic;
    mosaic.id = 5;
    mosaic.kind = AnnotationKind::mosaicRectangle;
    mosaic.rect = {10, 10, 40, 30};
    mosaic.mosaicRedaction = MosaicRedaction{
        MosaicRedactionType::pixelMosaic, 8};
    plan.items = {{mosaic, false}};
    const std::vector<EraserMask> mosaicMasks{{{20, 15, 8, 8}, {5}}};
    CHECK(!composeAnnotations(*mosaicPixels.value, plan,
        96, 96, 0, 0, nullptr, mosaicMasks).has_value());
    const auto erasedMosaicOffset = 18U * mosaicPixels.value->stride()
        + 24U * 4U;
    CHECK(std::memcmp(mosaicPixels.value->data() + erasedMosaicOffset,
        mosaicOriginal.data() + erasedMosaicOffset, 4U) == 0);
    const auto visibleMosaicOffset = 12U * mosaicPixels.value->stride()
        + 12U * 4U;
    CHECK(std::memcmp(mosaicPixels.value->data() + visibleMosaicOffset,
        mosaicOriginal.data() + visibleMosaicOffset, 4U) != 0);

    MemoryBudget magnifierBudget(4U * 1024U * 1024U);
    auto raw = PixelBuffer::allocate(120, 80, magnifierBudget);
    auto magnified = PixelBuffer::allocate(120, 80, magnifierBudget);
    CHECK(raw.value != nullptr);
    CHECK(magnified.value != nullptr);
    if (!raw.value || !magnified.value) return;
    fillTestGradient(*raw.value);
    std::memcpy(magnified.value->data(), raw.value->data(),
        raw.value->byteCount());
    ShapeAnnotation magnifier;
    magnifier.id = 6;
    magnifier.kind = AnnotationKind::magnifier;
    magnifier.rect = {40, 20, 40, 40};
    magnifier.style.strokeWidthDip = 2.0F;
    magnifier.magnifierShape = MagnifierShape::rectangle;
    magnifier.magnifierZoom = 2.0F;
    plan.items = {{magnifier, false}};
    const std::vector<EraserMask> magnifierMasks{{{55, 35, 10, 10}, {6}}};
    CHECK(!composeAnnotations(*magnified.value, plan,
        96, 96, 0, 0, raw.value.get(), magnifierMasks).has_value());
    CHECK(std::memcmp(pixelAt(*magnified.value, 60, 40),
        pixelAt(*raw.value, 60, 40), 4U) == 0);
    CHECK(std::memcmp(pixelAt(*magnified.value, 45, 25),
        pixelAt(*raw.value, 45, 25), 4U) != 0);
}

} // namespace

int main()
{
    testAnnotationsAreBurnedIntoExportPixels();
    testEmptyPlanLeavesPixelsUntouched();
    testNumberMarksAreBurnedIntoExportPixels();
    testMarkerUsesMultiplyAndDarkBackgroundFallback();
    testMarkerBatchingPreservesAnnotationOrder();
    testMosaicPixelAndGaussianRespectMasksAndOrder();
    testMagnifierSamplesOriginalWithMacOffsetAndNearestFiltering();
    testEraserMaskClearsOnlyItsAffectedAnnotationLayer();
    testEraserMasksMatchMacDpiAndCpuLayerSemantics();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
