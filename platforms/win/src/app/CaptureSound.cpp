#include "app/CaptureSound.h"

#include "resource.h"

namespace xxsnap::win {

bool playFullScreenCaptureSound(
    HINSTANCE instance, CaptureSoundPlayer player) noexcept
{
    if (player == nullptr) return false;
    const auto module = instance != nullptr
        ? instance
        : GetModuleHandleW(nullptr);
    return player(
        MAKEINTRESOURCEW(IDR_FULL_SCREEN_CAPTURE_SOUND),
        module,
        fullScreenCaptureSoundFlags) != FALSE;
}

bool playFullScreenCaptureSound(HINSTANCE instance) noexcept
{
    return playFullScreenCaptureSound(instance, PlaySoundW);
}

} // namespace xxsnap::win
