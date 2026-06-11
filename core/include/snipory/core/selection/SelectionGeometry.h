#pragma once

#include "snipory/core/annotation/AnnotationDocument.h"
#include "snipory/core/capture/CaptureTypes.h"

#include <QPoint>
#include <QRect>
#include <QSize>
#include <QVector>
#include <QtTypes>

#include <algorithm>
#include <cmath>

namespace snipory::core {

class SelectionGeometry final {
public:
    static QRect normalizedLogicalRect(QPoint start, QPoint end)
    {
        const int left = std::min(start.x(), end.x());
        const int top = std::min(start.y(), end.y());
        const int width = std::abs(end.x() - start.x());
        const int height = std::abs(end.y() - start.y());
        return QRect(left, top, width, height);
    }

    static bool isUsableSelection(const QRect &logicalRect)
    {
        return logicalRect.width() >= minimumLogicalSize() && logicalRect.height() >= minimumLogicalSize();
    }

    static CaptureRegion captureRegionFromLocalLogicalRect(const QRect &logicalRect, qreal devicePixelRatio)
    {
        const qreal ratio = devicePixelRatio > 0.0 ? devicePixelRatio : 1.0;
        return CaptureRegion::fromDevicePixels(static_cast<int>(std::floor(logicalRect.x() * ratio)),
                                               static_cast<int>(std::floor(logicalRect.y() * ratio)),
                                               static_cast<int>(std::ceil(logicalRect.width() * ratio)),
                                               static_cast<int>(std::ceil(logicalRect.height() * ratio)));
    }

    static QRect toolbarRectForSelection(const QRect &selectionRect, const QSize &toolbarSize, const QRect &screenRect)
    {
        constexpr int gap = 8;
        const QRect safeScreen = screenRect.adjusted(gap, gap, -gap, -gap);
        QRect toolbar(QPoint(selectionRect.left(), selectionRect.bottom() + gap + 1), toolbarSize);

        if (toolbar.bottom() > safeScreen.bottom()) {
            toolbar.moveTop(selectionRect.top() - gap - toolbarSize.height());
        }

        if (toolbar.right() > safeScreen.right()) {
            toolbar.moveRight(safeScreen.right());
        }
        if (toolbar.left() < safeScreen.left()) {
            toolbar.moveLeft(safeScreen.left());
        }
        if (toolbar.bottom() > safeScreen.bottom()) {
            toolbar.moveBottom(safeScreen.bottom());
        }
        if (toolbar.top() < safeScreen.top()) {
            toolbar.moveTop(safeScreen.top());
        }

        return toolbar;
    }

    static QVector<QRect> horizontalToolbarButtonRects(const QRect &toolbarRect, int buttonCount)
    {
        constexpr int horizontalPadding = 6;
        constexpr int verticalPadding = 4;
        constexpr int buttonStep = 28;
        constexpr QSize buttonSize(22, 22);
        QVector<QRect> buttons;
        buttons.reserve(std::max(buttonCount, 0));

        for (int index = 0; index < buttonCount; ++index) {
            buttons.append(QRect(QPoint(toolbarRect.left() + horizontalPadding + index * buttonStep,
                                       toolbarRect.top() + verticalPadding),
                                 buttonSize));
        }

        return buttons;
    }

    static QRect translatedRectWithinBounds(const QRect &rect, const QPoint &requestedTopLeft, const QRect &bounds)
    {
        if (!rect.isValid() || !bounds.isValid()) {
            return rect;
        }

        const int minX = bounds.left();
        const int minY = bounds.top();
        const int maxX = bounds.left() + std::max(0, bounds.width() - rect.width());
        const int maxY = bounds.top() + std::max(0, bounds.height() - rect.height());
        const QPoint clampedTopLeft(std::clamp(requestedTopLeft.x(), minX, maxX),
                                    std::clamp(requestedTopLeft.y(), minY, maxY));
        return QRect(clampedTopLeft, rect.size());
    }

    static QRect shapeOptionsToolbarRectForToolbar(const QRect &toolbarRect, const QRect &screenRect)
    {
        constexpr int gap = 8;
        constexpr QSize optionsSize(630, 30);
        const QRect safeScreen = screenRect.adjusted(gap, gap, -gap, -gap);
        QRect options(QPoint(toolbarRect.left(), toolbarRect.bottom() + gap + 1), optionsSize);

        if (options.bottom() > safeScreen.bottom()) {
            options.moveTop(toolbarRect.top() - gap - optionsSize.height());
        }
        if (options.right() > safeScreen.right()) {
            options.moveRight(safeScreen.right());
        }
        if (options.left() < safeScreen.left()) {
            options.moveLeft(safeScreen.left());
        }
        if (options.top() < safeScreen.top()) {
            options.moveTop(safeScreen.top());
        }

        return options;
    }

    static QVector<QRect> shapeColorSwatchRects(const QRect &optionsRect, int colorCount)
    {
        constexpr int startX = 301;
        constexpr int topPadding = 9;
        constexpr int swatchStep = 16;
        constexpr int columns = 20;
        constexpr QSize swatchSize(12, 12);
        QVector<QRect> swatches;
        swatches.reserve(std::max(colorCount, 0));

        for (int index = 0; index < colorCount; ++index) {
            const int row = index / columns;
            const int column = index % columns;
            swatches.append(QRect(QPoint(optionsRect.left() + startX + column * swatchStep,
                                        optionsRect.top() + topPadding + row * swatchStep),
                                  swatchSize));
        }

        return swatches;
    }

    static QRect shapeRectangleModeButtonRect(const QRect &optionsRect)
    {
        return QRect(optionsRect.left() + 118, optionsRect.top() + 4, 26, 22);
    }

    static QRect shapeEllipseModeButtonRect(const QRect &optionsRect)
    {
        return QRect(optionsRect.left() + 150, optionsRect.top() + 5, 22, 20);
    }

    static QRect shapeModeButtonBackgroundRect(const QRect &button)
    {
        return button.adjusted(-2, -2, 2, 2);
    }

    static QRect shapeRectangleIconRect(const QRect &button)
    {
        return QRect(button.left() + 5, button.top() + 4, 11, 9);
    }

    static QRect shapeRectangleArrowButtonRect(const QRect &button)
    {
        return QRect(button.left() + 19, button.top() + 16, 7, 5);
    }

    static QRect shapeCornerRadiusPanelRect(const QRect &optionsRect, const QRect &rectangleButton)
    {
        return QRect(rectangleButton.left() - 6, optionsRect.bottom() + 8, 260, 30);
    }

    static QRect shapeCornerRadiusValueRect(const QRect &panel)
    {
        return QRect(panel.right() - 54, panel.top() + 3, 52, 24);
    }

    static QRect shapeCornerRadiusSliderTrackRect(const QRect &panel, const QRect &valueRect)
    {
        return QRect(panel.left() + 78, panel.top() + 13, valueRect.left() - panel.left() - 86, 4);
    }

    static QRect shapeCornerRadiusValueUpRect(const QRect &valueRect)
    {
        return QRect(valueRect.right() - 17, valueRect.top(), 18, valueRect.height() / 2);
    }

    static QRect shapeCornerRadiusValueDownRect(const QRect &valueRect)
    {
        return QRect(valueRect.right() - 17,
                     valueRect.top() + valueRect.height() / 2,
                     18,
                     valueRect.height() - valueRect.height() / 2);
    }

    static QRect shapeCornerRadiusSliderThumbRect(const QRect &track, int value, int maximum)
    {
        const int clampedMaximum = std::max(1, maximum);
        const int clampedValue = std::clamp(value, 0, clampedMaximum);
        const qreal ratio = static_cast<qreal>(clampedValue) / static_cast<qreal>(clampedMaximum);
        const int thumbX = track.left() + static_cast<int>(std::round(ratio * track.width()));
        return QRect(thumbX - 7, track.center().y() - 7, 14, 14);
    }

    static QVector<QPoint> shapeResizeHandleCenters(const QRect &shapeRect, ShapeAnnotationKind kind)
    {
        const QRect outline = shapeRect.normalized().adjusted(0, 0, -1, -1);
        if (!outline.isValid()) {
            return {};
        }

        const QPoint topCenter(outline.center().x(), outline.top());
        const QPoint leftCenter(outline.left(), outline.center().y());
        const QPoint rightCenter(outline.right(), outline.center().y());
        const QPoint bottomCenter(outline.center().x(), outline.bottom());

        if (kind == ShapeAnnotationKind::Ellipse) {
            return {
                outline.topLeft(),
                topCenter,
                outline.topRight(),
                leftCenter,
                rightCenter,
                outline.bottomLeft(),
                bottomCenter,
                outline.bottomRight(),
            };
        }

        return {
            outline.topLeft(),
            topCenter,
            outline.topRight(),
            leftCenter,
            rightCenter,
            outline.bottomLeft(),
            bottomCenter,
            outline.bottomRight(),
        };
    }

    static QVector<QRect> shapeStyleButtonRects(const QRect &optionsRect)
    {
        constexpr int buttonWidth = 30;
        constexpr int buttonCount = 3;
        QVector<QRect> buttons;
        buttons.reserve(buttonCount);

        for (int index = 0; index < buttonCount; ++index) {
            buttons.append(QRect(optionsRect.left() + index * buttonWidth,
                                 optionsRect.top(),
                                 buttonWidth,
                                 optionsRect.height()));
        }

        return buttons;
    }

    static QVector<QRect> shapeStrokeWidthButtonRects(const QRect &optionsRect, int widthCount)
    {
        constexpr int startX = 6;
        constexpr int topPadding = 5;
        constexpr int buttonStep = 24;
        constexpr QSize buttonSize(20, 20);
        QVector<QRect> buttons;
        buttons.reserve(std::max(widthCount, 0));

        for (int index = 0; index < widthCount; ++index) {
            buttons.append(QRect(QPoint(optionsRect.left() + startX + index * buttonStep,
                                        optionsRect.top() + topPadding),
                                  buttonSize));
        }

        return buttons;
    }

private:
    static constexpr int minimumLogicalSize()
    {
        return 8;
    }
};

} // namespace snipory::core
