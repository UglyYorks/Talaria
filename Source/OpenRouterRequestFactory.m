#import "OpenRouterRequestFactory.h"
#import "OpenRouterSupport.h"

static NSString * const TLOpenRouterChatCompletionsURL = @"https://openrouter.ai/api/v1/chat/completions";
static NSString * const TLOpenRouterModelsURL = @"https://openrouter.ai/api/v1/models?output_modalities=text";

static void TLOpenRouterApplyCommonHeaders(NSMutableURLRequest *request) {
  [request setValue:@"app://talaria" forHTTPHeaderField:@"HTTP-Referer"];
  [request setValue:@"Talaria" forHTTPHeaderField:@"X-Title"];
}

NSURLRequest *TLOpenRouterMakeModelCatalogueRequest(NSString *token) {
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:TLOpenRouterModelsURL]];
  request.HTTPMethod = @"GET";
  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  TLOpenRouterApplyCommonHeaders(request);

  NSString *trimmedToken = TLOpenRouterTrim(token);
  if (trimmedToken.length > 0) {
    [request setValue:[NSString stringWithFormat:@"Bearer %@", trimmedToken] forHTTPHeaderField:@"Authorization"];
  }

  return request;
}

NSURLRequest *TLOpenRouterMakeChatRequest(NSString *token,
                                          NSString *model,
                                          NSArray<TLChatMessage *> *messages,
                                          NSError **error) {
  NSMutableArray<NSDictionary<NSString *, NSString *> *> *requestMessages = [NSMutableArray arrayWithCapacity:messages.count];
  for (TLChatMessage *message in messages) {
    [requestMessages addObject:[message requestDictionary]];
  }

  NSDictionary *body = @{
    @"model": model,
    @"messages": requestMessages,
    @"temperature": @0.7,
    @"stream": @YES,
    @"reasoning": @{@"max_tokens": @2000},
  };

  NSError *jsonError = nil;
  NSData *jsonData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
  if (!jsonData) {
    if (error) {
      *error = TLOpenRouterError([NSString stringWithFormat:@"Could not create OpenRouter request: %@", jsonError.localizedDescription]);
    }
    return nil;
  }

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:TLOpenRouterChatCompletionsURL]];
  request.HTTPMethod = @"POST";
  request.HTTPBody = jsonData;
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  [request setValue:[NSString stringWithFormat:@"Bearer %@", token] forHTTPHeaderField:@"Authorization"];
  TLOpenRouterApplyCommonHeaders(request);
  return request;
}

NSError *TLOpenRouterValidateChatInput(NSString *token,
                                       NSString *model,
                                       NSString *requestID,
                                       NSArray<TLChatMessage *> *messages) {
  if (token.length == 0) {
    return TLOpenRouterError(@"OpenRouter token is required.");
  }

  if (model.length == 0) {
    return TLOpenRouterError(@"OpenRouter model is required.");
  }

  if (requestID.length == 0) {
    return TLOpenRouterError(@"Request ID is required.");
  }

  if (messages.count == 0) {
    return TLOpenRouterError(@"At least one message is required.");
  }

  for (TLChatMessage *message in messages) {
    BOOL validRole = [message.role isEqualToString:TLRoleSystem] ||
      [message.role isEqualToString:TLRoleUser] ||
      [message.role isEqualToString:TLRoleAssistant];

    if (!validRole) {
      return TLOpenRouterError(@"Messages must use system, user, or assistant roles.");
    }

    if (TLOpenRouterTrim(message.content).length == 0) {
      return TLOpenRouterError(@"Messages cannot be empty.");
    }
  }

  return nil;
}
