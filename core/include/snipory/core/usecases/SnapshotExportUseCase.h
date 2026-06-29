#pragma once

#include "snipory/core/annotation/AnnotationDocument.h"
#include "snipory/core/capture/CaptureTypes.h"

namespace snipory::core {

class SnapshotExportUseCase final {
public:
    static QImage render(
        const QImage &snapshot,
        const CaptureRegion &region,
        const QVector<ShapeAnnotation> &annotations
    );
};

} // namespace snipory::core
