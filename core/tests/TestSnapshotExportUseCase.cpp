#include <QtTest/QtTest>

#include "snipory/core/annotation/AnnotationDocument.h"
#include "snipory/core/capture/CaptureTypes.h"
#include "snipory/core/usecases/SnapshotExportUseCase.h"

class TestSnapshotExportUseCase final : public QObject {
    Q_OBJECT

private slots:
    void returnsEmptyImageForNullSnapshot()
    {
        const QImage result = snipory::core::SnapshotExportUseCase::render(
            QImage(),
            snipory::core::CaptureRegion::fromDevicePixels(0, 0, 5, 5),
            {}
        );

        QVERIFY(result.isNull());
    }

    void returnsEmptyImageForInvalidRegion()
    {
        QImage snapshot(QSize(40, 30), QImage::Format_ARGB32_Premultiplied);
        snapshot.fill(QColor(10, 20, 30));

        const QImage result = snipory::core::SnapshotExportUseCase::render(
            snapshot,
            snipory::core::CaptureRegion::fromDevicePixels(8, 5, 0, 6),
            {}
        );

        QVERIFY(result.isNull());
    }

    void returnsEmptyImageWhenIntersectedRegionIsOutsideSnapshot()
    {
        QImage snapshot(QSize(40, 30), QImage::Format_ARGB32_Premultiplied);
        snapshot.fill(QColor(10, 20, 30));

        const QImage result = snipory::core::SnapshotExportUseCase::render(
            snapshot,
            snipory::core::CaptureRegion::fromDevicePixels(60, 50, 7, 6),
            {}
        );

        QVERIFY(result.isNull());
    }

    void cropsRequestedDevicePixelRegion()
    {
        QImage snapshot(QSize(40, 30), QImage::Format_ARGB32_Premultiplied);
        snapshot.fill(QColor(10, 20, 30));

        for (int y = 5; y <= 10; ++y) {
            for (int x = 8; x <= 14; ++x) {
                snapshot.setPixelColor(x, y, QColor(200, 210, 220));
            }
        }

        const QImage result = snipory::core::SnapshotExportUseCase::render(
            snapshot,
            snipory::core::CaptureRegion::fromDevicePixels(8, 5, 7, 6),
            {}
        );

        QCOMPARE(result.size(), QSize(7, 6));
        QCOMPARE(result.pixelColor(0, 0), QColor(200, 210, 220));
    }

    void drawsAnnotationsUsingCropLocalCoordinates()
    {
        QImage snapshot(QSize(40, 30), QImage::Format_ARGB32_Premultiplied);
        snapshot.fill(QColor(10, 20, 30));

        snipory::core::AnnotationStyle style;
        style.strokeColor = QColor(245, 34, 45);
        style.strokeWidth = 2;

        const QImage result = snipory::core::SnapshotExportUseCase::render(
            snapshot,
            snipory::core::CaptureRegion::fromDevicePixels(8, 5, 10, 10),
            {snipory::core::ShapeAnnotation::rectangle(QRect(10, 7, 8, 8), style)}
        );

        QCOMPARE(result.size(), QSize(10, 10));
        QCOMPARE(result.pixelColor(2, 5), QColor(245, 34, 45));
        QCOMPARE(result.pixelColor(0, 0), QColor(10, 20, 30));
    }
};

QTEST_MAIN(TestSnapshotExportUseCase)
#include "TestSnapshotExportUseCase.moc"
