#pragma once

#include "annotation/AnnotationTypes.h"

#include <array>
#include <cstddef>
#include <optional>

namespace xxsnap::win {

inline constexpr float numberMinimumSize = 1.0F;
inline constexpr float numberMaximumSize = 72.0F;
inline constexpr float numberDefaultSize = 3.0F;
inline constexpr int numberMinimumValue = 1;
inline constexpr int numberMaximumValue = 999;

struct NumberMarkTypeDescriptor {
    NumberMarkType type;
    const wchar_t* glyph;
    AnnotationColor defaultColor;
};

inline constexpr std::array<NumberMarkTypeDescriptor, 3> numberMarkTypes{{
    {NumberMarkType::number, L"1", {255, 59, 48, 255}},
    {NumberMarkType::check, L"✓", {52, 199, 89, 255}},
    {NumberMarkType::cross, L"×", {255, 59, 48, 255}},
}};

constexpr std::optional<std::size_t> numberMarkTypeIndex(
    NumberMarkType type) noexcept
{
    for (std::size_t index = 0; index < numberMarkTypes.size(); ++index) {
        if (numberMarkTypes[index].type == type) return index;
    }
    return std::nullopt;
}

enum class NumberHandleKind : std::uint8_t {
    deleteHandle,
    resize,
    increment,
    decrement,
    reset,
};

inline constexpr std::array<float, 20> numberSizeValues{
    1.0F, 2.0F, 3.0F, 4.0F, 5.0F, 6.0F, 7.0F, 8.0F, 9.0F, 10.0F,
    12.0F, 14.0F, 16.0F, 20.0F, 24.0F, 32.0F, 40.0F, 48.0F, 60.0F, 72.0F,
};

inline constexpr std::array<float, 20> numberMarkDiameters{
    15.0F, 18.0F, 21.0F, 24.0F, 27.0F, 30.0F, 33.0F, 36.0F, 38.0F, 41.0F,
    47.0F, 47.0F, 54.0F, 70.0F, 82.0F, 105.0F, 128.0F, 152.0F, 186.0F, 221.0F,
};

constexpr float clampedNumberSize(float size) noexcept
{
    return size < numberMinimumSize ? numberMinimumSize
        : size > numberMaximumSize ? numberMaximumSize : size;
}

constexpr int clampedNumberValue(int value) noexcept
{
    return value < numberMinimumValue ? numberMinimumValue
        : value > numberMaximumValue ? numberMaximumValue : value;
}

constexpr float numberMarkDiameter(float size) noexcept
{
    size = clampedNumberSize(size);
    for (std::size_t index = 0; index < numberSizeValues.size(); ++index) {
        if (size == numberSizeValues[index]) {
            return numberMarkDiameters[index];
        }
        if (index + 1U < numberSizeValues.size()
            && size > numberSizeValues[index]
            && size < numberSizeValues[index + 1U]) {
            const auto progress = (size - numberSizeValues[index])
                / (numberSizeValues[index + 1U] - numberSizeValues[index]);
            return numberMarkDiameters[index]
                + (numberMarkDiameters[index + 1U]
                    - numberMarkDiameters[index]) * progress;
        }
    }
    return numberMarkDiameters.back();
}

constexpr float numberMarkTextSize(float size) noexcept
{
    const auto scaled = numberMarkDiameter(size) * 0.72F;
    return scaled < 7.0F ? 7.0F : scaled;
}

constexpr AnnotationRect numberMarkRect(
    AnnotationPoint center,
    float size) noexcept
{
    const auto diameter = numberMarkDiameter(size);
    return {
        center.x - diameter / 2.0F,
        center.y - diameter / 2.0F,
        diameter,
        diameter,
    };
}

constexpr AnnotationRect numberOutlineRect(AnnotationRect rect) noexcept
{
    rect = standardized(rect);
    return {rect.x - 4.0F, rect.y - 4.0F,
        rect.width + 8.0F, rect.height + 8.0F};
}

inline std::optional<AnnotationRect> numberHandleRect(
    const ShapeAnnotation& annotation,
    NumberHandleKind kind) noexcept
{
    if (!isNumberAnnotation(annotation)) {
        return std::nullopt;
    }
    const auto outline = numberOutlineRect(annotation.rect);
    const auto size = kind == NumberHandleKind::deleteHandle ? 15.0F
        : kind == NumberHandleKind::resize ? 7.5F : 12.0F;
    const auto outsideLeftCenterX = outline.x - size / 2.0F - 2.0F;
    AnnotationPoint center{};
    switch (kind) {
    case NumberHandleKind::deleteHandle:
        center = {outline.x + outline.width, outline.y};
        break;
    case NumberHandleKind::resize:
        center = {outline.x + outline.width, outline.y + outline.height};
        break;
    case NumberHandleKind::increment:
        if (annotation.numberMarkType != NumberMarkType::number) {
            return std::nullopt;
        }
        center = {outsideLeftCenterX, outline.y};
        break;
    case NumberHandleKind::decrement:
        if (annotation.numberMarkType != NumberMarkType::number) {
            return std::nullopt;
        }
        center = {outsideLeftCenterX, outline.y + size};
        break;
    case NumberHandleKind::reset:
        if (annotation.numberMarkType != NumberMarkType::number
            || annotation.numberSequenceIndex.value_or(1) <= 1) {
            return std::nullopt;
        }
        center = {outsideLeftCenterX, outline.y + outline.height};
        break;
    }
    return AnnotationRect{
        center.x - size / 2.0F,
        center.y - size / 2.0F,
        size,
        size,
    };
}

} // namespace xxsnap::win
