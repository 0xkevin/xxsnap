#pragma once

#include "annotation/AnnotationTypes.h"
#include "annotation/NumberAnnotationMetrics.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <vector>

namespace xxsnap::win {

const std::array<AnnotationColor, 20>& macShapePalette() noexcept;
const std::array<AnnotationStrokePattern, 6>& macShapeStrokePatterns() noexcept;
const std::array<ArrowType, 7>& macArrowTypes() noexcept;
const std::array<float, 3>& macArrowStrokeWidths() noexcept;
const std::array<float, 3>& macBrushStrokeWidths() noexcept;
const std::array<AnnotationStrokePattern, 4>& macBrushStrokePatterns() noexcept;
const std::array<float, 3>& macMarkerStrokeWidths() noexcept;
const std::array<float, 3>& macMosaicStrokeWidths() noexcept;
const std::array<float, 3>& macMagnifierStrokeWidths() noexcept;

class ShapeOptionsState {
public:
    ShapeOptionsState() noexcept;

    AnnotationKind kind() const noexcept;
    const AnnotationStyle& style() const noexcept;
    std::optional<std::size_t> selectedPaletteIndex() const noexcept;

    bool load(AnnotationKind kind, AnnotationStyle style) noexcept;
    bool setKind(AnnotationKind kind) noexcept;
    bool setStrokeWidth(float strokeWidthDip) noexcept;
    bool setStrokePattern(AnnotationStrokePattern pattern) noexcept;
    bool toggleFill() noexcept;
    bool setCornerRadius(float cornerRadiusDip) noexcept;
    bool adjustCornerRadius(float deltaDip) noexcept;
    bool selectPalette(std::size_t index) noexcept;
    bool selectCustomColor(AnnotationColor color) noexcept;

private:
    void refreshPaletteSelection() noexcept;

    AnnotationKind kind_ = AnnotationKind::rectangle;
    AnnotationStyle style_{};
    std::optional<std::size_t> selectedPaletteIndex_;
};

class ArrowLineOptionsState {
public:
    ArrowLineOptionsState() noexcept;

    const AnnotationStyle& style() const noexcept;
    ArrowType startArrowType() const noexcept;
    ArrowType endArrowType() const noexcept;
    std::optional<std::size_t> selectedPaletteIndex() const noexcept;

    bool load(AnnotationStyle style, const ArrowLine& line) noexcept;
    bool setStrokeWidth(float strokeWidthDip) noexcept;
    bool setStrokePattern(AnnotationStrokePattern pattern) noexcept;
    bool selectArrowType(ArrowEndpoint endpoint, ArrowType type) noexcept;
    bool selectPalette(std::size_t index) noexcept;
    bool selectCustomColor(AnnotationColor color) noexcept;

private:
    void refreshPaletteSelection() noexcept;

    AnnotationStyle style_{};
    ArrowType startArrowType_ = ArrowType::none;
    ArrowType endArrowType_ = ArrowType::normal;
    std::optional<std::size_t> selectedPaletteIndex_;
};

class BrushOptionsState {
public:
    BrushOptionsState() noexcept;

    const AnnotationStyle& style() const noexcept;
    std::optional<std::size_t> selectedPaletteIndex() const noexcept;
    bool load(AnnotationStyle style) noexcept;
    bool setStrokeWidth(float strokeWidthDip) noexcept;
    bool setStrokePattern(AnnotationStrokePattern pattern) noexcept;
    bool selectPalette(std::size_t index) noexcept;
    bool selectCustomColor(AnnotationColor color) noexcept;

private:
    void refreshPaletteSelection() noexcept;

    AnnotationStyle style_{};
    std::optional<std::size_t> selectedPaletteIndex_;
};

enum class BrushOptionControl : std::uint8_t {
    strokeWidth,
    strokeStyle,
    palette,
    customColor,
};

struct BrushOptionHit {
    BrushOptionControl control = BrushOptionControl::strokeWidth;
    std::size_t index = 0;
};

constexpr bool operator==(
    BrushOptionHit left,
    BrushOptionHit right) noexcept
{
    return left.control == right.control && left.index == right.index;
}

struct BrushOptionsLayout {
    AnnotationRect toolbar{};
    std::size_t paletteCount = 0;
    std::vector<AnnotationRect> strokeWidths;
    std::vector<AnnotationRect> strokeWidthHits;
    AnnotationRect strokeStyle{};
    AnnotationPoint strokeStyleSampleStart{};
    AnnotationPoint strokeStyleSampleEnd{};
    std::vector<AnnotationRect> colorSwatches;
    std::vector<AnnotationRect> separators;
};

BrushOptionsLayout brushOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount);

std::optional<BrushOptionHit> brushOptionHitTest(
    const BrushOptionsLayout& layout,
    AnnotationPoint point) noexcept;

class MarkerOptionsState {
public:
    MarkerOptionsState() noexcept;
    const AnnotationStyle& style() const noexcept;
    std::optional<std::size_t> selectedPaletteIndex() const noexcept;
    bool load(AnnotationStyle style) noexcept;
    bool setStrokeWidth(float strokeWidthDip) noexcept;
    bool selectPalette(std::size_t index) noexcept;
    bool selectCustomColor(AnnotationColor color) noexcept;

private:
    void refreshPaletteSelection() noexcept;
    AnnotationStyle style_{};
    std::optional<std::size_t> selectedPaletteIndex_;
};

enum class MarkerOptionControl : std::uint8_t {
    strokeWidth,
    palette,
    customColor,
};

struct MarkerOptionHit {
    MarkerOptionControl control = MarkerOptionControl::strokeWidth;
    std::size_t index = 0;
};

constexpr bool operator==(
    MarkerOptionHit left,
    MarkerOptionHit right) noexcept
{
    return left.control == right.control && left.index == right.index;
}

struct MarkerOptionsLayout {
    AnnotationRect toolbar{};
    std::size_t paletteCount = 0;
    std::vector<AnnotationRect> strokeWidths;
    std::vector<AnnotationRect> strokeWidthHits;
    std::vector<AnnotationRect> colorSwatches;
    std::vector<AnnotationRect> separators;
};

MarkerOptionsLayout markerOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount);

std::optional<MarkerOptionHit> markerOptionHitTest(
    const MarkerOptionsLayout& layout,
    AnnotationPoint point) noexcept;

class MosaicOptionsState {
public:
    MosaicOptionsState() noexcept;
    const AnnotationStyle& style() const noexcept;
    AnnotationKind kind() const noexcept;
    MosaicRedaction redaction() const noexcept;
    bool load(const ShapeAnnotation& annotation) noexcept;
    bool setStrokeWidth(float strokeWidthDip) noexcept;
    bool setKind(AnnotationKind kind) noexcept;
    bool toggleRedactionType() noexcept;
    bool setRedactionValue(int value) noexcept;

private:
    AnnotationStyle style_{};
    AnnotationKind kind_ = AnnotationKind::mosaicStroke;
    MosaicRedactionType redactionType_ = MosaicRedactionType::pixelMosaic;
    std::array<int, 2> redactionValues_{8, 8};
};

enum class MosaicOptionControl : std::uint8_t {
    strokeWidth,
    rectangleMode,
    redactionType,
    redactionValue,
};

struct MosaicOptionHit {
    MosaicOptionControl control = MosaicOptionControl::strokeWidth;
    std::size_t index = 0;
};

constexpr bool operator==(
    MosaicOptionHit left,
    MosaicOptionHit right) noexcept
{
    return left.control == right.control && left.index == right.index;
}

struct MosaicOptionsLayout {
    AnnotationRect toolbar{};
    std::vector<AnnotationRect> strokeWidths;
    std::vector<AnnotationRect> strokeWidthHits;
    AnnotationRect rectangleMode{};
    AnnotationRect redactionType{};
    AnnotationRect redactionValue{};
    AnnotationRect valueTrack{};
    AnnotationRect valueLabel{};
};

MosaicOptionsLayout mosaicOptionsLayout(AnnotationPoint origin);
std::optional<MosaicOptionHit> mosaicOptionHitTest(
    const MosaicOptionsLayout& layout,
    AnnotationPoint point) noexcept;
int mosaicValueForPoint(
    const MosaicOptionsLayout& layout,
    AnnotationPoint point) noexcept;

class TextOptionsState {
public:
    TextOptionsState() noexcept;
    const AnnotationStyle& style() const noexcept;
    std::optional<std::size_t> selectedPaletteIndex() const noexcept;
    bool load(AnnotationStyle style) noexcept;
    bool toggleBold() noexcept;
    bool toggleItalic() noexcept;
    bool toggleOutline() noexcept;
    bool setFontFamily(std::wstring family);
    bool setTextSize(float size) noexcept;
    bool selectPalette(std::size_t index) noexcept;
    bool selectCustomColor(AnnotationColor color) noexcept;

private:
    void refreshPaletteSelection() noexcept;
    AnnotationStyle style_{};
    std::optional<std::size_t> selectedPaletteIndex_;
};

enum class TextOptionControl : std::uint8_t {
    bold,
    italic,
    outline,
    fontFamily,
    textSize,
    palette,
    customColor,
};

struct TextOptionHit {
    TextOptionControl control = TextOptionControl::bold;
    std::size_t index = 0;
};

constexpr bool operator==(
    TextOptionHit left,
    TextOptionHit right) noexcept
{
    return left.control == right.control && left.index == right.index;
}

struct TextOptionsLayout {
    AnnotationRect toolbar{};
    AnnotationRect bold{};
    AnnotationRect italic{};
    AnnotationRect outline{};
    AnnotationRect fontFamily{};
    AnnotationRect textSize{};
    std::size_t paletteCount = 0;
    std::vector<AnnotationRect> colorSwatches;
    std::vector<AnnotationRect> separators;
};

struct PopupMenuLayout {
    AnnotationRect menu{};
    std::vector<AnnotationRect> items;
};

PopupMenuLayout popupMenuLayout(
    AnnotationRect field,
    std::size_t itemCount,
    float safeHeight) noexcept;

std::optional<std::size_t> popupMenuHitTest(
    const PopupMenuLayout& layout,
    AnnotationPoint point) noexcept;

TextOptionsLayout textOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount);

std::optional<TextOptionHit> textOptionHitTest(
    const TextOptionsLayout& layout,
    AnnotationPoint point) noexcept;

class NumberOptionsState {
public:
    NumberOptionsState() noexcept;
    NumberMarkType type() const noexcept;
    const AnnotationStyle& style() const noexcept;
    std::optional<std::size_t> selectedPaletteIndex() const noexcept;
    bool load(const ShapeAnnotation& annotation) noexcept;
    bool setType(NumberMarkType type) noexcept;
    bool setSize(float size) noexcept;
    bool selectPalette(std::size_t index) noexcept;
    bool selectCustomColor(AnnotationColor color) noexcept;

private:
    void refreshPaletteSelection() noexcept;
    NumberMarkType type_ = NumberMarkType::number;
    AnnotationStyle style_{};
    std::optional<std::size_t> selectedPaletteIndex_;
};

enum class NumberPopupMenu : std::uint8_t {
    markType,
    size,
};

enum class NumberOptionControl : std::uint8_t {
    markType,
    size,
    palette,
    customColor,
};

struct NumberOptionHit {
    NumberOptionControl control = NumberOptionControl::markType;
    std::size_t index = 0;
};

constexpr bool operator==(
    NumberOptionHit left,
    NumberOptionHit right) noexcept
{
    return left.control == right.control && left.index == right.index;
}

struct NumberOptionsLayout {
    AnnotationRect toolbar{};
    AnnotationRect markType{};
    AnnotationRect size{};
    std::size_t paletteCount = 0;
    std::vector<AnnotationRect> colorSwatches;
    std::vector<AnnotationRect> separators;
};

NumberOptionsLayout numberOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount);
std::optional<NumberOptionHit> numberOptionHitTest(
    const NumberOptionsLayout& layout,
    AnnotationPoint point) noexcept;
PopupMenuLayout numberTypeMenuLayout(
    AnnotationRect field,
    float safeHeight) noexcept;

class MagnifierOptionsState {
public:
    MagnifierOptionsState() noexcept;
    MagnifierShape shape() const noexcept;
    float zoom() const noexcept;
    const AnnotationStyle& style() const noexcept;
    std::optional<std::size_t> selectedPaletteIndex() const noexcept;
    bool load(const ShapeAnnotation& annotation) noexcept;
    bool setShape(MagnifierShape shape) noexcept;
    bool setZoom(float zoom) noexcept;
    bool setStrokeWidth(float strokeWidthDip) noexcept;
    bool selectPalette(std::size_t index) noexcept;
    bool selectCustomColor(AnnotationColor color) noexcept;

private:
    ShapeOptionsState shapeOptions_;
    float zoom_ = 2.0F;
};

enum class MagnifierOptionControl : std::uint8_t {
    strokeWidth,
    rectangleMode,
    circleMode,
    zoom,
    palette,
    customColor,
};

struct MagnifierOptionHit {
    MagnifierOptionControl control = MagnifierOptionControl::strokeWidth;
    std::size_t index = 0;
};

constexpr bool operator==(
    MagnifierOptionHit left,
    MagnifierOptionHit right) noexcept
{
    return left.control == right.control && left.index == right.index;
}

struct MagnifierOptionsLayout {
    AnnotationRect toolbar{};
    std::vector<AnnotationRect> strokeWidths;
    std::vector<AnnotationRect> strokeWidthHits;
    AnnotationRect rectangleMode{};
    AnnotationRect circleMode{};
    AnnotationRect zoom{};
    std::size_t paletteCount = 0;
    std::vector<AnnotationRect> colorSwatches;
    std::vector<AnnotationRect> separators;
};

MagnifierOptionsLayout magnifierOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount);
std::optional<MagnifierOptionHit> magnifierOptionHitTest(
    const MagnifierOptionsLayout& layout,
    AnnotationPoint point) noexcept;

enum class ShapeOptionControl : std::uint8_t {
    strokeWidth,
    fillToggle,
    rectangleMode,
    cornerRadiusDisclosure,
    ellipseMode,
    strokeStyle,
    palette,
    customColor,
};

struct ShapeOptionHit {
    ShapeOptionControl control = ShapeOptionControl::strokeWidth;
    std::size_t index = 0;
};

constexpr bool operator==(
    ShapeOptionHit left,
    ShapeOptionHit right) noexcept
{
    return left.control == right.control && left.index == right.index;
}

struct ShapeOptionsLayout {
    AnnotationRect toolbar{};
    std::size_t paletteCount = 0;
    std::vector<AnnotationRect> strokeWidths;
    std::vector<AnnotationRect> strokeWidthHits;
    AnnotationRect fillToggle{};
    AnnotationRect fillToggleBackground{};
    AnnotationRect rectangleMode{};
    AnnotationRect rectangleDisclosure{};
    AnnotationRect rectangleModeBackground{};
    AnnotationRect ellipseMode{};
    AnnotationRect ellipseModeBackground{};
    AnnotationRect strokeStyle{};
    AnnotationPoint strokeStyleSampleStart{};
    AnnotationPoint strokeStyleSampleEnd{};
    AnnotationRect strokeStyleDisclosure{};
    std::vector<AnnotationRect> colorSwatches;
    std::vector<AnnotationRect> separators;
};

enum class ArrowLineOptionControl : std::uint8_t {
    strokeWidth,
    strokeStyle,
    startArrowType,
    endArrowType,
    palette,
    customColor,
};

struct ArrowLineOptionHit {
    ArrowLineOptionControl control = ArrowLineOptionControl::strokeWidth;
    std::size_t index = 0;
};

constexpr bool operator==(
    ArrowLineOptionHit left,
    ArrowLineOptionHit right) noexcept
{
    return left.control == right.control && left.index == right.index;
}

struct ArrowLineOptionsLayout {
    AnnotationRect toolbar{};
    std::size_t paletteCount = 0;
    std::vector<AnnotationRect> strokeWidths;
    std::vector<AnnotationRect> strokeWidthHits;
    AnnotationRect strokeStyle{};
    AnnotationPoint strokeStyleSampleStart{};
    AnnotationPoint strokeStyleSampleEnd{};
    AnnotationRect startArrowType{};
    AnnotationRect endArrowType{};
    std::vector<AnnotationRect> colorSwatches;
    std::vector<AnnotationRect> separators;
};

ArrowLineOptionsLayout arrowLineOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount);

std::optional<ArrowLineOptionHit> arrowLineOptionHitTest(
    const ArrowLineOptionsLayout& layout,
    AnnotationPoint point) noexcept;

struct ArrowTypeMenuLayout {
    AnnotationRect menu{};
    std::vector<AnnotationRect> items;
};

ArrowTypeMenuLayout arrowTypeMenuLayout(AnnotationRect menu);

std::optional<std::size_t> hitTestArrowTypeMenu(
    const ArrowTypeMenuLayout& layout,
    AnnotationPoint point) noexcept;

ShapeOptionsLayout shapeOptionsLayout(
    AnnotationPoint origin,
    std::size_t paletteCount);

std::optional<ShapeOptionHit> shapeOptionHitTest(
    const ShapeOptionsLayout& layout,
    AnnotationPoint point) noexcept;

struct StrokePatternMenuLayout {
    AnnotationRect menu{};
    std::vector<AnnotationRect> items;
    std::vector<AnnotationPoint> sampleStarts;
    std::vector<AnnotationPoint> sampleEnds;
};

StrokePatternMenuLayout strokePatternMenuLayout(
    AnnotationRect menu,
    std::size_t itemCount = 6U);

std::optional<std::size_t> hitTestStrokePatternMenu(
    const StrokePatternMenuLayout& layout,
    AnnotationPoint point) noexcept;

struct CornerRadiusPanelLayout {
    AnnotationRect panel{};
    AnnotationRect label{};
    AnnotationRect sliderTrack{};
    AnnotationRect value{};
    AnnotationRect increment{};
    AnnotationRect decrement{};
};

CornerRadiusPanelLayout cornerRadiusPanelLayout(
    const ShapeOptionsLayout& options,
    AnnotationRect safeBounds,
    float sliderLeadingOffsetDip = 78.0F) noexcept;

} // namespace xxsnap::win
