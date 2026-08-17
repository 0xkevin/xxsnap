#include "app/ShortcutFeedback.h"

#include <cstdlib>
#include <iostream>

using namespace xxsnap::win;

namespace {

int failures = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            std::cerr << __FILE__ << ':' << __LINE__                           \
                      << ": CHECK failed: " #condition << '\n';               \
            ++failures;                                                        \
        }                                                                       \
    } while (false)

void testMacPresentationContract()
{
    static_assert(shortcutFeedbackHoldMilliseconds == 3000);
    static_assert(shortcutFeedbackFadeMilliseconds == 1000);
    static_assert(shortcutFeedbackScreenInset == 28);
    static_assert(shortcutFeedbackHeight == 58);
    static_assert(shortcutFeedbackTriangleWidth == 14);
    static_assert(shortcutFeedbackMinimumBodyWidth == 88);
}

void testWindowsShortcutFormatting()
{
    CHECK(shortcutDisplayText(MOD_CONTROL, VK_OEM_3) == L"Ctrl+`");
    CHECK(shortcutDisplayText(MOD_CONTROL | MOD_SHIFT, '1')
        == L"Ctrl+Shift+1");
    CHECK(shortcutDisplayText(MOD_CONTROL, '3') == L"Ctrl+3");
    CHECK(shortcutDisplayText(0, VK_ESCAPE) == L"Esc");
    CHECK(shortcutDisplayText(0, VK_F5) == L"F5");
}

void testSystemShortcutFiltering()
{
    CHECK(!isDisplayableSystemShortcut(0, 'A'));
    CHECK(isDisplayableSystemShortcut(MOD_CONTROL, 'C'));
    CHECK(isDisplayableSystemShortcut(0, VK_ESCAPE));
    CHECK(isDisplayableSystemShortcut(0, VK_F5));
    CHECK(!isDisplayableSystemShortcut(MOD_CONTROL, VK_CONTROL));

    const HotKeyBinding binding{
        HotKeyCommand::fullScreen, MOD_CONTROL | MOD_SHIFT, '1'};
    CHECK(matchesHotKeyBinding(
        binding, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, '1'));
    CHECK(!matchesHotKeyBinding(binding, MOD_CONTROL, '1'));
}

} // namespace

int main()
{
    testMacPresentationContract();
    testWindowsShortcutFormatting();
    testSystemShortcutFiltering();
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
