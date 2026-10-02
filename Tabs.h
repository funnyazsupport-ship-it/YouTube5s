#import "VideoListController.h"

// Recommendations: related to the last watched video, or a generic search on first launch.
@interface HomeController : VideoListController
@end

@interface SearchController : VideoListController
@end

@interface HistoryController : VideoListController
@end

@interface SubscriptionsController : UITableViewController
@end
