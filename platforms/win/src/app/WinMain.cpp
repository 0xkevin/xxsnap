#include "app/AppHost.h"

#include <Windows.h>

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int showCommand)
{
    return xxsnap::win::AppHost::run(instance, showCommand);
}
