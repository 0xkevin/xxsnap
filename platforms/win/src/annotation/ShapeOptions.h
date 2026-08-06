#pragma once

#include "annotation/AnnotationTypes.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace xxsnap::win {

const std::array<AnnotationColor, 20>& macShapePalette() noexcept;
const std::array<AnnotationStrokePattern, 6>& macShapeStrokePatterns() noexcept;

class ShapeOptionsState {
public:
    ShapeOptionsState() noexcept;

    AnnotationKind kind() const noexcept;
    const AnnotationStyle& style() const noexcept;
    std::optional<std::size_t> selectedPaletteIndex() const noexcept;

    bool load(AnnotationKind kind, AnnotationStyle style) noexcept;
    bool setKind(AnnotationKind kind) noexcept;
    bool setStrokeWidth(float strokeWidthDip) noexcept;
    bool setStrokePattern(AnnotationStrokePattern pattern) noexcept;
    bool toggleFill() noexcept;
    bool setCornerRadius(float cornerRadiusDip) noexcept;
    bool adjustCornerRadius(float deltaDip) noexcept;
    bool selectPalette(std::size_t index) noexcept;
    bool selectCustomColor(AnnotationColor color) noexcept;

private:
    void refreshPaletteSelection() noexcept;

    AnnotationKind kind_ = AnnotationKind::rectangle;
    AnnotationStyle style_{};
    std::optional<std::size_t> selectedPaletteIndex_;
};

enum class ShapeOptionControl : std::uint8_t {
    strokeWidth,
    fillToggle,
    rectangleMode,
    ellipseMode,
    strokeStyle,
    palette,
    customColor,
};

struct ShapeOptionHit {
    ShapeOptionControl control = ShapeOptionControl::strokeWidth;
    std::size_t index = 0;
};

constexpr bool operator==(
    ShapeOptionHit left,
    ShapeOptionHit right) noexcept
{
    return left.control == right.control && left.index == right.index;
}

struct ShapeOptionsLayout {
    AnnotationRect toolbar{};
    std::size_t paletteCount = 0;
    std::vector<AnnotationRect> strokeWidths;
    std::vector<AnnotationRect> strokeWidthHits;
    AnnotationRect fillToggle{};
    AnnotationRect fillToggleBackground{};
    AnnotationRect rectangleMode{};
    AnnotationRect rectangleModeBackground{};
    AnnotationRect ellipseMode{};
    AnnotationRect ellipseModeBackground{};
    AnnotationRect strokeStyle{};
    std::vector<AnnotationRect> colorSwatches;
    std::vector<AnnotationRect> separators;
};

ShapeOptionsLayout shapeOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount);

std::optional<ShapeOptionHit> shapeOptionHitTest(
    const ShapeOptionsLayout& layout,
    AnnotationPoint point) noexcept;

struct StrokePatternMenuLayout {
    AnnotationRect menu{};
    std::vector<AnnotationRect> items;
};

StrokePatternMenuLayout strokePatternMenuLayout(AnnotationRect menu);

std::optional<std::size_t> hitTestStrokePatternMenu(
    const StrokePatternMenuLayout& layout,
    AnnotationPoint point) noexcept;

struct CornerRadiusPanelLayout {
    AnnotationRect panel{};
    AnnotationRect label{};
    AnnotationRect sliderTrack{};
    AnnotationRect value{};
    AnnotationRect increment{};
    AnnotationRect decrement{};
};

CornerRadiusPanelLayout cornerRadiusPanelLayout(
    const ShapeOptionsLayout& options,
    AnnotationRect safeBounds,
    float sliderLeadingOffsetDip = 78.0F) noexcept;

} // namespace xxsnap::win
