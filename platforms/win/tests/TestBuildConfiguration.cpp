#include <cstdint>

#if defined(XXSNAP_MODERN) == defined(XXSNAP_LEGACY)
#error "Exactly one of XXSNAP_MODERN or XXSNAP_LEGACY must be defined"
#endif

#if defined(_WIN64)
static_assert(sizeof(void*) == 8, "_WIN64 requires a 64-bit pointer");
#else
static_assert(sizeof(void*) == 4, "A non-_WIN64 Windows target requires a 32-bit pointer");
#endif

#if defined(XXSNAP_LEGACY)
#if !defined(_WIN32_WINNT)
#error "Legacy builds must define _WIN32_WINNT"
#elif _WIN32_WINNT != 0x0601
#error "Legacy builds must target Windows 7 (_WIN32_WINNT == 0x0601)"
#endif
#else
#if !defined(_WIN32_WINNT)
#error "Modern builds must define _WIN32_WINNT"
#elif _WIN32_WINNT != 0x0A00
#error "Modern builds must target Windows 10 (_WIN32_WINNT == 0x0A00)"
#endif
#endif

#if !defined(WINVER)
#error "Windows builds must define WINVER"
#elif WINVER != _WIN32_WINNT
#error "WINVER must match _WIN32_WINNT"
#endif

int main()
{
    return 0;
}
