#import "ScrollCaptureBridge.h"

#include "snipory/core/scroll/ScrollStitchSession.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <string>
#include <vector>

#include <zlib.h>

#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

namespace {

using snipory::core::scroll::AppendKind;
using snipory::core::scroll::AppendResult;
using snipory::core::scroll::ScrollDirection;
using snipory::core::scroll::ScrollFrame;
using snipory::core::scroll::ScrollStitchConfig;
using snipory::core::scroll::ScrollStitchSession;

NSString *const ScrollCaptureBridgeErrorDomain = @"com.xxsnap.scroll-capture-bridge";

enum class BridgeError : NSInteger {
    InvalidConfiguration = 1,
    InvalidImage,
    InvalidPreviewHeight,
    InvalidPreviewWidth,
    NoOutput,
    ConversionFailed,
    InternalFailure,
};

void setError(NSError **error, BridgeError code, NSString *message)
{
    if (error != nullptr) {
        *error = [NSError errorWithDomain:ScrollCaptureBridgeErrorDomain
                                     code:static_cast<NSInteger>(code)
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
}

struct BridgeImplementation final {
    explicit BridgeImplementation(std::size_t maximumAcceptedBytes)
        : maximumAcceptedBytes(maximumAcceptedBytes)
    {
    }

    std::size_t maximumAcceptedBytes;
    std::unique_ptr<ScrollStitchSession> session;
    CGFloat sourceScale = 1.0;
    bool acceptedImage = false;
    std::atomic_bool pngCancellationRequested = false;
    std::atomic_bool pngExportActive = false;
};

void setCancelledError(NSError **error)
{
    if (error != nullptr) {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSUserCancelledError
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: @"PNG export was cancelled."
                                 }];
    }
}

std::array<std::uint8_t, 4> bigEndian(std::uint32_t value)
{
    return {
        static_cast<std::uint8_t>((value >> 24U) & 0xffU),
        static_cast<std::uint8_t>((value >> 16U) & 0xffU),
        static_cast<std::uint8_t>((value >> 8U) & 0xffU),
        static_cast<std::uint8_t>(value & 0xffU),
    };
}

bool writeBytes(std::FILE* file, const void* bytes, std::size_t size)
{
    return file != nullptr && (size == 0U || std::fwrite(bytes, 1U, size, file) == size);
}

bool writePNGChunk(
    std::FILE* file,
    const char type[4],
    const std::uint8_t* bytes,
    std::size_t size)
{
    if (size > std::numeric_limits<std::uint32_t>::max()) {
        return false;
    }
    const auto length = bigEndian(static_cast<std::uint32_t>(size));
    uLong checksum = crc32(0L, Z_NULL, 0);
    checksum = crc32(
        checksum,
        reinterpret_cast<const Bytef*>(type),
        4U);
    if (size > 0U) {
        checksum = crc32(checksum, bytes, static_cast<uInt>(size));
    }
    const auto crc = bigEndian(static_cast<std::uint32_t>(checksum));
    return writeBytes(file, length.data(), length.size())
        && writeBytes(file, type, 4U)
        && writeBytes(file, bytes, size)
        && writeBytes(file, crc.data(), crc.size());
}

std::uint8_t unpremultiply(std::uint8_t channel, std::uint8_t alpha)
{
    if (alpha == 0U) {
        return 0U;
    }
    if (alpha == 255U) {
        return channel;
    }
    const auto value = (static_cast<unsigned>(channel) * 255U
        + static_cast<unsigned>(alpha) / 2U)
        / static_cast<unsigned>(alpha);
    return static_cast<std::uint8_t>(std::min(value, 255U));
}

std::uint8_t paethPredictor(std::uint8_t left, std::uint8_t above, std::uint8_t upperLeft)
{
    const int prediction = static_cast<int>(left)
        + static_cast<int>(above) - static_cast<int>(upperLeft);
    const int leftDistance = std::abs(prediction - static_cast<int>(left));
    const int aboveDistance = std::abs(prediction - static_cast<int>(above));
    const int upperLeftDistance = std::abs(prediction - static_cast<int>(upperLeft));
    if (leftDistance <= aboveDistance && leftDistance <= upperLeftDistance) {
        return left;
    }
    return aboveDistance <= upperLeftDistance ? above : upperLeft;
}

std::uint64_t filterCost(const std::vector<std::uint8_t>& row)
{
    std::uint64_t cost = 0;
    for (std::size_t index = 1U; index < row.size(); ++index) {
        cost += static_cast<unsigned>(std::abs(
            static_cast<int>(static_cast<std::int8_t>(row[index]))));
    }
    return cost;
}

const std::vector<std::uint8_t>& selectFilteredRow(
    const std::vector<std::uint8_t>& rgba,
    const std::vector<std::uint8_t>& previous,
    std::array<std::vector<std::uint8_t>, 5>& candidates)
{
    for (std::size_t filter = 0; filter < candidates.size(); ++filter) {
        candidates[filter].resize(rgba.size() + 1U);
        candidates[filter][0] = static_cast<std::uint8_t>(filter);
    }
    for (std::size_t index = 0; index < rgba.size(); ++index) {
        const std::uint8_t value = rgba[index];
        const std::uint8_t left = index >= 4U ? rgba[index - 4U] : 0U;
        const std::uint8_t above = previous.empty() ? 0U : previous[index];
        const std::uint8_t upperLeft = index >= 4U && !previous.empty()
            ? previous[index - 4U]
            : 0U;
        candidates[0][index + 1U] = value;
        candidates[1][index + 1U] = static_cast<std::uint8_t>(value - left);
        candidates[2][index + 1U] = static_cast<std::uint8_t>(value - above);
        candidates[3][index + 1U] = static_cast<std::uint8_t>(
            value - static_cast<std::uint8_t>(
                (static_cast<unsigned>(left) + static_cast<unsigned>(above)) / 2U));
        candidates[4][index + 1U] = static_cast<std::uint8_t>(
            value - paethPredictor(left, above, upperLeft));
    }
    std::size_t best = 0U;
    auto bestCost = filterCost(candidates[0]);
    for (std::size_t filter = 1U; filter < candidates.size(); ++filter) {
        const auto cost = filterCost(candidates[filter]);
        if (cost < bestCost) {
            best = filter;
            bestCost = cost;
        }
    }
    return candidates[best];
}

bool finishDeflate(
    z_stream& stream,
    std::FILE* file,
    std::atomic_bool& cancelled,
    const std::uint8_t* input,
    std::size_t inputSize,
    int flush)
{
    constexpr std::size_t outputCapacity = 256U * 1024U;
    std::array<std::uint8_t, outputCapacity> output{};
    stream.next_in = const_cast<Bytef*>(input);
    stream.avail_in = static_cast<uInt>(inputSize);
    int result = Z_OK;
    do {
        if (cancelled.load(std::memory_order_relaxed)) {
            return false;
        }
        stream.next_out = output.data();
        stream.avail_out = static_cast<uInt>(output.size());
        result = deflate(&stream, flush);
        if (result != Z_OK && result != Z_STREAM_END) {
            return false;
        }
        const auto produced = output.size() - stream.avail_out;
        if (produced > 0U
            && !writePNGChunk(file, "IDAT", output.data(), produced)) {
            return false;
        }
    } while (stream.avail_in > 0U
        || (flush == Z_FINISH && result != Z_STREAM_END));
    return flush != Z_FINISH || result == Z_STREAM_END;
}

struct TemporaryMappedPixels final {
    void *address = MAP_FAILED;
    std::size_t length = 0;
    int descriptor = -1;

    TemporaryMappedPixels(void *address, std::size_t length, int descriptor)
        : address(address), length(length), descriptor(descriptor)
    {
    }

    ~TemporaryMappedPixels()
    {
        if (address != MAP_FAILED) {
            munmap(address, length);
        }
        if (descriptor >= 0) {
            close(descriptor);
        }
    }
};

std::unique_ptr<TemporaryMappedPixels> makeTemporaryMappedPixels(
    std::size_t byteCount)
{
    NSString *pathTemplate = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"xxsnap-scroll-png-XXXXXX"];
    const char *fileSystemPath = pathTemplate.fileSystemRepresentation;
    std::vector<char> mutablePath(
        fileSystemPath, fileSystemPath + std::strlen(fileSystemPath) + 1U);
    const int descriptor = mkstemp(mutablePath.data());
    if (descriptor < 0) {
        return nullptr;
    }
    unlink(mutablePath.data());
    if (byteCount > static_cast<std::size_t>(std::numeric_limits<off_t>::max())
        || ftruncate(descriptor, static_cast<off_t>(byteCount)) != 0) {
        close(descriptor);
        return nullptr;
    }
    void *address = mmap(
        nullptr, byteCount, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    if (address == MAP_FAILED) {
        close(descriptor);
        return nullptr;
    }
    return std::make_unique<TemporaryMappedPixels>(address, byteCount, descriptor);
}

bool encodeStreamingPNG(
    const ScrollStitchSession& session,
    std::FILE* file,
    std::atomic_bool& cancelled,
    ScrollCapturePNGProgressHandler progress,
    NSError **error)
{
    const int width = session.outputWidth();
    const int height = session.previewOutputHeight();
    if (width <= 0 || height <= 0) {
        setError(error, BridgeError::NoOutput, @"No stitched image is available.");
        return false;
    }
    const auto rowBytes = static_cast<std::size_t>(width) * 4U;
    if (rowBytes / 4U != static_cast<std::size_t>(width)
        || static_cast<std::size_t>(height) > std::numeric_limits<std::size_t>::max() / rowBytes) {
        setError(error, BridgeError::ConversionFailed, @"The stitched image is too large.");
        return false;
    }
    const auto byteCount = rowBytes * static_cast<std::size_t>(height);
    auto pixels = makeTemporaryMappedPixels(byteCount);
    if (pixels == nullptr) {
        setError(error, BridgeError::ConversionFailed, @"Unable to create temporary image storage.");
        return false;
    }
    int progressBucket = -1;
    if (progress != nil) {
        progress(0.0);
        progressBucket = 0;
    }
    const bool composed = session.visitFinalRows(
        true,
        [&](const std::uint8_t* bgra, std::size_t bytes, int row, int totalRows) {
            if (cancelled.load(std::memory_order_relaxed)
                || bytes != rowBytes || totalRows != height) {
                return false;
            }
            const auto destinationRow = static_cast<std::size_t>(height - 1 - row);
            std::memcpy(
                static_cast<std::uint8_t *>(pixels->address) + destinationRow * rowBytes,
                bgra,
                rowBytes);
            if (progress != nil) {
                const int nextBucket = std::min(
                    30,
                    static_cast<int>(std::floor(
                        static_cast<double>(row + 1) / static_cast<double>(height) * 30.0)));
                if (nextBucket > progressBucket) {
                    progressBucket = nextBucket;
                    progress(static_cast<double>(progressBucket) / 200.0);
                }
            }
            return true;
        });
    if (!composed || cancelled.load(std::memory_order_relaxed)) {
        if (cancelled.load(std::memory_order_relaxed)) {
            setCancelledError(error);
        } else {
            setError(error, BridgeError::ConversionFailed, @"Unable to compose the stitched image.");
        }
        return false;
    }
    (void)msync(pixels->address, byteCount, MS_ASYNC);
    (void)madvise(pixels->address, byteCount, MADV_SEQUENTIAL);

    static constexpr std::array<std::uint8_t, 8> signature{
        0x89U, 0x50U, 0x4eU, 0x47U, 0x0dU, 0x0aU, 0x1aU, 0x0aU,
    };
    std::array<std::uint8_t, 13> header{};
    const auto widthBytes = bigEndian(static_cast<std::uint32_t>(width));
    const auto heightBytes = bigEndian(static_cast<std::uint32_t>(height));
    std::copy(widthBytes.cbegin(), widthBytes.cend(), header.begin());
    std::copy(heightBytes.cbegin(), heightBytes.cend(), header.begin() + 4);
    header[8] = 8U;
    header[9] = 6U;
    if (!writeBytes(file, signature.data(), signature.size())
        || !writePNGChunk(file, "IHDR", header.data(), header.size())) {
        setError(error, BridgeError::ConversionFailed, @"Unable to write the PNG header.");
        return false;
    }

    z_stream stream{};
    if (deflateInit(&stream, Z_DEFAULT_COMPRESSION) != Z_OK) {
        setError(error, BridgeError::ConversionFailed, @"Unable to initialize PNG compression.");
        return false;
    }
    bool succeeded = false;
    std::vector<std::uint8_t> rgba(static_cast<std::size_t>(width) * 4U);
    std::vector<std::uint8_t> previous;
    std::array<std::vector<std::uint8_t>, 5> candidates;
    bool rowsEncoded = true;
    for (int row = 0; row < height; ++row) {
        if (cancelled.load(std::memory_order_relaxed)) {
            rowsEncoded = false;
            break;
        }
        const auto *bgra = static_cast<const std::uint8_t *>(pixels->address)
            + static_cast<std::size_t>(row) * rowBytes;
        for (int x = 0; x < width; ++x) {
            const auto offset = static_cast<std::size_t>(x) * 4U;
            const auto alpha = bgra[offset + 3U];
            rgba[offset] = unpremultiply(bgra[offset + 2U], alpha);
            rgba[offset + 1U] = unpremultiply(bgra[offset + 1U], alpha);
            rgba[offset + 2U] = unpremultiply(bgra[offset], alpha);
            rgba[offset + 3U] = alpha;
        }
        const auto& filtered = selectFilteredRow(rgba, previous, candidates);
        if (!finishDeflate(
                stream,
                file,
                cancelled,
                filtered.data(),
                filtered.size(),
                Z_NO_FLUSH)) {
            rowsEncoded = false;
            break;
        }
        previous = rgba;
        if (progress != nil) {
            const double rowProgress = static_cast<double>(row + 1)
                / static_cast<double>(height);
            const int nextBucket = std::min(
                198,
                30 + static_cast<int>(std::floor(rowProgress * 168.0)));
            if (nextBucket > progressBucket) {
                progressBucket = nextBucket;
                progress(static_cast<double>(progressBucket) / 200.0);
            }
        }
    }
    if (rowsEncoded && !cancelled.load(std::memory_order_relaxed)) {
        succeeded = finishDeflate(stream, file, cancelled, nullptr, 0U, Z_FINISH)
            && writePNGChunk(file, "IEND", nullptr, 0U);
    }
    deflateEnd(&stream);
    if (!succeeded) {
        if (cancelled.load(std::memory_order_relaxed)) {
            setCancelledError(error);
        } else {
            setError(error, BridgeError::ConversionFailed, @"Unable to encode the stitched PNG.");
        }
        return false;
    }
    return true;
}

std::unique_ptr<ScrollStitchSession> makeSession(
    std::size_t maximumAcceptedBytes)
{
    ScrollStitchConfig config;
    config.maximumAcceptedBytes = maximumAcceptedBytes;
    config.seamWhiteCoverage = 0.0;
    return std::make_unique<ScrollStitchSession>(config);
}

CGImageRef bestCGImage(NSImage *image)
{
    CGImageRef selected = nullptr;
    NSInteger selectedArea = 0;
    for (NSImageRep *representation in image.representations) {
        if (![representation isKindOfClass:NSBitmapImageRep.class]) {
            continue;
        }
        NSBitmapImageRep *bitmap = static_cast<NSBitmapImageRep *>(representation);
        CGImageRef candidate = bitmap.CGImage;
        if (candidate == nullptr) {
            continue;
        }
        const NSInteger width = bitmap.pixelsWide;
        const NSInteger height = bitmap.pixelsHigh;
        if (width > 0 && height > 0 && width <= NSIntegerMax / height
            && width * height > selectedArea) {
            selected = candidate;
            selectedArea = width * height;
        }
    }
    if (selected != nullptr) {
        return selected;
    }
    NSRect proposedRect = NSMakeRect(0, 0, image.size.width, image.size.height);
    return [image CGImageForProposedRect:&proposedRect context:nil hints:nil];
}

bool frameFromImage(NSImage *image, ScrollFrame& frame, CGFloat& scale, NSError **error)
{
    if (image == nil || image.size.width <= 0 || image.size.height <= 0
        || !std::isfinite(image.size.width) || !std::isfinite(image.size.height)) {
        setError(error, BridgeError::InvalidImage, @"The image must have a finite, non-zero size.");
        return false;
    }
    CGImageRef source = bestCGImage(image);
    if (source == nullptr) {
        setError(error, BridgeError::InvalidImage, @"The image has no readable pixel representation.");
        return false;
    }
    const std::size_t width = CGImageGetWidth(source);
    const std::size_t height = CGImageGetHeight(source);
    if (width == 0 || height == 0
        || width > static_cast<std::size_t>(std::numeric_limits<int>::max())
        || height > static_cast<std::size_t>(std::numeric_limits<int>::max())) {
        setError(error, BridgeError::InvalidImage, @"The image pixel dimensions are unsupported.");
        return false;
    }

    frame = ScrollFrame(static_cast<int>(width), static_cast<int>(height));
    if (!frame.isValid()) {
        setError(error, BridgeError::ConversionFailed, @"Unable to allocate the canonical image buffer.");
        return false;
    }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == nullptr) {
        setError(error, BridgeError::ConversionFailed, @"Unable to create an RGB color space.");
        return false;
    }
    const CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little
        | static_cast<CGBitmapInfo>(kCGImageAlphaPremultipliedFirst);
    CGContextRef context = CGBitmapContextCreate(
        frame.pixels.data(), width, height, 8,
        static_cast<std::size_t>(frame.bytesPerRow), colorSpace, bitmapInfo);
    CGColorSpaceRelease(colorSpace);
    if (context == nullptr) {
        setError(error, BridgeError::ConversionFailed, @"Unable to convert the image to BGRA pixels.");
        return false;
    }
    CGContextSetBlendMode(context, kCGBlendModeCopy);
    CGContextTranslateCTM(context, 0, static_cast<CGFloat>(height));
    CGContextScaleCTM(context, 1, -1);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), source);
    CGContextRelease(context);

    const CGFloat horizontalScale = static_cast<CGFloat>(width) / image.size.width;
    const CGFloat verticalScale = static_cast<CGFloat>(height) / image.size.height;
    const CGFloat unifiedScale = (horizontalScale + verticalScale) / 2;
    const CGFloat horizontalPixelError = std::abs(unifiedScale * image.size.width - width);
    const CGFloat verticalPixelError = std::abs(unifiedScale * image.size.height - height);
    if (!std::isfinite(unifiedScale) || unifiedScale <= 0
        || horizontalPixelError > 1 || verticalPixelError > 1) {
        setError(error, BridgeError::InvalidImage, @"The image scale is invalid.");
        return false;
    }
    scale = unifiedScale;
    return true;
}

NSImage *imageFromFrame(const ScrollFrame& frame, CGFloat scale, NSError **error)
{
    if (!frame.isValid() || !std::isfinite(scale) || scale <= 0) {
        setError(error, BridgeError::NoOutput, @"No stitched image is available.");
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:frame.pixels.size()];
    if (data == nil || data.mutableBytes == nullptr) {
        setError(error, BridgeError::ConversionFailed, @"Unable to allocate the stitched image.");
        return nil;
    }
    auto *destination = static_cast<std::uint8_t *>(data.mutableBytes);
    const auto bytesPerRow = static_cast<std::size_t>(frame.bytesPerRow);
    for (int row = 0; row < frame.height; ++row) {
        std::memcpy(
            destination + static_cast<std::size_t>(frame.height - 1 - row) * bytesPerRow,
            frame.pixels.data() + static_cast<std::size_t>(row) * bytesPerRow,
            bytesPerRow);
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)data);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (provider == nullptr || colorSpace == nullptr) {
        if (provider != nullptr) CGDataProviderRelease(provider);
        if (colorSpace != nullptr) CGColorSpaceRelease(colorSpace);
        setError(error, BridgeError::ConversionFailed, @"Unable to create the stitched image.");
        return nil;
    }
    const CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little
        | static_cast<CGBitmapInfo>(kCGImageAlphaPremultipliedFirst);
    CGImageRef cgImage = CGImageCreate(
        static_cast<std::size_t>(frame.width), static_cast<std::size_t>(frame.height),
        8, 32, static_cast<std::size_t>(frame.bytesPerRow), colorSpace, bitmapInfo,
        provider, nullptr, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    if (cgImage == nullptr) {
        setError(error, BridgeError::ConversionFailed, @"Unable to create the stitched image.");
        return nil;
    }
    NSBitmapImageRep *representation = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    CGImageRelease(cgImage);
    const NSSize pointSize = NSMakeSize(frame.width / scale, frame.height / scale);
    representation.size = pointSize;
    NSImage *image = [[NSImage alloc] initWithSize:pointSize];
    [image addRepresentation:representation];
    return image;
}

struct MappedImageStorage final {
    void *address = MAP_FAILED;
    std::size_t length = 0;
    int descriptor = -1;
};

void releaseMappedImageStorage(void *info, const void *, std::size_t)
{
    auto *storage = static_cast<MappedImageStorage *>(info);
    if (storage == nullptr) {
        return;
    }
    if (storage->address != MAP_FAILED) {
        munmap(storage->address, storage->length);
    }
    if (storage->descriptor >= 0) {
        close(storage->descriptor);
    }
    delete storage;
}

CGImageRef mappedFinalCGImage(const ScrollStitchSession& session, NSError **error)
{
    const int width = session.outputWidth();
    const int height = session.previewOutputHeight();
    if (width <= 0 || height <= 0) {
        setError(error, BridgeError::NoOutput, @"No stitched image is available.");
        return nil;
    }
    const auto rowBytes = static_cast<std::size_t>(width) * 4U;
    if (rowBytes / 4U != static_cast<std::size_t>(width)
        || static_cast<std::size_t>(height) > std::numeric_limits<std::size_t>::max() / rowBytes) {
        setError(error, BridgeError::ConversionFailed, @"The stitched image is too large.");
        return nil;
    }
    const auto byteCount = rowBytes * static_cast<std::size_t>(height);
    if (byteCount > static_cast<std::size_t>(std::numeric_limits<off_t>::max())) {
        setError(error, BridgeError::ConversionFailed, @"The stitched image is too large.");
        return nil;
    }

    NSString *pathTemplate = [NSTemporaryDirectory()
        stringByAppendingPathComponent:@"xxsnap-scroll-final-XXXXXX"];
    const char *fileSystemPath = pathTemplate.fileSystemRepresentation;
    std::vector<char> mutablePath(
        fileSystemPath, fileSystemPath + std::strlen(fileSystemPath) + 1U);
    const int descriptor = mkstemp(mutablePath.data());
    if (descriptor < 0) {
        setError(error, BridgeError::ConversionFailed, @"Unable to create temporary image storage.");
        return nil;
    }
    unlink(mutablePath.data());
    if (ftruncate(descriptor, static_cast<off_t>(byteCount)) != 0) {
        close(descriptor);
        setError(error, BridgeError::ConversionFailed, @"Unable to size temporary image storage.");
        return nil;
    }
    void *address = mmap(nullptr, byteCount, PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
    if (address == MAP_FAILED) {
        close(descriptor);
        setError(error, BridgeError::ConversionFailed, @"Unable to map temporary image storage.");
        return nil;
    }
    (void)madvise(address, byteCount, MADV_SEQUENTIAL);
    auto *storage = new (std::nothrow) MappedImageStorage{address, byteCount, descriptor};
    if (storage == nullptr
        || !session.copyFinalPixels(address, byteCount, rowBytes, true, true)) {
        if (storage != nullptr) {
            releaseMappedImageStorage(storage, nullptr, 0);
        } else {
            munmap(address, byteCount);
            close(descriptor);
        }
        setError(error, BridgeError::ConversionFailed, @"Unable to compose the stitched image.");
        return nil;
    }
    (void)msync(address, byteCount, MS_ASYNC);
    (void)madvise(address, byteCount, MADV_DONTNEED);

    CGDataProviderRef provider = CGDataProviderCreateWithData(
        storage, address, byteCount, releaseMappedImageStorage);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (provider == nullptr || colorSpace == nullptr) {
        if (provider != nullptr) {
            CGDataProviderRelease(provider);
        } else {
            releaseMappedImageStorage(storage, nullptr, 0);
        }
        if (colorSpace != nullptr) CGColorSpaceRelease(colorSpace);
        setError(error, BridgeError::ConversionFailed, @"Unable to create the stitched image.");
        return nil;
    }
    const CGBitmapInfo bitmapInfo = kCGBitmapByteOrder32Little
        | static_cast<CGBitmapInfo>(kCGImageAlphaPremultipliedFirst);
    CGImageRef cgImage = CGImageCreate(
        static_cast<std::size_t>(width), static_cast<std::size_t>(height),
        8, 32, rowBytes, colorSpace, bitmapInfo,
        provider, nullptr, false, kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    if (cgImage == nullptr) {
        setError(error, BridgeError::ConversionFailed, @"Unable to create the stitched image.");
        return nil;
    }
    return cgImage;
}

NSImage *mappedFinalImage(
    const ScrollStitchSession& session,
    CGFloat scale,
    NSError **error)
{
    if (!std::isfinite(scale) || scale <= 0) {
        setError(error, BridgeError::NoOutput, @"No stitched image is available.");
        return nil;
    }
    CGImageRef cgImage = mappedFinalCGImage(session, error);
    if (cgImage == nullptr) {
        return nil;
    }
    NSBitmapImageRep *representation = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    const auto width = static_cast<CGFloat>(CGImageGetWidth(cgImage));
    const auto height = static_cast<CGFloat>(CGImageGetHeight(cgImage));
    CGImageRelease(cgImage);
    const NSSize pointSize = NSMakeSize(width / scale, height / scale);
    representation.size = pointSize;
    NSImage *image = [[NSImage alloc] initWithSize:pointSize];
    [image addRepresentation:representation];
    return image;
}

ScrollCaptureAppendKind bridgeKind(AppendKind kind)
{
    switch (kind) {
    case AppendKind::AcceptedInitial: return ScrollCaptureAppendKindAcceptedInitial;
    case AppendKind::AcceptedAppend: return ScrollCaptureAppendKindAcceptedAppend;
    case AppendKind::DuplicateDiscarded: return ScrollCaptureAppendKindDuplicateDiscarded;
    case AppendKind::ReviewDiscarded: return ScrollCaptureAppendKindReviewDiscarded;
    case AppendKind::AwaitingEvidence: return ScrollCaptureAppendKindAwaitingEvidence;
    case AppendKind::LowConfidenceDiscarded: return ScrollCaptureAppendKindLowConfidenceDiscarded;
    case AppendKind::ResourceLimit: return ScrollCaptureAppendKindResourceLimit;
    }
}

ScrollCaptureDirection bridgeDirection(ScrollDirection direction)
{
    switch (direction) {
    case ScrollDirection::Undetermined: return ScrollCaptureDirectionUnknown;
    case ScrollDirection::Down: return ScrollCaptureDirectionDown;
    case ScrollDirection::Up: return ScrollCaptureDirectionUp;
    }
}

ScrollDirection coreDirection(ScrollCaptureDirection direction)
{
    switch (direction) {
    case ScrollCaptureDirectionUnknown: return ScrollDirection::Undetermined;
    case ScrollCaptureDirectionDown: return ScrollDirection::Down;
    case ScrollCaptureDirectionUp: return ScrollDirection::Up;
    }
}

BridgeImplementation *implementationOrError(void *pointer, NSError **error)
{
    auto *implementation = static_cast<BridgeImplementation *>(pointer);
    if (implementation == nullptr) {
        setError(
            error,
            BridgeError::InvalidConfiguration,
            @"The scroll capture bridge was not initialized with a byte limit.");
    }
    return implementation;
}

} // namespace

@interface ScrollCaptureAppendUpdate ()
- (instancetype)initWithResult:(const AppendResult&)result;
- (instancetype)initWithKind:(ScrollCaptureAppendKind)kind
                    direction:(ScrollCaptureDirection)direction
                 outputHeight:(NSInteger)outputHeight;
@end

@implementation ScrollCaptureAppendUpdate

- (instancetype)init
{
    return nil;
}

- (instancetype)initWithResult:(const AppendResult&)result
{
    self = [super init];
    if (self != nil) {
        _kind = bridgeKind(result.kind);
        _direction = bridgeDirection(result.direction);
        _appendedHeight = static_cast<NSInteger>(result.appendedHeight);
        _outputHeight = static_cast<NSInteger>(result.outputHeight);
        _confidence = result.confidence;
    }
    return self;
}

- (instancetype)initWithKind:(ScrollCaptureAppendKind)kind
                    direction:(ScrollCaptureDirection)direction
                 outputHeight:(NSInteger)outputHeight
{
    self = [super init];
    if (self != nil) {
        _kind = kind;
        _direction = direction;
        _appendedHeight = 0;
        _outputHeight = outputHeight;
        _confidence = 1;
    }
    return self;
}

#if DEBUG
+ (instancetype)testValueWithKind:(ScrollCaptureAppendKind)kind
{
    return [[self alloc] initWithKind:kind
                           direction:ScrollCaptureDirectionUnknown
                        outputHeight:0];
}

+ (instancetype)testValueWithKind:(ScrollCaptureAppendKind)kind
                         direction:(ScrollCaptureDirection)direction
{
    return [[self alloc] initWithKind:kind direction:direction outputHeight:0];
}

+ (instancetype)testValueWithKind:(ScrollCaptureAppendKind)kind
                         direction:(ScrollCaptureDirection)direction
                      outputHeight:(NSInteger)outputHeight
{
    return [[self alloc] initWithKind:kind
                           direction:direction
                        outputHeight:outputHeight];
}
#endif

@end

@implementation ScrollCaptureBridge {
    void *_implementation;
}

- (instancetype)init
{
    return nil;
}

- (nullable instancetype)initWithMaximumAcceptedBytes:(NSUInteger)maximumAcceptedBytes
{
    if (maximumAcceptedBytes == 0
        || maximumAcceptedBytes > std::numeric_limits<std::size_t>::max()) {
        return nil;
    }
    self = [super init];
    if (self != nil) {
        try {
            _implementation = new BridgeImplementation(static_cast<std::size_t>(maximumAcceptedBytes));
        } catch (...) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    delete static_cast<BridgeImplementation *>(_implementation);
}

- (nullable ScrollCaptureAppendUpdate *)appendImage:(NSImage *)image
                                              error:(NSError **)error
{
    return [self appendImage:image
          preferredDirection:ScrollCaptureDirectionUnknown
             expectedAdvance:0
                       error:error];
}

- (nullable ScrollCaptureAppendUpdate *)appendImage:(NSImage *)image
                                  preferredDirection:(ScrollCaptureDirection)preferredDirection
                                               error:(NSError **)error
{
    return [self appendImage:image
          preferredDirection:preferredDirection
             expectedAdvance:0
                       error:error];
}

- (nullable ScrollCaptureAppendUpdate *)appendImage:(NSImage *)image
                                  preferredDirection:(ScrollCaptureDirection)preferredDirection
                                     expectedAdvance:(CGFloat)expectedAdvance
                                               error:(NSError **)error
{
    auto *implementation = implementationOrError(_implementation, error);
    if (implementation == nullptr) {
        return nil;
    }
    ScrollFrame frame;
    CGFloat sourceScale = 1;
    if (!frameFromImage(image, frame, sourceScale, error)) {
        return nil;
    }
    if (!std::isfinite(expectedAdvance) || expectedAdvance < 0) {
        setError(error, BridgeError::InvalidConfiguration, @"The expected scroll advance is invalid.");
        return nil;
    }
    const double scaledExpectedAdvance = static_cast<double>(expectedAdvance * sourceScale);
    if (scaledExpectedAdvance > std::numeric_limits<int>::max()) {
        setError(error, BridgeError::InvalidConfiguration, @"The expected scroll advance is too large.");
        return nil;
    }
    const int expectedAdvancePixels = static_cast<int>(std::lround(scaledExpectedAdvance));
    try {
        if (implementation->session == nullptr) {
            auto candidate = makeSession(
                implementation->maximumAcceptedBytes);
            if (candidate == nullptr) {
                setError(error, BridgeError::InvalidImage, @"The image scale is invalid.");
                return nil;
            }
            AppendResult result = candidate->append(
                std::move(frame), coreDirection(preferredDirection), expectedAdvancePixels);
            if (result.kind == AppendKind::AcceptedInitial) {
                implementation->session = std::move(candidate);
                implementation->sourceScale = sourceScale;
                implementation->acceptedImage = true;
            }
            return [[ScrollCaptureAppendUpdate alloc] initWithResult:result];
        }
        AppendResult result = implementation->session->append(
            std::move(frame), coreDirection(preferredDirection), expectedAdvancePixels);
        return [[ScrollCaptureAppendUpdate alloc] initWithResult:result];
    } catch (...) {
        setError(error, BridgeError::InternalFailure, @"The scroll stitch engine failed to append the image.");
        return nil;
    }
}

- (nullable NSNumber *)rebaseImage:(NSImage *)image error:(NSError **)error
{
    auto *implementation = implementationOrError(_implementation, error);
    if (implementation == nullptr) {
        return nil;
    }
    if (implementation->session == nullptr || !implementation->acceptedImage) {
        setError(error, BridgeError::NoOutput, @"Append an image before rebasing the matcher.");
        return nil;
    }
    ScrollFrame frame;
    CGFloat sourceScale = 1;
    if (!frameFromImage(image, frame, sourceScale, error)) {
        return nil;
    }
    if (std::abs(sourceScale - implementation->sourceScale) > 0.01) {
        setError(error, BridgeError::InvalidImage, @"The rebase image scale changed.");
        return nil;
    }
    try {
        return [NSNumber numberWithBool:implementation->session->rebase(frame)];
    } catch (...) {
        setError(error, BridgeError::InternalFailure, @"The scroll stitch engine failed to rebase the matcher.");
        return nil;
    }
}

- (nullable NSImage *)previewImageWithMaximumHeight:(NSInteger)maximumHeight
                                              error:(NSError **)error
{
    auto *implementation = implementationOrError(_implementation, error);
    if (implementation == nullptr) {
        return nil;
    }
    if (maximumHeight <= 0 || maximumHeight > std::numeric_limits<int>::max()) {
        setError(error, BridgeError::InvalidPreviewHeight, @"Preview height must be a positive 32-bit pixel count.");
        return nil;
    }
    if (!implementation->acceptedImage) {
        setError(error, BridgeError::NoOutput, @"Append an image before requesting a preview.");
        return nil;
    }
    try {
        return imageFromFrame(
            implementation->session->preview(static_cast<int>(maximumHeight)),
            implementation->sourceScale, error);
    } catch (...) {
        setError(error, BridgeError::InternalFailure, @"The scroll stitch engine failed to create a preview.");
        return nil;
    }
}

- (nullable NSImage *)previewImageWithMaximumWidth:(NSInteger)maximumWidth
                                             error:(NSError **)error
{
    auto *implementation = implementationOrError(_implementation, error);
    if (implementation == nullptr) {
        return nil;
    }
    if (maximumWidth <= 0 || maximumWidth > std::numeric_limits<int>::max()) {
        setError(error, BridgeError::InvalidPreviewWidth, @"Preview width must be a positive 32-bit pixel count.");
        return nil;
    }
    if (!implementation->acceptedImage) {
        setError(error, BridgeError::NoOutput, @"Append an image before requesting a preview.");
        return nil;
    }
    try {
        return imageFromFrame(
            implementation->session->previewForWidth(static_cast<int>(maximumWidth)),
            implementation->sourceScale, error);
    } catch (...) {
        setError(error, BridgeError::InternalFailure, @"The scroll stitch engine failed to create a preview.");
        return nil;
    }
}

- (nullable NSImage *)finalImageAndReturnError:(NSError **)error
{
    auto *implementation = implementationOrError(_implementation, error);
    if (implementation == nullptr) {
        return nil;
    }
    if (!implementation->acceptedImage) {
        setError(error, BridgeError::NoOutput, @"Append an image before requesting the final image.");
        return nil;
    }
    try {
        return mappedFinalImage(
            *implementation->session, implementation->sourceScale, error);
    } catch (...) {
        setError(error, BridgeError::InternalFailure, @"The scroll stitch engine failed to create the final image.");
        return nil;
    }
}

- (BOOL)writePNGToURL:(NSURL *)url error:(NSError **)error
{
    return [self writePNGToURL:url progress:nil error:error];
}

- (BOOL)writePNGToURL:(NSURL *)url
             progress:(ScrollCapturePNGProgressHandler)progress
                error:(NSError **)error
{
    auto *implementation = implementationOrError(_implementation, error);
    if (implementation == nullptr) {
        return NO;
    }
    if (!implementation->acceptedImage) {
        setError(error, BridgeError::NoOutput, @"Append an image before exporting PNG.");
        return NO;
    }
    if (url == nil || !url.isFileURL) {
        setError(error, BridgeError::InvalidConfiguration, @"The PNG destination must be a file URL.");
        return NO;
    }
    bool expectedInactive = false;
    if (!implementation->pngExportActive.compare_exchange_strong(
            expectedInactive, true, std::memory_order_acq_rel)) {
        setError(error, BridgeError::InvalidConfiguration, @"A PNG export is already running.");
        return NO;
    }
    implementation->pngCancellationRequested.store(false, std::memory_order_relaxed);
    const auto finishExport = [&]() {
        implementation->pngExportActive.store(false, std::memory_order_release);
    };

    NSURL *directory = url.URLByDeletingLastPathComponent;
    NSString *temporaryName = [NSString stringWithFormat:
        @".%@.%@.part", url.lastPathComponent, NSUUID.UUID.UUIDString];
    NSURL *temporaryURL = [directory URLByAppendingPathComponent:temporaryName];
    std::FILE *file = std::fopen(temporaryURL.fileSystemRepresentation, "wb");
    if (file == nullptr) {
        finishExport();
        setError(error, BridgeError::ConversionFailed, @"Unable to create temporary PNG storage.");
        return NO;
    }
    bool encoded = false;
    try {
        encoded = encodeStreamingPNG(
            *implementation->session,
            file,
            implementation->pngCancellationRequested,
            progress,
            error);
    } catch (...) {
        encoded = false;
        setError(error, BridgeError::InternalFailure, @"The scroll stitch engine failed to export PNG.");
    }
    const bool flushed = encoded && std::fflush(file) == 0;
    const bool synchronized = flushed && fsync(fileno(file)) == 0;
    const bool closed = std::fclose(file) == 0;
    if (!encoded || !flushed || !synchronized || !closed) {
        [[NSFileManager defaultManager] removeItemAtURL:temporaryURL error:nil];
        if (encoded && error != nullptr && *error == nil) {
            setError(error, BridgeError::ConversionFailed, @"Unable to finish writing the PNG.");
        }
        finishExport();
        return NO;
    }

    if (progress != nil) {
        progress(0.995);
    }
    if (implementation->pngCancellationRequested.load(std::memory_order_relaxed)) {
        [[NSFileManager defaultManager] removeItemAtURL:temporaryURL error:nil];
        setCancelledError(error);
        finishExport();
        return NO;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSError *publicationError = nil;
    BOOL published = NO;
    if ([fileManager fileExistsAtPath:url.path]) {
        published = [fileManager replaceItemAtURL:url
                                    withItemAtURL:temporaryURL
                                   backupItemName:nil
                                          options:0
                                 resultingItemURL:nil
                                            error:&publicationError];
    } else {
        published = [fileManager moveItemAtURL:temporaryURL
                                         toURL:url
                                         error:&publicationError];
    }
    if (!published) {
        [fileManager removeItemAtURL:temporaryURL error:nil];
        if (error != nullptr) {
            *error = publicationError ?: [NSError errorWithDomain:ScrollCaptureBridgeErrorDomain
                                                              code:static_cast<NSInteger>(BridgeError::ConversionFailed)
                                                          userInfo:@{
                                                              NSLocalizedDescriptionKey:
                                                                  @"Unable to publish the completed PNG."
                                                          }];
        }
        finishExport();
        return NO;
    }
    if (progress != nil) {
        progress(1.0);
    }
    finishExport();
    return YES;
}

- (void)cancelPNGWrite
{
    auto *implementation = static_cast<BridgeImplementation *>(_implementation);
    if (implementation != nullptr) {
        implementation->pngCancellationRequested.store(true, std::memory_order_relaxed);
    }
}

@end
