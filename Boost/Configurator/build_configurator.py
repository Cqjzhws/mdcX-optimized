#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_configurator.py — 编译打包 mdcX Boost 配置器 IPA（巨魔免签，可装）

纯 Objective-C / UIKit，不依赖 SwiftUI / Xcode。
工具链：ziglang(clang+lld) + iPhoneOS SDK + PIL 图标。
用法：python build_configurator.py
"""
import os, sys, glob, shutil, zipfile, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "build")
PY = sys.executable
APP = "MXBConfig"
DISPLAY = "mdcX Boost"
BUNDLE_ID = "com.mdcx.boost.config"
VERSION = "1.0"
TARGET = "aarch64-ios.13.0"

SDK_CANDIDATES = [r"C:/Users/Administrator/WorkBuddy/2026-10-20-01-45-41/sdk/iPhoneOS16.5.sdk"]
for _r in glob.glob(r"C:/Users/Administrator/WorkBuddy/*/sdk/iPhoneOS*.sdk"):
    SDK_CANDIDATES.append(_r.replace("\\", "/"))

def find_sdk():
    for p in SDK_CANDIDATES:
        if os.path.isfile(os.path.join(p, "usr", "include", "objc", "runtime.h")):
            return p
    return None

def run(cmd):
    print("  $ " + " ".join(cmd[:8]) + (" ..." if len(cmd) > 8 else ""))
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        print(r.stdout[-3000:]); print(r.stderr[-3000:])
        raise SystemExit("failed: %d" % r.returncode)
    if r.stderr.strip(): print("  [warn]", r.stderr.strip()[-600:])
    return r

INFO = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
	<key>CFBundleDisplayName</key><string>{display}</string>
	<key>CFBundleExecutable</key><string>{app}</string>
	<key>CFBundleIdentifier</key><string>{bid}</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>{display}</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>{ver}</string>
	<key>CFBundleVersion</key><string>{ver}</string>
	<key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
	<key>CFBundleIcons</key><dict>
		<key>CFBundlePrimaryIcon</key><dict>
			<key>CFBundleIconFiles</key><array><string>AppIcon60x60</string></array>
			<key>UIPrerenderedIcon</key><true/>
		</dict>
	</dict>
	<key>CFBundleIcons~ipad</key><dict>
		<key>CFBundlePrimaryIcon</key><dict>
			<key>CFBundleIconFiles</key><array><string>AppIcon76x76</string><string>AppIcon83.5x83.5</string></array>
			<key>UIPrerenderedIcon</key><true/>
		</dict>
	</dict>
	<key>LSRequiresIPhoneOS</key><true/>
	<key>MinimumOSVersion</key><string>13.0</string>
	<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
	<key>UILaunchScreen</key><dict/>
	<key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
	<key>UIStatusBarStyle</key><string>UIStatusBarStyleLightContent</string>
	<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
	<key>UISupportedInterfaceOrientations~ipad</key><array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
"""

def main():
    sdk = find_sdk()
    if not sdk: print("SDK 未找到"); sys.exit(1)
    print("[SDK]", sdk)
    os.makedirs(OUT, exist_ok=True)

    src = os.path.join(HERE, "main.m")
    obj = os.path.join(OUT, APP + ".o")
    exe = os.path.join(OUT, APP)
    cf = [PY,"-m","ziglang","cc","-target",TARGET,"-isysroot",sdk,
          "-isystem",os.path.join(sdk,"usr","include"),
          "-F",os.path.join(sdk,"System","Library","Frameworks"),
          "-fobjc-arc","-fobjc-exceptions","-ObjC","-O2","-Wall",
          "-Wno-unused-parameter","-Wno-deprecated-declarations"]

    print("[1/4] 编译 ObjC")
    run(cf + ["-c", src, "-o", obj])
    print("[2/4] 链接")
    ld = cf + ["-Wl,-headerpad,0x4000", "-L", os.path.join(sdk,"usr","lib"), obj, "-o", exe]
    for f in ["UIKit","Foundation","CoreFoundation","CoreGraphics","QuartzCore"]:
        ld += ["-framework", f]
    ld += ["-l", "objc"]
    run(ld)

    print("[3/4] 组装 .app")
    appdir = os.path.join(OUT, APP + ".app")
    if os.path.isdir(appdir): shutil.rmtree(appdir)
    os.makedirs(appdir)
    dst = os.path.join(appdir, APP)
    shutil.copy2(exe, dst); os.chmod(dst, 0o755)
    with open(os.path.join(appdir,"Info.plist"),"w",encoding="utf-8") as f:
        f.write(INFO.format(display=DISPLAY, app=APP, bid=BUNDLE_ID, ver=VERSION))
    sys.path.insert(0, HERE)
    from make_icon import main as mkicon
    icons = mkicon(appdir)

    print("[4/4] 打成 IPA（巨魔免签）")
    ipa = os.path.join(HERE, "mdcXBoost配置器-%s.ipa" % VERSION)
    if os.path.exists(ipa): os.remove(ipa)
    with zipfile.ZipFile(ipa,"w",zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        def di(name):
            zi=zipfile.ZipInfo(name); zi.external_attr=(0o40755<<16)|0x10; return zi
        z.writestr(di("Payload/"), b"")
        z.writestr(di("Payload/%s.app/"%APP), b"")
        for fn in [APP,"Info.plist"]+icons:
            zp=os.path.join(appdir,fn)
            mode=0o100755 if fn==APP else 0o100644
            zi=zipfile.ZipInfo("Payload/%s.app/%s"%(APP,fn)); zi.external_attr=mode<<16
            z.write(zp, zi.filename)
            # 覆盖 external_attr
            z.getinfo(zi.filename).external_attr = mode<<16
    print("\n构建成功 -> %s (%d bytes)" % (ipa, os.path.getsize(ipa)))

if __name__ == "__main__":
    main()
