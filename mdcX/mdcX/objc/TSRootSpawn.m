//
//  TSRootSpawn.m
//  mdcX
//
//  直接移植 opa334/TrollStore Shared/TSUtil.m 的 spawnRoot（MIT）。
//

#import "TSRootSpawn.h"
#import <spawn.h>

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

@implementation TSRootSpawn

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

@end
