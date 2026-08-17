#pragma once

#include "annotation/AnnotationTypes.h"

#include <d2d1.h>
#include <dwrite.h>

#include <cstddef>
#include <optional>

namespace xxsnap::win {

inline constexpr float textDisplayScale = 3.0F;
inline constexpr float textHorizontalPaddingDip = 8.0F;
inline constexpr float textCaretWidthDip = 1.0F;

AnnotationRect measuredTextRect(
    AnnotationPoint anchor,
    const std::wstring& text,
    const AnnotationStyle& style) noexcept;

AnnotationRect textCaretRect(
    const ShapeAnnotation& annotation,
    std::size_t textPosition) noexcept;

std::optional<std::size_t> textPositionAtPoint(
    const ShapeAnnotation& annotation,
    AnnotationPoint unrotatedPoint) noexcept;

HRESULT drawTextAnnotation(
    ID2D1Factory* d2dFactory,
    IDWriteFactory* dwriteFactory,
    ID2D1RenderTarget* renderTarget,
    const ShapeAnnotation& annotation) noexcept;

} // namespace xxsnap::win
