#include "app/HelpWindow.h"

#include <algorithm>
#include <array>
#include <cwchar>
#include <string>

namespace xxsnap::win {
namespace {

constexpr wchar_t windowClassName[] = L"XxSnap.HelpWindow.v1";
constexpr int navigationFirstId = 2100;
constexpr int contentId = 2200;

constexpr std::array<const wchar_t*, 5> helpContents{
LR"(截图

区域截图适合截取窗口的一部分，全屏截图会取得整个桌面，滚动截图用来保存一屏放不下的内容。

快捷键
区域截图（默认）：Ctrl+`
全屏截图（默认）：Ctrl+Shift+1
复制：Ctrl+C    保存：Ctrl+S    贴图：Ctrl+1
撤销：Ctrl+Z    重做：Ctrl+Shift+Z    取消：Esc

区域截图
从托盘菜单选择“区域截图”，或按当前快捷键。屏幕会停在当前画面，拖出范围并松开鼠标后，选区锁定，工具条随即出现。

调整选区
拖动选区内部可整体移动；拖四边或四角控制点可改宽高。标注工具已激活时，第一次按 Esc 退出工具，再按一次取消截图。

标注工具
形状、箭头、画笔、荧光笔、马赛克、文字、序号、放大镜和橡皮擦均可从工具条选择。选中工具后，对应的线宽、颜色或样式选项会显示。

全屏截图
结果先显示在屏幕右下角。单击缩略图进入全屏编辑器；右键菜单提供显示工具条、贴图、复制、保存和关闭。

滚动截图
先锁定可滚动内容区域，再点滚动截图。选择向上或向下后，每次点击“开始单步滚动”采集一段；到达页面边界后完成长图。)",
LR"(贴图

贴图把截图留在桌面上。查资料、核对数字或照着图片输入时，不用反复切换窗口。

快捷键
从当前截图创建贴图：Ctrl+1
退出工具 / 隐藏贴图：Esc
恢复最近隐藏的贴图（默认）：Ctrl+1

创建与移动
区域截图锁定后点贴图，全屏预览、全屏编辑器和长图编辑器也能创建贴图。按住贴图拖动可移动，鼠标滚轮可缩放。

右键菜单
提供显示工具条、复制图片、保存图片、重置大小、透明度 100%/80%/60%/40%、置顶、关闭和关闭全部贴图。

继续标注
右键选择“显示工具条”后，可在贴图上继续画形状、箭头、画笔和文字。结束编辑后，新内容会留在贴图里，复制和保存也会带上它们。)",
LR"(文字识别

文字识别会读取框选区域，把结果直接复制到剪贴板。整个识别过程在本机完成，不上传截图。

快捷键
开始文字识别（默认）：Ctrl+3
取消框选：Esc

开始识别
从菜单进入，或按当前快捷键后框住文字。松开鼠标就会自动识别并复制，这个模式没有工具栏，也不需要再点确认。

成功与失败提示
识别成功后会显示提示并播放一声提示音。没有识别到文字、图片读取失败或剪贴板写入失败时，会始终显示失败提示。声音和成功通知可在设置中关闭。

支持范围
横排文字和竖排文字都可识别，中文、英文、韩文混排也有基本支持。遇到多栏排版时，分开框选通常更稳。)",
LR"(教笔

教笔让标注直接留在当前桌面画面上，适合讲解界面或远程会议。进入后屏幕保持原色，默认工具是画笔。

快捷键
进入或退出教笔（默认）：Ctrl+2
呼出或隐藏工具栏：右键
删除选中标注：Delete

操作
在画布上右键会在指针旁打开紧凑工具栏。再右键一次会收起；选好工具后在画布上落笔，工具栏也会隐藏。

可用工具
画笔、形状、箭头、荧光笔、文字、序号、马赛克、取色测距、橡皮擦和放大镜都可使用。默认画笔可调粗细、线型和颜色。

复制与保存
复制或保存会取得当前完整桌面，并将教笔标注一起写入剪贴板或文件。取消保存面板时不会生成文件。

选择与删除
如果主工具还在激活，先按 Esc 退出当前工具。可编辑标注能选中后移动或调整大小，选中项可按 Delete 或 Backspace 删除。)",
LR"(问题反馈

如果 XxSnap 出现异常，请从托盘菜单选择“导出诊断日志…”，将生成的 ZIP 压缩包和问题现象发送到：

zfc.2012@gmail.com

诊断日志包含截图、滚动截图、文字识别、教笔等功能的运行记录和系统版本信息。

诊断日志不包含实际截图图片、识别文字、剪贴板内容、网址或文件路径。)"
};

int scaled(int value, UINT dpi) noexcept
{
    return MulDiv(value, static_cast<int>(dpi), 96);
}

} // namespace

struct HelpWindow::Impl final {
    HINSTANCE instance = nullptr;
    HWND owner = nullptr;
    HWND window = nullptr;
    HWND content = nullptr;
    UINT dpi = 96;
    HFONT regularFont = nullptr;
    HFONT navigationFont = nullptr;
    HelpChapter selected = HelpChapter::capture;

    ~Impl()
    {
        if (window != nullptr) DestroyWindow(window);
        if (regularFont != nullptr) DeleteObject(regularFont);
        if (navigationFont != nullptr) DeleteObject(navigationFont);
    }

    static LRESULT CALLBACK procedure(
        HWND window, UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        auto* self = reinterpret_cast<Impl*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
            self = static_cast<Impl*>(create->lpCreateParams);
            SetWindowLongPtrW(window, GWLP_USERDATA,
                reinterpret_cast<LONG_PTR>(self));
            self->window = window;
        }
        return self == nullptr ? DefWindowProcW(window, message, wParam, lParam)
                               : self->handle(message, wParam, lParam);
    }

    LRESULT handle(UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        switch (message) {
        case WM_COMMAND: {
            const auto identifier = LOWORD(wParam);
            if (identifier >= navigationFirstId
                && identifier < navigationFirstId
                    + static_cast<int>(helpChapterTitles.size())) {
                select(static_cast<HelpChapter>(identifier - navigationFirstId));
            }
            return 0;
        }
        case WM_CTLCOLORSTATIC:
            if (reinterpret_cast<HWND>(lParam) == content) {
                SetBkColor(reinterpret_cast<HDC>(wParam), RGB(255, 255, 255));
                return reinterpret_cast<LRESULT>(GetStockObject(WHITE_BRUSH));
            }
            return DefWindowProcW(window, message, wParam, lParam);
        case WM_SIZE:
            layout(LOWORD(lParam), HIWORD(lParam));
            return 0;
        case WM_GETMINMAXINFO: {
            auto* dimensions = reinterpret_cast<MINMAXINFO*>(lParam);
            dimensions->ptMinTrackSize.x = scaled(760, dpi);
            dimensions->ptMinTrackSize.y = scaled(512, dpi);
            return 0;
        }
        case WM_CLOSE:
            ShowWindow(window, SW_HIDE);
            return 0;
        case WM_DESTROY:
            window = nullptr;
            return 0;
        default:
            return DefWindowProcW(window, message, wParam, lParam);
        }
    }

    bool build()
    {
        WNDCLASSEXW windowClass{};
        windowClass.cbSize = sizeof(windowClass);
        windowClass.lpfnWndProc = procedure;
        windowClass.hInstance = instance;
        windowClass.hCursor = LoadCursorW(nullptr, MAKEINTRESOURCEW(32512));
        windowClass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        windowClass.lpszClassName = windowClassName;
        if (RegisterClassExW(&windowClass) == 0
            && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return false;
        const auto screen = GetDC(nullptr);
        dpi = screen == nullptr ? 96U
            : static_cast<UINT>(GetDeviceCaps(screen, LOGPIXELSX));
        if (screen != nullptr) ReleaseDC(nullptr, screen);
        regularFont = CreateFontW(-scaled(15, dpi), 0, 0, 0, FW_NORMAL,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH,
            L"Microsoft YaHei");
        navigationFont = CreateFontW(-scaled(15, dpi), 0, 0, 0, FW_SEMIBOLD,
            FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
            CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH,
            L"Microsoft YaHei");
        RECT bounds{0, 0, scaled(980, dpi), scaled(700, dpi)};
        AdjustWindowRectEx(&bounds, WS_OVERLAPPEDWINDOW, FALSE, 0);
        window = CreateWindowExW(0, windowClassName, L"XxSnap 帮助",
            WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT,
            bounds.right - bounds.left, bounds.bottom - bounds.top,
            owner, nullptr, instance, this);
        if (window == nullptr) return false;
        for (std::size_t index = 0; index < helpChapterTitles.size(); ++index) {
            const auto button = CreateWindowExW(0, L"BUTTON",
                helpChapterTitles[index], WS_CHILD | WS_VISIBLE | WS_TABSTOP
                    | BS_PUSHBUTTON | BS_LEFT,
                0, 0, 0, 0, window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(
                    navigationFirstId + static_cast<int>(index))),
                instance, nullptr);
            SendMessageW(button, WM_SETFONT,
                reinterpret_cast<WPARAM>(navigationFont), TRUE);
        }
        content = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", L"",
            WS_CHILD | WS_VISIBLE | WS_VSCROLL | ES_MULTILINE | ES_READONLY
                | ES_AUTOVSCROLL,
            0, 0, 0, 0, window,
            reinterpret_cast<HMENU>(static_cast<INT_PTR>(contentId)),
            instance, nullptr);
        SendMessageW(content, WM_SETFONT,
            reinterpret_cast<WPARAM>(regularFont), TRUE);
        SendMessageW(content, EM_SETMARGINS, EC_LEFTMARGIN | EC_RIGHTMARGIN,
            MAKELPARAM(scaled(22, dpi), scaled(22, dpi)));
        RECT client{};
        GetClientRect(window, &client);
        layout(client.right, client.bottom);
        select(HelpChapter::capture);
        return true;
    }

    void layout(int width, int height) noexcept
    {
        const auto sidebarWidth = scaled(200, dpi);
        const auto margin = scaled(18, dpi);
        const auto rowHeight = scaled(38, dpi);
        for (std::size_t index = 0; index < helpChapterTitles.size(); ++index) {
            const auto control = GetDlgItem(window,
                navigationFirstId + static_cast<int>(index));
            MoveWindow(control, margin, scaled(24, dpi)
                + static_cast<int>(index) * (rowHeight + scaled(6, dpi)),
                sidebarWidth - margin * 2, rowHeight, TRUE);
        }
        if (content != nullptr) {
            MoveWindow(content, sidebarWidth, 0,
                (std::max)(0, width - sidebarWidth), height, TRUE);
        }
    }

    void select(HelpChapter chapter) noexcept
    {
        auto index = static_cast<std::size_t>(chapter);
        if (index >= helpContents.size()) index = 0U;
        selected = static_cast<HelpChapter>(index);
        SetWindowTextW(content, helpContents[index]);
        SendMessageW(content, EM_SETSEL, 0, 0);
        SendMessageW(content, EM_SCROLLCARET, 0, 0);
        for (std::size_t current = 0; current < helpChapterTitles.size(); ++current) {
            EnableWindow(GetDlgItem(window,
                navigationFirstId + static_cast<int>(current)), current != index);
        }
    }
};

std::unique_ptr<HelpWindow> HelpWindow::create(
    HINSTANCE instance, HWND owner) noexcept
{
    if (instance == nullptr) return nullptr;
    try {
        auto impl = std::make_unique<Impl>();
        impl->instance = instance;
        impl->owner = owner;
        if (!impl->build()) return nullptr;
        return std::unique_ptr<HelpWindow>(new HelpWindow(std::move(impl)));
    } catch (...) {
        return nullptr;
    }
}

HelpWindow::HelpWindow(std::unique_ptr<Impl> impl) noexcept
    : impl_(std::move(impl))
{
}

HelpWindow::~HelpWindow() = default;

void HelpWindow::show(HelpChapter chapter) noexcept
{
    if (!impl_ || impl_->window == nullptr) return;
    impl_->select(chapter);
    ShowWindow(impl_->window, SW_SHOWNORMAL);
    SetForegroundWindow(impl_->window);
}

HWND HelpWindow::nativeWindow() const noexcept
{
    return impl_ ? impl_->window : nullptr;
}

} // namespace xxsnap::win
