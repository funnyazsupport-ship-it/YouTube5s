#import <Foundation/Foundation.h>

// Local history and subscriptions (there is no Google account login).
@interface YTStore : NSObject

+ (NSArray<NSDictionary *> *)history;
+ (void)addToHistory:(NSDictionary *)video;
+ (void)clearHistory;

// Channel dictionaries: id, title
+ (NSArray<NSDictionary *> *)subscriptions;
+ (BOOL)isSubscribed:(NSString *)channelId;
+ (void)setSubscribed:(BOOL)subscribed channelId:(NSString *)channelId title:(NSString *)title;

@end
