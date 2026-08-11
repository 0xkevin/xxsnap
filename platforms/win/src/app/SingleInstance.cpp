#include "app/SingleInstance.h"

#include <new>
#include <utility>

namespace xxsnap::win {
namespace {

constexpr wchar_t instanceMutexName[] = L"Local\\XxSnap.SingleInstance.v1";
constexpr wchar_t wakeMessageName[] = L"XxSnap.WakePrimary.v1";

class SystemSingleInstanceApi final : public SingleInstanceApi {
public:
    HANDLE createMutex(const wchar_t* name, DWORD& error) noexcept override
    {
        SetLastError(ERROR_SUCCESS);
        const auto handle = CreateMutexW(nullptr, FALSE, name);
        error = GetLastError();
        return handle;
    }

    UINT registerWindowMessage(
        const wchar_t* name, DWORD& error) noexcept override
    {
        const auto message = RegisterWindowMessageW(name);
        error = message == 0 ? GetLastError() : ERROR_SUCCESS;
        return message;
    }

    bool broadcast(UINT message, DWORD& error) noexcept override
    {
        if (PostMessageW(HWND_BROADCAST, message, 0, 0)) {
            error = ERROR_SUCCESS;
            return true;
        }
        error = GetLastError();
        return false;
    }

    void close(HANDLE handle) noexcept override
    {
        if (handle != nullptr) {
            CloseHandle(handle);
        }
    }
};

SingleInstanceCreateResult failure(
    SingleInstanceErrorCode code, DWORD nativeCode) noexcept
{
    return {
        SingleInstanceRole::failed,
        nullptr,
        SingleInstanceError{code, nativeCode},
    };
}

} // namespace

SingleInstanceApi& systemSingleInstanceApi() noexcept
{
    static SystemSingleInstanceApi api;
    return api;
}

SingleInstance::SingleInstance(
    SingleInstanceApi& api,
    HANDLE mutex,
    UINT wakeMessage,
    WakeCallback wakeCallback)
    : api_(api)
    , mutex_(mutex)
    , wakeMessage_(wakeMessage)
    , wakeCallback_(std::move(wakeCallback))
{
}

SingleInstance::~SingleInstance()
{
    if (mutex_ != nullptr) {
        api_.close(std::exchange(mutex_, nullptr));
    }
}

SingleInstanceCreateResult SingleInstance::create(
    SingleInstanceApi& api, WakeCallback wakeCallback)
{
    DWORD mutexError = ERROR_SUCCESS;
    const auto mutex = api.createMutex(instanceMutexName, mutexError);
    if (mutex == nullptr) {
        return failure(
            SingleInstanceErrorCode::mutexCreationFailed,
            mutexError == ERROR_SUCCESS ? ERROR_GEN_FAILURE : mutexError);
    }

    DWORD messageError = ERROR_SUCCESS;
    const auto message = api.registerWindowMessage(
        wakeMessageName, messageError);
    if (message == 0) {
        api.close(mutex);
        return failure(
            SingleInstanceErrorCode::messageRegistrationFailed,
            messageError == ERROR_SUCCESS ? ERROR_GEN_FAILURE : messageError);
    }

    if (mutexError == ERROR_ALREADY_EXISTS) {
        DWORD broadcastError = ERROR_SUCCESS;
        const auto sent = api.broadcast(message, broadcastError);
        api.close(mutex);
        if (!sent) {
            return failure(
                SingleInstanceErrorCode::wakeBroadcastFailed,
                broadcastError == ERROR_SUCCESS
                    ? ERROR_GEN_FAILURE
                    : broadcastError);
        }
        return {SingleInstanceRole::secondary, nullptr, std::nullopt};
    }
    if (mutexError != ERROR_SUCCESS) {
        api.close(mutex);
        return failure(SingleInstanceErrorCode::mutexCreationFailed, mutexError);
    }

    try {
        return {
            SingleInstanceRole::primary,
            std::unique_ptr<SingleInstance>(new SingleInstance(
                api, mutex, message, std::move(wakeCallback))),
            std::nullopt,
        };
    } catch (const std::bad_alloc&) {
        api.close(mutex);
        return failure(
            SingleInstanceErrorCode::mutexCreationFailed,
            ERROR_NOT_ENOUGH_MEMORY);
    }
}

UINT SingleInstance::wakeMessage() const noexcept
{
    return wakeMessage_;
}

bool SingleInstance::handleMessage(UINT message) noexcept
{
    if (message != wakeMessage_) {
        return false;
    }
    WakeCallback callback;
    try {
        callback = wakeCallback_;
    } catch (...) {
        return true;
    }
    if (callback) {
        try {
            callback();
        } catch (...) {
        }
    }
    return true;
}

} // namespace xxsnap::win
