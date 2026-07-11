#import "ScrollCaptureBridge.h"

#include "snipory/core/scroll/ScrollStitchSession.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <memory>
#include <new>

namespace {

using snipory::core::scroll::AppendKind;
using snipory::core::scroll::AppendResult;
using snipory::core::scroll::ScrollFrame;
using snipory::core::scroll::ScrollStitchConfig;
using snipory::core::scroll::ScrollStitchSession;

NSString *const ScrollCaptureBridgeErrorDomain = @"com.xxsnap.scroll-capture-bridge";

enum class BridgeError : NSInteger {
    InvalidConfiguration = 1,
    InvalidImage,
    InvalidPreviewHeight,
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
    std::size_t maximumAcceptedBytes, CGFloat sourceScale, int frameHeight)
{
    ScrollStitchConfig config;
    config.maximumAcceptedBytes = maximumAcceptedBytes;
    constexpr int defaultFixedBandPointBudget = 96;
    const auto scaledBudget = defaultFixedBandPointBudget * sourceScale;
    if (!std::isfinite(scaledBudget)
        || scaledBudget > std::numeric_limits<int>::max()) {
        return nullptr;
    }
    const auto pixelBudget = std::min<long>(
        std::lround(scaledBudget), frameHeight / 4);
    if (pixelBudget < 0) {
        return nullptr;
    }
    config.fixedTopCandidateHeight = static_cast<int>(pixelBudget);
    config.fixedBottomCandidateHeight = static_cast<int>(pixelBudget);
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

ScrollCaptureAppendKind bridgeKind(AppendKind kind)
{
    switch (kind) {
    case AppendKind::AcceptedInitial: return ScrollCaptureAppendKindAcceptedInitial;
    case AppendKind::AcceptedAppend: return ScrollCaptureAppendKindAcceptedAppend;
    case AppendKind::DuplicateDiscarded: return ScrollCaptureAppendKindDuplicateDiscarded;
    case AppendKind::ReviewDiscarded: return ScrollCaptureAppendKindReviewDiscarded;
    case AppendKind::PausedLowConfidence: return ScrollCaptureAppendKindPausedLowConfidence;
    case AppendKind::ResourceLimit: return ScrollCaptureAppendKindResourceLimit;
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
- (instancetype)initWithKind:(ScrollCaptureAppendKind)kind;
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
        _appendedHeight = static_cast<NSInteger>(result.appendedHeight);
        _outputHeight = static_cast<NSInteger>(result.outputHeight);
        _confidence = result.confidence;
    }
    return self;
}

- (instancetype)initWithKind:(ScrollCaptureAppendKind)kind
{
    self = [super init];
    if (self != nil) {
        _kind = kind;
        _appendedHeight = 0;
        _outputHeight = 0;
        _confidence = 1;
    }
    return self;
}

#if DEBUG
+ (instancetype)testValueWithKind:(ScrollCaptureAppendKind)kind
{
    return [[self alloc] initWithKind:kind];
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
            implementation->session = makeSession(
                implementation->maximumAcceptedBytes, sourceScale, frame.height);
            if (implementation->session == nullptr) {
                setError(error, BridgeError::InvalidImage, @"The image scale is invalid.");
                return nil;
            }
        }
        const AppendResult result = implementation->session->append(frame);
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
        return imageFromFrame(
            implementation->session->finalize(), implementation->sourceScale, error);
    } catch (...) {
        setError(error, BridgeError::InternalFailure, @"The scroll stitch engine failed to create the final image.");
        return nil;
    }
}

@end
