#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>
#include <mmsystem.h>

namespace xxsnap::win {

using EmbeddedSoundPlayer = BOOL (WINAPI*)(LPCWSTR, HMODULE, DWORD);

inline constexpr DWORD embeddedSoundFlags =
    SND_RESOURCE | SND_ASYNC | SND_NODEFAULT;

bool playFullScreenCaptureSound(
    HINSTANCE instance, EmbeddedSoundPlayer player) noexcept;
bool playFullScreenCaptureSound(HINSTANCE instance) noexcept;
bool playTextRecognitionSuccessSound(
    HINSTANCE instance, EmbeddedSoundPlayer player) noexcept;
bool playTextRecognitionSuccessSound(HINSTANCE instance) noexcept;

} // namespace xxsnap::win
