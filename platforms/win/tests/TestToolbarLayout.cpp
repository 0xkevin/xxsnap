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
    CHECK(toolbarWidth(vectorOf(terminalToolbarActions())) == 144.0F);
    CHECK(toolbarWidth(vectorOf(fullToolbarActions())) == 560.0F);

    const auto layout = computeMainToolbarLayout(
        {10.0F, 20.0F}, vectorOf(fullToolbarActions()));
    CHECK((layout.bounds == ToolbarRect{10.0F, 20.0F, 560.0F, 28.0F}));
    CHECK((layout.leadingDragHandle == ToolbarRect{14.0F, 24.0F, 20.0F, 20.0F}));
    CHECK((layout.items.front().rect == ToolbarRect{42.0F, 24.0F, 20.0F, 20.0F}));
    CHECK(layout.items[10].rect.x - layout.items[9].rect.x == 36.0F);
    CHECK(layout.items[11].rect.x - layout.items[10].rect.x == 36.0F);
    CHECK(layout.items[13].rect.x - layout.items[12].rect.x == 36.0F);
    CHECK((layout.trailingDragHandle == ToolbarRect{542.0F, 24.0F, 20.0F, 20.0F}));
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
    testHitTestingUsesButtonRectsOnly();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
