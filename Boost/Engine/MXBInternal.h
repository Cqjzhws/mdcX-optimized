//
//  MXBInternal.h
//  mdcX Boost — 内部模块安装函数声明
//

#ifndef MXB_INTERNAL_H
#define MXB_INTERNAL_H

#import <Foundation/Foundation.h>

void MXBInstallAnimationHooks(void);
BOOL MXBAnimationHooksInstalled(void);

void MXBInstallInteractionHooks(void);
BOOL MXBInteractionHooksInstalled(void);

void MXBInstallBackgroundKeeper(void);
BOOL MXBBackgroundKeeperInstalled(void);

void MXBInstallSafetyNet(void);
BOOL MXBSafetyNetInstalled(void);

#endif /* MXB_INTERNAL_H */
