#import "ChromiumImageActions.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_urlrequest.h"

void TLChromiumPopulateImageMenu(CefRefPtr<CefMenuModel> model, NSString *URLString, BOOL hasImage) {
  model->Clear();
  NSArray<NSString *> *titles = TLBrowserImageMenuTitles();
  BOOL supported = TLBrowserImageURLIsSupported([NSURL URLWithString:URLString]);
  for (NSUInteger index = 0; index < titles.count; index++) {
    if (index == TLBrowserImageSaveDownloads || index == TLBrowserImageCopyAddress || index == TLBrowserImageShare) model->AddSeparator();
    int command = TLChromiumImageCommandFirst + (int)index;
    model->AddItem(command, std::string(titles[index].UTF8String));
    BOOL enabled = supported;
    if (index == TLBrowserImageCopy || index == TLBrowserImageCopySubject || index == TLBrowserImageAddToPhotos ||
        index == TLBrowserImageWallpaper || index == TLBrowserImageShare) enabled &= hasImage;
    if (index == TLBrowserImageCopySubject) { if (@available(macOS 14.0, *)) {} else enabled = NO; }
    // Visual Look Up is unavailable on this Chromium surface; keep the disabled
    // item from the native reference menu instead of sending images to a search service.
    if (index == TLBrowserImageLookUp) enabled = NO;
    model->SetEnabled(command, enabled);
  }
  model->AddSeparator();
  model->AddItem(MENU_ID_USER_FIRST, "Inspect Element");
}

static NSError *TLImageReadError(void) {
  return [NSError errorWithDomain:@"Talaria.BrowserImage" code:1
    userInfo:@{NSLocalizedDescriptionKey:@"This image could not be read. Reload the page and try again."}];
}

class TLImageDownloadCallback : public CefDownloadImageCallback {
 public:
  TLImageDownloadCallback(NSURL *URL, void (^completion)(TLBrowserImageResource *, NSError *)) : URL_(URL), completion_([completion copy]) {}
  void OnDownloadImageFinished(const CefString&, int, CefRefPtr<CefImage> image) override {
    TLBrowserImageResource *resource = nil;
    if (image && !image->IsEmpty()) {
      int width = 0, height = 0;
      auto png = image->GetAsPNG(1, true, width, height);
      if (png && png->GetSize()) {
        NSMutableData *data = [NSMutableData dataWithLength:png->GetSize()]; png->GetData(data.mutableBytes, data.length, 0);
        resource = [TLBrowserImageResource resourceWithData:data URL:URL_ MIMEType:@"image/png"];
      }
    }
    auto completion = completion_; completion_ = nil;
    if (completion) completion(resource, resource ? nil : TLImageReadError());
  }
 private:
  NSURL *URL_;
  void (^completion_)(TLBrowserImageResource *, NSError *);
  IMPLEMENT_REFCOUNTING(TLImageDownloadCallback);
};

class TLImageURLRequestClient : public CefURLRequestClient {
 public:
  TLImageURLRequestClient(NSURL *URL, void (^completion)(TLBrowserImageResource *)) : URL_(URL), data_([NSMutableData data]), completion_([completion copy]) {}
  void OnDownloadData(CefRefPtr<CefURLRequest> request, const void *data, size_t length) override {
    if (data_.length + length > 128 * 1024 * 1024) { request->Cancel(); return; }
    [data_ appendBytes:data length:length];
  }
  void OnRequestComplete(CefRefPtr<CefURLRequest> request) override {
    auto response = request->GetResponse(); TLBrowserImageResource *resource = nil;
    if (request->GetRequestStatus() == UR_SUCCESS && response && response->GetStatus() < 400)
      resource = [TLBrowserImageResource resourceWithData:data_ URL:URL_ MIMEType:[NSString stringWithUTF8String:response->GetMimeType().ToString().c_str()]];
    auto completion = completion_; completion_ = nil; if (completion) completion(resource);
  }
  void OnUploadProgress(CefRefPtr<CefURLRequest>, int64_t, int64_t) override {}
  void OnDownloadProgress(CefRefPtr<CefURLRequest>, int64_t, int64_t) override {}
  bool GetAuthCredentials(bool, const CefString&, int, const CefString&, const CefString&, CefRefPtr<CefAuthCallback>) override { return false; }
 private:
  NSURL *URL_; NSMutableData *data_; void (^completion_)(TLBrowserImageResource *);
  IMPLEMENT_REFCOUNTING(TLImageURLRequestClient);
};

// Read the original cached resource first: this preserves GIF animation, SVG,
// encoding and authenticated images without refetching them outside Chromium.
class TLImageResourceRequest : public CefDevToolsMessageObserver {
 public:
  TLImageResourceRequest(NSURL *URL, NSString *frameURL, void (^completion)(TLBrowserImageResource *, NSError *))
    : URL_(URL), frameURL_(frameURL), completion_([completion copy]) {}
  void Start(CefRefPtr<CefBrowser> browser) {
    browser_ = browser; registration_ = browser->GetHost()->AddDevToolsMessageObserver(this);
    messageID_ = browser->GetHost()->ExecuteDevToolsMethod(0, "Page.getResourceTree", nullptr);
    CefRefPtr<TLImageResourceRequest> alive = this;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ alive->Finish(nil, TLImageReadError()); });
    if (!messageID_) Fallback();
  }
  void OnDevToolsMethodResult(CefRefPtr<CefBrowser>, int messageID, bool success, const void *result, size_t size) override {
    if (!completion_ || messageID != messageID_) return;
    CefRefPtr<TLImageResourceRequest> alive = this;
    NSDictionary *reply = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:result length:size] options:0 error:nil];
    if (!success || ![reply isKindOfClass:NSDictionary.class]) { Fallback(); return; }
    if (!reading_) {
      NSMutableArray *nodes = [NSMutableArray array];
      if ([reply[@"frameTree"] isKindOfClass:NSDictionary.class]) [nodes addObject:reply[@"frameTree"]];
      NSString *frameID = nil;
      while (nodes.count) {
        NSDictionary *node = nodes.lastObject; [nodes removeLastObject];
        for (NSDictionary *resource in node[@"resources"]) if ([resource[@"url"] isEqual:URL_.absoluteString]) {
          frameID = node[@"frame"][@"id"]; MIMEType_ = resource[@"mimeType"];
          if ([node[@"frame"][@"url"] isEqual:frameURL_]) break;
        }
        if (frameID && [node[@"frame"][@"url"] isEqual:frameURL_]) break;
        if ([node[@"childFrames"] isKindOfClass:NSArray.class]) [nodes addObjectsFromArray:node[@"childFrames"]];
      }
      if (!frameID.length) { Fallback(); return; }
      auto params = CefDictionaryValue::Create();
      params->SetString("frameId", std::string(frameID.UTF8String));
      params->SetString("url", std::string(URL_.absoluteString.UTF8String));
      reading_ = true;
      messageID_ = browser_->GetHost()->ExecuteDevToolsMethod(0, "Page.getResourceContent", params);
      if (!messageID_) Fallback();
    } else {
      NSString *content = [reply[@"content"] isKindOfClass:NSString.class] ? reply[@"content"] : nil;
      NSData *data = [reply[@"base64Encoded"] boolValue] ? [[NSData alloc] initWithBase64EncodedString:content ?: @"" options:0] : [content dataUsingEncoding:NSUTF8StringEncoding];
      TLBrowserImageResource *resource = data ? [TLBrowserImageResource resourceWithData:data URL:URL_ MIMEType:MIMEType_ ?: @""] : nil;
      if (resource) CompleteResource(resource); else Fallback();
    }
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser>) override {
    CefRefPtr<TLImageResourceRequest> alive = this; Finish(nil, TLImageReadError());
  }
 private:
  void Fallback() {
    if (!completion_ || fallback_) return;
    fallback_ = true; messageID_ = 0;
    // If the memory resource is gone, refetch through its Chromium profile so
    // cache, cookies and referrer policy stay associated with the browser.
    CefRefPtr<TLImageResourceRequest> alive = this;
    if (!browser_ || !browser_->IsValid()) { Finish(nil, TLImageReadError()); return; }
    auto request = CefRequest::Create(); request->SetURL(std::string(URL_.absoluteString.UTF8String));
    request->SetFlags(UR_FLAG_ALLOW_STORED_CREDENTIALS);
    request->SetReferrer(std::string(frameURL_.UTF8String), REFERRER_POLICY_DEFAULT);
    originalRequest_ = CefURLRequest::Create(request, new TLImageURLRequestClient(URL_, ^(TLBrowserImageResource *resource) {
      if (resource) alive->CompleteResource(resource); else alive->DecodeFallback();
    }), browser_->GetHost()->GetRequestContext());
    if (!originalRequest_) DecodeFallback();
  }
  void CompleteResource(TLBrowserImageResource *resource) {
    if (!completion_) return;
    if (resource.image) { Finish(resource, nil); return; }
    // Keep the original file, while obtaining pixels for formats AppKit cannot decode.
    CefRefPtr<TLImageResourceRequest> alive = this;
    browser_->GetHost()->DownloadImage(std::string(URL_.absoluteString.UTF8String), false, 0, false,
      new TLImageDownloadCallback(URL_, ^(TLBrowserImageResource *decoded, NSError *) {
        resource.image = decoded.image; alive->Finish(resource, nil);
      }));
  }
  void DecodeFallback() {
    if (!completion_ || !browser_ || !browser_->IsValid()) return;
    CefRefPtr<TLImageResourceRequest> alive = this;
    browser_->GetHost()->DownloadImage(std::string(URL_.absoluteString.UTF8String), false, 0, false,
      new TLImageDownloadCallback(URL_, ^(TLBrowserImageResource *resource, NSError *error) { alive->Finish(resource, error); }));
  }
  void Finish(TLBrowserImageResource *resource, NSError *error) {
    if (!completion_) return;
    auto completion = completion_; completion_ = nil; registration_ = nullptr; browser_ = nullptr;
    auto request = originalRequest_; originalRequest_ = nullptr;
    dispatch_async(dispatch_get_main_queue(), ^{
      // CEF must finish its callback before cancelling/releasing a URL request.
      if (request && request->GetRequestStatus() == UR_IO_PENDING) request->Cancel();
      completion(resource, error);
    });
  }
  NSURL *URL_;
  NSString *frameURL_, *MIMEType_;
  bool reading_ = false, fallback_ = false;
  int messageID_ = 0;
  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefRegistration> registration_;
  CefRefPtr<CefURLRequest> originalRequest_;
  void (^completion_)(TLBrowserImageResource *, NSError *);
  IMPLEMENT_REFCOUNTING(TLImageResourceRequest);
};
void TLChromiumReadImage(CefRefPtr<CefBrowser> browser, NSURL *URL, NSString *frameURL,
                        void (^completion)(TLBrowserImageResource *, NSError *)) {
  CefRefPtr<TLImageResourceRequest> request = new TLImageResourceRequest(URL, frameURL, completion);
  request->Start(browser);
}
