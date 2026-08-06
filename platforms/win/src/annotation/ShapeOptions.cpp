#include "annotation/ShapeOptions.h"

namespace xxsnap::win {
namespace {

constexpr std::array<AnnotationColor, 20> palette{
    AnnotationColor{255, 0, 26, 255},
    AnnotationColor{138, 138, 138, 255},
    AnnotationColor{0, 0, 0, 255},
    AnnotationColor{163, 0, 13, 255},
    AnnotationColor{255, 126, 6, 255},
    AnnotationColor{255, 243, 0, 255},
    AnnotationColor{0, 190, 78, 255},
    AnnotationColor{0, 176, 239, 255},
    AnnotationColor{60, 83, 215, 255},
    AnnotationColor{187, 74, 176, 255},
    AnnotationColor{255, 255, 255, 255},
    AnnotationColor{202, 202, 202, 255},
    AnnotationColor{206, 129, 93, 255},
    AnnotationColor{255, 178, 208, 255},
    AnnotationColor{255, 204, 0, 255},
    AnnotationColor{245, 231, 181, 255},
    AnnotationColor{179, 235, 0, 255},
    AnnotationColor{142, 225, 238, 255},
    AnnotationColor{111, 158, 200, 255},
    AnnotationColor{208, 198, 236, 255},
};

constexpr std::array<float, 3> strokeWidths{2.0F, 4.0F, 7.0F};

constexpr std::array<AnnotationStrokePattern, 6> strokePatterns{
    AnnotationStrokePattern::solid,
    AnnotationStrokePattern::dashLong,
    AnnotationStrokePattern::dashNarrow,
    AnnotationStrokePattern::dashLongShort,
    AnnotationStrokePattern::sketchSolid,
    AnnotationStrokePattern::sketchDashed,
};

constexpr float minimum(float left, float right) noexcept
{
    return left < right ? left : right;
}

constexpr float maximum(float left, float right) noexcept
{
    return left > right ? left : right;
}

constexpr float clampValue(float value, float lower, float upper) noexcept
{
    return maximum(lower, minimum(value, upper));
}

constexpr AnnotationRect inset(
    AnnotationRect rect,
    float horizontal,
    float vertical) noexcept
{
    return {
        rect.x + horizontal,
        rect.y + vertical,
        rect.width - horizontal * 2.0F,
        rect.height - vertical * 2.0F,
    };
}

constexpr bool contains(
    AnnotationRect rect,
    AnnotationPoint point) noexcept
{
    return point.x >= rect.x
        && point.y >= rect.y
        && point.x <= rect.x + rect.width
        && point.y <= rect.y + rect.height;
}

float floorWithoutRuntime(float value) noexcept
{
    const auto truncated = static_cast<int>(value);
    return static_cast<float>(
        static_cast<float>(truncated) > value ? truncated - 1 : truncated);
}

std::size_t clampedPaletteCount(std::size_t count) noexcept
{
    if (count < 4U) {
        return 4U;
    }
    return count > 20U ? 20U : count;
}

} // namespace

const std::array<AnnotationColor, 20>& macShapePalette() noexcept
{
    return palette;
}

const std::array<AnnotationStrokePattern, 6>& macShapeStrokePatterns() noexcept
{
    return strokePatterns;
}

ShapeOptionsState::ShapeOptionsState() noexcept
    : style_(primaryShapeActivationStyle({})), selectedPaletteIndex_(0U)
{
    style_.strokeColor = palette.front();
    style_.fillColor = palette.front();
}

AnnotationKind ShapeOptionsState::kind() const noexcept
{
    return kind_;
}

const AnnotationStyle& ShapeOptionsState::style() const noexcept
{
    return style_;
}

std::optional<std::size_t> ShapeOptionsState::selectedPaletteIndex() const noexcept
{
    return selectedPaletteIndex_;
}

bool ShapeOptionsState::load(
    AnnotationKind kind,
    AnnotationStyle style) noexcept
{
    if (!isShapeKind(kind)) {
        return false;
    }
    const auto changed = kind_ != kind || style_ != style;
    kind_ = kind;
    style_ = style;
    refreshPaletteSelection();
    return changed;
}

bool ShapeOptionsState::setKind(AnnotationKind kind) noexcept
{
    if (!isShapeKind(kind) || kind_ == kind) {
        return false;
    }
    kind_ = kind;
    return true;
}

bool ShapeOptionsState::setStrokeWidth(float strokeWidthDip) noexcept
{
    bool supported = false;
    for (const auto candidate : strokeWidths) {
        if (candidate == strokeWidthDip) {
            supported = true;
            break;
        }
    }
    if (!supported || style_.strokeWidthDip == strokeWidthDip) {
        return false;
    }
    style_.strokeWidthDip = strokeWidthDip;
    return true;
}

bool ShapeOptionsState::setStrokePattern(
    AnnotationStrokePattern pattern) noexcept
{
    if (style_.strokePattern == pattern) {
        return false;
    }
    style_.strokePattern = pattern;
    return true;
}

bool ShapeOptionsState::toggleFill() noexcept
{
    style_.fillEnabled = !style_.fillEnabled;
    return true;
}

bool ShapeOptionsState::setCornerRadius(float cornerRadiusDip) noexcept
{
    if (cornerRadiusDip != cornerRadiusDip) {
        return false;
    }
    const auto clamped = clampValue(cornerRadiusDip, 0.0F, 30.0F);
    if (style_.cornerRadiusDip == clamped) {
        return false;
    }
    style_.cornerRadiusDip = clamped;
    return true;
}

bool ShapeOptionsState::adjustCornerRadius(float deltaDip) noexcept
{
    if (deltaDip != deltaDip) {
        return false;
    }
    return setCornerRadius(style_.cornerRadiusDip + deltaDip);
}

bool ShapeOptionsState::selectPalette(std::size_t index) noexcept
{
    if (index >= palette.size()) {
        return false;
    }
    const auto color = palette[index];
    const auto changed = !(style_.strokeColor == color)
        || !(style_.fillColor == color)
        || selectedPaletteIndex_ != index;
    style_.strokeColor = color;
    style_.fillColor = color;
    selectedPaletteIndex_ = index;
    return changed;
}

bool ShapeOptionsState::selectCustomColor(AnnotationColor color) noexcept
{
    color.alpha = 255;
    const auto changed = !(style_.strokeColor == color)
        || !(style_.fillColor == color)
        || selectedPaletteIndex_.has_value();
    style_.strokeColor = color;
    style_.fillColor = color;
    selectedPaletteIndex_.reset();
    return changed;
}

void ShapeOptionsState::refreshPaletteSelection() noexcept
{
    selectedPaletteIndex_.reset();
    for (std::size_t index = 0; index < palette.size(); ++index) {
        if (palette[index] == style_.strokeColor) {
            selectedPaletteIndex_ = index;
            return;
        }
    }
}

ShapeOptionsLayout shapeOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount)
{
    ShapeOptionsLayout layout;
    layout.paletteCount = clampedPaletteCount(paletteCount);
    const auto rows = layout.paletteCount <= 10U ? 1U : 2U;
    const auto columns = (layout.paletteCount + rows - 1U) / rows;
    const auto customSize = rows == 1U ? 20.0F : 32.0F;
    const auto width = 329.0F
        + static_cast<float>(columns) * 16.0F
        + 2.0F
        + customSize
        + 10.0F;
    const auto height = rows == 1U ? 30.0F : 40.0F;
    layout.toolbar = {origin.x, origin.y, width, height};
    const auto controlY = origin.y + (height - 20.0F) / 2.0F;

    for (std::size_t index = 0; index < strokeWidths.size(); ++index) {
        const AnnotationRect control{
            origin.x + 10.0F + static_cast<float>(index) * 24.0F,
            controlY,
            20.0F,
            20.0F,
        };
        layout.strokeWidths.push_back(control);
        layout.strokeWidthHits.push_back(inset(control, -3.0F, -5.0F));
    }

    layout.fillToggle = {origin.x + 90.0F, controlY, 20.0F, 20.0F};
    layout.fillToggleBackground = inset(layout.fillToggle, -3.0F, -5.0F);
    layout.rectangleMode = {origin.x + 130.0F, controlY, 26.0F, 20.0F};
    layout.rectangleModeBackground = inset(
        layout.rectangleMode, -3.0F, -4.0F);
    layout.rectangleDisclosure = {
        layout.rectangleModeBackground.x
            + layout.rectangleModeBackground.width - 12.0F,
        layout.rectangleModeBackground.y
            + layout.rectangleModeBackground.height - 12.0F,
        12.0F,
        12.0F,
    };
    layout.ellipseMode = {origin.x + 162.0F, controlY, 22.0F, 20.0F};
    layout.ellipseModeBackground = inset(
        layout.ellipseMode, -3.0F, -5.0F);
    layout.strokeStyle = {origin.x + 204.0F, controlY, 102.0F, 20.0F};

    for (std::size_t index = 0; index < layout.paletteCount; ++index) {
        const auto column = index % columns;
        const auto row = rows == 1U ? 0U : index / columns;
        const auto swatchY = rows == 1U
            ? origin.y + (height - 12.0F) / 2.0F
            : origin.y + 5.0F + static_cast<float>(row) * 16.0F;
        layout.colorSwatches.push_back({
            origin.x + 329.0F + static_cast<float>(column) * 16.0F,
            swatchY,
            12.0F,
            12.0F,
        });
    }
    layout.colorSwatches.push_back({
        origin.x + 329.0F + static_cast<float>(columns) * 16.0F + 2.0F,
        origin.y + (height - customSize) / 2.0F,
        customSize,
        customSize,
    });

    const auto firstSeparatorX = layout.fillToggleBackground.x
        + layout.fillToggleBackground.width
        + (layout.rectangleModeBackground.x
            - layout.fillToggleBackground.x
            - layout.fillToggleBackground.width) / 2.0F;
    const auto secondSeparatorX = layout.ellipseModeBackground.x
        + layout.ellipseModeBackground.width
        + (layout.strokeStyle.x
            - layout.ellipseModeBackground.x
            - layout.ellipseModeBackground.width) / 2.0F;
    const auto firstSwatchX = layout.colorSwatches.front().x;
    const auto thirdSeparatorX = layout.strokeStyle.x
        + layout.strokeStyle.width
        + (firstSwatchX - layout.strokeStyle.x - layout.strokeStyle.width) / 2.0F;
    for (const auto x : {
             firstSeparatorX,
             secondSeparatorX,
             thirdSeparatorX}) {
        layout.separators.push_back({
            floorWithoutRuntime(x) + 0.25F,
            origin.y + height / 2.0F - 6.0F,
            1.5F,
            12.0F,
        });
    }
    return layout;
}

std::optional<ShapeOptionHit> shapeOptionHitTest(
    const ShapeOptionsLayout& layout,
    AnnotationPoint point) noexcept
{
    for (std::size_t index = 0; index < layout.strokeWidthHits.size(); ++index) {
        if (contains(layout.strokeWidthHits[index], point)) {
            return ShapeOptionHit{ShapeOptionControl::strokeWidth, index};
        }
    }
    if (contains(layout.fillToggle, point)) {
        return ShapeOptionHit{ShapeOptionControl::fillToggle, 0};
    }
    if (contains(layout.rectangleDisclosure, point)) {
        return ShapeOptionHit{ShapeOptionControl::cornerRadiusDisclosure, 0};
    }
    if (contains(layout.rectangleMode, point)) {
        return ShapeOptionHit{ShapeOptionControl::rectangleMode, 0};
    }
    if (contains(layout.ellipseMode, point)) {
        return ShapeOptionHit{ShapeOptionControl::ellipseMode, 0};
    }
    if (contains(layout.strokeStyle, point)) {
        return ShapeOptionHit{ShapeOptionControl::strokeStyle, 0};
    }
    if (layout.colorSwatches.empty()) {
        return std::nullopt;
    }
    for (std::size_t index = 0; index + 1U < layout.colorSwatches.size(); ++index) {
        if (contains(inset(layout.colorSwatches[index], -3.0F, -3.0F), point)) {
            return ShapeOptionHit{ShapeOptionControl::palette, index};
        }
    }
    const auto customIndex = layout.colorSwatches.size() - 1U;
    if (contains(inset(layout.colorSwatches.back(), -2.0F, -2.0F), point)) {
        return ShapeOptionHit{ShapeOptionControl::customColor, customIndex};
    }
    return std::nullopt;
}

StrokePatternMenuLayout strokePatternMenuLayout(AnnotationRect menu)
{
    StrokePatternMenuLayout layout;
    layout.menu = standardized(menu);
    constexpr std::size_t itemCount = 6U;
    for (std::size_t index = 0; index < itemCount; ++index) {
        layout.items.push_back({
            layout.menu.x + 4.0F,
            layout.menu.y + 4.0F + static_cast<float>(index) * 24.0F,
            layout.menu.width - 8.0F,
            20.0F,
        });
    }
    return layout;
}

std::optional<std::size_t> hitTestStrokePatternMenu(
    const StrokePatternMenuLayout& layout,
    AnnotationPoint point) noexcept
{
    if (!contains(layout.menu, point)) {
        return std::nullopt;
    }
    for (std::size_t index = 0; index < layout.items.size(); ++index) {
        if (contains(layout.items[index], point)) {
            return index;
        }
    }
    return std::nullopt;
}

CornerRadiusPanelLayout cornerRadiusPanelLayout(
    const ShapeOptionsLayout& options,
    AnnotationRect safeBounds,
    float sliderLeadingOffsetDip) noexcept
{
    safeBounds = standardized(safeBounds);
    sliderLeadingOffsetDip = maximum(78.0F, sliderLeadingOffsetDip);
    const auto width = 260.0F + sliderLeadingOffsetDip - 78.0F;
    AnnotationRect panel{
        options.rectangleMode.x - 6.0F,
        options.toolbar.y + options.toolbar.height + 8.0F,
        width,
        30.0F,
    };
    const auto safe = inset(safeBounds, 8.0F, 8.0F);
    if (panel.y + panel.height > safe.y + safe.height) {
        panel.y = options.toolbar.y - 38.0F;
    }
    const auto maximumX = safe.x + maximum(0.0F, safe.width - panel.width);
    const auto maximumY = safe.y + maximum(0.0F, safe.height - panel.height);
    panel.x = clampValue(panel.x, safe.x, maximumX);
    panel.y = clampValue(panel.y, safe.y, maximumY);

    CornerRadiusPanelLayout layout;
    layout.panel = panel;
    layout.label = {panel.x + 8.0F, panel.y + 8.0F, 62.0F, 14.0F};
    layout.value = {
        panel.x + panel.width - 55.0F,
        panel.y + 3.0F,
        52.0F,
        24.0F,
    };
    layout.sliderTrack = {
        panel.x + sliderLeadingOffsetDip,
        panel.y + 13.0F,
        layout.value.x - panel.x - sliderLeadingOffsetDip - 8.0F,
        4.0F,
    };
    layout.increment = {
        layout.value.x + layout.value.width - 17.0F,
        layout.value.y,
        18.0F,
        layout.value.height / 2.0F,
    };
    layout.decrement = {
        layout.value.x + layout.value.width - 17.0F,
        layout.value.y + layout.value.height / 2.0F,
        18.0F,
        layout.value.height / 2.0F,
    };
    return layout;
}

} // namespace xxsnap::win
