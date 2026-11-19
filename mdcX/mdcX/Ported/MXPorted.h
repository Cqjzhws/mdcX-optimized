#ifndef MXPorted_h
#define MXPorted_h
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// 极速IOS v2.4.6 配置器根页面（引擎/手感/系统/高级 4 个子页 + 自绘悬浮胶囊）
UIViewController *MXCreateJisuRootVC(void);
// 清理Pro v1.0.0 清理页（7 分类 + 白名单 + 清理历史 + root helper）
UIViewController *MXCreateCleanRootVC(void);

NS_ASSUME_NONNULL_END
#endif
