#include "toolbar/ToolbarState.h"

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

void testDefaultsExposeOnlyWorkingActions()
{
    ToolbarState state;
    CHECK(state.visibleActions() == vectorOf(terminalToolbarActions()));
    CHECK(!state.selectedAction().has_value());
    CHECK(state.isEnabled(ToolbarAction::cancel));
    CHECK(state.isEnabled(ToolbarAction::save));
    CHECK(state.isEnabled(ToolbarAction::copy));
    CHECK(!state.isVisible(ToolbarAction::rectangle));
    CHECK(!state.selectTool(ToolbarAction::cancel));
}

void testCapabilitiesStayInMacOrderAndControlSelection()
{
    ToolbarState state;
    state.setCapability(ToolbarAction::text, true);
    state.setCapability(ToolbarAction::rectangle, true);
    const std::vector expected{
        ToolbarAction::rectangle,
        ToolbarAction::text,
        ToolbarAction::cancel,
        ToolbarAction::save,
        ToolbarAction::copy,
    };
    CHECK(state.visibleActions() == expected);
    CHECK(state.selectTool(ToolbarAction::rectangle));
    CHECK(state.selectedAction() == ToolbarAction::rectangle);
    state.clearSelectedTool();
    CHECK(!state.selectedAction().has_value());
    CHECK(state.selectTool(ToolbarAction::rectangle));

    state.setCapability(ToolbarAction::rectangle, false);
    CHECK(!state.selectedAction().has_value());
    CHECK(!state.isVisible(ToolbarAction::rectangle));
}

void testHistoryActionsAreIndependent()
{
    ToolbarState state;
    state.setCapability(ToolbarAction::undo, true);
    state.setCapability(ToolbarAction::redo, true);
    state.setHistoryAvailability(true, false);
    CHECK(state.isEnabled(ToolbarAction::undo));
    CHECK(!state.isEnabled(ToolbarAction::redo));
    CHECK(!state.selectTool(ToolbarAction::undo));

    state.setHistoryAvailability(false, true);
    CHECK(!state.isEnabled(ToolbarAction::undo));
    CHECK(state.isEnabled(ToolbarAction::redo));
}

} // namespace

int main()
{
    testDefaultsExposeOnlyWorkingActions();
    testCapabilitiesStayInMacOrderAndControlSelection();
    testHistoryActionsAreIndependent();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
