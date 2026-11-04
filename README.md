# DouyinPlus

一个第三方抖音（Douyin）客户端实验项目，当前版本（M2）包含：

- 通过抖音官方网页完成账号登录，并安全保存会话 Cookie
- 浏览推荐视频流（上下滑动切换、视频播放、分页加载）
- 只读评论面板：分页、图文/表情评论、打开时暂停视频
- 点赞 / 收藏基础能力（乐观更新、失败回滚；默认关闭，见下）
- 隐藏 WebView 签名桥，读取需要 `a_bogus` / `msToken` 的接口
- GitHub Release 签名 APK 分发与校验说明

UI 采用 **Liquid Glass（液态玻璃）** 设计语言，基于 `liquid_glass_widgets` 的 shader 折射、高光与弹簧交互：悬浮玻璃按钮按压时会挤压 / 回弹，描述文字直接悬浮在视频上。

> 非官方客户端，仅用于个人学习 / 技术研究。视频、封面、音乐等版权归原作者及抖音所有。请遵守抖音用户协议，不要用于批量抓取、内容搬运或商业分发。

## 功能

| 功能 | 状态 | 说明 |
| --- | --- | --- |
| 推荐视频流 | ✅ | `tab/feed` 接口，竖向 PageView，自动翻页 |
| 视频播放 | ✅ | `video_player` + 抖音 CDN 直链，循环播放 |
| 官方网页登录 | ✅ | 内嵌 WebView，扫码 / 验证码 / 密码登录 |
| Cookie 持久化 | ✅ | `flutter_secure_storage` 加密保存 |
| 登录态校验 | ✅ | `user/profile/self` |
| 个人面板 | ✅ | 头像 / 昵称 / 粉丝 / Cookie 数量 / 退出登录 |
| 调试 Cookie 导入 | ✅ | 仅 Debug 构建，支持文件与文本导入 |
| 评论浏览 | ✅ | 隐藏 WebView 签名桥；分页、加载更多、空/错误状态 |
| 评论回复展开 | ⚠️ | 回复接口仍超时，暂只显示回复数 |
| 点赞 / 收藏 | 🚧 | 代码已接入，默认关闭（见下方开关） |
| 评论发布 / 关注 / 分享 | ⛔ | 暂不实现 |

## 环境

- Flutter 3.47+（本项目在 Flutter 3.47.8 / Dart 3.13 下开发）
- Android SDK 24+（minSdk 24）
- 已在 Android 14 x86_64 模拟器（1080×2400，420dpi）上验证

## 运行

```bash
flutter pub get
flutter run -d <android-device>
```

点赞 / 收藏会写入真实账号，默认关闭。仅在自己账号上低频验收时启用：

```bash
flutter run -d <android-device> \
  --dart-define=DOUYINPLUS_ENABLE_INTERACTIONS=true
```

> 开发期连续写入曾触发抖音验证码，因此公开 Release 不默认开启互动；详见 [`docs/m2-plan.md`](docs/m2-plan.md) 与 [`docs/release-notes/v0.2.0.md`](docs/release-notes/v0.2.0.md)。

或构建 APK：

```bash
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n dev.watermeko.douyinplus/.MainActivity
```

> 模拟器建议使用真实 GPU 模式（`emulator -gpu host`）。在本机测试时，旧版 SwiftShader GLES 打开 WebView 会导致模拟器崩溃，因此项目在 `AndroidManifest.xml` 中关闭了 Impeller（使用 Skia）。在真实设备上可自行评估是否重新启用 Impeller。

## 登录流程

1. 打开 App → 点击「登录抖音账号」。
2. 内嵌 WebView 打开抖音官方登录页（桌面 UA + 0.72 CSS 缩放，使完整登录框适配手机屏幕）。
3. 使用抖音 App 扫码，或使用验证码 / 密码登录。
4. 登录成功后，`MainActivity` 通过 MethodChannel 读取 Android WebView CookieManager 中的 HttpOnly Cookie（`sessionid`、`ttwid` 等）。
5. Cookie 加密保存到本机，并调用 `user/profile/self` 校验登录态，随后进入推荐流。

Cookie 等价于账号密码：不要提交到 Git、不要写入日志、不要发送给第三方。

## 调试 Cookie 导入（仅 Debug）

如果模拟器里无法扫码，可把已登录浏览器的 Cookie 以 JSON 形式导入：

```bash
adb shell mkdir -p /sdcard/Android/data/dev.watermeko.douyinplus/files
adb push douyin_cookies.json \
  /sdcard/Android/data/dev.watermeko.douyinplus/files/douyin_cookies.json
adb shell am force-stop dev.watermeko.douyinplus
adb shell am start -W -n dev.watermeko.douyinplus/.MainActivity
```

文件格式（至少包含 `sessionid` 与 `ttwid`）：

```json
{
  "sessionid": "...",
  "ttwid": "...",
  "UIFID": "..."
}
```

导入成功后请删除该文件。正式版不会展示 Cookie 导入入口。

## 目录结构

```
lib/
  app.dart                     # App 根、路由门（Splash/Login/Feed/Error）
  main.dart                    # 入口、状态栏样式
  core/
    config.dart                # 编译期 feature flags
    theme.dart                 # 颜色与主题
    format.dart                # 播放时间/万/亿/相对时间
    widgets/
      glass.dart               # GlassSurface / GlassButton / GlassToast 等
      liquid_background.dart   # 液态渐变背景
  data/
    app_controller.dart        # 登录态、Cookie 导入、退出登录
    cookie_bridge.dart         # Android WebView CookieManager 通道
    douyin_api.dart            # feed / profile 接口
    feed_controller.dart       # 分页、去重、加载状态
    session_store.dart         # SecureStorage 封装
    signature_bridge.dart      # 隐藏 WebView 签名桥
    signed_client.dart         # 签名请求接口与响应模型
    comment_repository.dart    # 评论/回复读取
    comments_controller.dart   # 评论分页与去重
    interaction_repository.dart# 点赞/收藏写入
    interactions_controller.dart # 乐观更新与回滚
    models/                    # Aweme / Comment / UserProfile / JSON 工具
  features/
    login/                     # 登录页、WebView、调试导入
    feed/                      # 推荐流、评论面板、玻璃 UI 浮层
    debug/                     # 签名桥 Debug 测试页（仅 Debug）
test/                          # 模型、分页、互动状态、签名分类测试
docs/
  douyin-api.md                # 抖音 Web API 调研文档
  m2-plan.md                   # M2 方案与 spike 结果
  release.md                   # 签名、CI、发布流程
  install.md / privacy.md      # 安装与隐私说明
  release-notes/               # GitHub Release 更新说明
```

## 接口与签名说明

详见 [`docs/douyin-api.md`](docs/douyin-api.md)。核心结论：

- 推荐流 `GET /aweme/v1/web/tab/feed/`：仅需 `sessionid` + `ttwid`，当前不需要 `a_bogus`。
- 评论列表、视频详情、点赞、收藏需要签名，由隐藏 WebView 在官方页面上下文发起；请求路径有白名单。
- 视频 CDN 直链可直接播放，支持 Range。
- 若接口失效，优先检查 Cookie 是否过期、`ttwid` 是否缺失、是否触发验证码或风控。
- 回复列表接口 `comment/list/reply` 目前仍会超时，尚未接入 UI。

## 分发与安装

- 通过 GitHub Release 分发签名 APK，附 SHA-256 校验和。
- 构建与密钥流程见 [`docs/release.md`](docs/release.md)，安装步骤与风险提示见 [`docs/install.md`](docs/install.md)，数据处理见 [`docs/privacy.md`](docs/privacy.md)。
- 最低 Android 7.0（minSdk 24）。

## 后续计划

详见 [`docs/m2-plan.md`](docs/m2-plan.md)。

- 真机回归、风控/验证码恢复、签名桥内存与耗电评估
- 修复回复列表接口后接入展开回复
- 评估在互动写入稳定后默认开启点赞/收藏
- 更长期：作者主页 / 相关推荐、播放清晰度与弱网降级、iOS 适配

## 免责声明

本项目与抖音 / 字节跳动无任何关联。接口为逆向调研所得，随时可能变更。使用本项目产生的一切后果由使用者自行承担。