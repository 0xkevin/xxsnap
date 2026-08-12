#include "overlay/VisualStyleCatalog.h"

#include <iostream>
#include <string_view>

namespace {

using xxsnap::win::Rgba8;
using xxsnap::win::VisualStyleCatalog;

static_assert(VisualStyleCatalog::selectionColor == Rgba8{83, 120, 232, 255});
static_assert(VisualStyleCatalog::dimAlpha == 0.34f);
static_assert(VisualStyleCatalog::selectionBorderDip == 2.0f);
static_assert(VisualStyleCatalog::selectionHandleDiameterDip == 10.0f);
static_assert(VisualStyleCatalog::selectionHandleStrokeDip == 2.0f);
static_assert(VisualStyleCatalog::selectionHandleStrokeAlpha == 0.95f);
static_assert(VisualStyleCatalog::sizeLabelFontSizeDip == 12.0f);
static_assert(VisualStyleCatalog::sizeLabelHeightDip == 24.0f);
static_assert(VisualStyleCatalog::sizeLabelGapDip == 8.0f);
static_assert(VisualStyleCatalog::sizeLabelCornerRadiusDip == 5.0f);
static_assert(VisualStyleCatalog::toolbarBackgroundAlpha == 0.9f);
static_assert(VisualStyleCatalog::toolbarBorderDip == 1.0f);
static_assert(VisualStyleCatalog::toolbarBackgroundColor == Rgba8{236, 236, 236, 255});
static_assert(VisualStyleCatalog::toolbarBorderColor == Rgba8{0, 0, 0, 25});
static_assert(VisualStyleCatalog::dimColor == Rgba8{0, 0, 0, 255});
static_assert(VisualStyleCatalog::selectionHandleStrokeColor == Rgba8{255, 255, 255, 255});

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

void testForcedAquaAppKitVisualContract()
{
    CHECK((VisualStyleCatalog::selectionColor == Rgba8{83, 120, 232, 255}));
    CHECK(VisualStyleCatalog::dimAlpha == 0.34f);
    CHECK(VisualStyleCatalog::selectionBorderDip == 2.0f);
    CHECK(VisualStyleCatalog::selectionHandleDiameterDip == 10.0f);
    CHECK(VisualStyleCatalog::selectionHandleStrokeDip == 2.0f);
    CHECK(std::wstring_view(VisualStyleCatalog::sizeLabelFontFamily)
        == L"Microsoft YaHei");
    CHECK(VisualStyleCatalog::sizeLabelFontSizeDip == 12.0f);
    CHECK(VisualStyleCatalog::sizeLabelHeightDip == 24.0f);
    CHECK(VisualStyleCatalog::toolbarBackgroundAlpha == 0.9f);
    CHECK((VisualStyleCatalog::toolbarBackgroundColor == Rgba8{236, 236, 236, 255}));
    CHECK((VisualStyleCatalog::toolbarBorderColor == Rgba8{0, 0, 0, 25}));
    CHECK(std::wstring_view(VisualStyleCatalog::sizeLabelDimensionSeparator) == L" x ");
    CHECK(std::wstring_view(VisualStyleCatalog::sizeLabelSuffix) == L"  px");
}

} // namespace

int main()
{
    testForcedAquaAppKitVisualContract();

    if (failureCount != 0) {
        std::cerr << failureCount << " visual style check(s) failed\n";
        return 1;
    }

    std::cout << "Visual style catalog checks passed\n";
    return 0;
}
