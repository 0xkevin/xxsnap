#include "annotation/AnnotationDocument.h"

#include <cstdlib>
#include <iostream>

namespace {

using namespace xxsnap::win;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

void testAddDeleteAndStableOrder()
{
    AnnotationDocument document;
    const auto rectangle = document.addShape(
        AnnotationKind::rectangle, {10, 20, 80, 40});
    const auto ellipse = document.addShape(
        AnnotationKind::ellipse, {100, 120, 50, 60});

    CHECK(rectangle != invalidAnnotationId);
    CHECK(ellipse > rectangle);
    CHECK(document.annotations().size() == 2U);
    CHECK(document.annotations()[0].id == rectangle);
    CHECK(document.annotations()[1].id == ellipse);
    CHECK(document.selectedId() == ellipse);
    CHECK(document.canUndo());
    CHECK(!document.canRedo());

    CHECK(document.remove(rectangle));
    CHECK(document.annotations().size() == 1U);
    CHECK(document.undo());
    CHECK(document.annotations().size() == 2U);
    CHECK(document.annotations()[0].id == rectangle);
    CHECK(document.annotations()[1].id == ellipse);
    CHECK(document.redo());
    CHECK(document.annotations().size() == 1U);
}

void testAllShapeEditsAreReversible()
{
    AnnotationDocument document;
    const auto id = document.addShape(
        AnnotationKind::rectangle,
        {10, 20, 80, 40},
        primaryShapeActivationStyle({}));
    CHECK(document.updateRect(id, {20, 30, 90, 50}));
    CHECK(document.move(id, {5, -10}));
    CHECK(document.updateRotation(id, 35.0F));
    CHECK(document.updateKind(id, AnnotationKind::ellipse));

    auto style = document.find(id)->style;
    style.fillEnabled = true;
    style.strokeWidthDip = 7.0F;
    CHECK(document.updateStyle(id, style));
    CHECK((document.find(id)->rect == AnnotationRect{25, 20, 90, 50}));
    CHECK(document.find(id)->rotationDegrees == 35.0F);
    CHECK(document.find(id)->kind == AnnotationKind::ellipse);
    CHECK(document.find(id)->style == style);

    CHECK(document.undo());
    CHECK(document.find(id)->style != style);
    CHECK(document.undo());
    CHECK(document.find(id)->kind == AnnotationKind::rectangle);
    CHECK(document.undo());
    CHECK(document.find(id)->rotationDegrees == 0.0F);
    CHECK(document.undo());
    CHECK((document.find(id)->rect == AnnotationRect{20, 30, 90, 50}));
    CHECK(document.undo());
    CHECK((document.find(id)->rect == AnnotationRect{10, 20, 80, 40}));

    CHECK(document.redo());
    CHECK(document.redo());
    CHECK(document.redo());
    CHECK(document.redo());
    CHECK(document.redo());
    CHECK(document.find(id)->style == style);
}

void testInvalidAndNoOpEditsDoNotPolluteHistory()
{
    AnnotationDocument document;
    CHECK(document.addShape(AnnotationKind::brush, {0, 0, 10, 10})
        == invalidAnnotationId);
    CHECK(document.addShape(AnnotationKind::rectangle, {0, 0, 0, 10})
        == invalidAnnotationId);
    CHECK(!document.canUndo());

    const auto id = document.addShape(
        AnnotationKind::rectangle, {0, 0, 10, 10});
    CHECK(!document.updateRect(id, {0, 0, 10, 10}));
    CHECK(!document.move(id, {0, 0}));
    CHECK(!document.updateRotation(id, 0.0F));
    CHECK(!document.remove(9999));
    CHECK(document.undo());
    CHECK(document.annotations().empty());
    CHECK(!document.undo());
}

void testNewCommandInvalidatesRedoAndSelectionIsSafe()
{
    AnnotationDocument document;
    const auto first = document.addShape(
        AnnotationKind::rectangle, {0, 0, 10, 10});
    const auto second = document.addShape(
        AnnotationKind::ellipse, {20, 20, 10, 10});
    CHECK(document.select(first));
    CHECK(!document.select(9999));
    CHECK(document.undo());
    CHECK(document.find(second) == nullptr);
    CHECK(document.canRedo());

    CHECK(document.move(first, {2, 3}));
    CHECK(!document.canRedo());
    CHECK(document.selectedId() == first);
    document.clearSelection();
    CHECK(!document.selectedId().has_value());
}

void testArrowLineCommandsPreserveCurveGeometryAndHistory()
{
    AnnotationDocument document;
    const ArrowLine line{
        {10, 20}, {110, 80}, {55, 25},
        ArrowType::none, ArrowType::normal};
    const auto id = document.addArrowLine(line);
    CHECK(id != invalidAnnotationId);
    CHECK(document.find(id)->kind == AnnotationKind::arrowLine);
    CHECK(document.find(id)->arrowLine == line);
    CHECK((document.find(id)->rect == AnnotationRect{10, 20, 100, 60}));

    CHECK(document.move(id, {15, -5}));
    const ArrowLine moved{
        {25, 15}, {125, 75}, {70, 20},
        ArrowType::none, ArrowType::normal};
    CHECK(document.find(id)->arrowLine == moved);
    CHECK(document.undo());
    CHECK(document.find(id)->arrowLine == line);

    auto edited = line;
    edited.control = {70, 5};
    edited.startArrowType = ArrowType::dot;
    edited.endArrowType = ArrowType::bar;
    CHECK(document.updateArrowLine(id, edited));
    CHECK(document.find(id)->arrowLine == edited);
    CHECK(document.undo());
    CHECK(document.find(id)->arrowLine == line);
}

void testBrushPathHistoryAndBounds()
{
    AnnotationDocument document;
    const BrushPath path{{{10, 20}, {35, 8}, {80, 50}}};
    const auto id = document.addBrushPath(path);
    CHECK(id != invalidAnnotationId);
    CHECK(document.find(id)->kind == AnnotationKind::brush);
    CHECK(document.find(id)->brushPath == path);
    CHECK((document.find(id)->rect == AnnotationRect{10, 8, 70, 42}));
    CHECK(document.move(id, {5, -3}));
    CHECK((document.find(id)->brushPath->points[0]
        == AnnotationPoint{15, 17}));
    CHECK((document.find(id)->brushPath->points[2]
        == AnnotationPoint{85, 47}));
    CHECK(document.undo());
    CHECK(document.find(id)->brushPath == path);
}

void testMarkerLineHistoryAndZeroLengthDot()
{
    AnnotationDocument document;
    const MarkerLine dot{{30, 40}, {30, 40}};
    const auto id = document.addMarkerLine(dot);
    CHECK(id != invalidAnnotationId);
    CHECK(document.find(id)->kind == AnnotationKind::marker);
    CHECK(document.find(id)->markerLine == dot);
    CHECK((document.find(id)->rect == AnnotationRect{30, 40, 0, 0}));
    CHECK(document.move(id, {5, -3}));
    CHECK((document.find(id)->markerLine
        == MarkerLine{{35, 37}, {35, 37}}));
    CHECK(document.updateMarkerLine(id, {{10, 20}, {90, 60}}));
    CHECK((document.find(id)->rect == AnnotationRect{10, 20, 80, 40}));
    CHECK(document.undo());
    CHECK((document.find(id)->markerLine
        == MarkerLine{{35, 37}, {35, 37}}));
}

} // namespace

int main()
{
    testAddDeleteAndStableOrder();
    testAllShapeEditsAreReversible();
    testInvalidAndNoOpEditsDoNotPolluteHistory();
    testNewCommandInvalidatesRedoAndSelectionIsSafe();
    testArrowLineCommandsPreserveCurveGeometryAndHistory();
    testBrushPathHistoryAndBounds();
    testMarkerLineHistoryAndZeroLengthDot();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
