#import <Foundation/Foundation.h>

// Video dictionaries are plist-safe (strings only) so they can go straight into NSUserDefaults.
// Keys: id, title, author, channelId, length, views, published, thumb
typedef void (^YTListBlock)(NSArray<NSDictionary *> *videos, NSString *continuation, NSError *error);
typedef void (^YTWatchBlock)(NSDictionary *info, NSArray<NSDictionary *> *videos, NSString *continuation, NSError *error);

@interface YTAPI : NSObject

+ (void)search:(NSString *)query continuation:(NSString *)continuation completion:(YTListBlock)completion;
+ (void)channel:(NSString *)channelId continuation:(NSString *)continuation completion:(YTListBlock)completion;

// info keys: title, views, date, description, author, channelId, avatar
+ (void)watch:(NSString *)videoId continuation:(NSString *)continuation completion:(YTWatchBlock)completion;

+ (void)streamURL:(NSString *)videoId completion:(void (^)(NSURL *url, NSError *error))completion;

@end
