#include "app/AppHost.h"

#include "app/HotKeyRegistrar.h"
#include "app/SingleInstance.h"
#include "app/TrayIcon.h"
#include "capture/DisplayTopology.h"
#include "capture/DxgiCaptureBackend.h"
#include "capture/FallbackCaptureBackend.h"
#include "capture/GdiCaptureBackend.h"
#include "export/ClipboardWriter.h"
#include "export/PngWriter.h"
#include "export/SelectionComposer.h"
#include "resource.h"
#include "session/CaptureSessionCoordinator.h"
#include "support/RuntimeApis.h"

#include <Windows.h>
#include <commdlg.h>
#include <objbase.h>

#include <cwchar>
#include <memory>
#include <new>
#include <optional>
#include <utility>
#include <variant>

namespace xxsnap::win {
namespace {

constexpr wchar_t receiverClassName[] = L"XxSnap.HiddenTopLevelWindow.v1";
constexpr wchar_t applicationName[] = L"XxSnap";
constexpr wchar_t hotKeyConflictText[] =
    L"Ctrl+` \u5df2\u88ab\u5176\u4ed6\u7a0b\u5e8f\u5360\u7528\uff0c\u4ecd\u53ef\u4ece\u6258\u76d8\u542f\u52a8\u533a\u57df\u622a\u56fe\u3002";
constexpr wchar_t topologyChangedText[] =
    L"\u663e\u793a\u5668\u914d\u7f6e\u8fde\u7eed\u53d8\u5316\uff0c\u672c\u6b21\u622a\u56fe\u5df2\u53d6\u6d88\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002";
constexpr wchar_t clipboardFailureText[] =
    L"\u65e0\u6cd5\u5199\u5165\u526a\u8d34\u677f\uff0c\u622a\u56fe\u5df2\u6682\u5b58\u5728\u5f53\u524d\u8fdb\u7a0b\u4e2d\u3002";
constexpr wchar_t sessionFailureText[] =
    L"\u672c\u6b21\u622a\u56fe\u672a\u5b8c\u6210\uff0c\u8bf7\u91cd\u8bd5\u3002";

enum class HostInitializationResult {
    primary,
    secondary,
    failed,
};

class WinCaptureSessionServices final : public CaptureSessionServices {
public:
    using ErrorCallback = std::function<void(CaptureSessionErrorCode)>;

    WinCaptureSessionServices(
        HINSTANCE instance,
        HWND owner,
        RuntimeApis& runtimeApis,
        ErrorCallback errorCallback)
        : instance_(instance)
        , owner_(owner)
        , runtimeApis_(runtimeApis)
        , fallback_(dxgi_, gdi_)
        , errorCallback_(std::move(errorCallback))
    {
    }

    DisplayTopologyResult snapshotTopology() noexcept override
    {
        try {
            return snapshotDisplayTopology(runtimeApis_);
        } catch (...) {
            return DisplayTopologyResult(
                TopologyError{TopologyErrorCode::systemFailure, ERROR_NOT_ENOUGH_MEMORY});
        }
    }

    CaptureResult capture(
        const DisplayTopologySnapshot& topology,
        MemoryBudget& budget) noexcept override
    {
        return fallback_.capture(topology, budget);
    }

    bool openOverlay(
        const FrozenDesktop& desktop,
        RestartCallback restartCallback,
        ActionCallback actionCallback) override
    {
        overlay_.reset();
        auto result = OverlayHost::create(
            instance_, desktop, std::move(restartCallback),
            std::move(actionCallback));
        overlay_ = std::move(result.value);
        return overlay_ != nullptr;
    }

    void showOverlay() noexcept override
    {
        if (overlay_) {
            overlay_->show();
        }
    }

    std::optional<PixelRect> selection() const noexcept override
    {
        return overlay_ ? overlay_->selection() : std::nullopt;
    }

    void closeOverlay() noexcept override
    {
        overlay_.reset();
    }

    SelectionCompositionResult compose(
        PixelRect selectionRect,
        const FrozenDesktop& desktop,
        MemoryBudget& budget) noexcept override
    {
        return composeSelection(selectionRect, desktop, budget);
    }

    CaptureExportResult exportSelection(
        const PixelBuffer& pixels,
        OverlayInputAction action) noexcept override
    {
        if (action == OverlayInputAction::copy) {
            return writeClipboard(pixels, owner_).succeeded()
                ? CaptureExportResult::completed
                : CaptureExportResult::failed;
        }
        if (action != OverlayInputAction::save) {
            return CaptureExportResult::cancelled;
        }

        wchar_t path[MAX_PATH] = L"XxSnap.png";
        OPENFILENAMEW dialog{};
        dialog.lStructSize = sizeof(dialog);
        dialog.hwndOwner = owner_;
        dialog.lpstrFilter = L"PNG \u56fe\u50cf (*.png)\0*.png\0\0";
        dialog.lpstrFile = path;
        dialog.nMaxFile = static_cast<DWORD>(std::size(path));
        dialog.lpstrDefExt = L"png";
        dialog.lpstrTitle = L"\u4fdd\u5b58\u622a\u56fe";
        dialog.Flags = OFN_NOCHANGEDIR | OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
        if (GetSaveFileNameW(&dialog) == FALSE) {
            return CommDlgExtendedError() == 0
                ? CaptureExportResult::cancelled
                : CaptureExportResult::failed;
        }
        return savePngAtomically(pixels, path).has_value()
            ? CaptureExportResult::failed
            : CaptureExportResult::completed;
    }

    void reportError(CaptureSessionErrorCode error) noexcept override
    {
        ErrorCallback callback;
        try {
            callback = errorCallback_;
        } catch (...) {
            return;
        }
        if (callback) {
            try {
                callback(error);
            } catch (...) {
            }
        }
    }

private:
    HINSTANCE instance_ = nullptr;
    HWND owner_ = nullptr;
    RuntimeApis& runtimeApis_;
    DxgiCaptureBackend dxgi_;
    GdiCaptureBackend gdi_;
    FallbackCaptureBackend fallback_;
    std::unique_ptr<OverlayHost> overlay_;
    ErrorCallback errorCallback_;
};

class Host final {
public:
    Host(HINSTANCE instance, RuntimeApis& runtimeApis) noexcept
        : instance_(instance)
        , runtimeApis_(runtimeApis)
    {
    }

    ~Host()
    {
        hotKey_.reset();
        tray_.reset();
        coordinator_.reset();
        sessionServices_.reset();
        singleInstance_.reset();
        if (window_ != nullptr) {
            DestroyWindow(window_);
            window_ = nullptr;
        }
        UnregisterClassW(receiverClassName, instance_);
    }

    HostInitializationResult initialize()
    {
        if (!createReceiverWindow()) {
            return HostInitializationResult::failed;
        }

        auto single = SingleInstance::create(
            systemSingleInstanceApi(), [this] { startRegionCapture(); });
        if (single.role == SingleInstanceRole::secondary) {
            return HostInitializationResult::secondary;
        }
        if (single.role != SingleInstanceRole::primary || !single.instance) {
            return HostInitializationResult::failed;
        }
        singleInstance_ = std::move(single.instance);

        sessionServices_ = std::make_unique<WinCaptureSessionServices>(
            instance_, window_, runtimeApis_,
            [this](CaptureSessionErrorCode error) { showSessionError(error); });
        coordinator_ = std::make_unique<CaptureSessionCoordinator>(
            *sessionServices_);

        const auto icon = reinterpret_cast<HICON>(LoadImageW(
            instance_, MAKEINTRESOURCEW(IDI_XXSNAP), IMAGE_ICON, 0, 0,
            LR_DEFAULTSIZE | LR_SHARED));
        if (icon == nullptr) {
            return HostInitializationResult::failed;
        }
        auto trayResult = TrayIcon::create(
            systemTrayIconApi(), window_, icon,
            [this](TrayCommand command) { handleTrayCommand(command); });
        if (!trayResult.value) {
            return HostInitializationResult::failed;
        }
        tray_ = std::move(trayResult.value);

        hotKey_ = std::make_unique<HotKeyRegistrar>(
            systemHotKeyApi(), [this] { startRegionCapture(); });
        if (!hotKey_->registerMvpRegionCapture(window_)) {
            if (!tray_->showHotKeyConflict(hotKeyConflictText)) {
                MessageBoxW(
                    window_, hotKeyConflictText, applicationName,
                    MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
            }
        }
        return HostInitializationResult::primary;
    }

    int messageLoop() noexcept
    {
        MSG message{};
        BOOL result = FALSE;
        while ((result = GetMessageW(&message, nullptr, 0, 0)) > 0) {
            TranslateMessage(&message);
            DispatchMessageW(&message);
        }
        return result == -1 ? EXIT_FAILURE : static_cast<int>(message.wParam);
    }

private:
    static LRESULT CALLBACK windowProcedure(
        HWND window, UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        Host* host = reinterpret_cast<Host*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
            host = static_cast<Host*>(create->lpCreateParams);
            SetWindowLongPtrW(
                window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(host));
        }
        if (host != nullptr) {
            const auto result = host->handleMessage(
                window, message, wParam, lParam);
            if (message == WM_NCDESTROY) {
                SetWindowLongPtrW(window, GWLP_USERDATA, 0);
                host->window_ = nullptr;
            }
            return result;
        }
        return DefWindowProcW(window, message, wParam, lParam);
    }

    bool createReceiverWindow() noexcept
    {
        WNDCLASSEXW windowClass{};
        windowClass.cbSize = sizeof(windowClass);
        windowClass.lpfnWndProc = windowProcedure;
        windowClass.hInstance = instance_;
        windowClass.lpszClassName = receiverClassName;
        if (RegisterClassExW(&windowClass) == 0
            && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return false;
        }
        window_ = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
            receiverClassName,
            applicationName,
            WS_POPUP,
            0,
            0,
            0,
            0,
            nullptr,
            nullptr,
            instance_,
            this);
        return window_ != nullptr;
    }

    LRESULT handleMessage(
        HWND window, UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        if (singleInstance_ && singleInstance_->handleMessage(message)) {
            return 0;
        }
        if (hotKey_ && hotKey_->handleMessage(message, wParam)) {
            return 0;
        }
        if (tray_ && tray_->handleMessage(message, wParam, lParam)) {
            return 0;
        }
        switch (message) {
        case WM_CLOSE:
            DestroyWindow(window);
            return 0;
        case WM_DESTROY:
            PostQuitMessage(EXIT_SUCCESS);
            return 0;
        case WM_DISPLAYCHANGE:
            if (coordinator_) {
                coordinator_->displayConfigurationChanged();
            }
            return 0;
        case WM_QUERYENDSESSION:
            return TRUE;
        default:
            return DefWindowProcW(window, message, wParam, lParam);
        }
    }

    void startRegionCapture() noexcept
    {
        if (coordinator_) {
            coordinator_->start();
        }
    }

    void handleTrayCommand(TrayCommand command) noexcept
    {
        if (command == TrayCommand::regionCapture) {
            startRegionCapture();
        } else if (command == TrayCommand::exit && window_ != nullptr) {
            PostMessageW(window_, WM_CLOSE, 0, 0);
        }
    }

    void showSessionError(CaptureSessionErrorCode error) noexcept
    {
        const wchar_t* text = sessionFailureText;
        if (error == CaptureSessionErrorCode::topologyChanged) {
            text = topologyChangedText;
        } else if (error == CaptureSessionErrorCode::exportFailed
                   && coordinator_ && coordinator_->recentCapture()) {
            text = clipboardFailureText;
        }
        if (!tray_ || !tray_->showHotKeyConflict(text)) {
            MessageBoxW(
                window_, text, applicationName,
                MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
        }
    }

    HINSTANCE instance_ = nullptr;
    RuntimeApis& runtimeApis_;
    HWND window_ = nullptr;
    std::unique_ptr<SingleInstance> singleInstance_;
    std::unique_ptr<WinCaptureSessionServices> sessionServices_;
    std::unique_ptr<CaptureSessionCoordinator> coordinator_;
    std::unique_ptr<TrayIcon> tray_;
    std::unique_ptr<HotKeyRegistrar> hotKey_;
};

} // namespace

int AppHost::run(HINSTANCE instance, int) noexcept
{
    if (instance == nullptr) {
        return EXIT_FAILURE;
    }

    const HRESULT comResult = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    const bool uninitializeCom = comResult == S_OK || comResult == S_FALSE;
    if (FAILED(comResult) && comResult != RPC_E_CHANGED_MODE) {
        return EXIT_FAILURE;
    }

    int exitCode = EXIT_FAILURE;
    try {
        RuntimeApis runtimeApis;
        runtimeApis.initializeProcessDpiAwareness();
        Host host(instance, runtimeApis);
        const auto initialized = host.initialize();
        if (initialized == HostInitializationResult::secondary) {
            exitCode = EXIT_SUCCESS;
        } else if (initialized == HostInitializationResult::primary) {
            exitCode = host.messageLoop();
        }
    } catch (...) {
        exitCode = EXIT_FAILURE;
    }

    if (uninitializeCom) {
        CoUninitialize();
    }
    return exitCode;
}

} // namespace xxsnap::win
