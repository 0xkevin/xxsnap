#include "snipory/core/usecases/SnapshotExportUseCase.h"

#include "snipory/core/annotation/AnnotationRenderer.h"

#include <QPainter>

namespace snipory::core {

QImage SnapshotExportUseCase::render(
    const QImage &snapshot,
    const CaptureRegion &region,
    const QVector<ShapeAnnotation> &annotations
)
{
    if (snapshot.isNull() || !region.isValid()) {
        return {};
    }

    const QRect boundedRegion = region.devicePixelRect().intersected(snapshot.rect());
    if (!boundedRegion.isValid()) {
        return {};
    }

    QImage image = snapshot.copy(boundedRegion);
    if (!annotations.isEmpty()) {
        QPainter painter(&image);
        painter.translate(-boundedRegion.topLeft());
        AnnotationRenderer::drawShapes(painter, annotations);
    }

    return image;
}

} // namespace snipory::core
