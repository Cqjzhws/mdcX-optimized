//
//  MXBConfig.h
//  mdcX Boost — 配置读取层
//

#ifndef MXB_CONFIG_H
#define MXB_CONFIG_H

#import <Foundation/Foundation.h>
#import "MXBBoost.h"

@interface MXBConfig : NSObject

+ (instancetype)shared;

/// 重新从 plist 载入配置（进程启动 / 收到 reload 通知时调用）
- (void)reload;

// 生效配置（已合并默认值 + 保护名单降级）
@property (nonatomic, readonly) BOOL enabled;
@property (nonatomic, readonly) NSInteger profile;      // 0/1/2
@property (nonatomic, readonly) double animMultiplier;
@property (nonatomic, readonly) double animFloor;
@property (nonatomic, readonly) BOOL transitionBoost;
@property (nonatomic, readonly) BOOL interactionBoost;
@property (nonatomic, readonly) BOOL backgroundKeepAlive;
@property (nonatomic, readonly) NSInteger bgMode;
@property (nonatomic, readonly) BOOL circuitEnabled;
@property (nonatomic, readonly) double circuitWindow;
@property (nonatomic, readonly) NSInteger circuitLimit;
@property (nonatomic, readonly) NSArray<NSString *> *protectList;

/// 当前进程 bundle id 是否在保护名单里
@property (nonatomic, readonly) BOOL currentAppProtected;

/// 熔断是否已触发（触发后 animMultiplier 会被压到安全档）
@property (nonatomic, readonly) BOOL circuitTripped;

/// 上报一次异常，供熔断统计；返回当前是否触发熔断
- (BOOL)reportAnomaly;

/// 当前生效配置的快照（诊断用）
- (NSDictionary *)snapshot;

@end

#endif /* MXB_CONFIG_H */
