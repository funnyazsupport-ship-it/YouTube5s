#import "Tabs.h"
#import "ShortsController.h"
#import "YTAuth.h"
#import "YTStore.h"
#import "YTUI.h"

#pragma mark - Home

@implementation HomeController

- (void)viewDidLoad {
    self.title = @"YouTube";
    self.emptyText = @"Лента пуста. Потяни вниз, чтобы обновить";
    // Without a Google account YouTube returns an empty home feed, so recommendations are
    // built from what was watched last on this phone.
    self.loader = ^(NSString *continuation, YTListBlock done) {
        if ([YTAuth isLoggedIn]) {
            // Signed in: the account's real recommendations.
            [YTAPI accountFeed:@"FEwhat_to_watch" continuation:continuation completion:done];
            return;
        }
        NSString *lastId = [YTStore history].firstObject[@"id"];
        if (lastId) {
            [YTAPI watch:lastId continuation:continuation completion:^(NSDictionary *info, NSArray<NSDictionary *> *videos, NSString *next, NSError *error) {
                done(videos, next, error);
            }];
        } else {
            [YTAPI search:@"популярное сегодня" continuation:continuation completion:done];
        }
    };
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Аккаунт" style:UIBarButtonItemStylePlain target:self action:@selector(openAccount)];
    // The feed source depends on the login state.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reload) name:YTAuthDidChangeNotification object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)openAccount {
    AccountController *account = [AccountController new];
    account.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:account animated:YES];
}

@end

#pragma mark - Search

@interface SearchController () <UISearchBarDelegate>
@property (nonatomic, strong) UISearchBar *searchBar;
@end

@implementation SearchController

- (void)viewDidLoad {
    self.emptyText = @"Введи запрос";
    [super viewDidLoad];
    self.searchBar = [UISearchBar new];
    self.searchBar.placeholder = @"Поиск на YouTube";
    self.searchBar.delegate = self;
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.keyboardAppearance = UIKeyboardAppearanceDark;
    self.navigationItem.titleView = self.searchBar;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *query = [searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!query.length) return;
    self.emptyText = @"Ничего не найдено";
    self.loader = ^(NSString *continuation, YTListBlock done) {
        [YTAPI search:query continuation:continuation completion:done];
    };
    [self reload];
}

@end

#pragma mark - History

@implementation HistoryController

- (void)viewDidLoad {
    self.title = @"История";
    self.emptyText = @"Здесь появятся просмотренные видео";
    self.loader = ^(NSString *continuation, YTListBlock done) {
        done([YTStore history], nil, nil);
    };
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Очистить" style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)clear {
    [YTStore clearHistory];
    [self reload];
}

@end

#pragma mark - Subscriptions

@interface SubscriptionsController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *channels;
@end

@implementation SubscriptionsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Подписки";
    self.view.backgroundColor = YTBackgroundColor();
    self.tableView.separatorColor = [UIColor colorWithWhite:0.2 alpha:1];
    self.tableView.tableFooterView = [UIView new];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.channels = [YTStore subscriptions];
    [self.tableView reloadData];
    // The combined feed of new videos exists only for a signed-in account.
    self.navigationItem.rightBarButtonItem = [YTAuth isLoggedIn]
        ? [[UIBarButtonItem alloc] initWithTitle:@"Лента" style:UIBarButtonItemStylePlain target:self action:@selector(openFeed)]
        : nil;
    if (self.channels.count) {
        self.tableView.backgroundView = nil;
    } else {
        UILabel *label = [UILabel new];
        label.text = @"Подписок пока нет.\nНажми «Подписаться» под любым видео";
        label.textColor = YTSecondaryTextColor();
        label.font = [UIFont systemFontOfSize:15];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        self.tableView.backgroundView = label;
    }
}

- (void)openFeed {
    VideoListController *feed = [VideoListController new];
    feed.title = @"Лента подписок";
    feed.emptyText = @"В подписках пока нет видео";
    feed.loader = ^(NSString *continuation, YTListBlock done) {
        [YTAPI accountFeed:@"FEsubscriptions" continuation:continuation completion:done];
    };
    [self.navigationController pushViewController:feed animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.channels.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"channel"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"channel"];
        cell.backgroundColor = YTBackgroundColor();
        cell.textLabel.textColor = UIColor.whiteColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectedBackgroundView = [UIView new];
        cell.selectedBackgroundView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    }
    cell.textLabel.text = self.channels[indexPath.row][@"title"];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *channel = self.channels[indexPath.row];
    NSString *channelId = channel[@"id"];
    VideoListController *list = [VideoListController new];
    list.title = channel[@"title"];
    list.emptyText = @"На канале нет видео";
    list.loader = ^(NSString *continuation, YTListBlock done) {
        [YTAPI channel:channelId continuation:continuation completion:done];
    };
    [self.navigationController pushViewController:list animated:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (NSString *)tableView:(UITableView *)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
    return @"Отписаться";
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    NSDictionary *channel = self.channels[indexPath.row];
    [YTStore setSubscribed:NO channelId:channel[@"id"] title:channel[@"title"]];
    self.channels = [YTStore subscriptions];
    [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
}

@end
