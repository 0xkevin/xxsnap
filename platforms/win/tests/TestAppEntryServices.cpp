#include "app/HotKeyRegistrar.h"
#include "app/SingleInstance.h"
#include "app/TrayIcon.h"

#include <Windows.h>

#include <array>
#include <functional>
#include <iostream>
#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace {

using xxsnap::win::AppHotKey;
using xxsnap::win::HotKeyApi;
using xxsnap::win::HotKeyBinding;
using xxsnap::win::HotKeyCommand;
using xxsnap::win::HotKeyRegistrar;
using xxsnap::win::SingleInstance;
using xxsnap::win::SingleInstanceApi;
using xxsnap::win::SingleInstanceRole;
using xxsnap::win::TrayCommand;
using xxsnap::win::TrayIcon;
using xxsnap::win::TrayIconApi;
using xxsnap::win::TrayMenuItem;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": " << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

class FakeSingleInstanceApi final : public SingleInstanceApi {
public:
    HANDLE createMutex(const wchar_t* name, DWORD& error) noexcept override
    {
        mutexName = name;
        error = createError;
        return createSucceeds ? reinterpret_cast<HANDLE>(0x101) : nullptr;
    }

    UINT registerWindowMessage(const wchar_t* name, DWORD& error) noexcept override
    {
        messageName = name;
        error = messageError;
        return messageId;
    }

    bool broadcast(UINT message, DWORD& error) noexcept override
    {
        ++broadcastCalls;
        broadcastMessage = message;
        error = broadcastError;
        return broadcastSucceeds;
    }

    void close(HANDLE handle) noexcept override
    {
        ++closeCalls;
        closedHandle = handle;
    }

    bool createSucceeds = true;
    DWORD createError = ERROR_SUCCESS;
    UINT messageId = 0xC123U;
    DWORD messageError = ERROR_SUCCESS;
    bool broadcastSucceeds = true;
    DWORD broadcastError = ERROR_SUCCESS;
    std::wstring mutexName;
    std::wstring messageName;
    int broadcastCalls = 0;
    UINT broadcastMessage = 0;
    int closeCalls = 0;
    HANDLE closedHandle = nullptr;
};

void testSingleInstancePrimarySecondaryAndRollback()
{
    FakeSingleInstanceApi primaryApi;
    int wakeCalls = 0;
    std::unique_ptr<SingleInstance> primary;
    auto primaryResult = SingleInstance::create(primaryApi, [&] {
        ++wakeCalls;
        primary.reset();
    });
    CHECK(primaryResult.role == SingleInstanceRole::primary);
    CHECK(primaryResult.instance != nullptr);
    CHECK(!primaryResult.error.has_value());
    CHECK(primaryApi.mutexName.rfind(L"Local\\", 0) == 0U);
    CHECK(!primaryApi.messageName.empty());
    primary = std::move(primaryResult.instance);
    const auto wakeMessage = primary->wakeMessage();
    auto* primaryDuringWake = primary.get();
    CHECK(primaryDuringWake->handleMessage(wakeMessage));
    CHECK(wakeCalls == 1);
    CHECK(primary == nullptr);
    CHECK(primaryApi.closeCalls == 1);

    FakeSingleInstanceApi secondaryApi;
    secondaryApi.createError = ERROR_ALREADY_EXISTS;
    auto secondary = SingleInstance::create(secondaryApi, [] {});
    CHECK(secondary.role == SingleInstanceRole::secondary);
    CHECK(secondary.instance == nullptr);
    CHECK(secondaryApi.broadcastCalls == 1);
    CHECK(secondaryApi.broadcastMessage == secondaryApi.messageId);
    CHECK(secondaryApi.closeCalls == 1);

    FakeSingleInstanceApi messageFailure;
    messageFailure.messageId = 0U;
    messageFailure.messageError = ERROR_INVALID_FUNCTION;
    auto failed = SingleInstance::create(messageFailure, [] {});
    CHECK(failed.role == SingleInstanceRole::failed);
    CHECK(failed.error.has_value());
    CHECK(messageFailure.closeCalls == 1);

    FakeSingleInstanceApi broadcastFailure;
    broadcastFailure.createError = ERROR_ALREADY_EXISTS;
    broadcastFailure.broadcastSucceeds = false;
    broadcastFailure.broadcastError = ERROR_ACCESS_DENIED;
    auto notWoken = SingleInstance::create(broadcastFailure, [] {});
    CHECK(notWoken.role == SingleInstanceRole::failed);
    CHECK(notWoken.error.has_value());
    CHECK(notWoken.error->nativeCode == ERROR_ACCESS_DENIED);
    CHECK(broadcastFailure.closeCalls == 1);
}

struct NotifyCall {
    DWORD operation;
    UINT flags;
    UINT version;
};

class FakeTrayIconApi final : public TrayIconApi {
public:
    UINT registerWindowMessage(const wchar_t* name, DWORD& error) noexcept override
    {
        taskbarMessageName = name;
        error = taskbarMessageError;
        return taskbarMessage;
    }

    bool notifyIcon(
        DWORD operation,
        const NOTIFYICONDATAW& data,
        DWORD& error) noexcept override
    {
        calls.push_back({operation, data.uFlags, data.uVersion});
        error = notifyError;
        if (failOperation.has_value() && *failOperation == operation) {
            return false;
        }
        return true;
    }

    std::optional<TrayCommand> showContextMenu(
        HWND,
        const std::array<TrayMenuItem, 4>& items,
        DWORD& error) noexcept override
    {
        ++menuCalls;
        menuItems = items;
        error = menuError;
        if (onShowContextMenu) {
            onShowContextMenu();
        }
        return nextCommand;
    }

    UINT taskbarMessage = 0xC234U;
    DWORD taskbarMessageError = ERROR_SUCCESS;
    DWORD notifyError = ERROR_INVALID_FUNCTION;
    std::optional<DWORD> failOperation;
    std::optional<TrayCommand> nextCommand;
    DWORD menuError = ERROR_SUCCESS;
    std::wstring taskbarMessageName;
    std::vector<NotifyCall> calls;
    int menuCalls = 0;
    std::array<TrayMenuItem, 4> menuItems{};
    std::function<void()> onShowContextMenu;
};

void testTrayLifecycleMenuAndExplorerRestart()
{
    FakeTrayIconApi api;
    std::vector<TrayCommand> commands;
    std::unique_ptr<TrayIcon> tray;
    auto result = TrayIcon::create(
        api,
        reinterpret_cast<HWND>(0x201),
        reinterpret_cast<HICON>(0x202),
        [&](TrayCommand command) {
            commands.push_back(command);
            tray.reset();
        });
    CHECK(result.value != nullptr);
    CHECK(!result.error.has_value());
    CHECK(api.calls.size() == 2U);
    CHECK(api.calls[0].operation == NIM_ADD);
    CHECK(api.calls[1].operation == NIM_SETVERSION);
    CHECK(api.calls[1].version == NOTIFYICON_VERSION_4);
    CHECK(result.value->taskbarCreatedMessage() == api.taskbarMessage);

    tray = std::move(result.value);
    CHECK(tray->handleMessage(api.taskbarMessage, 0, 0));
    CHECK(api.calls.size() == 4U);
    CHECK(api.calls[2].operation == NIM_ADD);
    CHECK(api.calls[3].operation == NIM_SETVERSION);

    api.nextCommand = TrayCommand::regionCapture;
    auto* trayDuringCallback = tray.get();
    CHECK(trayDuringCallback->handleMessage(
        xxsnap::win::trayCallbackMessage,
        0,
        MAKELPARAM(WM_RBUTTONUP, xxsnap::win::trayIconIdentifier)));
    CHECK(commands == std::vector<TrayCommand>{TrayCommand::regionCapture});
    CHECK(tray == nullptr);
    CHECK(api.menuCalls == 1);
    CHECK(api.menuItems[0].command == TrayCommand::regionCapture);
    CHECK(std::wstring(api.menuItems[0].label) == L"\u533a\u57df\u622a\u56fe");
    CHECK(api.menuItems[1].command == TrayCommand::fullScreenCapture);
    CHECK(std::wstring(api.menuItems[1].label) == L"\u5168\u5c4f\u622a\u56fe");
    CHECK(api.menuItems[2].command == TrayCommand::textRecognition);
    CHECK(std::wstring(api.menuItems[2].label) == L"\u6587\u5b57\u8bc6\u522b");
    CHECK(api.menuItems[3].command == TrayCommand::exit);
    CHECK(std::wstring(api.menuItems[3].label) == L"\u9000\u51fa");
    CHECK(api.calls.back().operation == NIM_DELETE);
}

void testTrayMenuLoopMaySynchronouslyDestroyTray()
{
    FakeTrayIconApi api;
    api.nextCommand = TrayCommand::regionCapture;
    int callbackCalls = 0;
    std::unique_ptr<TrayIcon> tray;
    auto result = TrayIcon::create(
        api,
        reinterpret_cast<HWND>(0x231),
        reinterpret_cast<HICON>(0x232),
        [&](TrayCommand) { ++callbackCalls; });
    CHECK(result.value != nullptr);
    tray = std::move(result.value);
    api.onShowContextMenu = [&] { tray.reset(); };
    auto* trayDuringMenu = tray.get();
    CHECK(trayDuringMenu->handleMessage(
        xxsnap::win::trayCallbackMessage,
        0,
        MAKELPARAM(WM_RBUTTONUP, xxsnap::win::trayIconIdentifier)));
    CHECK(tray == nullptr);
    CHECK(callbackCalls == 1);

    FakeTrayIconApi wrongIconApi;
    auto wrongIconResult = TrayIcon::create(
        wrongIconApi,
        reinterpret_cast<HWND>(0x241),
        reinterpret_cast<HICON>(0x242),
        [](TrayCommand) {});
    CHECK(wrongIconResult.value != nullptr);
    CHECK(!wrongIconResult.value->handleMessage(
        xxsnap::win::trayCallbackMessage,
        0,
        MAKELPARAM(WM_RBUTTONUP, xxsnap::win::trayIconIdentifier + 1)));
}

void testTrayRollbackAndConflictNotification()
{
    FakeTrayIconApi setVersionFailure;
    setVersionFailure.failOperation = NIM_SETVERSION;
    auto failed = TrayIcon::create(
        setVersionFailure,
        reinterpret_cast<HWND>(0x211),
        reinterpret_cast<HICON>(0x212),
        [](TrayCommand) {});
    CHECK(failed.value == nullptr);
    CHECK(failed.error.has_value());
    CHECK(setVersionFailure.calls.size() == 3U);
    CHECK(setVersionFailure.calls.back().operation == NIM_DELETE);

    FakeTrayIconApi api;
    auto result = TrayIcon::create(
        api,
        reinterpret_cast<HWND>(0x221),
        reinterpret_cast<HICON>(0x222),
        [](TrayCommand) {});
    CHECK(result.value != nullptr);
    CHECK(result.value->showHotKeyConflict(
        L"Ctrl+` \u5df2\u88ab\u5360\u7528"));
    CHECK(api.calls.back().operation == NIM_MODIFY);
    CHECK((api.calls.back().flags & NIF_INFO) != 0U);

    api.failOperation = NIM_ADD;
    CHECK(result.value->handleMessage(api.taskbarMessage, 0, 0));
    CHECK(result.value->lastError().has_value());
    CHECK(result.value->lastError()->code
        == xxsnap::win::TrayIconErrorCode::addFailed);
}

struct HotKeyCall {
    HWND window;
    int identifier;
    UINT modifiers;
    UINT virtualKey;
};

class FakeHotKeyApi final : public HotKeyApi {
public:
    bool registerHotKey(
        HWND window,
        int identifier,
        UINT modifiers,
        UINT virtualKey,
        DWORD& error) noexcept override
    {
        registrations.push_back({window, identifier, modifiers, virtualKey});
        error = registerError;
        return registerSucceeds;
    }

    bool unregisterHotKey(HWND window, int identifier, DWORD& error) noexcept override
    {
        ++unregisterCalls;
        unregisteredWindow = window;
        unregisteredIdentifier = identifier;
        error = unregisterError;
        return unregisterSucceeds;
    }

    bool registerSucceeds = true;
    DWORD registerError = ERROR_SUCCESS;
    bool unregisterSucceeds = true;
    DWORD unregisterError = ERROR_SUCCESS;
    std::vector<HotKeyCall> registrations;
    int unregisterCalls = 0;
    HWND unregisteredWindow = nullptr;
    int unregisteredIdentifier = 0;
};

void testAllDefaultMappingsAndMvpRegistration()
{
    constexpr auto bindings = xxsnap::win::defaultAppHotKeys();
    static_assert(bindings.size() == 5U);
    CHECK((bindings[0] == HotKeyBinding{
        HotKeyCommand::regionCapture, MOD_CONTROL, VK_OEM_3}));
    CHECK((bindings[1] == HotKeyBinding{
        HotKeyCommand::fullScreen, MOD_CONTROL | MOD_SHIFT, '1'}));
    CHECK((bindings[2] == HotKeyBinding{
        HotKeyCommand::ocr, MOD_CONTROL, '3'}));
    CHECK((bindings[3] == HotKeyBinding{
        HotKeyCommand::teachingPen, MOD_CONTROL, '2'}));
    CHECK((bindings[4] == HotKeyBinding{
        HotKeyCommand::restoreMostRecentlyHiddenPinnedImage,
        MOD_CONTROL, '1'}));

    FakeHotKeyApi api;
    int callbackCalls = 0;
    std::unique_ptr<HotKeyRegistrar> registrar;
    registrar = std::make_unique<HotKeyRegistrar>(api, [&] {
        ++callbackCalls;
        registrar.reset();
    });
    const auto window = reinterpret_cast<HWND>(0x301);
    CHECK(registrar->registerMvpRegionCapture(window));
    CHECK(api.registrations.size() == 1U);
    CHECK(api.registrations[0].modifiers == MOD_CONTROL);
    CHECK(api.registrations[0].virtualKey == VK_OEM_3);
    int restoreCalls = 0;
    int fullScreenCalls = 0;
    int ocrCalls = 0;
    CHECK(registrar->registerFullScreenCapture(
        window, [&] { ++fullScreenCalls; }));
    CHECK(api.registrations.size() == 2U);
    CHECK(api.registrations[1].identifier
        == xxsnap::win::fullScreenCaptureHotKeyIdentifier);
    CHECK(api.registrations[1].modifiers == (MOD_CONTROL | MOD_SHIFT));
    CHECK(api.registrations[1].virtualKey == '1');
    CHECK(registrar->handleMessage(
        WM_HOTKEY,
        static_cast<WPARAM>(
            xxsnap::win::fullScreenCaptureHotKeyIdentifier)));
    CHECK(fullScreenCalls == 1);
    CHECK(registrar->registerOcr(window, [&] { ++ocrCalls; }));
    CHECK(api.registrations.size() == 3U);
    CHECK(api.registrations[2].identifier
        == xxsnap::win::ocrHotKeyIdentifier);
    CHECK(api.registrations[2].modifiers == MOD_CONTROL);
    CHECK(api.registrations[2].virtualKey == '3');
    CHECK(registrar->handleMessage(
        WM_HOTKEY,
        static_cast<WPARAM>(xxsnap::win::ocrHotKeyIdentifier)));
    CHECK(ocrCalls == 1);
    CHECK(registrar->registerRestorePinnedImage(
        window, [&] { ++restoreCalls; }));
    CHECK(api.registrations.size() == 4U);
    CHECK(api.registrations[3].identifier
        == xxsnap::win::restorePinnedImageHotKeyIdentifier);
    CHECK(api.registrations[3].modifiers == MOD_CONTROL);
    CHECK(api.registrations[3].virtualKey == '1');
    CHECK(registrar->handleMessage(
        WM_HOTKEY,
        static_cast<WPARAM>(
            xxsnap::win::restorePinnedImageHotKeyIdentifier)));
    CHECK(restoreCalls == 1);
    auto* registrarDuringCallback = registrar.get();
    CHECK(registrarDuringCallback->handleMessage(
        WM_HOTKEY,
        static_cast<WPARAM>(xxsnap::win::regionCaptureHotKeyIdentifier)));
    CHECK(callbackCalls == 1);
    CHECK(registrar == nullptr);
    CHECK(api.unregisterCalls == 4);
}

void testHotKeyConflictAndCleanupAreExplicit()
{
    FakeHotKeyApi conflict;
    conflict.registerSucceeds = false;
    conflict.registerError = ERROR_HOTKEY_ALREADY_REGISTERED;
    HotKeyRegistrar failed(conflict, [] {});
    CHECK(!failed.registerMvpRegionCapture(reinterpret_cast<HWND>(0x311)));
    CHECK(failed.lastError().has_value());
    CHECK(failed.lastError()->nativeCode == ERROR_HOTKEY_ALREADY_REGISTERED);
    CHECK(conflict.registrations.size() == 1U);
    CHECK(conflict.unregisterCalls == 0);

    FakeHotKeyApi restoreConflict;
    HotKeyRegistrar restoreFailed(restoreConflict, [] {});
    const auto restoreWindow = reinterpret_cast<HWND>(0x312);
    CHECK(restoreFailed.registerMvpRegionCapture(restoreWindow));
    restoreConflict.registerSucceeds = false;
    restoreConflict.registerError = ERROR_HOTKEY_ALREADY_REGISTERED;
    CHECK(!restoreFailed.registerRestorePinnedImage(
        restoreWindow, [] {}));
    CHECK(restoreFailed.lastError().has_value());
    CHECK(restoreFailed.lastError()->nativeCode
        == ERROR_HOTKEY_ALREADY_REGISTERED);

    FakeHotKeyApi api;
    {
        HotKeyRegistrar registered(api, [] {});
        CHECK(registered.registerMvpRegionCapture(reinterpret_cast<HWND>(0x321)));
        CHECK(registered.unregister());
        CHECK(registered.unregister());
    }
    CHECK(api.unregisterCalls == 1);

    FakeHotKeyApi unregisterFailure;
    unregisterFailure.unregisterSucceeds = false;
    unregisterFailure.unregisterError = ERROR_ACCESS_DENIED;
    {
        HotKeyRegistrar registered(unregisterFailure, [] {});
        CHECK(registered.registerMvpRegionCapture(
            reinterpret_cast<HWND>(0x331)));
        CHECK(!registered.unregister());
        CHECK(registered.lastError().has_value());
        CHECK(registered.lastError()->nativeCode == ERROR_ACCESS_DENIED);
    }
    CHECK(unregisterFailure.unregisterCalls == 2);
}

} // namespace

int main()
{
    testSingleInstancePrimarySecondaryAndRollback();
    testTrayLifecycleMenuAndExplorerRestart();
    testTrayRollbackAndConflictNotification();
    testTrayMenuLoopMaySynchronouslyDestroyTray();
    testAllDefaultMappingsAndMvpRegistration();
    testHotKeyConflictAndCleanupAreExplicit();

    if (failureCount != 0) {
        std::cerr << failureCount << " app entry service check(s) failed\n";
        return 1;
    }
    std::cout << "App entry service checks passed\n";
    return 0;
}
