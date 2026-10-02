#import "VideoListController.h"
#import "PlayerController.h"
#import "YTUI.h"

@interface VideoListController ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *videos;
@property (nonatomic, strong) NSMutableSet<NSString *> *seenIds;
@property (nonatomic, copy) NSString *continuation;
@property (nonatomic, assign) BOOL loading;
@property (nonatomic, assign) NSUInteger generation; // bumped on reload so stale responses are dropped
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation VideoListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.videos = [NSMutableArray array];
    self.seenIds = [NSMutableSet set];
    self.view.backgroundColor = YTBackgroundColor();
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [self.tableView registerClass:YTVideoCell.class forCellReuseIdentifier:@"video"];

    self.refreshControl = [UIRefreshControl new];
    self.refreshControl.tintColor = UIColor.whiteColor;
    [self.refreshControl addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];

    self.statusLabel = [UILabel new];
    self.statusLabel.textColor = YTSecondaryTextColor();
    self.statusLabel.font = [UIFont systemFontOfSize:15];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;

    [self reload];
}

- (void)setStatus:(NSString *)text {
    self.statusLabel.text = text;
    self.tableView.backgroundView = text.length ? self.statusLabel : nil;
}

- (void)reload {
    self.generation++;
    self.loading = NO;
    self.continuation = nil;
    [self.videos removeAllObjects];
    [self.seenIds removeAllObjects];
    [self.tableView reloadData];
    if (!self.loader) {
        [self.refreshControl endRefreshing];
        [self setStatus:self.emptyText];
        return;
    }
    [self setStatus:@"Загрузка…"];
    [self loadPage];
}

- (void)loadPage {
    if (self.loading || !self.loader) return;
    self.loading = YES;
    NSUInteger generation = self.generation;
    BOOL firstPage = self.continuation == nil;
    __weak VideoListController *weakSelf = self;
    self.loader(self.continuation, ^(NSArray<NSDictionary *> *videos, NSString *continuation, NSError *error) {
        VideoListController *controller = weakSelf;
        if (!controller || controller.generation != generation) return;
        controller.loading = NO;
        [controller.refreshControl endRefreshing];
        controller.continuation = continuation;
        for (NSDictionary *video in videos) {
            NSString *videoId = video[@"id"];
            if (!videoId || [controller.seenIds containsObject:videoId]) continue;
            [controller.seenIds addObject:videoId];
            [controller.videos addObject:video];
        }
        [controller.tableView reloadData];
        if (controller.videos.count) {
            [controller setStatus:nil];
        } else if (error) {
            [controller setStatus:[NSString stringWithFormat:@"Ошибка: %@\n\nПотяни вниз, чтобы повторить", error.localizedDescription]];
        } else if (firstPage) {
            [controller setStatus:controller.emptyText ?: @"Ничего не найдено"];
        }
    });
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.videos.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [YTVideoCell heightForWidth:tableView.bounds.size.width];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    YTVideoCell *cell = [tableView dequeueReusableCellWithIdentifier:@"video" forIndexPath:indexPath];
    [cell configureWithVideo:self.videos[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (self.continuation && indexPath.row + 4 >= (NSInteger)self.videos.count) [self loadPage];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PlayerController *player = [[PlayerController alloc] initWithVideo:self.videos[indexPath.row]];
    player.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:player animated:YES];
}

@end
