//
//  MXBBoost.h
//  mdcX Boost — mdcX Max 自研运行时加速引擎
//
//  这是 mdcX Max 项目从零自研的加速引擎（MXB = mdcX Boost）。
//  不依赖、不引用、不包含任何第三方 tweak 项目的代码。
//  仅使用 Apple 公开 API（Objective-C runtime / Foundation / UIKit / QuartzCore / AVFoundation）。
//
//  设计契约：
//  · 配置源：~/Library/Preferences/com.mdcx.boost.plist（由 mdcX App 写入）
//  · 生效方式：TrollFools 注入 mdcxboost.dylib 到目标进程后，constructor 自动安装 hook
//  · 配置热更新：监听 Darwin 通知 com.mdcx.boost.reload
//  · 保护名单：命中 bundle id 的进程只做安全档加速（避免已知易崩 App 闪退）
//  · 安全熔断：单位时间内异常次数超阈值 → 自动降到安全倍率
//

#ifndef MXB_BOOST_H
#define MXB_BOOST_H

#import <Foundation/Foundation.h>

// 引擎版本（自研版本，与 mdcX 仓库版本独立）
#define MXB_VERSION "1.0.0"

// 配置域与路径（共享绝对路径：注入到任意进程后都能读到同一份配置）
#define MXB_PREFS_DOMAIN        @"com.mdcx.boost"
#define MXB_PREFS_ABSOLUTE      @"/var/mobile/Library/Preferences/com.mdcx.boost.plist"

//  Darwin 通知：配置热更新
#define MXB_NOTIFY_RELOAD       "com.mdcx.boost.reload"

// 日志标签（真机控制台过滤用）
#define MXB_LOG_TAG             @"[mdcXBoost]"

// ---- 配置键（Swift 写入端与此处严格一致，构成配置契约）----
#define MXB_KEY_ENABLED         @"enabled"          // Bool    总开关
#define MXB_KEY_PROFILE         @"profile"          // Int     档位 0=安全 1=均衡 2=极速
#define MXB_KEY_ANIM_MULT       @"animMultiplier"   // Double  动画倍率 (1~100)
#define MXB_KEY_ANIM_FLOOR      @"animFloor"        // Double  动画时长下限秒 (0.008~0.05)
#define MXB_KEY_TRANSITION      @"transitionBoost"  // Bool    转场/启动动画加速
#define MXB_KEY_INTERACTION     @"interactionBoost" // Bool    交互响应优化（触摸/滚动）
#define MXB_KEY_BACKGROUND      @"backgroundKeepAlive" // Bool 真后台保活
#define MXB_KEY_BG_MODE         @"bgMode"           // Int     保活强度 0=音频 1=音频+任务 2=全策略
#define MXB_KEY_SAFE_LIST       @"protectBundleIDs" // [String] 保护名单（命中则降安全档）
#define MXB_KEY_CIRCUIT         @"circuitBreaker"   // Bool    安全熔断开关
#define MXB_KEY_CIRCUIT_WINDOW  @"circuitWindowSec" // Double  熔断统计窗口秒
#define MXB_KEY_CIRCUIT_LIMIT   @"circuitLimit"     // Int     窗口内异常上限

// 档位默认倍率
#define MXB_PROFILE_SAFE_MULT   8.0
#define MXB_PROFILE_BALANCED    24.0
#define MXB_PROFILE_TURBO       50.0

// 对外只读接口（供诊断/统计浮层查询）
@interface MXBBoost : NSObject
+ (NSString *)version;
+ (BOOL)isEnabled;
+ (double)effectiveMultiplier;
+ (NSInteger)currentProfile;
+ (NSDictionary *)runtimeSnapshot;   // 当前生效配置 + 统计
@end

#endif /* MXB_BOOST_H */
