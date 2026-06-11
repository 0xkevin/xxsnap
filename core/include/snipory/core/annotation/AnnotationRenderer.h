#pragma once

#include "snipory/core/annotation/AnnotationDocument.h"

class QPainter;

namespace snipory::core {

class AnnotationRenderer final {
public:
    static QVector<qreal> dashPatternForStrokePattern(AnnotationStrokePattern pattern);
    static void drawShape(QPainter &painter, const ShapeAnnotation &shape);
    static void drawShapes(QPainter &painter, const QVector<ShapeAnnotation> &shapes);
};

} // namespace snipory::core
