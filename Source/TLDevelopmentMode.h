#import <Foundation/Foundation.h>

// The desktop launcher embeds the absolute data root in its uniquely identified
// bundle. Finder/reopen launches therefore retain isolation without environment
// variables or dependence on LaunchServices' working directory.
static inline NSURL *TLDevelopmentDataURL(void) {
  NSString *path = [NSBundle.mainBundle objectForInfoDictionaryKey:@"TLDevelopmentDataDirectory"];
  return path.isAbsolutePath ? [NSURL fileURLWithPath:path isDirectory:YES] : nil;
}
static inline NSString *TLInstanceBundleIdentifier(void) {
  return TLDevelopmentDataURL() ? NSBundle.mainBundle.bundleIdentifier : @"com.talaria.chat";
}
