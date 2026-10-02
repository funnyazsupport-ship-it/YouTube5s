#import "YTUI.h"
#import <objc/runtime.h>

UIColor *YTBackgroundColor(void) {
    return [UIColor colorWithWhite:0.06 alpha:1];
}

UIColor *YTSecondaryTextColor(void) {
    return [UIColor colorWithWhite:0.67 alpha:1];
}

UIColor *YTAccentColor(void) {
    return [UIColor colorWithRed:1 green:0.0 blue:0.0 alpha:1];
}

UIImage *YTGlyphIcon(NSString *glyph) {
    CGSize size = CGSizeMake(26, 26);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:20], NSForegroundColorAttributeName: UIColor.whiteColor};
    CGSize textSize = [glyph sizeWithAttributes:attributes];
    [glyph drawAtPoint:CGPointMake((size.width - textSize.width) / 2, (size.height - textSize.height) / 2) withAttributes:attributes];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#pragma mark - Remote images

static char kImageURLKey;

static NSCache *YTImageCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 80; // the 5s has 1 GB of RAM
    });
    return cache;
}

@implementation UIImageView (YTRemote)

- (void)yt_setImageURL:(NSString *)urlString {
    objc_setAssociatedObject(self, &kImageURLKey, urlString, OBJC_ASSOCIATION_COPY_NONATOMIC);
    self.image = nil;
    NSURL *url = urlString.length ? [NSURL URLWithString:urlString] : nil;
    if (!url) return;

    UIImage *cached = [YTImageCache() objectForKey:urlString];
    if (cached) { self.image = cached; return; }

    __weak UIImageView *weakSelf = self;
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        if (!image) return;
        [YTImageCache() setObject:image forKey:urlString];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIImageView *view = weakSelf;
            // The cell may have been reused for another video while this was loading.
            if (view && [objc_getAssociatedObject(view, &kImageURLKey) isEqual:urlString]) view.image = image;
        });
    }] resume];
}

@end

#pragma mark - Video cell

static const CGFloat kTextBlockHeight = 74;

@interface YTVideoCell ()
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UILabel *lengthLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@end

@implementation YTVideoCell

+ (CGFloat)heightForWidth:(CGFloat)width {
    return floor(width * 9 / 16) + kTextBlockHeight;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = YTBackgroundColor();
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        _thumbView = [UIImageView new];
        _thumbView.contentMode = UIViewContentModeScaleAspectFill;
        _thumbView.clipsToBounds = YES;
        _thumbView.backgroundColor = [UIColor colorWithWhite:0.13 alpha:1];
        [self.contentView addSubview:_thumbView];

        _lengthLabel = [UILabel new];
        _lengthLabel.font = [UIFont boldSystemFontOfSize:11];
        _lengthLabel.textColor = UIColor.whiteColor;
        _lengthLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.8];
        _lengthLabel.textAlignment = NSTextAlignmentCenter;
        _lengthLabel.layer.cornerRadius = 3;
        _lengthLabel.clipsToBounds = YES;
        [self.contentView addSubview:_lengthLabel];

        _titleLabel = [UILabel new];
        _titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.numberOfLines = 2;
        [self.contentView addSubview:_titleLabel];

        _metaLabel = [UILabel new];
        _metaLabel.font = [UIFont systemFontOfSize:12];
        _metaLabel.textColor = YTSecondaryTextColor();
        [self.contentView addSubview:_metaLabel];
    }
    return self;
}

- (void)configureWithVideo:(NSDictionary *)video {
    [self.thumbView yt_setImageURL:video[@"thumb"]];
    self.titleLabel.text = video[@"title"];
    NSString *length = video[@"length"];
    self.lengthLabel.text = length;
    self.lengthLabel.hidden = length.length == 0;

    NSMutableArray *parts = [NSMutableArray array];
    for (NSString *key in @[@"author", @"views", @"published"]) {
        NSString *part = video[key];
        if (part.length) [parts addObject:part];
    }
    self.metaLabel.text = [parts componentsJoinedByString:@" · "];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat thumbHeight = floor(width * 9 / 16);
    self.thumbView.frame = CGRectMake(0, 0, width, thumbHeight);

    CGSize lengthSize = [self.lengthLabel sizeThatFits:CGSizeMake(100, 20)];
    CGFloat lengthWidth = lengthSize.width + 8;
    self.lengthLabel.frame = CGRectMake(width - lengthWidth - 6, thumbHeight - 24, lengthWidth, 18);

    CGFloat textWidth = width - 24;
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(textWidth, 40)];
    self.titleLabel.frame = CGRectMake(12, thumbHeight + 8, textWidth, MIN(titleSize.height, 38));
    self.metaLabel.frame = CGRectMake(12, CGRectGetMaxY(self.titleLabel.frame) + 3, textWidth, 16);
}

@end
