//
//  TSRootSpawn.m
//  mdcX
//
//  直接移植 opa334/TrollStore Shared/TSUtil.m 的 spawnRoot（MIT）。
//

#import "TSRootSpawn.h"
#import <spawn.h>
#import <unistd.h>
#import <string.h>
#import <crt_externs.h>

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern char **environ;
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

NSString *const TSRebootHelperFlag = @"--mdcx-reboot-helper";

// Darwin 真值。2.4.2 之所以"点了没重启"，除了 iOS 上根本没有
// /sbin/reboot 之外，还因为绕道 killall -9 launchd —— pid 1 不吃 SIGKILL。
// 唯一可靠的路径是在 root 进程里直接调 reboot(2)。
//
// 这个常量曾经被写成 0（reboot(0) 必然返回 EINVAL），踩过一次；
// iOS SDK 未必提供 <sys/reboot.h>，用 #ifndef 兜底真值。
#ifndef RB_AUTOBOOT
#define RB_AUTOBOOT 0x08000004
#endif
extern int reboot(int);

static BOOL MDCArgvContains(const char *needle) {
    int argc = *_NSGetArgc();
    char **argv = *_NSGetArgv();
    if (argc <= 0 || argv == NULL) { return NO; }
    for (int i = 1; i < argc; i++) {
        if (argv[i] != NULL && strcmp(argv[i], needle) == 0) { return YES; }
    }
    return NO;
}

@implementation TSRootSpawn

#pragma mark - 重启助手（2.4.3）

+ (BOOL)isRebootHelperLaunch {
    return MDCArgvContains("--mdcx-reboot-helper");
}

+ (void)performRebootHelper {
    // 这里的执行时机与 SIOriginal 完全一致：进程已由 persona spawn 提为 root，
    // 且已过 dyld/ObjC 初始化、进入 App 自己的 main。这是真机验证过的位置。
    reboot(RB_AUTOBOOT);   // 成功即设备重启，本调用不会返回

    // 走到这里说明 reboot(2) 被拒（权限或内核）。
    // 兜底：强杀 launchd。pid 1 一般忽略 SIGKILL，但某些版本有效；
    // 保留它比什么都不做强。真正的成败由父进程读退出码判定。
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
    pid_t pid;
    char *killArgv[] = { "/usr/bin/killall", "-9", "launchd", NULL };
    posix_spawn(&pid, "/usr/bin/killall", NULL, &attr, killArgv, environ);
    posix_spawnattr_destroy(&attr);

    _exit(42);             // 42 = 助手里重启也失败了，父进程据此如实报错
}

#pragma mark - root spawn

+ (int)spawnRoot:(NSString *)path arguments:(NSArray<NSString *> *)args {
    NSMutableArray<NSString *> *argsM = (args ?: @[]).mutableCopy;
    [argsM insertObject:path atIndex:0];

    NSUInteger argCount = argsM.count;
    char **argsC = (char **)malloc((argCount + 1) * sizeof(char *));
    for (NSUInteger i = 0; i < argCount; i++) {
        argsC[i] = strdup(argsM[i].UTF8String);
    }
    argsC[argCount] = NULL;

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);

    // 官方参数：persona 99 + OVERRIDE，uid/gid 提为 0
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);

    pid_t pid;
    // environ 传 NULL，与官方一致，避免 root persona 下环境污染
    int spawnError = posix_spawn(&pid, path.UTF8String, NULL, &attr, (char *const *)argsC, NULL);
    posix_spawnattr_destroy(&attr);

    for (NSUInteger i = 0; i < argCount; i++) {
        free(argsC[i]);
    }
    free(argsC);

    if (spawnError != 0) {
        NSLog(@"[TSRootSpawn] posix_spawn(%@) failed: %d (%s)", path, spawnError, strerror(spawnError));
        return -200;
    }

    int status = 0;
    waitpid(pid, &status, 0);
    if ((status & 0x7f) != 0) {
        return -201; // 被信号终止
    }
    return (status >> 8) & 0xff;
}

+ (int)spawnSelfAsRootWaitingForExit:(nullable NSArray<NSString *> *)args
                             timeout:(NSTimeInterval)timeout {
    NSString *selfPath = NSBundle.mainBundle.executablePath;
    if (selfPath.length == 0) { return -200; }

    NSMutableArray<NSString *> *argsM = (args ?: @[]).mutableCopy;
    [argsM insertObject:selfPath atIndex:0];

    NSUInteger argCount = argsM.count;
    char **argsC = (char **)malloc((argCount + 1) * sizeof(char *));
    for (NSUInteger i = 0; i < argCount; i++) {
        argsC[i] = strdup(argsM[i].UTF8String);
    }
    argsC[argCount] = NULL;

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);

    pid_t pid = -1;
    // environ 透传：NULL 下加载 Swift 运行时的行为没有真机验证过，不冒险
    int spawnError = posix_spawn(&pid, selfPath.UTF8String, NULL, &attr,
                                 (char *const *)argsC, environ);
    posix_spawnattr_destroy(&attr);

    for (NSUInteger i = 0; i < argCount; i++) { free(argsC[i]); }
    free(argsC);

    if (spawnError != 0) {
        NSLog(@"[TSRootSpawn] spawn self failed: %d (%s)", spawnError, strerror(spawnError));
        return -200;
    }

    // 轮询等待：设备真的重启时本进程会随系统一起消失，永远走不到下面；
    // 只有子进程提前退出（说明 reboot 失败）或超时，才会返回结果。
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    for (;;) {
        int status = 0;
        pid_t r = waitpid(pid, &status, WNOHANG);
        if (r == pid) {
            if ((status & 0x7f) != 0) { return -201; }
            return (status >> 8) & 0xff;
        }
        if (r < 0) { return -200; }
        if ([deadline timeIntervalSinceNow] <= 0) { return -202; }
        usleep(100 * 1000);
    }
}

@end
