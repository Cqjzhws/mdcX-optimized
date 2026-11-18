//
//  MXBSafety.m
//  mdcX Boost — 安全网：配置热更新 + 异常熔断（自研）
//
//  1) 监听 Darwin 通知 com.mdcx.boost.reload → mdcX App 改档位后立即生效，无需重启 App
//  2) 捕获未处理 NSException → 计入熔断统计；窗口内超阈值 → 全局降安全档
//     这保证"极限加速把某个 App 搞崩"时能自愈，避免连续闪退。
//

#import <Foundation/Foundation.h>
#import <notify.h>
#import "MXBBoost.h"
#import "MXBConfig.h"

static BOOL MXBSafetyNetInstalledFlag = NO;
static NSUncaughtExceptionHandler *mxbPrevHandler = NULL;

static void MXBExceptionHandler(NSException *exception) {
    // 上报给熔断统计（可能触发降级）
    [[MXBConfig shared] reportAnomaly];
    NSLog(@"%@ uncaught exception captured: %@ (anomaly reported)", MXB_LOG_TAG, [exception reason]);
    if (mxbPrevHandler) mxbPrevHandler(exception);   // 转给原 handler，不改变原有崩溃行为
}

static void MXBReloadCallback(int token) {
    (void)token;
    [[MXBConfig shared] reload];
    NSLog(@"%@ reload notification received, config refreshed", MXB_LOG_TAG);
}

void MXBInstallSafetyNet(void) {
    // 1) Darwin 通知热更新
    int token = 0;
    int status = notify_register_dispatch(MXB_NOTIFY_RELOAD,
                                          &token,
                                          dispatch_get_main_queue(),
                                          ^(int t) { MXBReloadCallback(t); });
    if (status != NOTIFY_STATUS_OK) {
        NSLog(@"%@ notify_register failed: %d", MXB_LOG_TAG, status);
    }

    // 2) 异常熔断
    mxbPrevHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&MXBExceptionHandler);

    MXBSafetyNetInstalledFlag = YES;
    NSLog(@"%@ safety net installed (reload + circuit breaker)", MXB_LOG_TAG);
}

BOOL MXBSafetyNetInstalled(void) { return MXBSafetyNetInstalledFlag; }
