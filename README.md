# Cineo 看客 / 风暴剧场 iOS 源码

基于 [benson-singapore/cineo-flutter](https://github.com/benson-singapore/cineo-flutter)，
上游提交 `f286ddc220fcbe2f85a4f993442b772a6bd62d87`，许可证见 `LICENSE`。
保留 Cineo 的界面与播放功能，加入看客、风暴剧场接口；首次运行默认看客，
可在“视频源”中切换风暴剧场。

## 构建 IPA

1. 解压后将里面的内容上传 GitHub 仓库，包含 `.github`；仓库根目录应直接有 `pubspec.yaml`、`lib`、`ios`。
2. 打开 **Actions → Build iOS IPA → Run workflow**。
3. Bundle ID 默认 `local.cineo.kanke.storm`，可改为自己的标识。
4. 成功后下载 Artifacts 中的 `Cineo-Kanke-Storm-iOS-运行编号`，里面是未签名 IPA，需自行签名安装。

本包只包含 iOS 构建输入、测试、构建工作流和许可证。`test` 用于工作流中的完整回归；
`tool/validate_ipa.py` 用于编译后的 IPA 结构检查。
Flutter 固定 3.13.9，最低 iOS 15。

双源适配在 `lib/data/remote/service_sources.dart`；本地改动还包括首次来源配置、
播放/系统播放器/画中画/HLS 下载的地址解析及请求头传递、重复来源通知修复，
以及相应的协议和回归测试。风暴按匿名方式接入，不转发账号类 Cookie/Authorization。

本地静态分析无问题，191 项测试通过；两套来源的分类、搜索、详情和媒体请求已验证。
尚未执行 GitHub iOS 编译或 iPhone 实机验收。特殊编码、DRM、画中画等仍需实机检查；
下载沿用上游 HLS 限制，不支持 MP4 下载。外部服务可能变化。
