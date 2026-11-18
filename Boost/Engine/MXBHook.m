//
//  MXBHook.m
//  mdcX Boost — swizzle 助手实现
//

#import "MXBHook.h"
#import <objc/runtime.h>

static BOOL MXBSwizzle(Class cls, SEL original, SEL replacement, BOOL isMeta) {
    Method om = class_getInstanceMethod(cls, original);   // 对 metaclass 调用即取类方法
    Method rm = class_getInstanceMethod(cls, replacement);
    if (!om || !rm) {
        NSLog(@"[mdcXBoost] swizzle skip (missing): %@ %@%@",
              NSStringFromClass(cls), isMeta ? @"+":@"-", NSStringFromSelector(original));
        return NO;
    }
    // 若原方法不在本类（来自父类），先加一个再交换，避免污染父类
    IMP origIMP = method_getImplementation(om);
    const char *types = method_getTypeEncoding(om);
    Class target = cls;
    if (!class_addMethod(cls, original, origIMP, types)) {
        // 已在类中，直接交换
    }
    Method nowOrig = class_getInstanceMethod(target, original);
    Method nowRep  = class_getInstanceMethod(target, replacement);
    if (nowOrig && nowRep) method_exchangeImplementations(nowOrig, nowRep);
    return YES;
}

BOOL MXBSwizzleInstanceMethod(Class cls, SEL original, SEL replacement) {
    return MXBSwizzle(cls, original, replacement, NO);
}

BOOL MXBSwizzleClassMethod(Class metaCls, SEL original, SEL replacement) {
    return MXBSwizzle(metaCls, original, replacement, YES);
}
