#include <cstdint>
#include <iostream>
#include <limits>
#include <optional>

#include "snipory/core/portable/Geometry.h"

using namespace snipory::core::portable;

namespace {

int checkFailed(const char* expression, const char* file, int line)
{
    std::cerr << file << ':' << line << ": CHECK failed: " << expression << '\n';
    return 1;
}

} // namespace

#define CHECK(expression) \
    do { \
        if (!(expression)) { \
            return checkFailed(#expression, __FILE__, __LINE__); \
        } \
    } while (false)

int main()
{
    CHECK((PixelPoint{-1920, -40} == PixelPoint{-1920, -40}));
    CHECK((PixelSize{3840, 2160} == PixelSize{3840, 2160}));
    CHECK((PixelRect{-1920, 0, 1920, 1080} == PixelRect{-1920, 0, 1920, 1080}));

    CHECK((standardized({20, 30, -10, -20}) == PixelRect{10, 10, 10, 20}));
    CHECK((standardized({-100, -200, 50, 60}) == PixelRect{-100, -200, 50, 60}));

    CHECK((intersection({-1920, 0, 1920, 1080}, {-10, 10, 30, 40})
        == std::optional<PixelRect>{{-10, 10, 10, 40}}));
    CHECK(!intersection({0, 0, 10, 10}, {10, 0, 5, 5}).has_value());
    CHECK((intersection({20, 20, -20, -20}, {-5, -5, 10, 10})
        == std::optional<PixelRect>{{0, 0, 5, 5}}));

    constexpr std::int64_t beyond32 = 3'000'000'000LL;
    CHECK((intersection({-beyond32, 0, beyond32 * 2, 10}, {beyond32 - 5, 2, 10, 6})
        == std::optional<PixelRect>{{beyond32 - 5, 2, 5, 6}}));

    constexpr auto minimum = std::numeric_limits<std::int64_t>::min();
    constexpr auto maximum = std::numeric_limits<std::int64_t>::max();
    CHECK((intersection({maximum, 0, minimum, 1}, {maximum - 1, 0, 1, 1})
        == std::optional<PixelRect>{{maximum - 1, 0, 1, 1}}));
    CHECK((intersection({0, maximum, 1, minimum}, {0, maximum - 1, 1, 1})
        == std::optional<PixelRect>{{0, maximum - 1, 1, 1}}));
    CHECK((intersection(
               {maximum, maximum, minimum, minimum},
               {maximum - 1, maximum - 1, 1, 1})
        == std::optional<PixelRect>{{maximum - 1, maximum - 1, 1, 1}}));

    CHECK(checkedByteCount(3, 2, 4) == std::optional<std::uint64_t>{24});
    CHECK(!checkedByteCount(-1, 2, 4).has_value());
    CHECK(!checkedByteCount(1, -2, 4).has_value());
    CHECK(!checkedByteCount(1, 2, -4).has_value());
    CHECK(!checkedByteCount(0, 2, 4).has_value());
    CHECK(!checkedByteCount(1, 0, 4).has_value());
    CHECK(!checkedByteCount(1, 2, 0).has_value());
    CHECK(!checkedByteCount(9'000'000'000LL, 9'000'000'000LL, 4).has_value());
    CHECK(!checkedByteCount(
               std::numeric_limits<std::int64_t>::max(),
               2,
               std::numeric_limits<std::int64_t>::max())
               .has_value());

    return 0;
}
