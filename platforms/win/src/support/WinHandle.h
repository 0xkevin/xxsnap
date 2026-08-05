#pragma once

#include <functional>
#include <utility>

#include <Windows.h>

namespace xxsnap::win {

using ReleaseDcFunction = std::function<int(HWND, HDC)>;
using DeleteDcFunction = std::function<BOOL(HDC)>;
using DeleteObjectFunction = std::function<BOOL(HGDIOBJ)>;
using SelectObjectFunction = std::function<HGDIOBJ(HDC, HGDIOBJ)>;

class WindowDc final {
public:
    WindowDc() noexcept = default;
    WindowDc(HWND window, HDC handle, const ReleaseDcFunction* release) noexcept
        : window_(window)
        , handle_(handle)
        , release_(release)
    {
    }

    ~WindowDc() { reset(); }

    WindowDc(const WindowDc&) = delete;
    WindowDc& operator=(const WindowDc&) = delete;

    WindowDc(WindowDc&& other) noexcept
        : window_(std::exchange(other.window_, nullptr))
        , handle_(std::exchange(other.handle_, nullptr))
        , release_(std::exchange(other.release_, nullptr))
    {
    }

    WindowDc& operator=(WindowDc&& other) noexcept
    {
        if (this != &other) {
            reset();
            window_ = std::exchange(other.window_, nullptr);
            handle_ = std::exchange(other.handle_, nullptr);
            release_ = std::exchange(other.release_, nullptr);
        }
        return *this;
    }

    HDC get() const noexcept { return handle_; }

private:
    void reset() noexcept
    {
        if (handle_ != nullptr && release_ != nullptr) {
            const auto handle = std::exchange(handle_, nullptr);
            try {
                (*release_)(window_, handle);
            } catch (...) {
            }
        }
    }

    HWND window_ = nullptr;
    HDC handle_ = nullptr;
    const ReleaseDcFunction* release_ = nullptr;
};

class MemoryDc final {
public:
    MemoryDc() noexcept = default;
    MemoryDc(HDC handle, const DeleteDcFunction* destroy) noexcept
        : handle_(handle)
        , destroy_(destroy)
    {
    }

    ~MemoryDc() { reset(); }

    MemoryDc(const MemoryDc&) = delete;
    MemoryDc& operator=(const MemoryDc&) = delete;

    MemoryDc(MemoryDc&& other) noexcept
        : handle_(std::exchange(other.handle_, nullptr))
        , destroy_(std::exchange(other.destroy_, nullptr))
    {
    }

    MemoryDc& operator=(MemoryDc&& other) noexcept
    {
        if (this != &other) {
            reset();
            handle_ = std::exchange(other.handle_, nullptr);
            destroy_ = std::exchange(other.destroy_, nullptr);
        }
        return *this;
    }

    HDC get() const noexcept { return handle_; }

private:
    void reset() noexcept
    {
        if (handle_ != nullptr && destroy_ != nullptr) {
            const auto handle = std::exchange(handle_, nullptr);
            try {
                (*destroy_)(handle);
            } catch (...) {
            }
        }
    }

    HDC handle_ = nullptr;
    const DeleteDcFunction* destroy_ = nullptr;
};

class BitmapHandle final {
public:
    BitmapHandle() noexcept = default;
    BitmapHandle(HBITMAP handle, const DeleteObjectFunction* destroy) noexcept
        : handle_(handle)
        , destroy_(destroy)
    {
    }

    ~BitmapHandle() { reset(); }

    BitmapHandle(const BitmapHandle&) = delete;
    BitmapHandle& operator=(const BitmapHandle&) = delete;

    BitmapHandle(BitmapHandle&& other) noexcept
        : handle_(std::exchange(other.handle_, nullptr))
        , destroy_(std::exchange(other.destroy_, nullptr))
    {
    }

    BitmapHandle& operator=(BitmapHandle&& other) noexcept
    {
        if (this != &other) {
            reset();
            handle_ = std::exchange(other.handle_, nullptr);
            destroy_ = std::exchange(other.destroy_, nullptr);
        }
        return *this;
    }

    HBITMAP get() const noexcept { return handle_; }

private:
    void reset() noexcept
    {
        if (handle_ != nullptr && destroy_ != nullptr) {
            const auto handle = std::exchange(handle_, nullptr);
            try {
                (*destroy_)(handle);
            } catch (...) {
            }
        }
    }

    HBITMAP handle_ = nullptr;
    const DeleteObjectFunction* destroy_ = nullptr;
};

class SelectedObject final {
public:
    SelectedObject() noexcept = default;
    SelectedObject(
        HDC dc,
        HGDIOBJ previous,
        const SelectObjectFunction* selectObject) noexcept
        : dc_(dc)
        , previous_(previous)
        , selectObject_(selectObject)
    {
    }

    ~SelectedObject() { restore(); }

    SelectedObject(const SelectedObject&) = delete;
    SelectedObject& operator=(const SelectedObject&) = delete;

    SelectedObject(SelectedObject&& other) noexcept
        : dc_(std::exchange(other.dc_, nullptr))
        , previous_(std::exchange(other.previous_, nullptr))
        , selectObject_(std::exchange(other.selectObject_, nullptr))
    {
    }

    SelectedObject& operator=(SelectedObject&& other) noexcept
    {
        if (this != &other) {
            restore();
            dc_ = std::exchange(other.dc_, nullptr);
            previous_ = std::exchange(other.previous_, nullptr);
            selectObject_ = std::exchange(other.selectObject_, nullptr);
        }
        return *this;
    }

    bool restore() noexcept
    {
        if (dc_ != nullptr && previous_ != nullptr && selectObject_ != nullptr) {
            const auto dc = std::exchange(dc_, nullptr);
            const auto previous = std::exchange(previous_, nullptr);
            try {
                const auto restored = (*selectObject_)(dc, previous);
                return restored != nullptr && restored != HGDI_ERROR;
            } catch (...) {
                return false;
            }
        }
        return true;
    }

private:
    HDC dc_ = nullptr;
    HGDIOBJ previous_ = nullptr;
    const SelectObjectFunction* selectObject_ = nullptr;
};

} // namespace xxsnap::win
