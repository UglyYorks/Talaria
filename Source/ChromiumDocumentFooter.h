#import <Foundation/Foundation.h>
#include "include/cef_browser.h"

@interface TLChromiumDocumentFooter : NSObject
@property(nonatomic, readonly) BOOL ready;
- (instancetype)initWithBrowser:(CefRefPtr<CefBrowser>)browser source:(NSString *)source;
- (void)configure:(NSDictionary *)configuration completion:(void (^)(BOOL applied))completion;
- (void)sampleColorAllowingCapture:(BOOL)capture completion:(void (^)(NSDictionary *))completion;
- (void)stop;
@end
