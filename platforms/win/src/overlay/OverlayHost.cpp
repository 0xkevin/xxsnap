#include "overlay/OverlayHost.h"

#include "overlay/OverlayRenderer.h"

#include <commdlg.h>

#include <algorithm>
#include <cmath>
#include <limits>
#include <new>
#include <utility>

namespace xxsnap::win {
namespace {

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

StrokePatternMenuLayout strokePatternMenuFor(
    AnnotationRect field,
    float safeHeight) noexcept
{
    constexpr float menuHeight = 6.0F * 24.0F + 8.0F;
    auto menuRect = AnnotationRect{
        field.x,
        field.y + field.height + 8.0F,
        field.width,
        menuHeight,
    };
    if (menuRect.y + menuRect.height > safeHeight - 8.0F) {
        menuRect.y = field.y - 8.0F - menuHeight;
    }
    return strokePatternMenuLayout(menuRect);
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
        return true;
    }

    bool unregisterEditorHotKeys(HWND window) noexcept override
    {
        for (const auto identifier : {
                 overlayUndoHotKeyIdentifier,
                 overlayRedoHotKeyIdentifier,
                 overlaySaveHotKeyIdentifier,
                 overlayCopyHotKeyIdentifier,
                 overlayDeleteHotKeyIdentifier}) {
            UnregisterHotKey(window, identifier);
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
};

} // namespace

OverlayInputRouter::OverlayInputRouter(
    PixelRect virtualBounds,
    std::vector<OverlaySurface> surfaces,
    OverlayInputPlatform& platform,
    ActionCallback actionCallback,
    bool shapeAnnotationsEnabled)
    : model_(snipory::core::portable::standardized(virtualBounds))
    , surfaces_(std::move(surfaces))
    , platform_(platform)
    , actionCallback_(std::move(actionCallback))
    , shapeAnnotationsEnabled_(shapeAnnotationsEnabled)
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
}

std::vector<ToolbarAction> OverlayInputRouter::toolbarActions() const
{
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
    return editor_ == nullptr || editor_->toolbarState().isEnabled(action);
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
    const AnnotationRect bounds{
        physicalPixelsToDip(
            surface.physicalBounds.x - selection.x, surface.dpiX),
        physicalPixelsToDip(
            surface.physicalBounds.y - selection.y, surface.dpiY),
        physicalPixelsToDip(surface.physicalBounds.width, surface.dpiX),
        physicalPixelsToDip(surface.physicalBounds.height, surface.dpiY),
    };
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
        physicalPixelsToDip(virtualPoint.x - selection.x, owner.dpiX),
        physicalPixelsToDip(virtualPoint.y - selection.y, owner.dpiY),
    };
}

std::optional<ShapeOptionsLayout>
OverlayInputRouter::currentShapeOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isShapeToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
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
    const AnnotationRect safe{
        8.0F,
        8.0F,
        (std::max)(0.0F, chrome.overlayBounds.width - 16.0F),
        (std::max)(0.0F, chrome.overlayBounds.height - 16.0F),
    };
    auto x = (std::max)(safe.x, (std::min)(
        chrome.toolbar.bounds.x,
        safe.x + (std::max)(0.0F, safe.width - initial.toolbar.width)));
    auto y = chrome.toolbar.bounds.y + chrome.toolbar.bounds.height + 8.0F;
    if (y + initial.toolbar.height > safe.y + safe.height) {
        y = chrome.toolbar.bounds.y - 8.0F - initial.toolbar.height;
    }
    y = (std::max)(safe.y, (std::min)(
        y, safe.y + (std::max)(0.0F, safe.height - initial.toolbar.height)));
    return shapeOptionsLayout({x, y}, macShapePalette().size());
}

std::optional<ArrowLineOptionsLayout>
OverlayInputRouter::currentArrowLineOptionsLayout(
    const OverlaySurface& surface) const
{
    if (!editor_ || !editor_->isArrowLineToolActive()
        || !model_.selection().has_value()) {
        return std::nullopt;
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
    const AnnotationRect safe{
        8.0F, 8.0F,
        (std::max)(0.0F, chrome.overlayBounds.width - 16.0F),
        (std::max)(0.0F, chrome.overlayBounds.height - 16.0F),
    };
    const auto x = (std::max)(safe.x, (std::min)(
        chrome.toolbar.bounds.x,
        safe.x + (std::max)(0.0F, safe.width - initial.toolbar.width)));
    auto y = chrome.toolbar.bounds.y + chrome.toolbar.bounds.height + 8.0F;
    if (y + initial.toolbar.height > safe.y + safe.height) {
        y = chrome.toolbar.bounds.y - 8.0F - initial.toolbar.height;
    }
    y = (std::max)(safe.y, (std::min)(
        y, safe.y + (std::max)(0.0F, safe.height - initial.toolbar.height)));
    return arrowLineOptionsLayout({x, y}, macShapePalette().size());
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
        if (!presentation.showActions || !presentation.selection.has_value()) {
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
        presentation.toolbarItems.reserve(layout.toolbarItems.size());
        for (const auto& item : layout.toolbarItems) {
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
        if (editor_ != nullptr && editorOwnerIndex_ == index) {
            const auto selection = snipory::core::portable::standardized(
                *presentation.selection);
            presentation.annotationPlan = editor_->renderPlan({
                physicalPixelsToDip(
                    selection.x - surface.physicalBounds.x, surface.dpiX),
                physicalPixelsToDip(
                    selection.y - surface.physicalBounds.y, surface.dpiY),
            });
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
        }
    }
    return result;
}

std::optional<ToolbarAction> OverlayInputRouter::hitToolbarAction(
    const OverlaySurface& surface, PixelPoint clientPoint) const noexcept
{
    const auto owner = actionOwner();
    if (!owner.has_value() || &surfaces_[*owner] != &surface
        || !model_.selection().has_value()) {
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

bool OverlayInputRouter::pointerDown(HWND source, PixelPoint clientPoint) noexcept
{
    if (status_ != OverlayInputStatus::active || dragging_) {
        return false;
    }
    const auto* surface = surfaceFor(source);
    if (surface == nullptr) {
        return false;
    }
    if (editor_ != nullptr && editorOwnerIndex_.has_value()
        && &surfaces_[*editorOwnerIndex_] == surface) {
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
            if (const auto arrowOptions
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
    if (const auto action = hitToolbarAction(*surface, clientPoint)) {
        if (!toolbarActionEnabled(*action)) {
            return true;
        }
        if (*action == ToolbarAction::cancel) {
            cancelOnce();
        } else if (*action == ToolbarAction::save) {
            completeOnce(OverlayInputAction::save);
        } else if (*action == ToolbarAction::copy) {
            completeOnce(OverlayInputAction::copy);
        } else if (editor_ != nullptr) {
            editor_->handleToolbarAction(*action);
        }
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
            if (editor_->cornerRadiusPanelVisible()) {
                const AnnotationRect safe{
                    0.0F,
                    0.0F,
                    physicalPixelsToDip(
                        surface->physicalBounds.width, surface->dpiX),
                    physicalPixelsToDip(
                        surface->physicalBounds.height, surface->dpiY),
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
                        (point.x - panel.sliderTrack.x)
                            / panel.sliderTrack.width));
                    editor_->setCornerRadius(
                        static_cast<float>(static_cast<int>(ratio * 30.0F + 0.5F)));
                    return true;
                }
                if (contains(panel.panel, point)) {
                    return true;
                }
            }
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
    }

    const auto virtualPoint = toVirtual(*surface, clientPoint);
    if (editor_ != nullptr) {
        if (const auto local = annotationPoint(virtualPoint);
            local.has_value() && editor_->pointerDown(*local)) {
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
    const auto hit = model_.phase() == SelectionPhase::ready
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
        && &surfaces_[*editorOwnerIndex_] == surface) {
        if (const auto options = currentShapeOptionsLayout(*surface);
            options.has_value() && contains(options->toolbar, surfacePoint)) {
            return OverlayCursorStyle::arrow;
        }
        if (const auto options = currentArrowLineOptionsLayout(*surface);
            options.has_value() && contains(options->toolbar, surfacePoint)) {
            return OverlayCursorStyle::arrow;
        }
    }

    const auto virtualPoint = toVirtual(*surface, clientPoint);
    if (editor_ != nullptr) {
        if (const auto local = annotationPoint(virtualPoint)) {
            const auto shapeStyle = editor_->cursorStyleAt(*local);
            if (shapeStyle != ShapeCursorStyle::arrow) {
                return cursorStyleForShape(shapeStyle);
            }
        }
    }

    if (model_.phase() == SelectionPhase::moving) {
        return OverlayCursorStyle::move;
    }
    if (model_.phase() == SelectionPhase::resizing) {
        return cursorStyleForSelectionHandle(model_.activeHandle());
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

void OverlayInputRouter::pointerMove(HWND, PixelPoint) noexcept
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
    platformPointerMove(*point);
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
        if (annotationDragging_ && editor_ != nullptr) {
            if (const auto local = annotationPoint(virtualPoint)) {
                editor_->pointerMove(*local);
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
    if (annotationDragging_ && editor_ != nullptr) {
        if (const auto local = annotationPoint(virtualPoint)) {
            editor_->pointerUp(*local);
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
    captureWindow_ = nullptr;
    releasingCapture_ = true;
    const auto released = platform_.releaseMouse();
    releasingCapture_ = false;
    if (!released) {
        lastError_ = OverlayInputErrorCode::mouseReleaseFailed;
        cancelOnce();
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
            return;
        }
    }
    cancelOnce();
}

void OverlayInputRouter::cancelPressed() noexcept
{
    cancelOnce();
}

bool OverlayInputRouter::keyPressed(
    ShapeEditorKey key,
    bool control,
    bool shift) noexcept
{
    if (status_ != OverlayInputStatus::active || editor_ == nullptr) {
        return false;
    }
    const auto result = editor_->handleKey(key, control, shift);
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
    }
    return false;
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
    annotationDragging_ = false;
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

struct OverlayHost::Impl final : std::enable_shared_from_this<OverlayHost::Impl> {
    HINSTANCE instance = nullptr;
    const FrozenDesktop* desktop = nullptr;
    RestartCallback restartCallback;
    ActionCallback actionCallback;
    std::unique_ptr<OverlayInputPlatform> platform;
    std::vector<std::unique_ptr<OverlayWindow>> windows;
    std::unique_ptr<OverlayInputRouter> router;
    bool restartRequested = false;

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
        closeWindows();
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
        if (restartRequested || !router) {
            return;
        }
        switch (input.kind) {
        case OverlayWindowInputKind::pointerDown:
            router->pointerDown(source, input.clientPoint);
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
        case OverlayWindowInputKind::keyDown: {
            ShapeEditorKey key;
            switch (input.virtualKey) {
            case VK_DELETE:
                key = ShapeEditorKey::deleteKey;
                break;
            case 'Z':
                key = ShapeEditorKey::z;
                break;
            case 'S':
                key = ShapeEditorKey::save;
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
        }
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
                state.annotationPlan = current[index].annotationPlan;
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
            true);
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
