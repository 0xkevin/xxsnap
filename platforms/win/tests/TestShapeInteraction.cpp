#include "annotation/ShapeInteraction.h"

#include <array>
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

void testDraftStaysOutsideDocumentUntilCommit()
{
    AnnotationDocument document;
    ShapeInteraction interaction(document, {0, 0, 300, 200});

    CHECK(interaction.beginDrawing(
        AnnotationKind::rectangle,
        {20, 30},
        primaryShapeActivationStyle({})));
    interaction.update({120, 90});
    CHECK(document.annotations().empty());
    CHECK(interaction.preview().has_value());
    CHECK((interaction.preview()->rect == AnnotationRect{20, 30, 100, 60}));

    CHECK(interaction.commit());
    CHECK(document.annotations().size() == 1U);
    CHECK((document.annotations()[0].rect == AnnotationRect{20, 30, 100, 60}));
    CHECK(document.annotations()[0].style.strokeWidthDip == 4.0F);
    CHECK(interaction.mode() == ShapeInteractionMode::idle);
}

void testMinimumSizeCancelAndToolSwitchDiscardDraft()
{
    AnnotationDocument document;
    ShapeInteraction interaction(document, {0, 0, 100, 100});

    CHECK(interaction.beginDrawing(AnnotationKind::rectangle, {10, 10}));
    interaction.update({17, 40});
    CHECK(!interaction.commit());
    CHECK(document.annotations().empty());

    CHECK(interaction.beginDrawing(AnnotationKind::rectangle, {10, 10}));
    interaction.update({60, 60});
    CHECK(interaction.beginDrawing(AnnotationKind::ellipse, {70, 70}));
    interaction.update({95, 95});
    CHECK(interaction.preview()->kind == AnnotationKind::ellipse);
    interaction.cancel();
    CHECK(document.annotations().empty());
    CHECK(!interaction.preview().has_value());
}

void testDrawAndMoveAreClippedToBounds()
{
    AnnotationDocument document;
    ShapeInteraction interaction(document, {0, 0, 100, 80});

    CHECK(interaction.beginDrawing(AnnotationKind::ellipse, {90, 70}));
    interaction.update({140, 120});
    CHECK((interaction.preview()->rect == AnnotationRect{90, 70, 10, 10}));
    CHECK(interaction.commit());
    const auto id = document.annotations()[0].id;

    CHECK(interaction.beginMove(id, {95, 75}));
    interaction.update({-20, -30});
    CHECK((interaction.preview()->rect == AnnotationRect{0, 0, 10, 10}));
    interaction.cancel();
    CHECK((document.find(id)->rect == AnnotationRect{90, 70, 10, 10}));

    CHECK(interaction.beginMove(id, {95, 75}));
    interaction.update({50, 40});
    CHECK(interaction.commit());
    CHECK((document.find(id)->rect == AnnotationRect{45, 35, 10, 10}));
    CHECK(document.undo());
    CHECK((document.find(id)->rect == AnnotationRect{90, 70, 10, 10}));
}

struct ResizeCase {
    ShapeResizeHandle handle;
    AnnotationPoint point;
    AnnotationRect expected;
};

void testAllEightResizeHandlesAndHitTesting()
{
    constexpr std::array cases{
        ResizeCase{ShapeResizeHandle::topLeft, {10, 15}, {10, 15, 50, 45}},
        ResizeCase{ShapeResizeHandle::top, {40, 15}, {20, 15, 40, 45}},
        ResizeCase{ShapeResizeHandle::topRight, {75, 15}, {20, 15, 55, 45}},
        ResizeCase{ShapeResizeHandle::left, {10, 40}, {10, 20, 50, 40}},
        ResizeCase{ShapeResizeHandle::right, {75, 40}, {20, 20, 55, 40}},
        ResizeCase{ShapeResizeHandle::bottomLeft, {10, 75}, {10, 20, 50, 55}},
        ResizeCase{ShapeResizeHandle::bottom, {40, 75}, {20, 20, 40, 55}},
        ResizeCase{ShapeResizeHandle::bottomRight, {75, 75}, {20, 20, 55, 55}},
    };

    for (const auto& testCase : cases) {
        AnnotationDocument document;
        const auto id = document.addShape(
            AnnotationKind::rectangle, {20, 20, 40, 40});
        ShapeInteraction interaction(document, {0, 0, 100, 100});
        const auto center = interaction.resizeHandlePoint(id, testCase.handle);
        CHECK(center.has_value());
        CHECK(interaction.hitTestResizeHandle(id, *center) == testCase.handle);
        CHECK(interaction.beginResize(id, testCase.handle));
        interaction.update(testCase.point);
        CHECK(interaction.preview().has_value());
        CHECK(interaction.preview()->rect == testCase.expected);
        CHECK(interaction.commit());
        CHECK(document.find(id)->rect == testCase.expected);
    }
}

void testResizeRejectsTooSmallPreviewAndClipsPointer()
{
    AnnotationDocument document;
    const auto id = document.addShape(
        AnnotationKind::rectangle, {20, 20, 40, 40});
    ShapeInteraction interaction(document, {0, 0, 70, 70});

    CHECK(interaction.beginResize(id, ShapeResizeHandle::bottomRight));
    interaction.update({200, 200});
    CHECK((interaction.preview()->rect == AnnotationRect{20, 20, 50, 50}));
    interaction.update({25, 25});
    CHECK((interaction.preview()->rect == AnnotationRect{20, 20, 50, 50}));
    CHECK(interaction.commit());
    CHECK((document.find(id)->rect == AnnotationRect{20, 20, 50, 50}));
}

void testRotationPreviewCancelAndCommit()
{
    AnnotationDocument document;
    const auto id = document.addShape(
        AnnotationKind::ellipse, {20, 20, 40, 20});
    ShapeInteraction interaction(document, {0, 0, 100, 100});

    const auto handle = interaction.rotationHandlePoint(id);
    CHECK(handle.has_value());
    CHECK(interaction.hitTestRotationHandle(id, *handle));
    CHECK(interaction.beginRotation(id, {40, 10}));
    interaction.update({60, 30});
    CHECK(interaction.preview()->rotationDegrees == 90.0F);
    CHECK(document.find(id)->rotationDegrees == 0.0F);
    interaction.cancel();
    CHECK(document.find(id)->rotationDegrees == 0.0F);

    CHECK(interaction.beginRotation(id, {40, 10}));
    interaction.update({20, 30});
    CHECK(interaction.preview()->rotationDegrees == -90.0F);
    CHECK(interaction.commit());
    CHECK(document.find(id)->rotationDegrees == -90.0F);
    CHECK(document.undo());
    CHECK(document.find(id)->rotationDegrees == 0.0F);
}

} // namespace

int main()
{
    testDraftStaysOutsideDocumentUntilCommit();
    testMinimumSizeCancelAndToolSwitchDiscardDraft();
    testDrawAndMoveAreClippedToBounds();
    testAllEightResizeHandlesAndHitTesting();
    testResizeRejectsTooSmallPreviewAndClipsPointer();
    testRotationPreviewCancelAndCommit();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
