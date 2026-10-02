#import "YTStore.h"

static NSString *const kHistoryKey = @"history";
static NSString *const kSubscriptionsKey = @"subscriptions";
static const NSUInteger kHistoryLimit = 200;

@implementation YTStore

+ (NSArray *)arrayForKey:(NSString *)key {
    NSArray *array = [[NSUserDefaults standardUserDefaults] arrayForKey:key];
    return array ?: @[];
}

+ (NSArray<NSDictionary *> *)history {
    return [self arrayForKey:kHistoryKey];
}

+ (void)addToHistory:(NSDictionary *)video {
    NSString *videoId = video[@"id"];
    if (!videoId) return;
    NSMutableArray *history = [NSMutableArray arrayWithObject:video];
    for (NSDictionary *old in [self history]) {
        if (![old[@"id"] isEqual:videoId]) [history addObject:old];
        if (history.count >= kHistoryLimit) break;
    }
    [[NSUserDefaults standardUserDefaults] setObject:history forKey:kHistoryKey];
}

+ (void)clearHistory {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kHistoryKey];
}

+ (NSArray<NSDictionary *> *)subscriptions {
    return [self arrayForKey:kSubscriptionsKey];
}

+ (BOOL)isSubscribed:(NSString *)channelId {
    for (NSDictionary *channel in [self subscriptions]) {
        if ([channel[@"id"] isEqual:channelId]) return YES;
    }
    return NO;
}

+ (void)setSubscribed:(BOOL)subscribed channelId:(NSString *)channelId title:(NSString *)title {
    if (!channelId) return;
    NSMutableArray *subscriptions = [NSMutableArray array];
    for (NSDictionary *channel in [self subscriptions]) {
        if (![channel[@"id"] isEqual:channelId]) [subscriptions addObject:channel];
    }
    if (subscribed) [subscriptions insertObject:@{@"id": channelId, @"title": title ?: @"Канал"} atIndex:0];
    [[NSUserDefaults standardUserDefaults] setObject:subscriptions forKey:kSubscriptionsKey];
}

@end
