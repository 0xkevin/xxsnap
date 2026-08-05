#pragma once

#include "capture/CaptureBackend.h"

#include <variant>

namespace xxsnap::win {

using SelectionCompositionResult = std::variant<PixelBuffer, CaptureError>;

// The selection is a positive-size, half-open rectangle in virtual-desktop
// physical pixels. Frozen displays are applied in order, so later displays
// overwrite earlier ones where their pixel bounds overlap.
SelectionCompositionResult composeSelection(
    PixelRect selection,
    const FrozenDesktop& desktop,
    MemoryBudget& budget) noexcept;

} // namespace xxsnap::win
