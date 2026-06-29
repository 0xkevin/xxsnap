#pragma once

#include <QColor>
#include <QRect>
#include <QVector>

namespace snipory::core {

enum class ShapeAnnotationKind {
    Rectangle,
    Ellipse
};

enum class AnnotationStrokePattern {
    Solid,
    DashLong,
    DashNarrow,
    DashLongShort,
    SketchSolid,
    SketchDashed
};

struct AnnotationStyle final {
    QColor strokeColor = QColor(245, 34, 45);
    int strokeWidth = 3;
    AnnotationStrokePattern strokePattern = AnnotationStrokePattern::Solid;
    bool fillEnabled = false;
    QColor fillColor = QColor(245, 34, 45);
    int cornerRadius = 0;
};

struct ShapeAnnotation final {
    ShapeAnnotationKind kind = ShapeAnnotationKind::Rectangle;
    QRect rect;
    AnnotationStyle style;

    static ShapeAnnotation rectangle(const QRect &rect, const AnnotationStyle &style)
    {
        return {ShapeAnnotationKind::Rectangle, rect.normalized(), style};
    }

    static ShapeAnnotation ellipse(const QRect &rect, const AnnotationStyle &style)
    {
        return {ShapeAnnotationKind::Ellipse, rect.normalized(), style};
    }
};

class AnnotationDocument final {
public:
    QVector<ShapeAnnotation> shapes() const
    {
        return visibleShapes();
    }

    void addShape(const ShapeAnnotation &shape)
    {
        if (!isUsableShape(shape.rect)) {
            return;
        }

        QVector<ShapeAnnotation> nextShapes = visibleShapes();
        nextShapes.append(shape);
        commit(nextShapes);
    }

    bool replaceShape(int index, const ShapeAnnotation &shape)
    {
        if (index < 0 || index >= visibleShapes().size() || !isUsableShape(shape.rect)) {
            return false;
        }

        QVector<ShapeAnnotation> nextShapes = visibleShapes();
        nextShapes[index] = shape;
        commit(nextShapes);
        return true;
    }

    bool canUndo() const
    {
        return m_historyIndex > 0;
    }

    bool canRedo() const
    {
        return m_historyIndex + 1 < m_history.size();
    }

    void undo()
    {
        if (canUndo()) {
            --m_historyIndex;
        }
    }

    void redo()
    {
        if (canRedo()) {
            ++m_historyIndex;
        }
    }

    QVector<ShapeAnnotation> visibleShapes() const
    {
        if (m_historyIndex < 0 || m_historyIndex >= m_history.size()) {
            return {};
        }

        return m_history.at(m_historyIndex);
    }

    void clear()
    {
        m_history = {{}};
        m_historyIndex = 0;
    }

private:
    void commit(const QVector<ShapeAnnotation> &shapes)
    {
        while (m_history.size() > m_historyIndex + 1) {
            m_history.removeLast();
        }

        m_history.append(shapes);
        m_historyIndex = m_history.size() - 1;
    }

    static bool isUsableShape(const QRect &rect)
    {
        return rect.width() >= 8 && rect.height() >= 8;
    }

    QVector<QVector<ShapeAnnotation>> m_history = {{}};
    int m_historyIndex = 0;
};

} // namespace snipory::core
