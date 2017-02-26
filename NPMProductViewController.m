//
//  NPMProductViewController.m
//  PreciousMetals
//
//  Created by Liu Bing on 10/13/14.
//  Copyright (c) 2014 NetEase. All rights reserved.
//

#import "NPMProductViewController.h"
#import "LDPMTrendChartViewController.h"
@import MSWeakTimer;
#import "PmecGoodsDetail.h"
#import "NPMMarketInfoService.h"
#import "NPMMarketInfoViewModel.h"
#import "NPMRealTimeMarketInfo.h"
#import "PreciousMetals-Swift.h"
#import "NPMPushSettingViewController.h"
#import "FAOpenAccountStatusRoutes.h"
#import "NPMProductService.h"
#import "NPMDayMinTimeItem.h"
#import "NPMFullScreenTrendViewController.h"
#import "LDPMProductTransitionAnimator.h"
#import "UIViewController+NavBar.h"
#import "JLRoutes+Additions.h"
@import LDEventCollection;
@import LDRoutes;
#import "LDPMProductMarketPriceInfoView.h"
#import "LDPMToolBarInTradeView.h"
#import "LDPMAppABTestConfig.h"

static NSString *const normalTradeKey = @"normalTradeKey";
static NSInteger const marketUserGuideImageTag = 8899;

@interface NPMProductViewController ()<UIScrollViewDelegate, NPMTrendViewControllerDelegate, NPMFullScreenTrendViewControllerDelegate, UIViewControllerTransitioningDelegate, /*UIAlertViewDelegate,*/LDPMToolBarInTradeViewDelegate>

@property (nonatomic, strong) LDPMTrendChartViewController *trendChartViewController;
@property (nonatomic, strong) NPMFullScreenTrendViewController *fullScreenTrendViewController;
@property (nonatomic, strong,nonnull)   UIScrollView *scrollView;
@property (strong, nonatomic) LDPMProductMarketPriceInfoView *priceInfoView;
@property (strong, nonatomic) LDPMToolBarInTradeView *toolBarInTrade;

@property (assign, nonatomic) BOOL isNormalTrade;

@property (nonatomic, strong) NPMMarketInfoService *marketInfoService;

@property (nonatomic, strong) UIButton *refreshBtn;
@property (nonatomic, strong) UIBarButtonItem *refreshBtnItem;
@property (nonatomic, strong) UIBarButtonItem *negativeSpacer;
@property (nonatomic, strong) UIBarButtonItem *proDetailBtnItem;
@property (nonatomic, strong) UIBarButtonItem *proBtnItemNegativeSpacer;

@property (nonatomic,assign) BOOL socketAlive;

@property (nonatomic, strong) MSWeakTimer *timer;
@property (nonatomic, assign) BOOL timerAvailable;
@property (nonatomic, assign) BOOL lastTradeFlag;

@property (nonatomic, strong) UIView *colorfulView;

#pragma mark - 交易控制变量

@property (nonatomic,assign) BOOL enableTrade;
@property (nonatomic,assign) BOOL enableFastTrade;

@property (nonatomic, assign) UIDeviceOrientation orientation;

@end

@implementation NPMProductViewController

- (instancetype)init
{
    self = [super init];
    if (self) {
        _marketInfoService = [NPMMarketInfoService new];
        self.hidesBottomBarWhenPushed = YES;
    }
    
    return self;
}

- (void)updateLatestMarketInfo:(NPMRealTimeMarketInfo *)marketInfo
{
    self.title = [self.product screenName];
    
    NPMMarketInfoViewModel *viewModel = [NPMMarketInfoViewModel detailInfoViewModelWithData:marketInfo];
    if ([marketInfo.tradeFlag boolValue]) {
        self.navBarColor = viewModel.changeColor;
    } else {
        self.navBarColor = [UIColor colorWithRGB:0x828693];
    }
    
    if (marketInfo.tradeFlag.boolValue) {
        self.colorfulView.backgroundColor = viewModel.changeColor;
    } else {
        self.colorfulView.backgroundColor = [UIColor colorWithRGB:0x828693];
    }
    if ([marketInfo.tradeFlag boolValue] != self.lastTradeFlag) {
        [self setupRightBarButtonItems];
        self.lastTradeFlag = [marketInfo.tradeFlag boolValue];
    }
    [self.priceInfoView updateLatestMarketInfo:marketInfo];
}

#pragma mark -- life Cycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if ([self.product.partnerId isEqualToString:NPMPartnerIDNanJiaoSuo]) {
        [LDPMUserEvent addEvent:EVENT_PRODUCT_PRODUCT_NAME_NJS tag:self.product.screenName];
    } else if ([self.product.partnerId isEqualToString:NPMPartnerIDShangJiaoSuo]) {
        [LDPMUserEvent addEvent:EVENT_PRODUCT_PRODUCT_NAME_SGE tag:self.product.screenName];
    } else if ([self.product.partnerId isEqualToString:NPMPartnerIDGuangGuiZhongXin]) {
        [LDPMUserEvent addEvent:EVENT_PRODUCT_PRODUCT_NAME_PMEC tag:self.product.screenName];
    }
    
    // 处理商品的 enableTrade 状态
    self.enableTrade = (self.product.normalTradeBuyURL && self.product.normalTradeSellURL);
    self.enableFastTrade = (self.product.fastTradeBuyURL && self.product.fastTradeSellURL);
    
    self.lastTradeFlag = [self.marketInfo.tradeFlag boolValue];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    NSString *valueStr = [[NSUserDefaults standardUserDefaults] stringForKey:normalTradeKey];
    self.isNormalTrade = valueStr == nil ? YES : [valueStr boolValue];
    
    //现货商品不支持快速买卖
    if (!self.enableFastTrade) {
        self.isNormalTrade = YES;
    }
    
    [self initScrollView];
    [self setupRightBarButtonItems];
    [self initToolBar];
    
    self.title = [self.product screenName];
    
    [self.scrollView.mj_header beginRefreshing];
    [self checkSocketPushClientStatus];
    
    [self updateLatestMarketInfo:self.marketInfo];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkSocketPushClientStatus) name:LDSPClientStatusChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardDidShow:) name:UIKeyboardDidShowNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.timerAvailable = YES;
    //启动5秒刷新
    [self startTimer];
    [self subscribeRealTimeMarkInfo];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    NSString *key = [NSString stringWithFormat:@"%@marketguide", NSStringFromClass(self.class)];
    
    if (![[NSUserDefaults standardUserDefaults] boolForKey:key] && !self.isPreviewing) {
        [self showUserGuideView];
    }
    
    for (id obj in self.navigationController.navigationBar.subviews) {
        if ([obj isKindOfClass:[UIActivityIndicatorView class]]) {
            [obj removeFromSuperview];
        }
    }
    
    if (!self.isPreviewing) {
        [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deviceOrientationDidChange) name:UIDeviceOrientationDidChangeNotification object:nil];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.timerAvailable = NO;
    [self stopTimer];
    
    [self unsubscribeRealTimeMarkInfo];
    
    // 防止产品页在获取数据时(rightBarButtonItem 为菊花转时)拖拽返回, 导致整个导航栏的 rightBarButtonItem 错乱
    [self.refreshBtnItem setCustomView:self.refreshBtn];
    
    [self userGuideTapGesture];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    self.timerAvailable = NO;
    if (!self.isPreviewing) {
        [[UIDevice currentDevice] endGeneratingDeviceOrientationNotifications];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _scrollView.delegate = nil;
}

#pragma mark - Views
/**
 *  初始化tableview
 */
- (void)initScrollView
{
    //设置toolbar的高度
    CGFloat toolBarHeight = self.enableTrade? 49.0f :0.0f;
    CGRect rect = CGRectMake(0, 0, CGRectGetWidth(self.view.frame), CGRectGetHeight(self.view.frame) - toolBarHeight);
    self.scrollView = [[UIScrollView alloc] initWithFrame:rect];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.scrollView];
    
    //下拉刷新
    __weak typeof(self) weakSelf = self;
    self.scrollView.mj_header = [LDPMTableViewHeader headerWithRefreshingBlock:^{
        [weakSelf refreshData:@"下拉刷新"];
    }];
    ((LDPMTableViewHeader *)self.scrollView.mj_header).style = LDPMTableViewHeaderStyleWhite;
    self.scrollView.mj_header.backgroundColor = [UIColor clearColor];
    
    //下拉背景色，需放在mj_header下面
    self.colorfulView = [[UIView alloc] initWithFrame:CGRectMake(0, -SCREEN_HEIGHT, SCREEN_WIDTH, SCREEN_HEIGHT)];
    [self.scrollView insertSubview:self.colorfulView atIndex:0];
    self.colorfulView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;
    
    //实时价格区域
    CGFloat priceInfoViewHeight = ([[UIScreen mainScreen] bounds].size.height <= 568.0f) ? 91.0 : 116.0;
    self.priceInfoView = [[LDPMProductMarketPriceInfoView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.scrollView.frame), priceInfoViewHeight)];
    self.priceInfoView.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;
    [self.scrollView addSubview:self.priceInfoView];
    
    //行情图区域
    self.trendChartViewController = [[LDPMTrendChartViewController alloc] initWithProduct:self.product];
    self.trendChartViewController.isLandscape = NO;
    self.trendChartViewController.delegate = self;
    self.trendChartViewController.view.backgroundColor = [UIColor colorWithRGB:0xffffff];
    self.trendChartViewController.view.frame = CGRectMake(0, priceInfoViewHeight, CGRectGetWidth(self.scrollView.frame), CGRectGetHeight(self.scrollView.frame)-priceInfoViewHeight);
    self.trendChartViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self addChildViewController:self.trendChartViewController];
    [self.scrollView addSubview:self.trendChartViewController.view];
    [self.trendChartViewController didMoveToParentViewController:self];
    
}

- (void)setupRightBarButtonItems
{
    //创建详情按钮
    if (self.product.goodDescriptionURL) {
        UIButton *proDetailBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        proDetailBtn.size = CGSizeMake(20, 20);
        [proDetailBtn setImage:[UIImage imageNamed:@"product_detail_icon"] forState:UIControlStateNormal];
        self.proDetailBtnItem = [[UIBarButtonItem alloc] initWithCustomView:proDetailBtn];
        self.proBtnItemNegativeSpacer = [[UIBarButtonItem alloc]
                                         initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                         target:nil action:nil];
        self.proBtnItemNegativeSpacer.width = -10;
        
        [proDetailBtn addTarget:self action:@selector(toProductDetail:) forControlEvents:UIControlEventTouchUpInside];
    }
    
    //创建刷新按钮
    UIButton *refreshBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    
    refreshBtn.size = CGSizeMake(44, 44);
    [refreshBtn setImage:[UIImage imageNamed:@"refresh"] forState:UIControlStateNormal];
    self.refreshBtn = refreshBtn;
    self.refreshBtnItem = [[UIBarButtonItem alloc] initWithCustomView:self.refreshBtn];
    self.negativeSpacer = [[UIBarButtonItem alloc]
                           initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                           target:nil action:nil];
    self.negativeSpacer.width = -12;
    
    [self.refreshBtn addTarget:self action:@selector(refreshData:) forControlEvents:UIControlEventTouchUpInside];
   
    NSArray *itemArray = nil;
    if (self.marketInfo.tradeFlag.boolValue == NO) {
        self.negativeSpacer.width = 0;
        itemArray = [NSArray arrayWithObjects:self.negativeSpacer, self.proDetailBtnItem, nil];
    } else {
       itemArray = [NSArray arrayWithObjects:self.negativeSpacer, self.refreshBtnItem, self.proBtnItemNegativeSpacer, self.proDetailBtnItem, nil];
    }
    self.navigationItem.rightBarButtonItems = itemArray;
}

/**
 *  初始化toolbar
 */
- (void)initToolBar
{
    //现货商品不支持快速买卖
    BOOL hideIndicateView = NO;
    if ([self isSpotGoods:self.product.goodsId]) {
        hideIndicateView = YES;
    }
    //设置toolbar的高度
    CGFloat toolBarHeight = 49.0f;
    
    
    if (self.enableTrade) {
        self.toolBarInTrade = [[LDPMToolBarInTradeView alloc] initWithTradeType:self.isNormalTrade screenName:[self.product screenName] hideIndicateView:hideIndicateView];
        self.toolBarInTrade.delegate = self;
        [self.view addSubview:self.toolBarInTrade];
        [self.toolBarInTrade autoPinEdgeToSuperviewEdge:ALEdgeLeft];
        [self.toolBarInTrade autoPinEdgeToSuperviewEdge:ALEdgeRight];
        [self.toolBarInTrade autoPinEdgeToSuperviewEdge:ALEdgeBottom];
        self.toolBarInTrade.height = toolBarHeight;
        [self.toolBarInTrade autoSetDimension:ALDimensionHeight toSize:toolBarHeight];
        
        self.toolBarInTrade.layer.shadowColor = [UIColor blackColor].CGColor;
        self.toolBarInTrade.layer.shadowRadius = 2.0;
        self.toolBarInTrade.layer.shadowOpacity = 0.05;
        self.toolBarInTrade.layer.shadowOffset = CGSizeMake(0.0, -1.0);
        
        UIView *separatorLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, SCREEN_WIDTH, 0.5)];
        separatorLine.backgroundColor = [UIColor colorWithRGB:0xE6E6E6];
        [self.toolBarInTrade addSubview:separatorLine];
    }
    
    NSNumber *number = [[LDPMAppABTestConfig sharedInstance] getFlagForCaseID:@"111" defaultFlag:@(1)];
    //number为0显示全屏按钮
    if ([number integerValue] == 1) {
        //添加全屏按钮
        [self addFullScreenButton];
    }
}

//添加全屏按钮
- (void)addFullScreenButton {
    UIButton *fullScreenButton = [[UIButton alloc] init];
    
    [self.view addSubview:fullScreenButton];
    
    [fullScreenButton setImage:[UIImage imageNamed:@"full_screen_button"] forState:UIControlStateNormal];
    [fullScreenButton addTarget:self action:@selector(fullScreenBtnAction:) forControlEvents:UIControlEventTouchUpInside];
    
    [fullScreenButton autoSetDimension:ALDimensionWidth toSize:40.0];
    [fullScreenButton autoSetDimension:ALDimensionHeight toSize:40.0];
    CGFloat heightOfToolBar = self.toolBarInTrade.size.height;
    if (!self.enableTrade) {
        heightOfToolBar = CGFLOAT_MIN;
    }
    
    [fullScreenButton autoPinEdge:ALEdgeBottom toEdge:ALEdgeBottom ofView:self.view withOffset: -1 * (heightOfToolBar + 9)];
    [fullScreenButton autoPinEdge:ALEdgeTrailing toEdge:ALEdgeTrailing ofView:self.view withOffset:-10.0];
}

- (void)fullScreenBtnAction:(id)sender {
    [LDPMUserEvent addEvent:EVENT_PRODUCT_CHART_LANDSCAPE tag:self.product.screenName];
    [self fullScreenActionWithOrientation:UIDeviceOrientationLandscapeLeft];
}

#pragma mark - 网络刷新

- (void)startTimer
{
    if (self.socketAlive || !self.timerAvailable) {
        return;
    }
    
    self.timer = [MSWeakTimer scheduledTimerWithTimeInterval:5.0f target:self selector:@selector(refreshData:) userInfo:nil repeats:NO dispatchQueue:dispatch_get_main_queue()];
}

- (void)stopTimer
{
    [self.timer invalidate];
    self.timer = nil;
}

#pragma mark Subscribe & Unsubscribe


- (void)deviceOrientationDidChange
{
    UIDeviceOrientation orientation = [UIDevice currentDevice].orientation;
    if(orientation == UIDeviceOrientationLandscapeLeft || orientation == UIDeviceOrientationLandscapeRight) {
        self.orientation = orientation;
        [self fullScreenActionWithOrientation:orientation];
    }
}

- (void)subscribeRealTimeMarkInfo {
    NSString *partnerId = (self.marketInfo.partnerId.length > 0)?self.marketInfo.partnerId:self.product.partnerId;
    NSString *goodsId = (self.marketInfo.goodsId.length > 0)?self.marketInfo.goodsId:self.product.goodsId;
    
    if (partnerId.length > 0 && goodsId.length > 0) {
        NSString *topic  = [LDPMSocketMessageTopicUtil simplePriceTopicWithPartnerId:partnerId goodsId:goodsId];
        
        @weakify(self)
        [[LDSocketPushClient defaultClient] addObserver:self topic:topic pushType:LDSocketPushTypeGroup usingBlock:^(LDSPMessage *message) {
            @strongify(self)
            if ([message.topic isEqualToString:topic]) {
                id object = [NSJSONSerialization JSONObjectWithData:message.body
                                                            options:NSJSONReadingMutableContainers
                                                              error:NULL];
                NPMRealTimeMarketInfo *marketInfo = [[NPMRealTimeMarketInfo alloc] initWithArray:object];
                if (marketInfo) {
                    self.marketInfo = marketInfo;
                    [self updateLatestMarketInfo:marketInfo];
                }
            }
        }];
    }
}

- (void)unsubscribeRealTimeMarkInfo {
    NSString *topic = [LDPMSocketMessageTopicUtil simplePriceTopicWithPartnerId:self.marketInfo.partnerId goodsId:self.marketInfo.goodsId];
    [[LDSocketPushClient defaultClient] removeObserver:self topic:topic];
}

- (void)checkSocketPushClientStatus
{
    //该方法可能在非主线程中调用，防止refreshdata中的布局在非主线中调用
    dispatch_async(dispatch_get_main_queue(), ^{
        self.socketAlive = [[LDSocketPushClient defaultClient] isSocketAlive];
        if (self.socketAlive == NO) {
            
            //如果主动推不可用，使用原来的5s刷新策略
            [self refreshData:nil];
        }
    });
}


- (void)refreshData:(id)sender
{
    if ([sender isKindOfClass:[NSString class]]) {
        if ([sender isEqualToString:@"下拉刷新"]) {
            [LDPMUserEvent addEvent:EVENT_PRODUCT_REFRESH tag:@"下拉刷新"];
        }
    } else if ([sender isKindOfClass:[UIButton class]]) {
        [LDPMUserEvent addEvent:EVENT_PRODUCT_REFRESH tag:@"按钮刷新"];
    }
    
    if (self.product.productCode) {
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        spinner.frame = self.refreshBtn.frame;
        [spinner startAnimating];
        [self.refreshBtnItem setCustomView:spinner];
        
        __weak typeof(self) weakSelf = self;
        [self.marketInfoService fetchRealTimeMarketInfoForProduct:self.product completion:^(NPMRetCode responseCode, NSError *error, NPMRealTimeMarketInfo *marketInfo,NSDictionary *json) {
            dispatch_time_t delayInNanoSeconds = dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC);
            dispatch_after(delayInNanoSeconds, dispatch_get_main_queue(), ^{
                [weakSelf startTimer];
                [weakSelf.refreshBtnItem setCustomView:self.refreshBtn];
            });
            if (responseCode != NPMRetCodeSuccess) {
                return ;
            }
            weakSelf.marketInfo = marketInfo;
            [weakSelf.product mergeDataFromJSON:json];
            [weakSelf updateLatestMarketInfo:marketInfo];
            [weakSelf.scrollView.mj_header endRefreshing];
        }];
    } else {
        [self.scrollView.mj_header endRefreshing];
    }
}


#pragma mark - Bar Action

- (void)toolBarInTradeView:(LDPMToolBarInTradeView *)view respondToRemindEvent:(id)action
{
    [LDPMUserEvent addEvent:EVENT_PRODUCT_ACTION_REMIND tag:self.product.screenName];
    
    if (!self.product.goodsName || !self.marketInfo.synTime) {
        return;
    }
    
    [NPMLoginAction loginWithSuccessBlock:^{
        NPMPushSettingViewController* pushSettingViewController = [[NPMPushSettingViewController alloc] initWithNibName:NSStringFromClass([NPMPushSettingViewController class])
                                                                                                                 bundle:[NSBundle mainBundle]];
        pushSettingViewController.watchItem = [NPMWatchItem watchItemWithProduct:self.product];
        pushSettingViewController.marketInfo = self.marketInfo;
        [self.navigationController pushViewController:pushSettingViewController animated:YES];
    } andFailureBlock:nil];
}

- (void)toolBarInTradeView:(LDPMToolBarInTradeView *)view respondTobuyAction:(id)action
{
    [LDPMUserEvent addEvent:self.toolBarInTrade.isNormalTrade?EVENT_PRODUCT_ACTION_BUY:EVENT_PRODUCT_ACTION_FASTBUY tag:self.product.screenName];
    [JLRoutes routeURL:self.toolBarInTrade.isNormalTrade ? self.product.normalTradeBuyURL:self.product.fastTradeBuyURL withParameters:@{kLDRouteViewControllerKey:self}];
}

- (void)toolBarInTradeView:(LDPMToolBarInTradeView *)view respondToSellAction:(id)action
{
    [LDPMUserEvent addEvent:self.toolBarInTrade.isNormalTrade?EVENT_PRODUCT_ACTION_SELL:EVENT_PRODUCT_ACTION_FASTSELL tag:self.product.screenName];
    [JLRoutes routeURL:self.toolBarInTrade.isNormalTrade?self.product.normalTradeSellURL:self.product.fastTradeSellURL withParameters:@{kLDRouteViewControllerKey:self}];
}

- (void)toProductDetail: (id)sender
{
    NSURL *URL = self.product.goodDescriptionURL;
    if (URL) {
        [JLRoutes routeURL:URL withParameters:@{kLDRouteViewControllerKey:self}];
    }
}

#pragma mark - UIStepperTextField targetAction
//delegate在具体的快速买卖页面中设置。LDPMFastBuySellViewController、LDPMPmecFastBuySellViewController
- (void)keyboardDidShow:(NSNotification *)aNotification
{
    [LDPMUserEvent addEvent:EVENT_PRODUCT_FASTBUYSELL_MODULE tag:@"吊起键盘"];
}

#pragma mark - 行情图事件处理 - NPMTrendViewControllerDelegate

- (void)trendChartViewController:(LDPMTrendChartViewController *)viewController doubleTapped:(UITapGestureRecognizer *)gesture
{
    self.orientation = UIDeviceOrientationLandscapeLeft;
    [self fullScreenActionWithOrientation:self.orientation];
}

- (void)trendChartViewControllerMinTimeDidRefreshData:(LDPMDayTimeLine *)data
{
   
    @weakify(self);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        @strongify(self);
        
        [self.scrollView.mj_header endRefreshing];
    
    });
}


#pragma mark - 全屏行情图切换

/**
 *  实现行情图全屏显示
 */
- (void)fullScreenActionWithOrientation:(UIDeviceOrientation)orientation
{
    self.fullScreenTrendViewController = [[NPMFullScreenTrendViewController alloc] initWithNibName:NSStringFromClass([NPMFullScreenTrendViewController class]) bundle:nil];
    
    self.fullScreenTrendViewController.product = self.product;
    self.fullScreenTrendViewController.delegate = self;
    self.fullScreenTrendViewController.currentType = self.trendChartViewController.currentType;
    self.fullScreenTrendViewController.currentTechIndex = self.trendChartViewController.currentTechIndex;
    self.fullScreenTrendViewController.currentLineChartType = self.trendChartViewController.currentLineChartType;
    self.fullScreenTrendViewController.techIndexs = [self.trendChartViewController.techIndexs mutableCopy];
    self.fullScreenTrendViewController.selectedSegmentIndex = self.trendChartViewController.selectedSegmentIndex;
    self.fullScreenTrendViewController.marketInfo = self.marketInfo;
    
    self.fullScreenTrendViewController.transitioningDelegate = self;
    self.fullScreenTrendViewController.modalPresentationStyle = UIModalPresentationFullScreen;
    

    self.fullScreenTrendViewController.orientation = orientation;

    [self presentViewController:self.fullScreenTrendViewController animated:YES completion:nil];

}

- (void)fullScreenTrendViewControllerWillClose:(NPMFullScreenTrendViewController *)fullScreenTrendViewController
{
    self.trendChartViewController.currentTechIndex = fullScreenTrendViewController.trendChartViewController.currentTechIndex;
    self.trendChartViewController.currentLineChartType = fullScreenTrendViewController.trendChartViewController.currentLineChartType;
    self.trendChartViewController.techIndexs = [fullScreenTrendViewController.trendChartViewController.techIndexs mutableCopy];
    self.trendChartViewController.selectedSegmentIndex = fullScreenTrendViewController.trendChartViewController.selectedSegmentIndex;
    self.trendChartViewController.product = [fullScreenTrendViewController.product copy];
    self.trendChartViewController.changeControlView.currSelectedTechType = fullScreenTrendViewController.trendChartViewController.currentTechIndex;
    self.trendChartViewController.changeControlView.currSelectedlineChartType = fullScreenTrendViewController.trendChartViewController.currentLineChartType;
    [self.trendChartViewController updateChartViewWithLatestData];
}

#pragma mark - view controller transition delegate

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented presentingController:(UIViewController *)presenting sourceController:(UIViewController *)source
{
    LDPMProductTransitionAnimator *animator = [[LDPMProductTransitionAnimator alloc] initWithOrientation:self.orientation];
    
    animator.presenting = YES;
    return animator;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed
{
    LDPMProductTransitionAnimator *animator = [[LDPMProductTransitionAnimator alloc] initWithOrientation:self.orientation];
    
    animator.presenting = NO;
    return animator;
}

#pragma mark - Getters & Setters
- (void)setProduct:(NPMProduct *)product {
    _product = product;
    if (_product) {
        self.pageAlias = [product.goodsId copy];
    }
}

#pragma mark - 分时导航显示
- (void)showUserGuideView
{
    if (!_previewing) {
        NSString *key = [NSString stringWithFormat:@"%@marketguide", NSStringFromClass(self.class)];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:key];
        UIImageView *imageView = [[UIImageView alloc] init];
        [[[UIApplication sharedApplication].delegate window] addSubview:imageView];
        [imageView autoPinEdgesToSuperviewEdgesWithInsets:UIEdgeInsetsMake(0, 0, 0, 0)];
        imageView.userInteractionEnabled = YES;
        imageView.image = [UIImage imageNamed:@"marketMine_user_guide"];
        imageView.tag = marketUserGuideImageTag;
        UITapGestureRecognizer *tapGR = [UITapGestureRecognizer new];
        [tapGR addTarget:self action:@selector(userGuideTapGesture)];
        [imageView addGestureRecognizer:tapGR];
    }
}

- (void)userGuideTapGesture
{
    UIWindow *window = [[UIApplication sharedApplication].delegate window];
    UIImageView *imageView = (UIImageView *)[window viewWithTag:marketUserGuideImageTag];
    [imageView removeFromSuperview];

}

#pragma mark - 页面统计

- (NSString *)pageEventParam
{
    return self.product.goodsId;
}

#pragma mark - Prodcut Utils

- (BOOL)isSpotGoods:(NSString *)goodsId {
    
    static NSArray *spotGoodsList;
    if (!spotGoodsList) {
        //上金所现货对应的goodsID
        spotGoodsList = @[@"Au99.99", @"Au99.95", @"Au100g"];
    }
    
    if (goodsId.length == 0) {
        return NO;
    }
    return ([spotGoodsList indexOfObject:goodsId] != NSNotFound);
}

@end
