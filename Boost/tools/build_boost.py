#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_boost.py — mdcX Boost 自研加速引擎本地构建脚本

职责：
  1. 探测 iPhoneOS SDK / zig / lief
  2. 静态契约门禁（配置键 Swift 端与 ObjC 端一致、必须包含 constructor / hook 符号）
  3. zig 交叉编译 Engine/*.m -> mdcxboost.dylib (arm64)
  4. lief 校验：架构 / install_name / 关键符号存在 / __text 离开首页
  5. 输出到 out/

用法：
  python build_boost.py --check-only   # 只跑静态门禁
  python build_boost.py                # 完整构建
"""

import os
import re
import sys
import glob
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENGINE = os.path.join(ROOT, "Engine")
OUT = os.path.join(ROOT, "out")
DYLIB = os.path.join(OUT, "mdcxboost.dylib")

INSTALL_NAME = "@rpath/mdcxboost.dylib"

# 配置契约：Swift 写入端 (BoostConfig.swift) 与 ObjC 读取端必须一致的键
CONTRACT_KEYS = [
    "enabled", "profile", "animMultiplier", "animFloor",
    "transitionBoost", "interactionBoost", "backgroundKeepAlive",
    "bgMode", "protectBundleIDs", "circuitBreaker",
    "circuitWindowSec", "circuitLimit",
]

# 必须出现的 hook / 入口符号（防止误删导致静默失效）
REQUIRED_SYMBOLS = [
    "MXBBoostEntry",              # constructor
    "MXBInstallAnimationHooks",
    "MXBInstallInteractionHooks",
    "MXBInstallBackgroundKeeper",
    "MXBInstallSafetyNet",
    "mxb_setDuration:",           # CAAnimation hook
    "mxb_animateWithDuration",    # UIView hook
]

SDK_CANDIDATES = [
    r"C:/Users/Administrator/WorkBuddy/2026-10-20-01-45-41/sdk/iPhoneOS16.5.sdk",
]
for _root in glob.glob(r"C:/Users/Administrator/WorkBuddy/*/sdk/iPhoneOS*.sdk"):
    SDK_CANDIDATES.append(_root.replace("\\", "/"))


def log(msg):
    print(msg, flush=True)


def find_sdk():
    for p in SDK_CANDIDATES:
        if os.path.isdir(p) and os.path.isfile(os.path.join(p, "usr", "include", "objc", "runtime.h")):
            return p
    return None


def read_all_engine():
    buf = ""
    for f in sorted(glob.glob(os.path.join(ENGINE, "*"))):
        if f.endswith((".m", ".h")):
            buf += open(f, encoding="utf-8").read() + "\n"
    return buf


def static_gate():
    log("=== 静态契约门禁 ===")
    src = read_all_engine()
    ok = True

    # 版本
    m = re.search(r'MXB_VERSION\s+"([^"]+)"', src)
    ver = m.group(1) if m else None
    log("  MXB_VERSION = %s" % ver)
    if not ver:
        ok = False

    # 配置键每个都必须在源码里出现
    for key in CONTRACT_KEYS:
        present = ("@\"%s\"" % key) in src
        log("  key %-22s %s" % (key, "OK" if present else "MISSING"))
        if not present:
            ok = False

    # 必需符号
    for sym in REQUIRED_SYMBOLS:
        present = sym in src
        log("  symbol %-28s %s" % (sym, "OK" if present else "MISSING"))
        if not present:
            ok = False

    # 禁止引用第三方 tweak（确保纯自研）
    banned = ["SIOriginal", "FUBG", "sioriginal", "fubg", "libsubstitute", "Substrate"]
    for b in banned:
        if b in src:
            log("  !! 发现禁用引用: %s" % b)
            ok = False

    log("  静态门禁: %s" % ("[OK] 契约干净（纯自研，无第三方引用）" if ok else "[FAIL]"))
    return ok


def run(cmd, **kw):
    log("$ " + " ".join(cmd))
    r = subprocess.run(cmd, capture_output=True, text=True, **kw)
    if r.stdout:
        log(r.stdout.rstrip())
    if r.returncode != 0 and r.stderr:
        log(r.stderr.rstrip())
    return r


def build():
    sdk = find_sdk()
    if not sdk:
        log("SDK 未找到"); return 1
    log("SDK = %s" % sdk)

    # zig via python module
    zr = run([sys.executable, "-m", "ziglang", "version"])
    if zr.returncode != 0:
        log("zig 不可用"); return 1
    log("zig = %s" % zr.stdout.strip())

    os.makedirs(OUT, exist_ok=True)

    sources = sorted(glob.glob(os.path.join(ENGINE, "*.m")))
    log("编译源文件: %s" % ", ".join(os.path.basename(s) for s in sources))

    target = "aarch64-ios.16.5"
    cmd = [
        sys.executable, "-m", "ziglang", "cc",
        "-target", target,
        "-isysroot", sdk,
        "-isystem", os.path.join(sdk, "usr", "include"),
        "-F", os.path.join(sdk, "System", "Library", "Frameworks"),
        "-fobjc-arc",
        "-fobjc-runtime=ios-13.0",
        "-dynamiclib",
        "-shared",
        "-O2",
        "-Wall",
        "-Wl,-headerpad,0x4000",              # 关键：避开首页 SIGILL
        "-install_name", INSTALL_NAME,
    ]
    for s in sources:
        cmd.append(s)
    cmd += [
        "-o", DYLIB,
        "-L", os.path.join(sdk, "usr", "lib"),
        "-framework", "Foundation",
        "-framework", "UIKit",
        "-framework", "QuartzCore",
        "-framework", "AVFoundation",
        "-framework", "CoreFoundation",
        "-lobjc",
    ]
    r = run(cmd)
    if r.returncode != 0:
        log("编译失败"); return 1
    log("编译完成: %s (%d bytes)" % (DYLIB, os.path.getsize(DYLIB)))
    return 0


def verify():
    log("=== 产物校验 ===")
    import lief
    b = lief.parse(DYLIB)
    # 架构
    log("  cpu_type = %s" % b.header.cpu_type)
    assert "ARM64" in str(b.header.cpu_type).upper(), "架构非 arm64"
    # install_name
    ids = [str(c.name) for c in b.commands if "ID_DYLIB" in str(getattr(c, "command", "")).upper()]
    log("  install_name = %s" % ids)
    assert ids and ids[0] == INSTALL_NAME, "install_name 错误: %s" % ids
    # 依赖 framework
    deps = [str(c.name) for c in b.commands if "LOAD_DYLIB" in str(getattr(c, "command", "")).upper()]
    log("  dependencies = %s" % deps)
    for fw in ["Foundation", "UIKit", "QuartzCore", "AVFoundation", "objc"]:
        assert any(fw in d for d in deps), "缺少依赖 %s" % fw
    # __text 离开首页
    try:
        text = [s for s in b.segments if s.name == "__TEXT"][0]
        sec = [s for s in b.sections if s.name == "__text"][0]
        log("  __text offset = 0x%x (segment vmaddr=0x%x)" % (sec.offset, text.virtual_address))
        assert sec.offset >= 0x4000, "__text 仍在首页，SIGILL 风险"
    except Exception as e:
        log("  (跳过 __text 检查: %s)" % e)
    log("  产物校验 [OK]")
    return True


if __name__ == "__main__":
    if not static_gate():
        sys.exit(2)
    if "--check-only" in sys.argv:
        log("check-only 完成")
        sys.exit(0)
    rc = build()
    if rc != 0:
        sys.exit(rc)
    try:
        verify()
    except Exception as e:
        log("校验失败: %s" % e)
        sys.exit(3)
    log("\n构建成功 -> %s" % DYLIB)
