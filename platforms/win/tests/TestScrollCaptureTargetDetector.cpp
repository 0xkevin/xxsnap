#include "scroll/ScrollCaptureTargetDetector.h"

#include <cstdlib>
#include <iostream>
#include <vector>

namespace {

using snipory::core::portable::PixelPoint;
using snipory::core::portable::PixelRect;
using xxsnap::win::ScrollCaptureTargetCandidate;
using xxsnap::win::bestScrollCaptureTarget;
using xxsnap::win::scrollCaptureProbePoints;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": "
                  << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

void testMacProbeGridAndCandidateRanking()
{
    const auto probes = scrollCaptureProbePoints({100, 200, 1000, 800});
    CHECK(probes.size() == 9U);
    CHECK((probes.front() == PixelPoint{600, 600}));
    CHECK((probes[1] == PixelPoint{300, 360}));
    CHECK((probes.back() == PixelPoint{900, 840}));

    const PixelRect selection{0, 0, 1000, 800};
    const std::vector<ScrollCaptureTargetCandidate> candidates{
        {{0, 0, 250, 800}, 0},
        {{250, 80, 750, 640}, 4},
    };
    CHECK((bestScrollCaptureTarget(selection, candidates, 120, 120)
        == PixelRect{250, 80, 750, 640}));
}

void testMacClippingMinimumAndTieBreaks()
{
    const PixelRect selection{100, 100, 500, 500};
    CHECK((bestScrollCaptureTarget(
        selection, {{{50, 50, 650, 650}, 2}}, 120, 120)
        == selection));
    CHECK(!bestScrollCaptureTarget(
        selection, {{{100, 100, 119, 400}, 0}}, 120, 120).has_value());

    const std::vector<ScrollCaptureTargetCandidate> sameArea{
        {{100, 100, 300, 400}, 5},
        {{200, 100, 300, 400}, 3},
    };
    CHECK((bestScrollCaptureTarget(selection, sameArea, 120, 120)
        == PixelRect{200, 100, 300, 400}));
    const std::vector<ScrollCaptureTargetCandidate> sameCenter{
        {{150, 100, 300, 400}, 5},
        {{150, 100, 300, 400}, 3},
    };
    CHECK((bestScrollCaptureTarget(selection, sameCenter, 120, 120)
        == PixelRect{150, 100, 300, 400}));
}

} // namespace

int main()
{
    testMacProbeGridAndCandidateRanking();
    testMacClippingMinimumAndTieBreaks();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
