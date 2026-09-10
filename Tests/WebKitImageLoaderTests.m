#import <AppKit/AppKit.h>
#import "WebKitImageLoader.h"

@interface TLImageLoaderTest : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSMutableArray *results;
@property(nonatomic, copy) NSArray *cookies;
@property(nonatomic) NSUInteger index;
@end
@implementation TLImageLoaderTest
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.results=[NSMutableArray array];
  NSMutableArray *cookies=[NSMutableArray array];
  for(NSDictionary *values in @[@{@"name":@"source",@"domain":@"127.0.0.1",@"path":@"/"},@{@"name":@"target",@"domain":@"localhost",@"path":@"/"},@{@"name":@"wrongpath",@"domain":@"127.0.0.1",@"path":@"/private"},@{@"name":@"secure",@"domain":@"127.0.0.1",@"path":@"/",@"secure":@YES}]) {
    NSMutableDictionary *properties=[@{NSHTTPCookieName:values[@"name"],NSHTTPCookieValue:@"fixture",NSHTTPCookieDomain:values[@"domain"],NSHTTPCookiePath:values[@"path"]} mutableCopy];
    if(values[@"secure"])properties[NSHTTPCookieSecure]=@"TRUE";
    [cookies addObject:[NSHTTPCookie cookieWithProperties:properties]];
  }
  self.cookies=cookies;[self next];
}
- (void)next {
  NSArray *paths=@[@"/direct",@"/redirect",@"/too-large",@"/unknown-length"];
  if(self.index==paths.count) {
    [[NSJSONSerialization dataWithJSONObject:self.results options:0 error:nil] writeToFile:NSProcessInfo.processInfo.arguments[2] atomically:YES];[NSApp terminate:nil];return;
  }
  NSString *path=paths[self.index++];
  NSURL *URL=[NSURL URLWithString:[NSProcessInfo.processInfo.arguments[1] stringByAppendingString:path]];
  [TLWebKitImageLoader loadURL:URL cookies:self.cookies completion:^(NSData *data,NSString *type,NSError *error){
    [self.results addObject:@{@"path":path,@"data":data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"",@"failed":@(error!=nil)}];[self next];
  }];
}
@end
int main(void) {@autoreleasepool{NSApplication *app=NSApplication.sharedApplication;TLImageLoaderTest *delegate=[TLImageLoaderTest new];app.delegate=delegate;[app run];}return 0;}
