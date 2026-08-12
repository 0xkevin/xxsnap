#include <iterator>

namespace {

int failures = 0;

#define CHECK(condition) \
    do { \
        if (!(condition)) { \
            ++failures; \
        } \
    } while (false)

void testCompilerReadsUtf8SourceText()
{
#if defined(_MSC_VER)
#if !defined(_MSVC_EXECUTION_CHARACTER_SET)
#error "MSVC must compile every Windows source file with /utf-8"
#elif _MSVC_EXECUTION_CHARACTER_SET != 65001
#error "MSVC execution character set must be UTF-8"
#endif
#endif

    constexpr wchar_t sample[] = L"中文";
    CHECK(std::size(sample) == 3U);
    CHECK(sample[0] == static_cast<wchar_t>(0x4E2D));
    CHECK(sample[1] == static_cast<wchar_t>(0x6587));
}

} // namespace

int main()
{
    testCompilerReadsUtf8SourceText();
    return failures == 0 ? 0 : 1;
}
