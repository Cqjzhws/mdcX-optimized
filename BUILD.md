# mdcX Plus — 构建与使用说明

这是一个基于 [speedyfriend433/mdcX](https://github.com/speedyfriend433/mdcX)（MIT）的增强版本，
整合了 **Res Setter**（[haoict/ResolutionSetterSwift](https://github.com/haoict/ResolutionSetterSwift)，MIT）
的显示分辨率修改能力，并修复了上游的若干并发缺陷与 Respring 失效问题。

> ⚠️ 本项目会修改系统文件与系统偏好域，属于实验性工具。
> **请在备用测试机上操作**，不要用于主力机。

---

## 一、相对上游的改动

| # | 改动 | 说明 |
|---|------|------|
| 1 | **新增分辨率模块** | `Services/ResolutionSetter.swift` + `Views/ResolutionView.swift`。机制取自对 Res Setter 1.1 的逆向：改写 `com.apple.iokit.IOMobileGraphicsFamily` 偏好域的 `canvas_width`/`canvas_height`，再重启 `cfprefsd` / `backboardd`。**不使用任何私有 API**，因此不依赖内核漏洞，在零页漏洞已被修补的 iOS 16.2+ 上依然可用。 |
| 2 | **修复 Respring 失效** | 新增 `Services/RootProc.swift` + 随包 `killall` + Info.plist 的 `TSRootBinaries`。TrollStore 只对它声明并随包分发的二进制授予 root；原实现调用的系统路径 `/usr/bin/killall` **不在授权范围内**，在未越狱设备上会静默失败。 |
| 3 | **移除 `system()` 调用** | 改为 `posix_spawn` 直接 exec，不经 `/bin/sh`，消除命令注入面并省掉一次多余的 shell fork。 |
| 4 | **修复数据竞争（一）** | `ExploitManager` 原本对 `[String?]` 做并发下标写入 —— 典型数据竞争，可能丢结果、错位甚至崩溃。改为加锁收集后在主线程统一排序汇总。 |
| 5 | **修复数据竞争（二）** | 成功计数原在异步队列自增、却在外层立即读取，计数经常不准。改为全部完成后统一统计。 |
| 6 | **修复数据竞争（三）** | `applyAllTweaks` 的 `summary` 字符串被多个并发回调无锁拼接。改为 `NSLock` 保护。 |
| 7 | **两页签互斥** | 文件美化与分辨率都会重启 `backboardd`，通过根视图共享的 busy 标记保证二者不会并发执行。 |
| 8 | **改为实体 Info.plist** | 上游用 `GENERATE_INFOPLIST_FILE`，无法声明 `TSRootBinaries`；现改用 `Resources/Info.plist`。同时把 `UIFileSharingEnabled` 设为 `false`（root 工具不应对外暴露文件系统）。 |

### 关于 `TSRootBinaries`（重点）

TrollStore 通过 Info.plist 中的 `TSRootBinaries` 数组，给 **App 包内** 指定的可执行文件授予 root 权限。
判定依据是「随包分发」，因此 **系统路径下的只读工具无法被提权**。

```
Resources/Info.plist
  → TSRootBinaries = [ "killall" ]

tools/killall
  → 构建时由 "Copy Root Helper" 阶段复制到 App 包根目录，
    并 chmod 755，使其出现在 TSRootBinaries 的授权范围内。
```

安装后可在设备上自检：若「Respring」能真正让界面重启，说明提权生效。

---

## 二、构建步骤

### 1. 环境

- macOS + Xcode 16 或更高（工程使用了文件系统同步组，Xcode 15 及以下无法打开）
- 一台可用的 iOS 设备（**建议备用机**）

### 2. 打开与配置

```bash
cd mdcX-Plus/mdcX
open mdcX.xcodeproj
```

在 Xcode 中修改为自己账号的签名：

- `mdcX` target → Signing & Capabilities
  - Team 改为你自己的开发者账号
  - Bundle Identifier 改为唯一值（原为 `com.speedy67.mdcX`）
- 测试 target（`mdcXTests` / `mdcXUITests`）如果不需要，可直接删除

### 3. 确保 killall 可执行

如果你是从 Windows 传过来的，文件的可执行位可能丢失。构建阶段会自行 `chmod 755`，
但建议在仓库里也设置一次：

```bash
chmod +x tools/killall
```

> `tools/killall` 是 Apple 提供的 BSD `killall`（源自 Res Setter 的 IPA）。
> 也可以从设备上 `/usr/bin/killall` 复制一份，或直接使用 Res Setter IPA 中的同名文件。
> 仅供自用，请勿再分发。

### 4. 导出 IPA

```bash
xcodebuild -project mdcX.xcodeproj \
           -scheme mdcX \
           -configuration Release \
           -sdk iphoneos \
           -derivedDataPath build \
           clean build

# 打包
cd build/Build/Products/Release-iphoneos
mkdir Payload
cp -R mdcX.app Payload/
zip -qr mdcX-Plus.ipa Payload
```

### 5. 安装

把 `mdcX-Plus.ipa` 传到设备，用 **TrollStore** 安装
（必须用 TrollStore，否则拿不到 root 权限，两个核心功能都无法工作）。

---

## 三、使用说明

### 美化页（文件清零）

与上游一致：点击每行的 🔨 应用单项，或右上角「Apply All」批量应用。
左上角按钮为 Respring。

### 分辨率页（新增）

| 操作 | 说明 |
|------|------|
| 预设 | 4 个内置预设，对应主流大屏机型的原生画布尺寸 |
| 自定义 | 手动输入宽 / 高 |
| 应用 | 写入偏好域并重启显示服务，界面会短暂黑屏后回到锁屏 |
| 还原 | 从自动备份写回原始设置 |

**安全性设计**

- 修改前自动把原始 plist 备份到 `/private/var/tmp/com.local.mdcx.resolution/`
- 内置取值范围校验（宽高下限、上限、长宽比 0.40–0.57），明显不合理的值会被直接拒绝
- 校验函数是纯函数，**不会产生副作用** —— 只有用户在确认弹窗中点「应用」才会真正写入

**若出现黑屏**：强制重启设备即可恢复（长按电源＋音量减）。

---

## 四、已知限制

1. **零页功能在 iOS 16.2+ 已失效** —— 这是 Apple 修补了 `VM_BEHAVIOR_ZERO_WIRED_PAGES` 的结果，非本项目的 bug。此时只有分辨率功能仍可用。
2. **分辨率会全局影响布局** —— 所有 App 按新画布重排，部分 App 会错位；Dock、键盘、状态栏高度也会变化。
3. **触控映射** —— 非原生比例下触摸坐标可能轻微偏移。
4. **前提是 TrollStore** —— 普通侧载安装拿不到 root，两个功能都不可用。
5. **快门静音** —— 部分地区对相机快门声有法律或行业约束，请自行评估当地法规。
6. 分辨率相关键的物理含义（像素 / 点）依机型与系统版本可能不同，预设值取自 Res Setter 的内置列表；若效果不符，请以自定义输入微调。

---

## 五、致谢与许可

- [speedyfriend433/mdcX](https://github.com/speedyfriend433/mdcX) —— MIT，零页利用 PoC 与主体 UI
- [haoict/ResolutionSetterSwift](https://github.com/haoict/ResolutionSetterSwift) —— MIT，分辨率修改机制
- Google Project Zero —— `VM_BEHAVIOR_ZERO_WIRED_PAGES` 技术公开研究

本衍生项目同样以 MIT 分发，详见 `LICENSE`。
