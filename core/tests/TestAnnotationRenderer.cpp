#include <QtTest/QtTest>

#include <QPainter>

#include "snipory/core/annotation/AnnotationDocument.h"
#include "snipory/core/annotation/AnnotationRenderer.h"

class TestAnnotationRenderer final : public QObject {
    Q_OBJECT

private slots:
    void rendersRectangleStrokeOntoImage()
    {
        QImage image(QSize(40, 40), QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);

        snipory::core::AnnotationStyle style;
        style.strokeColor = QColor(245, 34, 45);
        style.strokeWidth = 2;

        QPainter painter(&image);
        snipory::core::AnnotationRenderer::drawShape(
            painter,
            snipory::core::ShapeAnnotation::rectangle(QRect(10, 10, 20, 20), style)
        );
        painter.end();

        QCOMPARE(image.pixelColor(10, 15), QColor(245, 34, 45));
        QCOMPARE(image.pixelColor(20, 20), QColor(Qt::transparent));
    }

    void rendersEllipseStrokeOntoImage()
    {
        QImage image(QSize(40, 40), QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);

        snipory::core::AnnotationStyle style;
        style.strokeColor = QColor(0, 142, 255);
        style.strokeWidth = 2;

        QPainter painter(&image);
        snipory::core::AnnotationRenderer::drawShape(
            painter,
            snipory::core::ShapeAnnotation::ellipse(QRect(10, 10, 20, 20), style)
        );
        painter.end();

        QCOMPARE(image.pixelColor(20, 10), QColor(0, 142, 255));
        QCOMPARE(image.pixelColor(20, 20), QColor(Qt::transparent));
    }

    void rendersFilledRectangleUsingSelectedColor()
    {
        QImage image(QSize(40, 40), QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);

        snipory::core::AnnotationStyle style;
        style.strokeColor = QColor(245, 34, 45);
        style.strokeWidth = 3;
        style.fillEnabled = true;
        style.fillColor = QColor(245, 34, 45);

        QPainter painter(&image);
        snipory::core::AnnotationRenderer::drawShape(
            painter,
            snipory::core::ShapeAnnotation::rectangle(QRect(10, 10, 20, 20), style)
        );
        painter.end();

        QCOMPARE(image.pixelColor(20, 20), QColor(245, 34, 45));
    }

    void rendersRoundedRectangleWithoutPaintingSquareCorner()
    {
        QImage image(QSize(50, 50), QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);

        snipory::core::AnnotationStyle style;
        style.strokeColor = QColor(0, 142, 255);
        style.strokeWidth = 2;
        style.fillEnabled = true;
        style.fillColor = QColor(0, 142, 255);
        style.cornerRadius = 8;

        QPainter painter(&image);
        snipory::core::AnnotationRenderer::drawShape(
            painter,
            snipory::core::ShapeAnnotation::rectangle(QRect(10, 10, 30, 30), style)
        );
        painter.end();

        QCOMPARE(image.pixelColor(10, 10), QColor(Qt::transparent));
        QCOMPARE(image.pixelColor(25, 25), QColor(0, 142, 255));
    }

    void dashPatternPresetsStayCompact()
    {
        QCOMPARE(snipory::core::AnnotationRenderer::dashPatternForStrokePattern(snipory::core::AnnotationStrokePattern::Solid), QVector<qreal>({}));
        QCOMPARE(snipory::core::AnnotationRenderer::dashPatternForStrokePattern(snipory::core::AnnotationStrokePattern::DashLong), QVector<qreal>({8.0, 4.0}));
        QCOMPARE(snipory::core::AnnotationRenderer::dashPatternForStrokePattern(snipory::core::AnnotationStrokePattern::DashNarrow), QVector<qreal>({4.0, 2.0}));
        QCOMPARE(snipory::core::AnnotationRenderer::dashPatternForStrokePattern(snipory::core::AnnotationStrokePattern::DashLongShort), QVector<qreal>({8.0, 3.0, 2.0, 3.0}));
    }
};

QTEST_MAIN(TestAnnotationRenderer)
#include "TestAnnotationRenderer.moc"
