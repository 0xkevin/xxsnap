#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>
#include <mmsystem.h>

namespace xxsnap::win {

using CaptureSoundPlayer = BOOL (WINAPI*)(LPCWSTR, HMODULE, DWORD);

inline constexpr DWORD fullScreenCaptureSoundFlags =
    SND_RESOURCE | SND_ASYNC | SND_NODEFAULT;

bool playFullScreenCaptureSound(
    HINSTANCE instance, CaptureSoundPlayer player) noexcept;
bool playFullScreenCaptureSound(HINSTANCE instance) noexcept;

} // namespace xxsnap::win
