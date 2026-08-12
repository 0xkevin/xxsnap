#pragma once

#include <cstdint>
#include <optional>

namespace xxsnap::win {

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
        && left.cornerRadiusDip == right.cornerRadiusDip;
}

constexpr bool operator!=(
    const AnnotationStyle& left,
    const AnnotationStyle& right) noexcept
{
    return !(left == right);
}

constexpr AnnotationStyle primaryShapeActivationStyle(
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
};

constexpr bool isArrowLineAnnotation(
    const ShapeAnnotation& annotation) noexcept
{
    return annotation.kind == AnnotationKind::arrowLine
        && annotation.arrowLine.has_value();
}

constexpr bool operator==(
    const ShapeAnnotation& left,
    const ShapeAnnotation& right) noexcept
{
    return left.id == right.id
        && left.kind == right.kind
        && left.rect == right.rect
        && left.style == right.style
        && left.rotationDegrees == right.rotationDegrees
        && left.arrowLine == right.arrowLine;
}

} // namespace xxsnap::win
