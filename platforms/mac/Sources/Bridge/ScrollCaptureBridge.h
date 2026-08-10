#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ScrollCaptureAppendKind) {
    ScrollCaptureAppendKindAcceptedInitial,
    ScrollCaptureAppendKindAcceptedAppend,
    ScrollCaptureAppendKindDuplicateDiscarded,
    ScrollCaptureAppendKindReviewDiscarded,
    ScrollCaptureAppendKindAwaitingEvidence,
    ScrollCaptureAppendKindLowConfidenceDiscarded,
    ScrollCaptureAppendKindResourceLimit,
};

typedef NS_ENUM(NSInteger, ScrollCaptureDirection) {
    ScrollCaptureDirectionUnknown,
    ScrollCaptureDirectionDown,
    ScrollCaptureDirectionUp,
};

typedef void (^ScrollCapturePNGProgressHandler)(double progress);

@interface ScrollCaptureAppendUpdate : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property(nonatomic, readonly) ScrollCaptureAppendKind kind;
@property(nonatomic, readonly) ScrollCaptureDirection direction;
@property(nonatomic, readonly) NSInteger appendedHeight;
@property(nonatomic, readonly) NSInteger outputHeight;
@property(nonatomic, readonly) double confidence;
#if DEBUG
+ (instancetype)testValueWithKind:(ScrollCaptureAppendKind)kind
    NS_SWIFT_NAME(testValue(kind:));
+ (instancetype)testValueWithKind:(ScrollCaptureAppendKind)kind
                         direction:(ScrollCaptureDirection)direction
    NS_SWIFT_NAME(testValue(kind:direction:));
+ (instancetype)testValueWithKind:(ScrollCaptureAppendKind)kind
                         direction:(ScrollCaptureDirection)direction
                      outputHeight:(NSInteger)outputHeight
    NS_SWIFT_NAME(testValue(kind:direction:outputHeight:));
#endif
@end

@interface ScrollCaptureBridge : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (nullable instancetype)initWithMaximumAcceptedBytes:(NSUInteger)maximumAcceptedBytes
    NS_SWIFT_NAME(init(maximumAcceptedBytes:));
- (nullable ScrollCaptureAppendUpdate *)appendImage:(NSImage *)image
                                              error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(append(_:));
- (nullable ScrollCaptureAppendUpdate *)appendImage:(NSImage *)image
                                  preferredDirection:(ScrollCaptureDirection)preferredDirection
                                               error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(append(_:preferredDirection:));
- (nullable ScrollCaptureAppendUpdate *)appendImage:(NSImage *)image
                                  preferredDirection:(ScrollCaptureDirection)preferredDirection
                                     expectedAdvance:(CGFloat)expectedAdvance
                                               error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(append(_:preferredDirection:expectedAdvance:));
- (nullable NSNumber *)rebaseImage:(NSImage *)image
                              error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(rebase(_:));
- (nullable NSImage *)previewImageWithMaximumHeight:(NSInteger)maximumHeight
                                              error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(preview(maximumHeight:));
- (nullable NSImage *)previewImageWithMaximumWidth:(NSInteger)maximumWidth
                                             error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(preview(maximumWidth:));
- (nullable NSImage *)finalImageAndReturnError:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(finalImage());
- (BOOL)writePNGToURL:(NSURL *)url
                error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(writePNG(to:));
- (BOOL)writePNGToURL:(NSURL *)url
             progress:(nullable ScrollCapturePNGProgressHandler)progress
                error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(writePNG(to:progress:));
- (void)cancelPNGWrite NS_SWIFT_NAME(cancelPNGWrite());
@end

NS_ASSUME_NONNULL_END
