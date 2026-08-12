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
constexpr AnnotationStyle defaultStyle{};
static_assert(defaultStyle.strokeColor == macDefaultRed);
static_assert(defaultStyle.strokeWidthDip == 3.0F);
static_assert(defaultStyle.strokePattern == AnnotationStrokePattern::solid);
static_assert(!defaultStyle.fillEnabled);
static_assert(defaultStyle.fillColor == macDefaultRed);
static_assert(defaultStyle.cornerRadiusDip == 0.0F);

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

} // namespace

int main()
{
    testGeometryStandardization();
    testPrimaryShapeActivationMatchesMac();
    testShapeAnnotationKeepsStablePortableState();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
