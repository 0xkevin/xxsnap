#include "annotation/ShapeEditorController.h"

#include <cstdlib>
#include <cmath>
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
        ToolbarAction::polyline,
        ToolbarAction::pen,
        ToolbarAction::marker,
        ToolbarAction::eyedropper,
        ToolbarAction::mosaic,
        ToolbarAction::text,
        ToolbarAction::number,
        ToolbarAction::magnifier,
        ToolbarAction::eraser,
        ToolbarAction::scroll,
        ToolbarAction::undo,
        ToolbarAction::redo,
        ToolbarAction::cancel,
        ToolbarAction::pin,
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

void testBrushDrawsFreehandPath()
{
    ShapeEditorController editor({0, 0, 400, 300});
    CHECK(editor.handleToolbarAction(ToolbarAction::pen));
    CHECK(editor.isBrushToolActive());
    CHECK(editor.brushOptions().style().strokeWidthDip == 3.0F);
    CHECK(editor.pointerDown({20, 30}));
    editor.pointerMove({40, 50});
    editor.pointerMove({70, 45});
    CHECK(editor.pointerUp({100, 80}));
    CHECK(editor.document().annotations().size() == 1U);
    const auto& freehand = editor.document().annotations()[0];
    const auto id = freehand.id;
    CHECK(freehand.kind == AnnotationKind::brush);
    CHECK(freehand.brushPath.has_value());
    CHECK(freehand.brushPath->points.size() == 4U);
    CHECK((freehand.brushPath->points.front() == AnnotationPoint{20, 30}));
    CHECK((freehand.brushPath->points.back() == AnnotationPoint{100, 80}));
    CHECK(!editor.document().selectedId().has_value());
    CHECK(editor.cursorStyleAt({40, 50}) == ShapeCursorStyle::brush);

    CHECK(editor.pointerDown({200, 200}));
    editor.pointerMove({240, 240}, true);
    CHECK(editor.pointerUp({500, -20}, true));
    CHECK(editor.document().annotations().size() == 2U);
    const auto& straight = editor.document().annotations()[1];
    CHECK(straight.brushPath->points.size() == 2U);
    CHECK((straight.brushPath->points[0] == AnnotationPoint{200, 200}));
    CHECK((straight.brushPath->points[1] == AnnotationPoint{400, 0}));

    CHECK(editor.handleKey(ShapeEditorKey::escapeKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.pointerDown({40, 50}));
    editor.pointerMove({80, 90});
    CHECK(editor.pointerUp({80, 90}));
    CHECK(editor.document().selectedId() == id);
    CHECK((editor.document().find(id)->brushPath->points.front()
        == AnnotationPoint{60, 70}));
    const auto plan = editor.renderPlan({}, true);
    CHECK(plan.lineHandles.size() == 2U);
    if (plan.lineHandles.size() == 2U) {
        CHECK(editor.pointerDown(plan.lineHandles.front()));
        editor.pointerMove({20, 20});
        CHECK(editor.pointerUp({20, 20}));
        CHECK(!(editor.document().find(id)->brushPath->points.front()
            == AnnotationPoint{60, 70}));
    }
}

void testMarkerDrawsSnappedLineDotAndEditsEndpoints()
{
    ShapeEditorController editor({0, 0, 400, 300});
    CHECK(editor.handleToolbarAction(ToolbarAction::marker));
    CHECK(editor.isMarkerToolActive());
    CHECK(editor.markerOptions().style().strokeWidthDip == 18.0F);
    CHECK((editor.markerOptions().style().strokeColor
        == AnnotationColor{179, 235, 0, 255}));
    CHECK(editor.applyMarkerOptionHit(
        {MarkerOptionControl::strokeWidth, 2}));

    CHECK(editor.pointerDown({20, 30}));
    editor.pointerMove({120, 70}, true);
    CHECK(editor.pointerUp({120, 70}, true));
    CHECK(editor.document().annotations().size() == 1U);
    const auto id = editor.document().annotations()[0].id;
    const auto line = *editor.document().find(id)->markerLine;
    const auto dx = line.end.x - line.start.x;
    const auto dy = line.end.y - line.start.y;
    CHECK(std::fabs(dy) < 0.001F
        || std::fabs(dx) < 0.001F
        || std::fabs(std::fabs(dx) - std::fabs(dy)) < 0.001F);
    CHECK(editor.document().find(id)->style.strokeWidthDip == 22.0F);
    CHECK(editor.document().selectedId() == id);
    CHECK(editor.renderPlan({}, true).lineHandles.size() == 2U);
    CHECK(editor.cursorStyleAt(line.start) == ShapeCursorStyle::marker);

    CHECK(editor.handleKey(ShapeEditorKey::escapeKey, false, false)
        == ShapeEditorKeyResult::consumed);
    const auto handles = editor.renderPlan({}, true).lineHandles;
    CHECK(editor.pointerDown(handles.back()));
    editor.pointerMove({200, 140});
    CHECK(editor.pointerUp({200, 140}));
    CHECK((editor.document().find(id)->markerLine->end
        == AnnotationPoint{200, 140}));

    CHECK(editor.handleToolbarAction(ToolbarAction::marker));
    CHECK(editor.pointerDown({250, 100}));
    CHECK(editor.pointerUp({250, 100}));
    CHECK(editor.document().annotations().size() == 2U);
    CHECK((editor.document().annotations()[1].markerLine.value()
        == MarkerLine{{250, 100}, {250, 100}}));
}

void testArrowLineDrawMoveControlEditAndOptions()
{
    ShapeEditorController editor({0, 0, 400, 300});
    CHECK(editor.handleToolbarAction(ToolbarAction::polyline));
    CHECK(editor.isArrowLineToolActive());
    CHECK(editor.toolbarState().selectedAction() == ToolbarAction::polyline);
    CHECK(editor.arrowLineOptions().style().strokeWidthDip == 4.0F);

    CHECK(editor.pointerDown({20, 30}));
    editor.pointerMove({180, 110});
    CHECK(editor.pointerUp({180, 110}));
    CHECK(editor.document().annotations().size() == 1U);
    const auto id = editor.document().annotations()[0].id;
    const auto created = *editor.document().find(id);
    CHECK(created.kind == AnnotationKind::arrowLine);
    CHECK(created.arrowLine.has_value());
    CHECK((created.arrowLine->start == AnnotationPoint{20, 30}));
    CHECK((created.arrowLine->end == AnnotationPoint{180, 110}));
    CHECK((created.arrowLine->control == AnnotationPoint{100, 70}));
    CHECK(created.arrowLine->startArrowType == ArrowType::none);
    CHECK(created.arrowLine->endArrowType == ArrowType::normal);

    CHECK(editor.pointerDown({100, 70}));
    editor.pointerMove({100, 20});
    CHECK(editor.pointerUp({100, 20}));
    CHECK((editor.document().find(id)->arrowLine->control
        == AnnotationPoint{100, 20}));

    CHECK(editor.applyArrowType(ArrowEndpoint::start, 5));
    CHECK(editor.document().find(id)->arrowLine->startArrowType
        == ArrowType::bar);
    CHECK(editor.applyArrowLineOptionHit(
        {ArrowLineOptionControl::strokeWidth, 2}));
    CHECK(editor.document().find(id)->style.strokeWidthDip == 6.0F);

    CHECK(editor.pointerDown({100, 20}));
    editor.pointerMove({120, 40});
    CHECK(editor.pointerUp({120, 40}));
    CHECK((editor.document().find(id)->arrowLine->control
        == AnnotationPoint{120, 40}));
    CHECK(editor.handleToolbarAction(ToolbarAction::undo));
    CHECK((editor.document().find(id)->arrowLine->control
        == AnnotationPoint{100, 20}));
}

void testArrowToolSwitchingMenusCursorsAndEditCancellation()
{
    ShapeEditorController editor({0, 0, 400, 300});
    CHECK(editor.handleToolbarAction(ToolbarAction::polyline));
    CHECK(editor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(editor.isShapeToolActive());
    CHECK(!editor.isArrowLineToolActive());
    CHECK(editor.pointerDown({20, 30}));
    editor.pointerMove({180, 110});
    CHECK(editor.pointerUp({180, 110}));
    CHECK(editor.document().annotations().size() == 1U);
    CHECK(editor.document().annotations()[0].kind == AnnotationKind::rectangle);

    CHECK(editor.handleToolbarAction(ToolbarAction::polyline));
    CHECK(editor.pointerDown({30, 180}));
    editor.pointerMove({210, 120});
    CHECK(editor.pointerUp({210, 120}));
    const auto id = editor.document().annotations().back().id;
    auto line = *editor.document().find(id)->arrowLine;

    CHECK(editor.applyArrowLineOptionHit(
        {ArrowLineOptionControl::startArrowType, 0}));
    CHECK(editor.arrowTypeMenuEndpoint() == ArrowEndpoint::start);
    CHECK(editor.applyArrowType(ArrowEndpoint::start, 0));
    CHECK(!editor.arrowTypeMenuEndpoint().has_value());

    CHECK(editor.cursorStyleAt(line.start) == ShapeCursorStyle::move);
    CHECK(editor.cursorStyleAt(line.end) == ShapeCursorStyle::move);
    CHECK(editor.cursorStyleAt(line.control) == ShapeCursorStyle::move);
    const AnnotationPoint syntheticRotation{
        editor.document().find(id)->rect.x
            + editor.document().find(id)->rect.width / 2.0F,
        editor.document().find(id)->rect.y - 14.0F,
    };
    CHECK(editor.cursorStyleAt(syntheticRotation)
        != ShapeCursorStyle::rotation);

    CHECK(editor.pointerDown(line.start));
    editor.pointerMove({50, 190});
    CHECK(editor.pointerUp({50, 190}));
    CHECK((editor.document().find(id)->arrowLine->start
        == AnnotationPoint{50, 190}));
    line = *editor.document().find(id)->arrowLine;

    CHECK(editor.pointerDown(line.end));
    editor.pointerMove({230, 100});
    CHECK(editor.pointerUp({230, 100}));
    CHECK((editor.document().find(id)->arrowLine->end
        == AnnotationPoint{230, 100}));
    line = *editor.document().find(id)->arrowLine;

    CHECK(editor.pointerDown(line.control));
    editor.pointerMove({120, 40});
    CHECK(editor.handleKey(ShapeEditorKey::escapeKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.document().find(id)->arrowLine.value() == line);

    const auto bodyPoint = AnnotationPoint{
        (line.start.x + 2.0F * line.control.x + line.end.x) / 4.0F,
        (line.start.y + 2.0F * line.control.y + line.end.y) / 4.0F,
    };
    CHECK(editor.pointerDown(bodyPoint));
    editor.pointerMove({bodyPoint.x + 20.0F, bodyPoint.y + 20.0F});
    CHECK(editor.pointerUp({bodyPoint.x + 20.0F, bodyPoint.y + 20.0F}));
    const auto moved = *editor.document().find(id)->arrowLine;
    CHECK((moved.start == AnnotationPoint{
        line.start.x + 20.0F, line.start.y + 20.0F}));
    CHECK((moved.end == AnnotationPoint{
        line.end.x + 20.0F, line.end.y + 20.0F}));
    CHECK((moved.control == AnnotationPoint{
        line.control.x + 20.0F, line.control.y + 20.0F}));
    CHECK(editor.handleToolbarAction(ToolbarAction::undo));
    CHECK(editor.document().find(id)->arrowLine.value() == line);
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
    CHECK(editor.applyOptionHit({ShapeOptionControl::cornerRadiusDisclosure, 0}));
    CHECK(editor.options().kind() == AnnotationKind::rectangle);
    CHECK(editor.cornerRadiusPanelVisible());
    CHECK(editor.adjustCornerRadius(1.0F));
    CHECK(editor.document().find(id)->style.cornerRadiusDip == 6.0F);
    editor.dismissPopovers();
    CHECK(!editor.cornerRadiusPanelVisible());
    CHECK(editor.applyStrokePattern(3));
    CHECK(editor.document().find(id)->style.strokePattern
        == AnnotationStrokePattern::dashLongShort);
    CHECK(editor.setCornerRadius(40));
    CHECK(editor.document().find(id)->style.cornerRadiusDip == 30.0F);

    CHECK(editor.handleToolbarAction(ToolbarAction::undo));
    CHECK(editor.document().find(id)->style.cornerRadiusDip == 6.0F);
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

void testCursorFollowsMacShapeInteractionSemantics()
{
    ShapeEditorController editor({-100, -80, 500, 360});
    CHECK(editor.cursorStyleAt({150, 120}) == ShapeCursorStyle::arrow);
    CHECK(editor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(editor.cursorStyleAt({-40, -20}) == ShapeCursorStyle::crosshair);

    CHECK(editor.pointerDown({20, 20}));
    CHECK(editor.cursorStyleAt({100, 80}) == ShapeCursorStyle::crosshair);
    editor.pointerMove({100, 80});
    CHECK(editor.pointerUp({100, 80}));
    const auto id = editor.document().annotations()[0].id;

    const AnnotationPoint border{35, 20};
    CHECK(editor.cursorStyleAt(border) == ShapeCursorStyle::move);
    CHECK(editor.pointerDown(border));
    CHECK(editor.cursorStyleAt({180, 140}) == ShapeCursorStyle::move);
    CHECK(editor.pointerUp(border));

    const auto bottomRight = editor.resizeHandlePoint(
        id, ShapeResizeHandle::bottomRight);
    CHECK(bottomRight.has_value());
    CHECK(editor.cursorStyleAt(*bottomRight)
        == ShapeCursorStyle::resizeTopLeftBottomRight);
    CHECK(editor.pointerDown(*bottomRight));
    CHECK(editor.cursorStyleAt({180, 140})
        == ShapeCursorStyle::resizeTopLeftBottomRight);
    CHECK(editor.pointerUp(*bottomRight));

    const auto rotation = editor.rotationHandlePoint(id);
    CHECK(rotation.has_value());
    CHECK(editor.cursorStyleAt(*rotation) == ShapeCursorStyle::rotation);
    CHECK(editor.pointerDown(*rotation));
    CHECK(editor.cursorStyleAt({180, 140}) == ShapeCursorStyle::rotation);
    CHECK(editor.pointerUp(*rotation));
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
    CHECK(editor.handleKey(ShapeEditorKey::pin, true, false)
        == ShapeEditorKeyResult::requestPin);

    CHECK(editor.handleKey(ShapeEditorKey::deleteKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.document().annotations().empty());
    CHECK(editor.handleKey(ShapeEditorKey::escapeKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(!editor.isShapeToolActive());
    CHECK(editor.handleKey(ShapeEditorKey::escapeKey, false, false)
        == ShapeEditorKeyResult::requestCancel);
}

void testEyedropperMatchesMacToolSelectionAndEscape()
{
    ShapeEditorController editor({0, 0, 300, 200});
    CHECK(editor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(editor.handleToolbarAction(ToolbarAction::eyedropper));
    CHECK(!editor.isShapeToolActive());
    CHECK(editor.isEyedropperToolActive());
    CHECK(editor.toolbarState().selectedAction() == ToolbarAction::eyedropper);
    CHECK(editor.cursorStyleAt({20, 20}) == ShapeCursorStyle::eyedropper);
    CHECK(editor.handleKey(ShapeEditorKey::escapeKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(!editor.isEyedropperToolActive());
    CHECK(!editor.toolbarState().selectedAction().has_value());

    CHECK(editor.handleKey(ShapeEditorKey::eyedropper, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.isEyedropperToolActive());
    CHECK(editor.handleToolbarAction(ToolbarAction::marker));
    CHECK(!editor.isEyedropperToolActive());
    CHECK(editor.isMarkerToolActive());
}

void testMacToolShortcutsSelectPrimaryAnnotationTools()
{
    ShapeEditorController editor({0, 0, 300, 200});
    CHECK(editor.handleKey(ShapeEditorKey::rectangle, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.toolbarState().selectedAction() == ToolbarAction::rectangle);
    CHECK(editor.handleKey(ShapeEditorKey::polyline, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.toolbarState().selectedAction() == ToolbarAction::polyline);
    CHECK(editor.handleKey(ShapeEditorKey::pen, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.toolbarState().selectedAction() == ToolbarAction::pen);
    CHECK(editor.handleKey(ShapeEditorKey::marker, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.toolbarState().selectedAction() == ToolbarAction::marker);
}

void testMosaicCreatesStrokeAndRotatableRectangle()
{
    ShapeEditorController editor({0, 0, 300, 200});
    CHECK(editor.handleKey(ShapeEditorKey::mosaic, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.isMosaicToolActive());
    CHECK(editor.mosaicOptions().style().strokeWidthDip == 15.0F);
    CHECK(editor.cursorStyleAt({30, 30}) == ShapeCursorStyle::mosaic);
    CHECK(editor.pointerDown({20, 20}));
    editor.pointerMove({45, 27}, true);
    CHECK(editor.pointerUp({70, 30}, true));
    CHECK(editor.document().annotations().size() == 1U);
    const auto& stroke = editor.document().annotations()[0];
    CHECK(isMosaicStrokeAnnotation(stroke));
    CHECK(stroke.mosaicStroke->points.front().y
        == stroke.mosaicStroke->points.back().y);
    CHECK(stroke.mosaicRedaction->value == 8);

    CHECK(editor.applyMosaicOptionHit({
        MosaicOptionControl::rectangleMode, 0}));
    CHECK(editor.applyMosaicOptionHit({
        MosaicOptionControl::redactionType, 0}));
    CHECK(editor.setMosaicRedactionValue(16));
    CHECK(editor.pointerDown({120, 60}));
    editor.pointerMove({220, 140});
    const auto rectanglePreview = editor.renderPlan({}, true);
    CHECK(rectanglePreview.mosaicPreviewOutline.has_value());
    CHECK((rectanglePreview.mosaicPreviewOutline.value_or(AnnotationRect{})
        == AnnotationRect{120, 60, 100, 80}));
    CHECK(editor.pointerUp({220, 140}));
    CHECK(editor.document().annotations().size() == 2U);
    const auto rectangleId = editor.document().annotations()[1].id;
    const auto* rectangle = editor.document().find(rectangleId);
    CHECK(rectangle != nullptr && isMosaicRectangleAnnotation(*rectangle));
    CHECK(rectangle->mosaicRedaction->type
        == MosaicRedactionType::gaussianBlur);
    CHECK(rectangle->mosaicRedaction->value == 16);
    const auto rotation = editor.rotationHandlePoint(rectangleId);
    CHECK(rotation.has_value());
    CHECK(editor.pointerDown(*rotation));
    editor.pointerMove({230, 100});
    CHECK(editor.pointerUp({230, 100}));
    CHECK(editor.document().find(rectangleId)->rotationDegrees != 0.0F);
    CHECK(!editor.pointerDown({-20, -20}));
}

void testMosaicDrawingTakesPriorityOverNonMosaicBordersLikeMac()
{
    ShapeEditorController editor({0, 0, 300, 200});
    CHECK(editor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(editor.pointerDown({20, 20}));
    editor.pointerMove({100, 100});
    CHECK(editor.pointerUp({100, 100}));
    const auto rectangleId = editor.document().annotations().front().id;

    CHECK(editor.handleToolbarAction(ToolbarAction::mosaic));
    CHECK(editor.pointerDown({20, 60}));
    editor.pointerMove({70, 60});
    CHECK(editor.pointerUp({70, 60}));
    CHECK(editor.document().annotations().size() == 2U);
    CHECK(isMosaicStrokeAnnotation(
        editor.document().annotations().back()));
    CHECK((editor.document().find(rectangleId)->rect
        == AnnotationRect{20, 20, 80, 80}));
}

void testTextCreatesUnicodeAndEditsAtCaret()
{
    ShapeEditorController editor({0, 0, 400, 300});
    CHECK(editor.handleKey(ShapeEditorKey::text, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.isTextToolActive());
    CHECK(editor.cursorStyleAt({60, 80}) == ShapeCursorStyle::textInput);
    CHECK(editor.textOptions().style().textFontFamily
        == L"Microsoft YaHei");
    CHECK(editor.textOptions().style().textSize == 6.0F);
    CHECK(editor.pointerDown({60, 80}));
    CHECK(editor.isEditingInlineValue());
    CHECK(editor.insertText(L"中文AB"));
    CHECK(editor.handleKey(ShapeEditorKey::left, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.insertText(L"测"));
    CHECK(editor.handleKey(ShapeEditorKey::home, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.insertText(L"开"));
    CHECK(editor.handleKey(ShapeEditorKey::end, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.insertText(L"\n第二行"));
    CHECK(editor.commitTextEdit());
    CHECK(editor.document().annotations().size() == 1U);
    const auto id = editor.document().annotations()[0].id;
    const auto* text = editor.document().find(id);
    CHECK(text != nullptr && isTextAnnotation(*text));
    CHECK(*text->text == L"开中文A测B\n第二行");
    CHECK(text->style.textFontFamily == L"Microsoft YaHei");
    CHECK(text->rect.width > 16.0F);
    CHECK(text->rect.height > 24.0F);

    CHECK(editor.pointerDown({text->rect.x + 10.0F,
        text->rect.y + text->rect.height / 2.0F}));
    CHECK(editor.isEditingInlineValue());
    const auto plan = editor.renderPlan({0, 0});
    CHECK(plan.textCaret.has_value());
    CHECK(plan.textDeleteHandle.has_value());
    CHECK(plan.textEditingOutline.has_value());
    CHECK((plan.textEditingOutline.value() == standardized(text->rect)));
    CHECK(plan.resizeHandles.size() == 7U);
    CHECK(editor.toggleTextPopupMenu(TextPopupMenu::fontFamily));
    CHECK(editor.textPopupMenu() == TextPopupMenu::fontFamily);
    editor.dismissPopovers();
    CHECK(!editor.textPopupMenu().has_value());
    CHECK(editor.setTextSize(12.0F));
    CHECK(editor.document().find(id)->style.textSize == 12.0F);
    CHECK(editor.cancelTextEdit());
    CHECK(editor.document().find(id)->style.textSize == 6.0F);
}

void testClearAllFinalizesInlineEditsBeforeClearing()
{
    ShapeEditorController textEditor({0, 0, 400, 300});
    CHECK(textEditor.handleToolbarAction(ToolbarAction::text));
    CHECK(textEditor.pointerDown({60, 80}));
    CHECK(textEditor.insertText(L"draft"));
    CHECK(textEditor.isEditingInlineValue());
    CHECK(textEditor.handleToolbarAction(ToolbarAction::clearAll));
    CHECK(!textEditor.isEditingInlineValue());
    CHECK(textEditor.document().annotations().empty());
    CHECK(textEditor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(textEditor.document().annotations().empty());
    CHECK(textEditor.handleKey(ShapeEditorKey::z, true, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(textEditor.document().annotations().size() == 1U);
    CHECK(isTextAnnotation(textEditor.document().annotations().front()));

    ShapeEditorController numberEditor({0, 0, 400, 300});
    CHECK(numberEditor.handleToolbarAction(ToolbarAction::number));
    CHECK(numberEditor.pointerDown({80, 80}));
    CHECK(numberEditor.pointerDown({80, 80}, false, 2));
    CHECK(numberEditor.isEditingNumber());
    CHECK(numberEditor.handleToolbarAction(ToolbarAction::clearAll));
    CHECK(!numberEditor.isEditingNumber());
    CHECK(numberEditor.document().annotations().empty());
    CHECK(numberEditor.handleToolbarAction(ToolbarAction::rectangle));
    CHECK(numberEditor.document().annotations().empty());
    CHECK(numberEditor.handleKey(ShapeEditorKey::z, true, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(numberEditor.document().annotations().size() == 1U);
    CHECK(isNumberAnnotation(numberEditor.document().annotations().front()));
}

void testNumberToolMatchesMacSequenceEditingAndControls()
{
    ShapeEditorController editor({0, 0, 500, 400});
    CHECK(editor.handleKey(ShapeEditorKey::number, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.isNumberToolActive());
    CHECK(editor.cursorStyleAt({40, 40}) == ShapeCursorStyle::numberMark);
    CHECK(editor.numberOptions().type() == NumberMarkType::number);
    CHECK(editor.numberOptions().style().textSize == 2.0F);

    CHECK(editor.pointerDown({80, 80}));
    CHECK(editor.pointerDown({80, 80}));
    CHECK(editor.pointerUp({80, 80}));
    const auto firstMarkId = editor.document().selectedId().value();
    const auto disabledDecrement = editor.numberHandle(
        firstMarkId, NumberHandleKind::decrement);
    CHECK(disabledDecrement.has_value());
    CHECK(editor.pointerDown({
        disabledDecrement->x + disabledDecrement->width / 2.0F,
        disabledDecrement->y + disabledDecrement->height / 2.0F}));
    CHECK(editor.document().find(firstMarkId)->numberSequenceIndex == 1);
    CHECK(editor.pointerDown({130, 80}));
    CHECK(editor.pointerDown({180, 80}));
    CHECK(editor.document().annotations().size() == 3U);
    CHECK(editor.document().annotations()[0].numberSequenceIndex == 1);
    CHECK(editor.document().annotations()[1].numberSequenceIndex == 2);
    CHECK(editor.document().annotations()[2].numberSequenceIndex == 3);

    const auto middleId = editor.document().annotations()[1].id;
    CHECK(editor.pointerDown({130, 80}));
    CHECK(editor.pointerUp({130, 80}));
    const auto decrement = editor.numberHandle(
        middleId, NumberHandleKind::decrement);
    CHECK(decrement.has_value());
    CHECK(editor.pointerDown({decrement->x + decrement->width / 2.0F,
        decrement->y + decrement->height / 2.0F}));
    CHECK(editor.document().find(middleId)->numberSequenceIndex == 1);
    CHECK(editor.document().annotations()[0].numberSequenceIndex == 2);

    CHECK(editor.pointerDown({130, 80}, false, 2));
    CHECK(editor.isEditingNumber());
    CHECK(editor.handleKey(ShapeEditorKey::backspace, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.insertText(L"99"));
    CHECK(editor.handleKey(ShapeEditorKey::enter, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.document().find(middleId)->numberSequenceIndex == 99);
    CHECK(editor.document().find(middleId)->numberSequenceIsManual);

    CHECK(editor.pointerDown({180, 80}));
    CHECK(editor.pointerUp({180, 80}));
    const auto reset = editor.numberHandle(
        editor.document().selectedId().value(), NumberHandleKind::reset);
    CHECK(reset.has_value());
    CHECK(editor.pointerDown({reset->x + reset->width / 2.0F,
        reset->y + reset->height / 2.0F}));
    CHECK(editor.document().find(editor.document().selectedId().value())
        ->numberSequenceIndex == 1);
    CHECK(editor.pointerDown({230, 80}));
    CHECK(editor.document().annotations().back().numberSequenceIndex == 2);

    CHECK(editor.selectNumberType(NumberMarkType::check));
    CHECK(editor.cursorStyleAt({40, 40}) == ShapeCursorStyle::numberCheck);
    CHECK(editor.pointerDown({280, 80}));
    CHECK(editor.document().annotations().back().numberMarkType
        == NumberMarkType::check);
    CHECK(!editor.document().annotations().back().numberSequenceIndex.has_value());
    CHECK(editor.setNumberSize(24.0F));
    CHECK(editor.numberOptions().style().textSize == 24.0F);
    CHECK(editor.selectNumberType(NumberMarkType::cross));
    CHECK(editor.cursorStyleAt({40, 40}) == ShapeCursorStyle::numberCross);
}

void testNewNumberMarkOnlyFollowsTypeAfterExplicitReselection()
{
    ShapeEditorController editor({0, 0, 500, 400});
    CHECK(editor.handleKey(ShapeEditorKey::number, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.selectNumberType(NumberMarkType::check));
    CHECK(editor.pointerDown({80, 80}));
    editor.pointerUp({80, 80});

    const auto firstId = editor.document().annotations().front().id;
    const auto firstStyle = editor.document().find(firstId)->style;
    CHECK(editor.selectNumberType(NumberMarkType::cross));
    CHECK(editor.document().find(firstId)->numberMarkType
        == NumberMarkType::check);
    CHECK(editor.document().find(firstId)->style == firstStyle);

    CHECK(editor.pointerDown({160, 80}));
    editor.pointerUp({160, 80});
    CHECK(editor.document().annotations().back().numberMarkType
        == NumberMarkType::cross);

    CHECK(editor.pointerDown({80, 80}));
    editor.pointerUp({80, 80});
    CHECK(editor.selectNumberType(NumberMarkType::number));
    CHECK(editor.document().find(firstId)->numberMarkType
        == NumberMarkType::number);
    CHECK(editor.document().find(firstId)->numberSequenceIndex.has_value());
}

void testNumberSequenceGroupsManualMarksResizeAndHistory()
{
    ShapeEditorController editor({0, 0, 600, 400});
    CHECK(editor.handleKey(ShapeEditorKey::number, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.pointerDown({80, 80}));
    CHECK(editor.pointerDown({130, 80}));
    CHECK(editor.pointerDown({180, 80}));
    const auto firstGroup = editor.document().annotations()[0]
        .numberSequenceGroupId;
    const auto thirdId = editor.document().annotations()[2].id;

    CHECK(editor.pointerDown({180, 80}));
    CHECK(editor.pointerUp({180, 80}));
    const auto reset = editor.numberHandle(thirdId, NumberHandleKind::reset);
    CHECK(reset.has_value());
    CHECK(editor.pointerDown({reset->x + reset->width / 2.0F,
        reset->y + reset->height / 2.0F}));
    CHECK(editor.pointerDown({230, 80}));
    CHECK(editor.document().annotations().back().numberSequenceIndex == 2);

    CHECK(editor.pointerDown({130, 80}));
    CHECK(editor.pointerUp({130, 80}));
    CHECK(editor.pointerDown({280, 80}));
    CHECK(editor.document().annotations().back().numberSequenceGroupId
        == firstGroup);
    CHECK(editor.document().annotations().back().numberSequenceIndex == 3);

    ShapeEditorController manualEditor({0, 0, 600, 400});
    CHECK(manualEditor.handleKey(ShapeEditorKey::number, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(manualEditor.pointerDown({80, 80}));
    CHECK(manualEditor.pointerDown({130, 80}));
    const auto firstId = manualEditor.document().annotations()[0].id;
    CHECK(manualEditor.pointerDown({80, 80}, false, 2));
    CHECK(manualEditor.handleKey(ShapeEditorKey::backspace, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(manualEditor.insertText(L"17"));
    CHECK(manualEditor.commitNumberEdit());
    CHECK(manualEditor.pointerDown({180, 80}));
    const auto eighteenId = manualEditor.document().annotations().back().id;
    CHECK(manualEditor.document().find(eighteenId)->numberSequenceIndex == 18);
    CHECK(manualEditor.document().find(eighteenId)->numberSequenceIsManual);
    CHECK(manualEditor.pointerDown({230, 80}));
    const auto nineteenId = manualEditor.document().annotations().back().id;
    CHECK(manualEditor.document().find(nineteenId)->numberSequenceIndex == 19);
    CHECK(manualEditor.document().find(nineteenId)->numberSequenceIsManual);

    CHECK(manualEditor.pointerDown({180, 80}));
    CHECK(manualEditor.pointerUp({180, 80}));
    CHECK(manualEditor.handleKey(ShapeEditorKey::deleteKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(manualEditor.document().find(eighteenId) == nullptr);
    CHECK(manualEditor.document().find(firstId)->numberSequenceIndex == 17);
    CHECK(manualEditor.document().find(nineteenId)->numberSequenceIndex == 19);
    CHECK(manualEditor.handleKey(ShapeEditorKey::z, true, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(manualEditor.document().find(eighteenId) != nullptr);
    CHECK(manualEditor.handleKey(ShapeEditorKey::z, true, true)
        == ShapeEditorKeyResult::consumed);
    CHECK(manualEditor.document().find(eighteenId) == nullptr);

    CHECK(manualEditor.pointerDown({230, 80}));
    CHECK(manualEditor.pointerUp({230, 80}));
    const auto before = standardized(manualEditor.document().find(nineteenId)->rect);
    const auto resize = manualEditor.numberHandle(
        nineteenId, NumberHandleKind::resize);
    CHECK(resize.has_value());
    const AnnotationPoint resizeCenter{
        resize->x + resize->width / 2.0F,
        resize->y + resize->height / 2.0F,
    };
    CHECK(manualEditor.pointerDown(resizeCenter));
    manualEditor.pointerMove({resizeCenter.x + 60.0F, resizeCenter.y + 60.0F});
    CHECK(manualEditor.pointerUp(
        {resizeCenter.x + 60.0F, resizeCenter.y + 60.0F}));
    const auto after = standardized(manualEditor.document().find(nineteenId)->rect);
    CHECK(after.width > before.width);
    CHECK(std::abs((after.x + after.width / 2.0F)
        - (before.x + before.width / 2.0F)) < 0.01F);
    CHECK(std::abs((after.y + after.height / 2.0F)
        - (before.y + before.height / 2.0F)) < 0.01F);
}

void testMagnifierMatchesMacCreationOptionsAndEditing()
{
    ShapeEditorController editor({0, 0, 400, 300});
    CHECK(editor.handleKey(ShapeEditorKey::magnifier, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.isMagnifierToolActive());
    CHECK(editor.magnifierOptions().shape() == MagnifierShape::rectangle);
    CHECK(editor.magnifierOptions().zoom() == 2.0F);
    CHECK(editor.cursorStyleAt({20, 20}) == ShapeCursorStyle::crosshair);
    CHECK(editor.applyMagnifierOptionHit(
        {MagnifierOptionControl::circleMode, 0U}));
    CHECK(editor.selectMagnifierZoom(3.0F));
    CHECK(editor.applyMagnifierOptionHit(
        {MagnifierOptionControl::strokeWidth, 2U}));

    const auto idleRevision = editor.interactionRevision();
    editor.pointerMove({20, 30});
    CHECK(editor.interactionRevision() == idleRevision);
    CHECK(editor.pointerDown({20, 30}));
    editor.pointerMove({100, 70}, true);
    const auto movedRevision = editor.interactionRevision();
    editor.pointerMove({100, 70}, true);
    CHECK(editor.interactionRevision() == movedRevision);
    CHECK(editor.pointerUp({100, 70}, true));
    CHECK(editor.document().annotations().size() == 1U);
    const auto id = editor.document().annotations()[0].id;
    const auto* magnifier = editor.document().find(id);
    CHECK(isMagnifierAnnotation(*magnifier));
    CHECK(magnifier->magnifierShape == MagnifierShape::circle);
    CHECK(magnifier->magnifierZoom == 3.0F);
    CHECK(magnifier->style.strokeWidthDip == 7.0F);
    CHECK(magnifier->rect.width == magnifier->rect.height);
    CHECK(editor.document().selectedId() == id);
    const auto plan = editor.renderPlan({}, true);
    CHECK(plan.resizeHandles.size() == 8U);
    CHECK(!plan.rotationHandle.has_value());
    CHECK(editor.cursorStyleAt({60, 70}) == ShapeCursorStyle::move);

    CHECK(editor.handleToolbarAction(ToolbarAction::magnifier));
    CHECK(!editor.isMagnifierToolActive());
    CHECK(editor.handleToolbarAction(ToolbarAction::magnifier));
    CHECK(editor.isMagnifierToolActive());
    CHECK(editor.magnifierOptions().shape() == MagnifierShape::circle);
    CHECK(editor.magnifierOptions().zoom() == 3.0F);
    CHECK(editor.magnifierOptions().style().strokeWidthDip == 7.0F);

    auto reloadedStyle = editor.document().find(id)->style;
    reloadedStyle.strokeWidthDip = 2.0F;
    CHECK(editor.document().updateMagnifier(
        id, MagnifierShape::rectangle, 4.0F, reloadedStyle));
    CHECK(editor.handleToolbarAction(ToolbarAction::eyedropper));
    CHECK(editor.isEyedropperToolActive());
    CHECK(editor.pointerDown({60, 70}));
    CHECK(editor.pointerUp({60, 70}));
    CHECK(editor.isMagnifierToolActive());
    CHECK(editor.document().selectedId() == id);
    CHECK(editor.magnifierOptions().shape() == MagnifierShape::rectangle);
    CHECK(editor.magnifierOptions().zoom() == 4.0F);
    CHECK(editor.magnifierOptions().style().strokeWidthDip == 2.0F);

    CHECK(editor.handleKey(ShapeEditorKey::deleteKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.document().annotations().empty());
    CHECK(editor.handleKey(ShapeEditorKey::z, true, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.document().annotations().size() == 1U);
    CHECK(editor.toolbarState().isEnabled(ToolbarAction::redo));
    CHECK(editor.applyMagnifierOptionHit(
        {MagnifierOptionControl::circleMode, 0U}));
    CHECK(!editor.toolbarState().isEnabled(ToolbarAction::redo));
    CHECK(editor.handleKey(ShapeEditorKey::z, true, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.toolbarState().isEnabled(ToolbarAction::redo));
    CHECK(editor.selectMagnifierZoom(3.0F));
    CHECK(!editor.toolbarState().isEnabled(ToolbarAction::redo));
    CHECK(editor.handleKey(ShapeEditorKey::escapeKey, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(!editor.isMagnifierToolActive());
}

void testEraserMatchesMacPointRectangleAndClearSemantics()
{
    ShapeEditorController editor({0, 0, 300, 200});
    const auto first = editor.document().addShape(
        AnnotationKind::rectangle, {20, 20, 100, 80});
    const auto second = editor.document().addShape(
        AnnotationKind::ellipse, {40, 30, 100, 80});
    CHECK(editor.handleKey(ShapeEditorKey::eraser, false, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.isEraserToolActive());
    CHECK(editor.eraserMode() == EraserMode::point);
    CHECK(editor.cursorStyleAt({60, 60}) == ShapeCursorStyle::eraser);

    CHECK(editor.pointerDown({60, 60}));
    editor.pointerMove({200, 150});
    CHECK(editor.document().find(second) == nullptr);
    CHECK(editor.document().find(first) != nullptr);
    CHECK(editor.pointerUp({200, 150}));
    CHECK(editor.document().find(first) != nullptr);

    CHECK(editor.applyEraserOptionHit(
        {EraserOptionControl::rectangleMode}));
    CHECK(editor.cursorStyleAt({-20, -20}) == ShapeCursorStyle::crosshair);
    CHECK(editor.pointerDown({-10, 10}));
    editor.pointerMove({70, 70});
    const auto preview = editor.eraserRectanglePreview();
    CHECK(preview.has_value());
    CHECK((preview.value_or(AnnotationRect{})
        == AnnotationRect{0, 10, 70, 60}));
    CHECK(editor.renderPlan({}, true).eraserPreview == preview);
    CHECK(editor.pointerUp({70, 70}));
    CHECK(editor.document().find(first) != nullptr);
    CHECK(editor.document().eraserMasks().size() == 1U);
    CHECK((editor.document().eraserMasks()[0].affectedAnnotationIds
        == std::vector<AnnotationId>{first}));

    CHECK(editor.applyEraserOptionHit({EraserOptionControl::clearAll}));
    CHECK(editor.document().annotations().empty());
    CHECK(editor.document().eraserMasks().empty());
    CHECK(editor.handleKey(ShapeEditorKey::z, true, false)
        == ShapeEditorKeyResult::consumed);
    CHECK(editor.document().find(first) != nullptr);
    CHECK(editor.document().eraserMasks().size() == 1U);

    const auto erasePoint = [](ShapeEditorController& controller,
                               AnnotationPoint point) {
        CHECK(controller.handleToolbarAction(ToolbarAction::eraser));
        CHECK(controller.pointerDown(point));
        CHECK(controller.pointerUp(point));
    };
    ShapeEditorController ellipseHit({0, 0, 100, 100});
    const auto ellipseId = ellipseHit.document().addShape(
        AnnotationKind::ellipse, {20, 20, 40, 40});
    erasePoint(ellipseHit, {22, 22});
    CHECK(ellipseHit.document().find(ellipseId) == nullptr);

    ShapeEditorController rotatedShapeHit({0, 0, 100, 100});
    const auto rotatedId = rotatedShapeHit.document().addShape(
        AnnotationKind::rectangle, {20, 20, 40, 40}, {}, 45.0F);
    erasePoint(rotatedShapeHit, {22, 22});
    CHECK(rotatedShapeHit.document().find(rotatedId) == nullptr);

    ShapeEditorController numberHit({0, 0, 100, 100});
    const auto numberId = numberHit.document().addNumberMark(
        {20, 20, 40, 40}, NumberMarkType::number, 1, false, 1);
    erasePoint(numberHit, {20, 20});
    CHECK(numberHit.document().find(numberId) == nullptr);

    ShapeEditorController precise({0, 0, 300, 200});
    const auto arrowId = precise.document().addArrowLine({
        {20, 100}, {280, 100}, {150, 0},
        ArrowType::none, ArrowType::normal});
    precise.document().addShape(
        AnnotationKind::rectangle, {100, 100, 100, 10}, {}, 45.0F);
    CHECK(precise.handleToolbarAction(ToolbarAction::eraser));
    CHECK(precise.applyEraserOptionHit(
        {EraserOptionControl::rectangleMode}));
    CHECK(precise.pointerDown({140, 5}));
    precise.pointerMove({160, 20});
    CHECK(precise.pointerUp({160, 20}));
    CHECK(precise.document().eraserMasks().size() == 1U);
    CHECK((precise.document().eraserMasks()[0].affectedAnnotationIds
        == std::vector<AnnotationId>{arrowId}));
    CHECK(precise.pointerDown({112, 132}));
    precise.pointerMove({116, 136});
    CHECK(precise.pointerUp({116, 136}));
    CHECK(precise.document().eraserMasks().size() == 1U);
}

} // namespace

int main()
{
    testToolbarCapabilityAndPrimaryToolToggle();
    testDrawOptionsHistoryAndKindSwitch();
    testSelectedShapeMoveResizeRotateAndEscapeCancel();
    testCursorFollowsMacShapeInteractionSemantics();
    testCtrlShortcutsDeleteAndTerminalRequests();
    testArrowLineDrawMoveControlEditAndOptions();
    testArrowToolSwitchingMenusCursorsAndEditCancellation();
    testBrushDrawsFreehandPath();
    testMarkerDrawsSnappedLineDotAndEditsEndpoints();
    testEyedropperMatchesMacToolSelectionAndEscape();
    testMacToolShortcutsSelectPrimaryAnnotationTools();
    testMosaicCreatesStrokeAndRotatableRectangle();
    testMosaicDrawingTakesPriorityOverNonMosaicBordersLikeMac();
    testTextCreatesUnicodeAndEditsAtCaret();
    testClearAllFinalizesInlineEditsBeforeClearing();
    testNumberToolMatchesMacSequenceEditingAndControls();
    testNewNumberMarkOnlyFollowsTypeAfterExplicitReselection();
    testNumberSequenceGroupsManualMarksResizeAndHistory();
    testMagnifierMatchesMacCreationOptionsAndEditing();
    testEraserMatchesMacPointRectangleAndClearSemantics();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
