#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include "annotation/NumberAnnotationMetrics.h"

#include <Windows.h>
#include <d2d1.h>
#include <dwrite.h>

#include <cstddef>
#include <optional>
#include <string>

namespace xxsnap::win {

AnnotationColor readableNumberForeground(
    AnnotationColor background) noexcept;
AnnotationRect numberCaretRect(
    const ShapeAnnotation& annotation,
    std::size_t caretPosition,
    const std::optional<std::wstring>& draftText = std::nullopt) noexcept;
HRESULT drawNumberAnnotation(
    IDWriteFactory* factory,
    ID2D1RenderTarget* renderTarget,
    const ShapeAnnotation& annotation,
    const std::optional<std::wstring>& draftText = std::nullopt) noexcept;

} // namespace xxsnap::win
