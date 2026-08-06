#pragma once

#include "toolbar/ToolbarCatalog.h"

#include <array>
#include <optional>
#include <vector>

namespace xxsnap::win {

class ToolbarState {
public:
    ToolbarState() noexcept;

    std::vector<ToolbarAction> visibleActions() const;
    bool isVisible(ToolbarAction action) const noexcept;
    bool isEnabled(ToolbarAction action) const noexcept;
    std::optional<ToolbarAction> selectedAction() const noexcept;

    void setCapability(ToolbarAction action, bool available) noexcept;
    void setHistoryAvailability(bool canUndo, bool canRedo) noexcept;
    bool selectTool(ToolbarAction action) noexcept;

private:
    static constexpr std::size_t indexOf(ToolbarAction action) noexcept
    {
        return static_cast<std::size_t>(action);
    }

    static constexpr bool isSelectableTool(ToolbarAction action) noexcept
    {
        return action <= ToolbarAction::scroll;
    }

    std::array<bool, fullToolbarActions().size()> capabilities_{};
    std::optional<ToolbarAction> selectedAction_;
    bool canUndo_ = false;
    bool canRedo_ = false;
};

} // namespace xxsnap::win
