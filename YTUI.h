#import <UIKit/UIKit.h>

// iOS 12 has no system dark mode, so the palette is fixed here.
UIColor *YTBackgroundColor(void);
UIColor *YTSecondaryTextColor(void);
UIColor *YTAccentColor(void);

// Renders a text glyph into a tab bar icon (the app ships no image assets).
UIImage *YTGlyphIcon(NSString *glyph);

@interface UIImageView (YTRemote)
- (void)yt_setImageURL:(NSString *)urlString;
@end

@interface YTVideoCell : UITableViewCell
+ (CGFloat)heightForWidth:(CGFloat)width;
- (void)configureWithVideo:(NSDictionary *)video;
@end
