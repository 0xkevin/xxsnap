#include "overlay/Eyedropper.h"

#include <algorithm>
#include <cmath>
#include <cwchar>

namespace xxsnap::win {

EyedropperPanelLayout eyedropperPanelLayout(
    AnnotationPoint pointer,
    AnnotationRect safeBounds) noexcept
{
    constexpr float width = 184.0F;
    constexpr float height = 188.0F;
    constexpr float magnifierHeight = 96.0F;
    constexpr float gap = 14.0F;
    constexpr float safeInset = 8.0F;
    safeBounds = standardized(safeBounds);
    const AnnotationRect safe{
        safeBounds.x + safeInset,
        safeBounds.y + safeInset,
        (std::max)(0.0F, safeBounds.width - safeInset * 2.0F),
        (std::max)(0.0F, safeBounds.height - safeInset * 2.0F),
    };
    AnnotationRect panel{pointer.x + gap, pointer.y + gap, width, height};
    if (panel.x + panel.width > safe.x + safe.width) {
        panel.x = pointer.x - gap - width;
    }
    if (panel.y + panel.height > safe.y + safe.height) {
        panel.y = pointer.y - gap - height;
    }
    panel.x = (std::max)(safe.x, (std::min)(
        panel.x, safe.x + safe.width - panel.width));
    panel.y = (std::max)(safe.y, (std::min)(
        panel.y, safe.y + safe.height - panel.height));
    return {
        panel,
        {panel.x, panel.y, panel.width, magnifierHeight},
        {panel.x, panel.y + magnifierHeight,
            panel.width, panel.height - magnifierHeight},
    };
}

std::wstring eyedropperColorText(
    AnnotationColor color,
    EyedropperCopyMode mode)
{
    wchar_t text[32]{};
    if (mode == EyedropperCopyMode::rgb) {
        std::swprintf(text, 32U, L"%u, %u, %u",
            color.red, color.green, color.blue);
    } else {
        std::swprintf(text, 32U, L"#%02X%02X%02X",
            color.red, color.green, color.blue);
    }
    return text;
}

int eyedropperPixelLength(
    AnnotationPoint start,
    AnnotationPoint end) noexcept
{
    return static_cast<int>(std::round(std::hypot(
        end.x - start.x, end.y - start.y)));
}

} // namespace xxsnap::win
