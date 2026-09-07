#import "TLApplicationPreferences.h"
#import "TLGlobalShortcut.h"

NSNotificationName const TLApplicationPreferencesDidChangeNotification = @"TLApplicationPreferencesDidChange";
static NSString * const TLNotchEnabledKey = @"application.notchEnabled";
static NSString * const TLQuickInputShortcutKey = @"application.quickInputShortcut";

// The adapter keeps OS state authoritative and lets tests avoid changing login items.
@interface TLMainAppLoginItem : NSObject <TLLoginItemService>
@end
@implementation TLMainAppLoginItem
- (SMAppServiceStatus)status { return SMAppService.mainAppService.status; }
- (BOOL)registerAndReturnError:(NSError **)error { return [SMAppService.mainAppService registerAndReturnError:error]; }
- (BOOL)unregisterAndReturnError:(NSError **)error { return [SMAppService.mainAppService unregisterAndReturnError:error]; }
@end

@interface TLApplicationPreferences ()
@property NSUserDefaults *defaults;
@property id<TLLoginItemService> loginItem;
@property id<TLGlobalShortcutRegistration> shortcutRegistration;
@property (nonatomic, copy, readwrite) NSDictionary *quickInputShortcut;
@property (nonatomic, copy, readwrite) NSString *shortcutError;
@end
@implementation TLApplicationPreferences
+ (TLApplicationPreferences *)sharedPreferences {
  static TLApplicationPreferences *preferences;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    preferences = [[self alloc] initWithDefaults:NSUserDefaults.standardUserDefaults
      loginItem:[[TLMainAppLoginItem alloc] init] shortcutRegistration:[[TLGlobalShortcut alloc] init]];
  });
  return preferences;
}
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults loginItem:(id<TLLoginItemService>)loginItem
           shortcutRegistration:(id<TLGlobalShortcutRegistration>)registration {
  if (!(self = [super init])) return nil;
  _defaults = defaults; _loginItem = loginItem; _shortcutRegistration = registration;
  __weak typeof(self) weakSelf = self;
  registration.handler = ^{ if (weakSelf.quickInputHandler) weakSelf.quickInputHandler(); };
  NSDictionary *saved = [defaults dictionaryForKey:TLQuickInputShortcutKey];
  if (saved) {
    NSError *error = nil;
    if ([self validShortcut:saved error:&error]) {
      _quickInputShortcut = [saved copy];
      [registration registerShortcut:saved error:&error];
    }
    _shortcutError = error.localizedDescription;
  }
  return self;
}
- (void)setShortcutRecording:(BOOL)shortcutRecording {
  if (_shortcutRecording == shortcutRecording) return;
  _shortcutRecording = shortcutRecording;
  NSError *error = nil;
  [self.shortcutRegistration registerShortcut:shortcutRecording ? nil : self.quickInputShortcut error:&error];
  if (!shortcutRecording) { self.shortcutError = error.localizedDescription; [self notifyChanged]; }
}
- (void)notifyChanged { [NSNotificationCenter.defaultCenter postNotificationName:TLApplicationPreferencesDidChangeNotification object:self]; }
- (BOOL)notchEnabled { return [self.defaults objectForKey:TLNotchEnabledKey] ? [self.defaults boolForKey:TLNotchEnabledKey] : YES; }
- (void)setNotchEnabled:(BOOL)enabled {
  if (self.notchEnabled == enabled) return;
  [self.defaults setBool:enabled forKey:TLNotchEnabledKey]; [self notifyChanged];
}
- (SMAppServiceStatus)loginItemStatus { return self.loginItem.status; }
- (BOOL)setLaunchAtLogin:(BOOL)enabled error:(NSError **)error {
  SMAppServiceStatus status = self.loginItemStatus;
  BOOL registered = status == SMAppServiceStatusEnabled || status == SMAppServiceStatusRequiresApproval;
  if (registered == enabled) return YES;
  BOOL saved = enabled ? [self.loginItem registerAndReturnError:error] : [self.loginItem unregisterAndReturnError:error];
  [self notifyChanged];
  return saved;
}
- (BOOL)validShortcut:(NSDictionary *)shortcut error:(NSError **)error {
  if (!shortcut) return YES;
  NSEventModifierFlags allowed = NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;
  NSNumber *code = shortcut[@"keyCode"], *modifiers = shortcut[@"modifiers"];
  NSString *label = shortcut[@"label"];
  BOOL valid = [code isKindOfClass:NSNumber.class] && code.integerValue >= 0 && code.integerValue <= 127 &&
    [modifiers isKindOfClass:NSNumber.class] && !(modifiers.unsignedIntegerValue & ~allowed) &&
    (modifiers.unsignedIntegerValue & (allowed & ~NSEventModifierFlagShift)) &&
    [label isKindOfClass:NSString.class] && label.length > 0 && label.length <= 24;
  if (!valid && error) *error = [NSError errorWithDomain:@"Talaria.Application" code:1
    userInfo:@{NSLocalizedDescriptionKey:@"Use a key together with Command, Control, or Option."}];
  return valid;
}
- (BOOL)setQuickInputShortcut:(NSDictionary *)shortcut error:(NSError **)error {
  if (![self validShortcut:shortcut error:error]) return NO;
  if ([self.quickInputShortcut isEqual:shortcut] && !self.shortcutError) return YES;
  if (![self.shortcutRegistration registerShortcut:shortcut error:error]) return NO;
  self.quickInputShortcut = shortcut; self.shortcutError = nil;
  if (shortcut) [self.defaults setObject:shortcut forKey:TLQuickInputShortcutKey];
  else [self.defaults removeObjectForKey:TLQuickInputShortcutKey];
  [self notifyChanged]; return YES;
}
@end
