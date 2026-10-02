#import <Foundation/Foundation.h>

// Video dictionaries are plist-safe (strings only) so they can go straight into NSUserDefaults.
// Keys: id, title, author, channelId, length, views, published, thumb
typedef void (^YTListBlock)(NSArray<NSDictionary *> *videos, NSString *continuation, NSError *error);
typedef void (^YTWatchBlock)(NSDictionary *info, NSArray<NSDictionary *> *videos, NSString *continuation, NSError *error);

@interface YTAPI : NSObject

+ (void)search:(NSString *)query continuation:(NSString *)continuation completion:(YTListBlock)completion;
+ (void)channel:(NSString *)channelId continuation:(NSString *)continuation completion:(YTListBlock)completion;

// The endless Shorts feed. Items only carry id and thumb; title/author arrive with the stream.
+ (void)shorts:(NSString *)continuation completion:(YTListBlock)completion;

// info keys: title, views, date, description, author, channelId, avatar
+ (void)watch:(NSString *)videoId continuation:(NSString *)continuation completion:(YTWatchBlock)completion;

// details keys: title, author, channelId, views
+ (void)stream:(NSString *)videoId completion:(void (^)(NSURL *url, NSDictionary *details, NSError *error))completion;

#pragma mark Signed-in account (needs YTAuth login)

// browseId: FEwhat_to_watch (recommendations) or FEsubscriptions.
+ (void)accountFeed:(NSString *)browseId continuation:(NSString *)continuation completion:(YTListBlock)completion;
+ (void)setLiked:(BOOL)liked videoId:(NSString *)videoId completion:(void (^)(NSError *error))completion;
+ (void)setSubscribed:(BOOL)subscribed channelId:(NSString *)channelId completion:(void (^)(NSError *error))completion;

@end
