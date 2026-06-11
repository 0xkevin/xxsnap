#include "snipory/core/annotation/AnnotationRenderer.h"

#include <QPainter>
#include <QPen>

namespace snipory::core {

QVector<qreal> AnnotationRenderer::dashPatternForStrokePattern(AnnotationStrokePattern pattern)
{
    switch (pattern) {
    case AnnotationStrokePattern::DashLong:
        return {8.0, 4.0};
    case AnnotationStrokePattern::DashNarrow:
        return {4.0, 2.0};
    case AnnotationStrokePattern::DashLongShort:
        return {8.0, 3.0, 2.0, 3.0};
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
        pen.setStyle(Qt::SolidLine);
        break;
    case AnnotationStrokePattern::DashLong:
    case AnnotationStrokePattern::DashNarrow:
    case AnnotationStrokePattern::DashLongShort:
        pen.setStyle(Qt::CustomDashLine);
        pen.setDashPattern(dashPatternForStrokePattern(shape.style.strokePattern));
        break;
    }
    painter.setPen(pen);
    painter.setBrush(shape.style.fillEnabled ? QBrush(shape.style.fillColor) : Qt::NoBrush);

    const QRect adjusted = shape.rect.adjusted(0, 0, -1, -1);
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
