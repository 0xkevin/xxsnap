#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <Windows.h>

#include <functional>
#include <memory>
#include <optional>

namespace xxsnap::win {

class SingleInstanceApi {
public:
    virtual ~SingleInstanceApi() = default;
    virtual HANDLE createMutex(const wchar_t* name, DWORD& error) noexcept = 0;
    virtual UINT registerWindowMessage(
        const wchar_t* name, DWORD& error) noexcept = 0;
    virtual bool broadcast(UINT message, DWORD& error) noexcept = 0;
    virtual void close(HANDLE handle) noexcept = 0;
};

SingleInstanceApi& systemSingleInstanceApi() noexcept;

enum class SingleInstanceRole {
    primary,
    secondary,
    failed,
};

enum class SingleInstanceErrorCode {
    mutexCreationFailed,
    messageRegistrationFailed,
    wakeBroadcastFailed,
};

struct SingleInstanceError {
    SingleInstanceErrorCode code;
    DWORD nativeCode;
};

struct SingleInstanceCreateResult;

class SingleInstance final {
public:
    using WakeCallback = std::function<void()>;

    ~SingleInstance();
    SingleInstance(const SingleInstance&) = delete;
    SingleInstance& operator=(const SingleInstance&) = delete;

    static SingleInstanceCreateResult create(
        SingleInstanceApi& api, WakeCallback wakeCallback);

    UINT wakeMessage() const noexcept;
    bool handleMessage(UINT message) noexcept;

private:
    SingleInstance(
        SingleInstanceApi& api,
        HANDLE mutex,
        UINT wakeMessage,
        WakeCallback wakeCallback);

    SingleInstanceApi& api_;
    HANDLE mutex_ = nullptr;
    UINT wakeMessage_ = 0;
    WakeCallback wakeCallback_;
};

struct SingleInstanceCreateResult {
    SingleInstanceRole role = SingleInstanceRole::failed;
    std::unique_ptr<SingleInstance> instance;
    std::optional<SingleInstanceError> error;
};

} // namespace xxsnap::win
