#include "app/CaptureSound.h"
#include "resource.h"

#include <cstdlib>
#include <cstring>
#include <iostream>

using namespace xxsnap::win;

namespace {

int failures = 0;
LPCWSTR playedResource = nullptr;
HMODULE playedModule = nullptr;
DWORD playedFlags = 0;
BOOL playbackResult = TRUE;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            std::cerr << __FILE__ << ':' << __LINE__                           \
                      << ": CHECK failed: " #condition << '\n';               \
            ++failures;                                                        \
        }                                                                       \
    } while (false)

BOOL WINAPI recordPlayback(LPCWSTR resource, HMODULE module, DWORD flags)
{
    playedResource = resource;
    playedModule = module;
    playedFlags = flags;
    return playbackResult;
}

void testPlaybackUsesEmbeddedWaveAsynchronously()
{
    const auto module = GetModuleHandleW(nullptr);
    CHECK(playFullScreenCaptureSound(module, recordPlayback));
    CHECK(playedResource == MAKEINTRESOURCEW(IDR_FULL_SCREEN_CAPTURE_SOUND));
    CHECK(playedModule == module);
    CHECK(playedFlags == fullScreenCaptureSoundFlags);
}

void testPlaybackHandlesDefaultModuleAndFailure()
{
    playbackResult = FALSE;
    CHECK(!playFullScreenCaptureSound(nullptr, recordPlayback));
    CHECK(playedModule == GetModuleHandleW(nullptr));
    CHECK(!playFullScreenCaptureSound(nullptr, nullptr));
    playbackResult = TRUE;
}

void testEmbeddedResourceContainsWaveData()
{
    const auto module = GetModuleHandleW(nullptr);
    const auto resource = FindResourceW(
        module,
        MAKEINTRESOURCEW(IDR_FULL_SCREEN_CAPTURE_SOUND),
        L"WAVE");
    CHECK(resource != nullptr);
    if (resource == nullptr) return;

    const auto size = SizeofResource(module, resource);
    const auto loaded = LoadResource(module, resource);
    const auto* bytes = static_cast<const unsigned char*>(
        LockResource(loaded));
    CHECK(size > 44U);
    CHECK(bytes != nullptr);
    if (bytes == nullptr || size < 12U) return;
    CHECK(std::memcmp(bytes, "RIFF", 4U) == 0);
    CHECK(std::memcmp(bytes + 8U, "WAVE", 4U) == 0);
}

} // namespace

int main()
{
    testPlaybackUsesEmbeddedWaveAsynchronously();
    testPlaybackHandlesDefaultModuleAndFailure();
    testEmbeddedResourceContainsWaveData();
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
