// Explicit desktop integration test. Runs only with a disposable browser profile.
#import <AppKit/AppKit.h>
#import "WebKitBrowserController.h"
#import "BrowserWebKitTestSupport.h"
#import "TLBrowserPreferences.h"
#import "TLBrowserDownloadManager.h"
#import "TLBrowserImageActions.h"
@interface TLProbeApplication : NSApplication
@end
@implementation TLProbeApplication
@end
static void Check(BOOL condition, NSString *message) {
  if (!condition) { fprintf(stderr,"FAIL: %s\n",message.UTF8String); exit(1); }
  fprintf(stdout,"PASS: %s\n",message.UTF8String); fflush(stdout);
}
@interface TLWebKitBrowserController (ImageTests)
- (void)openImageURL:(NSURL *)URL inSession:(TLWebKitBrowserSession *)session inNewWindow:(BOOL)newWindow;
- (NSMenu *)imageMenuForURL:(NSURL *)URL inSession:(TLWebKitBrowserSession *)session frame:(WKFrameInfo *)frame hasImage:(BOOL)hasImage;
- (void)configureMenu:(NSMenu *)menu event:(NSEvent *)event session:(TLWebKitBrowserSession *)session;
- (NSMenu *)pageMenuForSession:(TLWebKitBrowserSession *)session contextMenu:(NSMenu *)menu point:(NSPoint)point;
- (void)readImageAtURL:(NSURL *)URL inSession:(TLWebKitBrowserSession *)session frame:(WKFrameInfo *)frame completion:(void (^)(TLBrowserImageResource *, NSError *))completion;
@end
@interface TLImageProbeDelegate : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property TLWebKitBrowserSession *session;
@property NSString *baseURL;
@property BOOL started;
@property NSURL *openedURL;
@end
@implementation TLImageProbeDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  self.baseURL = NSProcessInfo.processInfo.environment[@"TL_BROWSER_TEST_URL"];
  Check([TLBrowserPreferences.profileURL.path hasPrefix:@"/tmp/talaria-image-test-"], @"isolated profile");
  self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,650) styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  [self.window makeKeyAndOrderFront:nil];
  self.session = [TLWebKitBrowserController.sharedController loadURL:[NSURL URLWithString:self.baseURL] inView:self.window.contentView fromWindow:self.window
    titleHandler:^(NSString *title) {
      if (![title isEqual:@"images ready"] || self.started) return;
      self.started = YES;
      dispatch_async(dispatch_get_main_queue(), ^{ [self testMenu]; [self testMedia]; });
    } linkHandler:^(NSURL *URL, NSEventModifierFlags modifiers) { self.openedURL = URL; Check(modifiers == 0, @"image tab ignores menu modifiers"); }
    URLHandler:nil faviconHandler:nil navigationHandler:nil];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,40*NSEC_PER_SEC),dispatch_get_main_queue(), ^{ Check(NO,@"image integration timeout"); });
}
- (void)testMenu {
  NSMenu *model = [NSMenu new];
  [self.session setValue:@{@"image":[self.baseURL stringByAppendingString:@"/image.png"],@"hasImage":@YES} forKey:@"context"];
  [TLWebKitBrowserController.sharedController configureMenu:model event:nil session:self.session];
  Check(model.numberOfItems == 16, @"image menu has all twelve actions and four separators");
  NSArray *expected = @[@"Open Image in New Tab", @"Open Image in New Window", @"", @"Save Image to “Downloads”", @"Save Image As…", @"Add Image to Photos", @"Use Image as Desktop Wallpaper", @"", @"Copy Image Address", @"Copy Image", @"Copy Subject", @"Look Up", @"", @"Share…", @"", @"Inspect Element"];
  for (NSUInteger i=0; i<expected.count; i++) {
    NSString *title = [model itemAtIndex:i].title;
    Check([title isEqual:expected[i]], [NSString stringWithFormat:@"image menu row %lu: %@",(unsigned long)i,title]);
  }
  Check(![model itemWithTitle:@"Look Up"].enabled, @"Look Up matches disabled reference state");
  model = [TLWebKitBrowserController.sharedController imageMenuForURL:[NSURL URLWithString:[self.baseURL stringByAppendingString:@"/missing.png"]] inSession:self.session frame:nil hasImage:NO];
  Check(![model itemWithTitle:@"Copy Image"].enabled && [model itemWithTitle:@"Copy Image Address"].enabled, @"broken image permits address actions without pretending content is available");
  for (NSString *URL in @[@"javascript:alert(1)",@"data:text/html,hello",@"file:///etc/passwd",@"https:"]) Check(!TLBrowserImageURLIsSupported([NSURL URLWithString:URL]), @"unsafe image navigation rejected");
  model = [NSMenu new]; [model addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@""];
  model = [TLWebKitBrowserController.sharedController pageMenuForSession:self.session contextMenu:model point:NSZeroPoint];
  Check(model.numberOfItems == 10 && [[model itemAtIndex:0].title isEqual:@"Copy"] && ![model itemWithTitle:@"Open Image in New Tab"], @"page/editing context menu remains unchanged");
  NSURL *URL = [NSURL URLWithString:[self.baseURL stringByAppendingString:@"/image.png"]];
  [TLWebKitBrowserController.sharedController openImageURL:URL inSession:self.session inNewWindow:NO];
  Check([self.openedURL isEqual:URL], @"Open Image in New Tab uses workspace tab handler");
}
- (void)testMedia {
  NSString *script=@"const video=document.createElement('video');video.muted=true;video.preload='auto';video.src='/movie.mov';document.body.append(video);"
    @"const formats={h264:video.canPlayType('video/mp4; codecs=\"avc1.42E01E\"'),aac:document.createElement('audio').canPlayType('audio/mp4; codecs=\"mp4a.40.2\"')};"
    @"await new Promise((resolve,reject)=>{video.onloadeddata=resolve;video.onerror=()=>reject(new Error('H.264 fixture failed to decode'));setTimeout(()=>reject(new Error('H.264 decode deadline')),5000)});"
    @"await video.play();await new Promise((resolve,reject)=>{video.onended=resolve;setTimeout(()=>reject(new Error('H.264 playback deadline')),5000)});"
    @"const result={...formats,width:video.videoWidth,height:video.videoHeight,played:video.played.length};video.remove();return result;";
  [self.session.webView callAsyncJavaScript:script arguments:@{} inFrame:nil inContentWorld:WKContentWorld.pageWorld completionHandler:^(NSDictionary *media,NSError *error){
    Check(!error, [NSString stringWithFormat:@"Native H.264 video decodes and plays (%@)",error.localizedDescription ?: @"ok"]);
    Check([media[@"width"] integerValue]>0 && [media[@"height"] integerValue]>0 && [media[@"played"] integerValue]>0,@"H.264 fixture produces actual video frames");
    Check([media[@"h264"] length]>0 && [media[@"aac"] length]>0,@"WebKit advertises H.264 and AAC playback support");
    [self readImage:0];
  }];
}
- (void)readImage:(NSUInteger)index {
  NSArray *paths = @[@"/image.png", @"/animation.gif", @"/vector.svg"];
  if (index == paths.count) { [self testBlob]; return; }
  NSURL *URL = [NSURL URLWithString:[self.baseURL stringByAppendingString:paths[index]]];
  [TLWebKitBrowserController.sharedController readImageAtURL:URL inSession:self.session frame:nil completion:^(TLBrowserImageResource *resource, NSError *error) {
    NSData *expected = [NSData dataWithContentsOfURL:[TLBrowserPreferences.profileURL URLByAppendingPathComponent:[paths[index] lastPathComponent]]];
    Check(!error && [resource.data isEqual:expected], [NSString stringWithFormat:@"cached %@ preserves exact original bytes and format",paths[index]]);
    Check(resource.image != nil, @"image formats expose pixels for native image actions");
    Check([resource.fileName isEqual:[paths[index] lastPathComponent]], @"image filename retains matching extension");
    if (index == 0) [self testSave:resource URL:URL completion:^{ [self readImage:index+1]; }]; else [self readImage:index+1];
  }];
}
- (void)testSave:(TLBrowserImageResource *)resource URL:(NSURL *)URL completion:(dispatch_block_t)completion {
  NSPasteboard *pasteboard = [NSPasteboard pasteboardWithUniqueName];
  Check([TLBrowserImageActions copyImage:resource.image toPasteboard:pasteboard] && [NSImage canInitWithPasteboard:pasteboard], @"Copy Image writes actual image data");
  [pasteboard releaseGlobally];
  TLBrowserDownloadManager *manager = [[TLBrowserDownloadManager alloc] initWithHistoryURL:[TLBrowserPreferences.profileURL URLByAppendingPathComponent:@"image-history.json"]];
  NSURL *destination = [TLBrowserPreferences.profileURL URLByAppendingPathComponent:@"Saved/image.png"];
  [TLBrowserImageActions saveResource:resource URL:URL destination:destination overwrite:NO manager:manager completion:^(NSError *error) {
    Check(!error && manager.downloads.firstObject.fileAvailable, @"quick save is recorded as a completed download");
    [TLBrowserImageActions saveResource:resource URL:URL destination:destination overwrite:NO manager:manager completion:^(NSError *error) {
      Check(!error && manager.downloads.count == 2 && ![manager.downloads[0].path isEqual:manager.downloads[1].path], @"quick save never overwrites an existing image");
      Check([[NSData dataWithContentsOfURL:destination] isEqual:resource.data], @"saved image matches original content");
      [TLBrowserImageActions saveResource:resource URL:URL destination:destination overwrite:YES manager:manager completion:^(NSError *error) {
        Check(!error && [manager.downloads.firstObject.path isEqual:destination.path], @"Save As honors the explicitly chosen destination");
        [TLBrowserImageActions saveResource:resource URL:URL destination:[destination URLByAppendingPathComponent:@"impossible.png"] overwrite:NO manager:manager completion:^(NSError *error) {
          Check(error && manager.downloads.firstObject.state == TLBrowserDownloadStateFailed, @"write errors produce a failed download instead of phantom activity");
          for (NSSharingServiceName name in @[NSSharingServiceNameAddToIPhoto, NSSharingServiceNameUseAsDesktopPicture]) {
            Check([[NSSharingService sharingServiceNamed:name] canPerformWithItems:@[resource.image]], @"native Photos/wallpaper service accepts image content");
          }
          [TLBrowserImageActions copySubjectOfImage:resource.image completion:^(NSImage *subject, NSError *error) {
            Check(subject != nil || error.localizedDescription.length > 0, @"subject extraction returns pixels or an actionable no-subject error");
            completion();
          }];
        }];
      }];
    }];
  }];
}
- (void)testBlob {
  TLTestEvaluate(self.session.webView, @"document.getElementById('blob').src", ^(NSString *URLString) {
    NSURL *URL = [NSURL URLWithString:URLString];
    Check(TLBrowserImageURLIsSupported(URL), @"blob image URL can open in a browser tab");
    [TLWebKitBrowserController.sharedController readImageAtURL:URL inSession:self.session frame:nil completion:^(TLBrowserImageResource *resource, NSError *error) {
      Check(!error && resource.image && resource.data.length, @"blob image can be read using the owning browser");
      [TLWebKitBrowserController.sharedController closeSession:self.session];
      [NSApp terminate:nil];
    }];
  });
}
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender { return [TLWebKitBrowserController.sharedController prepareForApplicationTermination] ? NSTerminateNow : NSTerminateLater; }
- (void)applicationWillTerminate:(NSNotification *)notification { [TLWebKitBrowserController.sharedController shutdown]; fprintf(stdout,"TALARIA_BROWSER_TEST_COMPLETE\n"); fflush(stdout); }
@end
int main(int argc,char **argv) { @autoreleasepool {
  NSApplication *app = [TLProbeApplication sharedApplication];
  static TLImageProbeDelegate *delegate; delegate = [TLImageProbeDelegate new]; app.delegate = delegate;
  [app setActivationPolicy:NSApplicationActivationPolicyAccessory]; [app finishLaunching]; [app run]; return 0;
}}
