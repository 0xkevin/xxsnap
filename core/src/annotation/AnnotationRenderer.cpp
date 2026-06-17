#include "snipory/core/annotation/AnnotationRenderer.h"

#include <cmath>

#include <QPainter>
#include <QPainterPath>
#include <QPen>

namespace snipory::core {
namespace {

bool isSketchPattern(AnnotationStrokePattern pattern)
{
    return pattern == AnnotationStrokePattern::SketchSolid || pattern == AnnotationStrokePattern::SketchDashed;
}

QVector<QPointF> segmentPoints(const QPointF &start, const QPointF &end, qreal step, bool includeEnd)
{
    const qreal distance = std::hypot(end.x() - start.x(), end.y() - start.y());
    const int count = std::max(1, static_cast<int>(std::ceil(distance / step)));
    const int upperBound = includeEnd ? count : std::max(0, count - 1);

    QVector<QPointF> points;
    points.reserve(upperBound + 1);
    for (int index = 0; index <= upperBound; ++index) {
        const qreal t = static_cast<qreal>(index) / static_cast<qreal>(count);
        points.append(QPointF(
            start.x() + (end.x() - start.x()) * t,
            start.y() + (end.y() - start.y()) * t
        ));
    }
    return points;
}

QVector<QPointF> arcPoints(const QPointF &center, qreal radius, qreal start, qreal end)
{
    const qreal arcLength = std::abs(end - start) * radius;
    const int count = std::max(2, static_cast<int>(std::ceil(arcLength / 5.0)));

    QVector<QPointF> points;
    points.reserve(count);
    for (int index = 0; index < count; ++index) {
        const qreal t = static_cast<qreal>(index) / static_cast<qreal>(count);
        const qreal angle = start + (end - start) * t;
        points.append(QPointF(
            center.x() + std::cos(angle) * radius,
            center.y() + std::sin(angle) * radius
        ));
    }
    return points;
}

QVector<QPointF> rectanglePoints(const QRectF &rect)
{
    const QPointF topLeft(rect.left(), rect.top());
    const QPointF topRight(rect.right(), rect.top());
    const QPointF bottomRight(rect.right(), rect.bottom());
    const QPointF bottomLeft(rect.left(), rect.bottom());

    QVector<QPointF> points;
    points += segmentPoints(topLeft, topRight, 7.0, false);
    points += segmentPoints(topRight, bottomRight, 7.0, false);
    points += segmentPoints(bottomRight, bottomLeft, 7.0, false);
    points += segmentPoints(bottomLeft, topLeft, 7.0, false);
    return points;
}

QVector<QPointF> roundedRectPoints(const QRectF &rect, qreal cornerRadius)
{
    const qreal radius = std::min({cornerRadius, rect.width() / 2.0, rect.height() / 2.0});
    if (radius <= 0) {
        return rectanglePoints(rect);
    }

    QVector<QPointF> points;
    points += segmentPoints(QPointF(rect.left() + radius, rect.top()), QPointF(rect.right() - radius, rect.top()), 7.0, false);
    points += arcPoints(QPointF(rect.right() - radius, rect.top() + radius), radius, -M_PI / 2.0, 0);
    points += segmentPoints(QPointF(rect.right(), rect.top() + radius), QPointF(rect.right(), rect.bottom() - radius), 7.0, false);
    points += arcPoints(QPointF(rect.right() - radius, rect.bottom() - radius), radius, 0, M_PI / 2.0);
    points += segmentPoints(QPointF(rect.right() - radius, rect.bottom()), QPointF(rect.left() + radius, rect.bottom()), 7.0, false);
    points += arcPoints(QPointF(rect.left() + radius, rect.bottom() - radius), radius, M_PI / 2.0, M_PI);
    points += segmentPoints(QPointF(rect.left(), rect.bottom() - radius), QPointF(rect.left(), rect.top() + radius), 7.0, false);
    points += arcPoints(QPointF(rect.left() + radius, rect.top() + radius), radius, M_PI, M_PI * 1.5);
    return points;
}

QVector<QPointF> ellipsePoints(const QRectF &rect)
{
    const int count = std::max(40, static_cast<int>(std::ceil((rect.width() + rect.height()) / 3.0)));
    const QPointF center = rect.center();

    QVector<QPointF> points;
    points.reserve(count);
    for (int index = 0; index < count; ++index) {
        const qreal angle = static_cast<qreal>(index) / static_cast<qreal>(count) * M_PI * 2.0;
        points.append(QPointF(
            center.x() + std::cos(angle) * rect.width() / 2.0,
            center.y() + std::sin(angle) * rect.height() / 2.0
        ));
    }
    return points;
}

qreal noise(int index, qreal salt)
{
    const qreal raw = std::sin((static_cast<qreal>(index) + 1.0) * 12.9898 + salt * 78.233) * 43758.5453;
    return (raw - std::floor(raw)) * 2.0 - 1.0;
}

QPainterPath sketchPathForShape(const ShapeAnnotation &shape, const QRectF &rect)
{
    QVector<QPointF> points;
    if (shape.kind == ShapeAnnotationKind::Ellipse) {
        points = ellipsePoints(rect);
    } else if (shape.style.cornerRadius > 0) {
        points = roundedRectPoints(rect, shape.style.cornerRadius);
    } else {
        points = rectanglePoints(rect);
    }

    QPainterPath path;
    if (points.isEmpty()) {
        return path;
    }

    const qreal amplitude = std::min<qreal>(2.2, std::max<qreal>(0.7, shape.style.strokeWidth * 0.35));
    path.moveTo(QPointF(
        points.first().x() + noise(0, 0.19) * amplitude * 0.55,
        points.first().y() + noise(0, 0.73) * amplitude
    ));
    for (qsizetype index = 1; index < points.size(); ++index) {
        path.lineTo(QPointF(
            points.at(index).x() + noise(static_cast<int>(index), 0.19) * amplitude * 0.55,
            points.at(index).y() + noise(static_cast<int>(index), 0.73) * amplitude
        ));
    }
    path.closeSubpath();
    return path;
}

void fillShape(QPainter &painter, const ShapeAnnotation &shape, const QRect &rect)
{
    if (!shape.style.fillEnabled) {
        return;
    }

    painter.save();
    painter.setPen(Qt::NoPen);
    painter.setBrush(QBrush(shape.style.fillColor));
    if (shape.kind == ShapeAnnotationKind::Ellipse) {
        painter.drawEllipse(rect);
    } else if (shape.style.cornerRadius > 0) {
        painter.drawRoundedRect(rect, shape.style.cornerRadius, shape.style.cornerRadius);
    } else {
        painter.drawRect(rect);
    }
    painter.restore();
}

} // namespace

QVector<qreal> AnnotationRenderer::dashPatternForStrokePattern(AnnotationStrokePattern pattern)
{
    switch (pattern) {
    case AnnotationStrokePattern::DashLong:
        return {8.0, 4.0};
    case AnnotationStrokePattern::DashNarrow:
        return {4.0, 2.0};
    case AnnotationStrokePattern::DashLongShort:
        return {8.0, 3.0, 2.0, 3.0};
    case AnnotationStrokePattern::SketchDashed:
        return {8.0, 4.0};
    case AnnotationStrokePattern::SketchSolid:
    case AnnotationStrokePattern::Solid:
    default:
        return {};
    }
}

void AnnotationRenderer::drawShape(QPainter &painter, const ShapeAnnotation &shape)
{
    painter.save();
    painter.setRenderHint(QPainter::Antialiasing, true);

    QPen pen(shape.style.strokeColor, shape.style.strokeWidth);
    pen.setCosmetic(false);
    pen.setCapStyle(Qt::RoundCap);
    pen.setJoinStyle(Qt::RoundJoin);
    switch (shape.style.strokePattern) {
    case AnnotationStrokePattern::Solid:
    case AnnotationStrokePattern::SketchSolid:
        pen.setStyle(Qt::SolidLine);
        break;
    case AnnotationStrokePattern::DashLong:
    case AnnotationStrokePattern::DashNarrow:
    case AnnotationStrokePattern::DashLongShort:
    case AnnotationStrokePattern::SketchDashed:
        pen.setStyle(Qt::CustomDashLine);
        pen.setDashPattern(dashPatternForStrokePattern(shape.style.strokePattern));
        break;
    }
    painter.setPen(pen);
    painter.setBrush(shape.style.fillEnabled ? QBrush(shape.style.fillColor) : Qt::NoBrush);

    const QRect adjusted = shape.rect.adjusted(0, 0, -1, -1);
    if (isSketchPattern(shape.style.strokePattern)) {
        fillShape(painter, shape, adjusted);
        painter.setBrush(Qt::NoBrush);
        painter.drawPath(sketchPathForShape(shape, QRectF(adjusted)));
        painter.restore();
        return;
    }

    if (shape.kind == ShapeAnnotationKind::Ellipse) {
        painter.drawEllipse(adjusted);
    } else if (shape.style.cornerRadius > 0) {
        painter.drawRoundedRect(adjusted, shape.style.cornerRadius, shape.style.cornerRadius);
    } else {
        painter.drawRect(adjusted);
    }

    painter.restore();
}

void AnnotationRenderer::drawShapes(QPainter &painter, const QVector<ShapeAnnotation> &shapes)
{
    for (const ShapeAnnotation &shape : shapes) {
        drawShape(painter, shape);
    }
}

} // namespace snipory::core
