#include "toolbar/ToolbarCatalog.h"
#include "resource.h"

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>

#include <array>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string_view>

using namespace xxsnap::win;
using Microsoft::WRL::ComPtr;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

template <typename T, std::size_t Size>
constexpr bool arraysEqual(
    const std::array<T, Size>& left,
    const std::array<T, Size>& right) noexcept
{
    for (std::size_t index = 0; index < Size; ++index) {
        if (left[index] != right[index]) {
            return false;
        }
    }
    return true;
}

void testCatalogContract()
{
    static_assert(ToolbarMetrics::heightDip == 28.0F);
    static_assert(ToolbarMetrics::buttonSizeDip == 20.0F);
    static_assert(ToolbarMetrics::buttonStepDip == 28.0F);
    static_assert(ToolbarMetrics::horizontalPaddingDip == 4.0F);
    static_assert(ToolbarMetrics::groupGapDip == 8.0F);
    static_assert(ToolbarMetrics::cornerRadiusDip == 6.0F);

    constexpr std::array expected{
        ToolbarAction::rectangle,
        ToolbarAction::polyline,
        ToolbarAction::pen,
        ToolbarAction::marker,
        ToolbarAction::eyedropper,
        ToolbarAction::mosaic,
        ToolbarAction::text,
        ToolbarAction::number,
        ToolbarAction::magnifier,
        ToolbarAction::eraser,
        ToolbarAction::scroll,
        ToolbarAction::undo,
        ToolbarAction::redo,
        ToolbarAction::cancel,
        ToolbarAction::pin,
        ToolbarAction::save,
        ToolbarAction::copy,
    };

    static_assert(arraysEqual(fullToolbarActions(), expected));
    static_assert(terminalToolbarActions().size() == 3);
    static_assert(pinnedEditorToolbarActions().size() == 15);
    static_assert(pinnedEditorToolbarActions().back()
        == ToolbarAction::finishEditing);
    constexpr std::array teachingPenExpected{
        ToolbarAction::pen,
        ToolbarAction::rectangle,
        ToolbarAction::polyline,
        ToolbarAction::marker,
        ToolbarAction::text,
        ToolbarAction::number,
        ToolbarAction::mosaic,
        ToolbarAction::eyedropper,
        ToolbarAction::eraser,
        ToolbarAction::magnifier,
        ToolbarAction::copy,
        ToolbarAction::save,
    };
    static_assert(arraysEqual(
        teachingPenToolbarActions(), teachingPenExpected));
    CHECK(std::wstring_view(toolbarIcon(ToolbarAction::finishEditing).resourceName)
        == L"done");
    CHECK(toolbarIcon(ToolbarAction::rectangle).insetDip == 0.0F);
    static_assert(toolbarIcon(ToolbarAction::number).insetDip == 3.0F);
    static_assert(toolbarIcon(ToolbarAction::scroll).insetDip == 0.0F);
    static_assert(toolbarIcon(ToolbarAction::undo).fixedColor);
    static_assert(toolbarIcon(ToolbarAction::redo).fixedColor);
    static_assert(extraGapAfter(ToolbarAction::eraser) == 8.0F);
    static_assert(extraGapAfter(ToolbarAction::scroll) == 8.0F);
    static_assert(extraGapAfter(ToolbarAction::redo) == 8.0F);
    static_assert(extraGapAfter(ToolbarAction::copy) == 0.0F);

    CHECK(toolbarImageResources().size() == 23U);
    CHECK(std::wstring_view(eraserTrashIcon().resourceName) == L"trash");
    static_assert(dragHandleIcon().resourceIdAt96Dpi > 0);
    const auto& rotationHandle = rotationHandleIcon();
    CHECK(rotationHandle.insetDip == 4.0F);
    CHECK(rotationHandle.fixedColor);
    CHECK(rotationHandle.resourceIdAt96Dpi > 0);
    CHECK(std::wstring_view(rotationHandle.resourceName)
        == L"refresh-svgrepo-com3");
    static_assert(toolbarResourceId(dragHandleIcon(), 72) == dragHandleIcon().resourceIdAt96Dpi);
    static_assert(toolbarResourceId(dragHandleIcon(), 97) == dragHandleIcon().resourceIdAt120Dpi);
    static_assert(toolbarResourceId(dragHandleIcon(), 121) == dragHandleIcon().resourceIdAt144Dpi);
    static_assert(toolbarResourceId(dragHandleIcon(), 145) == dragHandleIcon().resourceIdAt192Dpi);
    static_assert(toolbarResourceId(dragHandleIcon(), 240) == dragHandleIcon().resourceIdAt192Dpi);
    static_assert(toolbarIconPixelEdge(toolbarIcon(ToolbarAction::pen), 96U)
        == 16);
    static_assert(toolbarIconPixelEdge(toolbarIcon(ToolbarAction::pen), 144U)
        == 24);
    static_assert(toolbarIconPixelEdge(toolbarIcon(ToolbarAction::scroll), 144U)
        == 30);
    static_assert(toolbarIconPixelEdge(
        toolbarIcon(ToolbarAction::finishEditing), 192U) == 40);

    for (const auto action : fullToolbarActions()) {
        const auto& icon = toolbarIcon(action);
        CHECK(icon.resourceIdAt96Dpi > 0);
        CHECK(icon.resourceIdAt120Dpi > 0);
        CHECK(icon.resourceIdAt144Dpi > 0);
        CHECK(icon.resourceIdAt192Dpi > 0);
    }
    CHECK(std::wstring_view(toolbarIcon(ToolbarAction::cancel).resourceName)
        == L"cancel-capture");

    CHECK(std::wstring_view(toolbarTooltip(ToolbarAction::rectangle).title)
        == L"形状");
    CHECK(toolbarShortcutLabel(ToolbarAction::rectangle) == L"S");
    CHECK(toolbarShortcutLabel(ToolbarAction::scroll) == L"R");
    CHECK(toolbarShortcutLabel(ToolbarAction::undo) == L"Ctrl+Z");
    CHECK(toolbarShortcutLabel(ToolbarAction::redo) == L"Ctrl+Shift+Z");
    CHECK(toolbarShortcutLabel(ToolbarAction::pin) == L"Ctrl+1");
    CHECK(toolbarShortcutLabel(ToolbarAction::finishEditing) == L"ESC");
    CHECK(toolbarTooltipText(ToolbarAction::scroll) == L"滚动截图 (R)");
    CHECK(toolbarShortcutMatches(
        ToolbarAction::scroll, 'R', false, false, false));
    CHECK(toolbarShortcutMatches(
        ToolbarAction::rectangle, 'S', false, true, false));
    CHECK(!toolbarShortcutMatches(
        ToolbarAction::rectangle, 'S', true, false, false));
    CHECK(toolbarShortcutMatches(
        ToolbarAction::redo, 'Z', true, true, false));
    CHECK(!toolbarShortcutMatches(
        ToolbarAction::redo, 'Z', true, false, false));
}

void checkEmbeddedPng(
    IWICImagingFactory* factory,
    int resourceId,
    UINT expectedEdge)
{
    const auto module = GetModuleHandleW(nullptr);
    const auto resource = FindResourceW(
        module,
        MAKEINTRESOURCEW(resourceId),
        MAKEINTRESOURCEW(10));
    CHECK(resource != nullptr);
    if (resource == nullptr) {
        return;
    }

    const auto byteCount = SizeofResource(module, resource);
    const auto loaded = LoadResource(module, resource);
    auto* bytes = static_cast<BYTE*>(LockResource(loaded));
    CHECK(byteCount > 0);
    CHECK(loaded != nullptr);
    CHECK(bytes != nullptr);
    if (byteCount == 0 || loaded == nullptr || bytes == nullptr) {
        return;
    }

    ComPtr<IWICStream> stream;
    CHECK(SUCCEEDED(factory->CreateStream(&stream)));
    if (!stream) {
        return;
    }
    CHECK(SUCCEEDED(stream->InitializeFromMemory(bytes, byteCount)));

    ComPtr<IWICBitmapDecoder> decoder;
    CHECK(SUCCEEDED(factory->CreateDecoderFromStream(
        stream.Get(),
        nullptr,
        WICDecodeMetadataCacheOnLoad,
        &decoder)));
    if (!decoder) {
        return;
    }

    ComPtr<IWICBitmapFrameDecode> frame;
    CHECK(SUCCEEDED(decoder->GetFrame(0, &frame)));
    if (!frame) {
        return;
    }
    UINT width = 0;
    UINT height = 0;
    CHECK(SUCCEEDED(frame->GetSize(&width, &height)));
    CHECK(width == expectedEdge);
    CHECK(height == expectedEdge);
}

void testAllEmbeddedResourcesDecode()
{
    const auto comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    CHECK(SUCCEEDED(comResult));
    if (FAILED(comResult)) {
        return;
    }

    ComPtr<IWICImagingFactory> factory;
    CHECK(SUCCEEDED(CoCreateInstance(
        CLSID_WICImagingFactory,
        nullptr,
        CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&factory))));
    if (factory) {
        for (const auto& icon : toolbarImageResources()) {
            checkEmbeddedPng(
                factory.Get(), icon.resourceIdAt96Dpi,
                toolbarIconPixelEdge(icon, 96U));
            checkEmbeddedPng(
                factory.Get(), icon.resourceIdAt120Dpi,
                toolbarIconPixelEdge(icon, 120U));
            checkEmbeddedPng(
                factory.Get(), icon.resourceIdAt144Dpi,
                toolbarIconPixelEdge(icon, 144U));
            checkEmbeddedPng(
                factory.Get(), icon.resourceIdAt192Dpi,
                toolbarIconPixelEdge(icon, 192U));
        }
    }
    factory.Reset();
    CoUninitialize();
}

void testEmbeddedEraserCursorMatchesMacHotspot()
{
    const auto cursor = LoadCursorW(
        GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDC_XXSNAP_ERASER));
    CHECK(cursor != nullptr);
    if (cursor == nullptr) return;

    ICONINFO info{};
    CHECK(GetIconInfo(cursor, &info));
    CHECK(!info.fIcon);
    CHECK(info.xHotspot == 11U);
    CHECK(info.yHotspot == 21U);
    if (info.hbmMask != nullptr) DeleteObject(info.hbmMask);
    if (info.hbmColor != nullptr) DeleteObject(info.hbmColor);
}

int main()
{
    testCatalogContract();
    testAllEmbeddedResourcesDecode();
    testEmbeddedEraserCursorMatchesMacHotspot();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
