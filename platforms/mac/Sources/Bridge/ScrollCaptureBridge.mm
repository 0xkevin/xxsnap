#import "ScrollCaptureBridge.h"

#include "snipory/core/scroll/ScrollStitchSession.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <vector>

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
};

std::unique_ptr<ScrollStitchSession> makeSession(
    std::size_t maximumAcceptedBytes)
{
    ScrollStitchConfig config;
    config.maximumAcceptedBytes = maximumAcceptedBytes;
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

NSImage *mappedFinalImage(
    const ScrollStitchSession& session,
    CGFloat scale,
    NSError **error)
{
    const int width = session.outputWidth();
    const int height = session.previewOutputHeight();
    if (width <= 0 || height <= 0 || !std::isfinite(scale) || scale <= 0) {
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
    NSBitmapImageRep *representation = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
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
                    direction:(ScrollCaptureDirection)direction;
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
{
    self = [super init];
    if (self != nil) {
        _kind = kind;
        _direction = direction;
        _appendedHeight = 0;
        _outputHeight = 0;
        _confidence = 1;
    }
    return self;
}

#if DEBUG
+ (instancetype)testValueWithKind:(ScrollCaptureAppendKind)kind
{
    return [[self alloc] initWithKind:kind direction:ScrollCaptureDirectionUnknown];
}

+ (instancetype)testValueWithKind:(ScrollCaptureAppendKind)kind
                         direction:(ScrollCaptureDirection)direction
{
    return [[self alloc] initWithKind:kind direction:direction];
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
                       error:error];
}

- (nullable ScrollCaptureAppendUpdate *)appendImage:(NSImage *)image
                                  preferredDirection:(ScrollCaptureDirection)preferredDirection
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
    try {
        if (implementation->session == nullptr) {
            implementation->session = makeSession(implementation->maximumAcceptedBytes);
            if (implementation->session == nullptr) {
                setError(error, BridgeError::InvalidImage, @"The image scale is invalid.");
                return nil;
            }
        }
        AppendResult result = implementation->session->append(
            frame, coreDirection(preferredDirection));
        if (result.kind == AppendKind::AcceptedInitial) {
            implementation->sourceScale = sourceScale;
            implementation->acceptedImage = true;
        }
        return [[ScrollCaptureAppendUpdate alloc] initWithResult:result];
    } catch (...) {
        setError(error, BridgeError::InternalFailure, @"The scroll stitch engine failed to append the image.");
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

@end
