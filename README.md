# Antigravity Boot

给 macOS 上的 Antigravity 和 Gemini 播放启动动画。启动器在播放视频的同时打开目标应用。Antigravity 的窗口在片尾逐渐显现，Gemini 的动画向窗口中央收拢。点击「跳过」、按 Esc 或 ⌘.，可以提前进入应用。

## 安装和使用

1. 准备一台运行 macOS 13 或更高版本的 Mac，并安装 Antigravity 或 Gemini。安装包支持 Apple Silicon 和 Intel。
2. 打开 DMG，将 **Antigravity Boot** 拖到旁边的 **Applications**，然后从「应用程序」打开启动器。需要 Dock 入口时，将启动器拖入 Dock。
3. 选择目标应用和启动动画。公开标准版内置 4 秒「星轨」。选择「选择本地视频…」，再点击「启动」，即可使用自己的 MP4。推荐 H.264 视频。自选视频按原路径保存，请保留该文件。
4. 两个目标应用分别记住动画选择。勾选「以后直接启动选中的应用」可跳过选择窗口。按住 **Option** 打开启动器，直到选择窗口出现，即可更改。

1.0.0 的安装包采用本地临时签名，尚未获 Apple 公证。从网上下载时，macOS 可能提示无法验证开发者。首次打开时可参阅 [Apple 的 Mac 应用安全说明](https://support.apple.com/zh-cn/102445)。

## 从源码构建

在装有 Xcode Command Line Tools 的 Mac 上，解压源码并进入项目目录：

```sh
./build.sh public
open "build/public/Antigravity Boot.app"
```

构建使用系统 AppKit、AVFoundation 和 Core Image。脚本分别编译 arm64 和 x86_64，再合并成通用二进制。随包的星轨动画支持离线构建。

生成带「应用程序」拖放入口的 DMG：

```sh
./package.sh public
```

安装包输出至 `dist/`。分发前可使用 `shasum -a 256 -c SHA256SUMS.txt` 核对同目录的发布文件。

## 媒体与许可

代码、脚本、自制图标和原创星轨动画使用 [MIT 许可证](LICENSE)。星轨由几何轨道、光点和中心星组成。

录屏版内置经典版、水彩绘本、霓虹都市和换班四段角色动画。**这四段动画不开源，不适用 MIT 许可证，禁止商业使用。** 个人可用它们体验启动器或进行本项目的非商业演示。分享含动画的完整项目或安装包时，请保留[随附角色动画使用说明](Media/ANIMATION_NOTICE.md)。

从含有四段 MP4 的仓库检出后，运行 `./package.sh demo` 即可构建录屏版。

## 窗口交接

启动器读取 macOS 提供的可见窗口位置，让视频对齐目标窗口。宽高比不同时，用画面边缘的镜像填满空白。10 秒动画的末尾 2.25 秒用于交接；启动期间若目标窗口尚不可见，启动器会在居中位置淡出并尝试激活目标应用。
