# 看客 · 影视精简版

基于 Predidit/Kazumi 2.4.3（GPL-3.0）修改，本版版本号 2.4.4。iOS 包名保持 `local.kazumi.kanke.storm`，显示名称为“看客”。

## 使用

- 底部仅保留“影视、收藏、我的”。影视内选择看客或风暴剧场，浏览、搜索、查看详情、播放和选集切线。
- 详情或播放器内一键收藏，再从收藏页返回原来源。旧收藏缺少来源信息时按片名重新搜索，不删除旧数据。
- “我的”提供历史、下载、来源检测、播放设置、外观和存储管理。
- 播放失败页面的刷新按钮会重新解析当前剧集。也可返回详情重新获取剧集列表，或切线路、切来源。
- 来源页检测片库接口是否可连接；它不代表每部影片、每条线路都可用。来源配置入口仍为内置值；协议变更需更新适配代码。

## 精简范围

移除动漫推荐、放送时间表、追番状态菜单、Bangumi 账户/同步界面、角色与评论界面、以图搜番、原版规则商店和上游更新入口。播放器移除弹幕发送、弹幕设置、分集评论和一起看入口。来源页聚焦两套内置影视来源。

启动时关闭旧版可能留下的 Bangumi/WebDAV 自动同步、上游自动更新和弹幕缓存开关，并将已移除的默认启动页迁移到影视。保留收藏、历史、下载文件和播放器共用存储格式，保留原有来源记录以支持历史恢复。共用播放/存储底层仍使用部分上游模型名称。

## 构建

使用 Flutter 3.47.9 / Dart 3.13.7。iOS 在 macOS/Xcode 构建，依赖 CMake/Ninja。

```sh
python3 tool/fetch_assets.py
flutter pub get
dart analyze lib test tool
flutter test --no-pub
flutter build ios --release --no-codesign
```

工作流 `.github/workflows/build-ios-trial.yml` 生成未签名 IPA，不自动发布 Release。安装到 iPhone 仍需签名。

Windows 本机回归使用 `.qa-kazumi-native` 的上游官方 DLL 和专用 hook；`pubspec_overrides.yaml` 属于本机 QA，不交付、不用于 iOS 云构建。测试结论不等同于 iPhone 真机验收。

## 开源与资源授权

上游：https://github.com/Predidit/Kazumi ，固定提交 `7265274fac136a0cfe6ee32ea37f32f06ea57672`。本版源代码：https://github.com/qq604022385-hub/ksp 。完整许可证见 `LICENSE` 与 `licenses/`，依赖来源见 `third_party/UPSTREAM.json`。

上游图标来自 Yuquanaaa 的授权作品，不声明为自有或自由授权素材。图标、字体等固定上游资源通过 `tool/fetch_assets.py` 恢复并逐文件校验 SHA-256，清单见 `tool/upstream-assets.json`。关于页保留上游、许可证和资源致谢。
