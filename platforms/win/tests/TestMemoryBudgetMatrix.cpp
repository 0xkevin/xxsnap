#include "session/CaptureMemoryPlan.h"
#include "session/CaptureSessionCoordinator.h"

#include <Windows.h>

#include <cstdlib>
#include <iostream>
#include <limits>
#include <vector>

namespace {

using xxsnap::win::CaptureMemoryPlanStatus;
using xxsnap::win::DisplayDescriptor;
using xxsnap::win::defaultCaptureSessionMemoryLimit;
using xxsnap::win::planFrozenDesktopMemory;

int failures = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            std::cerr << __FILE__ << ':' << __LINE__                           \
                      << ": CHECK failed: " #condition << '\n';                \
            ++failures;                                                        \
        }                                                                       \
    } while (false)

DisplayDescriptor display(
    const wchar_t* name,
    std::int64_t x,
    std::int64_t width,
    std::int64_t height)
{
    return {
        name,
        {x, 0, width, height},
        96U,
        96U,
        DISPLAYCONFIG_ROTATION_IDENTITY,
    };
}

void testArchitectureLimit()
{
#if defined(_WIN64)
    CHECK(sizeof(void*) == 8U);
    CHECK(defaultCaptureSessionMemoryLimit
          == 2ULL * 1024ULL * 1024ULL * 1024ULL);
#else
    CHECK(sizeof(void*) == 4U);
    CHECK(defaultCaptureSessionMemoryLimit
          == 512ULL * 1024ULL * 1024ULL);
#endif
}

void testRepresentativeFourKTopologiesFit()
{
    const auto first = display(L"DISPLAY1", 0, 3840, 2160);
    const auto second = display(L"DISPLAY2", 3840, 3840, 2160);
    const auto third = display(L"DISPLAY3", 7680, 3840, 2160);

    const auto dual = planFrozenDesktopMemory(
        {first, second}, defaultCaptureSessionMemoryLimit);
    CHECK(dual.status == CaptureMemoryPlanStatus::fits);
    CHECK(dual.requiredBytes == 66'355'200ULL);

    const auto triple = planFrozenDesktopMemory(
        {first, second, third}, defaultCaptureSessionMemoryLimit);
    CHECK(triple.status == CaptureMemoryPlanStatus::fits);
    CHECK(triple.requiredBytes == 99'532'800ULL);
}

void testOversizedTopologyIsRejectedWithoutAllocation()
{
    const auto oversized = planFrozenDesktopMemory(
        {display(L"DISPLAY1", 0, 100'000, 100'000)},
        defaultCaptureSessionMemoryLimit);
    CHECK(oversized.status == CaptureMemoryPlanStatus::budgetExceeded);
    CHECK(oversized.requiredBytes == 40'000'000'000ULL);

    const auto invalid = planFrozenDesktopMemory(
        {display(L"DISPLAY1", 0, 0, 2160)},
        defaultCaptureSessionMemoryLimit);
    CHECK(invalid.status == CaptureMemoryPlanStatus::invalidSize);
    CHECK(invalid.requiredBytes == 0);
}

void testArithmeticNeverWrapsOnX86OrX64()
{
    constexpr auto width = (std::numeric_limits<std::int64_t>::max)() / 4;
    const auto large = display(L"DISPLAY", 0, width, 1);
    const auto plan = planFrozenDesktopMemory(
        {large, large, large},
        (std::numeric_limits<std::uint64_t>::max)());
    CHECK(plan.status == CaptureMemoryPlanStatus::arithmeticOverflow);

    const auto productOverflow = planFrozenDesktopMemory(
        {display(
            L"DISPLAY",
            0,
            (std::numeric_limits<std::int64_t>::max)(),
            (std::numeric_limits<std::int64_t>::max)())},
        (std::numeric_limits<std::uint64_t>::max)());
    CHECK(productOverflow.status
          == CaptureMemoryPlanStatus::arithmeticOverflow);
}

} // namespace

int main()
{
    testArchitectureLimit();
    testRepresentativeFourKTopologiesFit();
    testOversizedTopologyIsRejectedWithoutAllocation();
    testArithmeticNeverWrapsOnX86OrX64();

    if (failures != 0) {
        std::cerr << failures << " failure(s)\n";
        return EXIT_FAILURE;
    }
    return EXIT_SUCCESS;
}
