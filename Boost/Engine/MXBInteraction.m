//
//  MXBInteraction.m
//  mdcX Boost — 交互响应与滚动惯性优化（自研）
//
//  目标：减少触摸到反馈的延迟、削弱滚动"拖泥带水"的惯性等待。
//  手法：hook UIScrollView 的 decelerationRate 设置与 UIGestureRecognizer 的
//        最小按压时长，去掉系统默认的小延迟。仅在开关打开时生效。
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "MXBBoost.h"
#import "MXBConfig.h"
#import "MXBHook.h"

static BOOL MXBInteractionHooksInstalledFlag = NO;

// UIScrollView 减速速率：系统默认 0.998，改小让滚动更快停下（更跟手）
@interface UIScrollView (MXBBoost)
- (void)mxb_setDecelerationRate:(UIScrollViewDecelerationRate)rate;
@end
@implementation UIScrollView (MXBBoost)
- (void)mxb_setDecelerationRate:(UIScrollViewDecelerationRate)rate {
    MXBConfig *cfg = [MXBConfig shared];
    if (cfg.enabled && cfg.interactionBoost) {
        // 只加速"普通"减速，快速减速保持原样（避免破坏分页/滚动条语义）
        if (fabs(rate - UIScrollViewDecelerationRateNormal) < 0.0001) {
            rate = 0.985;   // 更短的惯性尾巴
        }
    }
    [self mxb_setDecelerationRate:rate];
}
@end

// 手势识别器：缩短最小按压时长（长按手势响应更快）
@interface UIGestureRecognizer (MXBBoost)
- (void)mxb_setMinimumPressDuration:(CFTimeInterval)d;
@end
@implementation UIGestureRecognizer (MXBBoost)
- (void)mxb_setMinimumPressDuration:(CFTimeInterval)d {
    MXBConfig *cfg = [MXBConfig shared];
    if (cfg.enabled && cfg.interactionBoost && d > 0.25) {
        d = 0.16;   // 长按识别从 0.5s 缩短到 0.16s
    }
    [self mxb_setMinimumPressDuration:d];
}
@end

void MXBInstallInteractionHooks(void) {
    MXBSwizzleInstanceMethod([UIScrollView class],
        @selector(setDecelerationRate:), @selector(mxb_setDecelerationRate:));
    MXBSwizzleInstanceMethod([UIGestureRecognizer class],
        @selector(setMinimumPressDuration:), @selector(mxb_setMinimumPressDuration:));
    MXBInteractionHooksInstalledFlag = YES;
    NSLog(@"%@ interaction hooks installed (UIScrollView, UIGestureRecognizer)", MXB_LOG_TAG);
}

BOOL MXBInteractionHooksInstalled(void) { return MXBInteractionHooksInstalledFlag; }
