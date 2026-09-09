#import "ChromiumFooterColor.h"
#import "TLBrowserContentColor.h"
#include <math.h>
#include "include/cef_devtools_message_observer.h"
#include "include/cef_registration.h"

class TLFooterColorRequest : public CefDevToolsMessageObserver {
 public:
  TLFooterColorRequest(CefRefPtr<CefBrowser> browser, NSNumber *context, NSString *source, bool capture, NSDictionary *cachedSample, void (^completion)(NSDictionary *))
    : browser_(browser), context_(context), source_(source), cachedSample_(cachedSample), completion_([completion copy]), capture_(capture) {}
  void Start() {
    registration_=browser_->GetHost()->AddDevToolsMessageObserver(this);
    CefRefPtr<TLFooterColorRequest> alive=this;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{alive->Finish(nil);});
    Send(@"Runtime.evaluate",@{@"contextId":context_,@"expression":[NSString stringWithFormat:@"(%@)()",source_],@"returnByValue":@YES,@"awaitPromise":@YES,@"silent":@YES,@"timeout":@200},CSS);
  }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser> browser,int identifier,bool success,const void *result,size_t size) override {
    if(!completion_ || identifier!=identifier_)return;
    CefRefPtr<TLFooterColorRequest> alive=this;
    if(!success || size>(stage_==Capture ? 12*1024*1024 : 64*1024)){Finish(nil);return;}
    NSDictionary *value=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil];
    if(![value isKindOfClass:NSDictionary.class]){Finish(nil);return;}
    if(stage_==CSS) {
      NSDictionary *sample=value[@"result"][@"value"];
      if(![sample isKindOfClass:NSDictionary.class]){Finish(nil);return;}
      sample_=[sample mutableCopy];
      top_=[sample[@"top"] isKindOfClass:NSDictionary.class] ? [sample[@"top"] mutableCopy] : nil;
      RestoreCachedPixels(sample_,cachedSample_);
      RestoreCachedPixels(top_,cachedSample_[@"top"]);
      if(top_)sample_[@"top"]=top_;
      captureFooter_=NeedsPixels(sample_);captureTop_=NeedsPixels(top_);
      if(!capture_ || (!captureFooter_ && !captureTop_)){Finish(sample_);return;}
      NSDictionary *captureSample=captureFooter_ ? sample_ : top_;
      NSArray *view=captureSample[@"viewState"];
      if(view.count!=4 || [view[0] doubleValue]<1 || [view[1] doubleValue]<1){Finish(nil);return;}
      if(captureFooter_ && [sample[@"documentExtension"] boolValue] && ![sample[@"token"] isKindOfClass:NSNumber.class]){Finish(nil);return;}
      captureView_=view;
      // Bound readback before asking Chromium to encode a full viewport.
      double pixels=[view[0] doubleValue]*[view[1] doubleValue]*pow([captureSample[@"deviceScale"] doubleValue],2);
      if(!isfinite(pixels) || pixels<=0 || pixels>TLBrowserContentColorMaximumImagePixels){Finish(sample);return;}
      captureStart_=NSProcessInfo.processInfo.systemUptime;
      // A CDP clip RESIZES the live render widget even with scale:1 and
      // captureBeyondViewport:false. Read the existing viewport without a clip;
      // crop its bottom edge off-thread after capture instead.
      Send(@"Page.captureScreenshot",@{@"format":@"png",@"fromSurface":@YES,@"captureBeyondViewport":@NO,@"optimizeForSpeed":@YES},Capture);
    } else if(stage_==Capture) {
      NSString *encoded=value[@"data"];if(![encoded isKindOfClass:NSString.class]){Finish(nil);return;}
      NSData *data=[[NSData alloc] initWithBase64EncodedString:encoded options:0];
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        double viewportHeight=[alive->captureView_[1] doubleValue];
        double bottom=[alive->sample_[@"sampleBottom"] doubleValue];
        BOOL extension=alive->captureFooter_ && [alive->sample_[@"documentExtension"] boolValue];
        NSArray *topRGB=alive->captureTop_ ? [TLBrowserContentColor dominantRGBForImageData:data
          bottomFraction:[alive->top_[@"sampleBottom"] doubleValue]/viewportHeight] : nil;
        NSArray *rgb=alive->captureFooter_ && !extension ? [TLBrowserContentColor dominantRGBForImageData:data
          bottomFraction:bottom>0 ? bottom/viewportHeight : 1] : nil;
        NSArray *colors=extension ? [TLBrowserContentColor horizontalRGBStripForImageData:data
          bottomFraction:bottom/viewportHeight widthFraction:[alive->sample_[@"contentWidth"] doubleValue]/[alive->captureView_[0] doubleValue]] : nil;
        dispatch_async(dispatch_get_main_queue(),^{
          if(!alive->completion_)return;
          alive->sample_[@"captureMS"]=@((NSProcessInfo.processInfo.systemUptime-alive->captureStart_)*1000);
          if(topRGB){alive->top_[@"rgb"]=topRGB;alive->top_[@"mode"]=@"pixels";}
          if(rgb){alive->sample_[@"rgb"]=rgb;alive->sample_[@"mode"]=@"pixels";}
          if(!topRGB && !rgb && !colors){alive->Finish(alive->sample_);return;}
          NSString *state=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:alive->captureView_ options:0 error:nil] encoding:NSUTF8StringEncoding];
          NSString *valid=[NSString stringWithFormat:@"!globalThis.__talariaDocumentFooter?.isScrolling() && JSON.stringify([innerWidth,innerHeight,scrollX,scrollY])===JSON.stringify(%@)",state];
          if(alive->captureFooter_ && !extension) {
            id bannerBottom=alive->sample_[@"bannerBottom"];
            NSString *edge=[bannerBottom isKindOfClass:NSNumber.class] ? [NSString stringWithFormat:@"Math.max(1,innerHeight-%g)",[bannerBottom doubleValue]] : @"(globalThis.__talariaDocumentFooter?.sampleBottom?.() ?? innerHeight)";
            valid=[valid stringByAppendingFormat:@" && Math.abs((%@)-%g)<1",edge,bottom];
          }
          alive->capturedStrip_=colors!=nil;
          if(colors) {
            NSDictionary *payload=@{@"token":alive->sample_[@"token"],@"viewState":alive->sample_[@"viewState"],@"colors":colors};
            NSString *json=[[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:payload options:0 error:nil] encoding:NSUTF8StringEncoding];
            // Apply the document strip only after validating the shared capture.
            valid=[valid stringByAppendingFormat:@" && globalThis.__talariaDocumentFooter?.acceptCanvasSample(%@)",json];
          }
          alive->Send(@"Runtime.evaluate",@{@"contextId":alive->context_,@"expression":valid,@"returnByValue":@YES,@"silent":@YES},Validate);
        });
      });
    } else {
      if(captureFooter_ && [sample_[@"documentExtension"] boolValue])sample_[@"applied"]=@(capturedStrip_ && [value[@"result"][@"value"] isEqual:@YES]);
      if(![value[@"result"][@"value"] isEqual:@YES]) {
        if(captureFooter_)[sample_ removeObjectForKey:@"rgb"];
        if(captureTop_)[top_ removeObjectForKey:@"rgb"];
      }
      Finish(sample_);
    }
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override {CefRefPtr<TLFooterColorRequest> alive=this;Finish(nil);}
 private:
  enum Stage {CSS,Capture,Validate};
  static bool NeedsPixels(NSDictionary *sample) {return sample && !sample[@"rgb"] && ![sample[@"busy"] boolValue] && [sample[@"captureReady"] boolValue];}
  static void RestoreCachedPixels(NSMutableDictionary *sample,NSDictionary *cached) {
    if(sample && !sample[@"rgb"] && sample[@"captureKey"] && [sample[@"captureKey"] isEqual:cached[@"captureKey"]] && cached[@"rgb"]) {
      sample[@"rgb"]=cached[@"rgb"];sample[@"mode"]=@"cachedPixels";
    }
  }
  void Send(NSString *method,NSDictionary *params,Stage stage) {
    if(!browser_ || !browser_->IsValid()){Finish(nil);return;}
    static int next=1500000000;identifier_=++next;stage_=stage;
    NSData *json=[NSJSONSerialization dataWithJSONObject:@{@"id":@(identifier_),@"method":method,@"params":params} options:0 error:nil];
    browser_->GetHost()->SendDevToolsMessage(json.bytes,json.length);
  }
  void Finish(NSDictionary *result) {
    if(!completion_)return;
    if(!result && captureStart_>0) {
      sample_[@"captureMS"]=@((NSProcessInfo.processInfo.systemUptime-captureStart_)*1000);
      [sample_ removeObjectForKey:@"rgb"];[top_ removeObjectForKey:@"rgb"];result=sample_;
    }
    auto callback=completion_;completion_=nil;registration_=nullptr;browser_=nullptr;callback(result ?: @{});
  }
  CefRefPtr<CefBrowser> browser_;CefRefPtr<CefRegistration> registration_;
  NSNumber *__strong context_;NSString *__strong source_;NSMutableDictionary *__strong sample_;
  NSDictionary *__strong cachedSample_;NSMutableDictionary *__strong top_;NSArray *__strong captureView_;
  bool captureFooter_=false,captureTop_=false,capturedStrip_=false;
  void (^__strong completion_)(NSDictionary *);
  bool capture_;Stage stage_=CSS;int identifier_=0;double captureStart_=0;
  IMPLEMENT_REFCOUNTING(TLFooterColorRequest);
};
void TLSampleChromiumFooterColor(CefRefPtr<CefBrowser> browser, NSNumber *context, NSString *source, BOOL captureAllowed, NSDictionary *cachedSample, void (^completion)(NSDictionary *)) {
  CefRefPtr<TLFooterColorRequest> request=new TLFooterColorRequest(browser,context,source,captureAllowed,cachedSample,completion);request->Start();
}
