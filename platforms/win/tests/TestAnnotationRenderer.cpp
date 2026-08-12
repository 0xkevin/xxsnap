#include "annotation/AnnotationRenderer.h"

#include <Windows.h>
#include <d2d1.h>
#include <objbase.h>
#include <wincodec.h>

#include <array>
#include <cmath>
#include <cstdlib>
#include <iostream>

namespace {

using namespace xxsnap::win;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

void testPlanUsesSelectionLocalCoordinatesAndLivePreview()
{
    AnnotationDocument document;
    const auto rectangle = document.addShape(
        AnnotationKind::rectangle, {10, 20, 80, 40});
    const auto ellipse = document.addShape(
        AnnotationKind::ellipse, {100, 40, 50, 60});
    CHECK(document.select(rectangle));

    ShapeAnnotation preview{
        invalidAnnotationId,
        AnnotationKind::rectangle,
        {20, 30, 40, 20},
        primaryShapeActivationStyle({}),
        0,
    };
    const auto plan = buildAnnotationRenderPlan(
        document, preview, {200, 100}, true);

    CHECK(plan.items.size() == 3U);
    CHECK((plan.items[0].annotation.rect == AnnotationRect{210, 120, 80, 40}));
    CHECK(plan.items[0].annotation.id == rectangle);
    CHECK(!plan.items[0].isPreview);
    CHECK(plan.items[1].annotation.id == ellipse);
    CHECK(plan.items[2].isPreview);
    CHECK((plan.items[2].annotation.rect == AnnotationRect{220, 130, 40, 20}));
    CHECK(plan.resizeHandles.size() == 8U);
    CHECK((plan.resizeHandles[0] == AnnotationPoint{210, 120}));
    CHECK((plan.resizeHandles[7] == AnnotationPoint{290, 160}));
    CHECK(plan.rotationHandle.has_value());
    CHECK((plan.rotationHandle.value() == AnnotationPoint{250, 106}));
}

void testEditingPreviewReplacesCommittedShape()
{
    AnnotationDocument document;
    const auto rectangle = document.addShape(
        AnnotationKind::rectangle, {10, 20, 80, 40});
    CHECK(document.select(rectangle));

    auto preview = *document.find(rectangle);
    preview.rect = {30, 40, 80, 40};
    const auto plan = buildAnnotationRenderPlan(
        document, preview, {200, 100}, true);

    CHECK(plan.items.size() == 1U);
    CHECK(plan.items[0].isPreview);
    CHECK(plan.items[0].annotation.id == rectangle);
    CHECK((plan.items[0].annotation.rect == AnnotationRect{230, 140, 80, 40}));
    CHECK(plan.resizeHandles.size() == 8U);
    CHECK((plan.resizeHandles[0] == AnnotationPoint{230, 140}));
    CHECK((plan.resizeHandles[7] == AnnotationPoint{310, 180}));
}

void testArrowLinePlanTranslatesCurveAndUsesThreeEditingHandles()
{
    AnnotationDocument document;
    const auto id = document.addArrowLine({
        {10, 20}, {110, 80}, {60, 15},
        ArrowType::dot, ArrowType::normal});
    CHECK(id != invalidAnnotationId);
    const auto plan = buildAnnotationRenderPlan(
        document, std::nullopt, {200, 100}, true);
    CHECK(plan.items.size() == 1U);
    CHECK(plan.items[0].annotation.arrowLine.has_value());
    CHECK((plan.items[0].annotation.arrowLine->start
        == AnnotationPoint{210, 120}));
    CHECK((plan.items[0].annotation.arrowLine->control
        == AnnotationPoint{260, 115}));
    CHECK((plan.items[0].annotation.arrowLine->end
        == AnnotationPoint{310, 180}));
    CHECK(plan.resizeHandles.empty());
    CHECK(plan.lineHandles.size() == 3U);
    CHECK((plan.lineHandles[0] == AnnotationPoint{210, 120}));
    CHECK((plan.lineHandles[1] == AnnotationPoint{310, 180}));
    CHECK((plan.lineHandles[2] == AnnotationPoint{260, 115}));
    CHECK(!plan.rotationHandle.has_value());
}

void testBrushPlanTranslatesPathAndUsesInsetEndpointHandles()
{
    AnnotationDocument document;
    AnnotationStyle style;
    style.strokeWidthDip = 5.0F;
    const auto id = document.addBrushPath(
        BrushPath{{{10, 20}, {40, 20}, {70, 50}}}, style);
    CHECK(id != invalidAnnotationId);
    CHECK(document.select(id));
    const auto plan = buildAnnotationRenderPlan(
        document, std::nullopt, {200, 100}, true);
    CHECK(plan.items.size() == 1U);
    CHECK(plan.items[0].annotation.brushPath.has_value());
    CHECK((plan.items[0].annotation.brushPath->points.front()
        == AnnotationPoint{210, 120}));
    CHECK((plan.items[0].annotation.brushPath->points.back()
        == AnnotationPoint{270, 150}));
    CHECK(plan.resizeHandles.empty());
    CHECK(plan.lineHandles.size() == 2U);
    CHECK((plan.lineHandles.front() == AnnotationPoint{219, 120}));
    CHECK(plan.lineHandles.back().x > 263.0F);
    CHECK(plan.lineHandles.back().y > 143.0F);
    CHECK(!plan.rotationHandle.has_value());
}

void testMarkerPlanTranslatesLineAndUsesInsetEndpointHandles()
{
    AnnotationDocument document;
    AnnotationStyle style;
    style.strokeWidthDip = 18.0F;
    const auto id = document.addMarkerLine({{10, 20}, {110, 20}}, style);
    CHECK(id != invalidAnnotationId);
    const auto plan = buildAnnotationRenderPlan(
        document, std::nullopt, {200, 100}, true);
    CHECK(plan.items.size() == 1U);
    CHECK((plan.items[0].annotation.markerLine.value()
        == MarkerLine{{210, 120}, {310, 120}}));
    CHECK(plan.resizeHandles.empty());
    CHECK(plan.lineHandles.size() == 2U);
    CHECK((plan.lineHandles[0] == AnnotationPoint{224, 120}));
    CHECK((plan.lineHandles[1] == AnnotationPoint{296, 120}));
    CHECK(!plan.rotationHandle.has_value());
}

void testMacDashPatternsAreAbsoluteDips()
{
    CHECK(strokeDashPattern(AnnotationStrokePattern::solid, 4).empty());
    CHECK(strokeDashPattern(AnnotationStrokePattern::sketchSolid, 4).empty());
    CHECK(strokeDashPattern(AnnotationStrokePattern::dashLong, 4)
        == std::vector<float>({12.0F, 6.4F}));
    CHECK(strokeDashPattern(AnnotationStrokePattern::dashNarrow, 4)
        == std::vector<float>({0.1F, 8.8F}));
    CHECK(strokeDashPattern(AnnotationStrokePattern::dashLongShort, 2)
        == std::vector<float>({8.0F, 4.0F, 0.1F, 4.0F}));
    CHECK(strokeDashPattern(AnnotationStrokePattern::sketchDashed, 7)
        == std::vector<float>({21.0F, 11.2F}));

    CHECK(normalizedStrokeDashPattern(AnnotationStrokePattern::dashLong, 2)
        == std::vector<float>({4.0F, 2.0F}));
    CHECK(normalizedStrokeDashPattern(AnnotationStrokePattern::dashNarrow, 2)
        == std::vector<float>({0.05F, 2.5F}));
}

void testStrokeMenuSketchSampleUsesExactMacJitter()
{
    const auto points = sketchStrokeSamplePoints({10, 10}, {80, 10}, 2.0F);
    CHECK(points.size() == 11U);
    CHECK(std::fabs(points[0].x - 10.036321F) < 0.0001F);
    CHECK(std::fabs(points[0].y - 9.558242F) < 0.0001F);
    CHECK(std::fabs(points[1].x - 16.986456F) < 0.0001F);
    CHECK(std::fabs(points[1].y - 10.640533F) < 0.0001F);
    CHECK(std::fabs(points[10].x - 80.354240F) < 0.0001F);
    CHECK(std::fabs(points[10].y - 10.536848F) < 0.0001F);
}

struct SnapshotResources {
    ID2D1Factory* d2dFactory = nullptr;
    IWICImagingFactory* wicFactory = nullptr;
    IWICBitmap* bitmap = nullptr;
    ID2D1RenderTarget* target = nullptr;

    ~SnapshotResources()
    {
        if (target != nullptr) {
            target->Release();
        }
        if (bitmap != nullptr) {
            bitmap->Release();
        }
        if (wicFactory != nullptr) {
            wicFactory->Release();
        }
        if (d2dFactory != nullptr) {
            d2dFactory->Release();
        }
    }
};

struct ArrowSnapshot {
    std::uint64_t checksum = 0U;
    std::uint32_t opaquePixels = 0U;
    std::uint32_t startPixels = 0U;
    std::uint32_t endPixels = 0U;
};

bool renderArrowSnapshot(
    std::uint32_t dpi,
    ArrowType startType,
    ArrowType endType,
    AnnotationStrokePattern pattern,
    ArrowSnapshot& snapshot)
{
    SnapshotResources resources;
    if (FAILED(D2D1CreateFactory(
            D2D1_FACTORY_TYPE_SINGLE_THREADED,
            &resources.d2dFactory))) {
        return false;
    }
    if (FAILED(CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&resources.wicFactory)))) {
        return false;
    }

    constexpr std::uint32_t logicalWidth = 240U;
    constexpr std::uint32_t logicalHeight = 160U;
    const auto pixelWidth = logicalWidth * dpi / 96U;
    const auto pixelHeight = logicalHeight * dpi / 96U;
    if (FAILED(resources.wicFactory->CreateBitmap(
            pixelWidth,
            pixelHeight,
            GUID_WICPixelFormat32bppPBGRA,
            WICBitmapCacheOnLoad,
            &resources.bitmap))) {
        return false;
    }
    const auto properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_SOFTWARE,
        D2D1::PixelFormat(
            DXGI_FORMAT_B8G8R8A8_UNORM,
            D2D1_ALPHA_MODE_PREMULTIPLIED),
        static_cast<float>(dpi),
        static_cast<float>(dpi));
    if (FAILED(resources.d2dFactory->CreateWicBitmapRenderTarget(
            resources.bitmap,
            properties,
            &resources.target))) {
        return false;
    }

    AnnotationStyle style;
    style.strokeColor = {255, 0, 0, 255};
    style.strokeWidthDip = 4.0F;
    style.strokePattern = pattern;
    const ArrowLine line{
        {30, 80},
        {210, 80},
        {120, 35},
        startType,
        endType,
    };
    AnnotationRenderPlan plan;
    plan.items.push_back({
        ShapeAnnotation{
            1,
            AnnotationKind::arrowLine,
            arrowLineBounds(line),
            style,
            0.0F,
            line,
        },
        false,
    });

    resources.target->BeginDraw();
    resources.target->Clear(D2D1::ColorF(0, 0));
    AnnotationRenderer renderer(resources.d2dFactory);
    if (FAILED(renderer.draw(resources.target, plan))
        || FAILED(resources.target->EndDraw())) {
        return false;
    }

    const WICRect lockRect{
        0,
        0,
        static_cast<INT>(pixelWidth),
        static_cast<INT>(pixelHeight),
    };
    IWICBitmapLock* lock = nullptr;
    if (FAILED(resources.bitmap->Lock(&lockRect, WICBitmapLockRead, &lock))) {
        return false;
    }
    UINT byteCount = 0U;
    UINT stride = 0U;
    BYTE* bytes = nullptr;
    const auto dataResult = lock->GetDataPointer(&byteCount, &bytes);
    const auto strideResult = lock->GetStride(&stride);
    if (FAILED(dataResult) || FAILED(strideResult)
        || byteCount < stride * pixelHeight) {
        lock->Release();
        return false;
    }

    snapshot = {};
    const auto scale = static_cast<float>(dpi) / 96.0F;
    const auto startX = 30.0F * scale;
    const auto endX = 210.0F * scale;
    const auto centerY = 80.0F * scale;
    const auto radius = 18.0F * scale;
    for (std::uint32_t y = 0U; y < pixelHeight; ++y) {
        for (std::uint32_t x = 0U; x < pixelWidth; ++x) {
            const auto* pixel = bytes + y * stride + x * 4U;
            if (pixel[3] == 0U) {
                continue;
            }
            ++snapshot.opaquePixels;
            snapshot.checksum += static_cast<std::uint64_t>(pixel[3])
                * (1U + x + y * pixelWidth);
            const auto dxStart = static_cast<float>(x) - startX;
            const auto dxEnd = static_cast<float>(x) - endX;
            const auto dy = static_cast<float>(y) - centerY;
            if (dxStart * dxStart + dy * dy <= radius * radius) {
                ++snapshot.startPixels;
            }
            if (dxEnd * dxEnd + dy * dy <= radius * radius) {
                ++snapshot.endPixels;
            }
        }
    }
    lock->Release();
    return snapshot.opaquePixels > 0U;
}

bool renderStrokeSnapshot(
    std::uint32_t dpi,
    AnnotationKind kind,
    AnnotationStrokePattern pattern,
    ArrowSnapshot& snapshot)
{
    SnapshotResources resources;
    if (FAILED(D2D1CreateFactory(
            D2D1_FACTORY_TYPE_SINGLE_THREADED,
            &resources.d2dFactory))) {
        return false;
    }
    if (FAILED(CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&resources.wicFactory)))) {
        return false;
    }
    constexpr std::uint32_t logicalWidth = 240U;
    constexpr std::uint32_t logicalHeight = 160U;
    const auto pixelWidth = logicalWidth * dpi / 96U;
    const auto pixelHeight = logicalHeight * dpi / 96U;
    if (FAILED(resources.wicFactory->CreateBitmap(
            pixelWidth, pixelHeight,
            GUID_WICPixelFormat32bppPBGRA,
            WICBitmapCacheOnLoad,
            &resources.bitmap))) {
        return false;
    }
    const auto properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_SOFTWARE,
        D2D1::PixelFormat(
            DXGI_FORMAT_B8G8R8A8_UNORM,
            D2D1_ALPHA_MODE_PREMULTIPLIED),
        static_cast<float>(dpi),
        static_cast<float>(dpi));
    if (FAILED(resources.d2dFactory->CreateWicBitmapRenderTarget(
            resources.bitmap, properties, &resources.target))) {
        return false;
    }

    AnnotationStyle style;
    style.strokeColor = {255, 0, 0, 255};
    style.strokeWidthDip = kind == AnnotationKind::marker ? 18.0F : 5.0F;
    style.strokePattern = pattern;
    const BrushPath path{{
        {20, 110}, {50, 70}, {85, 100}, {120, 45},
        {155, 90}, {190, 55}, {220, 85},
    }};
    const MarkerLine marker{{20, 110}, {220, 50}};
    ShapeAnnotation annotation;
    annotation.id = 1;
    annotation.kind = kind;
    annotation.style = style;
    if (kind == AnnotationKind::marker) {
        annotation.rect = markerLineBounds(marker);
        annotation.markerLine = marker;
    } else {
        annotation.rect = brushPathBounds(path);
        annotation.brushPath = path;
    }
    AnnotationRenderPlan plan;
    plan.items.push_back({annotation, false});
    resources.target->BeginDraw();
    resources.target->Clear(D2D1::ColorF(0, 0));
    AnnotationRenderer renderer(resources.d2dFactory);
    if (FAILED(renderer.draw(resources.target, plan))
        || FAILED(resources.target->EndDraw())) {
        return false;
    }

    const WICRect lockRect{
        0, 0,
        static_cast<INT>(pixelWidth),
        static_cast<INT>(pixelHeight),
    };
    IWICBitmapLock* lock = nullptr;
    if (FAILED(resources.bitmap->Lock(&lockRect, WICBitmapLockRead, &lock))) {
        return false;
    }
    UINT byteCount = 0U;
    UINT stride = 0U;
    BYTE* bytes = nullptr;
    const auto dataResult = lock->GetDataPointer(&byteCount, &bytes);
    const auto strideResult = lock->GetStride(&stride);
    if (FAILED(dataResult) || FAILED(strideResult)
        || byteCount < stride * pixelHeight) {
        lock->Release();
        return false;
    }
    snapshot = {};
    for (std::uint32_t y = 0U; y < pixelHeight; ++y) {
        for (std::uint32_t x = 0U; x < pixelWidth; ++x) {
            const auto* pixel = bytes + y * stride + x * 4U;
            if (pixel[3] == 0U) {
                continue;
            }
            ++snapshot.opaquePixels;
            snapshot.checksum += static_cast<std::uint64_t>(pixel[3])
                * (1U + x + y * pixelWidth);
        }
    }
    lock->Release();
    return snapshot.opaquePixels > 0U;
}

bool sampleCenterAtDpi(std::uint32_t dpi)
{
    SnapshotResources resources;
    if (FAILED(D2D1CreateFactory(
            D2D1_FACTORY_TYPE_SINGLE_THREADED,
            &resources.d2dFactory))) {
        return false;
    }
    if (FAILED(CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&resources.wicFactory)))) {
        return false;
    }

    const auto pixelWidth = 120U * dpi / 96U;
    const auto pixelHeight = 100U * dpi / 96U;
    if (FAILED(resources.wicFactory->CreateBitmap(
            pixelWidth,
            pixelHeight,
            GUID_WICPixelFormat32bppPBGRA,
            WICBitmapCacheOnLoad,
            &resources.bitmap))) {
        return false;
    }
    const auto properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_SOFTWARE,
        D2D1::PixelFormat(
            DXGI_FORMAT_B8G8R8A8_UNORM,
            D2D1_ALPHA_MODE_PREMULTIPLIED),
        static_cast<float>(dpi),
        static_cast<float>(dpi));
    if (FAILED(resources.d2dFactory->CreateWicBitmapRenderTarget(
            resources.bitmap,
            properties,
            &resources.target))) {
        return false;
    }

    AnnotationStyle style;
    style.strokeColor = {255, 0, 0, 255};
    style.fillColor = {0, 190, 78, 255};
    style.fillEnabled = true;
    style.strokeWidthDip = 4;
    style.cornerRadiusDip = 5;
    AnnotationRenderPlan plan;
    plan.items.push_back({
        ShapeAnnotation{1, AnnotationKind::rectangle, {20, 20, 60, 40}, style, 0},
        false,
    });

    resources.target->BeginDraw();
    resources.target->Clear(D2D1::ColorF(0, 0));
    AnnotationRenderer renderer(resources.d2dFactory);
    if (FAILED(renderer.draw(resources.target, plan))) {
        return false;
    }
    if (FAILED(resources.target->EndDraw())) {
        return false;
    }

    const auto centerX = 50U * dpi / 96U;
    const auto centerY = 40U * dpi / 96U;
    const WICRect lockRect{
        static_cast<INT>(centerX),
        static_cast<INT>(centerY),
        1,
        1,
    };
    IWICBitmapLock* lock = nullptr;
    if (FAILED(resources.bitmap->Lock(
            &lockRect,
            WICBitmapLockRead,
            &lock))) {
        return false;
    }
    UINT byteCount = 0;
    BYTE* bytes = nullptr;
    const auto result = lock->GetDataPointer(&byteCount, &bytes);
    const auto matches = SUCCEEDED(result)
        && byteCount >= 4U
        && bytes[0] == 78U
        && bytes[1] == 190U
        && bytes[2] == 0U
        && bytes[3] == 255U;
    lock->Release();
    return matches;
}

bool genericRendererLeavesRotationHandleForMacIconLayer()
{
    SnapshotResources resources;
    if (FAILED(D2D1CreateFactory(
            D2D1_FACTORY_TYPE_SINGLE_THREADED,
            &resources.d2dFactory))) {
        return false;
    }
    if (FAILED(CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&resources.wicFactory)))) {
        return false;
    }
    if (FAILED(resources.wicFactory->CreateBitmap(
            40U,
            40U,
            GUID_WICPixelFormat32bppPBGRA,
            WICBitmapCacheOnLoad,
            &resources.bitmap))) {
        return false;
    }
    const auto properties = D2D1::RenderTargetProperties(
        D2D1_RENDER_TARGET_TYPE_SOFTWARE,
        D2D1::PixelFormat(
            DXGI_FORMAT_B8G8R8A8_UNORM,
            D2D1_ALPHA_MODE_PREMULTIPLIED),
        96.0F,
        96.0F);
    if (FAILED(resources.d2dFactory->CreateWicBitmapRenderTarget(
            resources.bitmap,
            properties,
            &resources.target))) {
        return false;
    }

    AnnotationRenderPlan plan;
    plan.rotationHandle = AnnotationPoint{20.0F, 20.0F};
    resources.target->BeginDraw();
    resources.target->Clear(D2D1::ColorF(0, 0));
    AnnotationRenderer renderer(resources.d2dFactory);
    if (FAILED(renderer.draw(resources.target, plan))
        || FAILED(resources.target->EndDraw())) {
        return false;
    }

    const WICRect lockRect{20, 20, 1, 1};
    IWICBitmapLock* lock = nullptr;
    if (FAILED(resources.bitmap->Lock(&lockRect, WICBitmapLockRead, &lock))) {
        return false;
    }
    UINT byteCount = 0U;
    BYTE* bytes = nullptr;
    const auto result = lock->GetDataPointer(&byteCount, &bytes);
    const auto transparent = SUCCEEDED(result)
        && byteCount >= 4U
        && bytes[3] == 0U;
    lock->Release();
    return transparent;
}

void testDirect2DSnapshotsAtAllSupportedDpis()
{
    const auto comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const auto shouldUninitialize = SUCCEEDED(comResult);
    CHECK(comResult == S_OK || comResult == S_FALSE || comResult == RPC_E_CHANGED_MODE);
    for (const auto dpi : std::array<std::uint32_t, 4>{96, 120, 144, 192}) {
        CHECK(sampleCenterAtDpi(dpi));
    }
    if (shouldUninitialize) {
        CoUninitialize();
    }
}

void testArrowEndpointsAndPatternsRenderAtSupportedDpis()
{
    const auto comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const auto shouldUninitialize = SUCCEEDED(comResult);
    CHECK(comResult == S_OK || comResult == S_FALSE || comResult == RPC_E_CHANGED_MODE);

    constexpr std::array arrowTypes{
        ArrowType::none,
        ArrowType::normal,
        ArrowType::solidArrow,
        ArrowType::hollowArrow,
        ArrowType::diamond,
        ArrowType::bar,
        ArrowType::dot,
    };
    for (const auto dpi : std::array<std::uint32_t, 2>{96U, 144U}) {
        for (const auto type : arrowTypes) {
            ArrowSnapshot startSnapshot;
            CHECK(renderArrowSnapshot(
                dpi, type, ArrowType::none,
                AnnotationStrokePattern::solid, startSnapshot));
            CHECK(startSnapshot.opaquePixels > 100U * dpi / 96U);
            CHECK(startSnapshot.startPixels > 0U);

            ArrowSnapshot endSnapshot;
            CHECK(renderArrowSnapshot(
                dpi, ArrowType::none, type,
                AnnotationStrokePattern::solid, endSnapshot));
            CHECK(endSnapshot.opaquePixels > 100U * dpi / 96U);
            CHECK(endSnapshot.endPixels > 0U);
        }
    }

    constexpr std::array patterns{
        AnnotationStrokePattern::solid,
        AnnotationStrokePattern::dashLong,
        AnnotationStrokePattern::dashNarrow,
        AnnotationStrokePattern::dashLongShort,
        AnnotationStrokePattern::sketchSolid,
        AnnotationStrokePattern::sketchDashed,
    };
    std::array<std::uint64_t, patterns.size()> checksums{};
    for (std::size_t index = 0U; index < patterns.size(); ++index) {
        ArrowSnapshot snapshot;
        CHECK(renderArrowSnapshot(
            96U, ArrowType::dot, ArrowType::normal,
            patterns[index], snapshot));
        CHECK(snapshot.startPixels > 0U);
        CHECK(snapshot.endPixels > 0U);
        checksums[index] = snapshot.checksum;
    }
    CHECK(checksums[0] != checksums[4]);
    CHECK(checksums[1] != checksums[5]);

    if (shouldUninitialize) {
        CoUninitialize();
    }
}

void testBrushPatternsRenderAtSupportedDpis()
{
    const auto comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const auto shouldUninitialize = SUCCEEDED(comResult);
    CHECK(comResult == S_OK || comResult == S_FALSE
        || comResult == RPC_E_CHANGED_MODE);
    constexpr std::array patterns{
        AnnotationStrokePattern::solid,
        AnnotationStrokePattern::dashLong,
        AnnotationStrokePattern::dashNarrow,
        AnnotationStrokePattern::dashLongShort,
    };
    for (const auto dpi : std::array<std::uint32_t, 2>{96U, 144U}) {
        std::array<std::uint64_t, patterns.size()> checksums{};
        for (std::size_t index = 0U; index < patterns.size(); ++index) {
            ArrowSnapshot snapshot;
            CHECK(renderStrokeSnapshot(
                dpi, AnnotationKind::brush, patterns[index], snapshot));
            CHECK(snapshot.opaquePixels > 100U * dpi / 96U);
            checksums[index] = snapshot.checksum;
        }
        CHECK(checksums[0] != checksums[1]);
        CHECK(checksums[1] != checksums[2]);
        CHECK(checksums[2] != checksums[3]);
    }
    if (shouldUninitialize) {
        CoUninitialize();
    }
}

void testMarkerRendersWithMacOpacityAtSupportedDpis()
{
    const auto comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const auto shouldUninitialize = SUCCEEDED(comResult);
    CHECK(comResult == S_OK || comResult == S_FALSE
        || comResult == RPC_E_CHANGED_MODE);
    for (const auto dpi : std::array<std::uint32_t, 2>{96U, 144U}) {
        ArrowSnapshot snapshot;
        CHECK(renderStrokeSnapshot(
            dpi,
            AnnotationKind::marker,
            AnnotationStrokePattern::solid,
            snapshot));
        CHECK(snapshot.opaquePixels > 1000U * dpi / 96U);
        CHECK(snapshot.checksum > 0U);
    }
    if (shouldUninitialize) {
        CoUninitialize();
    }
}

void testRotationHandleIsReservedForMacIconLayer()
{
    const auto comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const auto shouldUninitialize = SUCCEEDED(comResult);
    CHECK(comResult == S_OK || comResult == S_FALSE || comResult == RPC_E_CHANGED_MODE);
    CHECK(genericRendererLeavesRotationHandleForMacIconLayer());
    if (shouldUninitialize) {
        CoUninitialize();
    }
}

} // namespace

int main()
{
    testPlanUsesSelectionLocalCoordinatesAndLivePreview();
    testEditingPreviewReplacesCommittedShape();
    testArrowLinePlanTranslatesCurveAndUsesThreeEditingHandles();
    testBrushPlanTranslatesPathAndUsesInsetEndpointHandles();
    testMarkerPlanTranslatesLineAndUsesInsetEndpointHandles();
    testMacDashPatternsAreAbsoluteDips();
    testStrokeMenuSketchSampleUsesExactMacJitter();
    testDirect2DSnapshotsAtAllSupportedDpis();
    testArrowEndpointsAndPatternsRenderAtSupportedDpis();
    testBrushPatternsRenderAtSupportedDpis();
    testMarkerRendersWithMacOpacityAtSupportedDpis();
    testRotationHandleIsReservedForMacIconLayer();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
