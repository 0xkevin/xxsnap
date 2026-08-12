#include "scroll/ScrollRegionCapturer.h"

#include <Windows.h>

#include <cstddef>
#include <cstdint>
#include <iostream>
#include <vector>

namespace {

using namespace xxsnap::win;

int failures = 0;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            std::cerr << __FILE__ << ':' << __LINE__                           \
                      << ": CHECK failed: " #condition << '\n';                \
            ++failures;                                                        \
        }                                                                       \
    } while (false)

struct FakeGdi final {
    std::vector<std::byte> pixels;
    int sourceX = 0;
    int sourceY = 0;
    bool failCopy = false;

    HDC desktop() const noexcept
    {
        return reinterpret_cast<HDC>(static_cast<std::uintptr_t>(1));
    }

    HDC memory() const noexcept
    {
        return reinterpret_cast<HDC>(static_cast<std::uintptr_t>(2));
    }

    HBITMAP bitmap() const noexcept
    {
        return reinterpret_cast<HBITMAP>(static_cast<std::uintptr_t>(3));
    }

    HGDIOBJ previous() const noexcept
    {
        return reinterpret_cast<HGDIOBJ>(static_cast<std::uintptr_t>(4));
    }

    GdiCaptureApis apis()
    {
        GdiCaptureApis result;
        result.getDc = [this](HWND) { return desktop(); };
        result.releaseDc = [](HWND, HDC) { return 1; };
        result.createCompatibleDc = [this](HDC) { return memory(); };
        result.deleteDc = [](HDC) { return TRUE; };
        result.createDibSection = [this](
            HDC, const BITMAPINFO* info, UINT, void** bits, HANDLE, DWORD) {
            const auto width = info->bmiHeader.biWidth;
            const auto height = -info->bmiHeader.biHeight;
            pixels.assign(
                static_cast<std::size_t>(width * height * 4), std::byte{0});
            *bits = pixels.data();
            return bitmap();
        };
        result.deleteObject = [](HGDIOBJ) { return TRUE; };
        result.selectObject = [this](HDC, HGDIOBJ object) {
            return object == bitmap() ? previous() : static_cast<HGDIOBJ>(bitmap());
        };
        result.bitBlt = [this](
            HDC, int, int, int width, int height,
            HDC, int x, int y, DWORD operation) {
            sourceX = x;
            sourceY = y;
            CHECK(operation == (SRCCOPY | CAPTUREBLT));
            if (failCopy) return FALSE;
            for (int row = 0; row < height; ++row) {
                for (int column = 0; column < width; ++column) {
                    const auto offset = static_cast<std::size_t>(
                        (row * width + column) * 4);
                    pixels[offset] = std::byte{static_cast<unsigned char>(column)};
                    pixels[offset + 1U] = std::byte{static_cast<unsigned char>(row)};
                    pixels[offset + 2U] = std::byte{0x7F};
                    pixels[offset + 3U] = std::byte{0};
                }
            }
            return TRUE;
        };
        result.gdiFlush = [] { return TRUE; };
        result.setLastError = [](DWORD value) { SetLastError(value); };
        result.getLastError = [] { return GetLastError(); };
        return result;
    }
};

void testCapturesRequestedPhysicalRegionAsOpaqueScrollFrame()
{
    FakeGdi fake;
    ScrollRegionCapturer capturer(fake.apis(), 1U * 1024U * 1024U);

    const auto frame = capturer.capture({-20, 35, 4, 3});

    CHECK(frame.has_value());
    if (!frame.has_value()) return;
    CHECK(fake.sourceX == -20);
    CHECK(fake.sourceY == 35);
    CHECK(frame->width == 4);
    CHECK(frame->height == 3);
    CHECK(frame->bytesPerRow == 16);
    CHECK(frame->pixels.size() == 48U);
    CHECK(frame->pixels[0] == 0U);
    CHECK(frame->pixels[1] == 0U);
    CHECK(frame->pixels[2] == 0x7FU);
    CHECK(frame->pixels[3] == 0xFFU);
    CHECK(frame->pixels[44] == 3U);
    CHECK(frame->pixels[45] == 2U);
    CHECK(frame->pixels[47] == 0xFFU);
}

void testRejectsInvalidOversizedAndFailedCaptures()
{
    FakeGdi fake;
    ScrollRegionCapturer capturer(fake.apis(), 47U);
    CHECK(!capturer.capture({0, 0, 0, 3}).has_value());
    CHECK(!capturer.capture({0, 0, 4, 3}).has_value());

    ScrollRegionCapturer copyFailure(fake.apis(), 48U);
    fake.failCopy = true;
    CHECK(!copyFailure.capture({0, 0, 4, 3}).has_value());
}

} // namespace

int main()
{
    testCapturesRequestedPhysicalRegionAsOpaqueScrollFrame();
    testRejectsInvalidOversizedAndFailedCaptures();
    return failures == 0 ? 0 : 1;
}
