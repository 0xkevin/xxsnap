#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SnapshotExportBridge : NSObject
+ (NSImage *)exportImage:(NSImage *)image;
@end

NS_ASSUME_NONNULL_END
