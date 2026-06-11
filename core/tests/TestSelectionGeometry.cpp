#include <QtTest/QtTest>

#include "snipory/core/selection/SelectionGeometry.h"

class TestSelectionGeometry final : public QObject {
    Q_OBJECT

private slots:
    void logicalRectConvertsToDevicePixels()
    {
        const snipory::core::CaptureRegion region =
            snipory::core::SelectionGeometry::captureRegionFromLocalLogicalRect(QRect(10, 20, 30, 40), 2.0);

        QCOMPARE(region.devicePixelRect(), QRect(20, 40, 60, 80));
    }

    void shapeOptionsToolbarUsesCurrentCompactDimensions()
    {
        const QRect toolbar(100, 100, 180, 30);
        const QRect screen(0, 0, 900, 700);

        const QRect options = snipory::core::SelectionGeometry::shapeOptionsToolbarRectForToolbar(toolbar, screen);

        QCOMPARE(options.size(), QSize(630, 30));
        QCOMPARE(options.top(), toolbar.bottom() + 9);
    }

    void shapeColorSwatchesUseSmallNormalRectsWithVisibleGaps()
    {
        const QRect options(20, 40, 630, 30);
        const QVector<QRect> swatches = snipory::core::SelectionGeometry::shapeColorSwatchRects(options, 20);

        QCOMPARE(swatches.at(0), QRect(321, 49, 12, 12));
        QCOMPARE(swatches.at(1), QRect(337, 49, 12, 12));
        QCOMPARE(swatches.at(19), QRect(625, 49, 12, 12));
        QCOMPARE(swatches.at(1).left() - swatches.at(0).right() - 1, 4);
    }

    void shapeRectangleDropdownKeepsArrowInsideSelectedBackgroundButSeparatedFromIcon()
    {
        const QRect options(20, 40, 630, 30);
        const QRect button = snipory::core::SelectionGeometry::shapeRectangleModeButtonRect(options);
        const QRect background = snipory::core::SelectionGeometry::shapeModeButtonBackgroundRect(button);
        const QRect icon = snipory::core::SelectionGeometry::shapeRectangleIconRect(button);
        const QRect arrow = snipory::core::SelectionGeometry::shapeRectangleArrowButtonRect(button);

        QCOMPARE(button, QRect(138, 44, 26, 22));
        QCOMPARE(background.size(), QSize(30, 26));
        QCOMPARE(icon.size(), QSize(11, 9));
        QCOMPARE(arrow.size(), QSize(7, 5));
        QVERIFY(background.contains(arrow));
        QCOMPARE(arrow.left() - icon.right() - 1, 3);
    }

    void cornerRadiusPanelKeepsValueBoxCompactAndSliderClear()
    {
        const QRect options(20, 40, 630, 30);
        const QRect button = snipory::core::SelectionGeometry::shapeRectangleModeButtonRect(options);
        const QRect panel = snipory::core::SelectionGeometry::shapeCornerRadiusPanelRect(options, button);
        const QRect value = snipory::core::SelectionGeometry::shapeCornerRadiusValueRect(panel);
        const QRect slider = snipory::core::SelectionGeometry::shapeCornerRadiusSliderTrackRect(panel, value);

        QCOMPARE(panel.size(), QSize(260, 30));
        QCOMPARE(value.size(), QSize(52, 24));
        QCOMPARE(panel.right() - value.right(), 3);
        QCOMPARE(slider.left(), panel.left() + 78);
        QCOMPARE(value.left() - slider.right() - 1, 8);
    }

    void resizeHandlesSitOnRectangleOutlineAndEllipseCardinalPoints()
    {
        const QRect shape(10, 20, 100, 80);

        const QVector<QPoint> rectangleHandles = snipory::core::SelectionGeometry::shapeResizeHandleCenters(
            shape,
            snipory::core::ShapeAnnotationKind::Rectangle
        );
        const QVector<QPoint> ellipseHandles = snipory::core::SelectionGeometry::shapeResizeHandleCenters(
            shape,
            snipory::core::ShapeAnnotationKind::Ellipse
        );

        QCOMPARE(rectangleHandles.at(0), QPoint(10, 20));
        QCOMPARE(rectangleHandles.at(1), QPoint(59, 20));
        QCOMPARE(rectangleHandles.at(2), QPoint(108, 20));
        QCOMPARE(rectangleHandles.at(3), QPoint(10, 59));
        QCOMPARE(rectangleHandles.at(4), QPoint(108, 59));
        QCOMPARE(rectangleHandles.at(5), QPoint(10, 98));
        QCOMPARE(rectangleHandles.at(6), QPoint(59, 98));
        QCOMPARE(rectangleHandles.at(7), QPoint(108, 98));

        QCOMPARE(ellipseHandles.at(1), QPoint(59, 20));
        QCOMPARE(ellipseHandles.at(3), QPoint(10, 59));
        QCOMPARE(ellipseHandles.at(4), QPoint(108, 59));
        QCOMPARE(ellipseHandles.at(6), QPoint(59, 98));
    }
};

QTEST_MAIN(TestSelectionGeometry)
#include "TestSelectionGeometry.moc"
