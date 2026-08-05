#include "overlay/SelectionModel.h"

#include <array>
#include <cstdint>
#include <iostream>
#include <limits>

namespace {

using snipory::core::portable::PixelPoint;
using snipory::core::portable::PixelRect;
using xxsnap::win::SelectionHandle;
using xxsnap::win::SelectionModel;
using xxsnap::win::SelectionPhase;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

SelectionModel readyModel(PixelRect bounds, PixelPoint anchor, PixelPoint pointer)
{
    SelectionModel model(bounds);
    model.beginCreation(anchor);
    model.updateInteraction(pointer);
    model.finishInteraction();
    CHECK(model.phase() == SelectionPhase::ready);
    return model;
}

void testCreationUsesPhysicalVirtualDesktopCoordinates()
{
    struct CreationCase {
        PixelPoint anchor;
        PixelPoint pointer;
    };
    constexpr std::array cases{
        CreationCase{{-1800, -100}, {200, 800}},
        CreationCase{{200, 800}, {-1800, -100}},
        CreationCase{{-1800, 800}, {200, -100}},
        CreationCase{{200, -100}, {-1800, 800}},
    };
    constexpr PixelRect expected{-1800, -100, 2000, 900};

    for (const auto& testCase : cases) {
        SelectionModel model(PixelRect{-1920, -200, 3840, 1280});
        CHECK(model.phase() == SelectionPhase::empty);
        CHECK(!model.selection().has_value());

        model.beginCreation(testCase.anchor);
        CHECK(model.phase() == SelectionPhase::creating);
        model.updateInteraction(testCase.pointer);
        CHECK(model.selection() == expected);

        model.finishInteraction();
        CHECK(model.phase() == SelectionPhase::ready);
        CHECK(model.selection() == expected);
    }
}

void testCreationClampsToVirtualBounds()
{
    auto model = readyModel(
        PixelRect{-100, -50, 300, 200},
        PixelPoint{-500, -500},
        PixelPoint{500, 500});
    CHECK((model.selection() == PixelRect{-100, -50, 300, 200}));
}

void testClickAndOneAxisMovementDoNotCreateASelection()
{
    for (const auto pointer : {PixelPoint{10, 10}, PixelPoint{11, 10}, PixelPoint{10, 11}}) {
        SelectionModel model(PixelRect{0, 0, 100, 100});
        model.beginCreation(PixelPoint{10, 10});
        model.updateInteraction(pointer);
        model.finishInteraction();
        CHECK(model.phase() == SelectionPhase::empty);
        CHECK(!model.selection().has_value());
    }
}

void testOneByOnePhysicalPixelSelectionIsValid()
{
    auto model = readyModel(
        PixelRect{-20, -20, 40, 40}, PixelPoint{-1, -1}, PixelPoint{0, 0});
    CHECK((model.selection() == PixelRect{-1, -1, 1, 1}));
}

void testMovingPreservesSizeAndGrabOffsetWhileClamping()
{
    auto model = readyModel(
        PixelRect{-200, -100, 400, 300}, PixelPoint{-100, 10}, PixelPoint{-50, 50});

    CHECK(model.beginMove(PixelPoint{-90, 20}));
    CHECK(model.phase() == SelectionPhase::moving);
    CHECK(model.activeHandle() == SelectionHandle::body);

    model.updateInteraction(PixelPoint{-500, -500});
    CHECK((model.selection() == PixelRect{-200, -100, 50, 40}));

    model.updateInteraction(PixelPoint{500, 500});
    CHECK((model.selection() == PixelRect{150, 160, 50, 40}));

    model.finishInteraction();
    CHECK(model.phase() == SelectionPhase::ready);
    CHECK(model.activeHandle() == SelectionHandle::none);
}

void testMovingIsSafeNearIntegerLimits()
{
    constexpr auto minimum = std::numeric_limits<std::int64_t>::min();
    constexpr auto maximum = std::numeric_limits<std::int64_t>::max();
    auto model = readyModel(
        PixelRect{minimum + 10, minimum + 20, 100, 100},
        PixelPoint{minimum + 20, minimum + 30},
        PixelPoint{minimum + 40, minimum + 60});

    CHECK(model.beginMove(PixelPoint{minimum + 25, minimum + 35}));
    model.updateInteraction(PixelPoint{maximum, maximum});
    CHECK((model.selection()
        == PixelRect{minimum + 90, minimum + 90, 20, 30}));
}

struct ResizeCase {
    SelectionHandle handle;
    PixelPoint grabPoint;
    PixelPoint pointer;
    PixelRect expected;
};

void testAllEightResizeHandles()
{
    constexpr std::array cases{
        ResizeCase{SelectionHandle::north, {50, 20}, {50, 10}, {20, 10, 60, 50}},
        ResizeCase{SelectionHandle::northEast, {80, 20}, {90, 10}, {20, 10, 70, 50}},
        ResizeCase{SelectionHandle::east, {80, 40}, {90, 40}, {20, 20, 70, 40}},
        ResizeCase{SelectionHandle::southEast, {80, 60}, {90, 80}, {20, 20, 70, 60}},
        ResizeCase{SelectionHandle::south, {50, 60}, {50, 80}, {20, 20, 60, 60}},
        ResizeCase{SelectionHandle::southWest, {20, 60}, {10, 80}, {10, 20, 70, 60}},
        ResizeCase{SelectionHandle::west, {20, 40}, {10, 40}, {10, 20, 70, 40}},
        ResizeCase{SelectionHandle::northWest, {20, 20}, {10, 10}, {10, 10, 70, 50}},
    };

    for (const auto& testCase : cases) {
        auto model = readyModel(
            PixelRect{0, 0, 100, 100}, PixelPoint{20, 20}, PixelPoint{80, 60});
        CHECK(model.beginResize(testCase.handle, testCase.grabPoint));
        CHECK(model.phase() == SelectionPhase::resizing);
        CHECK(model.activeHandle() == testCase.handle);
        model.updateInteraction(testCase.pointer);
        CHECK(model.selection() == testCase.expected);
        model.finishInteraction();
        CHECK(model.phase() == SelectionPhase::ready);
    }
}

void testResizeHandlesFlipAfterCrossingOppositeEdges()
{
    struct FlipCase {
        SelectionHandle initial;
        PixelPoint grabPoint;
        PixelPoint pointer;
        PixelRect expectedRect;
        SelectionHandle expectedHandle;
    };

    constexpr std::array cases{
        FlipCase{SelectionHandle::east, {80, 40}, {10, 40}, {10, 20, 10, 40},
                 SelectionHandle::west},
        FlipCase{SelectionHandle::northWest, {20, 20}, {90, 80}, {80, 60, 10, 20},
                 SelectionHandle::southEast},
        FlipCase{SelectionHandle::northEast, {80, 20}, {10, 80}, {10, 60, 10, 20},
                 SelectionHandle::southWest},
        FlipCase{SelectionHandle::south, {50, 60}, {50, 10}, {20, 10, 60, 10},
                 SelectionHandle::north},
    };

    for (const auto& testCase : cases) {
        auto model = readyModel(
            PixelRect{0, 0, 100, 100}, PixelPoint{20, 20}, PixelPoint{80, 60});
        CHECK(model.beginResize(testCase.initial, testCase.grabPoint));
        model.updateInteraction(testCase.pointer);
        CHECK(model.selection() == testCase.expectedRect);
        CHECK(model.activeHandle() == testCase.expectedHandle);
    }
}

void testResizeMaintainsAtLeastOneByOnePixelAndClampsToBounds()
{
    auto minimumModel = readyModel(
        PixelRect{0, 0, 100, 100}, PixelPoint{20, 20}, PixelPoint{80, 60});
    CHECK(minimumModel.beginResize(SelectionHandle::southEast, PixelPoint{80, 60}));
    minimumModel.updateInteraction(PixelPoint{20, 20});
    CHECK((minimumModel.selection() == PixelRect{20, 20, 1, 1}));

    auto northwest = readyModel(
        PixelRect{0, 0, 100, 100}, PixelPoint{20, 20}, PixelPoint{80, 60});
    CHECK(northwest.beginResize(SelectionHandle::northWest, PixelPoint{20, 20}));
    northwest.updateInteraction(PixelPoint{-500, -500});
    CHECK((northwest.selection() == PixelRect{0, 0, 80, 60}));

    auto southeast = readyModel(
        PixelRect{0, 0, 100, 100}, PixelPoint{20, 20}, PixelPoint{80, 60});
    CHECK(southeast.beginResize(SelectionHandle::southEast, PixelPoint{80, 60}));
    southeast.updateInteraction(PixelPoint{500, 500});
    CHECK((southeast.selection() == PixelRect{20, 20, 80, 80}));
}

void testHitTestingPrioritizesAllHandlesOverBody()
{
    auto model = readyModel(
        PixelRect{0, 0, 200, 200}, PixelPoint{10, 20}, PixelPoint{110, 100});

    struct HitCase {
        PixelPoint point;
        SelectionHandle expected;
    };
    constexpr std::array cases{
        HitCase{{10, 20}, SelectionHandle::northWest},
        HitCase{{60, 20}, SelectionHandle::north},
        HitCase{{110, 20}, SelectionHandle::northEast},
        HitCase{{110, 60}, SelectionHandle::east},
        HitCase{{110, 100}, SelectionHandle::southEast},
        HitCase{{60, 100}, SelectionHandle::south},
        HitCase{{10, 100}, SelectionHandle::southWest},
        HitCase{{10, 60}, SelectionHandle::west},
        HitCase{{60, 60}, SelectionHandle::body},
        HitCase{{150, 150}, SelectionHandle::none},
    };

    for (const auto& testCase : cases) {
        CHECK(model.hitTest(testCase.point, 4) == testCase.expected);
    }
}

void testSelectionBodyUsesHalfOpenRectangleEdges()
{
    auto model = readyModel(
        PixelRect{0, 0, 100, 100}, PixelPoint{10, 10}, PixelPoint{50, 50});

    CHECK(model.hitTest(PixelPoint{50, 31}, 0) == SelectionHandle::none);
    CHECK(model.hitTest(PixelPoint{31, 50}, 0) == SelectionHandle::none);

    CHECK(model.hitTest(PixelPoint{50, 30}, 0) == SelectionHandle::east);
    CHECK(model.hitTest(PixelPoint{30, 50}, 0) == SelectionHandle::south);

    auto rightMove = readyModel(
        PixelRect{0, 0, 100, 100}, PixelPoint{10, 10}, PixelPoint{50, 50});
    auto bottomMove = readyModel(
        PixelRect{0, 0, 100, 100}, PixelPoint{10, 10}, PixelPoint{50, 50});
    CHECK(!rightMove.beginMove(PixelPoint{50, 31}));
    CHECK(!bottomMove.beginMove(PixelPoint{31, 50}));
}

void testOverlappingHandlesChooseTheNearestAnchor()
{
    auto onePixel = readyModel(
        PixelRect{0, 0, 100, 100}, PixelPoint{10, 10}, PixelPoint{11, 11});
    struct CornerCase {
        PixelPoint point;
        SelectionHandle expected;
    };
    constexpr std::array corners{
        CornerCase{{10, 10}, SelectionHandle::northWest},
        CornerCase{{11, 10}, SelectionHandle::northEast},
        CornerCase{{11, 11}, SelectionHandle::southEast},
        CornerCase{{10, 11}, SelectionHandle::southWest},
    };
    for (const auto& testCase : corners) {
        CHECK(onePixel.hitTest(testCase.point, 4) == testCase.expected);
    }

    auto overlapping = readyModel(
        PixelRect{0, 0, 100, 100}, PixelPoint{10, 10}, PixelPoint{16, 16});
    CHECK(overlapping.hitTest(PixelPoint{13, 12}, 4) == SelectionHandle::north);
}

constexpr std::int64_t callerPhysicalRadius(std::int64_t dips, std::uint32_t dpi)
{
    return (dips * static_cast<std::int64_t>(dpi) + 48) / 96;
}

void testSelectionCoordinatesAreDpiIndependent()
{
    constexpr std::array<std::uint32_t, 3> dpis{96U, 144U, 192U};
    constexpr PixelRect expected{-120, -30, 200, 100};

    for (const auto dpi : dpis) {
        auto model = readyModel(
            PixelRect{-500, -300, 1000, 600},
            PixelPoint{-120, -30},
            PixelPoint{80, 70});
        CHECK(model.selection() == expected);

        const auto radius = callerPhysicalRadius(4, dpi);
        CHECK(radius == (dpi == 96U ? 4 : dpi == 144U ? 6 : 8));
        CHECK(model.hitTest(PixelPoint{-114, 20}, radius)
            == (dpi == 96U ? SelectionHandle::body : SelectionHandle::west));
        CHECK(model.selection() == expected);
    }
}

void testInvalidInteractionsLeaveReadySelectionUnchanged()
{
    auto model = readyModel(
        PixelRect{0, 0, 100, 100}, PixelPoint{10, 10}, PixelPoint{50, 50});
    CHECK(!model.beginResize(SelectionHandle::none, PixelPoint{10, 10}));
    CHECK(!model.beginResize(SelectionHandle::body, PixelPoint{20, 20}));
    CHECK(!model.beginMove(PixelPoint{99, 99}));
    CHECK(model.phase() == SelectionPhase::ready);
    CHECK((model.selection() == PixelRect{10, 10, 40, 40}));
}

} // namespace

int main()
{
    testCreationUsesPhysicalVirtualDesktopCoordinates();
    testCreationClampsToVirtualBounds();
    testClickAndOneAxisMovementDoNotCreateASelection();
    testOneByOnePhysicalPixelSelectionIsValid();
    testMovingPreservesSizeAndGrabOffsetWhileClamping();
    testMovingIsSafeNearIntegerLimits();
    testAllEightResizeHandles();
    testResizeHandlesFlipAfterCrossingOppositeEdges();
    testResizeMaintainsAtLeastOneByOnePixelAndClampsToBounds();
    testHitTestingPrioritizesAllHandlesOverBody();
    testSelectionBodyUsesHalfOpenRectangleEdges();
    testOverlappingHandlesChooseTheNearestAnchor();
    testSelectionCoordinatesAreDpiIndependent();
    testInvalidInteractionsLeaveReadySelectionUnchanged();

    return failureCount == 0 ? 0 : 1;
}
