#import "PlayerController.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import "VideoListController.h"
#import "YTAPI.h"
#import "YTAuth.h"
#import "YTStore.h"
#import "YTUI.h"

@interface PlayerController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSDictionary *video;
@property (nonatomic, copy) NSDictionary *info;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *related;
@property (nonatomic, copy) NSString *continuation;
@property (nonatomic, assign) BOOL loadingMore;
@property (nonatomic, assign) BOOL descriptionExpanded;
@property (nonatomic, assign) BOOL liked;
@property (nonatomic, strong) UIButton *exitLandscapeButton;

@property (nonatomic, strong) AVPlayerViewController *playerController;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIButton *channelButton;
@property (nonatomic, strong) UIButton *subscribeButton;
@property (nonatomic, strong) UILabel *descriptionLabel;
@end

@implementation PlayerController

- (instancetype)initWithVideo:(NSDictionary *)video {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _video = [video copy];
        _info = @{};
        _related = [NSMutableArray array];
    }
    return self;
}

- (NSString *)channelId {
    return self.info[@"channelId"] ?: self.video[@"channelId"];
}

- (NSString *)author {
    return self.info[@"author"] ?: self.video[@"author"];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = YTBackgroundColor();
    [YTStore addToHistory:self.video];

    self.playerController = [AVPlayerViewController new];
    [self addChildViewController:self.playerController];
    self.playerController.view.backgroundColor = UIColor.blackColor;
    [self.view addSubview:self.playerController.view];
    [self.playerController didMoveToParentViewController:self];

    self.messageLabel = [UILabel new];
    self.messageLabel.textColor = UIColor.whiteColor;
    self.messageLabel.font = [UIFont systemFontOfSize:14];
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.text = @"Загрузка…";
    self.messageLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.messageLabel.frame = self.playerController.contentOverlayView.bounds;
    [self.playerController.contentOverlayView addSubview:self.messageLabel];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.backgroundColor = YTBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self.tableView registerClass:YTVideoCell.class forCellReuseIdentifier:@"video"];
    [self.view addSubview:self.tableView];

    self.exitLandscapeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.exitLandscapeButton setTitle:@"⤡" forState:UIControlStateNormal];
    self.exitLandscapeButton.titleLabel.font = [UIFont systemFontOfSize:22];
    self.exitLandscapeButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    self.exitLandscapeButton.layer.cornerRadius = 20;
    self.exitLandscapeButton.hidden = YES;
    [self.exitLandscapeButton addTarget:self action:@selector(exitLandscape) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.exitLandscapeButton];

    [self updateBarButtons];
    [self buildHeader];
    [self loadStream];
    [self loadInfo];
}

- (void)buildHeader {
    self.headerView = [UIView new];

    self.titleLabel = [UILabel new];
    self.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.titleLabel.textColor = UIColor.whiteColor;
    self.titleLabel.numberOfLines = 0;
    [self.headerView addSubview:self.titleLabel];

    self.metaLabel = [UILabel new];
    self.metaLabel.font = [UIFont systemFontOfSize:12];
    self.metaLabel.textColor = YTSecondaryTextColor();
    [self.headerView addSubview:self.metaLabel];

    self.channelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.channelButton.tintColor = UIColor.whiteColor;
    self.channelButton.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.channelButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
    [self.channelButton addTarget:self action:@selector(openChannel) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.channelButton];

    self.subscribeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.subscribeButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.subscribeButton.layer.cornerRadius = 15;
    [self.subscribeButton addTarget:self action:@selector(toggleSubscription) forControlEvents:UIControlEventTouchUpInside];
    [self.headerView addSubview:self.subscribeButton];

    self.descriptionLabel = [UILabel new];
    self.descriptionLabel.font = [UIFont systemFontOfSize:13];
    self.descriptionLabel.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    self.descriptionLabel.userInteractionEnabled = YES;
    [self.descriptionLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleDescription)]];
    [self.headerView addSubview:self.descriptionLabel];
}

- (void)updateHeader {
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0) return;
    CGFloat textWidth = width - 24;

    self.titleLabel.text = self.info[@"title"] ?: self.video[@"title"];
    NSMutableArray *meta = [NSMutableArray array];
    NSString *views = self.info[@"views"] ?: self.video[@"views"];
    NSString *date = self.info[@"date"] ?: self.video[@"published"];
    if (views.length) [meta addObject:views];
    if (date.length) [meta addObject:date];
    self.metaLabel.text = [meta componentsJoinedByString:@" · "];

    [self.channelButton setTitle:[self author] ?: @"" forState:UIControlStateNormal];
    BOOL hasChannel = [self channelId].length > 0;
    self.channelButton.enabled = hasChannel;
    self.subscribeButton.hidden = !hasChannel;
    BOOL subscribed = hasChannel && [YTStore isSubscribed:[self channelId]];
    [self.subscribeButton setTitle:subscribed ? @"Вы подписаны" : @"Подписаться" forState:UIControlStateNormal];
    self.subscribeButton.backgroundColor = subscribed ? [UIColor colorWithWhite:0.2 alpha:1] : UIColor.whiteColor;
    self.subscribeButton.tintColor = subscribed ? UIColor.whiteColor : UIColor.blackColor;

    self.descriptionLabel.text = self.info[@"description"];
    self.descriptionLabel.numberOfLines = self.descriptionExpanded ? 0 : 3;

    CGFloat y = 12;
    CGSize titleSize = [self.titleLabel sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)];
    self.titleLabel.frame = CGRectMake(12, y, textWidth, ceil(titleSize.height));
    y = CGRectGetMaxY(self.titleLabel.frame) + 4;
    self.metaLabel.frame = CGRectMake(12, y, textWidth, 16);
    y += 16 + 8;

    CGFloat subscribeWidth = 124;
    self.subscribeButton.frame = CGRectMake(width - subscribeWidth - 12, y + 7, subscribeWidth, 30);
    self.channelButton.frame = CGRectMake(12, y, width - subscribeWidth - 36, 44);
    y += 44 + 4;

    if (self.descriptionLabel.text.length) {
        CGSize descriptionSize = [self.descriptionLabel sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)];
        self.descriptionLabel.frame = CGRectMake(12, y, textWidth, ceil(descriptionSize.height));
        y = CGRectGetMaxY(self.descriptionLabel.frame) + 12;
    } else {
        self.descriptionLabel.frame = CGRectZero;
    }

    self.headerView.frame = CGRectMake(0, 0, width, y);
    self.tableView.tableHeaderView = self.headerView; // reassigning makes the table pick up the new height
}

#pragma mark - Layout

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGRect bounds = self.view.bounds;
    BOOL landscape = bounds.size.width > bounds.size.height;
    self.exitLandscapeButton.hidden = !landscape;
    if (landscape) {
        self.playerController.view.frame = bounds;
        self.tableView.hidden = YES;
        // Left edge, vertically centred: clear of AVKit's own controls in the corners.
        self.exitLandscapeButton.frame = CGRectMake(8, bounds.size.height / 2 - 20, 40, 40);
        return;
    }
    CGFloat top = self.view.safeAreaInsets.top;
    CGFloat playerHeight = floor(bounds.size.width * 9 / 16);
    self.playerController.view.frame = CGRectMake(0, top, bounds.size.width, playerHeight);
    self.tableView.hidden = NO;
    CGFloat tableTop = top + playerHeight;
    CGRect tableFrame = CGRectMake(0, tableTop, bounds.size.width, bounds.size.height - tableTop);
    if (!CGRectEqualToRect(self.tableView.frame, tableFrame)) {
        self.tableView.frame = tableFrame;
        [self updateHeader];
    }
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    // Landscape = the video takes the whole screen.
    [self.navigationController setNavigationBarHidden:size.width > size.height animated:YES];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // AVKit's own fullscreen also triggers this, but then we are still the top controller.
    if (self.navigationController.topViewController != self) {
        [self.playerController.player pause];
        // The lists behind this screen are portrait layouts; don't leave them sideways.
        if (self.view.bounds.size.width > self.view.bounds.size.height) [self exitLandscape];
        [self.navigationController setNavigationBarHidden:NO animated:animated];
    }
}

#pragma mark - Loading

- (void)loadStream {
    __weak PlayerController *weakSelf = self;
    [YTAPI stream:self.video[@"id"] completion:^(NSURL *url, NSDictionary *details, NSError *error) {
        PlayerController *controller = weakSelf;
        if (!controller) return;
        if (!url) {
            controller.messageLabel.text = error.localizedDescription ?: @"Не удалось загрузить видео";
            return;
        }
        controller.messageLabel.hidden = YES;
        AVPlayer *player = [AVPlayer playerWithURL:url];
        controller.playerController.player = player;
        // Don't start playing if the user already left this screen.
        if (controller.navigationController.topViewController == controller) [player play];
    }];
}

- (void)loadInfo {
    __weak PlayerController *weakSelf = self;
    [YTAPI watch:self.video[@"id"] continuation:nil completion:^(NSDictionary *info, NSArray<NSDictionary *> *videos, NSString *continuation, NSError *error) {
        PlayerController *controller = weakSelf;
        if (!controller || error) return;
        controller.info = info ?: @{};
        controller.continuation = continuation;
        [controller.related addObjectsFromArray:videos];
        [controller updateHeader];
        [controller.tableView reloadData];
    }];
}

- (void)loadMoreRelated {
    if (self.loadingMore || !self.continuation) return;
    self.loadingMore = YES;
    __weak PlayerController *weakSelf = self;
    [YTAPI watch:nil continuation:self.continuation completion:^(NSDictionary *info, NSArray<NSDictionary *> *videos, NSString *continuation, NSError *error) {
        PlayerController *controller = weakSelf;
        if (!controller) return;
        controller.loadingMore = NO;
        controller.continuation = error ? nil : continuation;
        if (videos.count) {
            [controller.related addObjectsFromArray:videos];
            [controller.tableView reloadData];
        }
    }];
}

#pragma mark - Actions

- (void)toggleDescription {
    self.descriptionExpanded = !self.descriptionExpanded;
    [self updateHeader];
}

- (void)toggleSubscription {
    NSString *channelId = [self channelId];
    if (!channelId.length) return;
    BOOL subscribe = ![YTStore isSubscribed:channelId];
    [YTStore setSubscribed:subscribe channelId:channelId title:[self author]];
    [self updateHeader];
    // With an account the subscription is also made for real; the local list works either way.
    if ([YTAuth isLoggedIn]) [YTAPI setSubscribed:subscribe channelId:channelId completion:^(NSError *error) {}];
}

- (void)toggleLike {
    self.liked = !self.liked;
    BOOL liked = self.liked;
    [self updateBarButtons];
    __weak PlayerController *weakSelf = self;
    [YTAPI setLiked:liked videoId:self.video[@"id"] completion:^(NSError *error) {
        PlayerController *controller = weakSelf;
        if (!controller || !error || controller.liked != liked) return;
        controller.liked = !liked; // the server refused, roll the button back
        [controller updateBarButtons];
    }];
}

- (void)updateBarButtons {
    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[[UIBarButtonItem alloc] initWithTitle:@"⤢" style:UIBarButtonItemStylePlain target:self action:@selector(enterLandscape)]];
    if ([YTAuth isLoggedIn]) {
        UIBarButtonItem *like = [[UIBarButtonItem alloc] initWithTitle:@"👍" style:UIBarButtonItemStylePlain target:self action:@selector(toggleLike)];
        // Emoji ignore tint, so the liked state is shown with a prefix instead.
        if (self.liked) like.title = @"✓👍";
        [items addObject:like];
    }
    self.navigationItem.rightBarButtonItems = items;
}

#pragma mark - Rotation

// Rotates the interface by hand, so fullscreen also works with the rotation lock switched on.
- (void)forceOrientation:(UIInterfaceOrientation)orientation {
    [[UIDevice currentDevice] setValue:@(orientation) forKey:@"orientation"];
    [UIViewController attemptRotationToDeviceOrientation];
}

- (void)enterLandscape {
    [self forceOrientation:UIInterfaceOrientationLandscapeRight];
}

- (void)exitLandscape {
    [self forceOrientation:UIInterfaceOrientationPortrait];
}

- (void)openChannel {
    NSString *channelId = [self channelId];
    if (!channelId.length) return;
    VideoListController *channel = [VideoListController new];
    channel.title = [self author];
    channel.emptyText = @"На канале нет видео";
    channel.hidesBottomBarWhenPushed = YES;
    channel.loader = ^(NSString *continuation, YTListBlock done) {
        [YTAPI channel:channelId continuation:continuation completion:done];
    };
    [self.navigationController pushViewController:channel animated:YES];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.related.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [YTVideoCell heightForWidth:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    YTVideoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"video" forIndexPath:indexPath];
    [cell configureWithVideo:self.related[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row + 4 >= (NSInteger)self.related.count) [self loadMoreRelated];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // Replace this player instead of stacking: a chain of paused players would eat the 5s's memory.
    [self.playerController.player pause];
    PlayerController *next = [[PlayerController alloc] initWithVideo:self.related[indexPath.row]];
    next.hidesBottomBarWhenPushed = YES;
    NSMutableArray *stack = [self.navigationController.viewControllers mutableCopy];
    [stack removeLastObject];
    [stack addObject:next];
    [self.navigationController setViewControllers:stack animated:YES];
}

@end
