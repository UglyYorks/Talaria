#import "ChromiumContextMenu.h"
#include "include/cef_client.h"
#import "ChromiumRunLoop.h"
#import "ChromiumImageActions.h"
#import "design_system/TLLinkServicesView.h"

@interface TLChromiumContextMenuSelection : NSObject
@property(nonatomic) NSInteger command;
@property(nonatomic) cef_event_flags_t flags;
- (void)selectItem:(NSMenuItem *)item;
@end
@implementation TLChromiumContextMenuSelection
- (instancetype)init { if ((self=[super init])) _command=-1; return self; }
- (void)selectItem:(NSMenuItem *)item {
  self.command=item.tag;
  NSEventModifierFlags modifiers=NSEvent.modifierFlags;
  int flags=EVENTFLAG_NONE;
  if(modifiers & NSEventModifierFlagShift)flags|=EVENTFLAG_SHIFT_DOWN;
  if(modifiers & NSEventModifierFlagControl)flags|=EVENTFLAG_CONTROL_DOWN;
  if(modifiers & NSEventModifierFlagOption)flags|=EVENTFLAG_ALT_DOWN;
  if(modifiers & NSEventModifierFlagCommand)flags|=EVENTFLAG_COMMAND_DOWN;
  self.flags=static_cast<cef_event_flags_t>(flags);
}
@end

static NSMenu *TLChromiumNativeMenu(CefRefPtr<CefMenuModel> model, TLChromiumContextMenuSelection *selection) {
  NSMenu *menu=[NSMenu new];menu.autoenablesItems=NO;
  for(size_t index=0;index<model->GetCount();index++) {
    if(model->GetTypeAt(index)==MENUITEMTYPE_SEPARATOR) { [menu addItem:NSMenuItem.separatorItem];continue; }
    NSString *label=[NSString stringWithUTF8String:model->GetLabelAt(index).ToString().c_str()] ?: @"";
    NSMutableString *title=[NSMutableString string];
    // Chromium labels contain Windows-style accelerator markers. Preserve &&.
    for(NSUInteger offset=0;offset<label.length;offset++) {
      if([label characterAtIndex:offset]=='&') {
        if(offset+1>=label.length || [label characterAtIndex:offset+1]!='&')continue;
        offset++;
      }
      [title appendString:[label substringWithRange:NSMakeRange(offset,1)]];
    }
    NSMenuItem *item=[[NSMenuItem alloc] initWithTitle:title action:@selector(selectItem:) keyEquivalent:@""];
    item.target=selection;item.tag=model->GetCommandIdAt(index);
    item.enabled=model->IsEnabledAt(index);item.hidden=!model->IsVisibleAt(index);
    item.state=model->IsCheckedAt(index) ? NSControlStateValueOn : NSControlStateValueOff;
    if(item.tag==MENU_ID_PRINT)item.image=[NSImage imageWithSystemSymbolName:@"printer" accessibilityDescription:nil];
    if(item.tag==TLChromiumImageCommandFirst+TLBrowserImageShare)item.image=[NSImage imageWithSystemSymbolName:@"square.and.arrow.up" accessibilityDescription:nil];
    if(auto submenu=model->GetSubMenuAt(index)) { item.submenu=TLChromiumNativeMenu(submenu,selection);item.action=nil; }
    [menu addItem:item];
  }
  return menu;
}

void TLChromiumShowContextMenu(CefRefPtr<CefBrowser> browser, CefRefPtr<CefMenuModel> model,
                              CefPoint location, CefRefPtr<CefRunContextMenuCallback> callback) {
  TLChromiumContextMenuSelection *selection=[TLChromiumContextMenuSelection new];
  NSMenu *menu=TLChromiumNativeMenu(model,selection);
  TLChromiumDeferToMainRunLoop(^{
    if(!browser->IsValid()) { callback->Cancel();return; }
    NSView *view=(__bridge NSView *)browser->GetHost()->GetWindowHandle();
    if(!view.window.isVisible) { callback->Cancel();return; }
    NSPoint point=NSMakePoint(location.x,view.isFlipped ? location.y : NSHeight(view.bounds)-location.y);
    [menu popUpMenuPositioningItem:nil atLocation:point inView:view];
    if(selection.command>=0 && browser->IsValid())callback->Continue((int)selection.command,selection.flags);
    else callback->Cancel();
  });
}

void TLChromiumShowLinkContextMenu(CefRefPtr<CefBrowser> browser, CefRefPtr<CefMenuModel> imageModel,
  NSURL *URL, BOOL canSplit, CefPoint location, CefRefPtr<CefRunContextMenuCallback> callback,
  TLBrowserLinkOpenHandler open) {
  TLChromiumContextMenuSelection *selection = [TLChromiumContextMenuSelection new];
  NSMenu *imageMenu = imageModel ? TLChromiumNativeMenu(imageModel, selection) : nil;
  TLChromiumDeferToMainRunLoop(^{
    if (!browser->IsValid()) { callback->Cancel(); return; }
    NSView *view = (__bridge NSView *)browser->GetHost()->GetWindowHandle();
    NSWindow *window = view.window;
    if (!window.isVisible) { callback->Cancel(); return; }
    NSPoint point = NSMakePoint(location.x, view.isFlipped ? location.y : NSHeight(view.bounds) - location.y);
    NSMenu *menu = [TLBrowserLinkActions menuForURL:URL canSplit:canSplit view:view point:point open:open inspect:^{
      if (!browser->IsValid()) return;
      CefWindowInfo info; CefBrowserSettings settings;
      browser->GetHost()->ShowDevTools(info, nullptr, settings, location);
    } imageMenu:imageMenu];
    // Services reads this specific link from a temporary requestor, even when
    // different text is selected on the web page. The general clipboard is untouched.
    TLLinkServicesView *requestor = [[TLLinkServicesView alloc] initWithFrame:NSZeroRect]; requestor.URL = URL;
    NSResponder *previousResponder = window.firstResponder;
    NSMenu *previousServices = NSApp.servicesMenu;
    if (!imageMenu) {
      [view addSubview:requestor]; [window makeFirstResponder:requestor];
      [NSApp registerServicesMenuSendTypes:@[NSPasteboardTypeString, NSPasteboardTypeURL] returnTypes:@[]];
      NSApp.servicesMenu = menu.itemArray.lastObject.submenu;
      NSUpdateDynamicServices();
    }
    [menu popUpMenuPositioningItem:nil atLocation:point inView:view];
    if (!imageMenu) NSApp.servicesMenu = previousServices;
    if (window.firstResponder == requestor) [window makeFirstResponder:previousResponder];
    [requestor removeFromSuperview];
    if (selection.command >= 0 && browser->IsValid()) callback->Continue((int)selection.command, selection.flags);
    else callback->Cancel();
  });
}
