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

@interface ScrollCaptureAppendUpdate : NSObject
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@property(nonatomic, readonly) ScrollCaptureAppendKind kind;
@property(nonatomic, readonly) NSInteger appendedHeight;
@property(nonatomic, readonly) NSInteger outputHeight;
@property(nonatomic, readonly) double confidence;
#if DEBUG
+ (instancetype)testValueWithKind:(ScrollCaptureAppendKind)kind
    NS_SWIFT_NAME(testValue(kind:));
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
- (nullable NSImage *)previewImageWithMaximumHeight:(NSInteger)maximumHeight
                                              error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(preview(maximumHeight:));
- (nullable NSImage *)finalImageAndReturnError:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(finalImage());
@end

NS_ASSUME_NONNULL_END
