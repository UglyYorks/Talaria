#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLInputSuggestions : NSObject
+ (nullable NSURL *)browserURLForInput:(NSString *)input;
// Candidates contain URL, title, and optional visits, visitedAt, tabID, bookmark, faviconData, faviconImage.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)suggestionsForInput:(NSString *)input
  commands:(NSArray<NSDictionary *> *)commands localCandidates:(NSArray<NSDictionary *> *)candidates
  searchURL:(nullable NSURL *)searchURL hasAttachments:(BOOL)attachments;
+ (NSArray<NSDictionary *> *)prepareLocalCandidates:(NSArray<NSDictionary *> *)candidates;
+ (NSString *)destinationKeyForURL:(NSURL *)URL;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)hermesCommandsFromCatalogue:(NSDictionary *)catalogue;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)slashCommandsForInput:(NSString *)input commands:(NSArray<NSDictionary<NSString *, NSString *> *> *)commands;
@end

NS_ASSUME_NONNULL_END
