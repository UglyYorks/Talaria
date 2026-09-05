#import <Foundation/Foundation.h>
#import "TalariaModels.h"
#import "TLCredentialStore.h"

NS_ASSUME_NONNULL_BEGIN

@interface TLDatabase : NSObject

+ (NSURL *)defaultDatabaseURL;
- (nullable instancetype)initWithURL:(NSURL *)url error:(NSError **)error;
- (nullable instancetype)initWithURL:(NSURL *)url
                    credentialStore:(id<TLCredentialStore>)credentialStore
                              error:(NSError **)error;

- (nullable TLAppSettings *)appSettings:(NSError **)error;
- (nullable TLAppSettings *)saveAppSettings:(TLAppSettings *)settings error:(NSError **)error;
- (nullable NSArray<TLChatSummary *> *)listChats:(NSError **)error;
- (nullable TLChatRecord *)createChatWithModel:(NSString *)model error:(NSError **)error;
// Saves only model choices/defaults; credentials and appearance are untouched.
- (BOOL)saveModelsForChatID:(NSInteger)chatID model:(NSString *)model supportingModel:(NSString *)supportingModel error:(NSError **)error;
- (nullable TLChatRecord *)createChatWithModel:(NSString *)model supportingModel:(NSString *)supportingModel error:(NSError **)error;
- (nullable TLChatRecord *)chatWithID:(NSInteger)chatID error:(NSError **)error;
- (nullable TLChatSummary *)saveChatTitle:(NSString *)title chatID:(NSInteger)chatID error:(NSError **)error;
- (nullable TLChatSummary *)saveChatIcon:(NSString *)icon chatID:(NSInteger)chatID error:(NSError **)error;
- (nullable TLStoredChatMessage *)saveMessage:(TLChatMessage *)message chatID:(NSInteger)chatID error:(NSError **)error;
- (BOOL)deleteMessageWithID:(NSInteger)messageID chatID:(NSInteger)chatID error:(NSError **)error;
- (nullable TLChatRecord *)clearChatWithID:(NSInteger)chatID error:(NSError **)error;
- (BOOL)deleteChatWithID:(NSInteger)chatID error:(NSError **)error;
- (nullable NSArray<TLAgentRecord *> *)listAgents:(NSError **)error;
- (nullable TLAgentRecord *)createAgentWithName:(NSString *)name
                                      guestKind:(NSString *)guestKind
                                        runtime:(NSString *)runtime
                                    vmDirectory:(NSString *)vmDirectory
                                          error:(NSError **)error;
- (nullable TLAgentRecord *)agentWithID:(NSInteger)agentID error:(NSError **)error;
- (nullable TLAgentRecord *)createAgentWithName:(NSString *)name avatar:(NSString *)avatar
                                         soul:(NSString *)soul folderPaths:(NSArray<NSString *> *)folderPaths
                                  vmDirectory:(NSString *)vmDirectory error:(NSError **)error;
- (NSInteger)currentAgentID;
- (BOOL)setCurrentAgentID:(NSInteger)agentID error:(NSError **)error;
- (nullable TLAgentRecord *)updateAgentWithID:(NSInteger)agentID
                                       status:(NSString *)status
                                    lastError:(nullable NSString *)lastError
                                        error:(NSError **)error;
- (nullable TLAgentRecord *)updateAgentWithID:(NSInteger)agentID folderPaths:(NSArray<NSString *> *)folderPaths error:(NSError **)error;
- (nullable TLAgentRecord *)updateAgentWithID:(NSInteger)agentID name:(NSString *)name
                                      avatar:(NSString *)avatar soul:(NSString *)soul error:(NSError **)error;
- (BOOL)deleteAgentWithID:(NSInteger)agentID error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
