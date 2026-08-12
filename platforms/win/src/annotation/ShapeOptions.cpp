#include "annotation/ShapeOptions.h"

#include <algorithm>

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
constexpr std::array<float, 3> arrowStrokeWidths{3.0F, 4.0F, 6.0F};
constexpr std::array<float, 3> brushStrokeWidths{3.0F, 5.0F, 7.0F};
constexpr std::array<float, 3> markerStrokeWidths{14.0F, 18.0F, 22.0F};
constexpr std::array<float, 3> mosaicStrokeWidths{15.0F, 25.0F, 35.0F};

constexpr std::array<AnnotationStrokePattern, 6> strokePatterns{
    AnnotationStrokePattern::solid,
    AnnotationStrokePattern::dashLong,
    AnnotationStrokePattern::dashNarrow,
    AnnotationStrokePattern::dashLongShort,
    AnnotationStrokePattern::sketchSolid,
    AnnotationStrokePattern::sketchDashed,
};

constexpr std::array<AnnotationStrokePattern, 4> brushStrokePatterns{
    AnnotationStrokePattern::solid,
    AnnotationStrokePattern::dashLong,
    AnnotationStrokePattern::dashNarrow,
    AnnotationStrokePattern::dashLongShort,
};

constexpr std::array<ArrowType, 7> arrowTypes{
    ArrowType::none,
    ArrowType::normal,
    ArrowType::solidArrow,
    ArrowType::hollowArrow,
    ArrowType::diamond,
    ArrowType::bar,
    ArrowType::dot,
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

const std::array<ArrowType, 7>& macArrowTypes() noexcept
{
    return arrowTypes;
}

const std::array<float, 3>& macArrowStrokeWidths() noexcept
{
    return arrowStrokeWidths;
}

const std::array<float, 3>& macBrushStrokeWidths() noexcept
{
    return brushStrokeWidths;
}

const std::array<AnnotationStrokePattern, 4>& macBrushStrokePatterns() noexcept
{
    return brushStrokePatterns;
}

const std::array<float, 3>& macMarkerStrokeWidths() noexcept
{
    return markerStrokeWidths;
}

const std::array<float, 3>& macMosaicStrokeWidths() noexcept
{
    return mosaicStrokeWidths;
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

ArrowLineOptionsState::ArrowLineOptionsState() noexcept
    : selectedPaletteIndex_(0U)
{
    style_.strokeWidthDip = 4.0F;
    style_.strokeColor = palette.front();
}

const AnnotationStyle& ArrowLineOptionsState::style() const noexcept
{
    return style_;
}

ArrowType ArrowLineOptionsState::startArrowType() const noexcept
{
    return startArrowType_;
}

ArrowType ArrowLineOptionsState::endArrowType() const noexcept
{
    return endArrowType_;
}

std::optional<std::size_t> ArrowLineOptionsState::selectedPaletteIndex() const noexcept
{
    return selectedPaletteIndex_;
}

bool ArrowLineOptionsState::load(
    AnnotationStyle style,
    const ArrowLine& line) noexcept
{
    const auto changed = style_ != style
        || startArrowType_ != line.startArrowType
        || endArrowType_ != line.endArrowType;
    style_ = style;
    startArrowType_ = line.startArrowType;
    endArrowType_ = line.endArrowType;
    refreshPaletteSelection();
    return changed;
}

bool ArrowLineOptionsState::setStrokeWidth(float strokeWidthDip) noexcept
{
    bool supported = false;
    for (const auto candidate : arrowStrokeWidths) {
        supported = supported || candidate == strokeWidthDip;
    }
    if (!supported || style_.strokeWidthDip == strokeWidthDip) {
        return false;
    }
    style_.strokeWidthDip = strokeWidthDip;
    return true;
}

bool ArrowLineOptionsState::setStrokePattern(
    AnnotationStrokePattern pattern) noexcept
{
    if (style_.strokePattern == pattern) {
        return false;
    }
    style_.strokePattern = pattern;
    return true;
}

bool ArrowLineOptionsState::selectArrowType(
    ArrowEndpoint endpoint,
    ArrowType type) noexcept
{
    const auto isSingleEnded = [](ArrowType candidate) noexcept {
        return candidate == ArrowType::solidArrow
            || candidate == ArrowType::hollowArrow;
    };
    auto start = startArrowType_;
    auto end = endArrowType_;
    if (endpoint == ArrowEndpoint::start) {
        start = type;
        if (isSingleEnded(type)
            || (type != ArrowType::none && isSingleEnded(end))) {
            end = ArrowType::none;
        }
    } else {
        end = type;
        if (isSingleEnded(type)
            || (type != ArrowType::none && isSingleEnded(start))) {
            start = ArrowType::none;
        }
    }
    if (start == startArrowType_ && end == endArrowType_) {
        return false;
    }
    startArrowType_ = start;
    endArrowType_ = end;
    return true;
}

bool ArrowLineOptionsState::selectPalette(std::size_t index) noexcept
{
    if (index >= palette.size()) {
        return false;
    }
    const auto changed = !(style_.strokeColor == palette[index])
        || selectedPaletteIndex_ != index;
    style_.strokeColor = palette[index];
    selectedPaletteIndex_ = index;
    return changed;
}

bool ArrowLineOptionsState::selectCustomColor(AnnotationColor color) noexcept
{
    color.alpha = 255;
    const auto changed = !(style_.strokeColor == color)
        || selectedPaletteIndex_.has_value();
    style_.strokeColor = color;
    selectedPaletteIndex_.reset();
    return changed;
}

void ArrowLineOptionsState::refreshPaletteSelection() noexcept
{
    selectedPaletteIndex_.reset();
    for (std::size_t index = 0; index < palette.size(); ++index) {
        if (palette[index] == style_.strokeColor) {
            selectedPaletteIndex_ = index;
            return;
        }
    }
}

BrushOptionsState::BrushOptionsState() noexcept
    : selectedPaletteIndex_(0U)
{
    style_.strokeWidthDip = brushStrokeWidths.front();
    style_.strokePattern = AnnotationStrokePattern::solid;
    style_.strokeColor = palette.front();
    style_.fillColor = palette.front();
    style_.fillEnabled = false;
}

const AnnotationStyle& BrushOptionsState::style() const noexcept
{
    return style_;
}

std::optional<std::size_t> BrushOptionsState::selectedPaletteIndex() const noexcept
{
    return selectedPaletteIndex_;
}

bool BrushOptionsState::load(AnnotationStyle style) noexcept
{
    if (style.strokePattern == AnnotationStrokePattern::sketchSolid
        || style.strokePattern == AnnotationStrokePattern::sketchDashed) {
        style.strokePattern = AnnotationStrokePattern::solid;
    }
    style.fillEnabled = false;
    const auto changed = style_ != style;
    style_ = style;
    refreshPaletteSelection();
    return changed;
}

bool BrushOptionsState::setStrokeWidth(float strokeWidthDip) noexcept
{
    bool supported = false;
    for (const auto candidate : brushStrokeWidths) {
        supported = supported || candidate == strokeWidthDip;
    }
    if (!supported || style_.strokeWidthDip == strokeWidthDip) {
        return false;
    }
    style_.strokeWidthDip = strokeWidthDip;
    return true;
}

bool BrushOptionsState::setStrokePattern(
    AnnotationStrokePattern pattern) noexcept
{
    bool supported = false;
    for (const auto candidate : brushStrokePatterns) {
        supported = supported || candidate == pattern;
    }
    if (!supported || style_.strokePattern == pattern) {
        return false;
    }
    style_.strokePattern = pattern;
    return true;
}

bool BrushOptionsState::selectPalette(std::size_t index) noexcept
{
    if (index >= palette.size()) {
        return false;
    }
    const auto changed = !(style_.strokeColor == palette[index])
        || selectedPaletteIndex_ != index;
    style_.strokeColor = palette[index];
    style_.fillColor = palette[index];
    selectedPaletteIndex_ = index;
    return changed;
}

bool BrushOptionsState::selectCustomColor(AnnotationColor color) noexcept
{
    color.alpha = 255;
    const auto changed = !(style_.strokeColor == color)
        || selectedPaletteIndex_.has_value();
    style_.strokeColor = color;
    style_.fillColor = color;
    selectedPaletteIndex_.reset();
    return changed;
}

void BrushOptionsState::refreshPaletteSelection() noexcept
{
    selectedPaletteIndex_.reset();
    for (std::size_t index = 0; index < palette.size(); ++index) {
        if (palette[index] == style_.strokeColor) {
            selectedPaletteIndex_ = index;
            return;
        }
    }
}

MarkerOptionsState::MarkerOptionsState() noexcept
    : selectedPaletteIndex_(16U)
{
    style_.strokeColor = {179, 235, 0, 255};
    style_.fillColor = style_.strokeColor;
    style_.strokeWidthDip = markerStrokeWidths[1];
    style_.strokePattern = AnnotationStrokePattern::solid;
    style_.fillEnabled = false;
}

const AnnotationStyle& MarkerOptionsState::style() const noexcept
{
    return style_;
}

std::optional<std::size_t> MarkerOptionsState::selectedPaletteIndex() const noexcept
{
    return selectedPaletteIndex_;
}

bool MarkerOptionsState::load(AnnotationStyle style) noexcept
{
    style.strokePattern = AnnotationStrokePattern::solid;
    style.fillEnabled = false;
    style.strokeColor.alpha = 255;
    style.fillColor = style.strokeColor;
    const auto changed = style_ != style;
    style_ = style;
    refreshPaletteSelection();
    return changed;
}

bool MarkerOptionsState::setStrokeWidth(float strokeWidthDip) noexcept
{
    bool supported = false;
    for (const auto candidate : markerStrokeWidths) {
        supported = supported || candidate == strokeWidthDip;
    }
    if (!supported || style_.strokeWidthDip == strokeWidthDip) {
        return false;
    }
    style_.strokeWidthDip = strokeWidthDip;
    return true;
}

bool MarkerOptionsState::selectPalette(std::size_t index) noexcept
{
    if (index >= palette.size()) {
        return false;
    }
    const auto changed = !(style_.strokeColor == palette[index])
        || selectedPaletteIndex_ != index;
    style_.strokeColor = palette[index];
    style_.fillColor = palette[index];
    selectedPaletteIndex_ = index;
    return changed;
}

bool MarkerOptionsState::selectCustomColor(AnnotationColor color) noexcept
{
    color.alpha = 255;
    const auto changed = !(style_.strokeColor == color)
        || selectedPaletteIndex_.has_value();
    style_.strokeColor = color;
    style_.fillColor = color;
    selectedPaletteIndex_.reset();
    return changed;
}

void MarkerOptionsState::refreshPaletteSelection() noexcept
{
    selectedPaletteIndex_.reset();
    for (std::size_t index = 0; index < palette.size(); ++index) {
        if (palette[index] == style_.strokeColor) {
            selectedPaletteIndex_ = index;
            return;
        }
    }
}

BrushOptionsLayout brushOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount)
{
    BrushOptionsLayout layout;
    layout.paletteCount = clampedPaletteCount(paletteCount);
    const auto rows = layout.paletteCount <= 10U ? 1U : 2U;
    const auto columns = (layout.paletteCount + rows - 1U) / rows;
    const auto customSize = rows == 1U ? 20.0F : 32.0F;
    const auto height = rows == 1U ? 30.0F : 40.0F;
    const auto width = 214.0F + static_cast<float>(columns) * 16.0F
        + 2.0F + customSize + 10.0F;
    layout.toolbar = {origin.x, origin.y, width, height};
    const auto controlY = origin.y + (height - 20.0F) / 2.0F;
    for (std::size_t index = 0; index < brushStrokeWidths.size(); ++index) {
        const AnnotationRect control{
            origin.x + 10.0F + static_cast<float>(index) * 24.0F,
            controlY, 20.0F, 20.0F};
        layout.strokeWidths.push_back(control);
        layout.strokeWidthHits.push_back(inset(control, -3.0F, -5.0F));
    }
    layout.strokeStyle = {origin.x + 96.0F, controlY, 94.0F, 20.0F};
    layout.strokeStyleSampleStart = {
        layout.strokeStyle.x + 10.0F, controlY + 10.0F};
    layout.strokeStyleSampleEnd = {
        layout.strokeStyle.x + 72.0F, controlY + 10.0F};
    for (std::size_t index = 0; index < layout.paletteCount; ++index) {
        const auto column = index % columns;
        const auto row = rows == 1U ? 0U : index / columns;
        const auto swatchY = rows == 1U
            ? origin.y + (height - 12.0F) / 2.0F
            : origin.y + 5.0F + static_cast<float>(row) * 16.0F;
        layout.colorSwatches.push_back({
            origin.x + 214.0F + static_cast<float>(column) * 16.0F,
            swatchY, 12.0F, 12.0F});
    }
    layout.colorSwatches.push_back({
        origin.x + 214.0F + static_cast<float>(columns) * 16.0F + 2.0F,
        origin.y + (height - customSize) / 2.0F,
        customSize,
        customSize});
    const auto lastStrokeWidth = layout.strokeWidths.back();
    const auto firstSeparatorX = lastStrokeWidth.x + lastStrokeWidth.width
        + (layout.strokeStyle.x
            - lastStrokeWidth.x - lastStrokeWidth.width) / 2.0F;
    const auto secondSeparatorX = layout.strokeStyle.x
        + layout.strokeStyle.width
        + (layout.colorSwatches.front().x
            - layout.strokeStyle.x - layout.strokeStyle.width) / 2.0F;
    for (const auto x : {firstSeparatorX, secondSeparatorX}) {
        layout.separators.push_back({
            floorWithoutRuntime(x) + 0.25F,
            origin.y + height / 2.0F - 6.0F,
            1.5F,
            12.0F,
        });
    }
    return layout;
}

std::optional<BrushOptionHit> brushOptionHitTest(
    const BrushOptionsLayout& layout,
    AnnotationPoint point) noexcept
{
    for (std::size_t index = 0; index < layout.strokeWidthHits.size(); ++index) {
        if (contains(layout.strokeWidthHits[index], point)) {
            return BrushOptionHit{BrushOptionControl::strokeWidth, index};
        }
    }
    if (contains(layout.strokeStyle, point)) {
        return BrushOptionHit{BrushOptionControl::strokeStyle, 0};
    }
    if (layout.colorSwatches.empty()) {
        return std::nullopt;
    }
    for (std::size_t index = 0; index + 1U < layout.colorSwatches.size(); ++index) {
        if (contains(inset(layout.colorSwatches[index], -3.0F, -3.0F), point)) {
            return BrushOptionHit{BrushOptionControl::palette, index};
        }
    }
    if (contains(inset(layout.colorSwatches.back(), -2.0F, -2.0F), point)) {
        return BrushOptionHit{
            BrushOptionControl::customColor,
            layout.colorSwatches.size() - 1U};
    }
    return std::nullopt;
}

MarkerOptionsLayout markerOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount)
{
    MarkerOptionsLayout layout;
    layout.paletteCount = clampedPaletteCount(paletteCount);
    const auto rows = layout.paletteCount <= 10U ? 1U : 2U;
    const auto columns = (layout.paletteCount + rows - 1U) / rows;
    const auto customSize = rows == 1U ? 20.0F : 32.0F;
    const auto height = rows == 1U ? 30.0F : 40.0F;
    const auto width = 102.0F + static_cast<float>(columns) * 16.0F
        + 2.0F + customSize + 10.0F;
    layout.toolbar = {origin.x, origin.y, width, height};
    const auto controlY = origin.y + (height - 20.0F) / 2.0F;
    for (std::size_t index = 0; index < markerStrokeWidths.size(); ++index) {
        const AnnotationRect control{
            origin.x + 10.0F + static_cast<float>(index) * 24.0F,
            controlY, 20.0F, 20.0F};
        layout.strokeWidths.push_back(control);
        layout.strokeWidthHits.push_back(inset(control, -3.0F, -5.0F));
    }
    for (std::size_t index = 0; index < layout.paletteCount; ++index) {
        const auto column = index % columns;
        const auto row = rows == 1U ? 0U : index / columns;
        const auto swatchY = rows == 1U
            ? origin.y + (height - 12.0F) / 2.0F
            : origin.y + 5.0F + static_cast<float>(row) * 16.0F;
        layout.colorSwatches.push_back({
            origin.x + 102.0F + static_cast<float>(column) * 16.0F,
            swatchY, 12.0F, 12.0F});
    }
    layout.colorSwatches.push_back({
        origin.x + 102.0F + static_cast<float>(columns) * 16.0F + 2.0F,
        origin.y + (height - customSize) / 2.0F,
        customSize,
        customSize});
    const auto lastStrokeWidth = layout.strokeWidths.back();
    const auto separatorX = lastStrokeWidth.x + lastStrokeWidth.width
        + (layout.colorSwatches.front().x
            - lastStrokeWidth.x - lastStrokeWidth.width) / 2.0F;
    layout.separators.push_back({
        floorWithoutRuntime(separatorX) + 0.25F,
        origin.y + height / 2.0F - 6.0F,
        1.5F,
        12.0F,
    });
    return layout;
}

std::optional<MarkerOptionHit> markerOptionHitTest(
    const MarkerOptionsLayout& layout,
    AnnotationPoint point) noexcept
{
    for (std::size_t index = 0; index < layout.strokeWidthHits.size(); ++index) {
        if (contains(layout.strokeWidthHits[index], point)) {
            return MarkerOptionHit{MarkerOptionControl::strokeWidth, index};
        }
    }
    if (layout.colorSwatches.empty()) {
        return std::nullopt;
    }
    for (std::size_t index = 0; index + 1U < layout.colorSwatches.size(); ++index) {
        if (contains(inset(layout.colorSwatches[index], -3.0F, -3.0F), point)) {
            return MarkerOptionHit{MarkerOptionControl::palette, index};
        }
    }
    if (contains(inset(layout.colorSwatches.back(), -2.0F, -2.0F), point)) {
        return MarkerOptionHit{
            MarkerOptionControl::customColor,
            layout.colorSwatches.size() - 1U};
    }
    return std::nullopt;
}

MosaicOptionsState::MosaicOptionsState() noexcept
{
    style_.strokeWidthDip = mosaicStrokeWidths.front();
    style_.strokePattern = AnnotationStrokePattern::solid;
    style_.fillEnabled = false;
    style_.strokeColor = palette.front();
    style_.fillColor = palette.front();
}

const AnnotationStyle& MosaicOptionsState::style() const noexcept
{
    return style_;
}

AnnotationKind MosaicOptionsState::kind() const noexcept
{
    return kind_;
}

MosaicRedaction MosaicOptionsState::redaction() const noexcept
{
    const auto index = redactionType_ == MosaicRedactionType::gaussianBlur
        ? 0U : 1U;
    return {redactionType_, redactionValues_[index]};
}

bool MosaicOptionsState::load(const ShapeAnnotation& annotation) noexcept
{
    if (!isMosaicAnnotation(annotation)) {
        return false;
    }
    auto style = annotation.style;
    style.fillEnabled = false;
    style.strokePattern = AnnotationStrokePattern::solid;
    const auto redaction = *annotation.mosaicRedaction;
    const auto current = this->redaction();
    const auto changed = style_ != style || kind_ != annotation.kind
        || !(current == redaction);
    style_ = style;
    kind_ = annotation.kind;
    redactionType_ = redaction.type;
    setRedactionValue(redaction.value);
    return changed;
}

bool MosaicOptionsState::setStrokeWidth(float strokeWidthDip) noexcept
{
    auto supported = false;
    for (const auto candidate : mosaicStrokeWidths) {
        supported = supported || candidate == strokeWidthDip;
    }
    if (!supported) {
        return false;
    }
    const auto changed = style_.strokeWidthDip != strokeWidthDip
        || kind_ != AnnotationKind::mosaicStroke;
    style_.strokeWidthDip = strokeWidthDip;
    kind_ = AnnotationKind::mosaicStroke;
    return changed;
}

bool MosaicOptionsState::setKind(AnnotationKind kind) noexcept
{
    if ((kind != AnnotationKind::mosaicStroke
            && kind != AnnotationKind::mosaicRectangle)
        || kind_ == kind) {
        return false;
    }
    kind_ = kind;
    return true;
}

bool MosaicOptionsState::toggleRedactionType() noexcept
{
    redactionType_ = redactionType_ == MosaicRedactionType::pixelMosaic
        ? MosaicRedactionType::gaussianBlur
        : MosaicRedactionType::pixelMosaic;
    return true;
}

bool MosaicOptionsState::setRedactionValue(int value) noexcept
{
    value = clampedMosaicRedactionValue(value);
    const auto index = redactionType_ == MosaicRedactionType::gaussianBlur
        ? 0U : 1U;
    if (redactionValues_[index] == value) {
        return false;
    }
    redactionValues_[index] = value;
    return true;
}

MosaicOptionsLayout mosaicOptionsLayout(AnnotationPoint origin)
{
    MosaicOptionsLayout layout;
    layout.toolbar = {origin.x, origin.y, 252.0F, 28.0F};
    const auto controlY = origin.y + 4.0F;
    for (std::size_t index = 0; index < mosaicStrokeWidths.size(); ++index) {
        const AnnotationRect control{
            origin.x + 10.0F + static_cast<float>(index) * 24.0F,
            controlY, 20.0F, 20.0F};
        layout.strokeWidths.push_back(control);
        layout.strokeWidthHits.push_back(inset(control, -3.0F, -4.0F));
    }
    layout.rectangleMode = {origin.x + 88.0F, controlY, 20.0F, 20.0F};
    layout.redactionType = {origin.x + 118.0F, controlY, 20.0F, 20.0F};
    layout.redactionValue = {origin.x + 148.0F, controlY, 94.0F, 20.0F};
    layout.valueTrack = {
        layout.redactionValue.x + 8.0F,
        layout.redactionValue.y + 8.0F,
        54.0F,
        4.0F,
    };
    layout.valueLabel = {
        layout.redactionValue.x + 70.0F,
        layout.redactionValue.y,
        24.0F,
        20.0F,
    };
    return layout;
}

std::optional<MosaicOptionHit> mosaicOptionHitTest(
    const MosaicOptionsLayout& layout,
    AnnotationPoint point) noexcept
{
    for (std::size_t index = 0; index < layout.strokeWidthHits.size(); ++index) {
        if (contains(layout.strokeWidthHits[index], point)) {
            return MosaicOptionHit{MosaicOptionControl::strokeWidth, index};
        }
    }
    if (contains(layout.rectangleMode, point)) {
        return MosaicOptionHit{MosaicOptionControl::rectangleMode, 0};
    }
    if (contains(layout.redactionType, point)) {
        return MosaicOptionHit{MosaicOptionControl::redactionType, 0};
    }
    if (contains(layout.redactionValue, point)) {
        return MosaicOptionHit{MosaicOptionControl::redactionValue, 0};
    }
    return std::nullopt;
}

int mosaicValueForPoint(
    const MosaicOptionsLayout& layout,
    AnnotationPoint point) noexcept
{
    const auto progress = clampValue(
        (point.x - layout.valueTrack.x)
            / maximum(1.0F, layout.valueTrack.width),
        0.0F,
        1.0F);
    return mosaicMinimumRedactionValue + static_cast<int>(progress
        * static_cast<float>(mosaicMaximumRedactionValue
            - mosaicMinimumRedactionValue) + 0.5F);
}

ArrowLineOptionsLayout arrowLineOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount)
{
    ArrowLineOptionsLayout layout;
    layout.paletteCount = clampedPaletteCount(paletteCount);
    const auto rows = layout.paletteCount <= 10U ? 1U : 2U;
    const auto columns = (layout.paletteCount + rows - 1U) / rows;
    const auto customSize = rows == 1U ? 20.0F : 32.0F;
    const auto height = rows == 1U ? 30.0F : 40.0F;
    const auto width = 322.0F + static_cast<float>(columns) * 16.0F
        + 2.0F + customSize + 10.0F;
    layout.toolbar = {origin.x, origin.y, width, height};
    const auto controlY = origin.y + (height - 20.0F) / 2.0F;

    for (std::size_t index = 0; index < arrowStrokeWidths.size(); ++index) {
        const AnnotationRect control{
            origin.x + 10.0F + static_cast<float>(index) * 24.0F,
            controlY, 20.0F, 20.0F};
        layout.strokeWidths.push_back(control);
        layout.strokeWidthHits.push_back(inset(control, -3.0F, -5.0F));
    }
    layout.strokeStyle = {origin.x + 96.0F, controlY, 94.0F, 20.0F};
    layout.strokeStyleSampleStart = {
        layout.strokeStyle.x + 10.0F, controlY + 10.0F};
    layout.strokeStyleSampleEnd = {
        layout.strokeStyle.x + 72.0F, controlY + 10.0F};
    layout.startArrowType = {origin.x + 208.0F, controlY, 42.0F, 20.0F};
    layout.endArrowType = {origin.x + 256.0F, controlY, 42.0F, 20.0F};
    for (std::size_t index = 0; index < layout.paletteCount; ++index) {
        const auto column = index % columns;
        const auto row = rows == 1U ? 0U : index / columns;
        const auto swatchY = rows == 1U
            ? origin.y + (height - 12.0F) / 2.0F
            : origin.y + 5.0F + static_cast<float>(row) * 16.0F;
        layout.colorSwatches.push_back({
            origin.x + 322.0F + static_cast<float>(column) * 16.0F,
            swatchY, 12.0F, 12.0F});
    }
    layout.colorSwatches.push_back({
        origin.x + 322.0F + static_cast<float>(columns) * 16.0F + 2.0F,
        origin.y + (height - customSize) / 2.0F,
        customSize,
        customSize});
    const auto lastStrokeWidth = layout.strokeWidths.back();
    const auto firstSeparatorX = lastStrokeWidth.x + lastStrokeWidth.width
        + (layout.strokeStyle.x
            - lastStrokeWidth.x - lastStrokeWidth.width) / 2.0F;
    const auto secondSeparatorX = layout.strokeStyle.x
        + layout.strokeStyle.width
        + (layout.startArrowType.x
            - layout.strokeStyle.x - layout.strokeStyle.width) / 2.0F;
    const auto thirdSeparatorX = layout.endArrowType.x
        + layout.endArrowType.width
        + (layout.colorSwatches.front().x
            - layout.endArrowType.x - layout.endArrowType.width) / 2.0F;
    for (const auto x : {
             firstSeparatorX, secondSeparatorX, thirdSeparatorX}) {
        layout.separators.push_back({
            floorWithoutRuntime(x) + 0.25F,
            origin.y + height / 2.0F - 6.0F,
            1.5F,
            12.0F,
        });
    }
    return layout;
}

std::optional<ArrowLineOptionHit> arrowLineOptionHitTest(
    const ArrowLineOptionsLayout& layout,
    AnnotationPoint point) noexcept
{
    for (std::size_t index = 0; index < layout.strokeWidthHits.size(); ++index) {
        if (contains(layout.strokeWidthHits[index], point)) {
            return ArrowLineOptionHit{ArrowLineOptionControl::strokeWidth, index};
        }
    }
    if (contains(layout.strokeStyle, point)) {
        return ArrowLineOptionHit{ArrowLineOptionControl::strokeStyle, 0};
    }
    if (contains(layout.startArrowType, point)) {
        return ArrowLineOptionHit{ArrowLineOptionControl::startArrowType, 0};
    }
    if (contains(layout.endArrowType, point)) {
        return ArrowLineOptionHit{ArrowLineOptionControl::endArrowType, 0};
    }
    if (layout.colorSwatches.empty()) {
        return std::nullopt;
    }
    for (std::size_t index = 0; index + 1U < layout.colorSwatches.size(); ++index) {
        if (contains(inset(layout.colorSwatches[index], -3.0F, -3.0F), point)) {
            return ArrowLineOptionHit{ArrowLineOptionControl::palette, index};
        }
    }
    if (contains(inset(layout.colorSwatches.back(), -2.0F, -2.0F), point)) {
        return ArrowLineOptionHit{
            ArrowLineOptionControl::customColor,
            layout.colorSwatches.size() - 1U};
    }
    return std::nullopt;
}

ArrowTypeMenuLayout arrowTypeMenuLayout(AnnotationRect menu)
{
    ArrowTypeMenuLayout layout;
    layout.menu = standardized(menu);
    for (std::size_t index = 0; index < arrowTypes.size(); ++index) {
        layout.items.push_back({
            layout.menu.x + 4.0F,
            layout.menu.y + 4.0F + static_cast<float>(index) * 24.0F,
            layout.menu.width - 8.0F,
            20.0F});
    }
    return layout;
}

std::optional<std::size_t> hitTestArrowTypeMenu(
    const ArrowTypeMenuLayout& layout,
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
    layout.strokeStyleSampleStart = {
        layout.strokeStyle.x + 10.0F,
        layout.strokeStyle.y + layout.strokeStyle.height / 2.0F,
    };
    layout.strokeStyleSampleEnd = {
        layout.strokeStyle.x + layout.strokeStyle.width - 22.0F,
        layout.strokeStyle.y + layout.strokeStyle.height / 2.0F,
    };
    layout.strokeStyleDisclosure = {
        layout.strokeStyle.x + layout.strokeStyle.width - 16.0F,
        layout.strokeStyle.y + layout.strokeStyle.height / 2.0F - 2.0F,
        7.0F,
        5.0F,
    };

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

StrokePatternMenuLayout strokePatternMenuLayout(
    AnnotationRect menu,
    std::size_t itemCount)
{
    StrokePatternMenuLayout layout;
    layout.menu = standardized(menu);
    for (std::size_t index = 0; index < itemCount; ++index) {
        const AnnotationRect item{
            layout.menu.x + 4.0F,
            layout.menu.y + 4.0F + static_cast<float>(index) * 24.0F,
            layout.menu.width - 8.0F,
            20.0F,
        };
        layout.items.push_back(item);
        layout.sampleStarts.push_back({
            item.x + 10.0F,
            item.y + item.height / 2.0F,
        });
        layout.sampleEnds.push_back({
            item.x + item.width - 10.0F,
            item.y + item.height / 2.0F,
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
