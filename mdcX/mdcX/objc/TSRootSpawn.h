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

/// 以 root 身份重新执行 App 自身，并在有限时间内等它退出。
///
/// 用途：`reboot(2)` 这类特权系统调用必须在**本进程内**发起，无法交给
/// 独立二进制代劳 —— 所以让自身再起一份 root 副本，它在 main 之前就被
/// `TSRootSpawn.m` 里的 constructor 截住、直接调 reboot()。
///
/// 与 `spawnRoot:arguments:` 的差异：environ 透传（NULL 环境下 dyld 加载
/// Swift 运行时的行为未经真机验证，这里按已验证写法传完整 environ）。
///
/// @param args 追加的参数（不含程序名）
/// @param timeout 最长等待秒数
/// @return 子进程退出码；spawn 失败 -200；被信号终止 -201；超时仍在运行 -202
+ (int)spawnSelfAsRootWaitingForExit:(nullable NSArray<NSString *> *)args
                             timeout:(NSTimeInterval)timeout;

/// 特权重启助手使用的参数标记。主程序带此参数启动时不会进入 UI。
extern NSString *const TSRebootHelperFlag;

/// 本次启动是否为「重启助手」模式。
+ (BOOL)isRebootHelperLaunch;

/// 执行特权重启：先 `reboot(RB_AUTOBOOT)`，被拒则兜底强杀 launchd。
///
/// 成功时设备立即重启、本调用不会返回；失败时 `_exit(42)`。
/// 调用点必须与 SIOriginal 一致 —— App 自己的 main 最开头（已过 dyld/ObjC 初始化，
/// 且进程已被 persona spawn 提为 root），过早（如 constructor）没有真机验证过。
+ (void)performRebootHelper;

@end

NS_ASSUME_NONNULL_END
