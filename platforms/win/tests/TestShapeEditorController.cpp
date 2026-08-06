#include "annotation/ShapeEditorController.h"

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

void testToolbarCapabilityAndPrimaryToolToggle()
{
    ShapeEditorController editor({0, 0, 300, 200});
    const std::vector expected{
        ToolbarAction::rectangle,
        ToolbarAction::undo,
        ToolbarAction::redo,
        ToolbarAction::cancel,
        ToolbarAction::save,
        ToolbarAction::copy,
    };
    CHECK(editor.toolbarState().visibleActions() == expected);
    CHECK(!editor.toolbarState().isEnabled(ToolbarAction::undo));
    CHECK(!editor.toolbarState().isEnabled(ToolbarAction::redo));
    CHECK(editor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(editor.isShapeToolActive());
    CHECK(editor.toolbarState().selectedAction() == ToolbarAction::rectangle);
    CHECK(editor.options().style().strokeWidthDip == 4.0F);
    CHECK(editor.options().style().cornerRadiusDip == 5.0F);
    CHECK(editor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(!editor.isShapeToolActive());
    CHECK(!editor.toolbarState().selectedAction().has_value());
}

void testDrawOptionsHistoryAndKindSwitch()
{
    ShapeEditorController editor({0, 0, 300, 200});
    CHECK(editor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(editor.pointerDown({20, 30}));
    editor.pointerMove({120, 90});
    CHECK(editor.preview().has_value());
    CHECK(editor.document().annotations().empty());
    CHECK(editor.pointerUp({120, 90}));
    CHECK(editor.document().annotations().size() == 1U);
    const auto id = editor.document().annotations()[0].id;
    CHECK(editor.document().selectedId() == id);
    CHECK(editor.toolbarState().isEnabled(ToolbarAction::undo));

    CHECK(editor.applyOptionHit({ShapeOptionControl::strokeWidth, 2}));
    CHECK(editor.document().find(id)->style.strokeWidthDip == 7.0F);
    CHECK(editor.applyOptionHit({ShapeOptionControl::fillToggle, 0}));
    CHECK(editor.document().find(id)->style.fillEnabled);
    CHECK(editor.applyOptionHit({ShapeOptionControl::ellipseMode, 0}));
    CHECK(editor.document().find(id)->kind == AnnotationKind::ellipse);
    CHECK(editor.options().kind() == AnnotationKind::ellipse);
    CHECK(editor.applyStrokePattern(3));
    CHECK(editor.document().find(id)->style.strokePattern
        == AnnotationStrokePattern::dashLongShort);
    CHECK(editor.setCornerRadius(40));
    CHECK(editor.document().find(id)->style.cornerRadiusDip == 30.0F);

    CHECK(editor.handleToolbarAction(ToolbarAction::undo));
    CHECK(editor.document().find(id)->style.cornerRadiusDip == 5.0F);
    CHECK(editor.toolbarState().isEnabled(ToolbarAction::redo));
    CHECK(editor.handleToolbarAction(ToolbarAction::redo));
    CHECK(editor.document().find(id)->style.cornerRadiusDip == 30.0F);
}

void testSelectedShapeMoveResizeRotateAndEscapeCancel()
{
    ShapeEditorController editor({0, 0, 300, 200});
    CHECK(editor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(editor.pointerDown({20, 20}));
    editor.pointerMove({100, 80});
    CHECK(editor.pointerUp({100, 80}));
    const auto id = editor.document().annotations()[0].id;

    CHECK(editor.pointerDown({35, 20}));
    editor.pointerMove({55, 40});
    CHECK(editor.pointerUp({55, 40}));
    CHECK((editor.document().find(id)->rect == AnnotationRect{40, 40, 80, 60}));

    const auto bottomRight = editor.resizeHandlePoint(
        id, ShapeResizeHandle::bottomRight);
    CHECK(bottomRight.has_value());
    CHECK(editor.pointerDown(*bottomRight));
    editor.pointerMove({160, 130});
    CHECK(editor.pointerUp({160, 130}));
    CHECK((editor.document().find(id)->rect == AnnotationRect{40, 40, 120, 90}));

    const auto rotation = editor.rotationHandlePoint(id);
    CHECK(rotation.has_value());
    CHECK(editor.pointerDown(*rotation));
    editor.pointerMove({175, 85});
    CHECK(editor.pointerUp({175, 85}));
    CHECK(editor.document().find(id)->rotationDegrees != 0.0F);

    const auto original = editor.document().find(id)->rect;
    CHECK(editor.pointerDown({145, 55}));
    editor.pointerMove({5, 5});
    CHECK(editor.handleKey(ShapeEditorKey::escapeKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.document().find(id)->rect == original);
}

void testCtrlShortcutsDeleteAndTerminalRequests()
{
    ShapeEditorController editor({0, 0, 300, 200});
    CHECK(editor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(editor.pointerDown({10, 10}));
    editor.pointerMove({60, 60});
    CHECK(editor.pointerUp({60, 60}));
    CHECK(editor.handleKey(ShapeEditorKey::z, true, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.document().annotations().empty());
    CHECK(editor.handleKey(ShapeEditorKey::z, true, true)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.document().annotations().size() == 1U);
    CHECK(editor.handleKey(ShapeEditorKey::copy, true, false)
        == ShapeEditorKeyResult::requestCopy);
    CHECK(editor.handleKey(ShapeEditorKey::save, true, false)
        == ShapeEditorKeyResult::requestSave);

    CHECK(editor.handleKey(ShapeEditorKey::deleteKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.document().annotations().empty());
    CHECK(editor.handleKey(ShapeEditorKey::escapeKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(!editor.isShapeToolActive());
    CHECK(editor.handleKey(ShapeEditorKey::escapeKey, false, false)
        == ShapeEditorKeyResult::requestCancel);
}

} // namespace

int main()
{
    testToolbarCapabilityAndPrimaryToolToggle();
    testDrawOptionsHistoryAndKindSwitch();
    testSelectedShapeMoveResizeRotateAndEscapeCancel();
    testCtrlShortcutsDeleteAndTerminalRequests();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
