#pragma once

#include "annotation/AnnotationTypes.h"
#include "snipory/core/portable/Geometry.h"

#include <algorithm>
#include <cmath>
#include <cstdint>

namespace xxsnap::win
{

using snipory::core::portable::PixelRect;

struct LongImageEditorLayout
{
    PixelRect bounds{};
    double displayScale = 1.0;
    std::int64_t visibleSourceHeight = 0;
    std::int64_t maximumSourceOffset = 0;
};

inline PixelRect longImagePreviewBounds(PixelRect workArea,
                                        PixelRect selection,
                                        std::int64_t imageWidth,
                                        std::int64_t imageHeight,
                                        std::uint32_t dpiX,
                                        std::uint32_t dpiY) noexcept
{
    workArea = snipory::core::portable::standardized(workArea);
    selection = snipory::core::portable::standardized(selection);
    const auto scaleX = static_cast<double>(dpiX == 0U ? 96U : dpiX) / 96.0;
    const auto scaleY = static_cast<double>(dpiY == 0U ? 96U : dpiY) / 96.0;
    const auto maximumWidth = (std::max<std::int64_t>)(
        1, (std::min)(workArea.width,
                      static_cast<std::int64_t>(std::lround(300.0 * scaleX))));
    const auto maximumHeight = (std::max<std::int64_t>)(
        1, (std::min)(workArea.height,
                      static_cast<std::int64_t>(std::lround(480.0 * scaleY))));
    const auto previewScale = imageWidth > 0 && imageHeight > 0
        ? (std::min)({1.0,
                      static_cast<double>(maximumWidth) / imageWidth,
                      static_cast<double>(maximumHeight) / imageHeight})
        : 1.0;
    const auto width = (std::max<std::int64_t>)(
        1, static_cast<std::int64_t>(std::lround(imageWidth * previewScale)));
    const auto height = (std::max<std::int64_t>)(
        1, static_cast<std::int64_t>(std::lround(imageHeight * previewScale)));
    const auto gap = (std::max<std::int64_t>)(
        1, static_cast<std::int64_t>(std::lround(8.0 * scaleX)));
    auto x = selection.x + selection.width + gap;
    if (x + width > workArea.x + workArea.width) {
        x = selection.x - gap - width;
    }
    x = (std::max)(workArea.x,
                   (std::min)(x, workArea.x + workArea.width - width));
    auto y = selection.y;
    y = (std::max)(workArea.y,
                   (std::min)(y, workArea.y + workArea.height - height));
    return {x, y, width, height};
}

inline LongImageEditorLayout longImageEditorLayout(PixelRect workArea,
                                                   std::int64_t imageWidth,
                                                   std::int64_t imageHeight,
                                                   std::uint32_t dpiX,
                                                   std::uint32_t dpiY) noexcept
{
    workArea = snipory::core::portable::standardized(workArea);
    const auto scaleX = static_cast<double>(dpiX == 0U ? 96U : dpiX) / 96.0;
    const auto scaleY = static_cast<double>(dpiY == 0U ? 96U : dpiY) / 96.0;
    const auto maximumWidth =
        (std::max<std::int64_t>)(1, (std::min)(workArea.width,
                                               static_cast<std::int64_t>(
                                                   std::lround(1000.0 * scaleX))));
    const auto maximumHeight =
        (std::max<std::int64_t>)(1, (std::min)(workArea.height,
                                               static_cast<std::int64_t>(
                                                   std::lround(840.0 * scaleY))));
    const auto viewportWidth = imageWidth > 0
        ? (std::max<std::int64_t>)(1, (std::min)(maximumWidth, imageWidth))
        : maximumWidth;
    const auto displayScale = imageWidth > 0
        ? (std::min)(1.0, static_cast<double>(viewportWidth) / imageWidth)
        : 1.0;
    const auto viewportHeight =
        (std::max<std::int64_t>)(1, (std::min)(maximumHeight,
                                               static_cast<std::int64_t>(std::ceil(
                                                   imageHeight * displayScale))));
    LongImageEditorLayout result;
    result.bounds = {
        workArea.x + (workArea.width - viewportWidth) / 2,
        workArea.y + (workArea.height - viewportHeight) / 2,
        viewportWidth,
        viewportHeight,
    };
    result.displayScale = displayScale;
    result.visibleSourceHeight =
        (std::min)(imageHeight,
                   static_cast<std::int64_t>(
                       std::ceil(viewportHeight / (std::max)(displayScale, 0.0001))));
    result.maximumSourceOffset =
        (std::max<std::int64_t>)(0, imageHeight - result.visibleSourceHeight);
    return result;
}

inline std::int64_t clampedLongImageOffset(std::int64_t offset,
                                           const LongImageEditorLayout &layout) noexcept
{
    return (std::max<std::int64_t>)(0, (std::min)(offset, layout.maximumSourceOffset));
}

inline AnnotationPoint longImageAnnotationOrigin(std::int64_t sourceOffset,
                                                 std::uint32_t dpiY) noexcept
{
    return {0.0F, static_cast<float>(sourceOffset) * 96.0F /
                      static_cast<float>(dpiY == 0U ? 96U : dpiY)};
}

} // namespace xxsnap::win
