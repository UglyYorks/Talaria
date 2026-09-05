#import <AppKit/AppKit.h>
#import <Virtualization/Virtualization.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLVMTerminalSession : NSObject
@property (nonatomic, readonly) NSURL *commandURL;
@property (nonatomic, readonly) NSURL *socketURL;
- (nullable instancetype)initWithConnection:(VZVirtioSocketConnection *)connection
                              executableURL:(NSURL *)executableURL error:(NSError **)error;
- (void)beginForwarding;
- (void)openInTerminalWithCompletion:(void (^)(NSError *_Nullable error))completion;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
