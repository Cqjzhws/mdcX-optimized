//
//  MXBHook.h
//  mdcX Boost — Objective-C runtime 交换助手（自研通用工具）
//

#ifndef MXB_HOOK_H
#define MXB_HOOK_H

#import <Foundation/Foundation.h>

/// 交换实例方法；返回 YES 表示成功（原方法与替换方法都存在）
BOOL MXBSwizzleInstanceMethod(Class cls, SEL original, SEL replacement);

/// 交换类方法；传入的是 metaclass
BOOL MXBSwizzleClassMethod(Class metaCls, SEL original, SEL replacement);

#endif /* MXB_HOOK_H */
