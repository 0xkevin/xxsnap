#pragma once

#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>
#include <vector>

namespace snipory::core::portable {

enum class PixelFormat {
    bgra8Premultiplied,
};

enum class PixelBufferError {
    invalidSize,
    arithmeticOverflow,
    budgetExceeded,
    allocationFailed,
};

class PixelBuffer;

struct PixelBufferAllocation {
    std::unique_ptr<PixelBuffer> value;
    std::optional<PixelBufferError> error;
};

class MemoryBudget final {
public:
    explicit MemoryBudget(std::uint64_t limitBytes);
    ~MemoryBudget();

    MemoryBudget(const MemoryBudget&) = delete;
    MemoryBudget& operator=(const MemoryBudget&) = delete;
    MemoryBudget(MemoryBudget&&) = delete;
    MemoryBudget& operator=(MemoryBudget&&) = delete;

    std::uint64_t limitBytes() const noexcept;
    std::uint64_t usedBytes() const noexcept;

private:
    struct State;
    class Reservation final {
    public:
        Reservation() noexcept = default;
        ~Reservation();

        Reservation(const Reservation&) = delete;
        Reservation& operator=(const Reservation&) = delete;
        Reservation(Reservation&& other) noexcept;
        Reservation& operator=(Reservation&& other) noexcept;

    private:
        Reservation(std::shared_ptr<State> state, std::uint64_t byteCount) noexcept;
        void release() noexcept;

        std::shared_ptr<State> state_;
        std::uint64_t byteCount_ = 0;

        friend class MemoryBudget;
    };

    std::optional<Reservation> reserve(std::uint64_t byteCount) noexcept;

    std::shared_ptr<State> state_;

    friend class PixelBuffer;
};

class PixelBuffer final {
public:
    ~PixelBuffer();

    PixelBuffer(const PixelBuffer&) = delete;
    PixelBuffer& operator=(const PixelBuffer&) = delete;
    PixelBuffer(PixelBuffer&&) noexcept;
    PixelBuffer& operator=(PixelBuffer&&) noexcept;

    static PixelBufferAllocation allocate(
        std::int64_t width,
        std::int64_t height,
        MemoryBudget& budget) noexcept;

    std::int64_t width() const noexcept;
    std::int64_t height() const noexcept;
    std::uint64_t stride() const noexcept;
    PixelFormat format() const noexcept;
    std::byte* data() noexcept;
    const std::byte* data() const noexcept;
    std::size_t byteCount() const noexcept;

private:
    PixelBuffer(
        std::int64_t width,
        std::int64_t height,
        std::uint64_t stride,
        std::vector<std::byte> bytes,
        MemoryBudget::Reservation reservation) noexcept;

    std::int64_t width_ = 0;
    std::int64_t height_ = 0;
    std::uint64_t stride_ = 0;
    PixelFormat format_ = PixelFormat::bgra8Premultiplied;
    std::vector<std::byte> bytes_;
    MemoryBudget::Reservation reservation_;
};

} // namespace snipory::core::portable
