#include <atomic>
#include <cstddef>
#include <cstdint>
#include <iostream>
#include <limits>
#include <optional>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>

#include "snipory/core/portable/PixelBuffer.h"

using namespace snipory::core::portable;

namespace {

int checkFailed(const char* expression, const char* file, int line)
{
    std::cerr << file << ':' << line << ": CHECK failed: " << expression << '\n';
    return 1;
}

} // namespace

#define CHECK(expression) \
    do { \
        if (!(expression)) { \
            return checkFailed(#expression, __FILE__, __LINE__); \
        } \
    } while (false)

template<typename Buffer, typename = void>
struct HasResizableBytesView : std::false_type {
};

template<typename Buffer>
struct HasResizableBytesView<
    Buffer,
    std::void_t<decltype(std::declval<Buffer&>().bytes().resize(std::size_t{}))>>
    : std::true_type {
};

int main()
{
    static_assert(!std::is_copy_constructible_v<PixelBuffer>);
    static_assert(!std::is_copy_assignable_v<PixelBuffer>);
    static_assert(std::is_move_constructible_v<PixelBuffer>);
    static_assert(std::is_move_assignable_v<PixelBuffer>);
    static_assert(!HasResizableBytesView<PixelBuffer>::value);

    {
        MemoryBudget budget(24);
        auto allocation = PixelBuffer::allocate(3, 2, budget);

        CHECK(allocation.value != nullptr);
        CHECK(!allocation.error.has_value());
        CHECK(allocation.value->width() == 3);
        CHECK(allocation.value->height() == 2);
        CHECK(allocation.value->stride() == 12);
        CHECK(allocation.value->format() == PixelFormat::bgra8Premultiplied);
        CHECK(allocation.value->byteCount() == 24);
        allocation.value->data()[0] = std::byte{0x7f};
        const PixelBuffer& readOnlyBuffer = *allocation.value;
        CHECK(readOnlyBuffer.data()[0] == std::byte{0x7f});
        CHECK(budget.usedBytes() == 24);
    }

    {
        MemoryBudget budget(31);
        auto first = PixelBuffer::allocate(2, 2, budget);
        auto second = PixelBuffer::allocate(2, 2, budget);

        CHECK(first.value != nullptr);
        CHECK(second.value == nullptr);
        CHECK(second.error == std::optional<PixelBufferError>{PixelBufferError::budgetExceeded});
        CHECK(budget.usedBytes() == 16);

        first.value.reset();
        CHECK(budget.usedBytes() == 0);
    }

    {
        MemoryBudget budget(64);
        auto zeroWidth = PixelBuffer::allocate(0, 2, budget);
        auto negativeHeight = PixelBuffer::allocate(2, -1, budget);
        auto overflow = PixelBuffer::allocate(
            std::numeric_limits<std::int64_t>::max(),
            2,
            budget);

        CHECK(zeroWidth.value == nullptr);
        CHECK(zeroWidth.error == std::optional<PixelBufferError>{PixelBufferError::invalidSize});
        CHECK(negativeHeight.value == nullptr);
        CHECK(negativeHeight.error == std::optional<PixelBufferError>{PixelBufferError::invalidSize});
        CHECK(overflow.value == nullptr);
        CHECK(overflow.error == std::optional<PixelBufferError>{PixelBufferError::arithmeticOverflow});
        CHECK(budget.usedBytes() == 0);
    }

    {
        const auto vectorMaximum = std::vector<std::byte>{}.max_size();
        const auto firstUnrepresentableByteCount =
            static_cast<std::uint64_t>(vectorMaximum) + 1;
        const auto width = static_cast<std::int64_t>(
            (firstUnrepresentableByteCount + 3) / 4);
        MemoryBudget budget(std::numeric_limits<std::uint64_t>::max());

        auto allocation = PixelBuffer::allocate(width, 1, budget);

        CHECK(allocation.value == nullptr);
        CHECK(allocation.error
            == std::optional<PixelBufferError>{PixelBufferError::arithmeticOverflow});
        CHECK(budget.usedBytes() == 0);
    }

    {
        MemoryBudget budget(64);
        {
            auto first = PixelBuffer::allocate(2, 2, budget);
            auto second = PixelBuffer::allocate(3, 2, budget);
            CHECK(budget.usedBytes() == 40);

            PixelBuffer destination(std::move(*first.value));
            PixelBuffer source(std::move(*second.value));
            CHECK(budget.usedBytes() == 40);

            destination = std::move(source);
            CHECK(budget.usedBytes() == 24);
        }
        CHECK(budget.usedBytes() == 0);
    }

    {
        std::unique_ptr<PixelBuffer> survivingBuffer;
        {
            MemoryBudget budget(16);
            auto allocation = PixelBuffer::allocate(2, 2, budget);
            survivingBuffer = std::move(allocation.value);
            CHECK(budget.usedBytes() == 16);
        }
        survivingBuffer.reset();
    }

    {
        constexpr std::uint64_t allocationSize = 16;
        constexpr int threadCount = 16;
        MemoryBudget budget(allocationSize * 4);
        std::atomic<bool> start{false};
        std::atomic<bool> accountingViolation{false};
        std::atomic<int> attempted{0};
        std::atomic<int> succeeded{0};
        std::atomic<int> rejected{0};
        std::vector<std::thread> threads;
        threads.reserve(threadCount);

        for (int index = 0; index < threadCount; ++index) {
            threads.emplace_back([&] {
                while (!start.load(std::memory_order_acquire)) {
                    std::this_thread::yield();
                }

                auto allocation = PixelBuffer::allocate(2, 2, budget);
                if (budget.usedBytes() > budget.limitBytes()) {
                    accountingViolation.store(true, std::memory_order_relaxed);
                }
                if (allocation.value) {
                    if (allocation.error.has_value()) {
                        accountingViolation.store(true, std::memory_order_relaxed);
                    }
                    succeeded.fetch_add(1, std::memory_order_relaxed);
                } else {
                    if (allocation.error
                        != std::optional<PixelBufferError>{PixelBufferError::budgetExceeded}) {
                        accountingViolation.store(true, std::memory_order_relaxed);
                    }
                    rejected.fetch_add(1, std::memory_order_relaxed);
                }

                attempted.fetch_add(1, std::memory_order_release);
                while (attempted.load(std::memory_order_acquire) < threadCount) {
                    std::this_thread::yield();
                }
            });
        }

        start.store(true, std::memory_order_release);
        for (auto& thread : threads) {
            thread.join();
        }

        CHECK(!accountingViolation.load(std::memory_order_relaxed));
        CHECK(succeeded.load(std::memory_order_relaxed) == 4);
        CHECK(rejected.load(std::memory_order_relaxed) == threadCount - 4);
        CHECK(budget.usedBytes() == 0);
    }

    return 0;
}
