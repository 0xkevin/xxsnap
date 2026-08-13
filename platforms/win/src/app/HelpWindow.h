#pragma once

#include <Windows.h>

#include <array>
#include <memory>

namespace xxsnap::win {

enum class HelpChapter : std::size_t {
    capture,
    pin,
    textRecognition,
    teachingPen,
    reportIssue,
};

constexpr std::array<const wchar_t*, 5> helpChapterTitles{
    L"截图", L"贴图", L"文字识别", L"教笔", L"问题反馈"};

class HelpWindow final {
public:
    static std::unique_ptr<HelpWindow> create(
        HINSTANCE instance, HWND owner) noexcept;
    ~HelpWindow();

    HelpWindow(const HelpWindow&) = delete;
    HelpWindow& operator=(const HelpWindow&) = delete;

    void show(HelpChapter chapter = HelpChapter::capture) noexcept;
    HWND nativeWindow() const noexcept;

private:
    struct Impl;
    explicit HelpWindow(std::unique_ptr<Impl> impl) noexcept;
    std::unique_ptr<Impl> impl_;
};

} // namespace xxsnap::win
