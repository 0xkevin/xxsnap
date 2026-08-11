#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

namespace xxsnap::win {

class AppHost final {
public:
    static int run(HINSTANCE instance, int showCommand) noexcept;
};

} // namespace xxsnap::win
