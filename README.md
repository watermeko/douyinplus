# DouyinPlus

一个第三方抖音（Douyin）客户端实验项目，v1 聚焦两件事：

- 通过抖音官方网页完成账号登录，并安全保存会话 Cookie
- 浏览推荐视频流（上下滑动切换、视频播放、分页加载）

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
| 点赞 / 评论 / 收藏 / 分享 | ⛔ | v1 仅展示，点击提示“下一版开放” |

## 环境

- Flutter 3.47+（本项目在 Flutter 3.47.8 / Dart 3.13 下开发）
- Android SDK 24+（minSdk 24）
- 已在 Android 14 x86_64 模拟器（1080×2400，420dpi）上验证

## 运行

```bash
flutter pub get
flutter run -d <android-device>
```

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
    models/                    # Aweme / UserProfile / JSON 工具
  features/
    login/                     # 登录页、WebView、调试导入
    feed/                      # 推荐流、视频卡片、玻璃 UI 浮层
test/                          # 模型解析与格式化单元测试
docs/douyin-api.md             # 抖音 Web API 调研文档
```

## 接口与签名说明

详见 [`docs/douyin-api.md`](docs/douyin-api.md)。核心结论：

- 推荐流 `GET /aweme/v1/web/tab/feed/`：仅需 `sessionid` + `ttwid`，当前不需要 `a_bogus`。
- 视频详情 / 评论接口需要签名；v1 未使用。
- 视频 CDN 直链可直接播放，支持 Range。
- 若接口失效，优先检查 Cookie 是否过期、`ttwid` 是否缺失、是否触发风控。

## 后续计划

- 视频详情页 / 评论（需 WebView 内签名代理）
- 点赞、收藏、关注等写操作
- 更好的登录页（自绘二维码登录）
- iOS 适配
- 播放清晰度选择与弱网降级

## 免责声明

本项目与抖音 / 字节跳动无任何关联。接口为逆向调研所得，随时可能变更。使用本项目产生的一切后果由使用者自行承担。