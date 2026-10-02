#import <UIKit/UIKit.h>
#import "YTAPI.h"

// continuation is nil for the first page.
typedef void (^YTListLoader)(NSString *continuation, YTListBlock done);

// A paged list of videos; every tab and the channel page are built on it.
@interface VideoListController : UITableViewController
@property (nonatomic, copy) YTListLoader loader;
@property (nonatomic, copy) NSString *emptyText;
- (void)reload;
@end
