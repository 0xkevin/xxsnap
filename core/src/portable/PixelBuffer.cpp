#include "snipory/core/portable/PixelBuffer.h"

#include <atomic>
#include <limits>
#include <new>
#include <stdexcept>
#include <utility>

#include "snipory/core/portable/Geometry.h"

namespace snipory::core::portable {

struct MemoryBudget::State {
    explicit State(std::uint64_t limit)
        : limitBytes(limit)
    {
    }

    std::uint64_t limitBytes;
    std::atomic<std::uint64_t> usedBytes{0};
};

MemoryBudget::Reservation::Reservation(
    std::shared_ptr<State> state,
    std::uint64_t byteCount) noexcept
    : state_(std::move(state))
    , byteCount_(byteCount)
{
}

MemoryBudget::Reservation::~Reservation()
{
    release();
}

MemoryBudget::Reservation::Reservation(Reservation&& other) noexcept
    : state_(std::move(other.state_))
    , byteCount_(std::exchange(other.byteCount_, 0))
{
}

MemoryBudget::Reservation& MemoryBudget::Reservation::operator=(Reservation&& other) noexcept
{
    if (this != &other) {
        release();
        state_ = std::move(other.state_);
        byteCount_ = std::exchange(other.byteCount_, 0);
    }
    return *this;
}

void MemoryBudget::Reservation::release() noexcept
{
    if (state_) {
        auto state = std::move(state_);
        const auto byteCount = std::exchange(byteCount_, 0);
        state->usedBytes.fetch_sub(byteCount, std::memory_order_acq_rel);
    }
}

MemoryBudget::MemoryBudget(std::uint64_t limitBytes)
    : state_(std::make_shared<State>(limitBytes))
{
}

MemoryBudget::~MemoryBudget() = default;

std::uint64_t MemoryBudget::limitBytes() const noexcept
{
    return state_->limitBytes;
}

std::uint64_t MemoryBudget::usedBytes() const noexcept
{
    return state_->usedBytes.load(std::memory_order_acquire);
}

std::optional<MemoryBudget::Reservation> MemoryBudget::reserve(
    std::uint64_t byteCount) noexcept
{
    auto current = state_->usedBytes.load(std::memory_order_relaxed);
    while (true) {
        if (byteCount > state_->limitBytes - current) {
            return std::nullopt;
        }
        if (state_->usedBytes.compare_exchange_weak(
                current,
                current + byteCount,
                std::memory_order_acq_rel,
                std::memory_order_relaxed)) {
            return Reservation(state_, byteCount);
        }
    }
}

PixelBuffer::PixelBuffer(
    std::int64_t width,
    std::int64_t height,
    std::uint64_t stride,
    std::vector<std::byte> bytes,
    MemoryBudget::Reservation reservation) noexcept
    : width_(width)
    , height_(height)
    , stride_(stride)
    , bytes_(std::move(bytes))
    , reservation_(std::move(reservation))
{
}

PixelBuffer::~PixelBuffer() = default;
PixelBuffer::PixelBuffer(PixelBuffer&&) noexcept = default;
PixelBuffer& PixelBuffer::operator=(PixelBuffer&&) noexcept = default;

PixelBufferAllocation PixelBuffer::allocate(
    std::int64_t width,
    std::int64_t height,
    MemoryBudget& budget) noexcept
{
    if (width <= 0 || height <= 0) {
        return {nullptr, PixelBufferError::invalidSize};
    }

    constexpr std::int64_t bytesPerPixel = 4;
    const auto byteCount = checkedByteCount(width, height, bytesPerPixel);
    if (!byteCount.has_value()
        || static_cast<std::uint64_t>(width) > std::numeric_limits<std::uint64_t>::max() / bytesPerPixel
        || *byteCount > std::numeric_limits<std::size_t>::max()
        || *byteCount > std::vector<std::byte>{}.max_size()) {
        return {nullptr, PixelBufferError::arithmeticOverflow};
    }

    auto reservation = budget.reserve(*byteCount);
    if (!reservation.has_value()) {
        return {nullptr, PixelBufferError::budgetExceeded};
    }

    try {
        std::vector<std::byte> bytes(static_cast<std::size_t>(*byteCount));
        const auto stride = static_cast<std::uint64_t>(width) * bytesPerPixel;
        auto value = std::unique_ptr<PixelBuffer>(new PixelBuffer(
            width,
            height,
            stride,
            std::move(bytes),
            std::move(*reservation)));
        return {std::move(value), std::nullopt};
    } catch (const std::bad_alloc&) {
        return {nullptr, PixelBufferError::allocationFailed};
    } catch (const std::length_error&) {
        return {nullptr, PixelBufferError::arithmeticOverflow};
    }
}

std::int64_t PixelBuffer::width() const noexcept
{
    return width_;
}

std::int64_t PixelBuffer::height() const noexcept
{
    return height_;
}

std::uint64_t PixelBuffer::stride() const noexcept
{
    return stride_;
}

PixelFormat PixelBuffer::format() const noexcept
{
    return format_;
}

std::byte* PixelBuffer::data() noexcept
{
    return bytes_.data();
}

const std::byte* PixelBuffer::data() const noexcept
{
    return bytes_.data();
}

std::size_t PixelBuffer::byteCount() const noexcept
{
    return bytes_.size();
}

} // namespace snipory::core::portable
