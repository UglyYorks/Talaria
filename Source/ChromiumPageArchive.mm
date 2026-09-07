#import "ChromiumPageArchive.h"
#include "include/cef_devtools_message_observer.h"

class TLChromiumPageArchiveRequest : public CefDevToolsMessageObserver {
 public:
  explicit TLChromiumPageArchiveRequest(void (^completion)(NSData *, NSError *)) : completion_([completion copy]) {}
  void Start(CefRefPtr<CefBrowser> browser) {
    registration_=browser->GetHost()->AddDevToolsMessageObserver(this);
    auto params=CefDictionaryValue::Create();params->SetString("format","mhtml");
    messageID_=browser->GetHost()->ExecuteDevToolsMethod(0,"Page.captureSnapshot",params);
    if(!messageID_) { Finish(nil,@"This page could not be saved.");return; }
    CefRefPtr<TLChromiumPageArchiveRequest> alive=this;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),dispatch_get_main_queue(),^{
      alive->Finish(nil,@"Saving this page timed out. Please try again.");
    });
  }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int messageID, bool success,
                             const void *result, size_t size) override {
    if(!completion_ || messageID!=messageID_)return;
    CefRefPtr<TLChromiumPageArchiveRequest> alive=this;
    NSDictionary *value=[NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil];
    NSString *archive=[value isKindOfClass:NSDictionary.class] && [value[@"data"] isKindOfClass:NSString.class] ? value[@"data"] : nil;
    Finish(success && archive.length ? [archive dataUsingEncoding:NSUTF8StringEncoding] : nil,
           success && archive.length ? nil : @"This page could not be saved.");
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override {
    CefRefPtr<TLChromiumPageArchiveRequest> alive=this;
    Finish(nil,@"The page closed before it could be saved.");
  }
 private:
  void Finish(NSData *archive, NSString *message) {
    if(!completion_)return;
    auto completion=completion_;completion_=nil;registration_=nullptr;
    dispatch_async(dispatch_get_main_queue(),^{
      completion(archive,message ? [NSError errorWithDomain:@"Talaria.PageArchive" code:1
        userInfo:@{NSLocalizedDescriptionKey:message}] : nil);
    });
  }
  int messageID_=0;
  CefRefPtr<CefRegistration> registration_;
  void (^__strong completion_)(NSData *, NSError *);
  IMPLEMENT_REFCOUNTING(TLChromiumPageArchiveRequest);
};

void TLChromiumCapturePageArchive(CefRefPtr<CefBrowser> browser, void (^completion)(NSData *, NSError *)) {
  CefRefPtr<TLChromiumPageArchiveRequest> request=new TLChromiumPageArchiveRequest(completion);
  request->Start(browser);
}
