#include "annotation/AnnotationRenderer.h"

#include <Windows.h>
#include <d2d1.h>
#include <objbase.h>
#include <wincodec.h>

#include <array>
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

} // namespace

int main()
{
    testPlanUsesSelectionLocalCoordinatesAndLivePreview();
    testMacDashPatternsAreAbsoluteDips();
    testDirect2DSnapshotsAtAllSupportedDpis();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
