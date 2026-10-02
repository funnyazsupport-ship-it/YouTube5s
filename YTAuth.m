#import "YTAuth.h"
#import <Security/Security.h>

NSString *const YTAuthDidChangeNotification = @"YTAuthDidChangeNotification";

// Public OAuth client of the YouTube TV app; the device-code flow is tied to it.
static NSString *const kClientId = @"861556708454-d6dlm3lh05idd8npek18k6be8ba3oc68.apps.googleusercontent.com";
static NSString *const kClientSecret = @"SboVhoG9s0rNafixCSGGKXAT";
static NSString *const kScope = @"http://gdata.youtube.com https://gdata.youtube.com";
static NSString *const kDeviceCodeURL = @"https://www.youtube.com/o/oauth2/device/code";
static NSString *const kTokenURL = @"https://www.youtube.com/o/oauth2/token";
static NSString *const kKeychainAccount = @"youtube-refresh-token";

static NSString *sAccessToken;
static NSDate *sAccessExpiry;
static NSUInteger sLoginGeneration; // bumped to abandon a running poll loop

static NSError *YTAuthError(NSString *message) {
    return [NSError errorWithDomain:@"YouTube5s" code:2 userInfo:@{NSLocalizedDescriptionKey: message}];
}

#pragma mark - Keychain (the refresh token is a long-lived credential, so not NSUserDefaults)

static NSDictionary *YTKeychainQuery(void) {
    return @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService: @"YouTube5s",
             (__bridge id)kSecAttrAccount: kKeychainAccount};
}

static NSString *YTStoredRefreshToken(void) {
    NSMutableDictionary *query = [YTKeychainQuery() mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess || !result) return nil;
    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

static void YTStoreRefreshToken(NSString *token) {
    SecItemDelete((__bridge CFDictionaryRef)YTKeychainQuery());
    if (!token.length) return;
    NSMutableDictionary *item = [YTKeychainQuery() mutableCopy];
    item[(__bridge id)kSecValueData] = [token dataUsingEncoding:NSUTF8StringEncoding];
    item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlock;
    SecItemAdd((__bridge CFDictionaryRef)item, NULL);
}

@implementation YTAuth

// Completion on the main queue. Google answers "still waiting" with an error JSON, so the body is
// parsed regardless of the HTTP status.
+ (void)post:(NSString *)address body:(NSDictionary *)body completion:(void (^)(NSDictionary *json))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:address]];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 20;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *result = [json isKindOfClass:NSDictionary.class] ? json : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    }] resume];
}

+ (BOOL)isLoggedIn {
    return YTStoredRefreshToken().length > 0;
}

+ (void)logout {
    sLoginGeneration++;
    sAccessToken = nil;
    sAccessExpiry = nil;
    YTStoreRefreshToken(nil);
    [[NSNotificationCenter defaultCenter] postNotificationName:YTAuthDidChangeNotification object:nil];
}

+ (void)cancelLogin {
    sLoginGeneration++;
}

+ (void)adoptTokenResponse:(NSDictionary *)json {
    NSString *access = json[@"access_token"];
    NSNumber *expires = json[@"expires_in"];
    sAccessToken = [access isKindOfClass:NSString.class] ? access : nil;
    NSTimeInterval lifetime = [expires respondsToSelector:@selector(doubleValue)] ? expires.doubleValue : 3600;
    sAccessExpiry = [NSDate dateWithTimeIntervalSinceNow:lifetime - 60];
}

+ (void)startLogin:(void (^)(NSString *, NSString *))onCode finished:(void (^)(NSError *))finished {
    NSUInteger generation = ++sLoginGeneration;
    NSString *deviceId = [[NSUUID UUID].UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""].lowercaseString;
    NSDictionary *body = @{@"client_id": kClientId, @"scope": kScope, @"device_id": deviceId, @"device_model": @"ytlr::"};
    [self post:kDeviceCodeURL body:body completion:^(NSDictionary *json) {
        if (generation != sLoginGeneration) return;
        NSString *deviceCode = json[@"device_code"];
        NSString *userCode = json[@"user_code"];
        if (![deviceCode isKindOfClass:NSString.class] || ![userCode isKindOfClass:NSString.class]) {
            finished(YTAuthError(@"Google не выдал код для входа"));
            return;
        }
        NSString *url = [json[@"verification_url"] isKindOfClass:NSString.class] ? json[@"verification_url"] : @"https://www.google.com/device";
        NSTimeInterval interval = MAX(3, [json[@"interval"] doubleValue]);
        NSTimeInterval lifetime = [json[@"expires_in"] doubleValue] ?: 1800;
        onCode(userCode, url);
        [self pollCode:deviceCode interval:interval deadline:[NSDate dateWithTimeIntervalSinceNow:lifetime] generation:generation finished:finished];
    }];
}

+ (void)pollCode:(NSString *)deviceCode interval:(NSTimeInterval)interval deadline:(NSDate *)deadline generation:(NSUInteger)generation finished:(void (^)(NSError *))finished {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation != sLoginGeneration) return;
        if ([deadline timeIntervalSinceNow] < 0) { finished(YTAuthError(@"Код устарел, попробуй ещё раз")); return; }
        NSDictionary *body = @{@"client_id": kClientId, @"client_secret": kClientSecret, @"code": deviceCode,
                               @"grant_type": @"http://oauth.net/grant_type/device/1.0"};
        [self post:kTokenURL body:body completion:^(NSDictionary *json) {
            if (generation != sLoginGeneration) return;
            NSString *refresh = json[@"refresh_token"];
            if ([refresh isKindOfClass:NSString.class] && refresh.length) {
                YTStoreRefreshToken(refresh);
                [self adoptTokenResponse:json];
                [[NSNotificationCenter defaultCenter] postNotificationName:YTAuthDidChangeNotification object:nil];
                finished(nil);
                return;
            }
            NSString *error = json[@"error"];
            // No JSON at all means a network hiccup: keep waiting as well.
            if (!json || [error isEqual:@"authorization_pending"] || [error isEqual:@"slow_down"]) {
                NSTimeInterval next = [error isEqual:@"slow_down"] ? interval + 5 : interval;
                [self pollCode:deviceCode interval:next deadline:deadline generation:generation finished:finished];
            } else if ([error isEqual:@"access_denied"]) {
                finished(YTAuthError(@"Вход отклонён"));
            } else {
                finished(YTAuthError(@"Код устарел, попробуй ещё раз"));
            }
        }];
    });
}

+ (void)accessToken:(void (^)(NSString *))completion {
    if (sAccessToken && [sAccessExpiry timeIntervalSinceNow] > 0) { completion(sAccessToken); return; }
    NSString *refresh = YTStoredRefreshToken();
    if (!refresh.length) { completion(nil); return; }
    NSDictionary *body = @{@"client_id": kClientId, @"client_secret": kClientSecret, @"refresh_token": refresh, @"grant_type": @"refresh_token"};
    [self post:kTokenURL body:body completion:^(NSDictionary *json) {
        if ([json[@"access_token"] isKindOfClass:NSString.class]) {
            [self adoptTokenResponse:json];
        } else if ([json[@"error"] isEqual:@"invalid_grant"]) {
            // The account revoked access: the stored token is dead for good.
            [self logout];
        }
        completion(sAccessToken);
    }];
}

@end
