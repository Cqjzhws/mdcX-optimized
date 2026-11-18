//
//  MXBEntry.m
//  mdcX Boost — 注入入口（constructor）
//
//  dylib 被 TrollFools 注入到目标进程后，dyld 在 main 之前调用本 constructor，
//  依次安装：动画加速 → 交互优化 → 后台保活 → 安全网。
//  所有 hook 都用 Objective-C runtime，属于进程内生效，不改任何系统文件。
//

#import <Foundation/Foundation.h>
#import "MXBBoost.h"
#import "MXBConfig.h"
#import "MXBInternal.h"

@implementation MXBBoost

+ (NSString *)version { return @MXB_VERSION; }
+ (BOOL)isEnabled { return [MXBConfig shared].enabled; }
+ (double)effectiveMultiplier { return [MXBConfig shared].animMultiplier; }
+ (NSInteger)currentProfile { return [MXBConfig shared].profile; }
+ (NSDictionary *)runtimeSnapshot { return [[MXBConfig shared] snapshot]; }

@end

__attribute__((constructor))
static void MXBBoostEntry(void) {
    @autoreleasepool {
        NSLog(@"%@ ========================================", MXB_LOG_TAG);
        NSLog(@"%@ mdcX Boost v%@ launching in process: %@",
              MXB_LOG_TAG, @MXB_VERSION, [[NSBundle mainBundle] bundleIdentifier] ?: @"?");

        MXBConfig *cfg = [MXBConfig shared];
        if (!cfg.enabled) {
            NSLog(@"%@ disabled by config, hooks NOT installed", MXB_LOG_TAG);
            return;
        }

        // 安装顺序：核心 → 交互 → 保活 → 安全
        MXBInstallAnimationHooks();
        MXBInstallInteractionHooks();
        MXBInstallBackgroundKeeper();
        MXBInstallSafetyNet();

        NSLog(@"%@ READY | profile=%ld mult=%.1f floor=%.3f protected=%d circuit=%d",
              MXB_LOG_TAG,
              (long)cfg.profile, cfg.animMultiplier, cfg.animFloor,
              cfg.currentAppProtected, cfg.circuitEnabled);
        NSLog(@"%@ animation=%d interaction=%d background=%d safety=%d",
              MXB_LOG_TAG,
              MXBAnimationHooksInstalled(),
              MXBInteractionHooksInstalled(),
              MXBBackgroundKeeperInstalled(),
              MXBSafetyNetInstalled());
        NSLog(@"%@ ========================================", MXB_LOG_TAG);
    }
}
