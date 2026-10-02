#import "AppDelegate.h"
#import <AVFoundation/AVFoundation.h>
#import "ShortsController.h"
#import "Tabs.h"
#import "YTUI.h"

@implementation AppDelegate

- (UINavigationController *)tab:(UIViewController *)root title:(NSString *)title glyph:(NSString *)glyph {
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:root];
    navigation.navigationBar.barStyle = UIBarStyleBlack;
    navigation.navigationBar.translucent = NO;
    navigation.navigationBar.barTintColor = YTBackgroundColor();
    navigation.navigationBar.tintColor = UIColor.whiteColor;
    navigation.tabBarItem = [[UITabBarItem alloc] initWithTitle:title image:YTGlyphIcon(glyph) tag:0];
    return navigation;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Playback category: sound keeps working with the mute switch on.
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];

    UITabBarController *tabs = [UITabBarController new];
    tabs.tabBar.barStyle = UIBarStyleBlack;
    tabs.tabBar.translucent = NO;
    tabs.tabBar.barTintColor = YTBackgroundColor();
    tabs.tabBar.tintColor = UIColor.whiteColor;
    tabs.viewControllers = @[
        [self tab:[HomeController new] title:@"Главная" glyph:@"⌂"],
        [self tab:[ShortsController new] title:@"Shorts" glyph:@"▶"],
        [self tab:[SearchController new] title:@"Поиск" glyph:@"⌕"],
        [self tab:[SubscriptionsController new] title:@"Подписки" glyph:@"☰"],
        [self tab:[HistoryController new] title:@"История" glyph:@"↺"],
    ];

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = YTBackgroundColor();
    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];
    return YES;
}

// Stated explicitly so every screen may rotate, whatever the container controllers answer.
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskAllButUpsideDown;
}

@end
