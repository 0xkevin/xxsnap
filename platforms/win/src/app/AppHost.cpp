#include "app/AppHost.h"

#include "app/HotKeyRegistrar.h"
#include "app/HotKeySettings.h"
#include "app/PreferencesSettings.h"
#include "app/PreferencesWindow.h"
#include "app/SingleInstance.h"
#include "app/TrayIcon.h"
#include "capture/DisplayTopology.h"
#include "capture/DxgiCaptureBackend.h"
#include "capture/FallbackCaptureBackend.h"
#include "capture/GdiCaptureBackend.h"
#include "export/AnnotationComposer.h"
#include "export/ClipboardWriter.h"
#include "export/PngWriter.h"
#include "export/SelectionComposer.h"
#include "fullscreen/FullScreenCapturePreviewHost.h"
#include "ocr/OcrCaptureHost.h"
#include "pin/PinnedImageHost.h"
#include "resource.h"
#include "session/CaptureSessionCoordinator.h"
#include "session/CaptureMemoryPlan.h"
#include "scroll/ScrollCaptureHost.h"
#include "support/RuntimeApis.h"

#include <Windows.h>
#include <commdlg.h>
#include <objbase.h>

#include <chrono>
#include <array>
#include <cstdio>
#include <cwchar>
#include <memory>
#include <new>
#include <optional>
#include <string>
#include <utility>
#include <variant>

namespace xxsnap::win {
namespace {

constexpr wchar_t receiverClassName[] = L"XxSnap.HiddenTopLevelWindow.v1";
constexpr wchar_t applicationName[] = L"XxSnap";
constexpr wchar_t hotKeyConflictText[] =
    L"Ctrl+` \u5df2\u88ab\u5176\u4ed6\u7a0b\u5e8f\u5360\u7528\uff0c\u4ecd\u53ef\u4ece\u6258\u76d8\u542f\u52a8\u533a\u57df\u622a\u56fe\u3002";
constexpr wchar_t restorePinHotKeyConflictText[] =
    L"Ctrl+1 \u5df2\u88ab\u5176\u4ed6\u7a0b\u5e8f\u5360\u7528\uff0c\u4ecd\u53ef\u53cc\u51fb\u6216\u53f3\u952e\u8d34\u56fe\u7ee7\u7eed\u64cd\u4f5c\u3002";
constexpr wchar_t fullScreenHotKeyConflictText[] =
    L"Ctrl+Shift+1 \u5df2\u88ab\u5176\u4ed6\u7a0b\u5e8f\u5360\u7528\uff0c\u4ecd\u53ef\u4ece\u6258\u76d8\u542f\u52a8\u5168\u5c4f\u622a\u56fe\u3002";
constexpr wchar_t ocrHotKeyConflictText[] =
    L"Ctrl+3 \u5df2\u88ab\u5176\u4ed6\u7a0b\u5e8f\u5360\u7528\uff0c\u4ecd\u53ef\u4ece\u6258\u76d8\u542f\u52a8\u6587\u5b57\u8bc6\u522b\u3002";
constexpr wchar_t teachingPenHotKeyConflictText[] =
    L"Ctrl+2 \u5df2\u88ab\u5176\u4ed6\u7a0b\u5e8f\u5360\u7528\uff0c\u4ecd\u53ef\u4ece\u6258\u76d8\u542f\u52a8\u6559\u7b14\u3002";
constexpr wchar_t topologyChangedText[] =
    L"\u663e\u793a\u5668\u914d\u7f6e\u8fde\u7eed\u53d8\u5316\uff0c\u672c\u6b21\u622a\u56fe\u5df2\u53d6\u6d88\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5\u3002";
constexpr wchar_t clipboardFailureText[] =
    L"\u65e0\u6cd5\u5199\u5165\u526a\u8d34\u677f\uff0c\u622a\u56fe\u5df2\u6682\u5b58\u5728\u5f53\u524d\u8fdb\u7a0b\u4e2d\u3002";
constexpr wchar_t sessionFailureText[] =
    L"\u672c\u6b21\u622a\u56fe\u672a\u5b8c\u6210\uff0c\u8bf7\u91cd\u8bd5\u3002";
constexpr wchar_t captureMetricsPathVariable[] = L"XXSNAP_CAPTURE_METRICS_PATH";
constexpr wchar_t interactiveTestingVariable[] = L"XXSNAP_INTERACTIVE_TESTING";
constexpr UINT testOcrMessage = WM_APP + 0x7A;
constexpr UINT testPreferencesMessage = WM_APP + 0x7B;

void appendCaptureTiming(
    const char* trigger,
    CaptureBackendKind backend,
    std::chrono::steady_clock::duration duration) noexcept
{
    try {
        const DWORD required = GetEnvironmentVariableW(
            captureMetricsPathVariable, nullptr, 0);
        if (required <= 1) {
            return;
        }
        std::wstring path(required, L'\0');
        if (GetEnvironmentVariableW(
                captureMetricsPathVariable, path.data(), required) == 0) {
            return;
        }
        path.resize(std::wcslen(path.c_str()));

        const auto milliseconds = std::chrono::duration<double, std::milli>(
            duration).count();
        char line[128]{};
        const int length = std::snprintf(
            line,
            sizeof(line),
            "%s,%s,%.3f\r\n",
            trigger,
            backend == CaptureBackendKind::preferred ? "dxgi" : "gdi",
            milliseconds);
        if (length <= 0 || static_cast<std::size_t>(length) >= sizeof(line)) {
            return;
        }
        const HANDLE file = CreateFileW(
            path.c_str(),
            FILE_APPEND_DATA,
            FILE_SHARE_READ | FILE_SHARE_WRITE,
            nullptr,
            OPEN_ALWAYS,
            FILE_ATTRIBUTE_NORMAL,
            nullptr);
        if (file == INVALID_HANDLE_VALUE) {
            return;
        }
        DWORD written = 0;
        WriteFile(
            file,
            line,
            static_cast<DWORD>(length),
            &written,
            nullptr);
        CloseHandle(file);
    } catch (...) {
    }
}

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
        , pinnedImages_(instance, owner)
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
        targetProcessId_ = 0U;
        if (const auto foreground = GetForegroundWindow()) {
            GetWindowThreadProcessId(foreground, &targetProcessId_);
        }
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

    bool beginScrollCapture(
        PixelRect selectionRect,
        std::size_t maximumAcceptedBytes,
        ScrollCaptureCallback callback) override
    {
        if (!overlay_ || scrollCapture_ || !callback) return false;
        const auto annotation = overlay_->annotationSnapshot();
        if (!overlay_->suspendForScrollCapture()) return false;
        scrollCapture_ = ScrollCaptureHost::create(
            instance_, selectionRect, targetProcessId_,
            annotation.dpiX, annotation.dpiY, maximumAcceptedBytes,
            [this, callback = std::move(callback)](
                ScrollCaptureHostResult result) mutable {
                ScrollCaptureCompletion completion;
                switch (result.status) {
                case ScrollCaptureHostStatus::completed:
                    completion.status = ScrollCaptureCompletionStatus::completed;
                    completion.pixels = std::move(result.pixels);
                    completion.action = result.action
                            == ScrollCaptureHostExportAction::save
                        ? OverlayInputAction::save
                        : result.action == ScrollCaptureHostExportAction::pin
                        ? OverlayInputAction::pin
                        : OverlayInputAction::copy;
                    break;
                case ScrollCaptureHostStatus::cancelled:
                    completion.status = ScrollCaptureCompletionStatus::cancelled;
                    break;
                case ScrollCaptureHostStatus::failed:
                    completion.status = ScrollCaptureCompletionStatus::failed;
                    break;
                }
                callback(std::move(completion));
            });
        if (!scrollCapture_) {
            overlay_->resumeAfterScrollCapture();
            return false;
        }
        return true;
    }

    void cancelScrollCapture() noexcept override
    {
        scrollCapture_.reset();
    }

    bool resumeOverlayAfterScrollCapture() noexcept override
    {
        scrollCapture_.reset();
        return overlay_ && overlay_->resumeAfterScrollCapture();
    }

    void closeOverlay() noexcept override
    {
        scrollCapture_.reset();
        overlay_.reset();
    }

    SelectionCompositionResult compose(
        PixelRect selectionRect,
        const FrozenDesktop& desktop,
        MemoryBudget& budget) noexcept override
    {
        auto composition = composeSelection(selectionRect, desktop, budget);
        auto* pixels = std::get_if<PixelBuffer>(&composition);
        if (pixels == nullptr || !overlay_) {
            return composition;
        }
        const auto annotations = overlay_->annotationSnapshot();
        if (const auto compositionError = composeAnnotations(
                *pixels,
                annotations.plan,
                annotations.dpiX,
                annotations.dpiY,
                selectionRect.x,
                selectionRect.y,
                nullptr,
                annotations.eraserMasks)) {
            return *compositionError;
        }
        return composition;
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

        std::array<wchar_t, 1024> path{};
        const auto suggested = suggestedCaptureFilename();
        wcsncpy_s(path.data(), path.size(), suggested.c_str(), _TRUNCATE);
        OPENFILENAMEW dialog{};
        dialog.lStructSize = sizeof(dialog);
        dialog.hwndOwner = owner_;
        dialog.lpstrFilter = L"PNG \u56fe\u50cf (*.png)\0*.png\0\0";
        dialog.lpstrFile = path.data();
        dialog.nMaxFile = static_cast<DWORD>(path.size());
        dialog.lpstrDefExt = L"png";
        dialog.lpstrTitle = L"\u4fdd\u5b58\u622a\u56fe";
        dialog.Flags = OFN_NOCHANGEDIR | OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST;
        if (GetSaveFileNameW(&dialog) == FALSE) {
            return CommDlgExtendedError() == 0
                ? CaptureExportResult::cancelled
                : CaptureExportResult::failed;
        }
        return savePngAtomically(pixels, path.data()).has_value()
            ? CaptureExportResult::failed
            : CaptureExportResult::completed;
    }

    CaptureExportResult pinSelection(
        PixelBuffer pixels,
        PixelRect sourceRect) noexcept override
    {
        return pinnedImages_.pin(std::move(pixels), sourceRect)
            ? CaptureExportResult::completed
            : CaptureExportResult::failed;
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

    CaptureBackendKind lastBackend() const noexcept
    {
        return fallback_.lastBackend();
    }

    bool restoreMostRecentlyHiddenPinnedImage() noexcept
    {
        return pinnedImages_.restoreMostRecentlyHidden();
    }

    PinnedImageHost& pinnedImages() noexcept
    {
        return pinnedImages_;
    }

private:
    HINSTANCE instance_ = nullptr;
    HWND owner_ = nullptr;
    RuntimeApis& runtimeApis_;
    DxgiCaptureBackend dxgi_;
    GdiCaptureBackend gdi_;
    FallbackCaptureBackend fallback_;
    PinnedImageHost pinnedImages_;
    std::unique_ptr<OverlayHost> overlay_;
    std::unique_ptr<ScrollCaptureHost> scrollCapture_;
    DWORD targetProcessId_ = 0U;
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
        preferencesWindow_.reset();
        fullScreenPreview_.reset();
        teachingPenOverlay_.reset();
        teachingPenDesktop_.reset();
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
            systemSingleInstanceApi(), [this] { startRegionCapture("wake"); });
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
            systemHotKeyApi(), [this] { startRegionCapture("hotkey"); },
            hotKeySettingsStore_.load());
        if (!hotKey_->registerMvpRegionCapture(window_)) {
            if (!tray_->showHotKeyConflict(hotKeyConflictText)) {
                MessageBoxW(
                    window_, hotKeyConflictText, applicationName,
                    MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
            }
        }
        if (!hotKey_->registerRestorePinnedImage(window_, [this] {
            if (!coordinator_ || !coordinator_->pinCurrentSelection()) {
                if (sessionServices_) {
                    sessionServices_->restoreMostRecentlyHiddenPinnedImage();
                }
            }
        })) {
            if (!tray_->showHotKeyConflict(restorePinHotKeyConflictText)) {
                MessageBoxW(window_, restorePinHotKeyConflictText,
                    applicationName,
                    MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
            }
        }
        if (!hotKey_->registerFullScreenCapture(
                window_, [this] { startFullScreenCapture(); })) {
            if (!tray_->showHotKeyConflict(fullScreenHotKeyConflictText)) {
                MessageBoxW(window_, fullScreenHotKeyConflictText,
                    applicationName,
                    MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
            }
        }
        if (!hotKey_->registerOcr(window_, [this] { startTextRecognition(); })) {
            if (!tray_->showHotKeyConflict(ocrHotKeyConflictText)) {
                MessageBoxW(window_, ocrHotKeyConflictText,
                    applicationName,
                    MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
            }
        }
        if (!hotKey_->registerTeachingPen(
                window_, [this] { toggleTeachingPen(); })) {
            if (!tray_->showHotKeyConflict(teachingPenHotKeyConflictText)) {
                MessageBoxW(window_, teachingPenHotKeyConflictText,
                    applicationName,
                    MB_OK | MB_ICONWARNING | MB_SETFOREGROUND);
            }
        }
        ocrCapture_ = std::make_unique<OcrCaptureHost>(
            instance_, window_, runtimeApis_, [this] {
                if (teachingPenOverlay_) {
                    teachingPenOverlay_->resumeInputAfterRecognition();
                }
            });
        startRegionCapture("launch");
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
        if (message == testOcrMessage
            && GetEnvironmentVariableW(
                interactiveTestingVariable, nullptr, 0) > 1) {
            startTextRecognition();
            return 0;
        }
        if (message == testPreferencesMessage
            && GetEnvironmentVariableW(
                interactiveTestingVariable, nullptr, 0) > 1) {
            showPreferences(PreferencesSection::general);
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

    void startRegionCapture(const char* trigger) noexcept
    {
        if (coordinator_ && !teachingPenOverlay_) {
            const auto startedAt = std::chrono::steady_clock::now();
            const auto result = coordinator_->start();
            const auto finishedAt = std::chrono::steady_clock::now();
            if (result == CaptureSessionStartResult::started
                && coordinator_->state() == CaptureSessionState::selecting
                && sessionServices_) {
                appendCaptureTiming(
                    trigger,
                    sessionServices_->lastBackend(),
                    finishedAt - startedAt);
            }
        }
    }

    void handleTrayCommand(TrayCommand command) noexcept
    {
        if (command == TrayCommand::regionCapture) {
            startRegionCapture("tray");
        } else if (command == TrayCommand::fullScreenCapture) {
            startFullScreenCapture();
        } else if (command == TrayCommand::textRecognition) {
            startTextRecognition();
        } else if (command == TrayCommand::teachingPen) {
            toggleTeachingPen();
        } else if (command == TrayCommand::preferences) {
            showPreferences(PreferencesSection::general);
        } else if (command == TrayCommand::checkForUpdates) {
            MessageBoxW(window_, L"已是最新版本", applicationName,
                MB_OK | MB_ICONINFORMATION | MB_SETFOREGROUND);
        } else if (command == TrayCommand::donation) {
            showPreferences(PreferencesSection::donation);
        } else if (command == TrayCommand::about) {
            showPreferences(PreferencesSection::about);
        } else if (command == TrayCommand::exit && window_ != nullptr) {
            PostMessageW(window_, WM_CLOSE, 0, 0);
        }
    }

    void showPreferences(PreferencesSection section) noexcept
    {
        if (!preferencesWindow_) {
            preferencesWindow_ = PreferencesWindow::create(
                instance_, window_, PreferencesShortcutCallbacks{
                    [this] { return currentHotKeyBindings(); },
                    [this](HotKeyBinding binding) {
                        return applyHotKeyBinding(binding);
                    },
                    [this] { return resetHotKeyBindings(); },
                });
        }
        if (preferencesWindow_) preferencesWindow_->show(section);
    }

    std::array<HotKeyBinding, 5> currentHotKeyBindings() const noexcept
    {
        auto bindings = hotKeySettingsStore_.load();
        if (hotKey_) {
            for (auto& binding : bindings) {
                binding = hotKey_->binding(binding.command);
            }
        }
        return bindings;
    }

    bool applyHotKeyBinding(HotKeyBinding binding) noexcept
    {
        if (!hotKey_) return false;
        const auto previous = hotKey_->binding(binding.command);
        if (!hotKey_->rebind(binding)) return false;
        if (hotKeySettingsStore_.save(binding)) return true;
        hotKey_->rebind(previous);
        return false;
    }

    bool resetHotKeyBindings() noexcept
    {
        if (!hotKey_) return false;
        const auto previous = currentHotKeyBindings();
        std::size_t applied = 0;
        for (const auto binding : defaultAppHotKeys()) {
            if (!hotKey_->rebind(binding)) {
                for (std::size_t index = 0; index < applied; ++index) {
                    hotKey_->rebind(previous[index]);
                }
                return false;
            }
            ++applied;
        }
        if (hotKeySettingsStore_.reset()) return true;
        for (const auto binding : previous) hotKey_->rebind(binding);
        return false;
    }

    void startFullScreenCapture() noexcept
    {
        if (teachingPenOverlay_ || !coordinator_ || !sessionServices_
            || coordinator_->state() != CaptureSessionState::idle) {
            return;
        }
        try {
            auto topologyResult = sessionServices_->snapshotTopology();
            const auto* topology = topologyResult.value();
            if (topology == nullptr) {
                showSessionError(CaptureSessionErrorCode::topologyFailed);
                return;
            }
            const auto memoryPlan = planFrozenDesktopMemory(
                topology->displays(), defaultCaptureSessionMemoryLimit);
            if (memoryPlan.status != CaptureMemoryPlanStatus::fits) {
                showSessionError(CaptureSessionErrorCode::memoryLimitExceeded);
                return;
            }
            MemoryBudget captureBudget(defaultCaptureSessionMemoryLimit);
            auto captured = sessionServices_->capture(*topology, captureBudget);
            auto* desktop = std::get_if<FrozenDesktop>(&captured);
            if (desktop == nullptr) {
                showSessionError(CaptureSessionErrorCode::captureFailed);
                return;
            }
            const auto bounds = topology->virtualBounds();
            MemoryBudget compositionBudget(defaultCaptureSessionMemoryLimit);
            auto composition = composeSelection(
                bounds, *desktop, compositionBudget);
            auto* pixels = std::get_if<PixelBuffer>(&composition);
            if (pixels == nullptr) {
                showSessionError(CaptureSessionErrorCode::compositionFailed);
                return;
            }
            if (!fullScreenPreview_) {
                fullScreenPreview_ =
                    std::make_unique<FullScreenCapturePreviewHost>(
                        instance_, window_, sessionServices_->pinnedImages());
            }
            if (!fullScreenPreview_->show(std::move(*pixels), bounds)) {
                showSessionError(CaptureSessionErrorCode::overlayFailed);
            }
        } catch (...) {
            showSessionError(CaptureSessionErrorCode::allocationFailed);
        }
    }

    void startTextRecognition() noexcept
    {
        if (!ocrCapture_ || ocrCapture_->busy()
            || !coordinator_
            || coordinator_->state() != CaptureSessionState::idle) {
            return;
        }
        const auto teachingWasSuspended = teachingPenOverlay_
            && teachingPenOverlay_->suspendInputForRecognition();
        if (!ocrCapture_->start() && teachingWasSuspended
            && teachingPenOverlay_) {
            teachingPenOverlay_->resumeInputAfterRecognition();
        }
    }

    void toggleTeachingPen() noexcept
    {
        if (teachingPenOverlay_) {
            teachingPenOverlay_.reset();
            teachingPenDesktop_.reset();
            return;
        }
        startTeachingPen();
    }

    void startTeachingPen() noexcept
    {
        if (!coordinator_ || !sessionServices_
            || coordinator_->state() != CaptureSessionState::idle
            || teachingPenOverlay_) {
            return;
        }
        try {
            auto topologyResult = sessionServices_->snapshotTopology();
            const auto* topology = topologyResult.value();
            if (topology == nullptr) {
                showSessionError(CaptureSessionErrorCode::topologyFailed);
                return;
            }
            const auto memoryPlan = planFrozenDesktopMemory(
                topology->displays(), defaultCaptureSessionMemoryLimit);
            if (memoryPlan.status != CaptureMemoryPlanStatus::fits) {
                showSessionError(CaptureSessionErrorCode::memoryLimitExceeded);
                return;
            }
            MemoryBudget captureBudget(defaultCaptureSessionMemoryLimit);
            auto captured = sessionServices_->capture(*topology, captureBudget);
            auto* desktop = std::get_if<FrozenDesktop>(&captured);
            if (desktop == nullptr) {
                showSessionError(CaptureSessionErrorCode::captureFailed);
                return;
            }
            teachingPenDesktop_ = std::make_unique<FrozenDesktop>(
                std::move(*desktop));
            auto created = OverlayHost::createTeachingPen(
                instance_, *teachingPenDesktop_,
                [this] {
                    teachingPenOverlay_.reset();
                    teachingPenDesktop_.reset();
                    startTeachingPen();
                },
                [this](OverlayInputAction action) {
                    finishTeachingPen(action);
                });
            teachingPenOverlay_ = std::move(created.value);
            if (!teachingPenOverlay_) {
                teachingPenDesktop_.reset();
                showSessionError(CaptureSessionErrorCode::overlayFailed);
                return;
            }
            teachingPenOverlay_->show();
        } catch (...) {
            teachingPenOverlay_.reset();
            teachingPenDesktop_.reset();
            showSessionError(CaptureSessionErrorCode::allocationFailed);
        }
    }

    void finishTeachingPen(OverlayInputAction action) noexcept
    {
        if (!teachingPenOverlay_ || !teachingPenDesktop_) return;
        if (action != OverlayInputAction::copy
            && action != OverlayInputAction::save) {
            teachingPenOverlay_.reset();
            teachingPenDesktop_.reset();
            return;
        }
        try {
            const auto bounds = teachingPenDesktop_->topology.virtualBounds();
            const auto annotation = teachingPenOverlay_->annotationSnapshot();
            MemoryBudget budget(defaultCaptureSessionMemoryLimit);
            auto composition = composeSelection(
                bounds, *teachingPenDesktop_, budget);
            auto* pixels = std::get_if<PixelBuffer>(&composition);
            if (pixels == nullptr || composeAnnotations(
                    *pixels,
                    annotation.plan,
                    annotation.dpiX,
                    annotation.dpiY,
                    bounds.x,
                    bounds.y,
                    nullptr,
                    annotation.eraserMasks).has_value()) {
                teachingPenOverlay_.reset();
                teachingPenDesktop_.reset();
                showSessionError(CaptureSessionErrorCode::compositionFailed);
                return;
            }
            teachingPenOverlay_.reset();
            teachingPenDesktop_.reset();
            if (sessionServices_->exportSelection(*pixels, action)
                == CaptureExportResult::failed) {
                showSessionError(CaptureSessionErrorCode::exportFailed);
            }
        } catch (...) {
            teachingPenOverlay_.reset();
            teachingPenDesktop_.reset();
            showSessionError(CaptureSessionErrorCode::allocationFailed);
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
    SystemPreferencesRegistry preferencesRegistry_;
    HotKeySettingsStore hotKeySettingsStore_{preferencesRegistry_};
    std::unique_ptr<WinCaptureSessionServices> sessionServices_;
    std::unique_ptr<CaptureSessionCoordinator> coordinator_;
    std::unique_ptr<TrayIcon> tray_;
    std::unique_ptr<HotKeyRegistrar> hotKey_;
    std::unique_ptr<PreferencesWindow> preferencesWindow_;
    std::unique_ptr<FullScreenCapturePreviewHost> fullScreenPreview_;
    std::unique_ptr<OcrCaptureHost> ocrCapture_;
    std::unique_ptr<FrozenDesktop> teachingPenDesktop_;
    std::unique_ptr<OverlayHost> teachingPenOverlay_;
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
