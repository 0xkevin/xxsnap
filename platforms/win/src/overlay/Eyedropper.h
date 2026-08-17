#pragma once

#include "annotation/AnnotationTypes.h"

#include <string>

namespace xxsnap::win {

enum class EyedropperCopyMode : std::uint8_t {
    hex,
    rgb,
};

struct EyedropperPanelLayout {
    AnnotationRect panel{};
    AnnotationRect magnifier{};
    AnnotationRect info{};
};

EyedropperPanelLayout eyedropperPanelLayout(
    AnnotationPoint pointer,
    AnnotationRect safeBounds) noexcept;
std::wstring eyedropperColorText(
    AnnotationColor color,
    EyedropperCopyMode mode);
int eyedropperPixelLength(
    AnnotationPoint start,
    AnnotationPoint end) noexcept;

} // namespace xxsnap::win
