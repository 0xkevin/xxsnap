#include "overlay/OverlayHost.h"

#include "annotation/AnnotationGeometry.h"
#include "export/AnnotationComposer.h"
#include "export/SelectionComposer.h"
#include "overlay/OverlayRenderer.h"

#include <commdlg.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <new>
#include <cwchar>
#include <utility>

namespace xxsnap::win {
namespace {

AnnotationRenderPlan scaledRenderPlan(
    AnnotationRenderPlan plan,
    float scale)
{
    if (scale == 1.0F) return plan;
    const auto point = [scale](AnnotationPoint value) {
        return AnnotationPoint{value.x * scale, value.y * scale};
    };
    const auto rect = [scale](AnnotationRect value) {
        return AnnotationRect{
            value.x * scale, value.y * scale,
            value.width * scale, value.height * scale,
        };
    };
    for (auto& item : plan.items) {
        item.annotation = scaled(std::move(item.annotation), scale, scale);
    }
    for (auto& value : plan.resizeHandles) value = point(value);
    for (auto& value : plan.lineHandles) value = point(value);
    if (plan.rotationHandle) plan.rotationHandle = point(*plan.rotationHandle);
    if (plan.textCaret) plan.textCaret = rect(*plan.textCaret);
    if (plan.textCaretRotationCenter) {
        plan.textCaretRotationCenter = point(*plan.textCaretRotationCenter);
    }
    if (plan.textDeleteHandle) {
        plan.textDeleteHandle = point(*plan.textDeleteHandle);
    }
    if (plan.numberOutline) plan.numberOutline = rect(*plan.numberOutline);
    for (auto& value : plan.numberHandles) value.second = rect(value.second);
    if (plan.numberCaret) plan.numberCaret = rect(*plan.numberCaret);
    if (plan.eraserPreview) plan.eraserPreview = rect(*plan.eraserPreview);
    return plan;
}

std::int64_t saturatingAdd(std::int64_t lhs, std::int64_t rhs) noexcept
{
    constexpr auto minimum = (std::numeric_limits<std::int64_t>::min)();
    constexpr auto maximum = (std::numeric_limits<std::int64_t>::max)();
    if (rhs > 0 && lhs > maximum - rhs) {
        return maximum;
    }
    if (rhs < 0 && lhs < minimum - rhs) {
        return minimum;
    }
    return lhs + rhs;
}

bool contains(PixelRect rect, PixelPoint point) noexcept
{
    rect = snipory::core::portable::standardized(rect);
    return point.x >= rect.x && point.y >= rect.y
        && point.x < saturatingAdd(rect.x, rect.width)
        && point.y < saturatingAdd(rect.y, rect.height);
}

bool contains(AnnotationRect rect, AnnotationPoint point) noexcept
{
    rect = standardized(rect);
    return point.x >= rect.x && point.y >= rect.y
        && point.x <= rect.x + rect.width
        && point.y <= rect.y + rect.height;
}

int CALLBACK collectFontFamily(
    const LOGFONTW* font,
    const TEXTMETRICW*,
    DWORD,
    LPARAM parameter)
{
    if (font == nullptr || font->lfFaceName[0] == L'@') return 1;
    auto* families = reinterpret_cast<std::vector<std::wstring>*>(parameter);
    families->emplace_back(font->lfFaceName);
    return 1;
}

const std::vector<std::wstring>& systemFontFamilies()
{
    static const auto families = [] {
        std::vector<std::wstring> result;
        auto dc = GetDC(nullptr);
        if (dc != nullptr) {
            LOGFONTW request{};
            request.lfCharSet = DEFAULT_CHARSET;
            EnumFontFamiliesExW(dc, &request, collectFontFamily,
                reinterpret_cast<LPARAM>(&result), 0U);
            ReleaseDC(nullptr, dc);
        }
        std::sort(result.begin(), result.end());
        result.erase(std::unique(result.begin(), result.end()), result.end());
        const auto preferred = std::find(
            result.begin(), result.end(), textDefaultFontFamily);
        if (preferred != result.end() && preferred != result.begin()) {
            const auto value = *preferred;
            result.erase(preferred);
            result.insert(result.begin(), value);
        } else if (preferred == result.end()) {
            result.insert(result.begin(), textDefaultFontFamily);
        }
        return result;
    }();
    return families;
}

struct TextPopupData {
    PopupMenuLayout layout;
    std::vector<std::wstring> labels;
    std::size_t firstIndex = 0U;
    std::optional<std::size_t> selectedIndex;
};

TextPopupData textPopupDataFor(
    TextPopupMenu menu,
    const TextOptionsLayout& options,
    const TextOptionsState& state,
    float safeHeight,
    int scrollOffset)
{
    constexpr std::size_t visibleCount = 10U;
    TextPopupData data;
    AnnotationRect field{};
    std::size_t totalCount = 0U;
    std::size_t selected = 0U;
    if (menu == TextPopupMenu::fontFamily) {
        field = options.fontFamily;
        const auto& fonts = systemFontFamilies();
        totalCount = fonts.size();
        const auto found = std::find(fonts.begin(), fonts.end(),
            state.style().textFontFamily);
        selected = found == fonts.end() ? 0U
            : static_cast<std::size_t>(std::distance(fonts.begin(), found));
    } else {
        field = options.textSize;
        totalCount = 70U;
        selected = static_cast<std::size_t>(
            clampedTextSize(state.style().textSize) - textMinimumSize);
    }
    const auto heightLimitedCount = static_cast<std::size_t>((std::max)(
        1.0F, std::floor((safeHeight - 24.0F) / 24.0F)));
    const auto count = (std::min)(
        (std::min)(visibleCount, heightLimitedCount), totalCount);
    data.firstIndex = selected > count / 2U ? selected - count / 2U : 0U;
    if (scrollOffset < 0) {
        const auto amount = static_cast<std::size_t>(-scrollOffset);
        data.firstIndex = amount > data.firstIndex
            ? 0U : data.firstIndex - amount;
    } else {
        data.firstIndex += static_cast<std::size_t>(scrollOffset);
    }
    if (data.firstIndex + count > totalCount) {
        data.firstIndex = totalCount - count;
    }
    data.layout = popupMenuLayout(field, count, safeHeight);
    data.labels.reserve(count);
    for (std::size_t offset = 0; offset < count; ++offset) {
        const auto index = data.firstIndex + offset;
        if (menu == TextPopupMenu::fontFamily) {
            data.labels.push_back(systemFontFamilies()[index]);
        } else {
            data.labels.push_back(std::to_wstring(
                index + static_cast<std::size_t>(textMinimumSize)));
        }
        if (index == selected) data.selectedIndex = offset;
    }
    return data;
}

TextPopupData numberPopupDataFor(
    NumberPopupMenu menu,
    const NumberOptionsLayout& options,
    const NumberOptionsState& state,
    float safeHeight,
    int scrollOffset)
{
    TextPopupData data;
    if (menu == NumberPopupMenu::markType) {
        data.layout = numberTypeMenuLayout(options.markType, safeHeight);
        data.labels.reserve(numberMarkTypes.size());
        for (const auto& descriptor : numberMarkTypes) {
            data.labels.emplace_back(descriptor.glyph);
        }
        data.selectedIndex = numberMarkTypeIndex(state.type());
        return data;
    }
    const auto selectedIterator = std::find(
        numberSizeValues.begin(), numberSizeValues.end(),
        state.style().textSize);
    const auto selected = selectedIterator == numberSizeValues.end()
        ? 0U : static_cast<std::size_t>(std::distance(
            numberSizeValues.begin(), selectedIterator));
    constexpr std::size_t visibleMaximum = 10U;
    const auto heightLimitedCount = static_cast<std::size_t>((std::max)(
        1.0F, std::floor((safeHeight - 24.0F) / 24.0F)));
    const auto count = (std::min)(visibleMaximum,
        (std::min)(heightLimitedCount, numberSizeValues.size()));
    data.firstIndex = selected > count / 2U ? selected - count / 2U : 0U;
    if (scrollOffset < 0) {
        const auto amount = static_cast<std::size_t>(-scrollOffset);
        data.firstIndex = amount > data.firstIndex
            ? 0U : data.firstIndex - amount;
    } else {
        data.firstIndex += static_cast<std::size_t>(scrollOffset);
    }
    if (data.firstIndex + count > numberSizeValues.size()) {
        data.firstIndex = numberSizeValues.size() - count;
    }
    data.layout = popupMenuLayout(options.size, count, safeHeight);
    data.labels.reserve(count);
    for (std::size_t offset = 0; offset < count; ++offset) {
        const auto index = data.firstIndex + offset;
        data.labels.push_back(std::to_wstring(
            static_cast<int>(numberSizeValues[index])));
        if (index == selected) data.selectedIndex = offset;
    }
    return data;
}

StrokePatternMenuLayout strokePatternMenuFor(
    AnnotationRect field,
    float safeHeight,
    std::size_t itemCount = 6U) noexcept
{
    const auto menuHeight = static_cast<float>(itemCount) * 24.0F + 8.0F;
    auto menuRect = AnnotationRect{
        field.x,
        field.y + field.height + 8.0F,
        field.width,
        menuHeight,
    };
    if (menuRect.y + menuRect.height > safeHeight - 8.0F) {
        menuRect.y = field.y - 8.0F - menuHeight;
    }
    return strokePatternMenuLayout(menuRect, itemCount);
}

AnnotationPoint optionsToolbarOrigin(
    const OverlayLayout& chrome,
    AnnotationRect initialToolbar) noexcept
{
    const AnnotationRect safe{
        8.0F, 8.0F,
        (std::max)(0.0F, chrome.overlayBounds.width - 16.0F),
        (std::max)(0.0F, chrome.overlayBounds.height - 16.0F),
    };
    const auto x = (std::max)(safe.x, (std::min)(
        chrome.toolbar.bounds.x,
        safe.x + (std::max)(0.0F, safe.width - initialToolbar.width)));
    auto y = chrome.toolbar.bounds.y + chrome.toolbar.bounds.height + 8.0F;
    if (y + initialToolbar.height > safe.y + safe.height) {
        y = chrome.toolbar.bounds.y - 8.0F - initialToolbar.height;
    }
    y = (std::max)(safe.y, (std::min)(
        y, safe.y + (std::max)(0.0F, safe.height - initialToolbar.height)));
    return {x, y};
}

ArrowTypeMenuLayout arrowTypeMenuFor(
    const ArrowLineOptionsLayout& options,
    ArrowEndpoint endpoint,
    float safeHeight) noexcept
{
    const auto field = endpoint == ArrowEndpoint::start
        ? options.startArrowType
        : options.endArrowType;
    auto menuRect = AnnotationRect{
        field.x,
        options.toolbar.y + options.toolbar.height + 8.0F,
        58.0F,
        176.0F,
    };
    if (menuRect.y + menuRect.height > safeHeight - 8.0F) {
        menuRect.y = options.toolbar.y - 8.0F - menuRect.height;
    }
    return arrowTypeMenuLayout(menuRect);
}

OverlayCursorStyle cursorStyleForSelectionHandle(
    SelectionHandle handle) noexcept
{
    switch (handle) {
    case SelectionHandle::body:
        return OverlayCursorStyle::move;
    case SelectionHandle::north:
    case SelectionHandle::south:
        return OverlayCursorStyle::resizeUpDown;
    case SelectionHandle::east:
    case SelectionHandle::west:
        return OverlayCursorStyle::resizeLeftRight;
    case SelectionHandle::northWest:
    case SelectionHandle::southEast:
        return OverlayCursorStyle::resizeTopLeftBottomRight;
    case SelectionHandle::northEast:
    case SelectionHandle::southWest:
        return OverlayCursorStyle::resizeTopRightBottomLeft;
    case SelectionHandle::none:
        return OverlayCursorStyle::crosshair;
    }
    return OverlayCursorStyle::crosshair;
}

OverlayCursorStyle cursorStyleForShape(ShapeCursorStyle style) noexcept
{
    switch (style) {
    case ShapeCursorStyle::arrow:
        return OverlayCursorStyle::arrow;
    case ShapeCursorStyle::crosshair:
        return OverlayCursorStyle::crosshair;
    case ShapeCursorStyle::move:
        return OverlayCursorStyle::move;
    case ShapeCursorStyle::resizeLeftRight:
        return OverlayCursorStyle::resizeLeftRight;
    case ShapeCursorStyle::resizeUpDown:
        return OverlayCursorStyle::resizeUpDown;
    case ShapeCursorStyle::resizeTopLeftBottomRight:
        return OverlayCursorStyle::resizeTopLeftBottomRight;
    case ShapeCursorStyle::resizeTopRightBottomLeft:
        return OverlayCursorStyle::resizeTopRightBottomLeft;
    case ShapeCursorStyle::rotation:
        return OverlayCursorStyle::rotation;
    case ShapeCursorStyle::brush:
        return OverlayCursorStyle::brush;
    case ShapeCursorStyle::marker:
        return OverlayCursorStyle::marker;
    case ShapeCursorStyle::mosaic:
        return OverlayCursorStyle::mosaic;
    case ShapeCursorStyle::numberMark:
        return OverlayCursorStyle::numberMark;
    case ShapeCursorStyle::numberCheck:
        return OverlayCursorStyle::numberCheck;
    case ShapeCursorStyle::numberCross:
        return OverlayCursorStyle::numberCross;
    case ShapeCursorStyle::textInput:
        return OverlayCursorStyle::textInput;
    case ShapeCursorStyle::eyedropper:
        return OverlayCursorStyle::eyedropper;
    case ShapeCursorStyle::eraser:
        return OverlayCursorStyle::eraser;
    }
    return OverlayCursorStyle::arrow;
}

PixelRect buttonRectPhysical(DipRect rect, const OverlaySurface& surface) noexcept
{
    const auto left = dipLengthToPhysicalPixels(rect.x, surface.dpiX);
    const auto top = dipLengthToPhysicalPixels(rect.y, surface.dpiY);
    const auto right = dipLengthToPhysicalPixels(
        rect.x + rect.width, surface.dpiX);
    const auto bottom = dipLengthToPhysicalPixels(
        rect.y + rect.height, surface.dpiY);
    return {left, top, right - left, bottom - top};
}

PixelPoint buttonCenterPhysical(PixelRect rect) noexcept
{
    return {
        rect.x + rect.width / 2,
        rect.y + rect.height / 2,
    };
}

class SystemOverlayInputPlatform final : public OverlayInputPlatform {
public:
    bool captureMouse(HWND window) noexcept override
    {
        if (window == nullptr || !IsWindow(window)) {
            SetLastError(ERROR_INVALID_WINDOW_HANDLE);
            return false;
        }
        SetCapture(window);
        return GetCapture() == window;
    }

    bool releaseMouse() noexcept override
    {
        return ReleaseCapture() != FALSE;
    }

    std::optional<PixelPoint> cursorPosition() noexcept override
    {
        POINT point{};
        if (!GetCursorPos(&point)) {
            return std::nullopt;
        }
        return PixelPoint{point.x, point.y};
    }

    bool registerEscapeHotKey(HWND window, int identifier) noexcept override
    {
        return RegisterHotKey(window, identifier, 0, VK_ESCAPE) != FALSE;
    }

    bool unregisterEscapeHotKey(HWND window, int identifier) noexcept override
    {
        return UnregisterHotKey(window, identifier) != FALSE;
    }

    bool registerEditorHotKeys(HWND window) noexcept override
    {
        if (window == nullptr) {
            return false;
        }
        RegisterHotKey(window, overlayUndoHotKeyIdentifier, MOD_CONTROL, 'Z');
        RegisterHotKey(
            window,
            overlayRedoHotKeyIdentifier,
            MOD_CONTROL | MOD_SHIFT,
            'Z');
        RegisterHotKey(window, overlaySaveHotKeyIdentifier, MOD_CONTROL, 'S');
        RegisterHotKey(window, overlayCopyHotKeyIdentifier, MOD_CONTROL, 'C');
        RegisterHotKey(window, overlayDeleteHotKeyIdentifier, 0, VK_DELETE);
        RegisterHotKey(window, overlayPinHotKeyIdentifier, MOD_CONTROL, '1');
        return true;
    }

    bool unregisterEditorHotKeys(HWND window) noexcept override
    {
        for (const auto identifier : {
                 overlayUndoHotKeyIdentifier,
                 overlayRedoHotKeyIdentifier,
                 overlaySaveHotKeyIdentifier,
                 overlayCopyHotKeyIdentifier,
                 overlayDeleteHotKeyIdentifier,
                 overlayPinHotKeyIdentifier}) {
            UnregisterHotKey(window, identifier);
        }
        return true;
    }

    bool registerToolbarHotKeys(HWND window) noexcept override
    {
        if (window == nullptr) return false;
        for (std::size_t index = 0;
             index < static_cast<std::size_t>(ToolbarAction::count); ++index) {
            const auto action = static_cast<ToolbarAction>(index);
            const auto& shortcut = toolbarTooltip(action);
            if (shortcut.control || shortcut.virtualKey == VK_ESCAPE) continue;
            RegisterHotKey(window,
                overlayToolbarHotKeyIdentifier(action, false),
                0, shortcut.virtualKey);
            RegisterHotKey(window,
                overlayToolbarHotKeyIdentifier(action, true),
                MOD_SHIFT, shortcut.virtualKey);
        }
        return true;
    }

    bool unregisterToolbarHotKeys(HWND window) noexcept override
    {
        for (std::size_t index = 0;
             index < static_cast<std::size_t>(ToolbarAction::count); ++index) {
            const auto action = static_cast<ToolbarAction>(index);
            const auto& shortcut = toolbarTooltip(action);
            if (shortcut.control || shortcut.virtualKey == VK_ESCAPE) continue;
            UnregisterHotKey(
                window, overlayToolbarHotKeyIdentifier(action, false));
            UnregisterHotKey(
                window, overlayToolbarHotKeyIdentifier(action, true));
        }
        return true;
    }

    std::optional<AnnotationColor> chooseColor(
        HWND owner,
        AnnotationColor current) noexcept override
    {
        static COLORREF customColors[16]{};
        CHOOSECOLORW chooser{};
        chooser.lStructSize = sizeof(chooser);
        chooser.hwndOwner = owner;
        chooser.rgbResult = RGB(current.red, current.green, current.blue);
        chooser.lpCustColors = customColors;
        chooser.Flags = CC_FULLOPEN | CC_RGBINIT;
        if (!ChooseColorW(&chooser)) {
            return std::nullopt;
        }
        return AnnotationColor{
            GetRValue(chooser.rgbResult),
            GetGValue(chooser.rgbResult),
            GetBValue(chooser.rgbResult),
            255,
        };
    }

    bool copyText(const std::wstring& text) noexcept override
    {
        if (!OpenClipboard(nullptr)) {
            return false;
        }
        struct ClipboardCloser {
            ~ClipboardCloser() { CloseClipboard(); }
        } closer;
        if (!EmptyClipboard()) {
            return false;
        }
        const auto bytes = (text.size() + 1U) * sizeof(wchar_t);
        const auto memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
        if (memory == nullptr) {
            return false;
        }
        auto* destination = GlobalLock(memory);
        if (destination == nullptr) {
            GlobalFree(memory);
            return false;
        }
        std::memcpy(destination, text.c_str(), bytes);
        GlobalUnlock(memory);
        if (SetClipboardData(CF_UNICODETEXT, memory) == nullptr) {
            GlobalFree(memory);
            return false;
        }
        return true;
    }
};

} // namespace

OverlayInputRouter::OverlayInputRouter(
    PixelRect virtualBounds,
    std::vector<OverlaySurface> surfaces,
    OverlayInputPlatform& platform,
    ActionCallback actionCallback,
    bool shapeAnnotationsEnabled,
    const FrozenDesktop* desktop,
    OverlayMode mode)
    : virtualBounds_(snipory::core::portable::standardized(virtualBounds))
    , model_(virtualBounds_)
    , surfaces_(std::move(surfaces))
    , platform_(platform)
    , actionCallback_(std::move(actionCallback))
    , shapeAnnotationsEnabled_(shapeAnnotationsEnabled)
    , mode_(mode)
    , desktop_(desktop)
{
    for (auto& surface : surfaces_) {
        surface.physicalBounds = snipory::core::portable::standardized(
            surface.physicalBounds);
        if (surface.dpiX == 0) {
            surface.dpiX = 96;
        }
        if (surface.dpiY == 0) {
            surface.dpiY = 96;
        }
    }
    if (mode_ == OverlayMode::teachingPen) {
        lockSelection(virtualBounds);
        if (editor_ != nullptr) {
            editor_->setTeachingPenMode(true);
            editor_->handleToolbarAction(ToolbarAction::pen);
        }
    }
}

void OverlayInputRouter::lockSelection(PixelRect selection) noexcept
{
    selection = snipory::core::portable::standardized(selection);
    if (selection.width <= 0 || selection.height <= 0) return;
    model_.beginCreation({selection.x, selection.y});
    model_.updateInteraction({
        selection.x + selection.width,
        selection.y + selection.height,
    });
    model_.finishInteraction();
    ensureEditor();
}

void OverlayInputRouter::setAnnotationViewport(
    AnnotationPoint origin,
    float scale,
    AnnotationRect canvasBounds,
    const FrozenDesktop* desktop) noexcept
{
    if (dragging_) {
        releaseInteraction();
    }
    annotationViewportOrigin_ = origin;
    annotationViewportScale_ = (std::max)(scale, 0.0001F);
    annotationCanvasBounds_ = standardized(canvasBounds);
    desktop_ = desktop;
    rawSelectionCache_.reset();
    rawSelectionCacheSelection_.reset();
    cursorContrastSelection_.reset();
    cursorContrastPrefersLight_.reset();
    annotationCompositeCache_.reset();
    if (editor_ != nullptr) {
        editor_->setCanvasBounds(*annotationCanvasBounds_);
    }
}

std::vector<ToolbarAction> OverlayInputRouter::toolbarActions() const
{
    if (mode_ == OverlayMode::textRecognition) {
        return {};
    }
    if (mode_ == OverlayMode::pinnedImageEditor
        || mode_ == OverlayMode::longImageEditor) {
        return {
            pinnedEditorToolbarActions().begin(),
            pinnedEditorToolbarActions().end(),
        };
    }
    if (mode_ == OverlayMode::teachingPen) {
        return {
            teachingPenToolbarActions().begin(),
            teachingPenToolbarActions().end(),
        };
    }
    return editor_ != nullptr
        ? editor_->toolbarState().visibleActions()
        : std::vector<ToolbarAction>{
              terminalToolbarActions().begin(),
              terminalToolbarActions().end(),
          };
}

bool OverlayInputRouter::toolbarActionEnabled(
    ToolbarAction action) const noexcept
{
    if ((mode_ == OverlayMode::pinnedImageEditor
            || mode_ == OverlayMode::longImageEditor)
        && action == ToolbarAction::finishEditing) {
        return true;
    }
    return editor_ == nullptr || editor_->toolbarState().isEnabled(action);
}

bool OverlayInputRouter::performToolbarAction(ToolbarAction action) noexcept
{
    if (status_ != OverlayInputStatus::active
        || !toolbarActionEnabled(action)) {
        return false;
    }
    hoveredToolbarWindow_ = nullptr;
    hoveredToolbarAction_.reset();
    hoveredToolbarTooltipText_.clear();
    if (action == ToolbarAction::cancel) {
        cancelOnce();
    } else if (action == ToolbarAction::pin) {
        completeOnce(OverlayInputAction::pin);
    } else if (action == ToolbarAction::save) {
        completeOnce(OverlayInputAction::save);
    } else if (action == ToolbarAction::copy) {
        completeOnce(OverlayInputAction::copy);
    } else if (action == ToolbarAction::finishEditing) {
        completeOnce(OverlayInputAction::finishEditing);
    } else if (action == ToolbarAction::scroll) {
        releaseInteraction();
        deactivateEscapeHotKey();
        emitTerminal(OverlayInputAction::scrollCapture);
    } else if (editor_ != nullptr) {
        editor_->handleToolbarAction(action);
        if (editor_->isEyedropperToolActive()) {
            clearEyedropperState();
            refreshEyedropperComposite();
        } else {
            clearEyedropperState();
        }
    } else {
        return false;
    }
    return true;
}

void OverlayInputRouter::ensureEditor() noexcept
{
    if (!shapeAnnotationsEnabled_
        || model_.phase() != SelectionPhase::ready
        || !model_.selection().has_value()) {
        return;
    }
    const auto owner = actionOwner();
    if (!owner.has_value()) {
        return;
    }
    const auto selection = snipory::core::portable::standardized(
        *model_.selection());
    const auto& surface = surfaces_[*owner];
    const AnnotationRect viewportBounds{
        physicalPixelsToDip(
            virtualBounds_.x - selection.x, surface.dpiX),
        physicalPixelsToDip(
            virtualBounds_.y - selection.y, surface.dpiY),
        physicalPixelsToDip(virtualBounds_.width, surface.dpiX),
        physicalPixelsToDip(virtualBounds_.height, surface.dpiY),
    };
    const auto bounds = annotationCanvasBounds_.value_or(viewportBounds);
    if (!editor_) {
        try {
            editor_ = std::make_unique<ShapeEditorController>(bounds);
            editorOwnerIndex_ = owner;
        } catch (...) {
            editor_.reset();
            editorOwnerIndex_.reset();
        }
        return;
    }
    if (editorOwnerIndex_ == owner) {
        editor_->setCanvasBounds(bounds);
    }
}

std::optional<MainToolbarLayout>
OverlayInputRouter::teachingPenToolbarLayout(
    const OverlaySurface& surface) const
{
    if (mode_ != OverlayMode::teachingPen
        || !teachingPenToolbarAnchor_.has_value()
        || !contains(surface.physicalBounds, *teachingPenToolbarAnchor_)) {
        return std::nullopt;
    }
    const ToolbarPoint pointer{
        physicalPixelsToDip(
            teachingPenToolbarAnchor_->x - surface.physicalBounds.x,
            surface.dpiX),
        physicalPixelsToDip(
            teachingPenToolbarAnchor_->y - surface.physicalBounds.y,
            surface.dpiY),
    };
    const ToolbarRect bounds{
        0.0F,
        0.0F,
        physicalPixelsToDip(surface.physicalBounds.width, surface.dpiX),
        physicalPixelsToDip(surface.physicalBounds.height, surface.dpiY),
    };
    return computeTeachingPenToolbarLayout(pointer, bounds);
}

std::optional<AnnotationPoint>
OverlayInputRouter::teachingPenOptionsOrigin(
    const OverlaySurface& surface,
    float height) const noexcept
{
    const auto toolbar = teachingPenToolbarLayout(surface);
    if (!toolbar.has_value()) return std::nullopt;
    const ToolbarRect bounds{
        0.0F,
        0.0F,
        physicalPixelsToDip(surface.physicalBounds.width, surface.dpiX),
        physicalPixelsToDip(surface.physicalBounds.height, surface.dpiY),
    };
    const auto origin = attachedTeachingPenToolbarOrigin(
        toolbar->bounds, bounds, height);
    return AnnotationPoint{origin.x, origin.y};
}

std::optional<AnnotationPoint> OverlayInputRouter::annotationPoint(
    PixelPoint virtualPoint) const noexcept
{
    if (!editor_ || !editorOwnerIndex_.has_value()
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    const auto selection = snipory::core::portable::standardized(
        *model_.selection());
    const auto& owner = surfaces_[*editorOwnerIndex_];
    return AnnotationPoint{
        annotationViewportOrigin_.x
            + physicalPixelsToDip(
                virtualPoint.x - selection.x, owner.dpiX)
                / annotationViewportScale_,
        annotationViewportOrigin_.y
            + physicalPixelsToDip(
                virtualPoint.y - selection.y, owner.dpiY)
                / annotationViewportScale_,
    };
}

bool OverlayInputRouter::eyedropperPointIsValid(
    PixelPoint virtualPoint) const noexcept
{
    return model_.selection().has_value()
        && contains(*model_.selection(), virtualPoint);
}

void OverlayInputRouter::clearEyedropperState() noexcept
{
    eyedropperComposite_.reset();
    eyedropperSamplePoint_.reset();
    eyedropperSampleColor_.reset();
    eyedropperMagnifier_.fill({});
    eyedropperMeasurementStart_.reset();
    eyedropperMeasurementEnd_.reset();
    eyedropperMeasurementInProgress_ = false;
    eyedropperCopyMode_ = EyedropperCopyMode::hex;
    eyedropperCopySuccessUntil_.reset();
}

std::optional<PixelBuffer>
OverlayInputRouter::composeCurrentSelection() const noexcept
{
    if (desktop_ == nullptr || !model_.selection().has_value()) {
        return std::nullopt;
    }
    try {
        const auto selection = snipory::core::portable::standardized(
            *model_.selection());
        const auto cacheMatches = rawSelectionCacheSelection_.has_value()
            && rawSelectionCacheSelection_->x == selection.x
            && rawSelectionCacheSelection_->y == selection.y
            && rawSelectionCacheSelection_->width == selection.width
            && rawSelectionCacheSelection_->height == selection.height;
        if (!cacheMatches || rawSelectionCache_ == nullptr) {
            rawSelectionCache_.reset();
            rawSelectionCacheSelection_.reset();
            MemoryBudget rawBudget(512U * 1024U * 1024U);
            auto raw = composeSelection(selection, *desktop_, rawBudget);
            auto* pixels = std::get_if<PixelBuffer>(&raw);
            if (pixels == nullptr) {
                return std::nullopt;
            }
            rawSelectionCache_ = std::make_shared<PixelBuffer>(
                std::move(*pixels));
            rawSelectionCacheSelection_ = selection;
        }
        MemoryBudget outputBudget(512U * 1024U * 1024U);
        auto output = PixelBuffer::allocate(rawSelectionCache_->width(),
            rawSelectionCache_->height(), outputBudget);
        if (!output.value) {
            return std::nullopt;
        }
        std::memcpy(output.value->data(), rawSelectionCache_->data(),
            rawSelectionCache_->byteCount());
        auto* pixels = output.value.get();
        if (editor_ != nullptr && editorOwnerIndex_.has_value()) {
            const auto& owner = surfaces_[*editorOwnerIndex_];
            const auto plan = scaledRenderPlan(editor_->renderPlan({
                -annotationViewportOrigin_.x,
                -annotationViewportOrigin_.y,
            }, false), annotationViewportScale_);
            auto eraserMasks = editor_->document().eraserMasks();
            if (mode_ == OverlayMode::longImageEditor) {
                for (auto& mask : eraserMasks) {
                    mask.rect = translated(mask.rect, {
                        -annotationViewportOrigin_.x,
                        -annotationViewportOrigin_.y,
                    });
                    mask = scaled(
                        std::move(mask), annotationViewportScale_,
                        annotationViewportScale_);
                }
            }
            if (composeAnnotations(
                    *pixels, plan, owner.dpiX, owner.dpiY,
                    mode_ == OverlayMode::longImageEditor
                        ? 0 : model_.selection()->x,
                    mode_ == OverlayMode::longImageEditor
                        ? 0 : model_.selection()->y,
                    rawSelectionCache_.get(),
                    eraserMasks).has_value()) {
                return std::nullopt;
            }
        }
        return std::move(*pixels);
    } catch (...) {
        return std::nullopt;
    }
}

void OverlayInputRouter::refreshEyedropperComposite() noexcept
{
    eyedropperComposite_.reset();
    if (auto composition = composeCurrentSelection()) {
        eyedropperComposite_ = std::make_unique<PixelBuffer>(
            std::move(*composition));
    }
}

void OverlayInputRouter::updateEyedropper(
    PixelPoint virtualPoint,
    bool shift) noexcept
{
    if (editor_ == nullptr || !editor_->isEyedropperToolActive()
        || !eyedropperPointIsValid(virtualPoint)
        || eyedropperComposite_ == nullptr
        || !model_.selection().has_value()) {
        eyedropperSamplePoint_.reset();
        eyedropperSampleColor_.reset();
        return;
    }
    const auto selection = snipory::core::portable::standardized(
        *model_.selection());
    const auto localX = (std::max<std::int64_t>)(0,
        (std::min<std::int64_t>)(eyedropperComposite_->width() - 1,
            virtualPoint.x - selection.x));
    const auto localY = (std::max<std::int64_t>)(0,
        (std::min<std::int64_t>)(eyedropperComposite_->height() - 1,
            virtualPoint.y - selection.y));
    const auto colorAt = [this](std::int64_t x, std::int64_t y) {
        x = (std::max<std::int64_t>)(0,
            (std::min<std::int64_t>)(eyedropperComposite_->width() - 1, x));
        y = (std::max<std::int64_t>)(0,
            (std::min<std::int64_t>)(eyedropperComposite_->height() - 1, y));
        const auto* pixel = eyedropperComposite_->data()
            + static_cast<std::uint64_t>(y) * eyedropperComposite_->stride()
            + static_cast<std::uint64_t>(x) * 4U;
        return AnnotationColor{
            static_cast<std::uint8_t>(pixel[2]),
            static_cast<std::uint8_t>(pixel[1]),
            static_cast<std::uint8_t>(pixel[0]),
            255,
        };
    };
    eyedropperSamplePoint_ = virtualPoint;
    eyedropperSampleColor_ = colorAt(localX, localY);
    for (int row = 0; row < 9; ++row) {
        for (int column = 0; column < 9; ++column) {
            eyedropperMagnifier_[static_cast<std::size_t>(row * 9 + column)] =
                colorAt(localX + column - 4, localY + row - 4);
        }
    }
    if (eyedropperMeasurementInProgress_
        && eyedropperMeasurementStart_.has_value()) {
        auto end = AnnotationPoint{
            static_cast<float>(virtualPoint.x),
            static_cast<float>(virtualPoint.y),
        };
        if (shift) {
            const auto start = AnnotationPoint{
                static_cast<float>(eyedropperMeasurementStart_->x),
                static_cast<float>(eyedropperMeasurementStart_->y),
            };
            end = snappedAnnotationEnd(start, end);
        }
        eyedropperMeasurementEnd_ = PixelPoint{
            static_cast<std::int64_t>(std::llround(end.x)),
            static_cast<std::int64_t>(std::llround(end.y)),
        };
    }
}

std::optional<ShapeOptionsLayout>
OverlayInputRouter::currentShapeOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isShapeToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    if (mode_ == OverlayMode::teachingPen) {
        const auto initial = teachingPenShapeOptionsLayout(
            {}, macShapePalette().size());
        const auto origin = teachingPenOptionsOrigin(
            surface, initial.toolbar.height);
        return origin.has_value()
            ? std::optional<ShapeOptionsLayout>(
                teachingPenShapeOptionsLayout(
                    *origin, macShapePalette().size()))
            : std::nullopt;
    }
    const auto actions = toolbarActions();
    const auto chrome = computeOverlayLayout({
        surface.physicalBounds,
        *model_.selection(),
        surface.dpiX,
        surface.dpiY,
        0.0F,
        true,
        actions,
    });
    const auto initial = shapeOptionsLayout({}, macShapePalette().size());
    return shapeOptionsLayout(
        optionsToolbarOrigin(chrome, initial.toolbar), macShapePalette().size());
}

std::optional<ArrowLineOptionsLayout>
OverlayInputRouter::currentArrowLineOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isArrowLineToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    if (mode_ == OverlayMode::teachingPen) {
        const auto initial = teachingPenArrowLineOptionsLayout(
            {}, macShapePalette().size());
        const auto origin = teachingPenOptionsOrigin(
            surface, initial.toolbar.height);
        return origin.has_value()
            ? std::optional<ArrowLineOptionsLayout>(
                teachingPenArrowLineOptionsLayout(
                    *origin, macShapePalette().size()))
            : std::nullopt;
    }
    const auto chrome = computeOverlayLayout({
        surface.physicalBounds,
        *model_.selection(),
        surface.dpiX,
        surface.dpiY,
        0.0F,
        true,
        toolbarActions(),
    });
    const auto initial = arrowLineOptionsLayout({}, macShapePalette().size());
    return arrowLineOptionsLayout(
        optionsToolbarOrigin(chrome, initial.toolbar), macShapePalette().size());
}

std::optional<BrushOptionsLayout>
OverlayInputRouter::currentBrushOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isBrushToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    if (mode_ == OverlayMode::teachingPen) {
        const auto initial = teachingPenBrushOptionsLayout(
            {}, macShapePalette().size());
        const auto origin = teachingPenOptionsOrigin(
            surface, initial.toolbar.height);
        return origin.has_value()
            ? std::optional<BrushOptionsLayout>(
                teachingPenBrushOptionsLayout(
                    *origin, macShapePalette().size()))
            : std::nullopt;
    }
    const auto chrome = computeOverlayLayout({
        surface.physicalBounds,
        *model_.selection(),
        surface.dpiX,
        surface.dpiY,
        0.0F,
        true,
        toolbarActions(),
    });
    const auto initial = brushOptionsLayout({}, macShapePalette().size());
    return brushOptionsLayout(
        optionsToolbarOrigin(chrome, initial.toolbar), macShapePalette().size());
}

std::optional<MarkerOptionsLayout>
OverlayInputRouter::currentMarkerOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isMarkerToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    if (mode_ == OverlayMode::teachingPen) {
        const auto initial = teachingPenMarkerOptionsLayout(
            {}, macShapePalette().size());
        const auto origin = teachingPenOptionsOrigin(
            surface, initial.toolbar.height);
        return origin.has_value()
            ? std::optional<MarkerOptionsLayout>(
                teachingPenMarkerOptionsLayout(
                    *origin, macShapePalette().size()))
            : std::nullopt;
    }
    const auto chrome = computeOverlayLayout({
        surface.physicalBounds,
        *model_.selection(),
        surface.dpiX,
        surface.dpiY,
        0.0F,
        true,
        toolbarActions(),
    });
    const auto initial = markerOptionsLayout({}, macShapePalette().size());
    return markerOptionsLayout(
        optionsToolbarOrigin(chrome, initial.toolbar), macShapePalette().size());
}

std::optional<MosaicOptionsLayout>
OverlayInputRouter::currentMosaicOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isMosaicToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    if (mode_ == OverlayMode::teachingPen) {
        const auto initial = teachingPenMosaicOptionsLayout({});
        const auto origin = teachingPenOptionsOrigin(
            surface, initial.toolbar.height);
        return origin.has_value()
            ? std::optional<MosaicOptionsLayout>(
                teachingPenMosaicOptionsLayout(*origin))
            : std::nullopt;
    }
    const auto chrome = computeOverlayLayout({
        surface.physicalBounds,
        *model_.selection(),
        surface.dpiX,
        surface.dpiY,
        0.0F,
        true,
        toolbarActions(),
    });
    const auto initial = mosaicOptionsLayout({});
    return mosaicOptionsLayout(
        optionsToolbarOrigin(chrome, initial.toolbar));
}

std::optional<TextOptionsLayout>
OverlayInputRouter::currentTextOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isTextToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    if (mode_ == OverlayMode::teachingPen) {
        const auto initial = teachingPenTextOptionsLayout(
            {}, macShapePalette().size());
        const auto origin = teachingPenOptionsOrigin(
            surface, initial.toolbar.height);
        return origin.has_value()
            ? std::optional<TextOptionsLayout>(
                teachingPenTextOptionsLayout(
                    *origin, macShapePalette().size()))
            : std::nullopt;
    }
    const auto chrome = computeOverlayLayout({
        surface.physicalBounds,
        *model_.selection(),
        surface.dpiX,
        surface.dpiY,
        0.0F,
        true,
        toolbarActions(),
    });
    const auto initial = textOptionsLayout({}, macShapePalette().size());
    return textOptionsLayout(
        optionsToolbarOrigin(chrome, initial.toolbar),
        macShapePalette().size());
}

std::optional<NumberOptionsLayout>
OverlayInputRouter::currentNumberOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isNumberToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    if (mode_ == OverlayMode::teachingPen) {
        const auto initial = teachingPenNumberOptionsLayout(
            {}, macShapePalette().size());
        const auto origin = teachingPenOptionsOrigin(
            surface, initial.toolbar.height);
        return origin.has_value()
            ? std::optional<NumberOptionsLayout>(
                teachingPenNumberOptionsLayout(
                    *origin, macShapePalette().size()))
            : std::nullopt;
    }
    const auto chrome = computeOverlayLayout({
        surface.physicalBounds,
        *model_.selection(),
        surface.dpiX,
        surface.dpiY,
        0.0F,
        true,
        toolbarActions(),
    });
    const auto initial = numberOptionsLayout({}, macShapePalette().size());
    return numberOptionsLayout(
        optionsToolbarOrigin(chrome, initial.toolbar),
        macShapePalette().size());
}

std::optional<MagnifierOptionsLayout>
OverlayInputRouter::currentMagnifierOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isMagnifierToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    if (mode_ == OverlayMode::teachingPen) {
        const auto initial = teachingPenMagnifierOptionsLayout(
            {}, macShapePalette().size());
        const auto origin = teachingPenOptionsOrigin(
            surface, initial.toolbar.height);
        return origin.has_value()
            ? std::optional<MagnifierOptionsLayout>(
                teachingPenMagnifierOptionsLayout(
                    *origin, macShapePalette().size()))
            : std::nullopt;
    }
    const auto chrome = computeOverlayLayout({
        surface.physicalBounds,
        *model_.selection(),
        surface.dpiX,
        surface.dpiY,
        0.0F,
        true,
        toolbarActions(),
    });
    const auto initial = magnifierOptionsLayout(
        {}, macShapePalette().size());
    return magnifierOptionsLayout(
        optionsToolbarOrigin(chrome, initial.toolbar),
        macShapePalette().size());
}

std::optional<EraserOptionsLayout>
OverlayInputRouter::currentEraserOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isEraserToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    if (mode_ == OverlayMode::teachingPen) {
        const auto initial = teachingPenEraserOptionsLayout({});
        const auto origin = teachingPenOptionsOrigin(
            surface, initial.toolbar.height);
        return origin.has_value()
            ? std::optional<EraserOptionsLayout>(
                teachingPenEraserOptionsLayout(*origin))
            : std::nullopt;
    }
    const auto chrome = computeOverlayLayout({
        surface.physicalBounds,
        *model_.selection(),
        surface.dpiX,
        surface.dpiY,
        0.0F,
        true,
        toolbarActions(),
    });
    const auto initial = eraserOptionsLayout({});
    return eraserOptionsLayout(optionsToolbarOrigin(chrome, initial.toolbar));
}

bool OverlayInputRouter::handleCornerRadiusPanelPointer(
    const OverlaySurface& surface,
    PixelPoint clientPoint) noexcept
{
    if (!editor_ || !editor_->cornerRadiusPanelVisible()) return false;
    const auto options = currentShapeOptionsLayout(surface);
    if (!options.has_value()) return false;
    const AnnotationPoint point{
        static_cast<float>(clientPoint.x) * 96.0F
            / static_cast<float>(surface.dpiX),
        static_cast<float>(clientPoint.y) * 96.0F
            / static_cast<float>(surface.dpiY),
    };
    const AnnotationRect safe{
        0.0F,
        0.0F,
        physicalPixelsToDip(surface.physicalBounds.width, surface.dpiX),
        physicalPixelsToDip(surface.physicalBounds.height, surface.dpiY),
    };
    const auto panel = cornerRadiusPanelLayout(*options, safe);
    if (contains(panel.increment, point)) {
        editor_->adjustCornerRadius(1.0F);
        return true;
    }
    if (contains(panel.decrement, point)) {
        editor_->adjustCornerRadius(-1.0F);
        return true;
    }
    const AnnotationRect sliderHit{
        panel.sliderTrack.x - 5.0F,
        panel.sliderTrack.y - 8.0F,
        panel.sliderTrack.width + 10.0F,
        panel.sliderTrack.height + 16.0F,
    };
    if (contains(sliderHit, point) && panel.sliderTrack.width > 0.0F) {
        const auto ratio = (std::max)(0.0F, (std::min)(
            1.0F,
            (point.x - panel.sliderTrack.x) / panel.sliderTrack.width));
        editor_->setCornerRadius(
            static_cast<float>(static_cast<int>(ratio * 30.0F + 0.5F)));
        return true;
    }
    return contains(panel.panel, point);
}

OverlayInputRouter::~OverlayInputRouter()
{
    if (dragging_) {
        dragging_ = false;
        if (!platform_.releaseMouse()) {
            lastError_ = OverlayInputErrorCode::mouseReleaseFailed;
        }
    }
    if (escapeHotKeyWindow_ != nullptr) {
        deactivateEscapeHotKey();
    }
}

bool OverlayInputRouter::activateEscapeHotKey(HWND owner) noexcept
{
    if (escapeHotKeyWindow_ == owner && owner != nullptr) {
        return true;
    }
    if (status_ != OverlayInputStatus::active || owner == nullptr
        || escapeHotKeyWindow_ != nullptr) {
        return false;
    }
    if (!platform_.registerEscapeHotKey(
            owner, overlayEscapeHotKeyIdentifier)) {
        lastError_ = OverlayInputErrorCode::escapeHotKeyRegistrationFailed;
        status_ = OverlayInputStatus::cancelled;
        return false;
    }
    escapeHotKeyWindow_ = owner;
    if (shapeAnnotationsEnabled_) {
        editorHotKeysRegistered_ = platform_.registerEditorHotKeys(owner);
        toolbarHotKeysRegistered_ = platform_.registerToolbarHotKeys(owner);
    }
    return true;
}

bool OverlayInputRouter::deactivateEscapeHotKey() noexcept
{
    if (escapeHotKeyWindow_ == nullptr) {
        return true;
    }
    if (editorHotKeysRegistered_) {
        platform_.unregisterEditorHotKeys(escapeHotKeyWindow_);
        editorHotKeysRegistered_ = false;
    }
    if (toolbarHotKeysRegistered_) {
        platform_.unregisterToolbarHotKeys(escapeHotKeyWindow_);
        toolbarHotKeysRegistered_ = false;
    }
    if (!platform_.unregisterEscapeHotKey(
            escapeHotKeyWindow_, overlayEscapeHotKeyIdentifier)) {
        lastError_ = OverlayInputErrorCode::escapeHotKeyUnregistrationFailed;
        return false;
    }
    escapeHotKeyWindow_ = nullptr;
    return true;
}

const OverlaySurface* OverlayInputRouter::surfaceFor(HWND window) const noexcept
{
    const auto found = std::find_if(
        surfaces_.begin(), surfaces_.end(),
        [window](const OverlaySurface& surface) { return surface.window == window; });
    return found == surfaces_.end() ? nullptr : &*found;
}

PixelPoint OverlayInputRouter::toVirtual(
    const OverlaySurface& surface, PixelPoint clientPoint) const noexcept
{
    return {
        saturatingAdd(surface.physicalBounds.x, clientPoint.x),
        saturatingAdd(surface.physicalBounds.y, clientPoint.y),
    };
}

std::optional<std::size_t> OverlayInputRouter::actionOwner() const noexcept
{
    if (status_ != OverlayInputStatus::active
        || model_.phase() != SelectionPhase::ready
        || !model_.selection().has_value()) {
        return std::nullopt;
    }
    const auto selection = snipory::core::portable::standardized(
        *model_.selection());
    const PixelPoint bottomRight{
        saturatingAdd(selection.x, selection.width - 1),
        saturatingAdd(selection.y, selection.height - 1),
    };
    for (std::size_t index = 0; index < surfaces_.size(); ++index) {
        if (contains(surfaces_[index].physicalBounds, bottomRight)) {
            return index;
        }
    }

    std::optional<std::size_t> best;
    long double bestArea = 0;
    for (std::size_t index = 0; index < surfaces_.size(); ++index) {
        const auto clipped = snipory::core::portable::intersection(
            selection, surfaces_[index].physicalBounds);
        if (!clipped.has_value()) {
            continue;
        }
        const auto area = static_cast<long double>(clipped->width)
            * static_cast<long double>(clipped->height);
        if (!best.has_value() || area > bestArea) {
            best = index;
            bestArea = area;
        }
    }
    return best;
}

std::vector<OverlayPresentation> OverlayInputRouter::presentations() const
{
    std::vector<OverlayPresentation> result(surfaces_.size());
    const auto owner = actionOwner();
    for (std::size_t index = 0; index < surfaces_.size(); ++index) {
        auto& presentation = result[index];
        presentation.selection = model_.selection();
        presentation.showActions = owner.has_value() && *owner == index;
        presentation.pinnedImageEditor
            = mode_ == OverlayMode::pinnedImageEditor
            || mode_ == OverlayMode::longImageEditor;
        presentation.textRecognition
            = mode_ == OverlayMode::textRecognition;
        presentation.teachingPen
            = mode_ == OverlayMode::teachingPen;
        if (presentation.textRecognition) {
            presentation.showActions = false;
        }
        if (presentation.teachingPen) {
            presentation.teachingPenToolbar = teachingPenToolbarLayout(
                surfaces_[index]);
            presentation.showActions
                = presentation.teachingPenToolbar.has_value();
        }
        if ((!presentation.teachingPen && !presentation.showActions)
            || !presentation.selection.has_value()) {
            continue;
        }
        const auto& surface = surfaces_[index];
        const auto actions = toolbarActions();
        const auto layout = computeOverlayLayout({
            surface.physicalBounds,
            *presentation.selection,
            surface.dpiX,
            surface.dpiY,
            0.0F,
            true,
            actions,
        });
        if (presentation.showActions) {
            const auto& toolbarItems = presentation.teachingPenToolbar.has_value()
                ? presentation.teachingPenToolbar->items
                : layout.toolbar.items;
            presentation.toolbarItems.reserve(toolbarItems.size());
            for (const auto& item : toolbarItems) {
                const auto rect = buttonRectPhysical(item.rect, surface);
                presentation.toolbarItems.push_back({
                    item.action,
                    rect,
                    buttonCenterPhysical(rect),
                    editor_ != nullptr
                        && editor_->toolbarState().selectedAction() == item.action,
                    toolbarActionEnabled(item.action),
                });
            }
            if (hoveredToolbarWindow_ == surface.window
                && hoveredToolbarAction_.has_value()) {
                const auto hovered = std::find_if(
                    presentation.toolbarItems.begin(),
                    presentation.toolbarItems.end(),
                    [this](const auto& item) {
                        return item.action == *hoveredToolbarAction_;
                    });
                if (hovered != presentation.toolbarItems.end()) {
                    presentation.toolbarTooltip
                        = OverlayPresentationToolbarTooltip{
                            hoveredToolbarTooltipText_,
                            hovered->rectPhysical,
                        };
                }
            }
        }
        if (editor_ != nullptr
            && (editorOwnerIndex_ == index
                || mode_ == OverlayMode::teachingPen)) {
            const auto selection = snipory::core::portable::standardized(
                *presentation.selection);
            presentation.annotationPlan = scaledRenderPlan(editor_->renderPlan({
                physicalPixelsToDip(
                    selection.x - surface.physicalBounds.x, surface.dpiX)
                        / annotationViewportScale_
                    - annotationViewportOrigin_.x,
                physicalPixelsToDip(
                    selection.y - surface.physicalBounds.y, surface.dpiY)
                        / annotationViewportScale_
                    - annotationViewportOrigin_.y,
            }), annotationViewportScale_);
            const auto requiresComposite = !editor_->document().eraserMasks().empty()
                || std::any_of(
                presentation.annotationPlan.items.begin(),
                presentation.annotationPlan.items.end(),
                [](const auto& item) {
                    return isMosaicAnnotation(item.annotation);
                });
            if (requiresComposite && desktop_ != nullptr) {
                const auto cachedSelectionMatches
                    = annotationCompositeSelection_.has_value()
                    && annotationCompositeSelection_->x == selection.x
                    && annotationCompositeSelection_->y == selection.y
                    && annotationCompositeSelection_->width == selection.width
                    && annotationCompositeSelection_->height == selection.height;
                const auto documentRevision = editor_->document().revision();
                const auto interactionRevision
                    = editor_->isEraserToolActive()
                        && annotationCompositeCache_ != nullptr
                    ? annotationCompositeInteractionRevision_
                    : editor_->interactionRevision();
                if (!cachedSelectionMatches
                    || annotationCompositeDocumentRevision_ != documentRevision
                    || annotationCompositeInteractionRevision_
                        != interactionRevision
                    || annotationCompositeCache_ == nullptr) {
                    annotationCompositeCache_.reset();
                    if (auto composition = composeCurrentSelection()) {
                        annotationCompositeCache_ = std::make_shared<PixelBuffer>(
                            std::move(*composition));
                    }
                    annotationCompositeSelection_ = selection;
                    annotationCompositeDocumentRevision_ = documentRevision;
                    annotationCompositeInteractionRevision_
                        = interactionRevision;
                }
                if (annotationCompositeCache_ != nullptr) {
                    presentation.annotationComposite = annotationCompositeCache_;
                    presentation.annotationPlanOutsideSelectionOnly = true;
                }
            } else {
                annotationCompositeCache_.reset();
                annotationCompositeSelection_.reset();
            }
            if (const auto options = currentShapeOptionsLayout(surface)) {
                OverlayPresentationShapeOptions shapeOptions{
                    *options,
                    editor_->options(),
                    std::nullopt,
                    std::nullopt,
                };
                const AnnotationRect safe{
                    0.0F,
                    0.0F,
                    layout.overlayBounds.width,
                    layout.overlayBounds.height,
                };
                if (editor_->strokePatternMenuVisible()) {
                    shapeOptions.strokePatternMenu =
                        strokePatternMenuFor(options->strokeStyle, safe.height);
                }
                if (editor_->cornerRadiusPanelVisible()) {
                    shapeOptions.cornerRadiusPanel = cornerRadiusPanelLayout(
                        *options, safe);
                }
                presentation.shapeOptions = std::move(shapeOptions);
            }
            if (const auto options = currentArrowLineOptionsLayout(surface)) {
                OverlayPresentationArrowLineOptions arrowOptions{
                    *options,
                    editor_->arrowLineOptions(),
                    std::nullopt,
                };
                if (editor_->strokePatternMenuVisible()) {
                    const auto safeHeight = physicalPixelsToDip(
                        surface.physicalBounds.height, surface.dpiY);
                    arrowOptions.strokePatternMenu =
                        strokePatternMenuFor(options->strokeStyle, safeHeight);
                }
                if (const auto endpoint = editor_->arrowTypeMenuEndpoint()) {
                    const auto safeHeight = physicalPixelsToDip(
                        surface.physicalBounds.height, surface.dpiY);
                    arrowOptions.arrowTypeMenu = arrowTypeMenuFor(
                        *options, *endpoint, safeHeight);
                    arrowOptions.arrowTypeMenuEndpoint = endpoint;
                }
                presentation.arrowLineOptions = std::move(arrowOptions);
            }
            if (const auto options = currentBrushOptionsLayout(surface)) {
                OverlayPresentationBrushOptions brushOptions{
                    *options,
                    editor_->brushOptions(),
                    std::nullopt,
                };
                if (editor_->strokePatternMenuVisible()) {
                    const auto safeHeight = physicalPixelsToDip(
                        surface.physicalBounds.height, surface.dpiY);
                    brushOptions.strokePatternMenu = strokePatternMenuFor(
                        options->strokeStyle, safeHeight,
                        macBrushStrokePatterns().size());
                }
                presentation.brushOptions = std::move(brushOptions);
            }
            if (const auto options = currentMarkerOptionsLayout(surface)) {
                presentation.markerOptions = OverlayPresentationMarkerOptions{
                    *options,
                    editor_->markerOptions(),
                };
            }
            if (const auto options = currentMosaicOptionsLayout(surface)) {
                presentation.mosaicOptions = OverlayPresentationMosaicOptions{
                    *options,
                    editor_->mosaicOptions(),
                };
            }
            if (const auto options = currentTextOptionsLayout(surface)) {
                OverlayPresentationTextOptions textOptions{
                    *options,
                    editor_->textOptions(),
                    std::nullopt,
                    {},
                    std::nullopt,
                };
                if (const auto menu = editor_->textPopupMenu()) {
                    const auto safeHeight = physicalPixelsToDip(
                        surface.physicalBounds.height, surface.dpiY);
                    const auto data = textPopupDataFor(
                        *menu, *options, editor_->textOptions(), safeHeight,
                        editor_->popupScrollOffset());
                    textOptions.popupMenu = data.layout;
                    textOptions.popupLabels = data.labels;
                    textOptions.selectedPopupIndex = data.selectedIndex;
                }
                presentation.textOptions = std::move(textOptions);
            }
            if (const auto options = currentNumberOptionsLayout(surface)) {
                OverlayPresentationNumberOptions numberOptions{
                    *options,
                    editor_->numberOptions(),
                    std::nullopt,
                    std::nullopt,
                    {},
                    std::nullopt,
                };
                if (const auto menu = editor_->numberPopupMenu()) {
                    const auto safeHeight = physicalPixelsToDip(
                        surface.physicalBounds.height, surface.dpiY);
                    const auto data = numberPopupDataFor(
                        *menu, *options, editor_->numberOptions(), safeHeight,
                        editor_->popupScrollOffset());
                    numberOptions.popupMenu = data.layout;
                    numberOptions.popupKind = menu;
                    numberOptions.popupLabels = data.labels;
                    numberOptions.selectedPopupIndex = data.selectedIndex;
                }
                presentation.numberOptions = std::move(numberOptions);
            }
            if (const auto options = currentMagnifierOptionsLayout(surface)) {
                OverlayPresentationMagnifierOptions magnifierOptions{
                    *options,
                    editor_->magnifierOptions(),
                    std::nullopt,
                };
                if (editor_->magnifierZoomMenuVisible()) {
                    const auto safeHeight = physicalPixelsToDip(
                        surface.physicalBounds.height, surface.dpiY);
                    magnifierOptions.zoomMenu = popupMenuLayout(
                        options->zoom, magnifierZoomOptions.size(), safeHeight);
                }
                presentation.magnifierOptions =
                    std::move(magnifierOptions);
            }
            if (const auto options = currentEraserOptionsLayout(surface)) {
                presentation.eraserOptions = OverlayPresentationEraserOptions{
                    *options,
                    editor_->eraserMode(),
                };
            }
            if (editor_->isEyedropperToolActive()
                && eyedropperSamplePoint_.has_value()
                && eyedropperSampleColor_.has_value()) {
                const auto toSurfaceDip = [&surface](PixelPoint point) {
                    return AnnotationPoint{
                        physicalPixelsToDip(
                            point.x - surface.physicalBounds.x, surface.dpiX),
                        physicalPixelsToDip(
                            point.y - surface.physicalBounds.y, surface.dpiY),
                    };
                };
                OverlayPresentationEyedropper eyedropper;
                eyedropper.pointer = toSurfaceDip(*eyedropperSamplePoint_);
                eyedropper.color = *eyedropperSampleColor_;
                eyedropper.magnifier = eyedropperMagnifier_;
                eyedropper.copyMode = eyedropperCopyMode_;
                if (eyedropperCopySuccessUntil_.has_value()) {
                    const auto remaining = std::chrono::duration_cast<
                        std::chrono::milliseconds>(
                        *eyedropperCopySuccessUntil_
                        - std::chrono::steady_clock::now()).count();
                    if (remaining > 0) {
                        eyedropper.copySuccessMillisecondsRemaining
                            = static_cast<std::uint32_t>((std::min<std::int64_t>)(
                                remaining, 1200));
                    }
                }
                if (eyedropperMeasurementStart_.has_value()
                    && eyedropperMeasurementEnd_.has_value()) {
                    const auto length = eyedropperPixelLength(
                        {static_cast<float>(eyedropperMeasurementStart_->x),
                            static_cast<float>(eyedropperMeasurementStart_->y)},
                        {static_cast<float>(eyedropperMeasurementEnd_->x),
                            static_cast<float>(eyedropperMeasurementEnd_->y)});
                    if (length > 0) {
                        eyedropper.measurementStart = toSurfaceDip(
                            *eyedropperMeasurementStart_);
                        eyedropper.measurementEnd = toSurfaceDip(
                            *eyedropperMeasurementEnd_);
                        eyedropper.measurementLabel = std::to_wstring(length)
                            + L" px";
                    }
                }
                presentation.eyedropper = std::move(eyedropper);
            }
        }
    }
    return result;
}

std::optional<ToolbarAction> OverlayInputRouter::hitToolbarAction(
    const OverlaySurface& surface, PixelPoint clientPoint) const noexcept
{
    const auto owner = actionOwner();
    if (!model_.selection().has_value()) {
        return std::nullopt;
    }
    if (mode_ == OverlayMode::teachingPen) {
        const auto layout = teachingPenToolbarLayout(surface);
        if (!layout.has_value()) return std::nullopt;
        const auto point = ToolbarPoint{
            static_cast<float>(clientPoint.x) * 96.0F
                / static_cast<float>(surface.dpiX),
            static_cast<float>(clientPoint.y) * 96.0F
                / static_cast<float>(surface.dpiY),
        };
        return toolbarActionAt(*layout, point);
    }
    if (!owner.has_value() || &surfaces_[*owner] != &surface) {
        return std::nullopt;
    }
    const auto layout = computeOverlayLayout({
        surface.physicalBounds,
        *model_.selection(),
        surface.dpiX,
        surface.dpiY,
        0.0F,
        true,
        toolbarActions(),
    });
    const auto x = static_cast<float>(clientPoint.x) * 96.0F
        / static_cast<float>(surface.dpiX);
    const auto y = static_cast<float>(clientPoint.y) * 96.0F
        / static_cast<float>(surface.dpiY);
    return toolbarActionAt(layout.toolbar, {x, y});
}

bool OverlayInputRouter::pointerDown(
    HWND source,
    PixelPoint clientPoint,
    int clickCount) noexcept
{
    cancelPinnedImageShiftShortcut();
    if (status_ != OverlayInputStatus::active || dragging_) {
        return false;
    }
    const auto* surface = surfaceFor(source);
    if (surface == nullptr) {
        return false;
    }
    if (editor_ != nullptr && editorOwnerIndex_.has_value()
        && (&surfaces_[*editorOwnerIndex_] == surface
            || mode_ == OverlayMode::teachingPen)) {
        const AnnotationPoint point{
            static_cast<float>(clientPoint.x) * 96.0F
                / static_cast<float>(surface->dpiX),
            static_cast<float>(clientPoint.y) * 96.0F
                / static_cast<float>(surface->dpiY),
        };
        const auto safeHeight = physicalPixelsToDip(
            surface->physicalBounds.height, surface->dpiY);
        if (editor_->strokePatternMenuVisible()) {
            std::optional<StrokePatternMenuLayout> menu;
            if (const auto brushOptions
                = currentBrushOptionsLayout(*surface)) {
                menu = strokePatternMenuFor(
                    brushOptions->strokeStyle, safeHeight,
                    macBrushStrokePatterns().size());
            } else if (const auto arrowOptions
                = currentArrowLineOptionsLayout(*surface)) {
                menu = strokePatternMenuFor(
                    arrowOptions->strokeStyle, safeHeight);
            } else if (const auto shapeOptions
                = currentShapeOptionsLayout(*surface)) {
                menu = strokePatternMenuFor(
                    shapeOptions->strokeStyle, safeHeight);
            }
            if (menu.has_value()) {
                if (const auto pattern = hitTestStrokePatternMenu(*menu, point)) {
                    editor_->applyStrokePattern(*pattern);
                    return true;
                }
                if (contains(menu->menu, point)) {
                    return true;
                }
            }
        }
        if (const auto endpoint = editor_->arrowTypeMenuEndpoint()) {
            if (const auto options = currentArrowLineOptionsLayout(*surface)) {
                const auto menu = arrowTypeMenuFor(
                    *options, *endpoint, safeHeight);
                if (const auto type = hitTestArrowTypeMenu(menu, point)) {
                    editor_->applyArrowType(*endpoint, *type);
                    return true;
                }
                if (contains(menu.menu, point)) {
                    return true;
                }
            }
        }
    }
    if (handleCornerRadiusPanelPointer(*surface, clientPoint)) {
        return true;
    }
    if (const auto action = hitToolbarAction(*surface, clientPoint)) {
        if (!toolbarActionEnabled(*action)) return true;
        performToolbarAction(*action);
        return true;
    }
    if (editor_ != nullptr && editorOwnerIndex_.has_value()
        && &surfaces_[*editorOwnerIndex_] == surface) {
        const auto x = static_cast<float>(clientPoint.x) * 96.0F
            / static_cast<float>(surface->dpiX);
        const auto y = static_cast<float>(clientPoint.y) * 96.0F
            / static_cast<float>(surface->dpiY);
        if (const auto options = currentShapeOptionsLayout(*surface);
            options.has_value()) {
            const AnnotationPoint point{x, y};
            if (const auto hit = shapeOptionHitTest(*options, {x, y});
                hit.has_value()) {
                if (hit->control == ShapeOptionControl::customColor) {
                    if (const auto chosen = platform_.chooseColor(
                            source, editor_->options().style().strokeColor)) {
                        editor_->selectCustomColor(*chosen);
                    }
                    return true;
                }
                editor_->applyOptionHit(*hit);
                return true;
            }
            editor_->dismissPopovers();
        }
        if (const auto options = currentArrowLineOptionsLayout(*surface);
            options.has_value()) {
            const AnnotationPoint point{x, y};
            if (const auto hit = arrowLineOptionHitTest(*options, point)) {
                if (hit->control == ArrowLineOptionControl::customColor) {
                    if (const auto chosen = platform_.chooseColor(
                            source,
                            editor_->arrowLineOptions().style().strokeColor)) {
                        editor_->selectCustomColor(*chosen);
                    }
                    return true;
                }
                if (hit->control == ArrowLineOptionControl::startArrowType
                    || hit->control == ArrowLineOptionControl::endArrowType) {
                    editor_->applyArrowLineOptionHit(*hit);
                    return true;
                }
                editor_->applyArrowLineOptionHit(*hit);
                return true;
            }
            editor_->dismissPopovers();
        }
        if (const auto options = currentBrushOptionsLayout(*surface);
            options.has_value()) {
            const AnnotationPoint point{x, y};
            if (const auto hit = brushOptionHitTest(*options, point)) {
                if (hit->control == BrushOptionControl::customColor) {
                    if (const auto chosen = platform_.chooseColor(
                            source,
                            editor_->brushOptions().style().strokeColor)) {
                        editor_->selectCustomColor(*chosen);
                    }
                    return true;
                }
                editor_->applyBrushOptionHit(*hit);
                return true;
            }
            editor_->dismissPopovers();
        }
        if (const auto options = currentMarkerOptionsLayout(*surface);
            options.has_value()) {
            const AnnotationPoint point{x, y};
            if (const auto hit = markerOptionHitTest(*options, point)) {
                if (hit->control == MarkerOptionControl::customColor) {
                    if (const auto chosen = platform_.chooseColor(
                            source,
                            editor_->markerOptions().style().strokeColor)) {
                        editor_->selectCustomColor(*chosen);
                    }
                    return true;
                }
                editor_->applyMarkerOptionHit(*hit);
                return true;
            }
            editor_->dismissPopovers();
        }
        if (const auto options = currentMosaicOptionsLayout(*surface);
            options.has_value()) {
            const AnnotationPoint point{x, y};
            if (const auto hit = mosaicOptionHitTest(*options, point)) {
                if (hit->control == MosaicOptionControl::redactionValue) {
                    editor_->beginMosaicRedactionEdit();
                    editor_->setMosaicRedactionValue(
                        mosaicValueForPoint(*options, point));
                    if (platform_.captureMouse(source)) {
                        captureWindow_ = source;
                        dragging_ = true;
                        annotationDragging_ = false;
                        mosaicValueDragging_ = true;
                    } else {
                        editor_->endMosaicRedactionEdit();
                    }
                } else {
                    editor_->applyMosaicOptionHit(*hit);
                }
                return true;
            }
            editor_->dismissPopovers();
        }
        if (const auto options = currentTextOptionsLayout(*surface);
            options.has_value()) {
            const AnnotationPoint point{x, y};
            if (const auto menu = editor_->textPopupMenu()) {
                const auto safeHeight = physicalPixelsToDip(
                    surface->physicalBounds.height, surface->dpiY);
                const auto data = textPopupDataFor(
                    *menu, *options, editor_->textOptions(), safeHeight,
                    editor_->popupScrollOffset());
                if (const auto item = popupMenuHitTest(
                        data.layout, point)) {
                    const auto index = data.firstIndex + *item;
                    if (*menu == TextPopupMenu::fontFamily) {
                        if (index < systemFontFamilies().size()) {
                            editor_->setTextFontFamily(
                                systemFontFamilies()[index]);
                        }
                    } else {
                        editor_->setTextSize(
                            static_cast<float>(index) + textMinimumSize);
                    }
                    editor_->dismissPopovers();
                    return true;
                }
            }
            if (const auto hit = textOptionHitTest(*options, point)) {
                if (hit->control == TextOptionControl::customColor) {
                    if (const auto chosen = platform_.chooseColor(
                            source,
                            editor_->textOptions().style().strokeColor)) {
                        editor_->selectCustomColor(*chosen);
                    }
                } else if (hit->control == TextOptionControl::fontFamily) {
                    editor_->toggleTextPopupMenu(
                        TextPopupMenu::fontFamily);
                } else if (hit->control == TextOptionControl::textSize) {
                    editor_->toggleTextPopupMenu(
                        TextPopupMenu::textSize);
                } else {
                    editor_->applyTextOptionHit(*hit);
                }
                return true;
            }
            editor_->dismissPopovers();
        }
        if (const auto options = currentNumberOptionsLayout(*surface);
            options.has_value()) {
            const AnnotationPoint point{x, y};
            if (const auto menu = editor_->numberPopupMenu()) {
                const auto safeHeight = physicalPixelsToDip(
                    surface->physicalBounds.height, surface->dpiY);
                const auto data = numberPopupDataFor(
                    *menu, *options, editor_->numberOptions(), safeHeight,
                    editor_->popupScrollOffset());
                if (const auto item = popupMenuHitTest(
                        data.layout, point)) {
                    const auto index = data.firstIndex + *item;
                    if (*menu == NumberPopupMenu::markType) {
                        if (index < numberMarkTypes.size()) {
                            editor_->selectNumberType(
                                numberMarkTypes[index].type);
                        }
                    } else if (index < numberSizeValues.size()) {
                        editor_->setNumberSize(numberSizeValues[index]);
                    }
                    editor_->dismissPopovers();
                    return true;
                }
            }
            if (const auto hit = numberOptionHitTest(*options, point)) {
                if (hit->control == NumberOptionControl::customColor) {
                    if (const auto chosen = platform_.chooseColor(source,
                            editor_->numberOptions().style().strokeColor)) {
                        editor_->selectCustomColor(*chosen);
                    }
                } else if (hit->control == NumberOptionControl::markType) {
                    editor_->toggleNumberPopupMenu(
                        NumberPopupMenu::markType);
                } else if (hit->control == NumberOptionControl::size) {
                    editor_->toggleNumberPopupMenu(NumberPopupMenu::size);
                } else {
                    editor_->applyNumberOptionHit(*hit);
                }
                return true;
            }
            editor_->dismissPopovers();
        }
        if (const auto options = currentMagnifierOptionsLayout(*surface);
            options.has_value()) {
            const AnnotationPoint point{x, y};
            if (editor_->magnifierZoomMenuVisible()) {
                const auto safeHeight = physicalPixelsToDip(
                    surface->physicalBounds.height, surface->dpiY);
                const auto menu = popupMenuLayout(
                    options->zoom, magnifierZoomOptions.size(), safeHeight);
                if (const auto item = popupMenuHitTest(menu, point)) {
                    if (*item < magnifierZoomOptions.size()) {
                        editor_->selectMagnifierZoom(
                            magnifierZoomOptions[*item].value);
                    }
                    editor_->dismissPopovers();
                    return true;
                }
                if (contains(menu.menu, point)) {
                    return true;
                }
            }
            if (const auto hit = magnifierOptionHitTest(*options, point)) {
                if (hit->control == MagnifierOptionControl::customColor) {
                    if (const auto chosen = platform_.chooseColor(source,
                            editor_->magnifierOptions().style().strokeColor)) {
                        editor_->selectCustomColor(*chosen);
                    }
                } else {
                    editor_->applyMagnifierOptionHit(*hit);
                }
                return true;
            }
            editor_->dismissPopovers();
        }
        if (const auto options = currentEraserOptionsLayout(*surface);
            options.has_value()) {
            const AnnotationPoint point{x, y};
            if (const auto hit = eraserOptionHitTest(*options, point)) {
                editor_->applyEraserOptionHit(*hit);
                return true;
            }
        }
    }

    if (mode_ == OverlayMode::teachingPen
        && teachingPenToolbarAnchor_.has_value()) {
        teachingPenToolbarAnchor_.reset();
        if (editor_ != nullptr) editor_->dismissPopovers();
    }
    const auto virtualPoint = toVirtual(*surface, clientPoint);
    if (editor_ != nullptr && editor_->isEyedropperToolActive()) {
        if (!eyedropperPointIsValid(virtualPoint)) {
            return true;
        }
        updateEyedropper(virtualPoint, platform_.shiftPressed());
        if (eyedropperMeasurementInProgress_
            && eyedropperMeasurementStart_.has_value()) {
            const auto start = *eyedropperMeasurementStart_;
            const auto end = eyedropperMeasurementEnd_.value_or(virtualPoint);
            if (eyedropperPixelLength(
                    {static_cast<float>(start.x), static_cast<float>(start.y)},
                    {static_cast<float>(end.x), static_cast<float>(end.y)}) == 0) {
                eyedropperMeasurementStart_.reset();
                eyedropperMeasurementEnd_.reset();
            }
            eyedropperMeasurementInProgress_ = false;
        } else {
            eyedropperMeasurementStart_ = virtualPoint;
            eyedropperMeasurementEnd_ = virtualPoint;
            eyedropperMeasurementInProgress_ = true;
        }
        return true;
    }
    if (editor_ != nullptr) {
        if (const auto local = annotationPoint(virtualPoint);
            local.has_value()
                && editor_->pointerDown(
                    *local, platform_.shiftPressed(), clickCount)) {
            if (editor_->isEditingInlineValue()) {
                return true;
            }
            if (!platform_.captureMouse(source)) {
                editor_->cancelInteraction();
                lastError_ = OverlayInputErrorCode::mouseCaptureFailed;
                cancelOnce();
                return false;
            }
            captureWindow_ = source;
            dragging_ = true;
            annotationDragging_ = true;
            return true;
        }
        if (editor_->toolbarState().selectedAction().has_value()
            && model_.selection().has_value()
            && !contains(*model_.selection(), virtualPoint)) {
            return true;
        }
    }

    if (mode_ == OverlayMode::teachingPen) {
        return true;
    }
    if (!platform_.captureMouse(source)) {
        lastError_ = OverlayInputErrorCode::mouseCaptureFailed;
        cancelOnce();
        return false;
    }

    const auto point = virtualPoint;
    const auto handleRadius = (std::max<std::int64_t>)(
        1, dipLengthToPhysicalPixels(
            VisualStyleCatalog::selectionHandleDiameterDip / 2.0F,
            (std::max)(surface->dpiX, surface->dpiY)));
    const auto hit = mode_ != OverlayMode::textRecognition
            && model_.phase() == SelectionPhase::ready
        ? model_.hitTest(point, handleRadius)
        : SelectionHandle::none;
    bool began = false;
    if (hit == SelectionHandle::body) {
        began = model_.beginMove(point);
    } else if (hit != SelectionHandle::none) {
        began = model_.beginResize(hit, point);
    } else {
        model_.beginCreation(point);
        began = true;
    }
    if (!began) {
        platform_.releaseMouse();
        return false;
    }
    captureWindow_ = source;
    dragging_ = true;
    annotationDragging_ = false;
    return true;
}

bool OverlayInputRouter::rightPointerDown(
    HWND source,
    PixelPoint clientPoint) noexcept
{
    if (status_ != OverlayInputStatus::active
        || mode_ != OverlayMode::teachingPen || dragging_) {
        return false;
    }
    const auto* surface = surfaceFor(source);
    if (surface == nullptr) return false;
    if (teachingPenToolbarAnchor_.has_value()) {
        teachingPenToolbarAnchor_.reset();
        if (editor_ != nullptr) editor_->dismissPopovers();
    } else {
        teachingPenToolbarAnchor_ = toVirtual(*surface, clientPoint);
        if (editor_ != nullptr) editor_->dismissPopovers();
    }
    return true;
}

OverlayCursorStyle OverlayInputRouter::cursorStyle(
    HWND source, PixelPoint clientPoint) const noexcept
{
    if (status_ != OverlayInputStatus::active) {
        return OverlayCursorStyle::arrow;
    }
    const auto* surface = surfaceFor(source);
    if (surface == nullptr) {
        return OverlayCursorStyle::arrow;
    }
    if (mode_ == OverlayMode::textRecognition) {
        return OverlayCursorStyle::crosshair;
    }
    if (hitToolbarAction(*surface, clientPoint).has_value()) {
        return OverlayCursorStyle::arrow;
    }

    const AnnotationPoint surfacePoint{
        static_cast<float>(clientPoint.x) * 96.0F
            / static_cast<float>(surface->dpiX),
        static_cast<float>(clientPoint.y) * 96.0F
            / static_cast<float>(surface->dpiY),
    };
    if (editorOwnerIndex_.has_value()
        && (&surfaces_[*editorOwnerIndex_] == surface
            || mode_ == OverlayMode::teachingPen)) {
        if (const auto options = currentShapeOptionsLayout(*surface);
            options.has_value() && contains(options->toolbar, surfacePoint)) {
            return OverlayCursorStyle::arrow;
        }
        if (const auto options = currentArrowLineOptionsLayout(*surface);
            options.has_value() && contains(options->toolbar, surfacePoint)) {
            return OverlayCursorStyle::arrow;
        }
        if (const auto options = currentBrushOptionsLayout(*surface);
            options.has_value() && contains(options->toolbar, surfacePoint)) {
            return OverlayCursorStyle::arrow;
        }
        if (const auto options = currentMarkerOptionsLayout(*surface);
            options.has_value() && contains(options->toolbar, surfacePoint)) {
            return OverlayCursorStyle::arrow;
        }
        if (const auto options = currentMosaicOptionsLayout(*surface);
            options.has_value() && contains(options->toolbar, surfacePoint)) {
            return OverlayCursorStyle::arrow;
        }
        if (const auto options = currentTextOptionsLayout(*surface);
            options.has_value() && contains(options->toolbar, surfacePoint)) {
            return OverlayCursorStyle::arrow;
        }
        if (const auto options = currentNumberOptionsLayout(*surface);
            options.has_value() && contains(options->toolbar, surfacePoint)) {
            return OverlayCursorStyle::arrow;
        }
        if (const auto options = currentEraserOptionsLayout(*surface);
            options.has_value() && contains(options->toolbar, surfacePoint)) {
            return OverlayCursorStyle::arrow;
        }
    }

    const auto virtualPoint = toVirtual(*surface, clientPoint);
    if (editor_ != nullptr && editor_->isEyedropperToolActive()) {
        if (!eyedropperPointIsValid(virtualPoint)) {
            return OverlayCursorStyle::arrow;
        }
        return backgroundAwareCursorStyle(
            OverlayCursorStyle::eyedropper, virtualPoint, *surface);
    }
    if (editor_ != nullptr) {
        if (const auto local = annotationPoint(virtualPoint)) {
            const auto shapeStyle = editor_->cursorStyleAt(*local);
            if (shapeStyle != ShapeCursorStyle::arrow) {
                return backgroundAwareCursorStyle(
                    cursorStyleForShape(shapeStyle), virtualPoint, *surface);
            }
        }
    }

    if (mode_ == OverlayMode::teachingPen) {
        return OverlayCursorStyle::arrow;
    }

    if (model_.phase() == SelectionPhase::moving) {
        return backgroundAwareCursorStyle(
            OverlayCursorStyle::move, virtualPoint, *surface);
    }
    if (model_.phase() == SelectionPhase::resizing) {
        return backgroundAwareCursorStyle(
            cursorStyleForSelectionHandle(model_.activeHandle()),
            virtualPoint, *surface);
    }
    if (model_.phase() == SelectionPhase::ready) {
        const auto radius = (std::max<std::int64_t>)(
            1, dipLengthToPhysicalPixels(
                VisualStyleCatalog::selectionHandleDiameterDip / 2.0F,
                (std::max)(surface->dpiX, surface->dpiY)));
        return cursorStyleForSelectionHandle(
            model_.hitTest(virtualPoint, radius));
    }
    return OverlayCursorStyle::crosshair;
}

bool OverlayInputRouter::selectionPrefersLightCursor() const noexcept
{
    if (!model_.selection().has_value() || desktop_ == nullptr) {
        return false;
    }
    const auto selection = snipory::core::portable::standardized(
        *model_.selection());
    const auto cacheMatches = cursorContrastSelection_.has_value()
        && *cursorContrastSelection_ == selection
        && cursorContrastPrefersLight_.has_value();
    if (cacheMatches) {
        return *cursorContrastPrefersLight_;
    }

    cursorContrastSelection_ = selection;
    cursorContrastPrefersLight_ = false;
    if (selection.width <= 0 || selection.height <= 0) {
        return false;
    }

    constexpr std::int64_t maximumSamplesPerAxis = 24;
    const auto columns = (std::max<std::int64_t>)(
        1, (std::min)(maximumSamplesPerAxis, selection.width));
    const auto rows = (std::max<std::int64_t>)(
        1, (std::min)(maximumSamplesPerAxis, selection.height));
    long double total = 0.0L;
    std::uint64_t count = 0U;
    for (std::int64_t row = 0; row < rows; ++row) {
        for (std::int64_t column = 0; column < columns; ++column) {
            const PixelPoint point{
                selection.x + static_cast<std::int64_t>(
                    (static_cast<long double>(column) + 0.5L)
                    * static_cast<long double>(selection.width)
                    / static_cast<long double>(columns)),
                selection.y + static_cast<std::int64_t>(
                    (static_cast<long double>(row) + 0.5L)
                    * static_cast<long double>(selection.height)
                    / static_cast<long double>(rows)),
            };
            for (const auto& display : desktop_->displays) {
                const auto bounds = snipory::core::portable::standardized(
                    display.descriptor.pixelBounds);
                if (!contains(bounds, point)) continue;
                const auto x = point.x - bounds.x;
                const auto y = point.y - bounds.y;
                if (x < 0 || y < 0 || x >= display.pixels.width()
                    || y >= display.pixels.height()) {
                    break;
                }
                const auto offset = static_cast<std::uint64_t>(y)
                    * display.pixels.stride()
                    + static_cast<std::uint64_t>(x) * 4U;
                if (offset + 2U >= display.pixels.byteCount()) break;
                const auto* pixel = display.pixels.data() + offset;
                const auto blue = std::to_integer<unsigned int>(pixel[0]);
                const auto green = std::to_integer<unsigned int>(pixel[1]);
                const auto red = std::to_integer<unsigned int>(pixel[2]);
                total += (0.2126L * red + 0.7152L * green + 0.0722L * blue)
                    / 255.0L;
                ++count;
                break;
            }
        }
    }
    if (count > 0U) {
        cursorContrastPrefersLight_ = total / count < 0.5L;
    }
    return *cursorContrastPrefersLight_;
}

bool OverlayInputRouter::shouldUseLightCursor(
    PixelPoint virtualPoint,
    const OverlaySurface& surface) const noexcept
{
    if (!model_.selection().has_value()) return false;
    auto hitRect = snipory::core::portable::standardized(*model_.selection());
    const auto margin = dipLengthToPhysicalPixels(
        16.0F, (std::max)(surface.dpiX, surface.dpiY));
    hitRect.x -= margin;
    hitRect.y -= margin;
    hitRect.width += margin * 2;
    hitRect.height += margin * 2;
    return contains(hitRect, virtualPoint) && selectionPrefersLightCursor();
}

OverlayCursorStyle OverlayInputRouter::backgroundAwareCursorStyle(
    OverlayCursorStyle style,
    PixelPoint virtualPoint,
    const OverlaySurface& surface) const noexcept
{
    if (!shouldUseLightCursor(virtualPoint, surface)) return style;
    switch (style) {
    case OverlayCursorStyle::move:
        return OverlayCursorStyle::moveLight;
    case OverlayCursorStyle::resizeLeftRight:
        return OverlayCursorStyle::resizeLeftRightLight;
    case OverlayCursorStyle::resizeUpDown:
        return OverlayCursorStyle::resizeUpDownLight;
    case OverlayCursorStyle::resizeTopLeftBottomRight:
        return OverlayCursorStyle::resizeTopLeftBottomRightLight;
    case OverlayCursorStyle::resizeTopRightBottomLeft:
        return OverlayCursorStyle::resizeTopRightBottomLeftLight;
    case OverlayCursorStyle::brush:
        return OverlayCursorStyle::brushLight;
    case OverlayCursorStyle::marker:
        return OverlayCursorStyle::markerLight;
    case OverlayCursorStyle::eyedropper:
        return OverlayCursorStyle::eyedropperLight;
    default:
        return style;
    }
}

void OverlayInputRouter::pointerMove(HWND source, PixelPoint clientPoint) noexcept
{
    if (dragging_) cancelPinnedImageShiftShortcut();
    if (!dragging_ && status_ == OverlayInputStatus::active) {
        if (const auto* surface = surfaceFor(source)) {
            const auto action = hitToolbarAction(*surface, clientPoint);
            if (action != hoveredToolbarAction_) {
                hoveredToolbarTooltipText_ = action.has_value()
                    ? toolbarTooltipText(*action)
                    : std::wstring{};
            }
            hoveredToolbarWindow_ = source;
            hoveredToolbarAction_ = action;
        } else {
            hoveredToolbarWindow_ = nullptr;
            hoveredToolbarAction_.reset();
            hoveredToolbarTooltipText_.clear();
        }
    } else {
        hoveredToolbarWindow_ = nullptr;
        hoveredToolbarAction_.reset();
        hoveredToolbarTooltipText_.clear();
    }
    if (status_ == OverlayInputStatus::active
        && editor_ != nullptr && editor_->isEyedropperToolActive()) {
        if (const auto* surface = surfaceFor(source)) {
            updateEyedropper(
                toVirtual(*surface, clientPoint), platform_.shiftPressed());
        }
    }
    if (!dragging_ || status_ != OverlayInputStatus::active) {
        return;
    }
    const auto point = platform_.cursorPosition();
    if (!point.has_value()) {
        lastError_ = OverlayInputErrorCode::cursorPositionFailed;
        cancelOnce();
        return;
    }
    platformPointerMove(*point);
}

void OverlayInputRouter::pointerLeave(HWND source) noexcept
{
    if (hoveredToolbarWindow_ != source) return;
    hoveredToolbarWindow_ = nullptr;
    hoveredToolbarAction_.reset();
    hoveredToolbarTooltipText_.clear();
}

void OverlayInputRouter::pointerUp(HWND, PixelPoint) noexcept
{
    if (!dragging_ || status_ != OverlayInputStatus::active) {
        return;
    }
    const auto point = platform_.cursorPosition();
    if (!point.has_value()) {
        lastError_ = OverlayInputErrorCode::cursorPositionFailed;
        cancelOnce();
        return;
    }
    platformPointerUp(*point);
}

void OverlayInputRouter::platformPointerMove(PixelPoint virtualPoint) noexcept
{
    if (dragging_ && status_ == OverlayInputStatus::active) {
        if (mosaicValueDragging_ && editor_ != nullptr
            && editorOwnerIndex_.has_value()) {
            const auto& surface = surfaces_[*editorOwnerIndex_];
            if (const auto options = currentMosaicOptionsLayout(surface)) {
                const AnnotationPoint point{
                    physicalPixelsToDip(
                        virtualPoint.x - surface.physicalBounds.x,
                        surface.dpiX),
                    physicalPixelsToDip(
                        virtualPoint.y - surface.physicalBounds.y,
                        surface.dpiY),
                };
                editor_->setMosaicRedactionValue(
                    mosaicValueForPoint(*options, point));
            }
        } else if (annotationDragging_ && editor_ != nullptr) {
            if (const auto local = annotationPoint(virtualPoint)) {
                editor_->pointerMove(*local, platform_.shiftPressed());
            }
        } else {
            model_.updateInteraction(virtualPoint);
        }
    }
}

void OverlayInputRouter::platformPointerUp(PixelPoint virtualPoint) noexcept
{
    if (!dragging_ || status_ != OverlayInputStatus::active) {
        return;
    }
    if (mosaicValueDragging_) {
        platformPointerMove(virtualPoint);
        if (editor_ != nullptr) {
            editor_->endMosaicRedactionEdit();
        }
    } else if (annotationDragging_ && editor_ != nullptr) {
        if (const auto local = annotationPoint(virtualPoint)) {
            editor_->pointerUp(*local, platform_.shiftPressed());
        } else {
            editor_->cancelInteraction();
        }
    } else {
        model_.updateInteraction(virtualPoint);
        model_.finishInteraction();
        ensureEditor();
    }
    dragging_ = false;
    annotationDragging_ = false;
    mosaicValueDragging_ = false;
    captureWindow_ = nullptr;
    releasingCapture_ = true;
    const auto released = platform_.releaseMouse();
    releasingCapture_ = false;
    if (!released) {
        lastError_ = OverlayInputErrorCode::mouseReleaseFailed;
        cancelOnce();
    } else if (mode_ == OverlayMode::textRecognition
               && model_.selection().has_value()) {
        completeOnce(OverlayInputAction::recognizeText);
    }
}

void OverlayInputRouter::captureChanged() noexcept
{
    if (dragging_ && !releasingCapture_) {
        if (annotationDragging_ && editor_ != nullptr) {
            editor_->cancelInteraction();
        }
        cancelOnce();
    }
}

void OverlayInputRouter::cancelMode() noexcept
{
    cancelOnce();
}

void OverlayInputRouter::escapePressed() noexcept
{
    if (editor_ != nullptr) {
        const auto result = editor_->handleKey(
            ShapeEditorKey::escapeKey, false, false);
        if (result == ShapeEditorKeyResult::consumed) {
            if (!editor_->isEyedropperToolActive()) {
                clearEyedropperState();
            }
            return;
        }
    }
    if (mode_ == OverlayMode::pinnedImageEditor
        || mode_ == OverlayMode::longImageEditor) {
        completeOnce(OverlayInputAction::finishEditing);
    } else {
        cancelOnce();
    }
}

void OverlayInputRouter::cancelPressed() noexcept
{
    cancelOnce();
}

bool OverlayInputRouter::toolbarShortcutPressed(
    std::uint32_t virtualKey,
    bool control,
    bool shift,
    bool alt) noexcept
{
    if (status_ != OverlayInputStatus::active) return false;
    for (const auto action : toolbarActions()) {
        if (!toolbarShortcutMatches(
                action, virtualKey, control, shift, alt)) {
            continue;
        }
        const auto plainToolShortcut = !toolbarTooltip(action).control
            && action != ToolbarAction::cancel
            && action != ToolbarAction::finishEditing;
        if (plainToolShortcut && isEditingInlineValue()) return true;
        performToolbarAction(action);
        return true;
    }
    return false;
}

void OverlayInputRouter::synchronizeToolbarHotKeys() noexcept
{
    const auto shouldRegister = status_ == OverlayInputStatus::active
        && escapeHotKeyWindow_ != nullptr && shapeAnnotationsEnabled_
        && !isEditingInlineValue();
    if (shouldRegister == toolbarHotKeysRegistered_) return;
    if (shouldRegister) {
        toolbarHotKeysRegistered_
            = platform_.registerToolbarHotKeys(escapeHotKeyWindow_);
    } else {
        platform_.unregisterToolbarHotKeys(escapeHotKeyWindow_);
        toolbarHotKeysRegistered_ = false;
    }
}

bool OverlayInputRouter::keyPressed(
    ShapeEditorKey key,
    bool control,
    bool shift) noexcept
{
    if (status_ != OverlayInputStatus::active || editor_ == nullptr) {
        return false;
    }
    if (editor_->isEyedropperToolActive()
        && key == ShapeEditorKey::copy && !control
        && eyedropperSampleColor_.has_value()) {
        const auto copied = platform_.copyText(eyedropperColorText(
            *eyedropperSampleColor_, eyedropperCopyMode_));
        if (copied) {
            eyedropperCopySuccessUntil_ = std::chrono::steady_clock::now()
                + std::chrono::milliseconds(1200);
        }
        return copied;
    }
    const auto result = editor_->handleKey(key, control, shift);
    if (key == ShapeEditorKey::eyedropper
        && result == ShapeEditorKeyResult::consumed) {
        if (editor_->isEyedropperToolActive()) {
            clearEyedropperState();
            refreshEyedropperComposite();
        } else {
            clearEyedropperState();
        }
    }
    switch (result) {
    case ShapeEditorKeyResult::ignored:
        return false;
    case ShapeEditorKeyResult::consumed:
        return true;
    case ShapeEditorKeyResult::requestCancel:
        cancelOnce();
        return true;
    case ShapeEditorKeyResult::requestSave:
        completeOnce(OverlayInputAction::save);
        return true;
    case ShapeEditorKeyResult::requestCopy:
        completeOnce(OverlayInputAction::copy);
        return true;
    case ShapeEditorKeyResult::requestPin:
        completeOnce(OverlayInputAction::pin);
        return true;
    }
    return false;
}

bool OverlayInputRouter::textInput(std::wstring text)
{
    return status_ == OverlayInputStatus::active
        && editor_ != nullptr
        && editor_->isEditingInlineValue()
        && editor_->insertText(std::move(text));
}

bool OverlayInputRouter::mouseWheel(int delta) noexcept
{
    cancelPinnedImageShiftShortcut();
    if (status_ != OverlayInputStatus::active || editor_ == nullptr
        || (!editor_->textPopupMenu().has_value()
            && !editor_->numberPopupMenu().has_value())
        || delta == 0) {
        return false;
    }
    return editor_->scrollPopupMenu(delta > 0 ? -3 : 3);
}

bool OverlayInputRouter::longImageScrollAllowed() const noexcept
{
    return mode_ == OverlayMode::longImageEditor
        && status_ == OverlayInputStatus::active
        && !dragging_
        && !isEditingInlineValue();
}

bool OverlayInputRouter::isEditingInlineValue() const noexcept
{
    return editor_ != nullptr && editor_->isEditingInlineValue();
}

bool OverlayInputRouter::eyedropperShiftPressed() noexcept
{
    if (status_ != OverlayInputStatus::active || editor_ == nullptr
        || !editor_->isEyedropperToolActive()) {
        return false;
    }
    eyedropperCopyMode_ = eyedropperCopyMode_ == EyedropperCopyMode::hex
        ? EyedropperCopyMode::rgb : EyedropperCopyMode::hex;
    return true;
}

bool OverlayInputRouter::pinnedImageShiftChanged(
    bool pressed, bool control, bool alt) noexcept
{
    if (mode_ != OverlayMode::pinnedImageEditor
        || status_ != OverlayInputStatus::active) {
        pinnedImageShiftShortcutCandidate_ = false;
        return false;
    }
    const auto colorSamplerOwnsShift = eyedropperSampleColor_.has_value()
        || eyedropperSamplePoint_.has_value();
    if (pressed && !control && !alt && !dragging_
        && !colorSamplerOwnsShift) {
        pinnedImageShiftShortcutCandidate_ = true;
        return true;
    }
    if (!pressed && !control && !alt
        && pinnedImageShiftShortcutCandidate_) {
        pinnedImageShiftShortcutCandidate_ = false;
        emitTerminal(OverlayInputAction::hideEditingToolbar);
        return true;
    }
    pinnedImageShiftShortcutCandidate_ = false;
    return false;
}

void OverlayInputRouter::cancelPinnedImageShiftShortcut() noexcept
{
    pinnedImageShiftShortcutCandidate_ = false;
}

bool OverlayInputRouter::togglePinnedImageAlwaysOnTop() noexcept
{
    if (mode_ != OverlayMode::pinnedImageEditor
        || status_ != OverlayInputStatus::active) {
        return false;
    }
    cancelPinnedImageShiftShortcut();
    emitTerminal(OverlayInputAction::togglePinnedImageAlwaysOnTop);
    return true;
}

void OverlayInputRouter::shutdownForRestart() noexcept
{
    if (status_ != OverlayInputStatus::active) {
        return;
    }
    status_ = OverlayInputStatus::cancelled;
    releaseInteraction();
    deactivateEscapeHotKey();
}

void OverlayInputRouter::releaseInteraction() noexcept
{
    if (!dragging_) {
        return;
    }
    dragging_ = false;
    if (annotationDragging_ && editor_ != nullptr) {
        editor_->cancelInteraction();
    }
    if (mosaicValueDragging_ && editor_ != nullptr) {
        editor_->endMosaicRedactionEdit();
    }
    annotationDragging_ = false;
    mosaicValueDragging_ = false;
    captureWindow_ = nullptr;
    releasingCapture_ = true;
    if (!platform_.releaseMouse()) {
        lastError_ = OverlayInputErrorCode::mouseReleaseFailed;
    }
    releasingCapture_ = false;
}

void OverlayInputRouter::emitTerminal(OverlayInputAction action) noexcept
{
    ActionCallback callback;
    try {
        callback = actionCallback_;
    } catch (...) {
        return;
    }
    if (callback) {
        try {
            callback(action);
        } catch (...) {
        }
    }
}

void OverlayInputRouter::cancelOnce() noexcept
{
    if (status_ != OverlayInputStatus::active) {
        return;
    }
    status_ = OverlayInputStatus::cancelled;
    releaseInteraction();
    deactivateEscapeHotKey();
    emitTerminal(OverlayInputAction::cancel);
}

void OverlayInputRouter::completeOnce(OverlayInputAction action) noexcept
{
    if (status_ != OverlayInputStatus::active) {
        return;
    }
    status_ = OverlayInputStatus::completed;
    releaseInteraction();
    deactivateEscapeHotKey();
    emitTerminal(action);
}

OverlayInputStatus OverlayInputRouter::status() const noexcept
{
    return status_;
}

std::optional<OverlayInputErrorCode> OverlayInputRouter::lastError() const noexcept
{
    return lastError_;
}

SelectionPhase OverlayInputRouter::phase() const noexcept
{
    return model_.phase();
}

std::optional<PixelRect> OverlayInputRouter::selection() const noexcept
{
    return model_.selection();
}

const AnnotationDocument& OverlayInputRouter::annotationDocument() const noexcept
{
    static const AnnotationDocument empty;
    return editor_ != nullptr ? editor_->document() : empty;
}

std::pair<UINT, UINT> OverlayInputRouter::annotationDpi() const noexcept
{
    if (!editorOwnerIndex_.has_value()
        || *editorOwnerIndex_ >= surfaces_.size()) {
        return {96U, 96U};
    }
    const auto& surface = surfaces_[*editorOwnerIndex_];
    return {surface.dpiX, surface.dpiY};
}

std::optional<AnnotationStyle>
OverlayInputRouter::markerCursorStyle(bool light) const noexcept
{
    if (editor_ == nullptr || !editor_->isMarkerToolActive()) {
        return std::nullopt;
    }
    auto style = editor_->markerOptions().style();
    style.strokeWidthDip *= annotationViewportScale_;
    if (light) style.strokeColor = {255, 255, 255, 255};
    return style;
}

std::optional<AnnotationStyle>
OverlayInputRouter::mosaicCursorStyle() const noexcept
{
    if (editor_ == nullptr || !editor_->isMosaicToolActive()) {
        return std::nullopt;
    }
    auto style = editor_->mosaicOptions().style();
    style.strokeWidthDip *= annotationViewportScale_;
    return style;
}

std::optional<NumberCursorState>
OverlayInputRouter::numberCursorState() const noexcept
{
    if (editor_ == nullptr || !editor_->isNumberToolActive()) {
        return std::nullopt;
    }
    return NumberCursorState{
        editor_->numberOptions().type(),
        editor_->nextNumberSequenceValue(),
        editor_->numberOptions().style().strokeColor,
    };
}

struct OverlayHost::Impl final : std::enable_shared_from_this<OverlayHost::Impl> {
    HINSTANCE instance = nullptr;
    const FrozenDesktop* desktop = nullptr;
    RestartCallback restartCallback;
    ActionCallback actionCallback;
    ScrollCallback scrollCallback;
    std::optional<AnnotationRect> longImageCanvasBounds;
    float longImageDisplayScale = 1.0F;
    std::unique_ptr<OverlayInputPlatform> platform;
    std::vector<std::unique_ptr<OverlayWindow>> windows;
    std::unique_ptr<OverlayInputRouter> router;
    bool restartRequested = false;
    bool inputSuspended = false;

    void closeWindows() noexcept
    {
        for (const auto& window : windows) {
            const auto handle = window->handle();
            if (handle != nullptr) {
                ShowWindow(handle, SW_HIDE);
                DestroyWindow(handle);
            }
        }
    }

    void dispatchAction(OverlayInputAction action)
    {
        if (action != OverlayInputAction::togglePinnedImageAlwaysOnTop) {
            closeWindows();
        }
        ActionCallback callback = actionCallback;
        if (callback) {
            callback(action);
        }
    }

    void requestRestart()
    {
        if (restartRequested) {
            return;
        }
        restartRequested = true;
        if (router) {
            router->shutdownForRestart();
        }
        closeWindows();
        RestartCallback callback = restartCallback;
        if (callback) {
            callback();
        }
    }

    void handleInput(HWND source, const OverlayWindowInput& input) noexcept
    {
        if (restartRequested || inputSuspended || !router) {
            return;
        }
        switch (input.kind) {
        case OverlayWindowInputKind::pointerDown:
            router->pointerDown(source, input.clientPoint, input.clickCount);
            break;
        case OverlayWindowInputKind::rightPointerDown:
            router->rightPointerDown(source, input.clientPoint);
            break;
        case OverlayWindowInputKind::pointerMove:
            router->pointerMove(source, input.clientPoint);
            break;
        case OverlayWindowInputKind::pointerUp:
            router->pointerUp(source, input.clientPoint);
            break;
        case OverlayWindowInputKind::captureChanged:
            router->captureChanged();
            break;
        case OverlayWindowInputKind::cancelMode:
            router->cancelMode();
            break;
        case OverlayWindowInputKind::escape:
            router->escapePressed();
            break;
        case OverlayWindowInputKind::textInput:
            router->textInput(input.text);
            break;
        case OverlayWindowInputKind::mouseWheel:
            if (!router->mouseWheel(input.wheelDelta)
                && router->longImageScrollAllowed()
                && scrollCallback) {
                scrollCallback(input.wheelDelta);
            }
            break;
        case OverlayWindowInputKind::pointerLeave:
            router->pointerLeave(source);
            break;
        case OverlayWindowInputKind::cancelShiftShortcut:
            router->cancelPinnedImageShiftShortcut();
            break;
        case OverlayWindowInputKind::keyDown: {
            if (input.virtualKey == VK_SHIFT) {
                if (router->pinnedImageShiftChanged(
                        true, input.control, input.alt)) {
                    break;
                }
                router->eyedropperShiftPressed();
                break;
            }
            router->cancelPinnedImageShiftShortcut();
            if (input.virtualKey == 'T' && input.control && !input.shift
                && !input.alt
                && router->togglePinnedImageAlwaysOnTop()) {
                break;
            }
            if (router->toolbarShortcutPressed(
                    static_cast<std::uint32_t>(input.virtualKey),
                    input.control, input.shift, input.alt)) {
                break;
            }
            ShapeEditorKey key;
            switch (input.virtualKey) {
            case VK_DELETE:
                key = ShapeEditorKey::deleteKey;
                break;
            case VK_BACK:
                key = ShapeEditorKey::backspace;
                break;
            case VK_RETURN:
                key = ShapeEditorKey::enter;
                break;
            case VK_LEFT:
                key = ShapeEditorKey::left;
                break;
            case VK_RIGHT:
                key = ShapeEditorKey::right;
                break;
            case VK_HOME:
                key = ShapeEditorKey::home;
                break;
            case VK_END:
                key = ShapeEditorKey::end;
                break;
            case 'C':
                key = ShapeEditorKey::copy;
                break;
            default:
                return;
            }
            router->keyPressed(key, input.control, input.shift);
            break;
        }
        case OverlayWindowInputKind::keyUp:
            if (input.virtualKey == VK_SHIFT) {
                router->pinnedImageShiftChanged(
                    false, input.control, input.alt);
            } else {
                router->cancelPinnedImageShiftShortcut();
            }
            break;
        }
        router->synchronizeToolbarHotKeys();
        if (router
            && (input.kind == OverlayWindowInputKind::pointerDown
                || input.kind == OverlayWindowInputKind::pointerMove
                || input.kind == OverlayWindowInputKind::pointerUp)) {
            const auto style = router->cursorStyle(source, input.clientPoint);
            const auto found = std::find_if(
                windows.begin(), windows.end(),
                [source](const auto& window) {
                    return window != nullptr && window->handle() == source;
                });
            if (found != windows.end()) {
                if (style == OverlayCursorStyle::marker
                    || style == OverlayCursorStyle::markerLight
                    || style == OverlayCursorStyle::mosaic) {
                    const auto markerStyle = style == OverlayCursorStyle::marker
                        || style == OverlayCursorStyle::markerLight;
                    const auto dotStyle = markerStyle
                        ? router->markerCursorStyle(
                            style == OverlayCursorStyle::markerLight)
                        : router->mosaicCursorStyle();
                    if (const auto marker = dotStyle) {
                        if (style == OverlayCursorStyle::mosaic) {
                            (*found)->setMosaicCursor(marker->strokeWidthDip);
                        } else {
                            (*found)->setMarkerCursor(
                                marker->strokeColor, marker->strokeWidthDip);
                        }
                    }
                } else if (style == OverlayCursorStyle::numberMark
                    || style == OverlayCursorStyle::numberCheck
                    || style == OverlayCursorStyle::numberCross) {
                    if (const auto number = router->numberCursorState()) {
                        (*found)->setNumberCursor(
                            number->type, number->value, number->color);
                    }
                }
                (*found)->setCursorStyle(style);
            }
        }
        if (!refresh()) {
            router->cancelMode();
        }
    }

    bool refresh() noexcept
    {
        if (!router) {
            return false;
        }
        try {
            const auto current = router->presentations();
            const auto count = (std::min)(windows.size(), current.size());
            for (std::size_t index = 0; index < count; ++index) {
                OverlayRenderState state;
                state.selection = current[index].selection;
                state.showActions = current[index].showActions;
                state.pinnedImageEditor = current[index].pinnedImageEditor;
                state.textRecognition = current[index].textRecognition;
                state.teachingPen = current[index].teachingPen;
                state.teachingPenToolbar
                    = current[index].teachingPenToolbar;
                state.annotationPlan = current[index].annotationPlan;
                state.annotationComposite
                    = current[index].annotationComposite;
                state.annotationPlanOutsideSelectionOnly
                    = current[index].annotationPlanOutsideSelectionOnly;
                state.toolbarActions.clear();
                state.toolbarActions.reserve(current[index].toolbarItems.size());
                for (const auto& item : current[index].toolbarItems) {
                    state.toolbarActions.push_back(item.action);
                    if (item.selected) {
                        state.selectedToolbarAction = item.action;
                    }
                    if (item.action == ToolbarAction::undo) {
                        state.canUndo = item.enabled;
                    } else if (item.action == ToolbarAction::redo) {
                        state.canRedo = item.enabled;
                    }
                }
                if (current[index].toolbarTooltip.has_value()) {
                    const auto& tooltip = *current[index].toolbarTooltip;
                    const auto dpiX = desktop != nullptr
                            && index < desktop->displays.size()
                        ? desktop->displays[index].descriptor.dpiX
                        : 96U;
                    const auto dpiY = desktop != nullptr
                            && index < desktop->displays.size()
                        ? desktop->displays[index].descriptor.dpiY
                        : 96U;
                    state.toolbarTooltip = OverlayToolbarTooltipRenderState{
                        {
                            physicalPixelsToDip(tooltip.anchor.x, dpiX),
                            physicalPixelsToDip(tooltip.anchor.y, dpiY),
                            physicalPixelsToDip(tooltip.anchor.width, dpiX),
                            physicalPixelsToDip(tooltip.anchor.height, dpiY),
                        },
                        tooltip.text,
                    };
                }
                if (current[index].shapeOptions.has_value()) {
                    const auto& options = *current[index].shapeOptions;
                    state.shapeOptions = OverlayShapeOptionsRenderState{
                        options.layout,
                        options.state,
                        options.strokePatternMenu,
                        options.cornerRadiusPanel,
                    };
                }
                if (current[index].arrowLineOptions.has_value()) {
                    const auto& options = *current[index].arrowLineOptions;
                    state.arrowLineOptions = OverlayArrowLineOptionsRenderState{
                        options.layout,
                        options.state,
                        options.strokePatternMenu,
                        options.arrowTypeMenu,
                        options.arrowTypeMenuEndpoint,
                    };
                }
                if (current[index].brushOptions.has_value()) {
                    const auto& options = *current[index].brushOptions;
                    state.brushOptions = OverlayBrushOptionsRenderState{
                        options.layout,
                        options.state,
                        options.strokePatternMenu,
                    };
                }
                if (current[index].markerOptions.has_value()) {
                    const auto& options = *current[index].markerOptions;
                    state.markerOptions = OverlayMarkerOptionsRenderState{
                        options.layout,
                        options.state,
                    };
                }
                if (current[index].mosaicOptions.has_value()) {
                    const auto& options = *current[index].mosaicOptions;
                    state.mosaicOptions = OverlayMosaicOptionsRenderState{
                        options.layout,
                        options.state,
                    };
                }
                if (current[index].textOptions.has_value()) {
                    const auto& options = *current[index].textOptions;
                    state.textOptions = OverlayTextOptionsRenderState{
                        options.layout,
                        options.state,
                        options.popupMenu,
                        options.popupLabels,
                        options.selectedPopupIndex,
                    };
                }
                if (current[index].numberOptions.has_value()) {
                    const auto& options = *current[index].numberOptions;
                    state.numberOptions = OverlayNumberOptionsRenderState{
                        options.layout,
                        options.state,
                        options.popupMenu,
                        options.popupKind,
                        options.popupLabels,
                        options.selectedPopupIndex,
                    };
                }
                if (current[index].magnifierOptions.has_value()) {
                    const auto& options = *current[index].magnifierOptions;
                    state.magnifierOptions =
                        OverlayMagnifierOptionsRenderState{
                            options.layout,
                            options.state,
                            options.zoomMenu,
                        };
                }
                if (current[index].eraserOptions.has_value()) {
                    const auto& options = *current[index].eraserOptions;
                    state.eraserOptions = OverlayEraserOptionsRenderState{
                        options.layout,
                        options.mode,
                    };
                }
                if (current[index].eyedropper.has_value()) {
                    const auto& eyedropper = *current[index].eyedropper;
                    state.eyedropper = OverlayEyedropperRenderState{
                        eyedropper.pointer,
                        eyedropper.color,
                        eyedropper.magnifier,
                        eyedropper.copyMode,
                        eyedropper.copySuccessMillisecondsRemaining,
                        eyedropper.measurementStart,
                        eyedropper.measurementEnd,
                        eyedropper.measurementLabel,
                    };
                }
                windows[index]->setRenderState(std::move(state));
            }
            return true;
        } catch (...) {
            return false;
        }
    }
};

OverlayHost::OverlayHost(std::shared_ptr<Impl> impl) noexcept
    : impl_(std::move(impl))
{
}

OverlayHost::~OverlayHost() = default;

OverlayHostCreateResult OverlayHost::create(
    HINSTANCE instance,
    const FrozenDesktop& desktop,
    RestartCallback restartCallback,
    ActionCallback actionCallback)
{
    return createWithMode(instance, desktop, std::move(restartCallback),
        std::move(actionCallback), true, OverlayMode::capture);
}

OverlayHostCreateResult OverlayHost::createTextRecognition(
    HINSTANCE instance,
    const FrozenDesktop& desktop,
    RestartCallback restartCallback,
    ActionCallback actionCallback)
{
    return createWithMode(instance, desktop, std::move(restartCallback),
        std::move(actionCallback), false, OverlayMode::textRecognition);
}

OverlayHostCreateResult OverlayHost::createTeachingPen(
    HINSTANCE instance,
    const FrozenDesktop& desktop,
    RestartCallback restartCallback,
    ActionCallback actionCallback)
{
    return createWithMode(instance, desktop, std::move(restartCallback),
        std::move(actionCallback), true, OverlayMode::teachingPen);
}

OverlayHostCreateResult OverlayHost::createWithMode(
    HINSTANCE instance,
    const FrozenDesktop& desktop,
    RestartCallback restartCallback,
    ActionCallback actionCallback,
    bool shapeAnnotationsEnabled,
    OverlayMode mode)
{
    if (desktop.displays.empty()) {
        return {nullptr, OverlayHostError{OverlayHostErrorCode::noDisplays}};
    }
    try {
        auto impl = std::make_shared<Impl>();
        impl->instance = instance;
        impl->desktop = &desktop;
        impl->restartCallback = std::move(restartCallback);
        impl->actionCallback = std::move(actionCallback);
        impl->platform = std::make_unique<SystemOverlayInputPlatform>();

        const std::weak_ptr<Impl> weak = impl;
        for (const auto& display : desktop.displays) {
            auto created = OverlayWindow::create(
                instance,
                display,
                [weak] {
                    if (const auto locked = weak.lock()) {
                        locked->requestRestart();
                    }
                },
                [weak](HWND source, const OverlayWindowInput& input) {
                    if (const auto locked = weak.lock()) {
                        locked->handleInput(source, input);
                    }
                });
            if (!created.value) {
                return {
                    nullptr,
                    OverlayHostError{
                        OverlayHostErrorCode::windowCreationFailed,
                        created.error.has_value()
                            ? created.error->systemError
                            : ERROR_GEN_FAILURE,
                        created.error,
                    },
                };
            }
            impl->windows.push_back(std::move(created.value));
        }

        std::vector<OverlaySurface> surfaces;
        surfaces.reserve(impl->windows.size());
        for (std::size_t index = 0; index < impl->windows.size(); ++index) {
            const auto& descriptor = desktop.displays[index].descriptor;
            surfaces.push_back({
                impl->windows[index]->handle(),
                descriptor.pixelBounds,
                descriptor.dpiX,
                descriptor.dpiY,
            });
        }
        impl->router = std::make_unique<OverlayInputRouter>(
            desktop.topology.virtualBounds(),
            std::move(surfaces),
            *impl->platform,
            [weak](OverlayInputAction action) {
                if (const auto locked = weak.lock()) {
                    locked->dispatchAction(action);
                }
            },
            shapeAnnotationsEnabled,
            &desktop,
            mode);
        if (!impl->router->activateEscapeHotKey(impl->windows.front()->handle())) {
            return {
                nullptr,
                OverlayHostError{
                    OverlayHostErrorCode::escapeHotKeyRegistrationFailed,
                    GetLastError(),
                    std::nullopt,
                },
            };
        }
        if (!impl->refresh()) {
            return {
                nullptr,
                OverlayHostError{
                    OverlayHostErrorCode::outOfMemory,
                    ERROR_NOT_ENOUGH_MEMORY,
                    std::nullopt,
                },
            };
        }
        return {
            std::unique_ptr<OverlayHost>(new OverlayHost(std::move(impl))),
            std::nullopt,
        };
    } catch (const std::bad_alloc&) {
        return {
            nullptr,
            OverlayHostError{
                OverlayHostErrorCode::outOfMemory,
                ERROR_NOT_ENOUGH_MEMORY,
                std::nullopt,
            },
        };
    }
}

OverlayHostCreateResult OverlayHost::createPinnedImageEditor(
    HINSTANCE instance,
    const FrozenDesktop& desktop,
    ActionCallback actionCallback,
    bool alwaysOnTop)
{
    if (desktop.displays.size() != 1U) {
        return {nullptr, OverlayHostError{OverlayHostErrorCode::noDisplays}};
    }
    try {
        auto impl = std::make_shared<Impl>();
        impl->instance = instance;
        impl->desktop = &desktop;
        impl->actionCallback = std::move(actionCallback);
        impl->platform = std::make_unique<SystemOverlayInputPlatform>();
        const std::weak_ptr<Impl> weak = impl;
        auto created = OverlayWindow::create(
            instance, desktop.displays.front(), [] {},
            [weak](HWND source, const OverlayWindowInput& input) {
                if (const auto locked = weak.lock()) {
                    locked->handleInput(source, input);
                }
            });
        if (!created.value) {
            return {nullptr, OverlayHostError{
                OverlayHostErrorCode::windowCreationFailed,
                created.error.has_value() ? created.error->systemError
                                          : ERROR_GEN_FAILURE,
                created.error}};
        }
        impl->windows.push_back(std::move(created.value));
        impl->windows.front()->setAlwaysOnTop(alwaysOnTop);
        impl->windows.front()->setKeyboardInputAlwaysEnabled(true);
        const auto& descriptor = desktop.displays.front().descriptor;
        std::vector<OverlaySurface> surfaces{{
            impl->windows.front()->handle(),
            descriptor.pixelBounds,
            descriptor.dpiX,
            descriptor.dpiY,
        }};
        impl->router = std::make_unique<OverlayInputRouter>(
            descriptor.pixelBounds, std::move(surfaces), *impl->platform,
            [weak](OverlayInputAction action) {
                if (const auto locked = weak.lock()) {
                    locked->dispatchAction(action);
                }
            },
            true, &desktop, OverlayMode::pinnedImageEditor);
        impl->router->lockSelection(descriptor.pixelBounds);
        if (!impl->router->activateEscapeHotKey(
                impl->windows.front()->handle())
            || !impl->refresh()) {
            return {nullptr, OverlayHostError{
                OverlayHostErrorCode::escapeHotKeyRegistrationFailed,
                GetLastError(), std::nullopt}};
        }
        return {std::unique_ptr<OverlayHost>(
            new OverlayHost(std::move(impl))), std::nullopt};
    } catch (const std::bad_alloc&) {
        return {nullptr, OverlayHostError{
            OverlayHostErrorCode::outOfMemory,
            ERROR_NOT_ENOUGH_MEMORY, std::nullopt}};
    }
}

OverlayHostCreateResult OverlayHost::createLongImageEditor(
    HINSTANCE instance,
    const FrozenDesktop& desktop,
    AnnotationRect canvasBounds,
    ScrollCallback scrollCallback,
    ActionCallback actionCallback)
{
    if (desktop.displays.size() != 1U) {
        return {nullptr, OverlayHostError{OverlayHostErrorCode::noDisplays}};
    }
    try {
        auto impl = std::make_shared<Impl>();
        impl->instance = instance;
        impl->desktop = &desktop;
        impl->longImageCanvasBounds = standardized(canvasBounds);
        const auto sourceWidth = dipLengthToPhysicalPixels(
            canvasBounds.width, desktop.displays.front().descriptor.dpiX);
        impl->longImageDisplayScale = sourceWidth > 0
            ? static_cast<float>(
                desktop.displays.front().descriptor.pixelBounds.width)
                / static_cast<float>(sourceWidth)
            : 1.0F;
        impl->scrollCallback = std::move(scrollCallback);
        impl->actionCallback = std::move(actionCallback);
        impl->platform = std::make_unique<SystemOverlayInputPlatform>();
        const std::weak_ptr<Impl> weak = impl;
        auto created = OverlayWindow::create(
            instance, desktop.displays.front(), [] {},
            [weak](HWND source, const OverlayWindowInput& input) {
                if (const auto locked = weak.lock()) {
                    locked->handleInput(source, input);
                }
            });
        if (!created.value) {
            return {nullptr, OverlayHostError{
                OverlayHostErrorCode::windowCreationFailed,
                created.error.has_value() ? created.error->systemError
                                          : ERROR_GEN_FAILURE,
                created.error}};
        }
        impl->windows.push_back(std::move(created.value));
        impl->windows.front()->setKeyboardInputAlwaysEnabled(true);
        const auto& descriptor = desktop.displays.front().descriptor;
        std::vector<OverlaySurface> surfaces{{
            impl->windows.front()->handle(), descriptor.pixelBounds,
            descriptor.dpiX, descriptor.dpiY,
        }};
        impl->router = std::make_unique<OverlayInputRouter>(
            descriptor.pixelBounds, std::move(surfaces), *impl->platform,
            [weak](OverlayInputAction action) {
                if (const auto locked = weak.lock()) {
                    locked->dispatchAction(action);
                }
            },
            true, &desktop, OverlayMode::longImageEditor);
        impl->router->lockSelection(descriptor.pixelBounds);
        impl->router->setAnnotationViewport(
            {}, impl->longImageDisplayScale, canvasBounds, &desktop);
        if (!impl->router->activateEscapeHotKey(
                impl->windows.front()->handle())
            || !impl->refresh()) {
            return {nullptr, OverlayHostError{
                OverlayHostErrorCode::escapeHotKeyRegistrationFailed,
                GetLastError(), std::nullopt}};
        }
        return {std::unique_ptr<OverlayHost>(
            new OverlayHost(std::move(impl))), std::nullopt};
    } catch (const std::bad_alloc&) {
        return {nullptr, OverlayHostError{
            OverlayHostErrorCode::outOfMemory,
            ERROR_NOT_ENOUGH_MEMORY, std::nullopt}};
    }
}

void OverlayHost::show() noexcept
{
    const auto impl = impl_;
    if (!impl || impl->restartRequested || !impl->router
        || impl->router->status() != OverlayInputStatus::active) {
        return;
    }
    for (const auto& window : impl->windows) {
        if (impl->restartRequested
            || impl->router->status() != OverlayInputStatus::active) {
            break;
        }
        window->show();
    }
}

void OverlayHost::setAlwaysOnTop(bool enabled) noexcept
{
    const auto impl = impl_;
    if (!impl) return;
    for (const auto& window : impl->windows) {
        window->setAlwaysOnTop(enabled);
    }
}

bool OverlayHost::updateLongImageViewport(
    const FrozenDesktop& desktop,
    AnnotationPoint origin) noexcept
{
    const auto impl = impl_;
    if (!impl || !impl->router || impl->windows.size() != 1U
        || desktop.displays.size() != 1U) {
        return false;
    }
    impl->desktop = &desktop;
    impl->windows.front()->setDisplay(desktop.displays.front());
    if (!impl->longImageCanvasBounds.has_value()) {
        return false;
    }
    impl->router->setAnnotationViewport(
        origin,
        impl->longImageDisplayScale,
        *impl->longImageCanvasBounds,
        &desktop);
    return impl->refresh();
}

bool OverlayHost::suspendForScrollCapture() noexcept
{
    const auto impl = impl_;
    if (!impl || !impl->router
        || impl->router->status() != OverlayInputStatus::active) {
        return false;
    }
    impl->router->deactivateEscapeHotKey();
    for (const auto& window : impl->windows) {
        window->hide();
    }
    return true;
}

bool OverlayHost::resumeAfterScrollCapture() noexcept
{
    const auto impl = impl_;
    if (!impl || !impl->router || impl->windows.empty()
        || impl->router->status() != OverlayInputStatus::active
        || !impl->router->activateEscapeHotKey(
            impl->windows.front()->handle())
        || !impl->refresh()) {
        return false;
    }
    show();
    return true;
}

bool OverlayHost::suspendInputForRecognition() noexcept
{
    const auto impl = impl_;
    if (!impl || !impl->router
        || impl->router->status() != OverlayInputStatus::active) {
        return false;
    }
    impl->router->deactivateEscapeHotKey();
    impl->inputSuspended = true;
    return true;
}

bool OverlayHost::resumeInputAfterRecognition() noexcept
{
    const auto impl = impl_;
    if (!impl || !impl->router || impl->windows.empty()
        || impl->router->status() != OverlayInputStatus::active) {
        return false;
    }
    impl->inputSuspended = false;
    if (!impl->router->activateEscapeHotKey(
            impl->windows.front()->handle())
        || !impl->refresh()) {
        return false;
    }
    show();
    return true;
}

std::optional<PixelRect> OverlayHost::selection() const noexcept
{
    return impl_ && impl_->router
        ? impl_->router->selection()
        : std::nullopt;
}

OverlayAnnotationSnapshot OverlayHost::annotationSnapshot() const
{
    OverlayAnnotationSnapshot snapshot;
    if (!impl_ || !impl_->router) {
        return snapshot;
    }
    snapshot.plan = impl_->router->annotationDocument().annotations().empty()
        ? AnnotationRenderPlan{}
        : buildAnnotationRenderPlan(
              impl_->router->annotationDocument(),
              std::nullopt,
              {0.0F, 0.0F},
              false);
    snapshot.eraserMasks
        = impl_->router->annotationDocument().eraserMasks();
    const auto dpi = impl_->router->annotationDpi();
    snapshot.dpiX = dpi.first;
    snapshot.dpiY = dpi.second;
    return snapshot;
}

SelectionPhase OverlayHost::phase() const noexcept
{
    return impl_ && impl_->router
        ? impl_->router->phase()
        : SelectionPhase::empty;
}

std::optional<OverlayInputErrorCode> OverlayHost::lastInputError() const noexcept
{
    return impl_ && impl_->router
        ? impl_->router->lastError()
        : std::nullopt;
}

} // namespace xxsnap::win
