#include "scroll/ScrollCaptureTargetDetector.h"

#include <UIAutomation.h>
#include <objbase.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <utility>

namespace xxsnap::win {
namespace {

template <typename T>
class ComPtr final {
public:
    ComPtr() = default;
    ~ComPtr() { reset(); }
    ComPtr(const ComPtr&) = delete;
    ComPtr& operator=(const ComPtr&) = delete;
    ComPtr(ComPtr&& other) noexcept
        : value_(std::exchange(other.value_, nullptr))
    {
    }
    ComPtr& operator=(ComPtr&& other) noexcept
    {
        if (this != &other) {
            reset();
            value_ = std::exchange(other.value_, nullptr);
        }
        return *this;
    }
    T* get() const noexcept { return value_; }
    T** put() noexcept
    {
        reset();
        return &value_;
    }
    void reset() noexcept
    {
        if (value_ != nullptr) {
            value_->Release();
            value_ = nullptr;
        }
    }
    explicit operator bool() const noexcept { return value_ != nullptr; }
    T* operator->() const noexcept { return value_; }

private:
    T* value_ = nullptr;
};

std::optional<PixelRect> intersect(PixelRect left, PixelRect right) noexcept
{
    left = snipory::core::portable::standardized(left);
    right = snipory::core::portable::standardized(right);
    const auto x1 = (std::max)(left.x, right.x);
    const auto y1 = (std::max)(left.y, right.y);
    const auto x2 = (std::min)(left.x + left.width, right.x + right.width);
    const auto y2 = (std::min)(left.y + left.height, right.y + right.height);
    if (x2 <= x1 || y2 <= y1) return std::nullopt;
    return PixelRect{x1, y1, x2 - x1, y2 - y1};
}

bool candidateIsBetter(
    const ScrollCaptureTargetCandidate& candidate,
    const ScrollCaptureTargetCandidate& current,
    PixelPoint center) noexcept
{
    const auto area = static_cast<long double>(candidate.bounds.width)
        * static_cast<long double>(candidate.bounds.height);
    const auto currentArea = static_cast<long double>(current.bounds.width)
        * static_cast<long double>(current.bounds.height);
    if (area != currentArea) return area > currentArea;
    if (candidate.bounds.height != current.bounds.height) {
        return candidate.bounds.height > current.bounds.height;
    }
    const auto distance = [center](PixelRect rect) {
        const auto dx = static_cast<long double>(rect.x) * 2.0L
            + static_cast<long double>(rect.width)
            - static_cast<long double>(center.x) * 2.0L;
        const auto dy = static_cast<long double>(rect.y) * 2.0L
            + static_cast<long double>(rect.height)
            - static_cast<long double>(center.y) * 2.0L;
        return dx * dx + dy * dy;
    };
    const auto candidateDistance = distance(candidate.bounds);
    const auto currentDistance = distance(current.bounds);
    if (candidateDistance != currentDistance) {
        return candidateDistance < currentDistance;
    }
    return candidate.firstProbeIndex < current.firstProbeIndex;
}

bool isVerticallyScrollable(IUIAutomationElement* element) noexcept
{
    if (element == nullptr) return false;
    ComPtr<IUIAutomationScrollPattern> scroll;
    if (FAILED(element->GetCurrentPatternAs(
            UIA_ScrollPatternId,
            __uuidof(IUIAutomationScrollPattern),
            reinterpret_cast<void**>(scroll.put())))
        || !scroll) {
        return false;
    }
    BOOL verticallyScrollable = FALSE;
    double percent = UIA_ScrollPatternNoScroll;
    double viewSize = 100.0;
    return SUCCEEDED(scroll->get_CurrentVerticallyScrollable(
               &verticallyScrollable))
        && SUCCEEDED(scroll->get_CurrentVerticalScrollPercent(&percent))
        && SUCCEEDED(scroll->get_CurrentVerticalViewSize(&viewSize))
        && verticallyScrollable != FALSE
        && std::isfinite(percent)
        && percent != UIA_ScrollPatternNoScroll
        && std::isfinite(viewSize)
        && viewSize >= 0.0 && viewSize < 100.0;
}

std::optional<PixelRect> elementBounds(
    IUIAutomationElement* element,
    DWORD targetProcessId) noexcept
{
    if (element == nullptr) return std::nullopt;
    int processId = 0;
    RECT bounds{};
    if (FAILED(element->get_CurrentProcessId(&processId))
        || processId <= 0
        || static_cast<DWORD>(processId) != targetProcessId
        || FAILED(element->get_CurrentBoundingRectangle(&bounds))
        || bounds.right <= bounds.left || bounds.bottom <= bounds.top) {
        return std::nullopt;
    }
    return PixelRect{
        bounds.left,
        bounds.top,
        static_cast<std::int64_t>(bounds.right) - bounds.left,
        static_cast<std::int64_t>(bounds.bottom) - bounds.top,
    };
}

} // namespace

std::vector<PixelPoint> scrollCaptureProbePoints(PixelRect selection)
{
    selection = snipory::core::portable::standardized(selection);
    const auto point = [selection](int xFraction, int yFraction) {
        return PixelPoint{
            selection.x + selection.width * xFraction / 10,
            selection.y + selection.height * yFraction / 10,
        };
    };
    std::vector<PixelPoint> result;
    result.reserve(9U);
    result.push_back(point(5, 5));
    for (const auto y : {2, 5, 8}) {
        for (const auto x : {2, 5, 8}) {
            const auto candidate = point(x, y);
            if (candidate.x != result.front().x
                || candidate.y != result.front().y) {
                result.push_back(candidate);
            }
        }
    }
    return result;
}

std::optional<PixelRect> bestScrollCaptureTarget(
    PixelRect selection,
    const std::vector<ScrollCaptureTargetCandidate>& candidates,
    std::int64_t minimumWidth,
    std::int64_t minimumHeight) noexcept
{
    selection = snipory::core::portable::standardized(selection);
    const PixelPoint center{
        selection.x + selection.width / 2,
        selection.y + selection.height / 2,
    };
    std::optional<ScrollCaptureTargetCandidate> best;
    for (const auto& candidate : candidates) {
        const auto clipped = intersect(selection, candidate.bounds);
        if (!clipped.has_value()
            || clipped->width < minimumWidth
            || clipped->height < minimumHeight) {
            continue;
        }
        const ScrollCaptureTargetCandidate ranked{
            *clipped, candidate.firstProbeIndex};
        if (!best.has_value() || candidateIsBetter(ranked, *best, center)) {
            best = ranked;
        }
    }
    return best.has_value()
        ? std::optional<PixelRect>(best->bounds)
        : std::nullopt;
}

std::optional<PixelRect> ScrollCaptureTargetDetector::detect(
    PixelRect selection,
    DWORD targetProcessId,
    UINT dpiX,
    UINT dpiY) const noexcept
{
    selection = snipory::core::portable::standardized(selection);
    if (selection.width <= 0 || selection.height <= 0
        || targetProcessId == 0U) {
        return std::nullopt;
    }
    const auto initialized = CoInitializeEx(
        nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    const auto uninitialize = SUCCEEDED(initialized);
    if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) {
        return std::nullopt;
    }

    ComPtr<IUIAutomation> automation;
    auto result = CoCreateInstance(
        __uuidof(CUIAutomation),
        nullptr,
        CLSCTX_INPROC_SERVER,
        __uuidof(IUIAutomation),
        reinterpret_cast<void**>(automation.put()));
    ComPtr<IUIAutomationTreeWalker> walker;
    if (SUCCEEDED(result)) {
        result = automation->get_ControlViewWalker(walker.put());
    }

    std::optional<PixelRect> detected;
    if (SUCCEEDED(result)) {
        const auto probes = scrollCaptureProbePoints(selection);
        for (std::size_t probeIndex = 0U;
             probeIndex < probes.size() && !detected.has_value();
             ++probeIndex) {
            const POINT point{
                static_cast<LONG>(probes[probeIndex].x),
                static_cast<LONG>(probes[probeIndex].y),
            };
            ComPtr<IUIAutomationElement> element;
            if (FAILED(automation->ElementFromPoint(point, element.put()))) {
                continue;
            }
            std::vector<ScrollCaptureTargetCandidate> candidates;
            for (int depth = 0; depth < 16 && element; ++depth) {
                if (isVerticallyScrollable(element.get())) {
                    if (const auto bounds = elementBounds(
                            element.get(), targetProcessId)) {
                        candidates.push_back({
                            *bounds, static_cast<int>(probeIndex)});
                    }
                }
                ComPtr<IUIAutomationElement> parent;
                if (FAILED(walker->GetParentElement(
                        element.get(), parent.put()))) {
                    break;
                }
                element = std::move(parent);
            }
            const auto minimumWidth = static_cast<std::int64_t>(
                std::ceil(120.0 * (dpiX == 0U ? 96U : dpiX) / 96.0));
            const auto minimumHeight = static_cast<std::int64_t>(
                std::ceil(120.0 * (dpiY == 0U ? 96U : dpiY) / 96.0));
            detected = bestScrollCaptureTarget(
                selection, candidates, minimumWidth, minimumHeight);
        }
    }
    if (uninitialize) CoUninitialize();
    return detected;
}

} // namespace xxsnap::win
