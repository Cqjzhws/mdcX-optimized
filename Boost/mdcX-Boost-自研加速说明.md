# mdcX Boost — mdcX Max 自研运行时加速引擎

> 本模块是 mdcX Max 项目**从零自研**的加速能力（MXB = mdcX Boost）。
> 全部代码为本次新写，仅使用 Apple 公开 API（Objective-C runtime / Foundation / UIKit /
> QuartzCore / AVFoundation / Darwin notify）。**不含任何第三方 tweak 项目的代码、类名、宏或资源。**
> 构建脚本内置黑名单门禁，一旦出现第三方字样即构建失败。

## 0. 为什么必须这么做

mdcX 本体是 **MacDirtyCow 文件清零工具**（`mdcx_core.c` / `TweakActionType.zeroOutFiles`），
只在 iOS 14.0–16.1.2 有效，在 iOS 16.2 已失效；而且文件清零在原理上无法实现动画倍率、
UI 响应、真后台保活这类**运行时行为**。

因此本次改造的正确路径是：在 mdcX 仓库里新增一套自研的**运行时 hook 引擎**，
并把它**做成 mdcX 的一等功能**（新增 tweak 分类、配置服务、管理入口、界面），
mdcX 原有的 25 项文件清零功能一行未动。

## 1. 涉及的模块

| 层 | 文件 | 作用 |
|---|---|---|
| 引擎(C/ObjC) | `Boost/Engine/MXBBoost.h` | 公共契约：配置键、通知名、版本、档位倍率宏 |
| | `MXBConfig.m/.h` | 读取共享 plist、应用保护名单/熔断降级、快照 |
| | `MXBHook.m/.h` | 自研 swizzle 助手（实例/类方法交换） |
| | `MXBAnimation.m` | **动画核心**：UIView 动画 x5、CAAnimation、CATransaction 时长压缩 |
| | `MXBInteraction.m` | 交互优化：滚动惯性、长按识别时长 |
| | `MXBBackground.m` | 真后台保活：静音音频 + 后台任务 + 心跳 |
| | `MXBSafety.m` | 安全网：Darwin 通知热更新 + 异常熔断 |
| | `MXBEntry.m` | constructor 注入入口，安装全部 hook |
| 构建 | `Boost/tools/build_boost.py` | 静态契约门禁 + zig 交叉编译 + lief 校验 |
| Swift | `mdcX/mdcX/Services/BoostConfig.swift` | 配置写入层（档位模型 + plist 写 + 通知） |
| | `Services/BoostManager.swift` | 加速管理入口（应用/开关/状态/注入指引） |
| | `Services/ExploitManager.swift` | 新增 `.runtimeBoost` 执行分支 |
| | `Models/tweak.swift` | 新增 `.runtimeBoost` action 类型 |
| | `Services/TweakRegistry.swift` | 新增 `Performance` 分类 + 6 个加速项 |
| | `Views/BoostView.swift` | 「加速」标签页控制台 |
| | `mdcXApp.swift` | 主界面新增「加速」tab |

Xcode 工程使用 `PBXFileSystemSynchronizedRootGroup`，新增的 3 个 Swift 文件会自动纳入编译，无需改 pbxproj。

## 2. 关键参数与开关

配置写在共享 plist：`/var/mobile/Library/Preferences/com.mdcx.boost.plist`
（必须用绝对路径——dylib 注入到任意进程后 `NSHomeDirectory()` 指向目标进程容器，
读不到 App 容器里的配置）。Swift 与 ObjC 端 12 个键严格一致，构建门禁校验。

| 键 | 类型 | 默认 | 含义 |
|---|---|---|---|
| `enabled` | Bool | true | 总开关 |
| `profile` | Int | 2 | 档位：0安全/1均衡/2极速 |
| `animMultiplier` | Double | 跟随档位 | 动画倍率上限（不能超档位） |
| `animFloor` | Double | 0.012 | 时长下限（帧保底，防"闪现感"） |
| `transitionBoost` | Bool | true | 转场/启动动画加速 |
| `interactionBoost` | Bool | true | 滚动惯性 / 长按识别优化 |
| `backgroundKeepAlive` | Bool | true | 真后台保活 |
| `bgMode` | Int | 1 | 保活强度：0音频/1+后台任务/2全策略 |
| `protectBundleIDs` | [String] | 微信/企业微信/Safari | 保护名单，命中降安全档 |
| `circuitBreaker` | Bool | true | 安全熔断 |
| `circuitWindowSec` | Double | 10 | 熔断统计窗口（秒） |
| `circuitLimit` | Int | 6 | 窗口内异常上限，超过即降档 |

**档位倍率**：安全 8× / 均衡 24× / 极速 50×。
**帧保底**：所有动画压缩后不低于 `animFloor`，避免 0 时长导致的跳变/不流畅。
**时长分类**：循环/重复动画（`repeatCount>1`）不压缩，避免破坏动画语义。

## 3. 风险与回滚

**已知风险**：
1. 极速 50× 下少数第三方 App 可能出现动画异常；保护名单 + 熔断已默认兜底。
2. 后台保活增加耗电；`bgMode=2` 更明显。
3. 部分系统动画时长被硬编码在私有 API 中，hook 覆盖不到，效果因 iOS 版本而异。
4. 文件清零类旧 tweak 在 iOS 16.2 本来就不生效，与本模块无关。

**三档回滚**：
- **单 App 排障**：把该 App 的 bundle id 加进 `protectBundleIDs`，它自动降安全档。
- **整体降档**：在「加速」页切「安全」档，或点「恢复加速默认配置」。
- **完全关闭**：「加速」页关总开关（写 `enabled=false`），已注入进程即时停止 hook（无需重启）。
- **彻底移除**：用 TrollFools 移除注入的 dylib 并重启设备，系统回到原生状态。

所有回滚都是配置级或注入级，**不改系统文件、不留残留**。

## 4. 验证优化效果的具体检查点

**A. 编译/静态验证（已在 PC 完成）**
- `cd Boost && python tools/build_boost.py`：静态门禁 `[OK]` + 编译成功 + 产物校验 `[OK]`。
- 产物 `Boost/out/mdcxboost.dylib`：arm64、install_name `@rpath/mdcxboost.dylib`、
  依赖 5 个 framework、`__text@0x4cd8`（已离开首页，规避 SIGILL）。

**B. 真机日志（注入后用 macOS 控制台 / 越狱日志过滤 `mdcXBoost`）**
```
[mdcXBoost] mdcX Boost v1.0.0 launching in process: com.apple.springboard
[mdcXBoost] animation hooks installed (UIView x5, CAAnimation, CATransaction)
[mdcXBoost] interaction hooks installed (UIScrollView, UIGestureRecognizer)
[mdcXBoost] background keeper installed
[mdcXBoost] safety net installed (reload + circuit breaker)
[mdcXBoost] READY | profile=2 mult=50.0 floor=0.012 protected=0 circuit=1
```
看到 `READY` 且各 hook `installed`，说明引擎生效。改档位后应看到
`[mdcXBoost] reload notification received, config refreshed`。

**C. 体感检查（真机自测）**
1. 动画：控制中心上拉、App 开关、页面 push/pop —— 极速档明显更快且不"闪现"（帧保底）。
2. 交互：列表滚动更快停住、长按图标更快弹出菜单。
3. 启动：App 冷启动到首帧的转场更短。
4. 后台：音乐/导航类 App 切后台后停留更久不易被杀。
5. 保护名单：打开微信应自动降安全档（日志 `protected=1`）。
6. 熔断：连续触发异常后日志出现 `CIRCUIT BREAKER TRIPPED`，倍率自动降 8×。

## 5. 构建与注入

```bash
# 本地构建引擎
cd Boost
python tools/build_boost.py            # 产物: out/mdcxboost.dylib

# 真机部署
# 1) 用 Xcode 编译 mdcX App（含新增的加速页），TrollStore 安装
# 2) 把 out/mdcxboost.dylib 放进 App 包（或直接从包内取 mdcxboost 资源）
# 3) 巨魔 TrollFools 注入到 SpringBoard / 目标 App
# 4) 打开 mdcX「加速」页选档位，重启目标 App 生效
```

> 说明：PC 端无 Xcode / swiftc，Swift 层已完成严格静态审查（括号配对、枚举 case、
> 协议一致性、LogLevel 签名、配置键契约），但真机编译需在有 Xcode 的 Mac 上完成。
