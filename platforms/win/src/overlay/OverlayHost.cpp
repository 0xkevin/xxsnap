#include "overlay/OverlayHost.h"

#include "overlay/OverlayRenderer.h"

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

bool contains(DipRect rect, float x, float y) noexcept
{
    return x >= rect.x && y >= rect.y
        && x < rect.x + rect.width && y < rect.y + rect.height;
}

PixelPoint buttonCenterPhysical(DipRect rect, const OverlaySurface& surface) noexcept
{
    const auto x = static_cast<std::int64_t>(std::llround(
        (static_cast<double>(rect.x) + static_cast<double>(rect.width) / 2.0)
        * static_cast<double>(surface.dpiX == 0 ? 96U : surface.dpiX) / 96.0));
    const auto y = static_cast<std::int64_t>(std::llround(
        (static_cast<double>(rect.y) + static_cast<double>(rect.height) / 2.0)
        * static_cast<double>(surface.dpiY == 0 ? 96U : surface.dpiY) / 96.0));
    return {x, y};
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
};

} // namespace

OverlayInputRouter::OverlayInputRouter(
    PixelRect virtualBounds,
    std::vector<OverlaySurface> surfaces,
    OverlayInputPlatform& platform,
    ActionCallback actionCallback)
    : model_(snipory::core::portable::standardized(virtualBounds))
    , surfaces_(std::move(surfaces))
    , platform_(platform)
    , actionCallback_(std::move(actionCallback))
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
    return true;
}

bool OverlayInputRouter::deactivateEscapeHotKey() noexcept
{
    if (escapeHotKeyWindow_ == nullptr) {
        return true;
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
        const auto layout = computeOverlayLayout({
            surface.physicalBounds,
            *presentation.selection,
            surface.dpiX,
            surface.dpiY,
            0.0F,
            true,
        });
        presentation.cancelButtonCenterPhysical = buttonCenterPhysical(
            layout.cancel, surface);
        presentation.saveButtonCenterPhysical = buttonCenterPhysical(
            layout.save, surface);
        presentation.copyButtonCenterPhysical = buttonCenterPhysical(
            layout.copy, surface);
    }
    return result;
}

std::optional<OverlayInputAction> OverlayInputRouter::hitAction(
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
    });
    const auto x = static_cast<float>(clientPoint.x) * 96.0F
        / static_cast<float>(surface.dpiX);
    const auto y = static_cast<float>(clientPoint.y) * 96.0F
        / static_cast<float>(surface.dpiY);
    if (contains(layout.cancel, x, y)) {
        return OverlayInputAction::cancel;
    }
    if (contains(layout.save, x, y)) {
        return OverlayInputAction::save;
    }
    if (contains(layout.copy, x, y)) {
        return OverlayInputAction::copy;
    }
    return std::nullopt;
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
    if (const auto action = hitAction(*surface, clientPoint)) {
        if (*action == OverlayInputAction::cancel) {
            cancelOnce();
        } else {
            completeOnce(*action);
        }
        return true;
    }
    if (!platform_.captureMouse(source)) {
        lastError_ = OverlayInputErrorCode::mouseCaptureFailed;
        cancelOnce();
        return false;
    }

    const auto point = toVirtual(*surface, clientPoint);
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
    return true;
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
        model_.updateInteraction(virtualPoint);
    }
}

void OverlayInputRouter::platformPointerUp(PixelPoint virtualPoint) noexcept
{
    if (!dragging_ || status_ != OverlayInputStatus::active) {
        return;
    }
    model_.updateInteraction(virtualPoint);
    model_.finishInteraction();
    dragging_ = false;
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
        cancelOnce();
    }
}

void OverlayInputRouter::cancelMode() noexcept
{
    cancelOnce();
}

void OverlayInputRouter::escapePressed() noexcept
{
    cancelOnce();
}

void OverlayInputRouter::cancelPressed() noexcept
{
    cancelOnce();
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
                windows[index]->setSelection(
                    current[index].selection, current[index].showActions);
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
            });
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
