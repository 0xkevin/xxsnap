#include "app/PreferencesWindow.h"

#include <iostream>

using namespace xxsnap::win;

namespace {

int failureCount = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            std::cerr << __FILE__ << ':' << __LINE__                           \
                      << ": CHECK failed: " #condition << '\n';                \
            ++failureCount;                                                     \
        }                                                                       \
    } while (false)

void testMacParitySectionOrderAndSizing()
{
    constexpr auto sections = preferencesSections();
    static_assert(sections.size() == 6U);
    CHECK(sections[0] == PreferencesSection::general);
    CHECK(sections[1] == PreferencesSection::shortcuts);
    CHECK(sections[2] == PreferencesSection::save);
    CHECK(sections[3] == PreferencesSection::update);
    CHECK(sections[4] == PreferencesSection::donation);
    CHECK(sections[5] == PreferencesSection::about);
    const auto standard = preferencesWindowClientSize(96);
    CHECK(standard.cx == 680 && standard.cy == 480);
    const auto scaled = preferencesWindowClientSize(144);
    CHECK(scaled.cx == 1020 && scaled.cy == 720);
}

void testFilenameErrorsUseChineseUserFacingCopy()
{
    CHECK(filenameTemplateErrorText(FilenameTemplateError::empty, L"")
        == L"文件名模板不能为空");
    CHECK(filenameTemplateErrorText(
              FilenameTemplateError::pathCharacter, L"")
        == L"文件名模板不能包含 Windows 路径字符");
    CHECK(filenameTemplateErrorText(
              FilenameTemplateError::unknownVariable, L"{date}")
        == L"不支持的变量：{date}");
}

} // namespace

int main()
{
    testMacParitySectionOrderAndSizing();
    testFilenameErrorsUseChineseUserFacingCopy();
    return failureCount == 0 ? 0 : 1;
}
