//
//  MXBBackground.m
//  mdcX Boost — 真后台保活（自研）
//
//  原理（Apple 公开机制组合）：
//   1) 后台播放静音音频：声明 audio 后台类别，让进程在切后台后保持运行配额
//   2) 后台任务续期：beginBackgroundTask 在过期前续期，延长后台执行窗口
//   3) 心跳定时器：维持音频会话活跃，防止被系统判定为空闲而挂起
//
//  强度分档 bgMode：
//   0 = 仅静音音频；1 = 音频 + 后台任务；2 = 全策略（+ 心跳 + 定时刷新）
//  注意：iOS 对后台有系统级上限，无法保证"永久"存活；本模块把存活概率最大化。
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "MXBBoost.h"
#import "MXBConfig.h"

static BOOL MXBBackgroundKeeperInstalledFlag = NO;
static UIBackgroundTaskIdentifier mxbBgTask = 0;  // 0 == UIBackgroundTaskInvalid 运行时语义
static NSTimer *mxbHeartbeat = nil;
static AVAudioPlayer *mxbSilentPlayer = nil;
static BOOL mxbKeeperActive = NO;

// 生成一段 1 秒静音 WAV（44 字节头 + PCM 数据），无需外部资源文件
static NSData *MXBSilentAudioData(void) {
    NSMutableData *d = [NSMutableData data];
    uint32_t sampleRate = 44100;
    uint32_t dataLen = sampleRate * 2 / 10;   // 0.1 秒 16bit 单声道
    // RIFF header
    [d appendBytes:"RIFF" length:4];
    uint32_t chunkSize = 36 + dataLen; [d appendBytes:&chunkSize length:4];
    [d appendBytes:"WAVE" length:4];
    [d appendBytes:"fmt " length:4];
    uint32_t fmtLen = 16; [d appendBytes:&fmtLen length:4];
    uint16_t audioFmt = 1, channels = 1;
    uint32_t byteRate = sampleRate * channels * 2;
    uint16_t blockAlign = channels * 2, bits = 16;
    [d appendBytes:&audioFmt length:2];
    [d appendBytes:&channels length:2];
    [d appendBytes:&sampleRate length:4];
    [d appendBytes:&byteRate length:4];
    [d appendBytes:&blockAlign length:2];
    [d appendBytes:&bits length:2];
    [d appendBytes:"data" length:4];
    [d appendBytes:&dataLen length:4];
    [d appendBytes:[NSMutableData dataWithLength:dataLen].bytes length:dataLen];
    return d;
}

@interface MXBBackgroundKeeper : NSObject
+ (instancetype)shared;
- (void)start;
- (void)stop;
- (void)renew;
@end

@implementation MXBBackgroundKeeper
+ (instancetype)shared {
    static MXBBackgroundKeeper *inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [self new]; });
    return inst;
}

- (void)start {
    MXBConfig *cfg = [MXBConfig shared];
    if (!cfg.enabled || !cfg.backgroundKeepAlive || mxbKeeperActive) return;
    mxbKeeperActive = YES;
    NSLog(@"%@ background keeper START (mode=%ld)", MXB_LOG_TAG, (long)cfg.bgMode);

    // 1) 静音音频会话
    NSError *err = nil;
    AVAudioSession *sess = [AVAudioSession sharedInstance];
    [sess setCategory:AVAudioSessionCategoryPlayback error:&err];
    [sess setActive:YES error:&err];
    if (!mxbSilentPlayer) {
        mxbSilentPlayer = [[AVAudioPlayer alloc] initWithData:MXBSilentAudioData() error:&err];
        mxbSilentPlayer.numberOfLoops = -1;
        mxbSilentPlayer.volume = 0.0;   // 完全静音
        [mxbSilentPlayer prepareToPlay];
    }
    [mxbSilentPlayer play];

    // 2) 后台任务（mode>=1）
    if (cfg.bgMode >= 1) {
        if (mxbBgTask == UIBackgroundTaskInvalid) {
            mxbBgTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                [self renew];   // 过期前续期
            }];
        }
    }

    // 3) 心跳（mode>=2）
    if (cfg.bgMode >= 2 && !mxbHeartbeat) {
        mxbHeartbeat = [NSTimer scheduledTimerWithTimeInterval:30
                        target:self selector:@selector(renew) userInfo:nil repeats:YES];
    }
}

- (void)renew {
    if (!mxbKeeperActive) return;
    MXBConfig *cfg = [MXBConfig shared];
    // 音频续播
    if (mxbSilentPlayer && !mxbSilentPlayer.playing) [mxbSilentPlayer play];
    // 后台任务续期：结束旧的再开新的
    if (cfg.bgMode >= 1) {
        UIApplication *app = [UIApplication sharedApplication];
        if (mxbBgTask != UIBackgroundTaskInvalid) {
            [app endBackgroundTask:mxbBgTask];
            mxbBgTask = UIBackgroundTaskInvalid;
        }
        mxbBgTask = [app beginBackgroundTaskWithExpirationHandler:^{ [self renew]; }];
    }
}

- (void)stop {
    if (!mxbKeeperActive) return;
    mxbKeeperActive = NO;
    [mxbHeartbeat invalidate]; mxbHeartbeat = nil;
    [mxbSilentPlayer stop];
    UIApplication *app = [UIApplication sharedApplication];
    if (mxbBgTask != UIBackgroundTaskInvalid) {
        [app endBackgroundTask:mxbBgTask];
        mxbBgTask = UIBackgroundTaskInvalid;
    }
    NSLog(@"%@ background keeper STOP", MXB_LOG_TAG);
}
@end

void MXBInstallBackgroundKeeper(void) {
    // 监听前后台切换通知
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidEnterBackgroundNotification
        object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        [[MXBBackgroundKeeper shared] start];
    }];
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        // 回前台停止保活，省电
        [[MXBBackgroundKeeper shared] stop];
    }];
    MXBBackgroundKeeperInstalledFlag = YES;
    NSLog(@"%@ background keeper installed", MXB_LOG_TAG);
}

BOOL MXBBackgroundKeeperInstalled(void) { return MXBBackgroundKeeperInstalledFlag; }
