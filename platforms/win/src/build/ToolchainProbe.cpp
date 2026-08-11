#include <iostream>

#define XXSNAP_STRINGIFY_IMPL(value) #value
#define XXSNAP_STRINGIFY(value) XXSNAP_STRINGIFY_IMPL(value)

int main()
{
#if defined(XXSNAP_MODERN)
    constexpr auto family = "modern";
#else
    constexpr auto family = "legacy";
#endif

#if defined(_WIN64)
    constexpr auto targetArchitecture = "x64";
#else
    constexpr auto targetArchitecture = "x86";
#endif

    std::cout << "family=" << family << '\n'
              << "target_arch=" << targetArchitecture << '\n'
              << "_WIN32_WINNT=" << XXSNAP_STRINGIFY(_WIN32_WINNT) << '\n';
    return 0;
}
