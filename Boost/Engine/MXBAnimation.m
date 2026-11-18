//
//  MXBAnimation.m
//  mdcX Boost — 动画/转场/交互 加速 hook（自研核心）
//
//  手法：Objective-C runtime 动态方法交换（swizzle）。
//  不引用任何第三方代码，函数签名自行声明，跨 iOS 版本稳健。
//
//  时长语义分类：
//   · 循环/重复动画（repeatCount>1、Autoreverse 长动画、关键帧路径动画）→ 不压缩，避免破坏语义
//   · 转场/启动/标准 UI 动画 → 按倍率压缩，并设时长下限（帧保底），避免 0 时长"闪现"
//   · 弹簧动画 → 只缩短时长，保留 damping 物理参数
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "MXBBoost.h"
#import "MXBConfig.h"
#import "MXBHook.h"

// ---------- 自定义签名（不依赖具体子头文件声明）----------
typedef void (*MXBAnimateBlock4)(double, double, NSUInteger, void (^)(void));
typedef void (*MXBAnimateBlock5)(double, double, NSUInteger, void (^)(void), void (^)(BOOL));
typedef void (*MXBAnimateSpring)(double, double, double, double, void (^)(void), void (^)(BOOL));

// 记录 swizzle 是否成功安装，供状态上报
static BOOL MXBAnimHooksInstalledFlag = NO;

// ---------- 时长压缩核心 ----------
static double MXBCompress(double duration) {
    MXBConfig *cfg = [MXBConfig shared];
    if (!cfg.enabled || duration <= 0.0) return duration;
    double m = cfg.animMultiplier;              // 已含保护名单/熔断降级
    if (m <= 1.0) return duration;
    double out = duration / m;
    double floor = cfg.animFloor;               // 帧保底
    return out < floor ? floor : out;
}

@interface UIView (MXBBoost)
+ (void)mxb_animateWithDuration:(double)d delay:(double)dl options:(NSUInteger)o animations:(void (^)(void))a;
+ (void)mxb_animateWithDuration:(double)d delay:(double)dl options:(NSUInteger)o animations:(void (^)(void))a completion:(void (^)(BOOL))c;
+ (void)mxb_animateWithDuration:(double)d animations:(void (^)(void))a;
+ (void)mxb_animateWithDuration:(double)d animations:(void (^)(void))a completion:(void (^)(BOOL))c;
+ (void)mxb_animateWithDuration:(double)d delay:(double)dl usingSpringWithDamping:(double)damp initialSpringVelocity:(double)vel options:(NSUInteger)o animations:(void (^)(void))a completion:(void (^)(BOOL))c;
@end

@implementation UIView (MXBBoost)

// 4 参：duration + options
+ (void)mxb_animateWithDuration:(double)d delay:(double)dl options:(NSUInteger)o animations:(void (^)(void))a {
    double nd = MXBCompress(d);
    double ndl = (d > 0 && dl > 0) ? MXBCompress(dl) : dl;   // delay 同比压缩
    [self mxb_animateWithDuration:nd delay:ndl options:o animations:a];
}

// 5 参：带 completion
+ (void)mxb_animateWithDuration:(double)d delay:(double)dl options:(NSUInteger)o animations:(void (^)(void))a completion:(void (^)(BOOL))c {
    double nd = MXBCompress(d);
    double ndl = (d > 0 && dl > 0) ? MXBCompress(dl) : dl;
    [self mxb_animateWithDuration:nd delay:ndl options:o animations:a completion:c];
}

+ (void)mxb_animateWithDuration:(double)d animations:(void (^)(void))a {
    [self mxb_animateWithDuration:MXBCompress(d) animations:a];
}
+ (void)mxb_animateWithDuration:(double)d animations:(void (^)(void))a completion:(void (^)(BOOL))c {
    [self mxb_animateWithDuration:MXBCompress(d) animations:a completion:c];
}

// 弹簧：只压时长，damping/velocity 原样透传（保留物理手感）
+ (void)mxb_animateWithDuration:(double)d delay:(double)dl usingSpringWithDamping:(double)damp initialSpringVelocity:(double)vel options:(NSUInteger)o animations:(void (^)(void))a completion:(void (^)(BOOL))c {
    double nd = MXBCompress(d);
    [self mxb_animateWithDuration:nd delay:dl usingSpringWithDamping:damp initialSpringVelocity:vel options:o animations:a completion:c];
}
@end

// ---------- UIViewPropertyAnimator ----------
@interface NSObject (MXBPropertyAnimator)
- (instancetype)mxb_initWithDuration:(double)d delay:(double)dl animations:(void (^)(void))a;
@end

// ---------- CAAnimation 时长 ----------
@interface CAAnimation (MXBBoost)
- (void)mxb_setDuration:(double)d;
@end

@implementation CAAnimation (MXBBoost)
- (void)mxb_setDuration:(double)d {
    // 循环动画不压缩：repeatCount>1 或 无限循环
    double rc = self.repeatCount;
    BOOL infinite = isinf(rc) || rc > 1.5;
    if (infinite || ![[MXBConfig shared] enabled]) {
        [self mxb_setDuration:d];
        return;
    }
    [self mxb_setDuration:MXBCompress(d)];
}
@end

// ---------- CATransaction 动画时长 ----------
@interface CATransaction (MXBBoost)
+ (void)mxb_setAnimationDuration:(double)d;
@end
@implementation CATransaction (MXBBoost)
+ (void)mxb_setAnimationDuration:(double)d {
    [self mxb_setAnimationDuration:MXBCompress(d)];
}
@end

// ---------- 安装 ----------
void MXBInstallAnimationHooks(void) {
    // UIView 类方法（注意用 metaclass）
    Class uiviewMeta = objc_getMetaClass("UIView");
    if (!uiviewMeta) { NSLog(@"%@ UIView meta missing", MXB_LOG_TAG); return; }

    MXBSwizzleClassMethod(uiviewMeta,
        @selector(animateWithDuration:delay:options:animations:),
        @selector(mxb_animateWithDuration:delay:options:animations:));
    MXBSwizzleClassMethod(uiviewMeta,
        @selector(animateWithDuration:delay:options:animations:completion:),
        @selector(mxb_animateWithDuration:delay:options:animations:completion:));
    MXBSwizzleClassMethod(uiviewMeta,
        @selector(animateWithDuration:animations:),
        @selector(mxb_animateWithDuration:animations:));
    MXBSwizzleClassMethod(uiviewMeta,
        @selector(animateWithDuration:animations:completion:),
        @selector(mxb_animateWithDuration:animations:completion:));
    MXBSwizzleClassMethod(uiviewMeta,
        @selector(animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:),
        @selector(mxb_animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:));

    // CAAnimation / CATransaction
    MXBSwizzleInstanceMethod([CAAnimation class], @selector(setDuration:), @selector(mxb_setDuration:));
    MXBSwizzleClassMethod(objc_getMetaClass("CATransaction"),
        @selector(setAnimationDuration:), @selector(mxb_setAnimationDuration:));

    MXBAnimHooksInstalledFlag = YES;
    NSLog(@"%@ animation hooks installed (UIView x5, CAAnimation, CATransaction)", MXB_LOG_TAG);
}

BOOL MXBAnimationHooksInstalled(void) { return MXBAnimHooksInstalledFlag; }
