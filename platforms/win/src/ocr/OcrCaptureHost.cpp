#include "ocr/OcrCaptureHost.h"

#include "capture/DxgiCaptureBackend.h"
#include "capture/GdiCaptureBackend.h"
#include "export/ClipboardWriter.h"
#include "export/SelectionComposer.h"
#include "ocr/OcrEngine.h"
#include "overlay/OverlayHost.h"
#include "support/RuntimeApis.h"

#include <objbase.h>

#include <chrono>
#include <new>
#include <utility>
#include <variant>

namespace xxsnap::win {
namespace {

constexpr wchar_t hostWindowClass[] = L"XxSnap.OcrCaptureHost.v1";
constexpr UINT recognitionCompletedMessage = WM_APP + 0x71;
#if defined(_WIN64)
constexpr std::uint64_t ocrMemoryLimit = 2ULL * 1024ULL * 1024ULL * 1024ULL;
#else
constexpr std::uint64_t ocrMemoryLimit = 512ULL * 1024ULL * 1024ULL;
#endif

struct RecognitionCompletion {
    std::uint64_t generation = 0;
    PixelRect selection{};
    OcrResult result;
};

PixelRect cursorRect() noexcept
{
    POINT cursor{};
    GetCursorPos(&cursor);
    return {cursor.x, cursor.y, 1, 1};
}

} // namespace

struct OcrCaptureHost::Impl final {
    HINSTANCE instance = nullptr;
    HWND owner = nullptr;
    RuntimeApis& runtimeApis;
    DxgiCaptureBackend dxgi;
    GdiCaptureBackend gdi;
    FallbackCaptureBackend fallback{dxgi, gdi};
    OcrResultPresenter presenter;
    OcrCaptureHost::CompletionCallback completionCallback;
    HWND messageWindow = nullptr;
    std::unique_ptr<MemoryBudget> budget;
    std::unique_ptr<FrozenDesktop> desktop;
    std::unique_ptr<OverlayHost> overlay;
    std::thread worker;
    std::uint64_t generation = 0;
    bool active = false;

    Impl(HINSTANCE module, HWND sourceOwner, RuntimeApis& apis,
        OcrCaptureHost::CompletionCallback callback)
        : instance(module != nullptr ? module : GetModuleHandleW(nullptr))
        , owner(sourceOwner)
        , runtimeApis(apis)
        , presenter(instance, owner)
        , completionCallback(std::move(callback))
    {
    }

    ~Impl()
    {
        cancel();
        if (worker.joinable()) worker.join();
        if (messageWindow != nullptr) DestroyWindow(messageWindow);
        UnregisterClassW(hostWindowClass, instance);
    }

    static LRESULT CALLBACK windowProcedure(
        HWND window, UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        auto* self = reinterpret_cast<Impl*>(
            GetWindowLongPtrW(window, GWLP_USERDATA));
        if (message == WM_NCCREATE) {
            const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lParam);
            self = static_cast<Impl*>(create->lpCreateParams);
            self->messageWindow = window;
            SetWindowLongPtrW(
                window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
        }
        return self != nullptr
            ? self->handle(message, wParam, lParam)
            : DefWindowProcW(window, message, wParam, lParam);
    }

    bool ensureMessageWindow() noexcept
    {
        if (messageWindow != nullptr) return true;
        WNDCLASSEXW value{};
        value.cbSize = sizeof(value);
        value.lpfnWndProc = windowProcedure;
        value.hInstance = instance;
        value.lpszClassName = hostWindowClass;
        if (RegisterClassExW(&value) == 0
            && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
            return false;
        }
        messageWindow = CreateWindowExW(
            WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
            hostWindowClass, L"", WS_POPUP,
            0, 0, 0, 0, nullptr, nullptr, instance, this);
        return messageWindow != nullptr;
    }

    void releaseCapture() noexcept
    {
        overlay.reset();
        desktop.reset();
        budget.reset();
    }

    void cancel() noexcept
    {
        const auto wasActive = active;
        ++generation;
        active = false;
        releaseCapture();
        if (wasActive && completionCallback) completionCallback();
    }

    void showFailure(PixelRect selection) noexcept
    {
        presenter.showFailure(selection);
    }

    bool start() noexcept
    {
        if (active) return false;
        if (worker.joinable()) worker.join();
        if (!ensureMessageWindow()) return false;
        presenter.close();
        const auto requestGeneration = ++generation;
        active = true;
        try {
            bool topologyRetryUsed = false;
            for (;;) {
                auto topologyResult = snapshotDisplayTopology(runtimeApis);
                const auto* topology = topologyResult.value();
                if (topology == nullptr) {
                    showFailure(cursorRect());
                    cancel();
                    return false;
                }
                budget = std::make_unique<MemoryBudget>(ocrMemoryLimit);
                auto capture = fallback.capture(*topology, *budget);
                if (!std::holds_alternative<FrozenDesktop>(capture)) {
                    showFailure(cursorRect());
                    cancel();
                    return false;
                }
                desktop = std::make_unique<FrozenDesktop>(
                    std::move(std::get<FrozenDesktop>(capture)));
                auto verifiedResult = snapshotDisplayTopology(runtimeApis);
                const auto* verified = verifiedResult.value();
                if (verified != nullptr
                    && desktop->topology.fingerprint() == verified->fingerprint()) {
                    break;
                }
                desktop.reset();
                budget.reset();
                if (topologyRetryUsed) {
                    showFailure(cursorRect());
                    cancel();
                    return false;
                }
                topologyRetryUsed = true;
            }

            auto created = OverlayHost::createTextRecognition(
                instance, *desktop,
                [this, requestGeneration] {
                    if (active && generation == requestGeneration) {
                        releaseCapture();
                        active = false;
                        start();
                    }
                },
                [this, requestGeneration](OverlayInputAction action) {
                    if (!active || generation != requestGeneration) return;
                    if (action == OverlayInputAction::cancel) {
                        cancel();
                        return;
                    }
                    if (action != OverlayInputAction::recognizeText) {
                        cancel();
                        return;
                    }
                    beginRecognition(requestGeneration);
                });
            overlay = std::move(created.value);
            if (overlay == nullptr) {
                showFailure(cursorRect());
                cancel();
                return false;
            }
            overlay->show();
            return true;
        } catch (...) {
            showFailure(cursorRect());
            cancel();
            return false;
        }
    }

    void beginRecognition(std::uint64_t requestGeneration) noexcept
    {
        if (!overlay || !desktop || !budget) {
            showFailure(cursorRect());
            cancel();
            return;
        }
        const auto selected = overlay->selection();
        if (!selected.has_value()) {
            showFailure(cursorRect());
            cancel();
            return;
        }
        auto composition = composeSelection(*selected, *desktop, *budget);
        if (!std::holds_alternative<PixelBuffer>(composition)) {
            showFailure(*selected);
            cancel();
            return;
        }
        auto pixels = std::move(std::get<PixelBuffer>(composition));
        overlay.reset();
        desktop.reset();
        budget.reset();
        const auto targetWindow = messageWindow;
        try {
            worker = std::thread([
                targetWindow,
                requestGeneration,
                selection = *selected,
                pixels = std::move(pixels)]() mutable {
                const HRESULT com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
                auto completion = std::make_unique<RecognitionCompletion>();
                completion->generation = requestGeneration;
                completion->selection = selection;
                completion->result = recognizeText(pixels);
                if (com == S_OK || com == S_FALSE) CoUninitialize();
                auto* payload = completion.release();
                if (!PostMessageW(targetWindow, recognitionCompletedMessage,
                        0, reinterpret_cast<LPARAM>(payload))) {
                    delete payload;
                }
            });
        } catch (...) {
            showFailure(*selected);
            cancel();
        }
    }

    void finishRecognition(RecognitionCompletion completion) noexcept
    {
        if (completion.generation != generation) return;
        if (worker.joinable()) worker.join();
        active = false;
        if (completion.result.status == OcrStatus::completed
            && writeClipboardText(completion.result.text, owner).succeeded()) {
            presenter.showSuccess(completion.selection);
        } else {
            presenter.showFailure(completion.selection);
        }
        if (completionCallback) completionCallback();
    }

    LRESULT handle(UINT message, WPARAM wParam, LPARAM lParam) noexcept
    {
        if (message == recognitionCompletedMessage) {
            std::unique_ptr<RecognitionCompletion> completion(
                reinterpret_cast<RecognitionCompletion*>(lParam));
            if (completion) finishRecognition(std::move(*completion));
            return 0;
        }
        if (message == WM_NCDESTROY) {
            messageWindow = nullptr;
            return 0;
        }
        return DefWindowProcW(messageWindow, message, wParam, lParam);
    }
};

OcrCaptureHost::OcrCaptureHost(
    HINSTANCE instance, HWND owner, RuntimeApis& runtimeApis,
    CompletionCallback completionCallback)
    : impl_(std::make_unique<Impl>(instance, owner, runtimeApis,
          std::move(completionCallback)))
{
}

OcrCaptureHost::~OcrCaptureHost() = default;

bool OcrCaptureHost::start() noexcept
{
    return impl_->start();
}

void OcrCaptureHost::cancel() noexcept
{
    impl_->cancel();
}

bool OcrCaptureHost::busy() const noexcept
{
    return impl_->active;
}

} // namespace xxsnap::win
