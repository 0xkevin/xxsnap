#pragma once

#include <array>
#include <cstdint>
#include <optional>
#include <string_view>
#include <string>
#include <vector>

namespace xxsnap::win {

inline constexpr float textMinimumSize = 3.0F;
inline constexpr float textMaximumSize = 72.0F;
inline constexpr float textDefaultSize = 8.0F;
inline constexpr wchar_t textDefaultFontFamily[] = L"Microsoft YaHei";

constexpr float clampedTextSize(float size) noexcept
{
    return size < textMinimumSize ? textMinimumSize
        : size > textMaximumSize ? textMaximumSize : size;
}

using AnnotationId = std::uint64_t;
inline constexpr AnnotationId invalidAnnotationId = 0;

struct AnnotationPoint {
    float x = 0.0F;
    float y = 0.0F;
};

constexpr bool operator==(
    AnnotationPoint left,
    AnnotationPoint right) noexcept
{
    return left.x == right.x && left.y == right.y;
}

struct AnnotationRect {
    float x = 0.0F;
    float y = 0.0F;
    float width = 0.0F;
    float height = 0.0F;
};

constexpr bool operator==(
    AnnotationRect left,
    AnnotationRect right) noexcept
{
    return left.x == right.x
        && left.y == right.y
        && left.width == right.width
        && left.height == right.height;
}

struct EraserMask {
    AnnotationRect rect{};
    std::vector<AnnotationId> affectedAnnotationIds;
};

constexpr AnnotationRect standardized(AnnotationRect rect) noexcept
{
    if (rect.width < 0.0F) {
        rect.x += rect.width;
        rect.width = -rect.width;
    }
    if (rect.height < 0.0F) {
        rect.y += rect.height;
        rect.height = -rect.height;
    }
    return rect;
}

constexpr AnnotationRect translated(
    AnnotationRect rect,
    AnnotationPoint offset) noexcept
{
    rect.x += offset.x;
    rect.y += offset.y;
    return rect;
}

constexpr AnnotationPoint translated(
    AnnotationPoint point,
    AnnotationPoint offset) noexcept
{
    point.x += offset.x;
    point.y += offset.y;
    return point;
}

struct AnnotationColor {
    std::uint8_t red = 0;
    std::uint8_t green = 0;
    std::uint8_t blue = 0;
    std::uint8_t alpha = 255;
};

constexpr bool operator==(
    AnnotationColor left,
    AnnotationColor right) noexcept
{
    return left.red == right.red
        && left.green == right.green
        && left.blue == right.blue
        && left.alpha == right.alpha;
}

constexpr bool operator!=(
    AnnotationColor left,
    AnnotationColor right) noexcept
{
    return !(left == right);
}

enum class AnnotationStrokePattern : std::uint8_t {
    solid,
    dashLong,
    dashNarrow,
    dashLongShort,
    sketchSolid,
    sketchDashed,
};

struct AnnotationStyle {
    AnnotationColor strokeColor{245, 34, 45, 255};
    float strokeWidthDip = 3.0F;
    AnnotationStrokePattern strokePattern = AnnotationStrokePattern::solid;
    bool fillEnabled = false;
    AnnotationColor fillColor{245, 34, 45, 255};
    float cornerRadiusDip = 0.0F;
    float textSize = textDefaultSize;
    std::wstring textFontFamily = textDefaultFontFamily;
    bool textBold = false;
    bool textItalic = false;
    bool textOutlineEnabled = true;
    AnnotationColor textOutlineColor{255, 255, 255, 255};
};

constexpr bool operator==(
    const AnnotationStyle& left,
    const AnnotationStyle& right) noexcept
{
    return left.strokeColor == right.strokeColor
        && left.strokeWidthDip == right.strokeWidthDip
        && left.strokePattern == right.strokePattern
        && left.fillEnabled == right.fillEnabled
        && left.fillColor == right.fillColor
        && left.cornerRadiusDip == right.cornerRadiusDip
        && left.textSize == right.textSize
        && left.textFontFamily == right.textFontFamily
        && left.textBold == right.textBold
        && left.textItalic == right.textItalic
        && left.textOutlineEnabled == right.textOutlineEnabled
        && left.textOutlineColor == right.textOutlineColor;
}

inline bool operator!=(
    const AnnotationStyle& left,
    const AnnotationStyle& right) noexcept
{
    return !(left == right);
}

inline AnnotationStyle primaryShapeActivationStyle(
    AnnotationStyle style) noexcept
{
    style.strokeWidthDip = 4.0F;
    style.cornerRadiusDip = 5.0F;
    return style;
}

enum class AnnotationKind : std::uint8_t {
    rectangle,
    ellipse,
    arrowLine,
    brush,
    marker,
    text,
    numberSequence,
    magnifier,
    mosaicStroke,
    mosaicRectangle,
};

enum class NumberMarkType : std::uint8_t {
    number,
    check,
    cross,
};

enum class MagnifierShape : std::uint8_t {
    circle,
    rectangle,
};

struct MagnifierZoomOption {
    float value;
    std::wstring_view label;
};

inline constexpr std::array<MagnifierZoomOption, 4> magnifierZoomOptions{{
    {1.5F, L"1.5x"},
    {2.0F, L"2x"},
    {3.0F, L"3x"},
    {4.0F, L"4x"},
}};

constexpr float normalizedMagnifierZoom(float zoom) noexcept
{
    auto selected = magnifierZoomOptions[0].value;
    auto distance = zoom > selected ? zoom - selected : selected - zoom;
    for (const auto& option : magnifierZoomOptions) {
        const auto candidate = option.value;
        const auto candidateDistance = zoom > candidate
            ? zoom - candidate : candidate - zoom;
        if (candidateDistance < distance) {
            selected = candidate;
            distance = candidateDistance;
        }
    }
    return selected;
}

constexpr bool isShapeKind(AnnotationKind kind) noexcept
{
    return kind == AnnotationKind::rectangle
        || kind == AnnotationKind::ellipse;
}

enum class ArrowType : std::uint8_t {
    none,
    bar,
    dot,
    diamond,
    normal,
    solidArrow,
    hollowArrow,
};

enum class ArrowEndpoint : std::uint8_t {
    start,
    end,
};

struct ArrowLine {
    AnnotationPoint start{};
    AnnotationPoint end{};
    AnnotationPoint control{};
    ArrowType startArrowType = ArrowType::none;
    ArrowType endArrowType = ArrowType::normal;
};

struct BrushPath {
    std::vector<AnnotationPoint> points;
};

enum class MosaicRedactionType : std::uint8_t {
    gaussianBlur,
    pixelMosaic,
};

inline constexpr int mosaicMinimumRedactionValue = 5;
inline constexpr int mosaicMaximumRedactionValue = 20;

constexpr int clampedMosaicRedactionValue(int value) noexcept
{
    return value < mosaicMinimumRedactionValue
        ? mosaicMinimumRedactionValue
        : value > mosaicMaximumRedactionValue
            ? mosaicMaximumRedactionValue : value;
}

constexpr float mosaicRedactionProgress(int value) noexcept
{
    return static_cast<float>(
        clampedMosaicRedactionValue(value) - mosaicMinimumRedactionValue)
        / static_cast<float>(
            mosaicMaximumRedactionValue - mosaicMinimumRedactionValue);
}

struct MosaicRedaction {
    MosaicRedactionType type = MosaicRedactionType::pixelMosaic;
    int value = 8;
};

constexpr bool operator==(
    MosaicRedaction left,
    MosaicRedaction right) noexcept
{
    return left.type == right.type && left.value == right.value;
}

using MosaicStroke = BrushPath;

struct MarkerLine {
    AnnotationPoint start{};
    AnnotationPoint end{};
};

constexpr bool operator==(
    MarkerLine left,
    MarkerLine right) noexcept
{
    return left.start == right.start && left.end == right.end;
}

constexpr MarkerLine translated(
    MarkerLine line,
    AnnotationPoint offset) noexcept
{
    line.start = translated(line.start, offset);
    line.end = translated(line.end, offset);
    return line;
}

constexpr AnnotationRect markerLineBounds(const MarkerLine& line) noexcept
{
    return standardized({
        line.start.x,
        line.start.y,
        line.end.x - line.start.x,
        line.end.y - line.start.y,
    });
}

inline bool operator==(
    const BrushPath& left,
    const BrushPath& right) noexcept
{
    return left.points == right.points;
}

inline BrushPath translated(
    BrushPath path,
    AnnotationPoint offset)
{
    for (auto& point : path.points) {
        point = translated(point, offset);
    }
    return path;
}

inline AnnotationRect brushPathBounds(const BrushPath& path) noexcept
{
    if (path.points.empty()) {
        return {};
    }
    auto left = path.points.front().x;
    auto right = left;
    auto top = path.points.front().y;
    auto bottom = top;
    for (const auto point : path.points) {
        left = point.x < left ? point.x : left;
        right = point.x > right ? point.x : right;
        top = point.y < top ? point.y : top;
        bottom = point.y > bottom ? point.y : bottom;
    }
    return {left, top, right - left, bottom - top};
}

constexpr ArrowLine translated(
    ArrowLine line,
    AnnotationPoint offset) noexcept
{
    line.start = translated(line.start, offset);
    line.end = translated(line.end, offset);
    line.control = translated(line.control, offset);
    return line;
}

constexpr AnnotationRect arrowLineBounds(const ArrowLine& line) noexcept
{
    const auto minimum = [](float left, float right) constexpr noexcept {
        return left < right ? left : right;
    };
    const auto maximum = [](float left, float right) constexpr noexcept {
        return left > right ? left : right;
    };
    const auto left = minimum(minimum(line.start.x, line.end.x), line.control.x);
    const auto top = minimum(minimum(line.start.y, line.end.y), line.control.y);
    const auto right = maximum(maximum(line.start.x, line.end.x), line.control.x);
    const auto bottom = maximum(maximum(line.start.y, line.end.y), line.control.y);
    return {left, top, right - left, bottom - top};
}

constexpr bool operator==(
    const ArrowLine& left,
    const ArrowLine& right) noexcept
{
    return left.start == right.start
        && left.end == right.end
        && left.control == right.control
        && left.startArrowType == right.startArrowType
        && left.endArrowType == right.endArrowType;
}

constexpr bool operator!=(
    const ArrowLine& left,
    const ArrowLine& right) noexcept
{
    return !(left == right);
}

struct ShapeAnnotation {
    AnnotationId id = invalidAnnotationId;
    AnnotationKind kind = AnnotationKind::rectangle;
    AnnotationRect rect{};
    AnnotationStyle style{};
    float rotationDegrees = 0.0F;
    std::optional<ArrowLine> arrowLine;
    std::optional<BrushPath> brushPath;
    std::optional<MarkerLine> markerLine;
    std::optional<MosaicStroke> mosaicStroke;
    std::optional<MosaicRedaction> mosaicRedaction;
    std::optional<std::wstring> text;
    std::optional<NumberMarkType> numberMarkType;
    std::optional<int> numberSequenceIndex;
    bool numberSequenceIsManual = false;
    std::uint64_t numberSequenceGroupId = 0;
    std::optional<MagnifierShape> magnifierShape;
    std::optional<float> magnifierZoom;
};

constexpr bool isArrowLineAnnotation(
    const ShapeAnnotation& annotation) noexcept
{
    return annotation.kind == AnnotationKind::arrowLine
        && annotation.arrowLine.has_value();
}

constexpr bool isBrushAnnotation(
    const ShapeAnnotation& annotation) noexcept
{
    return annotation.kind == AnnotationKind::brush
        && annotation.brushPath.has_value();
}

constexpr bool isMarkerAnnotation(
    const ShapeAnnotation& annotation) noexcept
{
    return annotation.kind == AnnotationKind::marker
        && annotation.markerLine.has_value();
}

constexpr bool isMosaicStrokeAnnotation(
    const ShapeAnnotation& annotation) noexcept
{
    return annotation.kind == AnnotationKind::mosaicStroke
        && annotation.mosaicStroke.has_value()
        && annotation.mosaicRedaction.has_value();
}

constexpr bool isMosaicRectangleAnnotation(
    const ShapeAnnotation& annotation) noexcept
{
    return annotation.kind == AnnotationKind::mosaicRectangle
        && annotation.mosaicRedaction.has_value();
}

constexpr bool isMosaicAnnotation(
    const ShapeAnnotation& annotation) noexcept
{
    return isMosaicStrokeAnnotation(annotation)
        || isMosaicRectangleAnnotation(annotation);
}

inline bool isTextAnnotation(const ShapeAnnotation& annotation) noexcept
{
    return annotation.kind == AnnotationKind::text
        && annotation.text.has_value();
}

constexpr bool isMagnifierAnnotation(
    const ShapeAnnotation& annotation) noexcept
{
    return annotation.kind == AnnotationKind::magnifier
        && annotation.magnifierShape.has_value()
        && annotation.magnifierZoom.has_value();
}

constexpr bool isNumberAnnotation(
    const ShapeAnnotation& annotation) noexcept
{
    return annotation.kind == AnnotationKind::numberSequence
        && annotation.numberMarkType.has_value();
}

inline bool operator==(
    const ShapeAnnotation& left,
    const ShapeAnnotation& right) noexcept
{
    return left.id == right.id
        && left.kind == right.kind
        && left.rect == right.rect
        && left.style == right.style
        && left.rotationDegrees == right.rotationDegrees
        && left.arrowLine == right.arrowLine
        && left.brushPath == right.brushPath
        && left.markerLine == right.markerLine
        && left.mosaicStroke == right.mosaicStroke
        && left.mosaicRedaction == right.mosaicRedaction
        && left.text == right.text
        && left.numberMarkType == right.numberMarkType
        && left.numberSequenceIndex == right.numberSequenceIndex
        && left.numberSequenceIsManual == right.numberSequenceIsManual
        && left.numberSequenceGroupId == right.numberSequenceGroupId
        && left.magnifierShape == right.magnifierShape
        && left.magnifierZoom == right.magnifierZoom;
}

inline bool operator!=(
    const ShapeAnnotation& left,
    const ShapeAnnotation& right) noexcept
{
    return !(left == right);
}

inline ShapeAnnotation scaled(
    ShapeAnnotation annotation,
    float xScale,
    float yScale)
{
    const auto scalePoint = [xScale, yScale](AnnotationPoint point) {
        return AnnotationPoint{point.x * xScale, point.y * yScale};
    };
    annotation.rect = {
        annotation.rect.x * xScale,
        annotation.rect.y * yScale,
        annotation.rect.width * xScale,
        annotation.rect.height * yScale,
    };
    const auto styleScale = (xScale + yScale) / 2.0F;
    annotation.style.strokeWidthDip *= styleScale;
    annotation.style.cornerRadiusDip *= styleScale;
    annotation.style.textSize *= styleScale;
    if (annotation.arrowLine) {
        annotation.arrowLine->start = scalePoint(annotation.arrowLine->start);
        annotation.arrowLine->end = scalePoint(annotation.arrowLine->end);
        annotation.arrowLine->control = scalePoint(annotation.arrowLine->control);
    }
    if (annotation.brushPath) {
        for (auto& point : annotation.brushPath->points) {
            point = scalePoint(point);
        }
    }
    if (annotation.markerLine) {
        annotation.markerLine->start = scalePoint(annotation.markerLine->start);
        annotation.markerLine->end = scalePoint(annotation.markerLine->end);
    }
    if (annotation.mosaicStroke) {
        for (auto& point : annotation.mosaicStroke->points) {
            point = scalePoint(point);
        }
    }
    return annotation;
}

inline EraserMask scaled(EraserMask mask, float xScale, float yScale)
{
    mask.rect = {
        mask.rect.x * xScale,
        mask.rect.y * yScale,
        mask.rect.width * xScale,
        mask.rect.height * yScale,
    };
    return mask;
}

} // namespace xxsnap::win
