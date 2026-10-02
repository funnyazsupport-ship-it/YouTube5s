#import <Foundation/Foundation.h>

extern NSString *const YTAuthDidChangeNotification;

// Google account login through the "enter this code on another device" flow that YouTube uses on TVs.
// A normal Google login page does not work inside an app's web view, and not at all on iOS 12.
@interface YTAuth : NSObject

+ (BOOL)isLoggedIn;
+ (void)logout;

// onCode delivers the code the user must type at verificationURL; finished fires once, after the
// user confirmed (error == nil), the code expired, or the request failed.
+ (void)startLogin:(void (^)(NSString *code, NSString *verificationURL))onCode finished:(void (^)(NSError *error))finished;
+ (void)cancelLogin;

// Calls back on the main queue with a valid access token, or nil when not logged in / refresh failed.
+ (void)accessToken:(void (^)(NSString *token))completion;

@end
