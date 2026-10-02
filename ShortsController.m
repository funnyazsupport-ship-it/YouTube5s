#import "ShortsController.h"
#import <AVFoundation/AVFoundation.h>
#import "VideoListController.h"
#import "YTAPI.h"
#import "YTAuth.h"
#import "YTUI.h"

#pragma mark - Cell

static UILabel *YTOverlayLabel(UIFont *font, NSInteger lines) {
    UILabel *label = [UILabel new];
    label.font = font;
    label.textColor = UIColor.whiteColor;
    label.numberOfLines = lines;
    // Text sits directly on top of the video, the shadow keeps it readable on bright frames.
    label.layer.shadowColor = UIColor.blackColor.CGColor;
    label.layer.shadowOpacity = 0.8;
    label.layer.shadowRadius = 2;
    label.layer.shadowOffset = CGSizeMake(0, 1);
    return label;
}

@interface ShortCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *thumbView;
@property (nonatomic, strong) UIView *videoView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *statusLabel; // pause glyph or error text
@property (nonatomic, strong) UILabel *authorLabel;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, copy) void (^onAuthor)(void);
@end

@implementation ShortCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        UIView *content = self.contentView;
        content.backgroundColor = UIColor.blackColor;

        _thumbView = [UIImageView new];
        _thumbView.contentMode = UIViewContentModeScaleAspectFit;
        [content addSubview:_thumbView];
        _videoView = [UIView new];
        [content addSubview:_videoView];

        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        _spinner.hidesWhenStopped = YES;
        [content addSubview:_spinner];

        _statusLabel = YTOverlayLabel([UIFont systemFontOfSize:15], 0);
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        [content addSubview:_statusLabel];

        _authorLabel = YTOverlayLabel([UIFont boldSystemFontOfSize:15], 1);
        _authorLabel.userInteractionEnabled = YES;
        [_authorLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(authorTapped)]];
        [content addSubview:_authorLabel];
        _titleLabel = YTOverlayLabel([UIFont systemFontOfSize:14], 3);
        [content addSubview:_titleLabel];

        [content addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    }
    return self;
}

- (void)tapped {
    if (self.onTap) self.onTap();
}

- (void)authorTapped {
    if (self.onAuthor) self.onAuthor();
}

- (void)setDetails:(NSDictionary *)details {
    NSString *author = details[@"author"];
    self.authorLabel.text = author.length ? [@"@" stringByAppendingString:author] : nil;
    self.titleLabel.text = details[@"title"];
    [self setNeedsLayout];
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // A player layer left over from the previous video must not show up on a recycled cell.
    for (CALayer *layer in [self.videoView.layer.sublayers copy]) [layer removeFromSuperlayer];
    self.statusLabel.text = nil;
    [self.spinner stopAnimating];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    CGFloat width = bounds.size.width, height = bounds.size.height;
    self.thumbView.frame = bounds;
    self.videoView.frame = bounds;
    for (CALayer *layer in self.videoView.layer.sublayers) layer.frame = bounds;
    self.spinner.center = CGPointMake(width / 2, height / 2);
    self.statusLabel.frame = CGRectMake(30, height / 2 - 50, width - 60, 100);

    CGFloat textWidth = width - 24;
    CGFloat titleHeight = self.titleLabel.text.length ? ceil([self.titleLabel sizeThatFits:CGSizeMake(textWidth, CGFLOAT_MAX)].height) : 0;
    CGFloat y = height - 14 - titleHeight;
    self.titleLabel.frame = CGRectMake(12, y, textWidth, titleHeight);
    self.authorLabel.frame = CGRectMake(12, y - 26, textWidth, 22);
}

@end

#pragma mark - Shorts feed

@interface ShortsController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (nonatomic, strong) UICollectionView *collectionView;
@property (nonatomic, strong) UICollectionViewFlowLayout *layout;
@property (nonatomic, strong) UILabel *messageLabel;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *items;
@property (nonatomic, strong) NSMutableSet<NSString *> *seenIds;
// id -> {url, details}; filled when a stream is resolved, also ahead of time for the next video
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *streams;
@property (nonatomic, copy) NSString *continuation;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) BOOL visible;
@property (nonatomic, assign) BOOL userPaused;
@property (nonatomic, assign) BOOL didLayout;
@property (nonatomic, assign) NSInteger currentIndex;
@property (nonatomic, copy) NSString *currentId; // nil until something has been started
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@end

@implementation ShortsController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    self.items = [NSMutableArray array];
    self.seenIds = [NSMutableSet set];
    self.streams = [NSMutableDictionary dictionary];

    self.layout = [UICollectionViewFlowLayout new];
    self.layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    self.layout.minimumLineSpacing = 0;
    self.layout.minimumInteritemSpacing = 0;

    self.collectionView = [[UICollectionView alloc] initWithFrame:self.view.bounds collectionViewLayout:self.layout];
    self.collectionView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.collectionView.backgroundColor = UIColor.blackColor;
    self.collectionView.pagingEnabled = YES;
    self.collectionView.showsVerticalScrollIndicator = NO;
    self.collectionView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    [self.collectionView registerClass:ShortCell.class forCellWithReuseIdentifier:@"short"];
    [self.view addSubview:self.collectionView];

    self.messageLabel = [UILabel new];
    self.messageLabel.frame = CGRectInset(self.view.bounds, 24, 0);
    self.messageLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.messageLabel.textColor = YTSecondaryTextColor();
    self.messageLabel.font = [UIFont systemFontOfSize:15];
    self.messageLabel.textAlignment = NSTextAlignmentCenter;
    self.messageLabel.numberOfLines = 0;
    self.messageLabel.userInteractionEnabled = YES;
    [self.messageLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(loadMore)]];
    self.messageLabel.hidden = YES;
    [self.view addSubview:self.messageLabel];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appBecameActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [self loadMore];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize size = self.collectionView.bounds.size;
    if (size.height <= 0 || CGSizeEqualToSize(size, self.layout.itemSize)) return;
    // One page = one screen. Re-anchor to the current video because the offsets changed.
    self.layout.itemSize = size;
    [self.layout invalidateLayout];
    [self.collectionView layoutIfNeeded];
    self.collectionView.contentOffset = CGPointMake(0, self.currentIndex * size.height);
    self.didLayout = YES;
    [self startIfNeeded];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.visible = YES;
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    if (self.player && !self.userPaused) [self.player play];
    [self startIfNeeded];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.visible = NO;
    [self.player pause];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)appBecameActive {
    if (self.visible && self.player && !self.userPaused) [self.player play];
}

- (void)showMessage:(NSString *)text {
    self.messageLabel.text = text;
    self.messageLabel.hidden = text.length == 0;
}

#pragma mark - Loading

- (void)loadMore {
    if (self.loading) return;
    self.loading = YES;
    if (!self.items.count) [self showMessage:@"Загрузка Shorts…"];
    __weak ShortsController *weakSelf = self;
    [YTAPI shorts:self.continuation completion:^(NSArray<NSDictionary *> *videos, NSString *continuation, NSError *error) {
        ShortsController *controller = weakSelf;
        if (!controller) return;
        controller.loading = NO;
        if (continuation) controller.continuation = continuation;
        NSUInteger before = controller.items.count;
        for (NSDictionary *video in videos) {
            NSString *videoId = video[@"id"];
            if ([controller.seenIds containsObject:videoId]) continue;
            [controller.seenIds addObject:videoId];
            [controller.items addObject:video];
        }
        if (controller.items.count == 0) {
            [controller showMessage:[NSString stringWithFormat:@"Не удалось загрузить Shorts\n%@\n\nНажми, чтобы повторить", error.localizedDescription ?: @""]];
            return;
        }
        [controller showMessage:nil];
        if (before == 0) {
            [controller.collectionView reloadData];
            [controller.collectionView layoutIfNeeded];
        } else if (controller.items.count != before) {
            // Insert instead of reloadData: a reload would recycle the cell that is playing right now.
            NSMutableArray<NSIndexPath *> *paths = [NSMutableArray array];
            for (NSUInteger i = before; i < controller.items.count; i++) [paths addObject:[NSIndexPath indexPathForItem:i inSection:0]];
            [controller.collectionView insertItemsAtIndexPaths:paths];
        }
        [controller startIfNeeded];
        // The very first request returns a single video; fetch the rest of the feed right away.
        if (controller.items.count < 3 && continuation) [controller loadMore];
    }];
}

- (void)startIfNeeded {
    if (self.currentId || !self.visible || !self.didLayout || !self.items.count) return;
    [self playIndex:self.currentIndex];
}

// Resolves and remembers the stream for an item; completion may run synchronously on a cache hit.
- (void)resolveIndex:(NSInteger)index completion:(void (^)(NSDictionary *stream, NSError *error))completion {
    if (index < 0 || index >= (NSInteger)self.items.count) return;
    NSString *videoId = self.items[index][@"id"];
    NSDictionary *cached = self.streams[videoId];
    if (cached) { if (completion) completion(cached, nil); return; }
    __weak ShortsController *weakSelf = self;
    [YTAPI stream:videoId completion:^(NSURL *url, NSDictionary *details, NSError *error) {
        ShortsController *controller = weakSelf;
        if (!controller) return;
        NSDictionary *stream = url ? @{@"url": url, @"details": details ?: @{}} : nil;
        if (stream) controller.streams[videoId] = stream;
        if (completion) completion(stream, error);
    }];
}

#pragma mark - Playback

- (ShortCell *)cellAtIndex:(NSInteger)index {
    return (ShortCell *)[self.collectionView cellForItemAtIndexPath:[NSIndexPath indexPathForItem:index inSection:0]];
}

- (void)stopPlayback {
    if (self.player.currentItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem];
    }
    [self.player pause];
    [self.playerLayer removeFromSuperlayer];
    self.player = nil;
    self.playerLayer = nil;
}

- (void)playIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.items.count) return;
    [self stopPlayback];
    self.currentIndex = index;
    self.userPaused = NO;
    NSString *videoId = self.items[index][@"id"];
    self.currentId = videoId;

    ShortCell *cell = [self cellAtIndex:index];
    cell.statusLabel.text = nil;
    [cell.spinner startAnimating];

    __weak ShortsController *weakSelf = self;
    [self resolveIndex:index completion:^(NSDictionary *stream, NSError *error) {
        ShortsController *controller = weakSelf;
        // The user may have swiped on while the stream was being resolved.
        if (!controller || ![controller.currentId isEqualToString:videoId]) return;
        ShortCell *current = [controller cellAtIndex:index];
        [current.spinner stopAnimating];
        if (!stream) {
            current.statusLabel.text = error.localizedDescription ?: @"Видео недоступно";
            return;
        }
        [current setDetails:stream[@"details"]];
        [controller startPlayerWithURL:stream[@"url"] inCell:current];
    }];

    // Resolve the next stream ahead of time so the swipe starts playing sooner.
    [self resolveIndex:index + 1 completion:nil];
    if (index + 4 >= (NSInteger)self.items.count) [self loadMore];
}

- (void)startPlayerWithURL:(NSURL *)url inCell:(ShortCell *)cell {
    if (!cell) return;
    AVPlayerItem *playerItem = [AVPlayerItem playerItemWithURL:url];
    self.player = [AVPlayer playerWithPlayerItem:playerItem];
    self.player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(itemEnded:) name:AVPlayerItemDidPlayToEndTimeNotification object:playerItem];

    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.playerLayer.frame = cell.videoView.bounds;
    [cell.videoView.layer addSublayer:self.playerLayer];
    if (self.visible) [self.player play];
}

- (void)itemEnded:(NSNotification *)notification {
    // Loop, like Shorts do.
    [self.player seekToTime:kCMTimeZero];
    if (self.visible && !self.userPaused) [self.player play];
}

- (void)togglePause {
    if (!self.player) return;
    self.userPaused = !self.userPaused;
    ShortCell *cell = [self cellAtIndex:self.currentIndex];
    if (self.userPaused) {
        [self.player pause];
        cell.statusLabel.text = @"❚❚";
    } else {
        [self.player play];
        cell.statusLabel.text = nil;
    }
}

- (void)openAuthorAtIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)self.items.count) return;
    NSDictionary *details = self.streams[self.items[index][@"id"]][@"details"];
    NSString *channelId = details[@"channelId"];
    if (!channelId.length) return;
    VideoListController *channel = [VideoListController new];
    channel.title = details[@"author"];
    channel.emptyText = @"На канале нет видео";
    channel.hidesBottomBarWhenPushed = YES;
    channel.loader = ^(NSString *continuation, YTListBlock done) {
        [YTAPI channel:channelId continuation:continuation completion:done];
    };
    [self.navigationController pushViewController:channel animated:YES];
}

#pragma mark - Collection view

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.items.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    ShortCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"short" forIndexPath:indexPath];
    NSDictionary *item = self.items[indexPath.item];
    [cell.thumbView yt_setImageURL:item[@"thumb"]];
    [cell setDetails:self.streams[item[@"id"]][@"details"]];
    NSInteger index = indexPath.item;
    __weak ShortsController *weakSelf = self;
    cell.onTap = ^{ [weakSelf togglePause]; };
    cell.onAuthor = ^{ [weakSelf openAuthorAtIndex:index]; };
    return cell;
}

- (void)pageSettled {
    CGFloat height = self.collectionView.bounds.size.height;
    if (height <= 0) return;
    NSInteger index = (NSInteger)lround(self.collectionView.contentOffset.y / height);
    if (index != self.currentIndex || !self.currentId) [self playIndex:index];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [self pageSettled];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (!decelerate) [self pageSettled];
}

@end

#pragma mark - Account

@interface AccountController ()
@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, strong) UILabel *codeLabel;
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, assign) BOOL waiting;
@end

@implementation AccountController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Аккаунт";
    self.view.backgroundColor = YTBackgroundColor();

    self.textLabel = [UILabel new];
    self.textLabel.textColor = UIColor.whiteColor;
    self.textLabel.font = [UIFont systemFontOfSize:16];
    self.textLabel.textAlignment = NSTextAlignmentCenter;
    self.textLabel.numberOfLines = 0;
    [self.view addSubview:self.textLabel];

    self.codeLabel = [UILabel new];
    self.codeLabel.textColor = UIColor.whiteColor;
    self.codeLabel.font = [UIFont monospacedDigitSystemFontOfSize:34 weight:UIFontWeightBold];
    self.codeLabel.textAlignment = NSTextAlignmentCenter;
    self.codeLabel.adjustsFontSizeToFitWidth = YES;
    [self.view addSubview:self.codeLabel];

    self.button = [UIButton buttonWithType:UIButtonTypeSystem];
    self.button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.button.backgroundColor = UIColor.whiteColor;
    self.button.tintColor = UIColor.blackColor;
    self.button.layer.cornerRadius = 22;
    [self.button addTarget:self action:@selector(buttonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.button];

    [self showIdle];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    CGFloat width = self.view.bounds.size.width;
    CGFloat top = self.view.safeAreaInsets.top + 30;
    self.textLabel.frame = CGRectMake(20, top, width - 40, 150);
    self.codeLabel.frame = CGRectMake(20, top + 160, width - 40, 50);
    self.button.frame = CGRectMake((width - 220) / 2, top + 240, 220, 44);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (self.waiting && self.isMovingFromParentViewController) [YTAuth cancelLogin];
}

- (void)showIdle {
    self.waiting = NO;
    self.codeLabel.text = nil;
    if ([YTAuth isLoggedIn]) {
        self.textLabel.text = @"Ты вошёл в аккаунт Google.\n\nГлавная показывает твои рекомендации, в «Подписках» есть лента подписок, лайки и подписки ставятся по-настоящему.";
        [self.button setTitle:@"Выйти" forState:UIControlStateNormal];
    } else {
        self.textLabel.text = @"Вход нужен для своих рекомендаций, ленты подписок и лайков.\n\nПароль в этом приложении вводить не придётся.";
        [self.button setTitle:@"Войти" forState:UIControlStateNormal];
    }
}

- (void)buttonTapped {
    if (self.waiting) {
        [YTAuth cancelLogin];
        [self showIdle];
        return;
    }
    if ([YTAuth isLoggedIn]) {
        [YTAuth logout];
        [self showIdle];
        return;
    }
    self.waiting = YES;
    self.textLabel.text = @"Получаю код…";
    [self.button setTitle:@"Отмена" forState:UIControlStateNormal];
    __weak AccountController *weakSelf = self;
    [YTAuth startLogin:^(NSString *code, NSString *verificationURL) {
        AccountController *controller = weakSelf;
        if (!controller) return;
        NSString *address = [verificationURL stringByReplacingOccurrencesOfString:@"https://www." withString:@""];
        controller.textLabel.text = [NSString stringWithFormat:@"На компьютере или другом телефоне открой\n\n%@\n\nвойди в Google и введи код:", address];
        controller.codeLabel.text = code;
    } finished:^(NSError *error) {
        AccountController *controller = weakSelf;
        if (!controller) return;
        [controller showIdle];
        if (error) controller.textLabel.text = [NSString stringWithFormat:@"%@\n\nНажми «Войти», чтобы попробовать снова.", error.localizedDescription];
    }];
}

@end
