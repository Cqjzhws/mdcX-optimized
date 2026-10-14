//
//  TSRootSpawn.h
//  mdcX
//
//  TrollStore 官方 root spawn 桥接（照搬 opa334/TrollStore Shared/TSUtil.m spawnRoot）。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TSRootSpawn : NSObject

/// 以 root（persona 99, uid/gid 0）spawn 一个二进制并同步等待退出。
/// 前置：主 App 已脱离沙盒且带 com.apple.private.persona-mgmt entitlement
///      （由 TrollStore 安装时保留）。
/// @param path 可执行文件绝对路径（如包内 killall）
/// @param args 参数列表（不含程序名，方法内部自动补 argv[0]）
/// @return 子进程退出码；spawn 本身失败返回 -200
+ (int)spawnRoot:(NSString *)path arguments:(nullable NSArray<NSString *> *)args;

@end

NS_ASSUME_NONNULL_END
