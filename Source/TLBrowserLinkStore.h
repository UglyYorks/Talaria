#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Named tab groups and their saved links, shared by the browser's context and account menus.
@interface TLBrowserLinkStore : NSObject
+ (instancetype)sharedStore;
- (instancetype)initWithURL:(NSURL *)URL;
@property (nonatomic, readonly) NSArray<NSDictionary *> *groups;
- (NSArray<NSDictionary *> *)linksInCollection:(NSString *)collection;
- (BOOL)addURL:(NSURL *)URL title:(NSString *)title collection:(NSString *)collection error:(NSError **)error;
- (nullable NSString *)createGroupNamed:(NSString *)name error:(NSError **)error;
- (BOOL)removeURL:(NSString *)URLString collection:(NSString *)collection error:(NSError **)error;
- (BOOL)removeGroup:(NSString *)identifier error:(NSError **)error;
@end
FOUNDATION_EXPORT BOOL TLBrowserLinkURLIsNavigable(NSURL * _Nullable URL);
NS_ASSUME_NONNULL_END
