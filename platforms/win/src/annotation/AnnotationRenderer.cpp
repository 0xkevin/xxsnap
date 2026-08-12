#include "annotation/AnnotationRenderer.h"
#include "annotation/AnnotationGeometry.h"
#include "annotation/MarkerMetrics.h"
#include "annotation/ArrowLineRenderer.h"
#include "annotation/BrushRenderer.h"
#include "annotation/MarkerRenderer.h"
#include "annotation/NumberAnnotationRenderer.h"
#include "annotation/TextAnnotationRenderer.h"

#include <d2d1helper.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <utility>

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

constexpr float pi = 3.14159265358979323846F;
constexpr float degreesToRadians = pi / 180.0F;

constexpr float minimum(float left, float right) noexcept
{
    return left < right ? left : right;
}

constexpr float maximum(float left, float right) noexcept
{
    return left > right ? left : right;
}

constexpr float absoluteValue(float value) noexcept
{
    return value < 0.0F ? -value : value;
}

float normalizedRadians(float radians) noexcept
{
    while (radians > pi) {
        radians -= 2.0F * pi;
    }
    while (radians < -pi) {
        radians += 2.0F * pi;
    }
    return radians;
}

float approximateSine(float radians) noexcept
{
    const auto value = normalizedRadians(radians);
    const auto square = value * value;
    return value * (1.0F
        - square / 6.0F
        + square * square / 120.0F
        - square * square * square / 5040.0F
        + square * square * square * square / 362880.0F);
}

float approximateCosine(float radians) noexcept
{
    const auto value = normalizedRadians(radians);
    const auto square = value * value;
    return 1.0F
        - square / 2.0F
        + square * square / 24.0F
        - square * square * square / 720.0F
        + square * square * square * square / 40320.0F;
}

AnnotationPoint rotatedPoint(
    AnnotationPoint point,
    AnnotationRect rect,
    float rotationDegrees) noexcept
{
    if (rotationDegrees == 0.0F) {
        return point;
    }
    rect = standardized(rect);
    const AnnotationPoint center{
        rect.x + rect.width / 2.0F,
        rect.y + rect.height / 2.0F,
    };
    const auto radians = rotationDegrees * degreesToRadians;
    const auto sine = approximateSine(radians);
    const auto cosine = approximateCosine(radians);
    const auto dx = point.x - center.x;
    const auto dy = point.y - center.y;
    return {
        center.x + dx * cosine - dy * sine,
        center.y + dx * sine + dy * cosine,
    };
}

std::array<AnnotationPoint, 8> resizeHandlePoints(
    const ShapeAnnotation& annotation) noexcept
{
    const auto rect = standardized(annotation.rect);
    const auto centerX = rect.x + rect.width / 2.0F;
    const auto centerY = rect.y + rect.height / 2.0F;
    std::array points{
        AnnotationPoint{rect.x, rect.y},
        AnnotationPoint{centerX, rect.y},
        AnnotationPoint{rect.x + rect.width, rect.y},
        AnnotationPoint{rect.x, centerY},
        AnnotationPoint{rect.x + rect.width, centerY},
        AnnotationPoint{rect.x, rect.y + rect.height},
        AnnotationPoint{centerX, rect.y + rect.height},
        AnnotationPoint{rect.x + rect.width, rect.y + rect.height},
    };
    for (auto& point : points) {
        point = rotatedPoint(point, rect, annotation.rotationDegrees);
    }
    return points;
}

D2D1_COLOR_F d2dColor(AnnotationColor value) noexcept
{
    return D2D1::ColorF(
        static_cast<float>(value.red) / 255.0F,
        static_cast<float>(value.green) / 255.0F,
        static_cast<float>(value.blue) / 255.0F,
        static_cast<float>(value.alpha) / 255.0F);
}

D2D1_RECT_F d2dRect(AnnotationRect rect) noexcept
{
    return D2D1::RectF(
        rect.x,
        rect.y,
        rect.x + rect.width,
        rect.y + rect.height);
}

AnnotationRect strokeInsetRect(const ShapeAnnotation& annotation) noexcept
{
    auto rect = standardized(annotation.rect);
    const auto inset = maximum(0.0F, annotation.style.strokeWidthDip) / 2.0F;
    rect.x += inset;
    rect.y += inset;
    rect.width = maximum(0.0F, rect.width - inset * 2.0F);
    rect.height = maximum(0.0F, rect.height - inset * 2.0F);
    return rect;
}

bool isSketch(AnnotationStrokePattern pattern) noexcept
{
    return pattern == AnnotationStrokePattern::sketchSolid
        || pattern == AnnotationStrokePattern::sketchDashed;
}

std::uint32_t nextNoise(std::uint32_t value) noexcept
{
    value ^= value << 13U;
    value ^= value >> 17U;
    value ^= value << 5U;
    return value;
}

float noise(std::size_t index, std::uint32_t salt) noexcept
{
    auto value = static_cast<std::uint32_t>(index + 1U) * 0x9E3779B9U + salt;
    value = nextNoise(value);
    return static_cast<float>(value & 0xFFFFU) / 32767.5F - 1.0F;
}

std::size_t roundedUpCount(float value, float step) noexcept
{
    if (value <= 0.0F || step <= 0.0F) {
        return 1U;
    }
    const auto truncated = static_cast<std::size_t>(value / step);
    if (truncated == 0U) {
        return 1U;
    }
    return static_cast<float>(truncated) * step < value
        ? truncated + 1U
        : truncated;
}

void appendSegment(
    std::vector<AnnotationPoint>& points,
    AnnotationPoint start,
    AnnotationPoint end,
    bool includeEnd) noexcept
{
    const auto dx = end.x - start.x;
    const auto dy = end.y - start.y;
    const auto approximateDistance = maximum(absoluteValue(dx), absoluteValue(dy));
    const auto count = roundedUpCount(approximateDistance, 7.0F);
    const auto upper = includeEnd ? count : count - 1U;
    for (std::size_t index = 0; index <= upper; ++index) {
        const auto progress = static_cast<float>(index) / static_cast<float>(count);
        points.push_back({
            start.x + dx * progress,
            start.y + dy * progress,
        });
    }
}

std::vector<AnnotationPoint> sketchPoints(
    const ShapeAnnotation& annotation) noexcept
{
    const auto rect = strokeInsetRect(annotation);
    std::vector<AnnotationPoint> points;
    if (rect.width <= 0.0F || rect.height <= 0.0F) {
        return points;
    }

    if (annotation.kind == AnnotationKind::ellipse) {
        const auto count = static_cast<std::size_t>((std::max)(
            40.0F, (rect.width + rect.height) / 3.0F));
        const AnnotationPoint center{
            rect.x + rect.width / 2.0F,
            rect.y + rect.height / 2.0F,
        };
        points.reserve(count);
        for (std::size_t index = 0; index < count; ++index) {
            const auto angle = static_cast<float>(index)
                / static_cast<float>(count) * 2.0F * pi;
            points.push_back({
                center.x + approximateCosine(angle) * rect.width / 2.0F,
                center.y + approximateSine(angle) * rect.height / 2.0F,
            });
        }
    } else {
        appendSegment(
            points,
            {rect.x, rect.y},
            {rect.x + rect.width, rect.y},
            false);
        appendSegment(
            points,
            {rect.x + rect.width, rect.y},
            {rect.x + rect.width, rect.y + rect.height},
            false);
        appendSegment(
            points,
            {rect.x + rect.width, rect.y + rect.height},
            {rect.x, rect.y + rect.height},
            false);
        appendSegment(
            points,
            {rect.x, rect.y + rect.height},
            {rect.x, rect.y},
            false);
    }

    const auto amplitude = minimum(
        2.2F,
        maximum(0.7F, annotation.style.strokeWidthDip * 0.35F));
    for (std::size_t index = 0; index < points.size(); ++index) {
        points[index].x += noise(index, 19U) * amplitude * 0.55F;
        points[index].y += noise(index, 73U) * amplitude;
    }
    return points;
}

HRESULT createSketchGeometry(
    ID2D1Factory* factory,
    const ShapeAnnotation& annotation,
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
    const auto points = sketchPoints(annotation);
    if (!points.empty()) {
        sink->BeginFigure(
            D2D1::Point2F(points.front().x, points.front().y),
            D2D1_FIGURE_BEGIN_HOLLOW);
        for (std::size_t index = 1; index < points.size(); ++index) {
            sink->AddLine(D2D1::Point2F(points[index].x, points[index].y));
        }
        sink->EndFigure(D2D1_FIGURE_END_CLOSED);
    }
    result = sink->Close();
    if (FAILED(result)) {
        return result;
    }
    *destination = geometry.get();
    (*destination)->AddRef();
    return S_OK;
}

HRESULT createStrokeStyle(
    ID2D1Factory* factory,
    const AnnotationStyle& style,
    ID2D1StrokeStyle** destination) noexcept
{
    if (factory == nullptr || destination == nullptr) {
        return E_INVALIDARG;
    }
    const auto normalizedDashes = normalizedStrokeDashPattern(
        style.strokePattern,
        style.strokeWidthDip);
    const D2D1_STROKE_STYLE_PROPERTIES properties{
        D2D1_CAP_STYLE_ROUND,
        D2D1_CAP_STYLE_ROUND,
        D2D1_CAP_STYLE_ROUND,
        D2D1_LINE_JOIN_ROUND,
        10.0F,
        normalizedDashes.empty()
            ? D2D1_DASH_STYLE_SOLID
            : D2D1_DASH_STYLE_CUSTOM,
        0.0F,
    };
    return factory->CreateStrokeStyle(
        properties,
        normalizedDashes.empty() ? nullptr : normalizedDashes.data(),
        static_cast<UINT32>(normalizedDashes.size()),
        destination);
}

} // namespace

AnnotationRenderPlan buildAnnotationRenderPlan(
    const AnnotationDocument& document,
    const std::optional<ShapeAnnotation>& preview,
    AnnotationPoint selectionOriginDip,
    bool showEditingAffordances,
    std::optional<AnnotationEditingState> editingState)
{
    AnnotationRenderPlan plan;
    plan.items.reserve(document.annotations().size() + (preview.has_value() ? 1U : 0U));
    for (const auto& source : document.annotations()) {
        if (preview.has_value()
            && preview->id != invalidAnnotationId
            && source.id == preview->id) {
            continue;
        }
        auto annotation = source;
        annotation.rect.x += selectionOriginDip.x;
        annotation.rect.y += selectionOriginDip.y;
        if (annotation.arrowLine.has_value()) {
            annotation.arrowLine = translated(
                *annotation.arrowLine, selectionOriginDip);
        }
        if (annotation.brushPath.has_value()) {
            annotation.brushPath = translated(
                *annotation.brushPath, selectionOriginDip);
        }
        if (annotation.markerLine.has_value()) {
            annotation.markerLine = translated(
                *annotation.markerLine, selectionOriginDip);
        }
        if (annotation.mosaicStroke.has_value()) {
            annotation.mosaicStroke = translated(
                *annotation.mosaicStroke, selectionOriginDip);
        }
        plan.items.push_back({annotation, false, std::nullopt});
    }
    if (preview.has_value()) {
        auto annotation = *preview;
        annotation.rect.x += selectionOriginDip.x;
        annotation.rect.y += selectionOriginDip.y;
        if (annotation.arrowLine.has_value()) {
            annotation.arrowLine = translated(
                *annotation.arrowLine, selectionOriginDip);
        }
        if (annotation.brushPath.has_value()) {
            annotation.brushPath = translated(
                *annotation.brushPath, selectionOriginDip);
        }
        if (annotation.markerLine.has_value()) {
            annotation.markerLine = translated(
                *annotation.markerLine, selectionOriginDip);
        }
        if (annotation.mosaicStroke.has_value()) {
            annotation.mosaicStroke = translated(
                *annotation.mosaicStroke, selectionOriginDip);
        }
        plan.items.push_back({annotation, true, std::nullopt});
    }

    if (!showEditingAffordances) {
        return plan;
    }
    const ShapeAnnotation* editing = nullptr;
    if (preview.has_value()
        && preview->id != invalidAnnotationId
        && !plan.items.empty()) {
        editing = &plan.items.back().annotation;
    }
    if (const auto selected = document.selectedId(); selected.has_value()) {
        if (editing == nullptr) {
            for (const auto& item : plan.items) {
                if (!item.isPreview && item.annotation.id == *selected) {
                    editing = &item.annotation;
                    break;
                }
            }
        }
    }
    if (editing == nullptr && preview.has_value() && !plan.items.empty()) {
        editing = &plan.items.back().annotation;
    }
    if (editing == nullptr) {
        return plan;
    }

    if (editingState.has_value() && editingState->draftText.has_value()) {
        for (auto& item : plan.items) {
            if (item.annotation.id == editingState->id
                && isNumberAnnotation(item.annotation)) {
                item.numberDraft = editingState->draftText;
                break;
            }
        }
    }

    if (editingState.has_value() && editing->id == editingState->id
        && isTextAnnotation(*editing)) {
        plan.textCaret = textCaretRect(
            *editing, editingState->caretPosition);
        const auto rect = standardized(editing->rect);
        plan.textCaretRotationDegrees = editing->rotationDegrees;
        plan.textCaretRotationCenter = AnnotationPoint{
            rect.x + rect.width / 2.0F,
            rect.y + rect.height / 2.0F,
        };
    }

    if (isNumberAnnotation(*editing)) {
        plan.numberOutline = numberOutlineRect(editing->rect);
        for (const auto kind : {
                NumberHandleKind::deleteHandle,
                NumberHandleKind::resize,
                NumberHandleKind::increment,
                NumberHandleKind::decrement,
                NumberHandleKind::reset}) {
            if (const auto rect = numberHandleRect(*editing, kind)) {
                plan.numberHandles.push_back({kind, *rect});
            }
        }
        const auto value = editing->numberSequenceIndex.value_or(1);
        const auto manual = std::any_of(document.annotations().begin(),
            document.annotations().end(), [&](const auto& annotation) {
                return isNumberAnnotation(annotation)
                    && annotation.numberMarkType == NumberMarkType::number
                    && annotation.numberSequenceGroupId
                        == editing->numberSequenceGroupId
                    && annotation.numberSequenceIsManual;
            });
        const auto adjacentExists = [&](int candidate) {
            return std::any_of(document.annotations().begin(),
                document.annotations().end(), [&](const auto& annotation) {
                    return annotation.id != editing->id
                        && isNumberAnnotation(annotation)
                        && annotation.numberMarkType == NumberMarkType::number
                        && annotation.numberSequenceGroupId
                            == editing->numberSequenceGroupId
                        && annotation.numberSequenceIndex == candidate;
                });
        };
        plan.numberIncrementEnabled = value < numberMaximumValue
            && (manual || adjacentExists(value + 1));
        plan.numberDecrementEnabled = value > numberMinimumValue
            && (manual || adjacentExists(value - 1));
        if (editingState.has_value()
            && editing->id == editingState->id) {
            plan.numberCaret = numberCaretRect(
                *editing, editingState->caretPosition,
                editingState->draftText);
        }
        return plan;
    }

    if (editing->arrowLine.has_value()) {
        plan.lineHandles = {
            editing->arrowLine->start,
            editing->arrowLine->end,
            editing->arrowLine->control,
        };
        return plan;
    }
    if (editing->brushPath.has_value()) {
        if (editing->id == invalidAnnotationId) {
            return plan;
        }
        const auto& points = editing->brushPath->points;
        if (points.size() >= 2U) {
            const auto insetEndpoint = [](AnnotationPoint endpoint,
                                           AnnotationPoint neighbour) {
                constexpr float inset = 9.0F;
                const auto dx = neighbour.x - endpoint.x;
                const auto dy = neighbour.y - endpoint.y;
                const auto length = static_cast<float>(std::hypot(dx, dy));
                if (length <= 0.001F) {
                    return endpoint;
                }
                const auto distance = minimum(inset, length / 2.0F);
                return AnnotationPoint{
                    endpoint.x + dx / length * distance,
                    endpoint.y + dy / length * distance,
                };
            };
            plan.lineHandles = {
                insetEndpoint(points[0], points[1]),
                insetEndpoint(points.back(), points[points.size() - 2U]),
            };
        }
        return plan;
    }
    if (editing->markerLine.has_value()) {
        if (editing->id == invalidAnnotationId) {
            return plan;
        }
        const auto line = *editing->markerLine;
        if (annotationDistanceSquared(line.start, line.end)
            >= markerMetrics::dotThresholdDip
                * markerMetrics::dotThresholdDip) {
            plan.lineHandles = {
                insetAnnotationEndpoint(
                    line.start, line.end, markerMetrics::endpointInsetDip),
                insetAnnotationEndpoint(
                    line.end, line.start, markerMetrics::endpointInsetDip),
            };
        }
        return plan;
    }
    if (editing->mosaicStroke.has_value()) {
        return plan;
    }

    const auto handles = resizeHandlePoints(*editing);
    if (isTextAnnotation(*editing)) {
        plan.resizeHandles.reserve(handles.size() - 1U);
        for (std::size_t index = 0; index < handles.size(); ++index) {
            if (index == 2U) {
                plan.textDeleteHandle = handles[index];
            } else {
                plan.resizeHandles.push_back(handles[index]);
            }
        }
    } else {
        plan.resizeHandles.assign(handles.begin(), handles.end());
    }
    if (isMagnifierAnnotation(*editing)) {
        return plan;
    }
    const auto rect = standardized(editing->rect);
    const AnnotationPoint rotation{
        rect.x + rect.width / 2.0F,
        rect.y - 14.0F,
    };
    plan.rotationHandle = rotatedPoint(
        rotation, rect, editing->rotationDegrees);
    return plan;
}

std::vector<float> strokeDashPattern(
    AnnotationStrokePattern pattern,
    float strokeWidthDip)
{
    const auto width = maximum(strokeWidthDip, 1.0F);
    const auto longDash = maximum(8.0F, width * 3.0F);
    const auto gap = maximum(4.0F, width * 1.6F);
    const auto dotGap = maximum(5.0F, width * 2.2F);
    switch (pattern) {
    case AnnotationStrokePattern::solid:
    case AnnotationStrokePattern::sketchSolid:
        return {};
    case AnnotationStrokePattern::dashLong:
    case AnnotationStrokePattern::sketchDashed:
        return {longDash, gap};
    case AnnotationStrokePattern::dashNarrow:
        return {0.1F, dotGap};
    case AnnotationStrokePattern::dashLongShort:
        return {longDash, gap, 0.1F, gap};
    }
    return {};
}

std::vector<float> normalizedStrokeDashPattern(
    AnnotationStrokePattern pattern,
    float strokeWidthDip)
{
    const auto absoluteDashes = strokeDashPattern(pattern, strokeWidthDip);
    const auto divisor = maximum(1.0F, strokeWidthDip);
    std::vector<float> normalizedDashes;
    normalizedDashes.reserve(absoluteDashes.size());
    for (const auto dash : absoluteDashes) {
        normalizedDashes.push_back(dash / divisor);
    }
    return normalizedDashes;
}

std::vector<AnnotationPoint> sketchStrokeSamplePoints(
    AnnotationPoint start,
    AnnotationPoint end,
    float lineWidthDip)
{
    const auto dx = static_cast<double>(end.x - start.x);
    const auto dy = static_cast<double>(end.y - start.y);
    const auto count = (std::max)(
        1,
        static_cast<int>(std::ceil(std::hypot(dx, dy) / 7.0)));
    const auto amplitude = (std::min)(
        2.2,
        (std::max)(0.7, static_cast<double>(lineWidthDip) * 0.35));
    const auto noise = [](int index, double salt) {
        const auto raw = std::sin(
            (static_cast<double>(index) + 1.0) * 12.9898
            + salt * 78.233) * 43758.5453;
        return (raw - std::floor(raw)) * 2.0 - 1.0;
    };

    std::vector<AnnotationPoint> points;
    points.reserve(static_cast<std::size_t>(count + 1));
    for (int index = 0; index <= count; ++index) {
        const auto progress = static_cast<double>(index)
            / static_cast<double>(count);
        points.push_back({
            static_cast<float>(
                static_cast<double>(start.x) + dx * progress
                + noise(index, 0.19) * amplitude * 0.55),
            static_cast<float>(
                static_cast<double>(start.y) + dy * progress
                + noise(index, 0.73) * amplitude),
        });
    }
    return points;
}

AnnotationRenderer::AnnotationRenderer(ID2D1Factory* factory) noexcept
    : factory_(factory)
{
    if (factory_ != nullptr) {
        factory_->AddRef();
    }
    DWriteCreateFactory(
        DWRITE_FACTORY_TYPE_SHARED,
        __uuidof(IDWriteFactory),
        reinterpret_cast<IUnknown**>(&dwriteFactory_));
}

AnnotationRenderer::~AnnotationRenderer()
{
    if (factory_ != nullptr) {
        factory_->Release();
    }
    if (dwriteFactory_ != nullptr) {
        dwriteFactory_->Release();
    }
}

HRESULT AnnotationRenderer::draw(
    ID2D1RenderTarget* renderTarget,
    const AnnotationRenderPlan& plan) const noexcept
{
    if (renderTarget == nullptr || factory_ == nullptr) {
        return E_INVALIDARG;
    }

    for (const auto& item : plan.items) {
        const auto& annotation = item.annotation;
        if (annotation.kind == AnnotationKind::arrowLine
            && annotation.arrowLine.has_value()) {
            const auto result = drawArrowLine(
                factory_, renderTarget, annotation);
            if (FAILED(result)) {
                return result;
            }
            continue;
        }
        if (annotation.kind == AnnotationKind::brush
            && annotation.brushPath.has_value()) {
            const auto result = drawBrushPath(
                factory_, renderTarget, annotation);
            if (FAILED(result)) {
                return result;
            }
            continue;
        }
        if (annotation.kind == AnnotationKind::marker
            && annotation.markerLine.has_value()) {
            const auto result = drawMarkerLine(renderTarget, annotation);
            if (FAILED(result)) {
                return result;
            }
            continue;
        }
        if (isTextAnnotation(annotation)) {
            if (dwriteFactory_ == nullptr) {
                return E_FAIL;
            }
            D2D1_MATRIX_3X2_F previousTransform{};
            renderTarget->GetTransform(&previousTransform);
            const auto fullRect = standardized(annotation.rect);
            if (annotation.rotationDegrees != 0.0F) {
                const auto center = D2D1::Point2F(
                    fullRect.x + fullRect.width / 2.0F,
                    fullRect.y + fullRect.height / 2.0F);
                renderTarget->SetTransform(
                    D2D1::Matrix3x2F::Rotation(
                        annotation.rotationDegrees, center)
                    * previousTransform);
            }
            const auto result = drawTextAnnotation(
                factory_, dwriteFactory_, renderTarget, annotation);
            renderTarget->SetTransform(previousTransform);
            if (FAILED(result)) {
                return result;
            }
            continue;
        }
        if (isNumberAnnotation(annotation)) {
            if (dwriteFactory_ == nullptr) {
                return E_FAIL;
            }
            const auto result = drawNumberAnnotation(
                dwriteFactory_, renderTarget, annotation, item.numberDraft);
            if (FAILED(result)) {
                return result;
            }
            continue;
        }
        if (isMagnifierAnnotation(annotation)) {
            const auto rect = strokeInsetRect(annotation);
            if (rect.width <= 0.0F || rect.height <= 0.0F
                || annotation.style.strokeWidthDip <= 0.0F) {
                continue;
            }
            ComPtr<ID2D1SolidColorBrush> strokeBrush;
            const auto result = renderTarget->CreateSolidColorBrush(
                d2dColor(annotation.style.strokeColor),
                strokeBrush.put());
            if (FAILED(result)) {
                return result;
            }
            if (*annotation.magnifierShape == MagnifierShape::circle) {
                const auto ellipse = D2D1::Ellipse(
                    D2D1::Point2F(
                        rect.x + rect.width / 2.0F,
                        rect.y + rect.height / 2.0F),
                    rect.width / 2.0F,
                    rect.height / 2.0F);
                renderTarget->DrawEllipse(&ellipse, strokeBrush.get(),
                    annotation.style.strokeWidthDip);
            } else {
                renderTarget->DrawRectangle(d2dRect(rect), strokeBrush.get(),
                    annotation.style.strokeWidthDip);
            }
            continue;
        }
        if (!isShapeKind(annotation.kind)) {
            continue;
        }
        const auto rect = strokeInsetRect(annotation);
        if (rect.width <= 0.0F || rect.height <= 0.0F) {
            continue;
        }

        ComPtr<ID2D1SolidColorBrush> strokeBrush;
        auto result = renderTarget->CreateSolidColorBrush(
            d2dColor(annotation.style.strokeColor),
            strokeBrush.put());
        if (FAILED(result)) {
            return result;
        }
        ComPtr<ID2D1SolidColorBrush> fillBrush;
        if (annotation.style.fillEnabled) {
            result = renderTarget->CreateSolidColorBrush(
                d2dColor(annotation.style.fillColor),
                fillBrush.put());
            if (FAILED(result)) {
                return result;
            }
        }
        ComPtr<ID2D1StrokeStyle> strokeStyle;
        result = createStrokeStyle(
            factory_, annotation.style, strokeStyle.put());
        if (FAILED(result)) {
            return result;
        }

        D2D1_MATRIX_3X2_F previousTransform{};
        renderTarget->GetTransform(&previousTransform);
        const auto fullRect = standardized(annotation.rect);
        if (annotation.rotationDegrees != 0.0F) {
            const auto center = D2D1::Point2F(
                fullRect.x + fullRect.width / 2.0F,
                fullRect.y + fullRect.height / 2.0F);
            renderTarget->SetTransform(
                D2D1::Matrix3x2F::Rotation(
                    annotation.rotationDegrees, center)
                * previousTransform);
        }

        const auto radius = minimum(
            maximum(0.0F, annotation.style.cornerRadiusDip),
            minimum(rect.width, rect.height) / 2.0F);
        if (annotation.kind == AnnotationKind::ellipse) {
            const auto ellipse = D2D1::Ellipse(
                D2D1::Point2F(
                    rect.x + rect.width / 2.0F,
                    rect.y + rect.height / 2.0F),
                rect.width / 2.0F,
                rect.height / 2.0F);
            if (annotation.style.fillEnabled) {
                renderTarget->FillEllipse(&ellipse, fillBrush.get());
            }
            if (!isSketch(annotation.style.strokePattern)) {
                renderTarget->DrawEllipse(
                    &ellipse,
                    strokeBrush.get(),
                    annotation.style.strokeWidthDip,
                    strokeStyle.get());
            }
        } else {
            const auto rounded = D2D1::RoundedRect(
                d2dRect(rect), radius, radius);
            if (annotation.style.fillEnabled) {
                renderTarget->FillRoundedRectangle(&rounded, fillBrush.get());
            }
            if (!isSketch(annotation.style.strokePattern)) {
                renderTarget->DrawRoundedRectangle(
                    &rounded,
                    strokeBrush.get(),
                    annotation.style.strokeWidthDip,
                    strokeStyle.get());
            }
        }

        if (isSketch(annotation.style.strokePattern)) {
            ComPtr<ID2D1PathGeometry> geometry;
            result = createSketchGeometry(
                factory_, annotation, geometry.put());
            if (FAILED(result)) {
                renderTarget->SetTransform(previousTransform);
                return result;
            }
            renderTarget->DrawGeometry(
                geometry.get(),
                strokeBrush.get(),
                annotation.style.strokeWidthDip,
                strokeStyle.get());
        }
        renderTarget->SetTransform(previousTransform);
    }

    if (!plan.resizeHandles.empty() || !plan.lineHandles.empty()) {
        ComPtr<ID2D1SolidColorBrush> blueBrush;
        auto result = renderTarget->CreateSolidColorBrush(
            D2D1::ColorF(0.0F, 122.0F / 255.0F, 1.0F, 1.0F),
            blueBrush.put());
        if (FAILED(result)) {
            return result;
        }
        ComPtr<ID2D1SolidColorBrush> whiteBrush;
        result = renderTarget->CreateSolidColorBrush(
            D2D1::ColorF(D2D1::ColorF::White),
            whiteBrush.put());
        if (FAILED(result)) {
            return result;
        }
        const auto drawHandle = [renderTarget, &blueBrush, &whiteBrush](
                                    AnnotationPoint point) {
            const auto ellipse = D2D1::Ellipse(
                D2D1::Point2F(point.x, point.y), 3.0F, 3.0F);
            renderTarget->FillEllipse(&ellipse, blueBrush.get());
            renderTarget->DrawEllipse(&ellipse, whiteBrush.get(), 1.0F);
        };
        for (const auto point : plan.resizeHandles) {
            drawHandle(point);
        }
        for (const auto point : plan.lineHandles) {
            drawHandle(point);
        }
    }
    if (plan.textCaret.has_value()) {
        ComPtr<ID2D1SolidColorBrush> whiteBrush;
        auto result = renderTarget->CreateSolidColorBrush(
            D2D1::ColorF(1.0F, 1.0F, 1.0F, 0.95F), whiteBrush.put());
        if (FAILED(result)) return result;
        ComPtr<ID2D1SolidColorBrush> blackBrush;
        result = renderTarget->CreateSolidColorBrush(
            D2D1::ColorF(0.0F, 0.0F, 0.0F, 0.9F), blackBrush.put());
        if (FAILED(result)) return result;
        const auto caret = *plan.textCaret;
        const auto x = caret.x + caret.width / 2.0F;
        D2D1_MATRIX_3X2_F previousTransform{};
        renderTarget->GetTransform(&previousTransform);
        if (plan.textCaretRotationCenter.has_value()
            && plan.textCaretRotationDegrees != 0.0F) {
            renderTarget->SetTransform(
                D2D1::Matrix3x2F::Rotation(
                    plan.textCaretRotationDegrees,
                    D2D1::Point2F(
                        plan.textCaretRotationCenter->x,
                        plan.textCaretRotationCenter->y))
                * previousTransform);
        }
        renderTarget->DrawLine(
            D2D1::Point2F(x, caret.y),
            D2D1::Point2F(x, caret.y + caret.height),
            whiteBrush.get(), 3.0F);
        renderTarget->DrawLine(
            D2D1::Point2F(x, caret.y),
            D2D1::Point2F(x, caret.y + caret.height),
            blackBrush.get(), 1.0F);
        renderTarget->SetTransform(previousTransform);
    }
    if (plan.textDeleteHandle.has_value()) {
        ComPtr<ID2D1SolidColorBrush> blueBrush;
        auto result = renderTarget->CreateSolidColorBrush(
            D2D1::ColorF(0.0F, 0.48F, 1.0F, 1.0F), blueBrush.put());
        if (FAILED(result)) return result;
        ComPtr<ID2D1SolidColorBrush> whiteBrush;
        result = renderTarget->CreateSolidColorBrush(
            D2D1::ColorF(D2D1::ColorF::White), whiteBrush.put());
        if (FAILED(result)) return result;
        const auto point = *plan.textDeleteHandle;
        const auto circle = D2D1::Ellipse(
            D2D1::Point2F(point.x, point.y), 7.0F, 7.0F);
        renderTarget->FillEllipse(&circle, blueBrush.get());
        renderTarget->DrawLine(
            D2D1::Point2F(point.x - 3.0F, point.y - 3.0F),
            D2D1::Point2F(point.x + 3.0F, point.y + 3.0F),
            whiteBrush.get(), 1.6F);
        renderTarget->DrawLine(
            D2D1::Point2F(point.x - 3.0F, point.y + 3.0F),
            D2D1::Point2F(point.x + 3.0F, point.y - 3.0F),
            whiteBrush.get(), 1.6F);
    }
    if (plan.numberOutline.has_value()) {
        ComPtr<ID2D1SolidColorBrush> blueBrush;
        auto result = renderTarget->CreateSolidColorBrush(
            D2D1::ColorF(0.0F, 0.48F, 1.0F, 1.0F), blueBrush.put());
        if (FAILED(result)) return result;
        ComPtr<ID2D1SolidColorBrush> whiteBrush;
        result = renderTarget->CreateSolidColorBrush(
            D2D1::ColorF(D2D1::ColorF::White), whiteBrush.put());
        if (FAILED(result)) return result;
        ComPtr<ID2D1SolidColorBrush> disabledBrush;
        result = renderTarget->CreateSolidColorBrush(
            D2D1::ColorF(0.55F, 0.55F, 0.55F, 1.0F), disabledBrush.put());
        if (FAILED(result)) return result;
        const D2D1_STROKE_STYLE_PROPERTIES dashProperties{
            D2D1_CAP_STYLE_FLAT, D2D1_CAP_STYLE_FLAT,
            D2D1_CAP_STYLE_FLAT, D2D1_LINE_JOIN_MITER, 10.0F,
            D2D1_DASH_STYLE_DASH, 0.0F};
        ComPtr<ID2D1StrokeStyle> dashed;
        result = factory_->CreateStrokeStyle(
            dashProperties, nullptr, 0U, dashed.put());
        if (FAILED(result)) return result;
        renderTarget->DrawRectangle(
            d2dRect(*plan.numberOutline), blueBrush.get(), 1.5F,
            dashed.get());
        for (const auto& [kind, rect] : plan.numberHandles) {
            const auto enabled = kind == NumberHandleKind::increment
                ? plan.numberIncrementEnabled
                : kind == NumberHandleKind::decrement
                    ? plan.numberDecrementEnabled : true;
            auto* foreground = enabled ? blueBrush.get() : disabledBrush.get();
            const auto center = D2D1::Point2F(
                rect.x + rect.width / 2.0F,
                rect.y + rect.height / 2.0F);
            if (kind == NumberHandleKind::deleteHandle) {
                const auto circle = D2D1::Ellipse(center,
                    rect.width / 2.0F, rect.height / 2.0F);
                renderTarget->FillEllipse(&circle, whiteBrush.get());
                const auto inner = D2D1::Ellipse(center,
                    rect.width / 2.0F - 1.0F,
                    rect.height / 2.0F - 1.0F);
                renderTarget->FillEllipse(&inner, foreground);
                renderTarget->DrawLine(
                    {center.x - 3.0F, center.y - 3.0F},
                    {center.x + 3.0F, center.y + 3.0F},
                    whiteBrush.get(), 1.6F);
                renderTarget->DrawLine(
                    {center.x - 3.0F, center.y + 3.0F},
                    {center.x + 3.0F, center.y - 3.0F},
                    whiteBrush.get(), 1.6F);
            } else if (kind == NumberHandleKind::resize) {
                const auto circle = D2D1::Ellipse(center,
                    rect.width / 2.0F, rect.height / 2.0F);
                renderTarget->FillEllipse(&circle, whiteBrush.get());
                const auto inner = D2D1::Ellipse(center,
                    rect.width / 2.0F - 1.2F,
                    rect.height / 2.0F - 1.2F);
                renderTarget->FillEllipse(&inner, foreground);
            } else if (kind == NumberHandleKind::reset) {
                const auto circle = D2D1::Ellipse(center,
                    rect.width / 2.0F, rect.height / 2.0F);
                renderTarget->FillEllipse(&circle, whiteBrush.get());
                const auto inner = D2D1::Ellipse(center,
                    rect.width / 2.0F - 1.2F,
                    rect.height / 2.0F - 1.2F);
                renderTarget->FillEllipse(&inner, foreground);
                constexpr std::array<AnnotationPoint, 6> resetArc{
                    AnnotationPoint{-2.8F, 1.0F},
                    AnnotationPoint{-3.0F, -0.6F},
                    AnnotationPoint{-2.0F, -2.2F},
                    AnnotationPoint{-0.2F, -3.0F},
                    AnnotationPoint{1.8F, -2.4F},
                    AnnotationPoint{2.8F, -0.8F},
                };
                for (std::size_t index = 1U;
                     index < resetArc.size(); ++index) {
                    renderTarget->DrawLine(
                        {center.x + resetArc[index - 1U].x,
                            center.y + resetArc[index - 1U].y},
                        {center.x + resetArc[index].x,
                            center.y + resetArc[index].y},
                        whiteBrush.get(), 1.5F);
                }
                renderTarget->DrawLine(
                    {center.x - 2.5F, center.y + 1.5F},
                    {center.x + 2.5F, center.y + 1.5F},
                    whiteBrush.get(), 1.5F);
                renderTarget->DrawLine(
                    {center.x - 2.5F, center.y + 1.5F},
                    {center.x - 1.0F, center.y - 1.0F},
                    whiteBrush.get(), 1.5F);
            } else {
                renderTarget->FillRectangle(d2dRect(rect), whiteBrush.get());
                renderTarget->DrawRectangle(
                    d2dRect({rect.x + 1.0F, rect.y + 1.0F,
                        rect.width - 2.0F, rect.height - 2.0F}),
                    foreground, 1.2F);
                renderTarget->DrawLine(
                    {center.x - 2.0F, center.y},
                    {center.x + 2.0F, center.y}, foreground, 1.4F);
                if (kind == NumberHandleKind::increment) {
                    renderTarget->DrawLine(
                        {center.x, center.y - 2.0F},
                        {center.x, center.y + 2.0F}, foreground, 1.4F);
                }
            }
        }
    }
    if (plan.numberCaret.has_value()) {
        ComPtr<ID2D1SolidColorBrush> blackBrush;
        const auto result = renderTarget->CreateSolidColorBrush(
            D2D1::ColorF(0.0F, 0.0F, 0.0F, 1.0F), blackBrush.put());
        if (FAILED(result)) return result;
        const auto caret = *plan.numberCaret;
        renderTarget->FillRectangle(d2dRect(caret), blackBrush.get());
    }
    return S_OK;
}

} // namespace xxsnap::win
