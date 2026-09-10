#import <Foundation/Foundation.h>
#import "WebKitBrowserController.h"
#import "TLBrowserDownloadManager.h"

@interface TLWebKitBrowserController (LifecycleTests)
- (void)recordTransfer:(id)transfer;
- (void)finishTransfer:(id)transfer;
- (void)registerDownload:(id)download session:(TLWebKitBrowserSession *)session;
@end
@protocol TLTransferActions <NSObject, WKDownloadDelegate>
- (void)performAction:(TLBrowserDownloadAction)action;
@end

@interface TLDownloadFixture : NSObject
@property(nonatomic, weak) id delegate;
@property(nonatomic) NSProgress *progress;
@property(nonatomic, copy) void (^cancellation)(NSData *);
@property(nonatomic) NSUInteger cancellations;
@property(nonatomic, copy) NSURLRequest *originalRequest;
@end
@implementation TLDownloadFixture
- (void)cancel:(void (^)(NSData *))completion { self.cancellations++;self.cancellation=completion; }
@end
@interface TLResumeFixture : NSObject
@property(nonatomic, copy) void (^completion)(id);
@property(nonatomic, copy) NSURLRequest *restartedRequest;
@end
@implementation TLResumeFixture
- (void)resumeDownloadFromResumeData:(NSData *)data completionHandler:(void (^)(id))completion { self.completion=completion; }
- (void)startDownloadUsingRequest:(NSURLRequest *)request completionHandler:(void (^)(id))completion { self.restartedRequest=request;self.completion=completion; }
@end
@interface TLLifecycleController : TLWebKitBrowserController
@property(nonatomic) NSUInteger finishes;
@property(nonatomic, copy) void (^recorded)(id);
@end
@implementation TLLifecycleController
- (void)recordTransfer:(id)transfer { if(self.recorded)self.recorded(transfer); }
- (void)finishTransfer:(id)transfer { self.finishes++; }
@end

static void Check(BOOL value, const char *message) {
  if(!value){fprintf(stderr,"FAIL: %s\n",message);exit(1);}
}
static NSObject<TLTransferActions> *Transfer(TLLifecycleController *controller, TLResumeFixture *webView, TLBrowserDownloadState state) {
  TLWebKitBrowserSession *session=[TLWebKitBrowserSession new];
  [session setValue:webView forKey:@"webView"];
  id transfer=[NSClassFromString(@"TLWebKitDownloadTransfer") new];
  [transfer setValue:controller forKey:@"controller"];
  [transfer setValue:session forKey:@"session"];
  [transfer setValue:@(state) forKey:@"state"];
  [transfer setValue:[@"resume" dataUsingEncoding:NSUTF8StringEncoding] forKey:@"resumeData"];
  return transfer;
}
int main(void) {
  @autoreleasepool {
    TLLifecycleController *controller=[TLLifecycleController new];
    TLResumeFixture *view=[TLResumeFixture new];
    NSObject<TLTransferActions> *transfer=Transfer(controller,view,TLBrowserDownloadStatePaused);
    [transfer performAction:TLBrowserDownloadActionResume];
    [transfer performAction:TLBrowserDownloadActionCancel];
    TLDownloadFixture *late=[TLDownloadFixture new];view.completion(late);
    Check(late.cancellations==1 && controller.finishes==1,"Cancelled pending resume cannot start a new download");
    Check([[transfer valueForKey:@"state"] integerValue]==TLBrowserDownloadStateCancelled,"Late resume preserves cancelled state");

    controller=[TLLifecycleController new];view=[TLResumeFixture new];
    transfer=Transfer(controller,view,TLBrowserDownloadStatePaused);
    [transfer performAction:TLBrowserDownloadActionResume];
    [transfer performAction:TLBrowserDownloadActionPause];
    TLDownloadFixture *resumed=[TLDownloadFixture new];view.completion(resumed);
    Check(resumed.cancellations==1,"Pause queued during resume cancels the returned download for resume data");
    resumed.cancellation([@"new resume" dataUsingEncoding:NSUTF8StringEncoding]);
    Check([[transfer valueForKey:@"state"] integerValue]==TLBrowserDownloadStatePaused && controller.finishes==0,"Queued pause retains the transfer");
    [transfer performAction:TLBrowserDownloadActionCancel];
    Check(controller.finishes==1,"A paused transfer can subsequently be cancelled");

    controller=[TLLifecycleController new];view=[TLResumeFixture new];
    transfer=Transfer(controller,view,TLBrowserDownloadStatePaused);
    [transfer performAction:TLBrowserDownloadActionResume];
    [transfer performAction:TLBrowserDownloadActionPause];
    [transfer performAction:TLBrowserDownloadActionResume];
    resumed=[TLDownloadFixture new];view.completion(resumed);
    Check(resumed.cancellations==0 && controller.finishes==0 && [[transfer valueForKey:@"state"] integerValue]==TLBrowserDownloadStateDownloading,"Resume can undo a queued pause without requiring unavailable resume data");

    controller=[TLLifecycleController new];
    transfer=Transfer(controller,[TLResumeFixture new],TLBrowserDownloadStateDownloading);
    TLDownloadFixture *active=[TLDownloadFixture new];[transfer setValue:active forKey:@"download"];
    [transfer performAction:TLBrowserDownloadActionPause];
    [transfer performAction:TLBrowserDownloadActionCancel];
    active.cancellation(nil);
    Check([[transfer valueForKey:@"state"] integerValue]==TLBrowserDownloadStateCancelled && controller.finishes==1,"Cancel overrides an outstanding pause even when the server returns no resume data");

    for(NSUInteger resumable=0;resumable<2;resumable++) {
      controller=[TLLifecycleController new];view=[TLResumeFixture new];
      transfer=Transfer(controller,view,TLBrowserDownloadStateDownloading);
      [transfer setValue:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.test/file"]] forKey:@"restartRequest"];
      active=[TLDownloadFixture new];[transfer setValue:active forKey:@"download"];
      [transfer performAction:TLBrowserDownloadActionPause];
      [transfer performAction:TLBrowserDownloadActionResume];
      Check(view.completion==nil,"Resume waits while cancellation is collecting resume data");
      active.cancellation(resumable ? [@"resumable" dataUsingEncoding:NSUTF8StringEncoding] : nil);
      Check(view.completion!=nil && controller.finishes==0 && [[transfer valueForKey:@"state"] integerValue]==TLBrowserDownloadStateDownloading,"Queued Resume continues after Pause finishes, with or without native resume data");
      Check((view.restartedRequest!=nil)==!resumable,"Queued Resume chooses native continuation or safe GET restart correctly");

      controller=[TLLifecycleController new];view=[TLResumeFixture new];
      transfer=Transfer(controller,view,TLBrowserDownloadStateDownloading);
      [transfer setValue:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.test/file"]] forKey:@"restartRequest"];
      active=[TLDownloadFixture new];[transfer setValue:active forKey:@"download"];
      [transfer performAction:TLBrowserDownloadActionPause];
      [transfer performAction:TLBrowserDownloadActionResume];
      [transfer performAction:TLBrowserDownloadActionCancel];
      active.cancellation(resumable ? [@"resumable" dataUsingEncoding:NSUTF8StringEncoding] : nil);
      Check(view.completion==nil && controller.finishes==1 && [[transfer valueForKey:@"state"] integerValue]==TLBrowserDownloadStateCancelled,"Cancel overrides a queued Resume while cancellation completes");
    }

    controller=[TLLifecycleController new];view=[TLResumeFixture new];
    transfer=Transfer(controller,view,TLBrowserDownloadStateDownloading);
    active=[TLDownloadFixture new];[transfer setValue:active forKey:@"download"];
    __weak TLLifecycleController *observingController=controller;
    controller.recorded=^(NSObject<TLTransferActions> *item){
      if([[item valueForKey:@"state"] integerValue]==TLBrowserDownloadStatePaused && ![[item valueForKey:@"cancelling"] boolValue]){
        observingController.recorded=nil;[item performAction:TLBrowserDownloadActionResume];
      }
    };
    [transfer performAction:TLBrowserDownloadActionPause];active.cancellation([@"resumable" dataUsingEncoding:NSUTF8StringEncoding]);
    Check(view.completion!=nil && controller.finishes==0 && [[transfer valueForKey:@"awaitingDownload"] boolValue],"An observer resuming during the paused notification cannot have its new transfer destroyed");

    controller=[TLLifecycleController new];view=[TLResumeFixture new];
    TLWebKitBrowserSession *session=[TLWebKitBrowserSession new];[session setValue:view forKey:@"webView"];
    active=[TLDownloadFixture new];active.originalRequest=[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://example.test/file"]];
    [controller registerDownload:active session:session];
    transfer=[[controller valueForKey:@"transfers"] anyObject];
    [transfer performAction:TLBrowserDownloadActionPause];active.cancellation(nil);
    Check([[transfer valueForKey:@"state"] integerValue]==TLBrowserDownloadStatePaused && [[transfer valueForKey:@"failureReason"] containsString:@"restarts from the beginning"],"A nonresumable GET pauses with an explicit restart notice");
    [transfer setValue:@1024 forKey:@"receivedBytes"];
    [transfer performAction:TLBrowserDownloadActionResume];
    Check([view.restartedRequest.URL isEqual:active.originalRequest.URL] && [[transfer valueForKey:@"receivedBytes"] longLongValue]==0,"Resume restarts the original GET and resets progress");
    resumed=[TLDownloadFixture new];view.completion(resumed);
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *original=[directory stringByAppendingPathComponent:@"file.bin"];
    NSData *untouched=[@"User-owned replacement" dataUsingEncoding:NSUTF8StringEncoding];[untouched writeToFile:original atomically:YES];
    [transfer setValue:original forKey:@"path"];
    __block NSURL *chosen;
    NSURLResponse *response=[[NSURLResponse alloc] initWithURL:active.originalRequest.URL MIMEType:@"application/octet-stream" expectedContentLength:100 textEncodingName:nil];
    [transfer download:(WKDownload *)resumed decideDestinationUsingResponse:response suggestedFilename:@"file.bin" completionHandler:^(NSURL *URL){chosen=URL;}];
    Check(chosen && ![chosen.path isEqual:original] && [[NSData dataWithContentsOfFile:original] isEqual:untouched],"Restart allocates a collision-free destination without deleting a user-replaced file");
    [TLBrowserDownloadManager.sharedManager releaseDestinationForDownloadID:[[transfer valueForKey:@"identifier"] unsignedIntegerValue]];
    [NSFileManager.defaultManager removeItemAtPath:directory error:nil];

    controller=[TLLifecycleController new];active=[TLDownloadFixture new];
    NSMutableURLRequest *POST=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://example.test/export"]];POST.HTTPMethod=@"POST";POST.HTTPBody=[@"export=1" dataUsingEncoding:NSUTF8StringEncoding];active.originalRequest=POST;
    [controller registerDownload:active session:session];transfer=[[controller valueForKey:@"transfers"] anyObject];
    [transfer performAction:TLBrowserDownloadActionPause];active.cancellation(nil);
    Check([[transfer valueForKey:@"state"] integerValue]==TLBrowserDownloadStateFailed && ![transfer valueForKey:@"restartRequest"],"A POST download without resume data is never automatically replayed");

    TLWebKitBrowserSession *closed=[TLWebKitBrowserSession new];[closed setValue:@YES forKey:@"closed"];
    late=[TLDownloadFixture new];[controller registerDownload:late session:closed];
    Check(late.cancellations==1,"A download arriving after session closure is cancelled");
    [controller setValue:@YES forKey:@"shuttingDown"];
    late=[TLDownloadFixture new];[controller registerDownload:late session:[TLWebKitBrowserSession new]];
    Check(late.cancellations==1,"A download arriving after application shutdown is cancelled");
    puts("PASS: WebKit download lifecycle races");
  }
  return 0;
}
