#include "scroll/ScrollCaptureSession.h"

#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <iostream>

namespace {

using snipory::core::scroll::AppendKind;
using snipory::core::scroll::ScrollDirection;
using snipory::core::scroll::ScrollFrame;
using xxsnap::win::ScrollCapturePhase;
using xxsnap::win::ScrollCapturePauseReason;
using xxsnap::win::ScrollCaptureSession;
using xxsnap::win::ScrollCaptureUpdate;

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

ScrollFrame viewport(int documentY)
{
    ScrollFrame frame(120, 140);
    for (int y = 0; y < frame.height; ++y) {
        for (int x = 0; x < frame.width; ++x) {
            const auto value = documentPixel(x, documentY + y);
            const auto offset = static_cast<std::size_t>(y)
                    * static_cast<std::size_t>(frame.bytesPerRow)
                + static_cast<std::size_t>(x) * 4U;
            frame.pixels[offset] = value;
            frame.pixels[offset + 1U] = value;
            frame.pixels[offset + 2U] = value;
            frame.pixels[offset + 3U] = 255U;
        }
    }
    return frame;
}

std::uint8_t pixelAt(
    const snipory::core::portable::PixelBuffer& buffer, int x, int y)
{
    const auto offset = static_cast<std::size_t>(y)
            * static_cast<std::size_t>(buffer.stride())
        + static_cast<std::size_t>(x) * 4U;
    return static_cast<std::uint8_t>(buffer.data()[offset]);
}

void testMacSessionStateAndWheelDirection()
{
    CHECK(ScrollCaptureSession::directionForWheelDelta(120)
        == ScrollDirection::Down);
    CHECK(ScrollCaptureSession::directionForWheelDelta(-120)
        == ScrollDirection::Up);
    CHECK(ScrollCaptureSession::directionForWheelDelta(0)
        == ScrollDirection::Undetermined);
    CHECK(!ScrollCaptureSession::requiresSaveOnlyForHeight(29'000));
    CHECK(ScrollCaptureSession::requiresSaveOnlyForHeight(29'001));

    ScrollCaptureSession session(16U * 1024U * 1024U);
    ScrollCaptureUpdate update;
    CHECK(session.start(viewport(0), update));
    CHECK(session.phase() == ScrollCapturePhase::capturing);
    CHECK(update.append.kind == AppendKind::AcceptedInitial);
    CHECK(update.preview.has_value());
    CHECK(update.preview->height == 140);

    CHECK(session.append(viewport(60), 120, update));
    CHECK(update.append.kind == AppendKind::AcceptedAppend);
    CHECK(update.append.direction == ScrollDirection::Down);
    CHECK(update.preview.has_value());
    CHECK(update.append.outputHeight == 200);
    CHECK(!update.warning.has_value());

    CHECK(session.append(viewport(60), 120, update));
    CHECK(update.append.kind == AppendKind::DuplicateDiscarded);
    CHECK(!update.preview.has_value());
    const auto final = session.finish(16U * 1024U * 1024U);
    CHECK(final.has_value());
    CHECK(final->width() == 120);
    CHECK(final->height() == 200);
    CHECK(pixelAt(*final, 0, 0) == documentPixel(0, 0));
    CHECK(pixelAt(*final, 119, 199) == documentPixel(119, 199));
    CHECK(session.phase() == ScrollCapturePhase::finished);
}

void testCancelAndResourcePause()
{
    ScrollCaptureUpdate update;
    ScrollCaptureSession cancelled(16U * 1024U * 1024U);
    CHECK(cancelled.start(viewport(0), update));
    cancelled.cancel();
    CHECK(cancelled.phase() == ScrollCapturePhase::cancelled);
    CHECK(!cancelled.finish(16U * 1024U * 1024U).has_value());

    ScrollCaptureSession limited(1U);
    CHECK(!limited.start(viewport(0), update));
    CHECK(limited.phase() == ScrollCapturePhase::idle);

    ScrollCaptureSession paused(16U * 1024U * 1024U);
    CHECK(paused.start(viewport(0), update));
    paused.pause(ScrollCapturePauseReason::captureFailure);
    CHECK(paused.phase() == ScrollCapturePhase::paused);
    CHECK(paused.pauseReason() == ScrollCapturePauseReason::captureFailure);
    CHECK(!paused.append(viewport(60), 120, update));
    CHECK(paused.finish(16U * 1024U * 1024U).has_value());
    CHECK(paused.phase() == ScrollCapturePhase::finished);
    CHECK(!paused.pauseReason().has_value());
}

} // namespace

int main()
{
    testMacSessionStateAndWheelDirection();
    testCancelAndResourcePause();
    return failureCount == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
