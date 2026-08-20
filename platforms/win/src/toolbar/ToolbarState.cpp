#include "toolbar/ToolbarState.h"

namespace xxsnap::win {

ToolbarState::ToolbarState() noexcept
{
    for (const auto action : terminalToolbarActions()) {
        capabilities_[indexOf(action)] = true;
    }
    capabilities_[indexOf(ToolbarAction::clearAll)] = true;
}

std::vector<ToolbarAction> ToolbarState::visibleActions() const
{
    std::vector<ToolbarAction> actions;
    actions.reserve(fullToolbarActions().size());
    for (const auto action : fullToolbarActions()) {
        if (isVisible(action)) {
            actions.push_back(action);
        }
    }
    return actions;
}

bool ToolbarState::isVisible(ToolbarAction action) const noexcept
{
    return capabilities_[indexOf(action)];
}

bool ToolbarState::isEnabled(ToolbarAction action) const noexcept
{
    if (!isVisible(action)) {
        return false;
    }
    if (action == ToolbarAction::undo) {
        return canUndo_;
    }
    if (action == ToolbarAction::redo) {
        return canRedo_;
    }
    return true;
}

std::optional<ToolbarAction> ToolbarState::selectedAction() const noexcept
{
    return selectedAction_;
}

void ToolbarState::setCapability(
    ToolbarAction action,
    bool available) noexcept
{
    capabilities_[indexOf(action)] = available;
    if (!available && selectedAction_ == action) {
        selectedAction_.reset();
    }
}

void ToolbarState::setHistoryAvailability(bool canUndo, bool canRedo) noexcept
{
    canUndo_ = canUndo;
    canRedo_ = canRedo;
}

bool ToolbarState::selectTool(ToolbarAction action) noexcept
{
    if (!isVisible(action) || !isSelectableTool(action)) {
        return false;
    }
    selectedAction_ = action;
    return true;
}

void ToolbarState::clearSelectedTool() noexcept
{
    selectedAction_.reset();
}

} // namespace xxsnap::win
