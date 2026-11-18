//
//  MXBConfig.m
//  mdcX Boost — 配置读取层实现
//

#import "MXBConfig.h"
#import <mach/mach.h>
#import <sys/sysctl.h>

@interface MXBConfig ()
@property (nonatomic, strong) NSDictionary *raw;
@property (nonatomic, assign) BOOL circuitTripped;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *anomalyTimes;
@property (nonatomic, strong) NSLock *lock;
@end

@implementation MXBConfig

+ (instancetype)shared {
    static MXBConfig *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[self alloc] init]; });
    return inst;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _lock = [NSLock new];
        _anomalyTimes = [NSMutableArray array];
        [self reload];
    }
    return self;
}

- (NSString *)prefsPath {
    // 共享配置：dylib 被注入到 SpringBoard/各 App 后，NSHomeDirectory() 指向的是
    // 目标进程的容器，不是 mdcX 的容器。因此必须用所有进程都能读到的绝对路径。
    // TrollStore 环境下 /var/mobile/Library/Preferences/ 可写。
    return @"/var/mobile/Library/Preferences/com.mdcx.boost.plist";
}

- (void)reload {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:[self prefsPath]];
    self.raw = d ?: @{};
    NSLog(@"%@ config reload, keys=%lu, protected=%d",
          MXB_LOG_TAG, (unsigned long)self.raw.count, self.currentAppProtected);
}

// ---------- 原始读取助手 ----------
- (BOOL)boolFor:(NSString *)key def:(BOOL)def {
    id v = self.raw[key];
    return [v isKindOfClass:[NSNumber class]] ? [v boolValue] : def;
}
- (double)doubleFor:(NSString *)key def:(double)def {
    id v = self.raw[key];
    return [v isKindOfClass:[NSNumber class]] ? [v doubleValue] : def;
}
- (NSInteger)intFor:(NSString *)key def:(NSInteger)def {
    id v = self.raw[key];
    return [v isKindOfClass:[NSNumber class]] ? [v integerValue] : def;
}

// ---------- 生效属性 ----------
- (BOOL)enabled        { return [self boolFor:MXB_KEY_ENABLED def:YES]; }
- (NSInteger)profile   { return [self intFor:MXB_KEY_PROFILE def:2]; }
- (double)animFloor    {
    double f = [self doubleFor:MXB_KEY_ANIM_FLOOR def:0.012];
    return f < 0.006 ? 0.006 : (f > 0.05 ? 0.05 : f);
}
- (BOOL)transitionBoost   { return [self boolFor:MXB_KEY_TRANSITION def:YES]; }
- (BOOL)interactionBoost  { return [self boolFor:MXB_KEY_INTERACTION def:YES]; }
- (BOOL)backgroundKeepAlive { return [self boolFor:MXB_KEY_BACKGROUND def:YES]; }
- (NSInteger)bgMode     { NSInteger m = [self intFor:MXB_KEY_BG_MODE def:1]; return m < 0 ? 0 : (m > 2 ? 2 : m); }
- (BOOL)circuitEnabled  { return [self boolFor:MXB_KEY_CIRCUIT def:YES]; }
- (double)circuitWindow { double w = [self doubleFor:MXB_KEY_CIRCUIT_WINDOW def:10.0]; return w <= 0 ? 10.0 : w; }
- (NSInteger)circuitLimit { NSInteger l = [self intFor:MXB_KEY_CIRCUIT_LIMIT def:6]; return l <= 0 ? 6 : l; }

- (NSArray<NSString *> *)protectList {
    id v = self.raw[MXB_KEY_SAFE_LIST];
    if ([v isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray array];
        for (id x in v) if ([x isKindOfClass:[NSString class]]) [out addObject:x];
        return out;
    }
    // 默认保护名单：这些 App 用高倍率已知容易出问题，默认只走安全档
    return @[@"com.tencent.xin",          // 微信
             @"com.tencent.weworkocal",   // 企业微信
             @"com.apple.mobilesafari"];  // Safari
}

- (NSString *)currentBundleID {
    static NSString *bid = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *b = [[NSBundle mainBundle] bundleIdentifier];
        bid = b ?: @"";
    });
    return bid;
}

- (BOOL)currentAppProtected {
    NSString *bid = [self currentBundleID];
    if (bid.length == 0) return NO;
    for (NSString *p in [self protectList]) {
        if ([bid isEqualToString:p] || [bid hasPrefix:[p stringByAppendingString:@"."]]) return YES;
    }
    return NO;
}

- (double)baseMultiplier {
    double p;
    switch ([self profile]) {
        case 0:  p = MXB_PROFILE_SAFE_MULT; break;
        case 1:  p = MXB_PROFILE_BALANCED; break;
        default: p = MXB_PROFILE_TURBO; break;
    }
    // 档位决定了上限，plist 里的 animMultiplier 只能在此上限内微调
    double custom = [self doubleFor:MXB_KEY_ANIM_MULT def:p];
    return custom > p ? p : custom;
}

- (double)animMultiplier {
    double m = [self baseMultiplier];
    if ([self currentAppProtected]) m = MXB_PROFILE_SAFE_MULT;   // 保护名单降安全档
    if (self.circuitTripped)       m = MXB_PROFILE_SAFE_MULT;    // 熔断降安全档
    return m;
}

// ---------- 熔断 ----------
- (BOOL)reportAnomaly {
    if (!self.circuitEnabled) return NO;
    [self.lock lock];
    double now = [[NSDate date] timeIntervalSince1970];
    [self.anomalyTimes addObject:@(now)];
    // 淘汰窗口外的记录
    NSMutableArray *fresh = [NSMutableArray array];
    for (NSNumber *t in self.anomalyTimes) {
        if (now - t.doubleValue <= [self circuitWindow]) [fresh addObject:t];
    }
    self.anomalyTimes = fresh;
    BOOL trip = (NSInteger)fresh.count >= [self circuitLimit];
    if (trip) self.circuitTripped = YES;
    [self.lock unlock];
    if (trip) {
        NSLog(@"%@ CIRCUIT BREAKER TRIPPED: %lu anomalies in %.0fs -> degrade to safe profile",
              MXB_LOG_TAG, (unsigned long)fresh.count, [self circuitWindow]);
    }
    return trip;
}

- (NSDictionary *)snapshot {
    return @{
        @"version": @MXB_VERSION,
        MXB_KEY_ENABLED: @(self.enabled),
        MXB_KEY_PROFILE: @(self.profile),
        MXB_KEY_ANIM_MULT: @(self.animMultiplier),
        MXB_KEY_ANIM_FLOOR: @(self.animFloor),
        MXB_KEY_TRANSITION: @(self.transitionBoost),
        MXB_KEY_INTERACTION: @(self.interactionBoost),
        MXB_KEY_BACKGROUND: @(self.backgroundKeepAlive),
        MXB_KEY_BG_MODE: @(self.bgMode),
        @"protected": @(self.currentAppProtected),
        @"circuitTripped": @(self.circuitTripped),
        @"bundleID": [self currentBundleID]
    };
}

@end
