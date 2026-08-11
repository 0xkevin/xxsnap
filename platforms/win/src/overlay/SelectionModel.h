#pragma once

#include <cstdint>
#include <optional>

#include "snipory/core/portable/Geometry.h"

namespace xxsnap::win {

using snipory::core::portable::PixelPoint;
using snipory::core::portable::PixelRect;

enum class SelectionPhase {
    empty,
    creating,
    ready,
    moving,
    resizing,
};

enum class SelectionHandle {
    none,
    north,
    northEast,
    east,
    southEast,
    south,
    southWest,
    west,
    northWest,
    body,
};

class SelectionModel final {
public:
    explicit SelectionModel(PixelRect virtualBounds) noexcept;

    SelectionPhase phase() const noexcept;
    SelectionHandle activeHandle() const noexcept;
    const std::optional<PixelRect>& selection() const noexcept;

    void beginCreation(PixelPoint anchor) noexcept;
    bool beginMove(PixelPoint grabPoint) noexcept;
    bool beginResize(SelectionHandle handle, PixelPoint grabPoint) noexcept;
    void updateInteraction(PixelPoint pointer) noexcept;
    void finishInteraction() noexcept;

    SelectionHandle hitTest(PixelPoint point, std::int64_t handleRadius) const noexcept;

private:
    PixelRect virtualBounds_;
    std::optional<PixelRect> selection_;
    SelectionPhase phase_ = SelectionPhase::empty;
    SelectionHandle activeHandle_ = SelectionHandle::none;
    PixelPoint creationAnchor_{};
    PixelPoint grabOffset_{};
    std::int64_t fixedResizeX_ = 0;
    std::int64_t fixedResizeY_ = 0;
    int resizeHorizontalSide_ = 0;
    int resizeVerticalSide_ = 0;
};

} // namespace xxsnap::win
