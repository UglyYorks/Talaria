#import <AppKit/AppKit.h>
#import "TLChatSettingsController.h"
#import "design_system/TLModelDropdown.h"
#import "design_system/TLThinkingSlider.h"
#import "Database.h"
#import "AssistantTurnRunner.h"

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
@interface TLThinkingCatalogue : NSObject
@property (nonatomic, copy) TLAgentModelCatalogueHandler completion;
@property (nonatomic) NSInteger agentID;
@end
@implementation TLThinkingCatalogue
- (void)fetchModelCatalogueWithAgentID:(NSInteger)agentID token:(NSString *)token completion:(TLAgentModelCatalogueHandler)completion {
  self.agentID = agentID; self.completion = completion;
}
@end

@interface TLThinkingTurnStream : NSObject <TLAssistantTurnStreaming>
@property (nonatomic, copy) NSString *effort;
@property (nonatomic, copy) NSString *sessionID;
@property (nonatomic) NSInteger agentID;
@end
@implementation TLThinkingTurnStream
- (void)cancelChatWithRequestID:(NSString *)requestID {}
- (void)streamChatWithDefaultAgentRequestID:(NSString *)requestID sessionID:(NSString *)sessionID token:(NSString *)token
  model:(NSString *)model messages:(NSArray<TLChatMessage *> *)messages delta:(TLAgentStreamDeltaHandler)delta
  completion:(TLAgentStreamCompletionHandler)completion { Check(NO, @"thinking must not be dropped by the legacy path"); }
- (void)streamChatWithAgentID:(NSInteger)agentID requestID:(NSString *)requestID sessionID:(NSString *)sessionID
  token:(NSString *)token model:(NSString *)model reasoningEffort:(NSString *)effort messages:(NSArray<TLChatMessage *> *)messages
  delta:(TLAgentStreamDeltaHandler)delta completion:(TLAgentStreamCompletionHandler)completion {
  self.effort = effort; self.sessionID = sessionID; self.agentID = agentID;
  delta(requestID, TLAgentStreamDeltaKindContent, @"Answer");
  completion(nil);
}
@end

static TLAgentModel *Model(NSString *name, NSArray *levels, NSString *preferred) {
  TLAgentModel *model = [TLAgentModel new];
  model.name = name; model.modelID = [@"test::" stringByAppendingString:name];
  model.providerID = @"test"; model.modelDescription = @"Test provider";
  model.thinkingLevels = levels; model.defaultThinkingLevel = preferred;
  return model;
}
static void Act(NSControl *control) { [NSApp sendAction:control.action to:control.target from:control]; }
static BOOL HasColor(NSBitmapImageRep *bitmap, NSColor *expected) {
  NSColor *rgb = [expected colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
  for (NSInteger y = 0; y < bitmap.pixelsHigh; y++) for (NSInteger x = 0; x < bitmap.pixelsWide; x++) {
    NSColor *pixel = [[bitmap colorAtX:x y:y] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
    if (pixel.alphaComponent > .9 && fabs(pixel.redComponent - rgb.redComponent) < .03 &&
        fabs(pixel.greenComponent - rgb.greenComponent) < .03 && fabs(pixel.blueComponent - rgb.blueComponent) < .03) return YES;
  }
  return NO;
}
static NSBitmapImageRep *Render(NSView *view) {
  [view layoutSubtreeIfNeeded];
  NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
  [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
  return bitmap;
}
static NSBitmapImageRep *RenderButton(id control) {
  NSControl *button = control;
  TLThemePalette *palette = [control palette];
  NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
    pixelsWide:ceil(NSWidth(button.bounds)) pixelsHigh:ceil(NSHeight(button.bounds)) bitsPerSample:8 samplesPerPixel:4
    hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
  [NSGraphicsContext saveGraphicsState];
  NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
  [palette.tabBackground setFill]; NSRectFill(button.bounds);
  [button.cell drawWithFrame:button.bounds inView:button];
  [NSGraphicsContext restoreGraphicsState];
  return bitmap;
}
static void TestPopover(void) {
  TLThinkingCatalogue *catalogue = [TLThinkingCatalogue new];
  TLChatSettingsController *controller = [[TLChatSettingsController alloc] initWithModel:@"test::Reply model"
    supportingModel:@"test::Small model" reasoningEffort:@"high" agentID:42 token:@"test"
    orchestrator:(id)catalogue palette:[TLThemePalette paletteForPreference:TLThemePreferenceLight]];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 500)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  window.contentView = controller.view;
  TLModelDropdown *models = [controller valueForKey:@"modelDropdown"];
  TLModelDropdown *supporting = [controller valueForKey:@"supportingDropdown"];
  TLThinkingSlider *slider = [controller valueForKey:@"thinkingSlider"];
  TLThemedButton *refresh = [controller valueForKey:@"refreshButton"], *save = [controller valueForKey:@"saveButton"];
  TLThemedButton *cancel = [controller valueForKey:@"cancelButton"];
  Act(refresh);
  Check(catalogue.agentID == 42 && !models.enabled && !slider.enabled && !save.enabled, @"loading is pinned to the chat's agent and disables settings");
  catalogue.completion(nil, [NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Offline"}]);
  Check(refresh.enabled && !save.enabled, @"failed discovery permits retry");
  Act(refresh);
  TLAgentModel *reply = Model(@"Reply model", @[@"none", @"minimal", @"low", @"medium", @"high", @"xhigh", @"max", @"ultra"], @"medium");
  TLAgentModel *small = Model(@"Small model", @[@"high"], @"high");
  TLAgentModel *unknown = Model(@"Unknown model", @[], @"");
  catalogue.completion(@[reply, small, unknown], nil);
  Check(save.enabled && slider.enabled && slider.numberOfTickMarks == 5, @"more than five capabilities produce five real stops");
  NSArray *stops = [controller valueForKey:@"sliderLevels"];
  Check([stops containsObject:@"high"] && [stops.firstObject isEqual:@"none"] && [stops.lastObject isEqual:@"ultra"], @"range endpoints and saved selection survive reduction");
  slider.integerValue = slider.numberOfTickMarks - 1; Act(slider);
  Check([[controller valueForKey:@"reasoningEffort"] isEqual:@"ultra"], @"slider selects a supported value");
  models.selectedModelID = small.modelID; models.selectionHandler();
  Check(!slider.enabled && slider.numberOfTickMarks == 1 && [[controller valueForKey:@"reasoningEffort"] isEqual:@"high"], @"one thinking level disables the slider");
  models.selectedModelID = unknown.modelID; models.selectionHandler();
  Check(!slider.enabled && slider.numberOfTickMarks == 0, @"missing capabilities do not invent thinking levels");
  models.selectedModelID = reply.modelID; models.selectionHandler();
  Check([[controller valueForKey:@"reasoningEffort"] isEqual:@"ultra"], @"switching models restores the model's draft thinking selection");
  __block void (^finished)(NSError *);
  __block NSString *selectedEffort;
  controller.selectionHandler = ^(NSString *largeID, NSString *smallID, NSString *effort, void (^completion)(NSError *)) {
    Check([largeID isEqual:reply.modelID] && [smallID isEqual:small.modelID], @"save carries both provider-qualified models");
    selectedEffort = effort; finished = completion;
  };
  for (NSNumber *theme in @[@(TLThemePreferenceLight), @(TLThemePreferenceDark)]) {
    TLThemePalette *p = [TLThemePalette paletteForPreference:theme.integerValue];
    [controller applyPalette:p];
    [window setContentSize:controller.preferredContentSize];
    NSBitmapImageRep *bitmap = Render(controller.view);
    [[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
      writeToFile:[NSString stringWithFormat:@"build/chat-settings-%@.png", theme] atomically:YES];
    Check(NSWidth(models.frame) > 200 && NSWidth(models.frame) <= NSWidth(controller.view.bounds), @"dropdown fits compact popover");
    Check(NSMinY(save.frame) >= 0 && NSHeight(controller.view.bounds) < 550, @"actions fit the popover height");
    for (TLThemedButton *button in @[models, supporting, save, cancel, refresh]) {
      for (NSNumber *pressed in @[@NO, @YES]) {
        [button highlight:pressed.boolValue];
        NSBitmapImageRep *render = RenderButton(button);
        Check(HasColor(render, button.primary ? p.primaryActionText : p.secondaryActionText), [NSString stringWithFormat:@"rendered foreground: %@ theme %@ pressed %@", button.title, theme, pressed]);
        if (!pressed.boolValue) Check(HasColor(render, button.primary ? p.primaryActionSurface : p.secondaryActionSurface), @"rendered dropdown/action surface follows theme");
      }
      [button highlight:NO];
      button.enabled = NO;
      Check(Render(button) != nil, @"disabled control renders");
      button.enabled = YES;
    }
    Check(HasColor(RenderButton(slider), p.primaryActionSurface), @"slider renders a visible themed thumb");
  }
  Act(save);
  Check(finished && !save.enabled && !cancel.enabled && !models.enabled && !slider.enabled, @"saving waits for acknowledgement and prevents edits");
  finished([NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Could not apply"}]);
  Check(save.enabled && slider.enabled && ![[controller valueForKey:@"dismissed"] boolValue], @"runtime failure keeps drafts for retry");
  Act(save); finished(nil);
  Check([selectedEffort isEqual:@"ultra"] && [[controller valueForKey:@"dismissed"] boolValue], @"successful save closes settings");
  [controller setValue:@NO forKey:@"dismissed"];
  Act(refresh); Act(cancel);
  catalogue.completion(@[], nil);
  Check(models.models.count == 3, @"dismissed popover ignores late discovery");
  [window close];
}
static void TestAnchoredPopover(void) {
  TLThinkingCatalogue *catalogue = [TLThinkingCatalogue new];
  TLChatSettingsController *controller = [[TLChatSettingsController alloc] initWithModel:@"test::Reply model"
    supportingModel:@"test::Small model" reasoningEffort:@"medium" agentID:7 token:@"test"
    orchestrator:(id)catalogue palette:[TLThemePalette paletteForPreference:TLThemePreferenceDark]];
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 200, 500)
    styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
  window.releasedWhenClosed = NO;
  NSButton *anchor = [[NSButton alloc] initWithFrame:NSMakeRect(130, 12, 32, 32)];
  [window.contentView addSubview:anchor];
  [window orderFront:nil];
  __block BOOL closed = NO;
  controller.closeHandler = ^{ closed = YES; };
  [controller presentRelativeToView:anchor];
  catalogue.completion(@[Model(@"Reply model", @[@"low", @"medium", @"high"], @"medium"), Model(@"Small model", @[@"none"], @"none")], nil);
  Check(controller.popover.shown && !window.attachedSheet && NSWidth(window.frame) == 200,
    @"settings is an anchored popover and does not expand a narrow main window");
  [controller.popover close];
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
  while (!closed && deadline.timeIntervalSinceNow > 0)
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  Check(closed, @"closing settings releases quick-input focus ownership");
  [window close];
}
static void TestStorage(void) {
  NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
  NSURL *url = [directory URLByAppendingPathComponent:@"thinking.sqlite"];
  NSError *error = nil;
  TLDatabase *database = [[TLDatabase alloc] initWithURL:url error:&error];
  Check(database && !error, @"database opens");
  TLChatRecord *a = [database createChatWithModel:@"test::large" supportingModel:@"test::small" reasoningEffort:@"high" error:&error];
  TLChatRecord *b = [database createChatWithModel:@"test::large" supportingModel:@"test::small" error:&error];
  Check(a && [a.reasoningEffort isEqual:@"high"] && b.reasoningEffort.length == 0, @"draft effort is stored atomically without changing another chat");
  Check([database saveChatSettingsForChatID:a.chatID model:@"test::next" supportingModel:@"test::small" reasoningEffort:@"low" error:&error], @"models and effort save together");
  Check([database saveModelsForChatID:a.chatID model:@"test::next" supportingModel:@"test::other" error:&error], @"legacy model changes preserve thinking");
  database = nil;
  database = [[TLDatabase alloc] initWithURL:url error:&error];
  TLChatRecord *restored = [database chatWithID:a.chatID error:&error];
  Check([restored.reasoningEffort isEqual:@"low"] && [restored.supportingModel isEqual:@"test::other"] &&
    [restored.hermesSessionID isEqual:a.hermesSessionID], @"reopening preserves the chat's selection and session identity");
  Check([[(TLChatRecord *)[restored copy] reasoningEffort] isEqual:@"low"], @"copy retains thinking settings");
  Check(![database saveChatSettingsForChatID:a.chatID model:@"" supportingModel:@"bad" reasoningEffort:@"max" error:&error], @"invalid save fails");
  Check([[database chatWithID:a.chatID error:nil].reasoningEffort isEqual:@"low"], @"failed save preserves thinking");
  Check([database chatWithID:b.chatID error:nil].reasoningEffort.length == 0, @"other chat stays unchanged");
  TLThinkingTurnStream *stream = [TLThinkingTurnStream new];
  TLAssistantTurnRunner *runner = [[TLAssistantTurnRunner alloc] initWithMessageStore:(id)database streaming:stream];
  restored.sourceAgentID = 42; restored.continuationSessionID = @"continued-session";
  NSMutableArray *messages = [NSMutableArray array];
  Check([runner startTurnWithChat:restored token:@"test" model:restored.model messages:messages nextPrompt:@"Hello"
    updateHandler:nil completionHandler:nil error:nil], @"turn starts with stored settings");
  Check([stream.effort isEqual:@"low"] && stream.agentID == 42 && [stream.sessionID isEqual:@"continued-session"],
    @"turn forwards thinking to the owning agent and continuation session");
  database = nil;
  [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
}
static void TestParsing(void) {
  NSDictionary *catalogue = @{@"providers": @[@{@"slug":@"test", @"models":@[@"reply"]}],
    @"thinking": @{@"test::reply": @{@"levels":@[@"low", @"high", @"low", @42], @"default":@"high"}}};
  NSError *error = nil;
  TLAgentModel *model = TLParseHermesModelOptions([NSJSONSerialization dataWithJSONObject:catalogue options:0 error:nil], &error).firstObject;
  Check(!error && [model.thinkingLevels isEqual:@[@"low", @"high"]] && [model.defaultThinkingLevel isEqual:@"high"], @"parse valid thinking metadata and discard malformed values");
  Check([((TLAgentModel *)model.copy).thinkingLevels isEqual:model.thinkingLevels], @"model copies retain capabilities");
  for (NSUInteger n = 1; n < 12; n++) {
    NSMutableArray *levels = [NSMutableArray array];
    for (NSUInteger i = 0; i < n; i++) [levels addObject:[@(i) stringValue]];
    for (NSString *selected in levels) {
      NSArray *stops = TLThinkingSliderLevels(levels, selected);
      Check(stops.count == MIN(n, 5) && [stops containsObject:selected] && [stops.firstObject isEqual:levels.firstObject] &&
        [stops.lastObject isEqual:levels.lastObject], @"every saved effort is reachable among at most five ordered stops");
    }
  }
}
int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TestParsing(); TestStorage(); TestPopover(); TestAnchoredPopover();
    NSLog(@"Chat settings tests passed");
  }
  return 0;
}
