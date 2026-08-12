#include "annotation/ShapeOptions.h"

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

void testMacPaletteAndActivationDefaults()
{
    const auto& palette = macShapePalette();
    CHECK(palette.size() == 20U);
    CHECK((palette.front() == AnnotationColor{255, 0, 26, 255}));
    CHECK((palette.back() == AnnotationColor{208, 198, 236, 255}));

    ShapeOptionsState state;
    CHECK(state.kind() == AnnotationKind::rectangle);
    CHECK(state.style().strokeWidthDip == 4.0F);
    CHECK(state.style().cornerRadiusDip == 5.0F);
    CHECK(state.style().strokePattern == AnnotationStrokePattern::solid);
    CHECK(!state.style().fillEnabled);
    CHECK(state.style().strokeColor == palette.front());
    CHECK(state.style().fillColor == palette.front());
    CHECK(state.selectedPaletteIndex() == 0U);
}

void testStateMutationsMatchMacControls()
{
    CHECK(macShapeStrokePatterns().size() == 6U);
    CHECK(macShapeStrokePatterns()[4] == AnnotationStrokePattern::sketchSolid);
    ShapeOptionsState state;
    CHECK(state.setStrokeWidth(7.0F));
    CHECK(!state.setStrokeWidth(6.0F));
    CHECK(state.setStrokePattern(AnnotationStrokePattern::sketchDashed));
    CHECK(state.toggleFill());
    CHECK(state.style().fillEnabled);
    CHECK(state.setKind(AnnotationKind::ellipse));
    CHECK(!state.setKind(AnnotationKind::arrowLine));
    CHECK(state.setCornerRadius(40.0F));
    CHECK(state.style().cornerRadiusDip == 30.0F);
    CHECK(state.adjustCornerRadius(-40.0F));
    CHECK(state.style().cornerRadiusDip == 0.0F);

    CHECK(state.selectPalette(8));
    CHECK(state.selectedPaletteIndex() == 8U);
    CHECK(state.style().strokeColor == macShapePalette()[8]);
    CHECK(state.style().fillColor == macShapePalette()[8]);
    CHECK(state.selectCustomColor({1, 2, 3, 99}));
    CHECK(!state.selectedPaletteIndex().has_value());
    CHECK((state.style().strokeColor == AnnotationColor{1, 2, 3, 255}));
    CHECK(state.style().fillColor == state.style().strokeColor);
}

void testCornerRadiusPanelUsesExactMacGeometry()
{
    const auto options = shapeOptionsLayout({100, 100}, 20);
    const auto below = cornerRadiusPanelLayout(
        options, {0, 0, 800, 600});
    CHECK((below.panel == AnnotationRect{224, 148, 260, 30}));
    CHECK((below.value == AnnotationRect{429, 151, 52, 24}));
    CHECK((below.sliderTrack == AnnotationRect{302, 161, 119, 4}));
    CHECK((below.increment == AnnotationRect{464, 151, 18, 12}));
    CHECK((below.decrement == AnnotationRect{464, 163, 18, 12}));

    const auto above = cornerRadiusPanelLayout(
        shapeOptionsLayout({100, 540}, 20), {0, 0, 800, 600});
    CHECK(above.panel.y == 502.0F);
}

void testTwoRowDefaultLayoutUsesExactMacDips()
{
    const auto layout = shapeOptionsLayout({100, 200}, 20);
    CHECK((layout.toolbar == AnnotationRect{100, 200, 533, 40}));
    CHECK(layout.strokeWidths.size() == 3U);
    CHECK((layout.strokeWidths[0] == AnnotationRect{110, 210, 20, 20}));
    CHECK((layout.strokeWidthHits[0] == AnnotationRect{107, 205, 26, 30}));
    CHECK((layout.fillToggle == AnnotationRect{190, 210, 20, 20}));
    CHECK((layout.rectangleMode == AnnotationRect{230, 210, 26, 20}));
    CHECK((layout.rectangleDisclosure == AnnotationRect{247, 222, 12, 12}));
    CHECK((layout.ellipseMode == AnnotationRect{262, 210, 22, 20}));
    CHECK((layout.strokeStyle == AnnotationRect{304, 210, 102, 20}));
    CHECK((layout.strokeStyleSampleStart == AnnotationPoint{314, 220}));
    CHECK((layout.strokeStyleSampleEnd == AnnotationPoint{384, 220}));
    CHECK((layout.strokeStyleDisclosure == AnnotationRect{390, 218, 7, 5}));
    CHECK(layout.colorSwatches.size() == 21U);
    CHECK((layout.colorSwatches[0] == AnnotationRect{429, 205, 12, 12}));
    CHECK((layout.colorSwatches[10] == AnnotationRect{429, 221, 12, 12}));
    CHECK((layout.colorSwatches[20] == AnnotationRect{591, 204, 32, 32}));
    CHECK(layout.separators.size() == 3U);
    CHECK((layout.separators[0] == AnnotationRect{220.25F, 214, 1.5F, 12}));
    CHECK((layout.separators[1] == AnnotationRect{295.25F, 214, 1.5F, 12}));
    CHECK((layout.separators[2] == AnnotationRect{417.25F, 214, 1.5F, 12}));
}

void testOneRowAndClampedPaletteLayouts()
{
    const auto ten = shapeOptionsLayout({}, 10);
    CHECK((ten.toolbar == AnnotationRect{0, 0, 521, 30}));
    CHECK((ten.colorSwatches[0] == AnnotationRect{329, 9, 12, 12}));
    CHECK((ten.colorSwatches[10] == AnnotationRect{491, 5, 20, 20}));

    const auto minimum = shapeOptionsLayout({}, 0);
    CHECK(minimum.paletteCount == 4U);
    CHECK((minimum.toolbar == AnnotationRect{0, 0, 425, 30}));

    const auto maximum = shapeOptionsLayout({}, 99);
    CHECK(maximum.paletteCount == 20U);
    CHECK((maximum.toolbar == AnnotationRect{0, 0, 533, 40}));
}

void testSharedHitGeometryAndMenus()
{
    const auto layout = shapeOptionsLayout({}, 20);
    CHECK((shapeOptionHitTest(layout, {8, 20})
        == ShapeOptionHit{ShapeOptionControl::strokeWidth, 0}));
    CHECK((shapeOptionHitTest(layout, {91, 20})
        == ShapeOptionHit{ShapeOptionControl::fillToggle, 0}));
    CHECK((shapeOptionHitTest(layout, {131, 20})
        == ShapeOptionHit{ShapeOptionControl::rectangleMode, 0}));
    CHECK((shapeOptionHitTest(layout, {151, 32})
        == ShapeOptionHit{ShapeOptionControl::cornerRadiusDisclosure, 0}));
    CHECK((shapeOptionHitTest(layout, {164, 20})
        == ShapeOptionHit{ShapeOptionControl::ellipseMode, 0}));
    CHECK((shapeOptionHitTest(layout, {205, 20})
        == ShapeOptionHit{ShapeOptionControl::strokeStyle, 0}));
    CHECK((shapeOptionHitTest(layout, {330, 5})
        == ShapeOptionHit{ShapeOptionControl::palette, 0}));
    CHECK((shapeOptionHitTest(layout, {492, 20})
        == ShapeOptionHit{ShapeOptionControl::customColor, 20}));
    CHECK(!shapeOptionHitTest(layout, {700, 20}).has_value());

    const auto menu = strokePatternMenuLayout({10, 20, 102, 152});
    CHECK(menu.items.size() == 6U);
    CHECK((menu.items[0] == AnnotationRect{14, 24, 94, 20}));
    CHECK((menu.items[5] == AnnotationRect{14, 144, 94, 20}));
    CHECK((menu.sampleStarts[0] == AnnotationPoint{24, 34}));
    CHECK((menu.sampleEnds[0] == AnnotationPoint{98, 34}));
    CHECK(hitTestStrokePatternMenu(menu, {20, 150}) == 5U);
}

} // namespace

int main()
{
    testMacPaletteAndActivationDefaults();
    testStateMutationsMatchMacControls();
    testCornerRadiusPanelUsesExactMacGeometry();
    testTwoRowDefaultLayoutUsesExactMacDips();
    testOneRowAndClampedPaletteLayouts();
    testSharedHitGeometryAndMenus();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
