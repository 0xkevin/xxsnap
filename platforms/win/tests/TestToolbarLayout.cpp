#include "toolbar/ToolbarLayout.h"

#include <cstdlib>
#include <iostream>
#include <vector>

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

template <typename Container>
std::vector<ToolbarAction> vectorOf(const Container& actions)
{
    return {actions.begin(), actions.end()};
}

void testExactMacToolbarGeometry()
{
    CHECK(toolbarWidth(vectorOf(terminalToolbarActions())) == 135.0F);
    CHECK(toolbarWidth(vectorOf(fullToolbarActions())) == 551.0F);

    const auto layout = computeMainToolbarLayout(
        {10.0F, 20.0F}, vectorOf(fullToolbarActions()));
    CHECK((layout.bounds == ToolbarRect{10.0F, 20.0F, 551.0F, 28.0F}));
    CHECK((layout.leadingDragHandle == ToolbarRect{13.0F, 24.0F, 20.0F, 20.0F}));
    CHECK((layout.items.front().rect == ToolbarRect{37.0F, 24.0F, 20.0F, 20.0F}));
    CHECK(layout.items[10].rect.x - layout.items[9].rect.x == 36.0F);
    CHECK(layout.items[11].rect.x - layout.items[10].rect.x == 36.0F);
    CHECK(layout.items[13].rect.x - layout.items[12].rect.x == 36.0F);
    CHECK((layout.trailingDragHandle == ToolbarRect{533.0F, 24.0F, 20.0F, 20.0F}));
}

void testTeachingPenToolbarMatchesMacCompactGeometry()
{
    const auto layout = computeTeachingPenToolbarLayout(
        {360.0F, 420.0F}, {0.0F, 0.0F, 800.0F, 600.0F});
    CHECK((layout.bounds == ToolbarRect{366.0F, 218.0F, 56.0F, 196.0F}));
    CHECK(layout.items.size() == teachingPenToolbarActions().size());
    CHECK((layout.items[0].rect == ToolbarRect{370.0F, 222.0F, 20.0F, 20.0F}));
    CHECK((layout.items[1].rect == ToolbarRect{398.0F, 222.0F, 20.0F, 20.0F}));
    CHECK((layout.items[10].rect == ToolbarRect{370.0F, 362.0F, 20.0F, 20.0F}));
    CHECK((layout.items[11].rect == ToolbarRect{398.0F, 362.0F, 20.0F, 20.0F}));
    CHECK((layout.items[12].rect == ToolbarRect{384.0F, 390.0F, 20.0F, 20.0F}));
    CHECK(layout.teachingPenActionSeparator
        == std::optional<ToolbarRect>(ToolbarRect{373.0F, 357.0F, 42.0F, 1.0F}));

    const auto corner = computeTeachingPenToolbarLayout(
        {796.0F, 596.0F}, {0.0F, 0.0F, 800.0F, 600.0F});
    CHECK((corner.bounds == ToolbarRect{734.0F, 394.0F, 56.0F, 196.0F}));
}

void testHitTestingUsesButtonRectsOnly()
{
    const auto layout = computeMainToolbarLayout(
        {10.0F, 20.0F}, vectorOf(fullToolbarActions()));
    for (const auto& item : layout.items) {
        const ToolbarPoint center{
            item.rect.x + item.rect.width / 2.0F,
            item.rect.y + item.rect.height / 2.0F,
        };
        CHECK(toolbarActionAt(layout, center) == item.action);
    }

    CHECK(!toolbarActionAt(layout, {20.0F, 30.0F}).has_value());
    CHECK(!toolbarActionAt(layout, {552.0F, 30.0F}).has_value());
    CHECK(!toolbarActionAt(layout, {324.0F, 30.0F}).has_value());
    CHECK(!toolbarActionAt(layout, {10.0F, 20.0F}).has_value());
}

} // namespace

int main()
{
    testExactMacToolbarGeometry();
    testTeachingPenToolbarMatchesMacCompactGeometry();
    testHitTestingUsesButtonRectsOnly();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
