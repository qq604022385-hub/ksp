# 看客 iOS 客户端

**源码修正版 v2**：已将分类模型 `Category` 统一更名为 `VideoCategory`，修复 macOS XCTest 中的类型歧义；测试和界面使用明确的模块限定类型。请覆盖上传新源码并提交后再运行 Actions，不要只重跑旧提交的任务。详见 `Verification/category-build-fix.md`。

原生 SwiftUI + KSPlayer / FFmpeg 客户端，复用你提供的《看客手机 app300》内容协议。最低 iOS 16.0，适配 iPhone / iPad。没有广告 SDK，没有广告配置、激励视频或广告自动启动代码。

已实现：分类片库、搜索、分页、影片详情、线路选择、选集、下一集、自定义播放器、倍速、收藏、观看历史、断点续播、本机数据管理。复用 KSPlayer 2.3.4 的控制栏、横屏全屏、进度拖动、亮度/音量手势、双击暂停、长按倍速及锁屏按钮，并在全屏内增加选集、线路和下一集。播放内核显式指定为 KSMEPlayer（FFmpeg），关闭系统内核回退。画中画入口暂不开放。操作体验和媒体兼容性仍需 iPhone 验收。

## 在 GitHub 构建 IPA

1. 解压源码包，将**解压目录里面的文件**上传到一个新仓库，建议使用私有仓库。仓库根目录应直接有 `Kanke.xcodeproj`、`Kanke`、`Packages`、`Scripts` 和 `.github`，不要再套一层 `ios` 文件夹，也不要只上传 ZIP。
2. 打开仓库 **Actions → Build iOS IPA → Run workflow**。若提示启用 Actions，先启用。
3. `bundle_id` 可保留 `local.kanke.player`，签名选项 `signed` 保持关闭。
4. 工作流会校验工程、运行 Swift 单元测试、编译模拟器版本，并用 GitHub 的 macOS / Xcode 环境编译 iPhone 版本。
5. 成功后进入该次运行底部的 **Artifacts**，下载 `Kanke-iOS-运行编号`，解压得到 `Kanke-unsigned.ipa`。

你本机不需要 Mac，也不需要为这一步提供 Apple 开发者证书。GitHub 对私有仓库的 macOS 运行有账户额度限制，以你自己的 GitHub 账户为准。

**未签名 IPA 不能直接安装到 iPhone。** 需要后续使用你自己的 Apple 签名方式；GitHub 构建和手机安装签名是两个步骤。此源码没有内置企业证书、共享证书或他人的签名身份。

## 可选：使用自己的证书生成签名 IPA

只有你已准备匹配的证书和描述文件时才开启 `signed`。在仓库 **Settings → Secrets and variables → Actions** 添加：

| Secret | 内容 |
| --- | --- |
| `IOS_CERTIFICATE_P12_BASE64` | 自己的 `.p12` 证书文件经 Base64 编码后的内容 |
| `IOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码，可为空 |
| `IOS_PROVISION_PROFILE_BASE64` | 匹配 Bundle ID、签名身份和设备的 `.mobileprovision` 文件经 Base64 编码后的内容 |

再次手动运行工作流，设置与描述文件匹配的 `bundle_id`，开启 `signed`。产物为 `Kanke-signed.ipa`。描述文件必须包含所安装设备或符合相应分发方式；构建脚本不会绕过 Apple 的安装签名要求。个人/开发用原生签名流程可参见 [Apple 的设备分发说明](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)。不要把证书、密码和描述文件直接提交到仓库。

## 本地 Xcode

在 Mac 上先运行 `python3 Scripts/prepare_player.py`，再打开 `Kanke.xcodeproj`，选择 `Kanke` scheme。原生界面以 Xcode 16 或更高版本为目标编写，Swift 语言模式为 5。第三方 KSPlayer 源码位于 `Vendor/KSPlayer`；FFmpegKit 的 iPhone/模拟器原生依赖由脚本从固定上游提交下载（首次约 300 MB），不提交到仓库。Actions 已自动加入此步骤。许可证及修改说明见 `THIRD-PARTY-NOTICES.md`；该公开版本采用 GPL-3.0。

```sh
swift test --package-path Packages/KankeCore
xcodebuild -project Kanke.xcodeproj -scheme Kanke \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -archivePath build/Kanke.xcarchive CODE_SIGNING_ALLOWED=NO archive
bash Scripts/package_ipa.sh build/Kanke.xcarchive/Products/Applications/Kanke.app false
```

## 接口实现

`Packages/KankeCore` 包含网络、模型、十六进制 RC4 响应解码和兼容 Java 表单编码的播放请求。应用启动后沿用原包的发现流程：

1. 获取原包的 HTTPS 引导地址，返回当前服务地址。
2. 读取 `extend/api/set.php?type=set`，获得片库地址与当前协议配置。
3. 分类：`api.php/localhost/Category`；片单：`api.php/localhost/vod/?ac=list&class=…&page=…`。
4. 搜索：`api.php/localhost/So/?ac=list&zm=…&page=…`；详情：`api.php/localhost/vod/?ac=detail&ids=…`。
5. 对原有 `/Client/` 路由发送 `app` 和 `key` 表单，保留服务器返回的播放 URL 以及 User-Agent / Referer / Origin / Cookie。

默认访问配置来自原服务公开返回的客户端配置，没有硬编码个人账号或静态响应密钥；访问被服务器拒绝时显示错误，不伪造服务端授权或奖励。RC4 仅用于旧接口协议兼容，不承担 HTTPS 的安全功能。原服务动态返回 HTTP 地址，所以 Info.plist 保留了相应 ATS 兼容设置。

`videolist` 使用通用字典适配，能够展示旧安卓代码中未列出的新线路。视频源本身嵌入的内容广告没有被过滤。外部接口、签名 URL 和 CDN 可能随时变化，若某线路不可用，请尝试其他线路。

## 已验证与尚未验证

当前 Windows 环境已实测服务器发现、配置、分类、片单、搜索、详情、线路元数据解码，以及三条来源的播放解析；两条 HLS 返回有效播放列表，一条 MP4 请求成功。查看 `Verification/live-api-verification.json`。这些是接口/媒体请求验证，不是 FFmpeg 播放验收。

工程结构、资源、工作流和协议的主机检查记录见 `Verification/host-validation.txt`。原生 Swift 单元测试已写入，但本机没有可用的 Apple SDK 构建环境，**尚未执行 Xcode 编译、GitHub Actions 构建或 iPhone 安装验收**。工作流成功与实际产物验证以你运行后的日志为准，不能将源码检查当成已生成可安装 IPA。

首次运行时请检查片库、搜索、选集、切线、播放/暂停、后台返回、倍速与续播。HLS / MP4 可播性、特殊编码、DRM、请求头转发、横屏返回和手势都需要实际 iPhone 测试。应用会显示解码/网络/播放错误，并提供重新加载和切线入口。

## 目录

- `Kanke/`：原生界面、KSPlayer / FFmpeg 生命周期、本机收藏/历史。
- `Packages/KankeCore/`：网络与协议、数据模型、Swift 测试及去敏测试样本。
- `.github/workflows/build-ios.yml`：GitHub macOS 构建流程。
- `Scripts/`：工程检查、IPA 打包与可选自有证书签名。
- `Verification/`：可审计的主机与接口验证记录。

解包出来的安卓代码、完整接口响应、临时播放 URL、安卓签名材料都不在此源码包中。
