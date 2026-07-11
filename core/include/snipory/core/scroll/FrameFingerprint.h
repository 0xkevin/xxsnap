#pragma once

#include "snipory/core/scroll/ScrollFrame.h"

#include <cstdint>
#include <optional>
#include <vector>

namespace snipory::core::scroll {

struct FingerprintSize final
{
    int width = 0;
    int height = 0;
};

struct Fingerprint final
{
    FingerprintSize size;
    std::vector<std::uint8_t> luminance;
};

class FrameFingerprint final
{
public:
    [[nodiscard]] static Fingerprint make(const ScrollFrame& frame, FingerprintSize size);
    [[nodiscard]] static std::optional<double> meanAbsoluteDistance(
        const Fingerprint& left,
        const Fingerprint& right);
};

} // namespace snipory::core::scroll
