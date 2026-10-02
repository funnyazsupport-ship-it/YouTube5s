#import "YTAPI.h"
#import "YTAuth.h"

// Each innertube client is good for something different:
// MWEB - small list responses; ANDROID - a playable muxed stream; TV - the only one that accepts the account token.
typedef NS_ENUM(NSInteger, YTClient) { YTClientWeb, YTClientAndroid, YTClientTV };

static NSString *const kWebVersion = @"2.20260925.01.00";
static NSString *const kWebUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";
static NSString *const kAndroidVersion = @"20.10.38";
static NSString *const kAndroidUA = @"com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip";
static NSString *const kTVVersion = @"7.20260925.10.00";
static NSString *const kTVUA = @"Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version";

static NSError *YTError(NSString *message) {
    return [NSError errorWithDomain:@"YouTube5s" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

// Safe path lookup: NSString steps index dictionaries, NSNumber steps index arrays.
static id YTDig(id node, NSArray *path) {
    for (id step in path) {
        if ([step isKindOfClass:NSString.class]) {
            if (![node isKindOfClass:NSDictionary.class]) return nil;
            node = [(NSDictionary *)node objectForKey:step];
        } else {
            if (![node isKindOfClass:NSArray.class]) return nil;
            NSUInteger i = [step unsignedIntegerValue];
            if (i >= [(NSArray *)node count]) return nil;
            node = [(NSArray *)node objectAtIndex:i];
        }
    }
    return node;
}

// YouTube text nodes come as {runs:[{text}]}, {simpleText}, {content} or a bare string.
static NSString *YTText(id node) {
    if ([node isKindOfClass:NSString.class]) return node;
    if (![node isKindOfClass:NSDictionary.class]) return nil;
    NSArray *runs = node[@"runs"];
    if ([runs isKindOfClass:NSArray.class]) {
        NSMutableString *s = [NSMutableString string];
        for (id run in runs) {
            NSString *t = YTDig(run, @[@"text"]);
            if ([t isKindOfClass:NSString.class]) [s appendString:t];
        }
        return s;
    }
    id simple = node[@"simpleText"] ?: node[@"content"];
    return [simple isKindOfClass:NSString.class] ? simple : nil;
}

static id YTFind(id node, NSString *key) {
    if ([node isKindOfClass:NSDictionary.class]) {
        id hit = [(NSDictionary *)node objectForKey:key];
        if (hit) return hit;
        for (id value in [(NSDictionary *)node allValues]) {
            id found = YTFind(value, key);
            if (found) return found;
        }
    } else if ([node isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)node) {
            id found = YTFind(value, key);
            if (found) return found;
        }
    }
    return nil;
}

// TV responses nest continuations: one for the whole page and one per shelf inside it.
// The page-level one is the closest to the root, hence breadth-first.
static NSString *YTShallowestTVContinuation(id root) {
    if (!root) return nil;
    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    for (NSUInteger i = 0; i < queue.count; i++) {
        id node = queue[i];
        if ([node isKindOfClass:NSDictionary.class]) {
            NSString *token = YTDig(node, @[@"nextContinuationData", @"continuation"]);
            if ([token isKindOfClass:NSString.class]) return token;
            [queue addObjectsFromArray:[(NSDictionary *)node allValues]];
        } else if ([node isKindOfClass:NSArray.class]) {
            [queue addObjectsFromArray:node];
        }
    }
    return nil;
}

// Mobile web list item.
static NSDictionary *YTVideoFromRenderer(NSDictionary *r) {
    NSString *videoId = r[@"videoId"];
    if (![videoId isKindOfClass:NSString.class]) return nil;
    NSMutableDictionary *v = [NSMutableDictionary dictionary];
    v[@"id"] = videoId;
    v[@"title"] = YTText(r[@"headline"]) ?: @"";
    NSString *author = YTText(r[@"shortBylineText"]);
    if (author) v[@"author"] = author;
    NSString *channelId = YTDig(r, @[@"shortBylineText", @"runs", @0, @"navigationEndpoint", @"browseEndpoint", @"browseId"]);
    if ([channelId isKindOfClass:NSString.class]) v[@"channelId"] = channelId;
    NSString *length = YTText(r[@"lengthText"]);
    if (length) v[@"length"] = length;
    NSString *views = YTText(r[@"shortViewCountText"]);
    if (views) v[@"views"] = views;
    NSString *published = YTText(r[@"publishedTimeText"]);
    if (published) v[@"published"] = published;
    NSArray *thumbs = YTDig(r, @[@"thumbnail", @"thumbnails"]);
    NSString *thumb = [thumbs isKindOfClass:NSArray.class] ? YTDig(thumbs.lastObject, @[@"url"]) : nil;
    v[@"thumb"] = [thumb isKindOfClass:NSString.class] ? thumb : [NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/mqdefault.jpg", videoId];
    return v;
}

// TV list item (account feeds). Channels, playlists and Shorts tiles are skipped.
static NSDictionary *YTVideoFromTile(NSDictionary *tile) {
    NSString *videoId = YTDig(tile, @[@"onSelectCommand", @"watchEndpoint", @"videoId"]);
    if (![videoId isKindOfClass:NSString.class]) return nil;
    NSMutableDictionary *v = [NSMutableDictionary dictionary];
    v[@"id"] = videoId;
    v[@"title"] = YTText(YTDig(tile, @[@"metadata", @"tileMetadataRenderer", @"title"])) ?: @"";
    v[@"thumb"] = [NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/mqdefault.jpg", videoId];
    NSString *length = YTText(YTDig(YTFind(tile[@"header"], @"thumbnailOverlayTimeStatusRenderer"), @[@"text"]));
    if (length) v[@"length"] = length;

    // Line 1 is the channel name, line 2 holds badges plus "views" and "age".
    NSArray *lines = YTDig(tile, @[@"metadata", @"tileMetadataRenderer", @"lines"]);
    NSMutableArray<NSString *> *lineTexts = [NSMutableArray array];
    if ([lines isKindOfClass:NSArray.class]) {
        for (id line in lines) {
            NSArray *items = YTDig(line, @[@"lineRenderer", @"items"]);
            NSMutableArray *parts = [NSMutableArray array];
            if ([items isKindOfClass:NSArray.class]) {
                for (id item in items) {
                    NSString *text = YTText(YTDig(item, @[@"lineItemRenderer", @"text"]));
                    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    if (trimmed.length && ![trimmed isEqualToString:@"•"]) [parts addObject:trimmed];
                }
            }
            if (parts.count) [lineTexts addObject:[parts componentsJoinedByString:@" · "]];
        }
    }
    if (lineTexts.count > 0) v[@"author"] = lineTexts[0];
    if (lineTexts.count > 1) v[@"views"] = lineTexts[1];
    return v;
}

// Collects videos and (mobile web) continuation tokens in document order.
// engagementPanels is skipped: its continuations belong to comments / channel "about", not to the list.
static void YTWalk(id node, NSMutableArray *videos, NSMutableArray *continuations) {
    if ([node isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = node;
        for (NSString *key in dict) {
            id value = dict[key];
            if ([key isEqualToString:@"engagementPanels"]) continue;
            if ([key isEqualToString:@"videoWithContextRenderer"] || [key isEqualToString:@"tileRenderer"]) {
                NSDictionary *v = nil;
                if ([value isKindOfClass:NSDictionary.class]) {
                    v = [key isEqualToString:@"tileRenderer"] ? YTVideoFromTile(value) : YTVideoFromRenderer(value);
                }
                if (v) [videos addObject:v];
            } else if ([key isEqualToString:@"continuationItemRenderer"]) {
                NSString *token = YTDig(value, @[@"continuationEndpoint", @"continuationCommand", @"token"]);
                if ([token isKindOfClass:NSString.class]) [continuations addObject:token];
            } else {
                YTWalk(value, videos, continuations);
            }
        }
    } else if ([node isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)node) YTWalk(value, videos, continuations);
    }
}

@implementation YTAPI

+ (void)post:(NSString *)endpoint body:(NSDictionary *)body client:(YTClient)clientType token:(NSString *)token completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSString *country = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode] ?: @"US";
    NSDictionary *client;
    NSString *userAgent, *clientNumber, *version;
    switch (clientType) {
        case YTClientAndroid:
            client = @{@"clientName": @"ANDROID", @"clientVersion": kAndroidVersion, @"hl": @"ru", @"gl": @"US",
                       @"osName": @"Android", @"osVersion": @"11", @"androidSdkVersion": @30};
            userAgent = kAndroidUA; clientNumber = @"3"; version = kAndroidVersion;
            break;
        case YTClientTV:
            client = @{@"clientName": @"TVHTML5", @"clientVersion": kTVVersion, @"hl": @"ru", @"gl": country};
            userAgent = kTVUA; clientNumber = @"7"; version = kTVVersion;
            break;
        case YTClientWeb:
            client = @{@"clientName": @"MWEB", @"clientVersion": kWebVersion, @"hl": @"ru", @"gl": country};
            userAgent = kWebUA; clientNumber = @"2"; version = kWebVersion;
            break;
    }
    NSMutableDictionary *full = [body mutableCopy];
    full[@"context"] = @{@"client": client};

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/%@?prettyPrint=false", endpoint]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 25;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:full options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    [request setValue:clientNumber forHTTPHeaderField:@"X-YouTube-Client-Name"];
    [request setValue:version forHTTPHeaderField:@"X-YouTube-Client-Version"];
    if (token) [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];

    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *json = nil;
        NSError *result = error;
        if (data && !error) {
            id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
            if ([object isKindOfClass:NSDictionary.class]) json = object;
            NSString *apiMessage = YTDig(json, @[@"error", @"message"]);
            if ([apiMessage isKindOfClass:NSString.class]) {
                result = YTError([@"YouTube: " stringByAppendingString:apiMessage]);
                json = nil;
            } else if (!json) {
                result = YTError(@"YouTube вернул непонятный ответ");
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(json, result); });
    }] resume];
}

+ (void)web:(NSString *)endpoint body:(NSDictionary *)body completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [self post:endpoint body:body client:YTClientWeb token:nil completion:completion];
}

// Requests made as the signed-in account.
+ (void)account:(NSString *)endpoint body:(NSDictionary *)body completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [YTAuth accessToken:^(NSString *token) {
        if (!token) { completion(nil, YTError(@"Нужно войти в аккаунт")); return; }
        [self post:endpoint body:body client:YTClientTV token:token completion:completion];
    }];
}

+ (void)list:(NSString *)endpoint body:(NSDictionary *)body completion:(YTListBlock)completion {
    [self web:endpoint body:body completion:^(NSDictionary *json, NSError *error) {
        if (!json) { completion(nil, nil, error); return; }
        NSMutableArray *videos = [NSMutableArray array];
        NSMutableArray *continuations = [NSMutableArray array];
        YTWalk(json, videos, continuations);
        completion(videos, continuations.firstObject, nil);
    }];
}

+ (void)search:(NSString *)query continuation:(NSString *)continuation completion:(YTListBlock)completion {
    NSDictionary *body = continuation ? @{@"continuation": continuation} : @{@"query": query ?: @""};
    [self list:@"search" body:body completion:completion];
}

+ (void)channel:(NSString *)channelId continuation:(NSString *)continuation completion:(YTListBlock)completion {
    // params selects the "Videos" tab
    NSDictionary *body = continuation ? @{@"continuation": continuation} : @{@"browseId": channelId ?: @"", @"params": @"EgZ2aWRlb3PyBgQKAjoA"};
    [self list:@"browse" body:body completion:completion];
}

+ (NSDictionary *)shortWithId:(NSString *)videoId {
    // oardefault is the vertical thumbnail; the frame0.jpg the API suggests is 1080x1920, too heavy for a 5s.
    return @{@"id": videoId, @"thumb": [NSString stringWithFormat:@"https://i.ytimg.com/vi/%@/oardefault.jpg", videoId]};
}

+ (void)shorts:(NSString *)continuation completion:(YTListBlock)completion {
    if (!continuation) {
        // A "seedless" request starts a fresh feed: one video plus the token for the rest.
        NSDictionary *body = @{@"params": @"CA8%3D", @"inputType": @"REEL_WATCH_INPUT_TYPE_SEEDLESS", @"disablePlayerResponse": @YES};
        [self web:@"reel/reel_item_watch" body:body completion:^(NSDictionary *json, NSError *error) {
            if (!json) { completion(nil, nil, error); return; }
            NSString *videoId = YTDig(json, @[@"replacementEndpoint", @"reelWatchEndpoint", @"videoId"]);
            NSString *next = YTDig(json, @[@"sequenceContinuation"]);
            NSArray *videos = [videoId isKindOfClass:NSString.class] ? @[[self shortWithId:videoId]] : @[];
            completion(videos, [next isKindOfClass:NSString.class] ? next : nil, nil);
        }];
        return;
    }
    [self web:@"reel/reel_watch_sequence" body:@{@"sequenceParams": continuation} completion:^(NSDictionary *json, NSError *error) {
        if (!json) { completion(nil, nil, error); return; }
        NSMutableArray *videos = [NSMutableArray array];
        NSArray *entries = json[@"entries"];
        if ([entries isKindOfClass:NSArray.class]) {
            for (id entry in entries) {
                NSString *videoId = YTDig(entry, @[@"command", @"reelWatchEndpoint", @"videoId"]);
                if ([videoId isKindOfClass:NSString.class]) [videos addObject:[self shortWithId:videoId]];
            }
        }
        NSString *next = YTDig(json, @[@"continuationEndpoint", @"continuationCommand", @"token"]);
        completion(videos, [next isKindOfClass:NSString.class] ? next : nil, nil);
    }];
}

+ (void)watch:(NSString *)videoId continuation:(NSString *)continuation completion:(YTWatchBlock)completion {
    NSDictionary *body = continuation ? @{@"continuation": continuation} : @{@"videoId": videoId ?: @""};
    [self web:@"next" body:body completion:^(NSDictionary *json, NSError *error) {
        if (!json) { completion(nil, nil, nil, error); return; }
        NSMutableArray *videos = [NSMutableArray array];
        NSMutableArray *continuations = [NSMutableArray array];
        YTWalk(json, videos, continuations);

        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        if (!continuation) {
            NSDictionary *header = YTFind(json, @"videoDescriptionHeaderRenderer");
            NSDictionary *slim = YTFind(json, @"slimVideoInformationRenderer");
            NSDictionary *owner = YTFind(json, @"slimOwnerRenderer");
            NSString *title = YTText(YTDig(slim, @[@"title"])) ?: YTText(YTDig(header, @[@"title"]));
            if (title) info[@"title"] = title;
            NSString *views = YTText(YTDig(header, @[@"views"]));
            if (views) info[@"views"] = views;
            NSString *date = YTText(YTDig(header, @[@"publishDate"]));
            if (date) info[@"date"] = date;
            NSString *description = YTText(YTDig(YTFind(json, @"expandableVideoDescriptionBodyRenderer"), @[@"attributedDescriptionBodyText"]));
            if (description) info[@"description"] = description;
            NSString *author = YTText(YTDig(owner, @[@"title"]));
            if (author) info[@"author"] = author;
            NSString *channelId = YTDig(owner, @[@"navigationEndpoint", @"browseEndpoint", @"browseId"]);
            if ([channelId isKindOfClass:NSString.class]) info[@"channelId"] = channelId;
            NSArray *avatars = YTDig(owner, @[@"thumbnail", @"thumbnails"]);
            NSString *avatar = [avatars isKindOfClass:NSArray.class] ? YTDig(avatars.lastObject, @[@"url"]) : nil;
            if ([avatar isKindOfClass:NSString.class]) info[@"avatar"] = avatar;
        }
        completion(info, videos, continuations.firstObject, nil);
    }];
}

+ (void)stream:(NSString *)videoId completion:(void (^)(NSURL *, NSDictionary *, NSError *))completion {
    NSDictionary *body = @{@"videoId": videoId ?: @"", @"contentCheckOk": @YES, @"racyCheckOk": @YES};
    [self post:@"player" body:body client:YTClientAndroid token:nil completion:^(NSDictionary *json, NSError *error) {
        if (!json) { completion(nil, nil, error); return; }
        NSDictionary *streaming = YTDig(json, @[@"streamingData"]);

        // Muxed (video+audio in one file) formats are the only progressive ones AVPlayer can play directly.
        NSString *best = nil;
        NSInteger bestHeight = -1;
        NSArray *formats = YTDig(streaming, @[@"formats"]);
        if ([formats isKindOfClass:NSArray.class]) {
            for (id format in formats) {
                NSString *url = YTDig(format, @[@"url"]);
                NSString *mime = YTDig(format, @[@"mimeType"]);
                if (![url isKindOfClass:NSString.class]) continue;
                if ([mime isKindOfClass:NSString.class] && ![mime hasPrefix:@"video/mp4"]) continue;
                NSNumber *height = YTDig(format, @[@"height"]);
                NSInteger h = [height isKindOfClass:NSNumber.class] ? height.integerValue : 0;
                if (h > bestHeight) { bestHeight = h; best = url; }
            }
        }
        // Live streams have no muxed file, only an HLS manifest.
        if (!best) {
            NSString *hls = YTDig(streaming, @[@"hlsManifestUrl"]);
            if ([hls isKindOfClass:NSString.class]) best = hls;
        }
        NSURL *url = best ? [NSURL URLWithString:best] : nil;
        if (!url) {
            NSString *reason = YTDig(json, @[@"playabilityStatus", @"reason"]);
            if (![reason isKindOfClass:NSString.class]) reason = @"YouTube не отдал поток для этого видео";
            completion(nil, nil, YTError(reason));
            return;
        }

        NSMutableDictionary *details = [NSMutableDictionary dictionary];
        for (NSString *key in @[@"title", @"author", @"channelId"]) {
            NSString *value = YTDig(json, @[@"videoDetails", key]);
            if ([value isKindOfClass:NSString.class]) details[key] = value;
        }
        NSString *views = YTDig(json, @[@"videoDetails", @"viewCount"]);
        if ([views isKindOfClass:NSString.class]) details[@"views"] = views;
        completion(url, details, nil);
    }];
}

#pragma mark - Signed-in account

+ (void)accountFeed:(NSString *)browseId continuation:(NSString *)continuation completion:(YTListBlock)completion {
    NSDictionary *body = continuation ? @{@"continuation": continuation} : @{@"browseId": browseId ?: @""};
    [self account:@"browse" body:body completion:^(NSDictionary *json, NSError *error) {
        if (!json) { completion(nil, nil, error); return; }
        NSMutableArray *videos = [NSMutableArray array];
        NSMutableArray *unused = [NSMutableArray array];
        YTWalk(json, videos, unused);
        completion(videos, YTShallowestTVContinuation(json), nil);
    }];
}

+ (void)setLiked:(BOOL)liked videoId:(NSString *)videoId completion:(void (^)(NSError *))completion {
    NSDictionary *body = @{@"target": @{@"videoId": videoId ?: @""}};
    [self account:liked ? @"like/like" : @"like/removelike" body:body completion:^(NSDictionary *json, NSError *error) {
        completion(json ? nil : error);
    }];
}

+ (void)setSubscribed:(BOOL)subscribed channelId:(NSString *)channelId completion:(void (^)(NSError *))completion {
    NSDictionary *body = @{@"channelIds": @[channelId ?: @""]};
    [self account:subscribed ? @"subscription/subscribe" : @"subscription/unsubscribe" body:body completion:^(NSDictionary *json, NSError *error) {
        completion(json ? nil : error);
    }];
}

@end
