//
//  main.m — mdcX Boost 配置器（从零自研，纯 UIKit，无 SwiftUI / 无 Xcode 依赖）
//
//  作用：一个独立可装的小 App，用来写 mdcX Boost 加速引擎的配置。
//  配置路径与键名与 Boost/Engine/MXBBoost.h 严格一致。
//  写完 post Darwin 通知 com.mdcx.boost.reload，已注入的 dylib 即时生效。
//
//  编译：Boost/tools/build_configurator.py（zig + iPhoneOS SDK）
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>

// ===== 配置契约（与 MXBBoost.h 完全一致）=====
static NSString * const kPrefsPath = @"/var/mobile/Library/Preferences/com.mdcx.boost.plist";
static NSString * const kNotifyReload = @"com.mdcx.boost.reload";

static NSString * const KEY_ENABLED   = @"enabled";
static NSString * const KEY_PROFILE   = @"profile";
static NSString * const KEY_ANIMMULT  = @"animMultiplier";
static NSString * const KEY_ANIMFLOOR = @"animFloor";
static NSString * const KEY_TRANSITION= @"transitionBoost";
static NSString * const KEY_INTERACT  = @"interactionBoost";
static NSString * const KEY_BG        = @"backgroundKeepAlive";
static NSString * const KEY_BGMODE    = @"bgMode";
static NSString * const KEY_PROTECT   = @"protectBundleIDs";
static NSString * const KEY_CIRCUIT   = @"circuitBreaker";
static NSString * const KEY_CIRWIN    = @"circuitWindowSec";
static NSString * const KEY_CIRLIMIT  = @"circuitLimit";

static NSArray<NSString *> *defaultProtect(void) {
    return @[@"com.tencent.xin", @"com.tencent.weworkocal", @"com.apple.mobilesafari"];
}

// ===== 配置读写 =====
@interface MXBConf : NSObject
+ (NSMutableDictionary *)load;
+ (void)save:(NSDictionary *)d;
@end
@implementation MXBConf
+ (NSMutableDictionary *)load {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (!d) d = [NSMutableDictionary dictionary];
    // 填默认
    if (!d[KEY_ENABLED])   d[KEY_ENABLED]   = @YES;
    if (!d[KEY_PROFILE])   d[KEY_PROFILE]   = @2;
    if (!d[KEY_ANIMFLOOR]) d[KEY_ANIMFLOOR] = @0.012;
    if (!d[KEY_TRANSITION])d[KEY_TRANSITION]= @YES;
    if (!d[KEY_INTERACT])  d[KEY_INTERACT]  = @YES;
    if (!d[KEY_BG])        d[KEY_BG]        = @YES;
    if (!d[KEY_BGMODE])    d[KEY_BGMODE]    = @1;
    if (!d[KEY_PROTECT])   d[KEY_PROTECT]   = defaultProtect();
    if (!d[KEY_CIRCUIT])   d[KEY_CIRCUIT]   = @YES;
    if (!d[KEY_CIRWIN])    d[KEY_CIRWIN]    = @10.0;
    if (!d[KEY_CIRLIMIT])  d[KEY_CIRLIMIT]  = @6;
    return d;
}
+ (void)save:(NSDictionary *)d {
    [d writeToFile:kPrefsPath atomically:YES];
    notify_post([kNotifyReload UTF8String]);
}
@end

// ===== 颜色 / 样式 =====
static UIColor *acc(void) { return [UIColor colorWithRed:0.98 green:0.74 blue:0.20 alpha:1.0]; } // 极客金
static UIColor *bg(void)  { return [UIColor colorWithRed:0.05 green:0.05 blue:0.09 alpha:1.0]; }
static UIColor *card(void){ return [UIColor colorWithRed:0.11 green:0.11 blue:0.16 alpha:1.0]; }

// ===== 主界面 =====
@interface RootVC : UIViewController <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tv;
@property (nonatomic, strong) NSMutableDictionary *cfg;
@property (nonatomic, strong) UISegmentedControl *profileSeg;
@property (nonatomic, strong) UISegmentedControl *bgSeg;
@property (nonatomic, strong) UISwitch *swEnabled, *swTrans, *swInteract, *swBG, *swCircuit;
@property (nonatomic, strong) UILabel *statusLabel;
@end

@implementation RootVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"mdcX Boost";
    self.view.backgroundColor = bg();
    self.cfg = [MXBConf load];

    self.tv = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tv.translatesAutoresizingMaskIntoConstraints = NO;
    self.tv.dataSource = self; self.tv.delegate = self;
    self.tv.backgroundColor = [UIColor clearColor];
    self.tv.separatorColor = [UIColor colorWithWhite:1 alpha:0.06];
    [self.view addSubview:self.tv];
    [NSLayoutConstraint activateConstraints:@[
        [self.tv.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tv.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tv.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tv.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];

    // 分段控件
    self.profileSeg = [[UISegmentedControl alloc] initWithItems:@[@"安全 8×",@"均衡 24×",@"极速 50×"]];
    self.profileSeg.selectedSegmentIndex = [self.cfg[KEY_PROFILE] integerValue];
    self.profileSeg.tintColor = acc();
    [self.profileSeg addTarget:self action:@selector(profileChanged:) forControlEvents:UIControlEventValueChanged];

    self.bgSeg = [[UISegmentedControl alloc] initWithItems:@[@"音频",@"+任务",@"全策略"]];
    self.bgSeg.selectedSegmentIndex = [self.cfg[KEY_BGMODE] integerValue];
    self.bgSeg.tintColor = acc();
    [self.bgSeg addTarget:self action:@selector(bgChanged:) forControlEvents:UIControlEventValueChanged];

    self.swEnabled = [self makeSwitch:[self.cfg[KEY_ENABLED] boolValue] action:@selector(toggleEnabled:)];
    self.swTrans   = [self makeSwitch:[self.cfg[KEY_TRANSITION] boolValue] action:@selector(toggleTrans:)];
    self.swInteract= [self makeSwitch:[self.cfg[KEY_INTERACT] boolValue] action:@selector(toggleInteract:)];
    self.swBG      = [self makeSwitch:[self.cfg[KEY_BG] boolValue] action:@selector(toggleBG:)];
    self.swCircuit = [self makeSwitch:[self.cfg[KEY_CIRCUIT] boolValue] action:@selector(toggleCircuit:)];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = [self statusText];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.statusLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"恢复默认" style:UIBarButtonItemStylePlain
                                       target:self action:@selector(resetAll)];
}

- (UISwitch *)makeSwitch:(BOOL)on action:(SEL)action {
    UISwitch *s = [[UISwitch alloc] init];
    s.on = on; s.onTintColor = acc();
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

- (NSString *)statusText {
    NSInteger p = [self.cfg[KEY_PROFILE] integerValue];
    NSString *pn = @[@"安全",@"均衡",@"极速"][MIN(p,2)];
    BOOL en = [self.cfg[KEY_ENABLED] boolValue];
    return [NSString stringWithFormat:@"状态：%@ · %@档\n配置：%@\n已注入进程收到 reload 通知即生效；改档位无需重新注入。",
            en?@"开启":@"关闭", pn, kPrefsPath];
}

- (void)save {
    [MXBConf save:self.cfg];
    self.statusLabel.text = [self statusText];
}

- (void)profileChanged:(UISegmentedControl *)seg {
    self.cfg[KEY_PROFILE] = @(seg.selectedSegmentIndex);
    // 切档时清掉自定义倍率，让引擎用档位默认
    [self.cfg removeObjectForKey:KEY_ANIMMULT];
    [self save];
}
- (void)bgChanged:(UISegmentedControl *)seg {
    self.cfg[KEY_BGMODE] = @(seg.selectedSegmentIndex); [self save];
}
- (void)toggleEnabled:(UISwitch *)s { self.cfg[KEY_ENABLED]=@(s.on); [self save]; }
- (void)toggleTrans:(UISwitch *)s   { self.cfg[KEY_TRANSITION]=@(s.on); [self save]; }
- (void)toggleInteract:(UISwitch *)s{ self.cfg[KEY_INTERACT]=@(s.on); [self save]; }
- (void)toggleBG:(UISwitch *)s      { self.cfg[KEY_BG]=@(s.on); [self save]; }
- (void)toggleCircuit:(UISwitch *)s { self.cfg[KEY_CIRCUIT]=@(s.on); [self save]; }
- (void)resetAll {
    self.cfg = [NSMutableDictionary dictionary];
    self.cfg[KEY_ENABLED]=@YES; self.cfg[KEY_PROFILE]=@2; self.cfg[KEY_ANIMFLOOR]=@0.012;
    self.cfg[KEY_TRANSITION]=@YES; self.cfg[KEY_INTERACT]=@YES; self.cfg[KEY_BG]=@YES;
    self.cfg[KEY_BGMODE]=@1; self.cfg[KEY_PROTECT]=defaultProtect();
    self.cfg[KEY_CIRCUIT]=@YES; self.cfg[KEY_CIRWIN]=@10.0; self.cfg[KEY_CIRLIMIT]=@6;
    [self save];
    self.profileSeg.selectedSegmentIndex = 2;
    self.bgSeg.selectedSegmentIndex = 1;
    self.swEnabled.on=self.swTrans.on=self.swInteract.on=self.swBG.on=self.swCircuit.on=YES;
    [self.tv reloadData];
}

// ===== 表格 =====
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }
- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return @[@"总开关",@"加速档位",@"功能开关",@"后台保活"][s];
}
- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    NSArray *rows = @[@1,@1,@4,@2];
    return s < rows.count ? [rows[s] integerValue] : 0;
}
- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *cid = @"c";
    UITableViewCell *c = [tv dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
    c.backgroundColor = card();
    c.textLabel.textColor = [UIColor whiteColor];
    c.selectionStyle = UITableViewCellSelectionStyleNone;
    c.accessoryView = nil;

    if (ip.section==0) {
        c.textLabel.text = @"启用 mdcX Boost 加速";
        c.accessoryView = self.swEnabled;
    } else if (ip.section==1) {
        c.textLabel.text = @"倍率档位";
        self.profileSeg.frame = CGRectMake(0,0,220,32);
        c.accessoryView = self.profileSeg;
    } else if (ip.section==2) {
        if (ip.row==0) { c.textLabel.text=@"转场 / 启动加速"; c.accessoryView=self.swTrans; }
        if (ip.row==1) { c.textLabel.text=@"交互响应优化"; c.accessoryView=self.swInteract; }
        if (ip.row==2) { c.textLabel.text=@"安全熔断（防连崩）"; c.accessoryView=self.swCircuit; }
        if (ip.row==3) { c.textLabel.text=@"保护名单：微信/Safari 等自动降档"; c.accessoryView=nil; }
    } else {
        if (ip.row==0) { c.textLabel.text=@"启用真后台保活"; c.accessoryView=self.swBG; }
        if (ip.row==1) {
            c.textLabel.text=@"保活强度";
            self.bgSeg.frame = CGRectMake(0,0,180,32);
            c.accessoryView = self.bgSeg;
        }
    }
    return c;
}
- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip { return 52; }
- (UIView *)tableView:(UITableView *)tv viewForFooterInSection:(NSInteger)s {
    if (s != 3) return nil;
    UIView *v = [[UIView alloc] init];
    self.statusLabel.frame = CGRectMake(16, 4, [UIScreen mainScreen].bounds.size.width-32, 60);
    [v addSubview:self.statusLabel];
    return v;
}
- (CGFloat)tableView:(UITableView *)tv heightForFooterInSection:(NSInteger)s { return s==3?70:8; }
@end

// ===== App Delegate =====
@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[RootVC new]];
    nav.navigationBar.barTintColor = bg();
    nav.navigationBar.tintColor = acc();
    nav.navigationBar.titleTextAttributes = @{NSForegroundColorAttributeName:[UIColor whiteColor]};
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
