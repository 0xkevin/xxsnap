#include "app/CaptureSound.h"

#include "resource.h"

namespace xxsnap::win {
namespace {

bool playEmbeddedSound(
    HINSTANCE instance,
    int resourceIdentifier,
    EmbeddedSoundPlayer player) noexcept
{
    if (player == nullptr) return false;
    const auto module = instance != nullptr
        ? instance
        : GetModuleHandleW(nullptr);
    return player(
        MAKEINTRESOURCEW(resourceIdentifier),
        module,
        embeddedSoundFlags) != FALSE;
}

} // namespace

bool playFullScreenCaptureSound(
    HINSTANCE instance, EmbeddedSoundPlayer player) noexcept
{
    return playEmbeddedSound(
        instance, IDR_FULL_SCREEN_CAPTURE_SOUND, player);
}

bool playFullScreenCaptureSound(HINSTANCE instance) noexcept
{
    return playFullScreenCaptureSound(instance, PlaySoundW);
}

bool playTextRecognitionSuccessSound(
    HINSTANCE instance, EmbeddedSoundPlayer player) noexcept
{
    return playEmbeddedSound(
        instance, IDR_TEXT_RECOGNITION_SUCCESS_SOUND, player);
}

bool playTextRecognitionSuccessSound(HINSTANCE instance) noexcept
{
    return playTextRecognitionSuccessSound(instance, PlaySoundW);
}

} // namespace xxsnap::win
