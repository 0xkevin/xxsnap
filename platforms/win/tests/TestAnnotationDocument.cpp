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

    auto style = document.find(id)->style;
    style.fillEnabled = true;
    style.strokeWidthDip = 7.0F;
    CHECK(document.updateStyle(id, style));
    CHECK((document.find(id)->rect == AnnotationRect{25, 20, 90, 50}));
    CHECK(document.find(id)->rotationDegrees == 35.0F);
    CHECK(document.find(id)->style == style);

    CHECK(document.undo());
    CHECK(document.find(id)->style != style);
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

} // namespace

int main()
{
    testAddDeleteAndStableOrder();
    testAllShapeEditsAreReversible();
    testInvalidAndNoOpEditsDoNotPolluteHistory();
    testNewCommandInvalidatesRedoAndSelectionIsSafe();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
