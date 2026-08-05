#include "overlay/VisualStyleCatalog.h"

#include <array>
#include <cstddef>
#include <iostream>

namespace {

using xxsnap::win::MvpToolbarAction;
using xxsnap::win::Rgba8;
using xxsnap::win::VisualStyleCatalog;

constexpr std::array expectedActions{
    MvpToolbarAction::cancel,
    MvpToolbarAction::save,
    MvpToolbarAction::copy,
};

static_assert(VisualStyleCatalog::selectionColor == Rgba8{83, 120, 232, 255});
static_assert(VisualStyleCatalog::dimAlpha == 0.34f);
static_assert(VisualStyleCatalog::selectionBorderDip == 2.0f);
static_assert(VisualStyleCatalog::toolbarHeightDip == 28.0f);
static_assert(VisualStyleCatalog::buttonSizeDip == 20.0f);
static_assert(VisualStyleCatalog::buttonStepDip == 28.0f);
static_assert(VisualStyleCatalog::horizontalPaddingDip == 4.0f);
static_assert(VisualStyleCatalog::mvpToolbarWidthDip == 144.0f);
static_assert(VisualStyleCatalog::mvpToolbarActions.size() == 3);
static_assert(VisualStyleCatalog::mvpToolbarActions[0] == MvpToolbarAction::cancel);
static_assert(VisualStyleCatalog::mvpToolbarActions[1] == MvpToolbarAction::save);
static_assert(VisualStyleCatalog::mvpToolbarActions[2] == MvpToolbarAction::copy);
static_assert(
    VisualStyleCatalog::mvpToolbarWidthDip
    == VisualStyleCatalog::horizontalPaddingDip
        + VisualStyleCatalog::buttonStepDip
            * static_cast<float>(VisualStyleCatalog::mvpToolbarActions.size() + 2));

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

void testMacVisualContract()
{
    CHECK((VisualStyleCatalog::selectionColor == Rgba8{83, 120, 232, 255}));
    CHECK(VisualStyleCatalog::dimAlpha == 0.34f);
    CHECK(VisualStyleCatalog::selectionBorderDip == 2.0f);
    CHECK(VisualStyleCatalog::toolbarHeightDip == 28.0f);
    CHECK(VisualStyleCatalog::buttonSizeDip == 20.0f);
    CHECK(VisualStyleCatalog::buttonStepDip == 28.0f);
    CHECK(VisualStyleCatalog::horizontalPaddingDip == 4.0f);
    CHECK(VisualStyleCatalog::mvpToolbarWidthDip == 144.0f);
}

void testMvpToolbarContract()
{
    CHECK(VisualStyleCatalog::mvpToolbarActions == expectedActions);
    CHECK(VisualStyleCatalog::mvpToolbarActions.size() == 3);
    CHECK(
        VisualStyleCatalog::mvpToolbarWidthDip
        == VisualStyleCatalog::horizontalPaddingDip
            + VisualStyleCatalog::buttonStepDip
                * static_cast<float>(VisualStyleCatalog::mvpToolbarActions.size() + 2));
}

} // namespace

int main()
{
    testMacVisualContract();
    testMvpToolbarContract();

    if (failureCount != 0) {
        std::cerr << failureCount << " visual style check(s) failed\n";
        return 1;
    }

    std::cout << "Visual style catalog checks passed\n";
    return 0;
}
