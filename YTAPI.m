#import "YTAPI.h"

static NSString *const kWebVersion = @"2.20260925.01.00";
static NSString *const kWebUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";
static NSString *const kAndroidVersion = @"20.10.38";
static NSString *const kAndroidUA = @"com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip";

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

// Collects video renderers and continuation tokens in document order.
// engagementPanels is skipped: its continuations belong to comments / channel "about", not to the list.
static void YTWalk(id node, NSMutableArray *videos, NSMutableArray *continuations) {
    if ([node isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = node;
        for (NSString *key in dict) {
            id value = dict[key];
            if ([key isEqualToString:@"engagementPanels"]) continue;
            if ([key isEqualToString:@"videoWithContextRenderer"]) {
                NSDictionary *v = [value isKindOfClass:NSDictionary.class] ? YTVideoFromRenderer(value) : nil;
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

+ (void)post:(NSString *)endpoint body:(NSDictionary *)body android:(BOOL)android completion:(void (^)(NSDictionary *json, NSError *error))completion {
    NSDictionary *client;
    if (android) {
        client = @{@"clientName": @"ANDROID", @"clientVersion": kAndroidVersion, @"hl": @"ru", @"gl": @"US",
                   @"osName": @"Android", @"osVersion": @"11", @"androidSdkVersion": @30};
    } else {
        NSString *country = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode] ?: @"US";
        client = @{@"clientName": @"MWEB", @"clientVersion": kWebVersion, @"hl": @"ru", @"gl": country};
    }
    NSMutableDictionary *full = [body mutableCopy];
    full[@"context"] = @{@"client": client};

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/%@?prettyPrint=false", endpoint]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 25;
    request.HTTPBody = [NSJSONSerialization dataWithJSONObject:full options:0 error:nil];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:android ? kAndroidUA : kWebUA forHTTPHeaderField:@"User-Agent"];
    [request setValue:android ? @"3" : @"2" forHTTPHeaderField:@"X-YouTube-Client-Name"];
    [request setValue:android ? kAndroidVersion : kWebVersion forHTTPHeaderField:@"X-YouTube-Client-Version"];

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

+ (void)list:(NSString *)endpoint body:(NSDictionary *)body completion:(YTListBlock)completion {
    [self post:endpoint body:body android:NO completion:^(NSDictionary *json, NSError *error) {
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

+ (void)watch:(NSString *)videoId continuation:(NSString *)continuation completion:(YTWatchBlock)completion {
    NSDictionary *body = continuation ? @{@"continuation": continuation} : @{@"videoId": videoId ?: @""};
    [self post:@"next" body:body android:NO completion:^(NSDictionary *json, NSError *error) {
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

+ (void)streamURL:(NSString *)videoId completion:(void (^)(NSURL *, NSError *))completion {
    NSDictionary *body = @{@"videoId": videoId ?: @"", @"contentCheckOk": @YES, @"racyCheckOk": @YES};
    [self post:@"player" body:body android:YES completion:^(NSDictionary *json, NSError *error) {
        if (!json) { completion(nil, error); return; }
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
        if (url) { completion(url, nil); return; }

        NSString *reason = YTDig(json, @[@"playabilityStatus", @"reason"]);
        if (![reason isKindOfClass:NSString.class]) reason = @"YouTube не отдал поток для этого видео";
        completion(nil, YTError(reason));
    }];
}

@end
