#include "annotation/ArrowLineRenderer.h"

#include "annotation/AnnotationRenderer.h"

#include <d2d1helper.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <utility>
#include <vector>

namespace xxsnap::win {
namespace {

template<typename Interface>
class ComPtr final {
public:
    ComPtr() noexcept = default;
    ~ComPtr() { reset(); }

    ComPtr(const ComPtr&) = delete;
    ComPtr& operator=(const ComPtr&) = delete;

    Interface* get() const noexcept { return value_; }
    Interface* operator->() const noexcept { return value_; }

    Interface** put() noexcept
    {
        reset();
        return &value_;
    }

    void reset() noexcept
    {
        if (value_ != nullptr) {
            std::exchange(value_, nullptr)->Release();
        }
    }

private:
    Interface* value_ = nullptr;
};

constexpr float minimum(float left, float right) noexcept
{
    return left < right ? left : right;
}

constexpr float maximum(float left, float right) noexcept
{
    return left > right ? left : right;
}

bool isSketch(AnnotationStrokePattern pattern) noexcept
{
    return pattern == AnnotationStrokePattern::sketchSolid
        || pattern == AnnotationStrokePattern::sketchDashed;
}

bool isVectorArrow(ArrowType type) noexcept
{
    return type == ArrowType::solidArrow || type == ArrowType::hollowArrow;
}

D2D1_COLOR_F d2dColor(AnnotationColor value) noexcept
{
    return D2D1::ColorF(
        static_cast<float>(value.red) / 255.0F,
        static_cast<float>(value.green) / 255.0F,
        static_cast<float>(value.blue) / 255.0F,
        static_cast<float>(value.alpha) / 255.0F);
}

AnnotationPoint unitDirection(
    AnnotationPoint from,
    AnnotationPoint to) noexcept
{
    const auto dx = to.x - from.x;
    const auto dy = to.y - from.y;
    const auto length = static_cast<float>(std::hypot(
        static_cast<double>(dx), static_cast<double>(dy)));
    if (length <= 0.001F) {
        return {1.0F, 0.0F};
    }
    return {dx / length, dy / length};
}

AnnotationPoint quadraticPoint(const ArrowLine& line, float progress) noexcept
{
    const auto remaining = 1.0F - progress;
    return {
        remaining * remaining * line.start.x
            + 2.0F * remaining * progress * line.control.x
            + progress * progress * line.end.x,
        remaining * remaining * line.start.y
            + 2.0F * remaining * progress * line.control.y
            + progress * progress * line.end.y,
    };
}

struct CurveFrame {
    AnnotationPoint point{};
    AnnotationPoint tangent{};
    float distance = 0.0F;
};

std::vector<CurveFrame> sampledCurveFrames(const ArrowLine& line)
{
    const auto chord = static_cast<float>(std::hypot(
        static_cast<double>(line.end.x - line.start.x),
        static_cast<double>(line.end.y - line.start.y)));
    const auto controlSpan = static_cast<float>(std::hypot(
        static_cast<double>(line.control.x - line.start.x),
        static_cast<double>(line.control.y - line.start.y)))
        + static_cast<float>(std::hypot(
            static_cast<double>(line.end.x - line.control.x),
            static_cast<double>(line.end.y - line.control.y)));
    const auto steps = (std::max)(
        32, static_cast<int>(std::ceil((std::max)(chord, controlSpan) / 3.0F)));
    std::vector<CurveFrame> frames;
    frames.reserve(static_cast<std::size_t>(steps + 1));
    auto previous = line.start;
    auto distance = 0.0F;
    for (int index = 0; index <= steps; ++index) {
        const auto progress = static_cast<float>(index)
            / static_cast<float>(steps);
        const auto point = quadraticPoint(line, progress);
        if (index > 0) {
            distance += static_cast<float>(std::hypot(
                static_cast<double>(point.x - previous.x),
                static_cast<double>(point.y - previous.y)));
        }
        const AnnotationPoint derivative{
            2.0F * (1.0F - progress) * (line.control.x - line.start.x)
                + 2.0F * progress * (line.end.x - line.control.x),
            2.0F * (1.0F - progress) * (line.control.y - line.start.y)
                + 2.0F * progress * (line.end.y - line.control.y),
        };
        frames.push_back({point, unitDirection({}, derivative), distance});
        previous = point;
    }
    return frames;
}

CurveFrame interpolatedFrame(
    const std::vector<CurveFrame>& frames,
    float targetDistance) noexcept
{
    if (frames.empty()) {
        return {};
    }
    if (targetDistance <= 0.0F) {
        return frames.front();
    }
    if (targetDistance >= frames.back().distance) {
        return frames.back();
    }
    for (std::size_t index = 1; index < frames.size(); ++index) {
        if (frames[index].distance < targetDistance) {
            continue;
        }
        const auto& previous = frames[index - 1U];
        const auto& current = frames[index];
        const auto span = maximum(0.001F, current.distance - previous.distance);
        const auto progress = (targetDistance - previous.distance) / span;
        const AnnotationPoint tangent{
            previous.tangent.x
                + (current.tangent.x - previous.tangent.x) * progress,
            previous.tangent.y
                + (current.tangent.y - previous.tangent.y) * progress,
        };
        return {
            {
                previous.point.x + (current.point.x - previous.point.x) * progress,
                previous.point.y + (current.point.y - previous.point.y) * progress,
            },
            unitDirection({}, tangent),
            targetDistance,
        };
    }
    return frames.back();
}

AnnotationPoint curveEdgePoint(
    const CurveFrame& frame,
    float offset) noexcept
{
    return {
        frame.point.x - frame.tangent.y * offset,
        frame.point.y + frame.tangent.x * offset,
    };
}

struct ArrowTemplatePoint {
    float x = 0.0F;
    float y = 0.0F;
};

constexpr float arrowTemplateTipX = 20.0F;
constexpr float arrowTemplateTailX = 4.0F;
constexpr float arrowTemplateAxisY = 12.0457356F;
constexpr std::array arrowTemplate{
    ArrowTemplatePoint{12.979733F, 14.0133576F},
    ArrowTemplatePoint{11.9712417F, 16.0147138F},
    ArrowTemplatePoint{20.0F, 12.0457356F},
    ArrowTemplatePoint{11.9712417F, 8.01471379F},
    ArrowTemplatePoint{12.979733F, 10.0250492F},
    ArrowTemplatePoint{4.0F, 12.0457356F},
};

AnnotationPoint stretchedTemplatePoint(
    ArrowTemplatePoint point,
    const std::vector<CurveFrame>& frames,
    float totalDistance,
    float scale) noexcept
{
    const auto distanceFromEnd = minimum(
        totalDistance, (arrowTemplateTipX - point.x) * scale);
    const auto frame = interpolatedFrame(
        frames, maximum(0.0F, totalDistance - distanceFromEnd));
    return curveEdgePoint(
        frame, (point.y - arrowTemplateAxisY) * scale);
}

std::vector<AnnotationPoint> sampledTemplateBodyEdge(
    ArrowTemplatePoint bodyPoint,
    const std::vector<CurveFrame>& frames,
    float totalDistance,
    float scale)
{
    const auto distanceFromEnd = minimum(
        totalDistance, (arrowTemplateTipX - bodyPoint.x) * scale);
    const auto bodyDistance = maximum(0.0F, totalDistance - distanceFromEnd);
    const auto count = (std::max)(
        12, static_cast<int>(std::ceil(bodyDistance / 6.0F)));
    std::vector<AnnotationPoint> points;
    points.reserve(static_cast<std::size_t>(count + 1));
    for (int index = 0; index <= count; ++index) {
        const auto progress = static_cast<float>(index)
            / static_cast<float>(count);
        const auto frame = interpolatedFrame(
            frames, bodyDistance * progress);
        const auto templateY = arrowTemplateAxisY
            + (bodyPoint.y - arrowTemplateAxisY) * progress;
        points.push_back(curveEdgePoint(
            frame, (templateY - arrowTemplateAxisY) * scale));
    }
    return points;
}

HRESULT createFilledPolygon(
    ID2D1Factory* factory,
    const AnnotationPoint* points,
    std::size_t count,
    ID2D1PathGeometry** destination) noexcept;

HRESULT createStrokeStyle(
    ID2D1Factory* factory,
    const AnnotationStyle& style,
    ID2D1StrokeStyle** destination) noexcept
{
    if (factory == nullptr || destination == nullptr) {
        return E_INVALIDARG;
    }
    const auto dashes = normalizedStrokeDashPattern(
        style.strokePattern, style.strokeWidthDip);
    const D2D1_STROKE_STYLE_PROPERTIES properties{
        D2D1_CAP_STYLE_ROUND,
        D2D1_CAP_STYLE_ROUND,
        D2D1_CAP_STYLE_ROUND,
        D2D1_LINE_JOIN_ROUND,
        10.0F,
        dashes.empty() ? D2D1_DASH_STYLE_SOLID : D2D1_DASH_STYLE_CUSTOM,
        0.0F,
    };
    return factory->CreateStrokeStyle(
        properties,
        dashes.empty() ? nullptr : dashes.data(),
        static_cast<UINT32>(dashes.size()),
        destination);
}

double sketchNoise(std::size_t index, double salt) noexcept
{
    const auto raw = std::sin(
        (static_cast<double>(index) + 1.0) * 12.9898
        + salt * 78.233) * 43758.5453;
    return (raw - std::floor(raw)) * 2.0 - 1.0;
}

std::vector<AnnotationPoint> sketchQuadraticPoints(
    const ArrowLine& line,
    float lineWidthDip)
{
    const auto approximateLength = std::hypot(
        static_cast<double>(line.control.x - line.start.x),
        static_cast<double>(line.control.y - line.start.y))
        + std::hypot(
            static_cast<double>(line.end.x - line.control.x),
            static_cast<double>(line.end.y - line.control.y));
    const auto count = (std::max)(
        2, static_cast<int>(std::ceil(approximateLength / 7.0)));
    const auto amplitude = (std::min)(
        2.2, (std::max)(0.7, static_cast<double>(lineWidthDip) * 0.35));
    std::vector<AnnotationPoint> points;
    points.reserve(static_cast<std::size_t>(count + 1));
    for (int index = 0; index <= count; ++index) {
        auto point = quadraticPoint(
            line, static_cast<float>(index) / static_cast<float>(count));
        point.x += static_cast<float>(
            sketchNoise(static_cast<std::size_t>(index), 0.19)
            * amplitude * 0.55);
        point.y += static_cast<float>(
            sketchNoise(static_cast<std::size_t>(index), 0.73)
            * amplitude);
        points.push_back(point);
    }
    return points;
}

HRESULT createLineGeometry(
    ID2D1Factory* factory,
    const ArrowLine& line,
    bool sketch,
    float lineWidthDip,
    ID2D1PathGeometry** destination) noexcept
{
    if (factory == nullptr || destination == nullptr) {
        return E_INVALIDARG;
    }
    ComPtr<ID2D1PathGeometry> geometry;
    auto result = factory->CreatePathGeometry(geometry.put());
    if (FAILED(result)) {
        return result;
    }
    ComPtr<ID2D1GeometrySink> sink;
    result = geometry->Open(sink.put());
    if (FAILED(result)) {
        return result;
    }
    if (sketch) {
        const auto points = sketchQuadraticPoints(line, lineWidthDip);
        if (!points.empty()) {
            sink->BeginFigure(
                D2D1::Point2F(points.front().x, points.front().y),
                D2D1_FIGURE_BEGIN_HOLLOW);
            for (std::size_t index = 1; index < points.size(); ++index) {
                sink->AddLine(D2D1::Point2F(points[index].x, points[index].y));
            }
            sink->EndFigure(D2D1_FIGURE_END_OPEN);
        }
    } else {
        sink->BeginFigure(
            D2D1::Point2F(line.start.x, line.start.y),
            D2D1_FIGURE_BEGIN_HOLLOW);
        sink->AddQuadraticBezier(D2D1::QuadraticBezierSegment(
            D2D1::Point2F(line.control.x, line.control.y),
            D2D1::Point2F(line.end.x, line.end.y)));
        sink->EndFigure(D2D1_FIGURE_END_OPEN);
    }
    result = sink->Close();
    if (FAILED(result)) {
        return result;
    }
    *destination = geometry.get();
    (*destination)->AddRef();
    return S_OK;
}

HRESULT createSpecialArrowGeometry(
    ID2D1Factory* factory,
    const ArrowLine& source,
    bool pointsAtStart,
    float strokeWidth,
    ID2D1PathGeometry** destination) noexcept
{
    if (factory == nullptr || destination == nullptr) {
        return E_INVALIDARG;
    }
    auto line = source;
    if (pointsAtStart) {
        std::swap(line.start, line.end);
    }
    const auto frames = sampledCurveFrames(line);
    if (frames.empty() || frames.back().distance <= 0.001F) {
        return E_INVALIDARG;
    }
    const auto totalDistance = frames.back().distance;
    const auto scale = minimum(
        maximum(0.8F, strokeWidth / 2.0F),
        maximum(0.2F,
            totalDistance / (arrowTemplateTipX - arrowTemplateTailX)));
    const auto upper = sampledTemplateBodyEdge(
        arrowTemplate[0], frames, totalDistance, scale);
    const auto lower = sampledTemplateBodyEdge(
        arrowTemplate[4], frames, totalDistance, scale);
    if (upper.empty() || lower.empty()) {
        return E_INVALIDARG;
    }

    ComPtr<ID2D1PathGeometry> geometry;
    auto result = factory->CreatePathGeometry(geometry.put());
    if (FAILED(result)) {
        return result;
    }
    ComPtr<ID2D1GeometrySink> sink;
    result = geometry->Open(sink.put());
    if (FAILED(result)) {
        return result;
    }
    sink->BeginFigure(
        D2D1::Point2F(upper.front().x, upper.front().y),
        D2D1_FIGURE_BEGIN_FILLED);
    for (std::size_t index = 1; index < upper.size(); ++index) {
        sink->AddLine(D2D1::Point2F(upper[index].x, upper[index].y));
    }
    for (const auto index : {1U, 2U, 3U}) {
        const auto point = stretchedTemplatePoint(
            arrowTemplate[index], frames, totalDistance, scale);
        sink->AddLine(D2D1::Point2F(point.x, point.y));
    }
    for (auto iterator = lower.rbegin(); iterator != lower.rend(); ++iterator) {
        sink->AddLine(D2D1::Point2F(iterator->x, iterator->y));
    }
    sink->EndFigure(D2D1_FIGURE_END_CLOSED);
    result = sink->Close();
    if (FAILED(result)) {
        return result;
    }
    *destination = geometry.get();
    (*destination)->AddRef();
    return S_OK;
}

HRESULT createWidenedGeometry(
    ID2D1Factory* factory,
    ID2D1Geometry* source,
    float width,
    ID2D1PathGeometry** destination) noexcept
{
    if (factory == nullptr || source == nullptr || destination == nullptr) {
        return E_INVALIDARG;
    }
    ComPtr<ID2D1PathGeometry> geometry;
    auto result = factory->CreatePathGeometry(geometry.put());
    if (FAILED(result)) {
        return result;
    }
    ComPtr<ID2D1GeometrySink> sink;
    result = geometry->Open(sink.put());
    if (FAILED(result)) {
        return result;
    }
    result = source->Widen(
        maximum(1.0F, width),
        nullptr,
        nullptr,
        D2D1_DEFAULT_FLATTENING_TOLERANCE,
        sink.get());
    if (FAILED(result)) {
        return result;
    }
    result = sink->Close();
    if (FAILED(result)) {
        return result;
    }
    *destination = geometry.get();
    (*destination)->AddRef();
    return S_OK;
}

HRESULT createSpecialTailCapGeometry(
    ID2D1Factory* factory,
    const ArrowLine& source,
    bool pointsAtStart,
    float strokeWidth,
    ID2D1PathGeometry** destination) noexcept
{
    auto line = source;
    if (pointsAtStart) {
        std::swap(line.start, line.end);
    }
    const auto frames = sampledCurveFrames(line);
    if (factory == nullptr || destination == nullptr
        || frames.empty() || frames.back().distance <= 0.001F) {
        return E_INVALIDARG;
    }
    const auto totalDistance = frames.back().distance;
    const auto scale = minimum(
        maximum(0.8F, strokeWidth / 2.0F),
        maximum(0.2F,
            totalDistance / (arrowTemplateTipX - arrowTemplateTailX)));
    constexpr float capX = 5.2F;
    const auto ratio = (capX - arrowTemplateTailX)
        / (arrowTemplate[0].x - arrowTemplateTailX);
    const ArrowTemplatePoint upper{
        capX,
        arrowTemplateAxisY
            + (arrowTemplate[0].y - arrowTemplateAxisY) * ratio,
    };
    const ArrowTemplatePoint lower{
        capX,
        arrowTemplateAxisY
            + (arrowTemplate[4].y - arrowTemplateAxisY) * ratio,
    };
    const std::array points{
        stretchedTemplatePoint(upper, frames, totalDistance, scale),
        stretchedTemplatePoint(arrowTemplate[5], frames, totalDistance, scale),
        stretchedTemplatePoint(lower, frames, totalDistance, scale),
    };
    return createFilledPolygon(
        factory, points.data(), points.size(), destination);
}

HRESULT createFilledPolygon(
    ID2D1Factory* factory,
    const AnnotationPoint* points,
    std::size_t count,
    ID2D1PathGeometry** destination) noexcept
{
    if (factory == nullptr || points == nullptr || count < 3U
        || destination == nullptr) {
        return E_INVALIDARG;
    }
    ComPtr<ID2D1PathGeometry> geometry;
    auto result = factory->CreatePathGeometry(geometry.put());
    if (FAILED(result)) {
        return result;
    }
    ComPtr<ID2D1GeometrySink> sink;
    result = geometry->Open(sink.put());
    if (FAILED(result)) {
        return result;
    }
    sink->BeginFigure(
        D2D1::Point2F(points[0].x, points[0].y),
        D2D1_FIGURE_BEGIN_FILLED);
    for (std::size_t index = 1; index < count; ++index) {
        sink->AddLine(D2D1::Point2F(points[index].x, points[index].y));
    }
    sink->EndFigure(D2D1_FIGURE_END_CLOSED);
    result = sink->Close();
    if (FAILED(result)) {
        return result;
    }
    *destination = geometry.get();
    (*destination)->AddRef();
    return S_OK;
}

void drawArrowHead(
    ID2D1Factory* factory,
    ID2D1RenderTarget* target,
    AnnotationPoint tip,
    AnnotationPoint towardBody,
    ArrowType type,
    float width,
    ID2D1SolidColorBrush* brush) noexcept
{
    if (type == ArrowType::none || factory == nullptr
        || target == nullptr || brush == nullptr) {
        return;
    }
    const auto axis = unitDirection(tip, towardBody);
    const AnnotationPoint normal{-axis.y, axis.x};
    const auto add = [](AnnotationPoint origin, AnnotationPoint first,
                        float firstScale, AnnotationPoint second,
                        float secondScale) noexcept {
        return AnnotationPoint{
            origin.x + first.x * firstScale + second.x * secondScale,
            origin.y + first.y * firstScale + second.y * secondScale,
        };
    };
    if (type == ArrowType::dot) {
        const auto radius = maximum(3.5F, width * 1.45F);
        const auto ellipse = D2D1::Ellipse(
            D2D1::Point2F(tip.x, tip.y), radius, radius);
        target->FillEllipse(&ellipse, brush);
        return;
    }
    if (type == ArrowType::bar) {
        const auto half = maximum(5.0F, width * 2.1F);
        const auto first = add(tip, normal, -half, axis, 0.0F);
        const auto second = add(tip, normal, half, axis, 0.0F);
        target->DrawLine(
            D2D1::Point2F(first.x, first.y),
            D2D1::Point2F(second.x, second.y), brush, maximum(1.5F, width));
        return;
    }

    if (type == ArrowType::diamond) {
        const auto length = maximum(10.0F, width * 3.3F);
        const auto half = maximum(4.0F, width * 1.5F);
        const auto center = add(tip, axis, length * 0.5F, normal, 0.0F);
        const std::array points{
            tip,
            add(center, normal, half, axis, 0.0F),
            add(tip, axis, length, normal, 0.0F),
            add(center, normal, -half, axis, 0.0F),
        };
        ComPtr<ID2D1PathGeometry> geometry;
        if (SUCCEEDED(createFilledPolygon(
                factory, points.data(), points.size(), geometry.put()))) {
            target->FillGeometry(geometry.get(), brush);
        }
        return;
    }

    if (type == ArrowType::normal) {
        constexpr std::array<std::array<float, 2>, 7> templatePoints{{
            {{12.0F, 8.0F}},
            {{20.0F, 12.0F}},
            {{12.0F, 16.0F}},
            {{13.4784F, 13.0F}},
            {{11.45F, 13.0F}},
            {{11.45F, 11.0F}},
            {{13.4784F, 11.0F}},
        }};
        const auto scale = maximum(0.8F, width / 2.0F);
        std::array<AnnotationPoint, templatePoints.size()> points{};
        for (std::size_t index = 0; index < templatePoints.size(); ++index) {
            points[index] = add(
                tip,
                axis,
                (20.0F - templatePoints[index][0]) * scale,
                normal,
                -(templatePoints[index][1] - 12.0F) * scale);
        }
        ComPtr<ID2D1PathGeometry> geometry;
        if (SUCCEEDED(createFilledPolygon(
                factory, points.data(), points.size(), geometry.put()))) {
            target->FillGeometry(geometry.get(), brush);
        }
    }
}

ArrowLine trimmedNormalBody(const ArrowLine& line, float width)
{
    auto body = line;
    const auto frames = sampledCurveFrames(line);
    if (frames.empty()) {
        return body;
    }
    const auto scale = maximum(0.8F, width / 2.0F);
    const auto inset = minimum(
        maximum(18.0F, width * 4.6F) * 0.62F,
        (20.0F - 11.45F) * scale);
    if (line.startArrowType == ArrowType::normal) {
        body.start = interpolatedFrame(frames, inset).point;
    }
    if (line.endArrowType == ArrowType::normal) {
        body.end = interpolatedFrame(
            frames, maximum(0.0F, frames.back().distance - inset)).point;
    }
    return body;
}

} // namespace

HRESULT drawArrowLine(
    ID2D1Factory* factory,
    ID2D1RenderTarget* renderTarget,
    const ShapeAnnotation& annotation) noexcept
{
    if (factory == nullptr || renderTarget == nullptr
        || !isArrowLineAnnotation(annotation)) {
        return E_INVALIDARG;
    }
    ComPtr<ID2D1SolidColorBrush> brush;
    auto result = renderTarget->CreateSolidColorBrush(
        d2dColor(annotation.style.strokeColor), brush.put());
    if (FAILED(result)) {
        return result;
    }
    const auto& line = *annotation.arrowLine;
    const auto vectorAtStart = isVectorArrow(line.startArrowType);
    const auto vectorAtEnd = isVectorArrow(line.endArrowType);
    if (vectorAtStart || vectorAtEnd) {
        const auto type = vectorAtStart
            ? line.startArrowType
            : line.endArrowType;
        ComPtr<ID2D1PathGeometry> geometry;
        result = createSpecialArrowGeometry(
            factory, line, vectorAtStart,
            annotation.style.strokeWidthDip, geometry.put());
        if (FAILED(result)) {
            return result;
        }
        if (type == ArrowType::solidArrow) {
            renderTarget->FillGeometry(geometry.get(), brush.get());
        } else {
            ComPtr<ID2D1PathGeometry> outline;
            result = createWidenedGeometry(
                factory,
                geometry.get(),
                annotation.style.strokeWidthDip * 0.5F,
                outline.put());
            if (FAILED(result)) {
                return result;
            }
            renderTarget->FillGeometry(outline.get(), brush.get());
            ComPtr<ID2D1PathGeometry> tailCap;
            result = createSpecialTailCapGeometry(
                factory,
                line,
                vectorAtStart,
                annotation.style.strokeWidthDip,
                tailCap.put());
            if (FAILED(result)) {
                return result;
            }
            renderTarget->FillGeometry(tailCap.get(), brush.get());
        }
        return S_OK;
    }

    ComPtr<ID2D1StrokeStyle> strokeStyle;
    result = createStrokeStyle(factory, annotation.style, strokeStyle.put());
    if (FAILED(result)) {
        return result;
    }
    const auto body = trimmedNormalBody(line, annotation.style.strokeWidthDip);
    ComPtr<ID2D1PathGeometry> geometry;
    result = createLineGeometry(
        factory,
        body,
        isSketch(annotation.style.strokePattern),
        annotation.style.strokeWidthDip,
        geometry.put());
    if (FAILED(result)) {
        return result;
    }
    renderTarget->DrawGeometry(
        geometry.get(), brush.get(), annotation.style.strokeWidthDip,
        strokeStyle.get());
    drawArrowHead(factory, renderTarget, line.start, line.control,
        line.startArrowType, annotation.style.strokeWidthDip, brush.get());
    drawArrowHead(factory, renderTarget, line.end, line.control,
        line.endArrowType, annotation.style.strokeWidthDip, brush.get());
    return S_OK;
}

} // namespace xxsnap::win
