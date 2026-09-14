#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "TLDevelopmentMode.h"
#import "Database.h"
#import "AgentVMService.h"
#import "TLBrowserPreferences.h"
#import "TLCredentialStore.h"
#import "AppDelegate.h"

static void Check(BOOL value, NSString *message) {
  if (!value) { NSLog(@"FAIL: %@", message); exit(1); }
}
static NSString *developmentPath;
static NSString *instructions;
static NSAlert *shownAlert;
@interface NSBundle (DevelopmentTests)
- (id)developmentTestInfo:(NSString *)key;
- (NSString *)developmentTestIdentifier;
@end
@implementation NSBundle (DevelopmentTests)
- (id)developmentTestInfo:(NSString *)key {
  if (self == NSBundle.mainBundle) {
    if ([key isEqual:@"TLDevelopmentDataDirectory"]) return developmentPath;
    if ([key isEqual:@"TLDevelopmentTestInstructions"]) return instructions;
  }
  return [self developmentTestInfo:key];
}
- (NSString *)developmentTestIdentifier {
  return developmentPath && self == NSBundle.mainBundle ? @"com.talaria.chat.dev.fixture" : [self developmentTestIdentifier];
}
@end
@interface NSAlert (DevelopmentTests)
- (void)developmentTestSheet:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler;
@end
@implementation NSAlert (DevelopmentTests)
- (void)developmentTestSheet:(NSWindow *)window completionHandler:(void (^)(NSModalResponse))handler { shownAlert = self; }
@end
@interface TLAppDelegate (DevelopmentTests)
- (void)resetApp:(id)sender;
- (void)showTestInstructions:(id)sender;
@end

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    Method info = class_getInstanceMethod(NSBundle.class, @selector(objectForInfoDictionaryKey:));
    Method testInfo = class_getInstanceMethod(NSBundle.class, @selector(developmentTestInfo:));
    Method identifier = class_getInstanceMethod(NSBundle.class, @selector(bundleIdentifier));
    Method testIdentifier = class_getInstanceMethod(NSBundle.class, @selector(developmentTestIdentifier));
    Method sheet = class_getInstanceMethod(NSAlert.class, @selector(beginSheetModalForWindow:completionHandler:));
    Method testSheet = class_getInstanceMethod(NSAlert.class, @selector(developmentTestSheet:completionHandler:));
    method_exchangeImplementations(info, testInfo);
    method_exchangeImplementations(identifier, testIdentifier);
    method_exchangeImplementations(sheet, testSheet);
    Check(!TLDevelopmentDataURL() && [TLInstanceBundleIdentifier() isEqual:@"com.talaria.chat"], @"ordinary copies retain their single-instance identity");
    NSURL *normalDatabase = TLDatabase.defaultDatabaseURL;
    developmentPath = @"/private/tmp/Talaria Development Fixture/data";
    Check([TLDatabase.defaultDatabaseURL.path isEqual:[developmentPath stringByAppendingPathComponent:@"talaria.sqlite3"]], @"database uses the embedded absolute path");
    Check([TLAgentVMService.defaultAgentsDirectoryURL.path isEqual:[developmentPath stringByAppendingPathComponent:@"Agents"]], @"new VMs stay in the snapshot");
    Check([TLBrowserPreferences.profileURL.path isEqual:[developmentPath stringByAppendingPathComponent:@"WebKit"]], @"browser settings and download history stay in the snapshot");
    Check([TLInstanceBundleIdentifier() isEqual:@"com.talaria.chat.dev.fixture"], @"singleton handoff is scoped to this snapshot");
    TLKeychainCredentialStore *credentials = [TLKeychainCredentialStore new];
    Check([[credentials valueForKey:@"service"] isEqual:@"com.talaria.chat.dev.fixture.credentials"], @"credential operations cannot use the production helper or keychain service");
    // These checks never access a credential, database, VM, or shared reset marker.
    TLAppDelegate *delegate = [TLAppDelegate new];
    [delegate resetApp:nil];
    Check([shownAlert.messageText isEqual:@"Development copy"], @"development reset exits before shared reset operations");
    instructions = @"Open two tabs.\nCheck a quoted value: \"hello\".";
    shownAlert = nil;
    [delegate showTestInstructions:nil];
    Check([shownAlert.informativeText isEqual:instructions], @"instructions are displayed literally");
    developmentPath = nil;
    Check([TLDatabase.defaultDatabaseURL isEqual:normalDatabase], @"normal database location is unchanged");
    method_exchangeImplementations(sheet, testSheet);
    method_exchangeImplementations(identifier, testIdentifier);
    method_exchangeImplementations(info, testInfo);
    NSLog(@"Development mode tests passed");
  }
  return 0;
}
