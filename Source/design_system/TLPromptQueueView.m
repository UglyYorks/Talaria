#import "TLPromptQueueView.h"
#import "TLGlassButton.h"
#import "TLThemedButton.h"
#import "UIComponents.h"

@interface TLPromptQueueView ()
@property (nonatomic) CGFloat preferredHeight;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;
@property (nonatomic, strong) NSView *body;
@property (nonatomic, copy) NSArray *renderSignature;
@end

@implementation TLPromptQueueView
- (instancetype)initWithFrame:(NSRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.heightConstraint = [self.heightAnchor constraintEqualToConstant:0];
    self.heightConstraint.active = YES;
    self.hidden = YES;
  }
  return self;
}
- (NSTextField *)label:(NSString *)text palette:(TLThemePalette *)palette {
  NSTextField *label = [NSTextField labelWithString:text];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  label.font = palette.smallFont;
  label.textColor = palette.textMuted;
  label.lineBreakMode = NSLineBreakByTruncatingTail;
  [label setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
  return label;
}
- (TLHoverIconButton *)icon:(NSString *)symbol label:(NSString *)label index:(NSUInteger)index action:(SEL)action palette:(TLThemePalette *)palette {
  TLHoverIconButton *button = [TLHoverIconButton new];
  button.translatesAutoresizingMaskIntoConstraints = NO;
  button.palette = palette;
  button.bordered = NO;
  button.hoverSurfaceOnly = YES;
  button.idleContentTintColor = palette.textMuted;
  button.hoverContentTintColor = palette.appText;
  button.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:label];
  button.imagePosition = NSImageOnly;
  button.toolTip = label;
  [button setAccessibilityLabel:label];
  button.tag = index;
  button.target = self;
  button.action = action;
  [button.widthAnchor constraintEqualToConstant:palette.composerButtonHeight - palette.space6].active = YES;
  [button.heightAnchor constraintEqualToAnchor:button.widthAnchor].active = YES;
  return button;
}
- (void)updatePrompts:(NSArray<TLQueuedPrompt *> *)prompts editing:(TLQueuedPrompt *)editing
              paused:(BOOL)paused canResume:(BOOL)canResume canSendNow:(BOOL)canSendNow palette:(TLThemePalette *)palette {
  NSMutableArray *signature = [NSMutableArray arrayWithArray:@[palette, @(paused), @(canResume), @(canSendNow), editing ?: NSNull.null]];
  for (TLQueuedPrompt *prompt in prompts) [signature addObject:@[prompt.text, prompt.attachmentURLs]];
  if ([self.renderSignature isEqual:signature]) return;
  self.renderSignature = signature;
  [self.body removeFromSuperview];
  self.hidden = prompts.count == 0;
  self.layer.backgroundColor = palette.composerSurface.CGColor;
  self.layer.borderColor = palette.composerBorder.CGColor;
  self.layer.borderWidth = palette.borderWidth;
  self.layer.cornerRadius = palette.radiusMedium;
  CGFloat rowHeight = palette.composerButtonHeight;
  CGFloat headerHeight = rowHeight;
  self.preferredHeight = prompts.count ? headerHeight + MIN(prompts.count, 3) * rowHeight + palette.space3 : 0;
  self.heightConstraint.constant = self.preferredHeight;
  if (!prompts.count) return;
  NSView *body = [NSView new];
  body.translatesAutoresizingMaskIntoConstraints = NO;
  self.body = body;
  [self addSubview:body];
  [NSLayoutConstraint activateConstraints:@[
    [body.leadingAnchor constraintEqualToAnchor:self.leadingAnchor], [body.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    [body.topAnchor constraintEqualToAnchor:self.topAnchor], [body.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]]];
  NSString *status = editing ? @"Editing" : paused ? @"Paused" : @"Up next";
  NSTextField *title = [self label:[NSString stringWithFormat:@"%@ · %lu", status, (unsigned long)prompts.count] palette:palette];
  [body addSubview:title];
  [NSLayoutConstraint activateConstraints:@[
    [title.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:palette.space6],
    [title.centerYAnchor constraintEqualToAnchor:body.topAnchor constant:headerHeight / 2]]];
  if (editing || paused) {
    TLThemedButton *action = [TLThemedButton buttonWithTitle:editing ? @"Cancel edit" : @"Resume" target:self
      action:editing ? @selector(cancelEdit:) : @selector(resume:)];
    action.translatesAutoresizingMaskIntoConstraints = NO;
    action.palette = palette;
    action.enabled = editing || canResume;
    [body addSubview:action];
    [NSLayoutConstraint activateConstraints:@[
      [action.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-palette.space5],
      [action.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
      [title.trailingAnchor constraintLessThanOrEqualToAnchor:action.leadingAnchor constant:-palette.space3]]];
  } else {
    [title.trailingAnchor constraintLessThanOrEqualToAnchor:body.trailingAnchor constant:-palette.space6].active = YES;
  }
  NSScrollView *scroll = [NSScrollView new];
  scroll.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.drawsBackground = NO;
  scroll.hasVerticalScroller = YES;
  scroll.autohidesScrollers = YES;
  [body addSubview:scroll];
  [NSLayoutConstraint activateConstraints:@[
    [scroll.leadingAnchor constraintEqualToAnchor:body.leadingAnchor], [scroll.trailingAnchor constraintEqualToAnchor:body.trailingAnchor],
    [scroll.topAnchor constraintEqualToAnchor:body.topAnchor constant:headerHeight],
    [scroll.bottomAnchor constraintEqualToAnchor:body.bottomAnchor constant:-palette.space3]]];
  TLFlippedView *document = [TLFlippedView new];
  document.translatesAutoresizingMaskIntoConstraints = NO;
  scroll.documentView = document;
  [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor].active = YES;
  [document.heightAnchor constraintEqualToConstant:prompts.count * rowHeight].active = YES;
  [prompts enumerateObjectsUsingBlock:^(TLQueuedPrompt *prompt, NSUInteger index, BOOL *stop) {
    NSString *text = prompt.text.length ? prompt.text : @"Attached files";
    if (prompt.attachmentURLs.count) text = [text stringByAppendingFormat:@"  · %lu file%@", (unsigned long)prompt.attachmentURLs.count, prompt.attachmentURLs.count == 1 ? @"" : @"s"];
    NSTextField *label = [self label:[NSString stringWithFormat:@"%lu. %@", (unsigned long)index + 1, text] palette:palette];
    label.textColor = palette.appText;
    label.toolTip = text;
    TLHoverIconButton *sendNow = [self icon:@"arrow.up" label:@"Send now" index:index action:@selector(sendNow:) palette:palette];
    sendNow.enabled = canSendNow && !editing;
    TLHoverIconButton *edit = [self icon:@"pencil" label:@"Edit queued prompt" index:index action:@selector(edit:) palette:palette];
    TLHoverIconButton *remove = [self icon:@"xmark" label:@"Remove queued prompt" index:index action:@selector(remove:) palette:palette];
    edit.enabled = !editing;
    [document addSubview:label]; [document addSubview:sendNow]; [document addSubview:edit]; [document addSubview:remove];
    [NSLayoutConstraint activateConstraints:@[
      [label.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:palette.space6],
      [label.centerYAnchor constraintEqualToAnchor:document.topAnchor constant:(index + 0.5) * rowHeight],
      [label.trailingAnchor constraintEqualToAnchor:sendNow.leadingAnchor constant:-palette.space3],
      [sendNow.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
      [sendNow.trailingAnchor constraintEqualToAnchor:edit.leadingAnchor constant:-palette.space3],
      [edit.centerYAnchor constraintEqualToAnchor:label.centerYAnchor], [remove.centerYAnchor constraintEqualToAnchor:label.centerYAnchor],
      [edit.trailingAnchor constraintEqualToAnchor:remove.leadingAnchor constant:-palette.space3],
      [remove.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-palette.space5]]];
  }];
}
- (void)sendNow:(NSButton *)sender { if (sender.enabled && self.sendNowHandler) self.sendNowHandler(sender.tag); }
- (void)edit:(NSButton *)sender { if (self.editHandler) self.editHandler(sender.tag); }
- (void)remove:(NSButton *)sender { if (self.removeHandler) self.removeHandler(sender.tag); }
- (void)resume:(id)sender { if (self.resumeHandler) self.resumeHandler(); }
- (void)cancelEdit:(id)sender { if (self.cancelEditHandler) self.cancelEditHandler(); }
@end
