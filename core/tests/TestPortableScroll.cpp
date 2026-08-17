#include "snipory/core/scroll/ScrollStitchSession.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>

namespace {

using snipory::core::scroll::AppendKind;
using snipory::core::scroll::ScrollDirection;
using snipory::core::scroll::ScrollFrame;
using snipory::core::scroll::ScrollStitchConfig;
using snipory::core::scroll::ScrollStitchSession;

int failureCount = 0;

void check(bool condition, const char* expression, int line)
{
    if (!condition) {
        std::cerr << "CHECK failed at line " << line << ": "
                  << expression << '\n';
        ++failureCount;
    }
}

#define CHECK(expression) check((expression), #expression, __LINE__)

std::uint8_t documentPixel(int x, int y)
{
    auto value = static_cast<std::uint32_t>(y) * 0x9e3779b9U
        ^ static_cast<std::uint32_t>(x) * 0x85ebca6bU;
    value ^= value >> 16U;
    value *= 0x7feb352dU;
    value ^= value >> 15U;
    return static_cast<std::uint8_t>(value & 0xffU);
}

ScrollFrame documentViewport(int documentY)
{
    ScrollFrame frame(120, 140);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            const auto value = documentPixel(x, documentY + y);
            const auto offset = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(frame.bytesPerRow)
                + static_cast<std::size_t>(x) * 4U;
            frame.pixels[offset] = value;
            frame.pixels[offset + 1U]
                = static_cast<std::uint8_t>(value ^ 0x35U);
            frame.pixels[offset + 2U]
                = static_cast<std::uint8_t>(value ^ 0xa7U);
            frame.pixels[offset + 3U] = 255U;
        }
    }
    return frame;
}

std::uint8_t blueAt(const ScrollFrame& frame, int x, int y)
{
    return frame.pixels[static_cast<std::size_t>(y)
            * static_cast<std::size_t>(frame.bytesPerRow)
        + static_cast<std::size_t>(x) * 4U];
}

void testDirectionLockAndNaturalOrder()
{
    ScrollStitchSession down;
    CHECK(down.append(documentViewport(0)).kind
        == AppendKind::AcceptedInitial);
    const auto downAppend = down.append(
        documentViewport(60), ScrollDirection::Down);
    CHECK(downAppend.kind == AppendKind::AcceptedAppend);
    CHECK(downAppend.direction == ScrollDirection::Down);
    CHECK(down.outputHeight() == 200);
    const auto review = down.append(
        documentViewport(0), ScrollDirection::Up).kind;
    CHECK(review == AppendKind::DuplicateDiscarded
        || review == AppendKind::ReviewDiscarded);
    const auto downImage = down.finalize();
    CHECK(downImage.isValid());
    CHECK(blueAt(downImage, 37, 0) == documentPixel(37, 0));
    CHECK(blueAt(downImage, 37, 199) == documentPixel(37, 199));

    ScrollStitchSession up;
    CHECK(up.append(documentViewport(120)).kind
        == AppendKind::AcceptedInitial);
    const auto upAppend = up.append(
        documentViewport(60), ScrollDirection::Up);
    CHECK(upAppend.kind == AppendKind::AcceptedAppend);
    CHECK(upAppend.direction == ScrollDirection::Up);
    CHECK(up.outputHeight() == 200);
    const auto upImage = up.finalize();
    CHECK(upImage.isValid());
    CHECK(blueAt(upImage, 37, 0) == documentPixel(37, 60));
    CHECK(blueAt(upImage, 37, 199) == documentPixel(37, 259));
}

void testDuplicatePreviewAndResourceGuard()
{
    ScrollStitchSession session;
    const auto seed = documentViewport(0);
    CHECK(session.append(seed).kind == AppendKind::AcceptedInitial);
    CHECK(session.append(seed).kind == AppendKind::DuplicateDiscarded);
    const auto preview = session.preview(70);
    CHECK(preview.isValid());
    CHECK(preview.width == 60);
    CHECK(preview.height == 70);

    ScrollStitchConfig limited;
    limited.maximumAcceptedBytes = 1U;
    ScrollStitchSession guarded(limited);
    CHECK(guarded.append(documentViewport(0)).kind
        == AppendKind::ResourceLimit);
    CHECK(guarded.outputHeight() == 0);
    CHECK(!guarded.finalize().isValid());
}

} // namespace

int main()
{
    testDirectionLockAndNaturalOrder();
    testDuplicatePreviewAndResourceGuard();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
