#import "ChromiumOverlayProbe.h"
#include "include/cef_devtools_message_observer.h"
#include "include/cef_registration.h"

static NSString *TLOverlayJSONString(id value) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:value options:0 error:nil];
  return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
}

// One bounded inspection. Does not enable DOM/Runtime event streams, enumerate
// document contents, snapshot the document, or retain nodes between inspections. Nested
// targets are attached only after hit-testing their visible frame owner.
class TLOverlayRequest : public CefDevToolsMessageObserver {
 public:
  TLOverlayRequest(CefRefPtr<CefBrowser> browser, NSString *source, NSDictionary *geometry,
                   void (^completion)(NSDictionary *))
      : browser_(browser), source_([source copy]), geometry_([geometry copy]), completion_([completion copy]) {
    contexts_ = [NSMutableDictionary dictionary];
    sessions_ = [NSMutableArray arrayWithObject:@""];
    parents_ = [NSMutableDictionary dictionary];
    group_ = [@"talaria-overlay-" stringByAppendingString:NSUUID.UUID.UUIDString];
    session_ = @"";
  }
  void Start() {
    registration_ = browser_->GetHost()->AddDevToolsMessageObserver(this);
    Send(@"Page.getFrameTree", @{}, FrameTree);
    CefRefPtr<TLOverlayRequest> keepAlive = this;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
      keepAlive->Finish(nil);
    });
  }
  bool OnDevToolsMessage(CefRefPtr<CefBrowser> browser, const void *message, size_t size) override {
    NSDictionary *reply = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:message length:size] options:0 error:nil];
    if (!completion_ || ![reply isKindOfClass:NSDictionary.class] || [reply[@"id"] intValue] != messageID_) return false;
    CefRefPtr<TLOverlayRequest> keepAlive = this;
    if (reply[@"error"] || ![reply[@"result"] isKindOfClass:NSDictionary.class]) { failure_=reply[@"error"]; Finish(nil); return true; }
    NSDictionary *value = reply[@"result"];
    // A hit-test reply includes IPC and renderer queueing. Keep that latency
    // diagnostic-only: billing it as CPU can turn a busy page into seconds of
    // unnecessary idle. Native hit tests instead receive a bounded work allowance.
    if (stage_ == Hit) hitRoundTripMS_ += (NSProcessInfo.processInfo.systemUptime - sentAt_) * 1000;
    switch (stage_) {
      case FrameTree:
        frameID_ = value[@"frameTree"][@"frame"][@"id"];
        mainFrameID_=frameID_; inspectedFrameID_=frameID_;
        if (!frameID_.length) { Finish(nil); break; }
        Send(@"Page.createIsolatedWorld", @{@"frameId":frameID_, @"worldName":@"talaria-overlay"}, MainWorld);
        break;
      case MainWorld: {
        NSNumber *context = value[@"executionContextId"];
        if (![context isKindOfClass:NSNumber.class]) { Finish(nil); break; }
        contexts_[ContextKey()] = context;
        mainContext_ = context;
        NSString *script = [NSString stringWithFormat:@"(%@)(%@)", source_, TLOverlayJSONString(geometry_)];
        Send(@"Runtime.evaluate", @{@"contextId":context, @"expression":script,
          @"returnByValue":@YES, @"awaitPromise":@YES, @"silent":@YES, @"timeout":@50}, Scan);
        break;
      }
      case Scan: {
        NSDictionary *scan = Value(value);
        if (!scan) { Finish(nil); break; }
        costMS_ += [scan[@"cpuMS"] doubleValue];
        maxSliceMS_ = MAX(maxSliceMS_, [scan[@"maxSliceMS"] doubleValue]);
        scan_ = scan;
        if ([scan[@"obstructed"] isEqual:@YES]) { banner_=scan[@"banner"]; reason_=scan[@"reason"]; Finish(@YES); break; }
        if (![scan[@"obstructed"] isEqual:@NO]) { Finish(nil); break; }
        if ([geometry_[@"skipFallback"] boolValue]) { Finish(nil); break; }
        points_ = [scan[@"fallbacks"] isKindOfClass:NSArray.class] ? scan[@"fallbacks"] : nil;
        if (!points_.count || points_.count > 3) { Finish(nil); break; }
        NextPoint();
        break;
      }
      case Hit: {
        backendID_ = value[@"backendNodeId"];
        frameID_ = value[@"frameId"];
        if (![backendID_ isKindOfClass:NSNumber.class] || !frameID_.length) { Finish(nil); break; }
        if(![frameID_ isEqual:inspectedFrameID_]) {
          // A same-process cross-origin hit can jump straight into a child.
          // Prove its outer frame first instead of asking child JS to cross SOP.
          Send(@"Page.getFrameTree",@{},HitFrameTree);break;
        }
        ResolveHit();
        break;
      }
      case HitFrameTree: {
        NSMutableDictionary *parents=[NSMutableDictionary dictionary];
        NSMutableArray *queue=[NSMutableArray arrayWithObject:value[@"frameTree"] ?: @{}];
        for(NSUInteger i=0;i<queue.count && i<128;i++) {
          NSDictionary *tree=queue[i];NSString *parent=tree[@"frame"][@"id"];
          for(NSDictionary *child in tree[@"childFrames"]) {
            if(queue.count>=128)break;
            NSString *identifier=child[@"frame"][@"id"];
            if(identifier && parent)parents[identifier]=parent;
            [queue addObject:child];
          }
        }
        NSString *child=frameID_;NSUInteger steps=0;
        while(parents[child] && ![parents[child] isEqual:inspectedFrameID_] && ++steps<6)child=parents[child];
        if(![parents[child] isEqual:inspectedFrameID_]){Finish(nil);break;}
        Send(@"DOM.getFrameOwner",@{@"frameId":child},HitFrameOwner);
        break;
      }
      case HitFrameOwner: {
        backendID_=value[@"backendNodeId"];frameID_=inspectedFrameID_;
        if(![backendID_ isKindOfClass:NSNumber.class]){Finish(nil);break;}
        ResolveHit();
        break;
      }
      case HitWorld: {
        NSNumber *context = value[@"executionContextId"];
        if (![context isKindOfClass:NSNumber.class]) { Finish(nil); break; }
        contexts_[ContextKey()] = context;
        Resolve(context);
        break;
      }
      case ResolveNode: {
        NSString *objectID = value[@"object"][@"objectId"];
        if (!objectID.length) { Finish(nil); break; }
        NSDictionary *argument = @{@"candidate":@YES, @"allowFrame":@(depth_ > 0),
          @"viewportPinned":@(depth_ > 0 && [point_[@"viewportPinned"] isEqual:@YES]), @"x":point_[@"x"], @"y":point_[@"y"]};
        NSString *function = [NSString stringWithFormat:@"function(config){ return (%@).call(this,config); }", source_];
        Send(@"Runtime.callFunctionOn", @{@"objectId":objectID, @"functionDeclaration":function,
          @"arguments":@[@{@"value":argument}], @"returnByValue":@YES, @"awaitPromise":@YES,
          @"silent":@YES}, Classify);
        break;
      }
      case Classify: {
        NSDictionary *result = Value(value);
        if(result[@"reason"] && ![result[@"obstructed"] isEqual:@YES])failure_=@{@"reason":result[@"reason"]};
        if (!result) { Finish(nil); break; }
        costMS_ += [result[@"cpuMS"] doubleValue];
        maxSliceMS_ = MAX(maxSliceMS_, [result[@"maxSliceMS"] doubleValue]);
        if ([result[@"obstructed"] isEqual:@YES]) { banner_=result[@"banner"]; reason_=result[@"reason"]; Finish(@YES); break; }
        if ([result[@"frame"] isKindOfClass:NSDictionary.class] && depth_++ < 2) {
          bannerScale_ *= [result[@"frame"][@"scaleY"] doubleValue];
          bannerCoverage_ *= [result[@"frame"][@"coverage"] doubleValue];
          point_ = result[@"frame"];
          Send(@"DOM.describeNode", @{@"backendNodeId":backendID_, @"depth":@0}, FrameOwner);
        } else if ([result[@"obstructed"] isEqual:@NO]) NextPoint();
        else Finish(nil);
        break;
      }
      case FrameOwner: {
        NSString *childID = value[@"node"][@"frameId"];
        if (!childID.length) { Finish(nil); break; }
        // Out-of-process frame IDs are target IDs. A still-loading or detached
        // frame returns an error; it must never be treated as a clear area.
        childFrameID_ = childID;
        // Chromium lazily creates OOP-frame DevTools agents during discovery.
        // Request only iframe target metadata; attach solely to this hit frame.
        Send(@"Target.getTargets", @{@"filter":@[@{@"type":@"iframe"}, @{@"exclude":@YES}]}, DiscoverFrame);
        break;
      }
      case ChildWorld: {
        NSNumber *context = value[@"executionContextId"];
        if (![context isKindOfClass:NSNumber.class]) { Finish(nil); break; }
        contexts_[ContextKey()] = context;
        if(!resetHitCoordinates_){HitPoint();break;}
        Send(@"Runtime.evaluate", @{@"contextId":context, @"expression":@"[scrollX,scrollY]",
          @"returnByValue":@YES, @"silent":@YES}, ChildScroll);
        break;
      }
      case ChildScroll: {
        NSArray *scroll = value[@"result"][@"value"];
        if (![scroll isKindOfClass:NSArray.class] || scroll.count != 2 ||
            ![scroll[0] isKindOfClass:NSNumber.class] || ![scroll[1] isKindOfClass:NSNumber.class]) { Finish(nil); break; }
        hitScrollX_ = [scroll[0] doubleValue]; hitScrollY_ = [scroll[1] doubleValue];
        HitPoint();
        break;
      }
      case Validate:
        Finish([value[@"result"][@"value"] isEqual:@YES] ? pendingResult_ : nil);
        break;
      case DiscoverFrame: {
        BOOL separate=NO;
        for(NSDictionary *target in value[@"targetInfos"])if([target[@"targetId"] isEqual:childFrameID_]){separate=YES;break;}
        if(separate)Send(@"Target.attachToTarget", @{@"targetId":childFrameID_, @"flatten":@YES}, Attach);
        else {
          // Same-site cross-origin documents can share the parent's target.
          // Keep native hit coordinates in that target, classification in child coordinates.
          frameID_=childFrameID_;inspectedFrameID_=childFrameID_;resetHitCoordinates_=false;
          Send(@"Page.createIsolatedWorld",@{@"frameId":frameID_,@"worldName":@"talaria-overlay"},ChildWorld);
        }
        break;
      }
      case Attach: {
        NSString *childSession = value[@"sessionId"];
        if (!childSession.length) { Finish(nil); break; }
        parents_[childSession] = session_;
        [sessions_ addObject:childSession];
        session_ = childSession;
        frameID_ = childFrameID_;
        inspectedFrameID_=frameID_;targetPoint_=point_;resetHitCoordinates_=true;
        Send(@"Page.createIsolatedWorld", @{@"frameId":frameID_, @"worldName":@"talaria-overlay"}, ChildWorld);
        break;
      }
    }
    return true;
  }
  void OnDevToolsAgentDetached(CefRefPtr<CefBrowser> browser) override {
    CefRefPtr<TLOverlayRequest> keepAlive = this;
    Finish(nil);
  }
 private:
  enum Stage {FrameTree, MainWorld, Scan, Hit, HitFrameTree, HitFrameOwner, HitWorld, ResolveNode, Classify, FrameOwner, DiscoverFrame, Attach, ChildWorld, ChildScroll, Validate};
  NSDictionary *Value(NSDictionary *result) {
    id value = result[@"result"][@"value"];
    return !result[@"exceptionDetails"] && [value isKindOfClass:NSDictionary.class] ? value : nil;
  }
  NSString *ContextKey() { return [NSString stringWithFormat:@"%@:%@", session_, frameID_]; }
  void ResolveHit() {
    NSNumber *context=contexts_[ContextKey()];
    if(context)Resolve(context);
    else Send(@"Page.createIsolatedWorld",@{@"frameId":frameID_,@"worldName":@"talaria-overlay"},HitWorld);
  }
  void Resolve(NSNumber *context) {
    Send(@"DOM.resolveNode", @{@"backendNodeId":backendID_, @"executionContextId":context, @"objectGroup":group_}, ResolveNode);
  }
  void NextPoint() {
    if (pointIndex_ >= points_.count) { Finish(@NO); return; }
    point_ = points_[pointIndex_++];
    rootPoint_ = point_;bannerScale_=1;bannerCoverage_=1;
    targetPoint_=point_;inspectedFrameID_=mainFrameID_;
    session_ = @"";
    depth_ = 0;
    NSArray *view = scan_[@"viewState"];
    hitScrollX_ = [view[2] doubleValue]; hitScrollY_ = [view[3] doubleValue];
    HitPoint();
  }
  void HitPoint() {
    if (![point_[@"x"] isKindOfClass:NSNumber.class] || ![point_[@"y"] isKindOfClass:NSNumber.class]) { Finish(nil); return; }
    hitTests_++;
    // CDP's native hit test uses document coordinates, while elementFromPoint
    // and candidate classification use viewport coordinates. Preserve point_
    // for classification and add the owning frame's scroll only at this boundary.
    Send(@"DOM.getNodeForLocation", @{@"x":@((int)([targetPoint_[@"x"] doubleValue]+hitScrollX_)), @"y":@((int)([targetPoint_[@"y"] doubleValue]+hitScrollY_)),
      @"ignorePointerEventsNone":@YES, @"includeUserAgentShadowDOM":@NO}, Hit);
  }
  int Raw(NSString *method, NSDictionary *params, NSString *session, bool track = false) {
    if (!browser_ || !browser_->IsValid()) return 0;
    static int nextMessageID = 1000000000;
    int identifier = ++nextMessageID;
    NSMutableDictionary *message = [@{@"id":@(identifier), @"method":method, @"params":params} mutableCopy];
    if (session.length) message[@"sessionId"] = session;
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    // Browser-side methods can reply synchronously. Publish the ID before
    // dispatch, and never overwrite a newer ID installed by a nested reply.
    if (track) messageID_ = identifier;
    if (!data || !browser_->GetHost()->SendDevToolsMessage(data.bytes, data.length)) return 0;
    return identifier;
  }
  void Send(NSString *method, NSDictionary *params, Stage stage) {
    if (++commands_ > 40) { Finish(nil); return; }
    stage_ = stage;
    sentAt_ = NSProcessInfo.processInfo.systemUptime;
    if (!Raw(method, params, session_, true) && completion_) Finish(nil);
  }
  void Finish(NSNumber *obstructed) {
    if (!completion_) return;
    if (obstructed && !validating_) {
      validating_ = true;
      pendingResult_ = obstructed;
      NSString *state = TLOverlayJSONString(scan_[@"viewState"]);
      if (!state || !mainContext_) { Finish(nil); return; }
      session_ = @"";
      // Compare to the first element to avoid inserting unescaped JSON as text.
      NSString *expression = [NSString stringWithFormat:@"JSON.stringify([innerWidth,innerHeight,scrollX,scrollY])===(%@)[0]", TLOverlayJSONString(@[state])];
      Send(@"Runtime.evaluate", @{@"contextId":mainContext_, @"expression":expression,
        @"returnByValue":@YES, @"silent":@YES, @"timeout":@25}, Validate);
      return;
    }
    auto callback = completion_;
    completion_ = nil;
    // Release every object group, then detach only sessions this request owns.
    for (NSString *session in sessions_) Raw(@"Runtime.releaseObjectGroup", @{@"objectGroup":group_}, session);
    for (NSString *session in [sessions_ reverseObjectEnumerator]) {
      if (session.length) Raw(@"Target.detachFromTarget", @{@"sessionId":session}, parents_[session] ?: @"");
    }
    NSMutableDictionary *result = [@{@"obstructed":obstructed ?: NSNull.null,
      @"costMS":@(costMS_ + hitTests_ * 1.0), @"cpuMS":@(costMS_),
      @"hitTests":@(hitTests_), @"hitRoundTripMS":@(hitRoundTripMS_),
      @"scanComplete":@([scan_[@"obstructed"] isKindOfClass:NSNumber.class]),
      @"fallbackFailed":@(!obstructed && hitTests_ > 0 && !validating_),
      @"maxSliceMS":@(maxSliceMS_), @"samples":scan_[@"samples"] ?: @0, @"cursor":scan_[@"cursor"] ?: @0} mutableCopy];
    NSDictionary *point = rootPoint_ ?: scan_[@"point"];
    if(failure_)result[@"failure"]=failure_;
    if(obstructed.boolValue && reason_)result[@"reason"]=reason_;
    if (obstructed.boolValue && point) {
      result[@"hint"] = @{@"x":point[@"x"], @"bottom":@([scan_[@"viewport"][@"height"] doubleValue]-[point[@"y"] doubleValue])};
    }
    if(obstructed.boolValue && [banner_ isKindOfClass:NSDictionary.class] && [banner_[@"coverage"] doubleValue]*bannerCoverage_>=0.65 && point){
      NSMutableDictionary *banner=[banner_ mutableCopy];
      double edge=[point[@"y"] doubleValue]+[banner[@"edgeDelta"] doubleValue]*bannerScale_;
      banner[@"bottom"]=@(MAX(1,[scan_[@"viewState"][1] doubleValue]-edge));
      banner[@"id"]=[NSString stringWithFormat:@"%@:%@",frameID_ ?: mainFrameID_,banner[@"id"]];
      [banner removeObjectForKey:@"edgeDelta"];[banner removeObjectForKey:@"coverage"];
      result[@"banner"]=banner;
    }
    registration_ = nullptr;
    browser_ = nullptr;
    dispatch_async(dispatch_get_main_queue(), ^{ callback(result); });
  }
  CefRefPtr<CefBrowser> browser_;
  CefRefPtr<CefRegistration> registration_;
  NSString *__strong source_, * __strong group_, * __strong session_, * __strong frameID_, * __strong childFrameID_;
  NSDictionary *__strong geometry_, * __strong scan_, * __strong point_, * __strong rootPoint_;
  NSDictionary *__strong failure_, *__strong banner_;
  NSString *__strong reason_;
  double bannerScale_=1,bannerCoverage_=1;
  NSString *__strong mainFrameID_, *__strong inspectedFrameID_;
  NSDictionary *__strong targetPoint_;
  NSArray *__strong points_;
  NSMutableDictionary *__strong contexts_, * __strong parents_;
  NSMutableArray *__strong sessions_;
  NSNumber *__strong backendID_, * __strong mainContext_, * __strong pendingResult_;
  bool validating_ = false;
  bool resetHitCoordinates_ = false;
  void (^__strong completion_)(NSDictionary *);
  Stage stage_ = FrameTree;
  NSUInteger pointIndex_ = 0, depth_ = 0, commands_ = 0, hitTests_ = 0;
  int messageID_ = 0;
  double hitScrollX_ = 0, hitScrollY_ = 0;
  double costMS_ = 0, maxSliceMS_ = 0, hitRoundTripMS_ = 0;
  NSTimeInterval sentAt_ = 0;
  IMPLEMENT_REFCOUNTING(TLOverlayRequest);
};

void TLChromiumProbeOverlay(CefRefPtr<CefBrowser> browser, NSString *source, NSDictionary *geometry,
                           void (^completion)(NSDictionary *)) {
  CefRefPtr<TLOverlayRequest> request = new TLOverlayRequest(browser, source, geometry, completion);
  request->Start();
}
