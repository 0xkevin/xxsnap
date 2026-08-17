#include "app/HelpWindow.h"

#include <iostream>
#include <array>
#include <cstdlib>
#include <cwchar>
#include <string>

using namespace xxsnap::win;

namespace {

int failures = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            std::cerr << __FILE__ << ':' << __LINE__                           \
                      << ": CHECK failed: " #condition << '\n';                \
            ++failures;                                                        \
        }                                                                       \
    } while (false)

std::wstring controlText(HWND control)
{
    const auto length = GetWindowTextLengthW(control);
    std::wstring value(static_cast<std::size_t>(length) + 1U, L'\0');
    GetWindowTextW(control, value.data(), length + 1);
    value.resize(static_cast<std::size_t>(length));
    return value;
}

void testMacHelpContract()
{
    const std::array<const wchar_t*, 5> expected{
        L"截图", L"贴图", L"文字识别", L"教笔", L"问题反馈"};
    for (std::size_t index = 0; index < expected.size(); ++index) {
        CHECK(std::wcscmp(helpChapterTitles[index], expected[index]) == 0);
    }
    auto window = HelpWindow::create(GetModuleHandleW(nullptr), nullptr);
    CHECK(window != nullptr);
    if (!window) return;
    const auto native = window->nativeWindow();
    CHECK(native != nullptr);
    RECT client{};
    GetClientRect(native, &client);
    const auto dc = GetDC(native);
    const auto dpi = dc == nullptr ? 96 : GetDeviceCaps(dc, LOGPIXELSX);
    if (dc != nullptr) ReleaseDC(native, dc);
    CHECK(std::abs(client.right - MulDiv(980, dpi, 96)) <= 2);
    CHECK(std::abs(client.bottom - MulDiv(700, dpi, 96)) <= 2);

    const auto content = GetDlgItem(native, 2200);
    CHECK(content != nullptr);
    auto text = controlText(content);
    CHECK(text.find(L"Ctrl+Shift+1") != std::wstring::npos);
    CHECK(text.find(L"Command") == std::wstring::npos);
    SendMessageW(native, WM_COMMAND, 2104, 0);
    text = controlText(content);
    CHECK(text.find(L"zfc.2012@gmail.com") != std::wstring::npos);
    CHECK(text.find(L"不包含实际截图图片") != std::wstring::npos);
}

} // namespace

int main()
{
    testMacHelpContract();
    return failures == 0 ? 0 : 1;
}
