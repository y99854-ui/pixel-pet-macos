# Pixel Pet macOS · 6722 修复版

Windows 6719 版的原生 macOS 移植，使用 Swift/AppKit。六种角色的像素矩形、两帧尾巴、眨眼、眼睛边界和独立睡垫配色均沿用 Windows 版数据。无需联网或第三方运行库。

6722 将开发单元测试与应用构建分开，修复仅安装命令行工具时因缺少 `XCTest` 而无法启动的问题。普通构建使用命令行工具编译应用、打包并执行 AppKit 自测；完整单元测试由独立入口和 CI 执行。6721 已修复 `CoreGraphics` 导入。

此修复版将偏好设置改为 `UserDefaults.standard`，解决新系统上以应用自身标识符创建 suite 后强制解包导致的启动崩溃；构建脚本也会记录失败步骤和退出码。

## 下载应用

从 [Releases](https://github.com/y99854-ui/pixel-pet-macos/releases) 下载 `Pixel-Pet-macOS-6722-arm64.zip`，解压后打开 `Pixel Pet.app`，或将完整应用复制到「应用程序」。

## 构建与启动

要求 macOS 12 或更新版本，支持 Apple Silicon 和 Intel。源码构建需要 Swift 5.7+（Xcode 14+ 的命令行工具）；未安装时在终端运行 `xcode-select --install`，完成系统安装提示后继续。

1. 下载并全部解压仓库。
2. 进入解压后的源码目录，双击 `Start-Pixel-Pet.command`。第一次会编译应用、打包并自动验证资源和窗口渲染，然后启动。
3. 构建后的应用位于 `dist/Pixel Pet.app`。以后可以直接双击，或复制到「应用程序」。复制整个 `.app`，不要单独移动其中的可执行文件。

也可在终端从仓库根目录执行：

```sh
cd pixel-pet-macos
./Build-Pixel-Pet.command
open 'dist/Pixel Pet.app'
```

默认生成与构建机器相同架构的应用。分别在 Apple Silicon 和 Intel 上构建对应版本。脚本进行本地临时签名；Release 提供 Apple Silicon（arm64）应用 ZIP，使用本地临时签名，尚未经过 Developer ID 签名和公证。Intel Mac 请从源码构建。若 macOS 对下载的源码启动脚本显示安全提示，请确认来源，按系统「隐私与安全性」中的提示允许执行；不要关闭系统安全检查。

若构建失败，脚本会在最后重复显示关键错误，并将完整输出保存到 `.build/pixel-pet-build-日期时间.log`。双击启动时会等待回车，方便复制错误。更新源码包后请解压到新目录再构建，避免复用旧的 `.app`。

## 互动

- 启动时轮换灰猫、柯基、饼干仓鼠、礼服柯基、黑猫、花开。
- 按住拖动；普通窗口为 216 × 204 点，动画时才扩大。
- 拖至当前屏幕可用区域下边缘 18 点内松手，宠物趴在自己的睡垫上，暂停散步。可用区域考虑 Dock 的位置。
- 向上拖离边缘超过 40 点，再拖回，在闭眼休息和左右偷瞄之间切换。横向拖动不切换；拖回普通区域恢复普通造型。
- 左、右或上边缘松手：眼睛完全越界时播放星光并换宠物；仅部分越界时旋转回到当前屏幕中央。
- 双击播放爱心、放大跳跃和旋转落回原位置。macOS 版动画使用原生时间轴，路径并非 Windows 版逐帧复制。
- 右键或 Control 点击打开菜单：散步、置顶、角色、透明度、回到右下角、每小时模式和退出。
- 菜单栏爪印提供相同菜单，宠物隐藏时也可退出。应用没有 Dock 图标。

位置、透明度、散步和置顶设置会保存。窗口跟随所处屏幕；显示器断开时会重新限制在可用屏幕内。

## 每小时出现 30 秒

从爪印菜单启用「每小时出现 30 秒」。首次约一小时后出现；之后每次出现轮换角色。锁屏、切换用户或显示器休眠时等待恢复使用，显示期间休眠会提前隐藏。关闭该选项恢复常驻。

也可在应用未运行时从终端启动：

```sh
open 'dist/Pixel Pet.app' --args --hourly
```

每小时模式只在本次运行中生效，不创建登录项。系统睡眠期间不会尝试唤醒电脑。菜单栏、全屏空间、锁屏通知、多显示器和 Dock 边缘行为需在实际 macOS 桌面验收。

## 开发与验证

应用构建不依赖 `XCTest`。完整单元测试仍保留；在 macOS 上需要包含 `XCTest` 的完整 Xcode 工具链，单独双击 `Test-Pixel-Pet.command` 执行。若测试入口提示缺少该库，安装完整 Xcode 后可运行 `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` 选择它的工具链。Linux 的 Swift 工具链也可执行核心单元测试。

```sh
swift test
swift build
swift run PixelPet
# 构建应用后，在可交互的 macOS 桌面测试资源打包和窗口渲染：
'dist/Pixel Pet.app/Contents/MacOS/PixelPet' --self-test
```

`swift test` 覆盖六种角色的边缘判定、下边缘动作切换、负坐标屏幕、脚爪与睡垫对齐、24 帧数据和每小时调度。核心测试可在 Linux 运行；桌面应用仅支持 macOS。`--self-test` 不更改用户设置，检查 18 种角色/姿势渲染及真实窗口的显示、隐藏、关闭；不能替代手动拖动、双击及锁屏验收。

本次发布在 Apple Silicon macOS 上完成构建、签名验证与 18 种 AppKit 渲染自测。当前命令行工具缺少 XCTest，未执行核心单元测试。

`Sources/PixelPetCore/Resources/sprites.json` 是提交的运行资源，构建时不需要 PowerShell。Windows 绘制数据更新后，可用 PowerShell 7 重新导出（只执行原脚本中的纯绘制函数）：

```sh
pwsh -NoProfile -File Tools/Export-Sprites.ps1 \
  -Source /path/to/pixel-pet-windows/02-App/PixelPet.ps1 \
  -Output Sources/PixelPetCore/Resources/sprites.json
swift test
```

## 卸载

从爪印菜单退出，删除 `.app` 和源码目录。若要清除设置，可在退出后执行：

```sh
defaults delete io.github.y99854-ui.PixelPetMac
rm -f "$HOME/Library/Application Support/PixelPetMac/instance.lock"
```

Windows 版见 [pixel-pet-windows](https://github.com/y99854-ui/pixel-pet-windows)。
