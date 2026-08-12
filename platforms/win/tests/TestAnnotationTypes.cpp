#include "annotation/AnnotationTypes.h"

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

constexpr AnnotationColor macDefaultRed{245, 34, 45, 255};

void testDefaultStyleMatchesMac()
{
    const AnnotationStyle defaultStyle{};
    CHECK(defaultStyle.strokeColor == macDefaultRed);
    CHECK(defaultStyle.strokeWidthDip == 3.0F);
    CHECK(defaultStyle.strokePattern == AnnotationStrokePattern::solid);
    CHECK(!defaultStyle.fillEnabled);
    CHECK(defaultStyle.fillColor == macDefaultRed);
    CHECK(defaultStyle.cornerRadiusDip == 0.0F);
    CHECK(defaultStyle.textSize == 8.0F);
    CHECK(defaultStyle.textFontFamily == L"Microsoft YaHei");
}

void testGeometryStandardization()
{
    CHECK((standardized(AnnotationRect{20, 30, -8, -12})
        == AnnotationRect{12, 18, 8, 12}));
    CHECK((standardized(AnnotationRect{1, 2, 3, 4})
        == AnnotationRect{1, 2, 3, 4}));
    CHECK((translated(AnnotationRect{1, 2, 3, 4}, {5, -2})
        == AnnotationRect{6, 0, 3, 4}));
    const ArrowLine line{
        {10, 20}, {90, 60}, {40, 5},
        ArrowType::dot, ArrowType::normal};
    const auto moved = translated(line, {7, -3});
    CHECK((moved.start == AnnotationPoint{17, 17}));
    CHECK((moved.end == AnnotationPoint{97, 57}));
    CHECK((moved.control == AnnotationPoint{47, 2}));
    CHECK(moved.startArrowType == ArrowType::dot);
    CHECK(moved.endArrowType == ArrowType::normal);
    const MarkerLine marker{{4, 8}, {20, 30}};
    CHECK((markerLineBounds(marker) == AnnotationRect{4, 8, 16, 22}));
    CHECK((translated(marker, {-2, 5})
        == MarkerLine{{2, 13}, {18, 35}}));
}

void testPrimaryShapeActivationMatchesMac()
{
    AnnotationStyle previous;
    previous.strokeWidthDip = 7.0F;
    previous.cornerRadiusDip = 22.0F;
    previous.fillEnabled = true;

    const auto activated = primaryShapeActivationStyle(previous);
    CHECK(activated.strokeWidthDip == 4.0F);
    CHECK(activated.cornerRadiusDip == 5.0F);
    CHECK(activated.fillEnabled);
    CHECK(activated.strokeColor == previous.strokeColor);
    CHECK(activated.fillColor == previous.fillColor);
}

void testShapeAnnotationKeepsStablePortableState()
{
    ShapeAnnotation annotation{
        42,
        AnnotationKind::ellipse,
        {10, 20, 80, 40},
        primaryShapeActivationStyle({}),
        15.0F,
    };
    CHECK(annotation.id == 42);
    CHECK(annotation.kind == AnnotationKind::ellipse);
    CHECK((annotation.rect == AnnotationRect{10, 20, 80, 40}));
    CHECK(annotation.rotationDegrees == 15.0F);
}

void testAnnotationScalingTransformsAllGeometry()
{
    ShapeAnnotation annotation;
    annotation.rect = {2, 3, 10, 20};
    annotation.style.strokeWidthDip = 4.0F;
    annotation.style.cornerRadiusDip = 6.0F;
    annotation.style.textSize = 8.0F;
    annotation.arrowLine = ArrowLine{{1, 2}, {3, 4}, {5, 6}};
    annotation.brushPath = BrushPath{{{7, 8}, {9, 10}}};
    annotation.markerLine = MarkerLine{{11, 12}, {13, 14}};
    annotation.mosaicStroke = MosaicStroke{{{15, 16}, {17, 18}}};

    const auto result = scaled(std::move(annotation), 2.0F, 3.0F);
    CHECK((result.rect == AnnotationRect{4, 9, 20, 60}));
    CHECK(result.style.strokeWidthDip == 10.0F);
    CHECK(result.style.cornerRadiusDip == 15.0F);
    CHECK(result.style.textSize == 20.0F);
    CHECK((result.arrowLine->start == AnnotationPoint{2, 6}));
    CHECK((result.arrowLine->end == AnnotationPoint{6, 12}));
    CHECK((result.arrowLine->control == AnnotationPoint{10, 18}));
    CHECK((result.brushPath->points[1] == AnnotationPoint{18, 30}));
    CHECK((result.markerLine->end == AnnotationPoint{26, 42}));
    CHECK((result.mosaicStroke->points[1] == AnnotationPoint{34, 54}));

    EraserMask mask{{2, 3, 10, 20}, {4, 5}};
    const auto scaledMask = scaled(std::move(mask), 2.0F, 3.0F);
    CHECK((scaledMask.rect == AnnotationRect{4, 9, 20, 60}));
    CHECK(scaledMask.affectedAnnotationIds
        == std::vector<AnnotationId>({4, 5}));
}

} // namespace

int main()
{
    testDefaultStyleMatchesMac();
    testGeometryStandardization();
    testPrimaryShapeActivationMatchesMac();
    testShapeAnnotationKeepsStablePortableState();
    testAnnotationScalingTransformsAllGeometry();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
