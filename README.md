# Kazumi 看客 / 风暴剧场试接入版

基于 [Predidit/Kazumi](https://github.com/Predidit/Kazumi) **2.4.3**，固定提交 `7265274fac136a0cfe6ee32ea37f32f06ea57672`。保留原有播放器、选集、历史、缓存和动漫功能。

## 使用入口

首次启动默认进入底部 **影视**。选择“看客”或“风暴剧场”，可以浏览片库、切换分类、搜索、加载下一页，点击影片查看简介和线路，再点击“播放 / 续播”进入 Kazumi 原有播放页选集、切线。无需自己搭服务器。

电影、电视剧使用来源独立的本地身份记录历史，不会伪装成 Bangumi 条目；因此不请求对应的 Bangumi 评论或自动弹幕。原有动漫入口仍保持原来的行为。接口访问错误会显示重试或换源入口。

## 接入方式

- `lib/services/builtin_sources/source_protocols.dart`：复用已有看客 RC4/客户端表单协议与风暴 AES-GCM/动态路由/节点发现协议。
- `builtin_catalog.dart`：将来源结果转换为 Kazumi 搜索和线路模型，使用稳定的来源/影片标识记录历史。
- `lib/pages/catalog/`：双源片库、搜索、分页与详情入口。
- 两套来源首次启动内置到规则列表，可以走原有来源搜索与历史恢复流程；删除后不会每次启动强制恢复。
- 选择剧集时才解析临时媒体地址。播放与下载传递媒体请求头；下载重试重新解析地址和请求头。风暴不读取或转发配置中的账号 Cookie/Authorization。
- 原有 `WebViewVideoSourceService` 在遇到内置协议时直接解析，其他规则仍使用上游网页解析。取消或切集会丢弃过期结果。
- 风暴节点的 chunked 响应在 Dart IOClient 中有兼容问题；采用 Kazumi 已有的 `ech_http` 原生 libcurl 网络库，不启动本地代理、不调用外部命令。

## 构建与检查

使用 Flutter **3.47.9** / Dart **3.13.7**。上游六个 Git 包以原提交源码放在 `third_party/`，版本与许可证记录在 `third_party/UPSTREAM.json`，避免每次构建克隆整个 Git 镜像。

```sh
python3 tool/fetch_assets.py
flutter pub get
dart analyze lib test tool
flutter test --no-pub
dart run tool/probe_builtin_sources.dart
```

原生资产需要对应平台编译工具：iOS 在 macOS/Xcode 环境构建，另需 CMake/Ninja。接口探针只读取最多 8 KiB 媒体样本，不下载完整影片；输出不含服务配置、账号信息或临时媒体 URL。

Windows 本机测试使用同版上游官方发布包的原生 DLL、已编译的 ink_sparkle 着色器，以及本地 QA hook 副本，并以 `flutter test --no-pub --no-test-assets` 执行。这规避了本机 C++ 构建工具缺失和 Flutter 着色器编译器的中文路径问题；应用与测试的 Dart 代码照常编译。`pubspec_overrides.yaml` 仅属于本机验证环境，不包含在交付 ZIP 中。交付源码保留原始原生构建 hook，iOS 编译与真机播放需另行验证。实测范围和结果见 `verification/`。

## GitHub Actions

源码带有自动与手动 **Build Kazumi iOS trial** 工作流，可在自己的仓库 Actions 中运行，产生未签名 IPA。它只修改 Runner 主应用的 Bundle ID，并检查 IPA 中所有 bundle 标识是否重复。工作流不会发布 Release。

这次“试接入”不代表已经通过 iPhone 安装、播放、后台恢复或完整缓存验收。已存在的原版 Kazumi/旧 Cineo 安装包不包含本次接口代码。

## 上游与许可

应用沿用 GPL-3.0，详见 `LICENSE`。第三方依赖保留原许可证。图标来自上游已获作者 Yuquanaaa 授权使用的作品；该图标并非自由素材，本次不将其声明为自有或自由授权资源。

图标、启动图和字体不重复上传到 Git。构建前从固定上游提交下载，逐文件校验 SHA-256；清单见 `tool/upstream-assets.json`。
