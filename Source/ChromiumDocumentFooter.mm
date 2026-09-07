#import "ChromiumDocumentFooter.h"
#import "ChromiumFooterColor.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_registration.h"

class TLDocumentFooterBridge : public CefDevToolsMessageObserver {
 public:
  TLDocumentFooterBridge(CefRefPtr<CefBrowser> browser,NSString *source):browser_(browser),source_(source) {
    callbacks_=[NSMutableDictionary dictionary];
  }
  void Start(){registration_=browser_->GetHost()->AddDevToolsMessageObserver(this);Send(@"Page.getFrameTree",@{},Tree);}
  bool Ready(){return ready_;}
  void Configure(NSDictionary *config,void (^completion)(BOOL)) {
    configuration_=[config copy];
    if(!ready_){
      if(completion){if(pending_)pending_(NO);pending_=[completion copy];
        NSUInteger generation=++pendingGeneration_;CefRefPtr<TLDocumentFooterBridge> alive=this;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
          if(generation!=alive->pendingGeneration_)return;
          auto callback=alive->pending_;alive->pending_=nil;if(callback)callback(NO);
        });}
      return;
    }
    Invoke(@"configure",config,completion);
  }
  void Invoke(NSString *method,id argument,void (^completion)(BOOL)) {
    if(!ready_){if(completion)completion(NO);return;}
    NSData *json=[NSJSONSerialization dataWithJSONObject:@[argument] options:0 error:nil];
    NSString *expression=[NSString stringWithFormat:@"globalThis.__talariaDocumentFooter?.%@((%@)[0])",method,[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    Raw(@"Runtime.evaluate",@{@"contextId":context_,@"expression":expression,@"returnByValue":@YES,@"silent":@YES},false,completion);
  }
  void SampleColor(bool capture,void (^completion)(NSDictionary *)) {
    if(!ready_ || !browser_){completion(@{});return;}
    static NSString *source;static dispatch_once_t once;
    dispatch_once(&once,^{source=[NSString stringWithContentsOfURL:[NSBundle.mainBundle URLForResource:@"BrowserFooterColor" withExtension:@"js"] encoding:NSUTF8StringEncoding error:nil];});
    if(!source.length){completion(@{});return;}
    CefRefPtr<TLDocumentFooterBridge> alive=this;
    id banner=configuration_[@"banner"] ?: NSNull.null;
    NSData *json=[NSJSONSerialization dataWithJSONObject:@[banner] options:0 error:nil];
    NSString *withBanner=[NSString stringWithFormat:@"function(){const read=(%@);const top=read(null,true);const bottom=read((%@)[0]);return {...bottom,top,cpuMS:(top.cpuMS||0)+(bottom.cpuMS||0),maxSliceMS:(top.cpuMS||0)+(bottom.cpuMS||0)};}",source,[[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    TLSampleChromiumFooterColor(browser_,context_,withBanner,capture,pixelSample_,^(NSDictionary *sample){
      if(alive->ready_) {
        NSMutableDictionary *cache=[alive->pixelSample_ mutableCopy] ?: [NSMutableDictionary dictionary];
        if([sample[@"mode"] isEqual:@"pixels"] && sample[@"rgb"]) {cache[@"rgb"]=sample[@"rgb"];if(sample[@"captureKey"])cache[@"captureKey"]=sample[@"captureKey"];else [cache removeObjectForKey:@"captureKey"];}
        NSDictionary *top=sample[@"top"];
        if([top[@"mode"] isEqual:@"pixels"] && top[@"rgb"])cache[@"top"]=top;
        alive->pixelSample_=cache;
      }
      completion(sample);
    });
  }
  void Stop() {
    if(ready_)Raw(@"Runtime.evaluate",@{@"contextId":context_,@"expression":@"globalThis.__talariaDocumentFooter?.dispose()",@"silent":@YES},false,nil);
    ready_=false;registration_=nullptr;browser_=nullptr;
    auto pending=pending_;pending_=nil;if(pending)pending(NO);
    NSArray *callbacks=callbacks_.allValues;[callbacks_ removeAllObjects];for(void (^callback)(BOOL) in callbacks)callback(NO);
  }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>,int identifier,bool success,const void *result,size_t size) override {
    CefRefPtr<TLDocumentFooterBridge> alive=this;
    if(!browser_ || size>65536)return;
    NSDictionary *value=size ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil] : @{};
    void (^callback)(BOOL)=callbacks_[@(identifier)];
    if(callback){[callbacks_ removeObjectForKey:@(identifier)];callback(success && [value[@"result"][@"value"] isEqual:@YES]);return;}
    if(identifier!=messageID_ || !success || ![value isKindOfClass:NSDictionary.class])return;
    switch(stage_) {
      case Tree:{NSString *frame=value[@"frameTree"][@"frame"][@"id"];
        if(frame.length)Send(@"Page.createIsolatedWorld",@{@"frameId":frame,@"worldName":@"talaria-document-footer"},World);break;}
      case World:context_=value[@"executionContextId"];
        if([context_ isKindOfClass:NSNumber.class])Send(@"Runtime.evaluate",@{@"contextId":context_,@"expression":[NSString stringWithFormat:@"(%@)()",source_],@"silent":@YES},Installed);break;
      case Installed:ready_=!value[@"exceptionDetails"];
        if(ready_ && configuration_){auto pending=pending_;pending_=nil;Configure(configuration_,pending);}break;
    }
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override {CefRefPtr<TLDocumentFooterBridge> alive=this;Stop();}
 private:
  enum Stage{Tree,World,Installed};
  void Raw(NSString *method,NSDictionary *params,bool track,void (^completion)(BOOL)) {
    if(!browser_ || !browser_->IsValid()){if(completion)completion(NO);return;}
    static int next=1400000000;int identifier=++next;
    NSData *data=[NSJSONSerialization dataWithJSONObject:@{@"id":@(identifier),@"method":method,@"params":params} options:0 error:nil];
    if(track)messageID_=identifier;
    if(completion){callbacks_[@(identifier)]=[completion copy];CefRefPtr<TLDocumentFooterBridge> alive=this;
      dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        void (^cb)(BOOL)=alive->callbacks_[@(identifier)];[alive->callbacks_ removeObjectForKey:@(identifier)];if(cb)cb(NO);
      });}
    browser_->GetHost()->SendDevToolsMessage(data.bytes,data.length);
  }
  void Send(NSString *method,NSDictionary *params,Stage stage){stage_=stage;Raw(method,params,true,nil);}
  CefRefPtr<CefBrowser> browser_;CefRefPtr<CefRegistration> registration_;
  NSString *__strong source_;NSNumber *__strong context_;NSDictionary *__strong configuration_,*__strong pixelSample_;
  NSMutableDictionary *__strong callbacks_;void (^__strong pending_)(BOOL);
  Stage stage_=Tree;int messageID_=0;bool ready_=false;NSUInteger pendingGeneration_=0;
  IMPLEMENT_REFCOUNTING(TLDocumentFooterBridge);
};
@implementation TLChromiumDocumentFooter {CefRefPtr<TLDocumentFooterBridge> _bridge;}
- (instancetype)initWithBrowser:(CefRefPtr<CefBrowser>)browser source:(NSString *)source {if((self=[super init])){_bridge=new TLDocumentFooterBridge(browser,source);_bridge->Start();}return self;}
- (BOOL)ready{return _bridge && _bridge->Ready();}
- (void)configure:(NSDictionary *)config completion:(void (^)(BOOL))completion {if(_bridge)_bridge->Configure(config,completion);else if(completion)completion(NO);}
- (void)sampleColorAllowingCapture:(BOOL)capture completion:(void (^)(NSDictionary *))completion {if(_bridge)_bridge->SampleColor(capture,completion);else completion(@{});}
- (void)stop {if(_bridge){_bridge->Stop();_bridge=nullptr;}}
- (void)dealloc {[self stop];}
@end
