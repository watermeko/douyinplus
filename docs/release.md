# 发布与签名

本文档面向维护者。发布产物通过 GitHub Release 侧载分发，不上架应用商店。

> 发布 APK 必须与旧版使用同一签名证书。丢失 keystore 会导致用户无法覆盖安装，只能卸载重装（会清空本机登录数据）。

## 1. 生成 release keystore（只做一次）

在 `android/` 下生成并离线备份：

```bash
keytool -genkeypair -v \
  -keystore android/key.jks \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias douyinplus
```

`key.jks`、`key.properties` 已被 `.gitignore` 排除，**不要提交、不要上传到网盘公开链接**。至少保留两份离线备份，并记录密码与 alias。

## 2. 本地签名配置

```bash
cp android/key.properties.example android/key.properties
```

按实际密码修改 `android/key.properties`：

```properties
storePassword=...
keyPassword=...
keyAlias=douyinplus
storeFile=../key.jks
```

`storeFile` 相对 `android/app`（Gradle 模块目录）解析；也可以写绝对路径。

未提供 `key.properties` 时，`flutter build apk --release` 会退回 debug 签名，仅用于本机测试，不能用于分发。

## 3. GitHub Actions secrets

仓库 → Settings → Secrets and variables → Actions，新增：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | keystore 的 Base64（单行） |
| `ANDROID_KEYSTORE_PASSWORD` | storePassword |
| `ANDROID_KEY_ALIAS` | keyAlias |
| `ANDROID_KEY_PASSWORD` | keyPassword |

Linux 生成 Base64：

```bash
base64 -w0 android/key.jks
```

macOS 可使用 `base64 -i android/key.jks`。把输出整行粘贴为 secret，不要换行。

## 4. 发布流程

1. 在 `pubspec.yaml` 更新版本号，例如 `version: 0.2.0+2`。Git tag 必须与语义化版本一致。
2. 在 `docs/release-notes/v0.2.0.md` 写更新说明；缺省会使用 `docs/release-notes/template.md`。
3. 本地验证：
   ```bash
   flutter analyze
   flutter test
   flutter build apk --release --build-name=0.2.0 --build-number=2
   ```
4. 提交并打 tag：
   ```bash
   git tag -a v0.2.0 -m "DouyinPlus v0.2.0"
   git push origin v0.2.0
   ```
5. Actions 会执行 analyze / test / 签名构建 / 生成 SHA-256 / 创建 GitHub Release。
6. 下载 Release 中的 APK，在一台干净设备上安装并验证登录、推荐流、评论区。

工作流固定 `DOUYINPLUS_ENABLE_INTERACTIONS=false`。互动写入目前处于验收阶段，不要在公开发布中默认开启。

## 5. CI 产物的命名

- `douyinplus-v0.2.0.apk`
- `douyinplus-v0.2.0.apk.sha256`

SHA-256 文件内容包含文件名，可直接校验：

```bash
sha256sum -c douyinplus-v0.2.0.apk.sha256
```

Windows PowerShell：

```powershell
Get-FileHash .\douyinplus-v0.2.0.apk -Algorithm SHA256
```

## 6. 版本与覆盖安装

- `versionName` 取 Git tag：`v0.2.0` → `0.2.0`。
- `versionCode` 取 GitHub Actions 的 `GITHUB_RUN_NUMBER`，单调递增；不要手动回退。
- 同一签名的更高 `versionCode` APK 可以覆盖安装并保留登录数据。
- 更换签名或包名会让旧版无法覆盖安装；包名 `dev.watermeko.douyinplus` 不应再改。
- 首个公开发布（v0.2.0）使用本机生成的 release keystore（`CN=DouyinPlus`）。此前用手动 `adb install` 装过 debug 签名的开发版时，无法覆盖安装，需要先卸载一次（会清空本机登录态），之后的正式版之间可以正常覆盖升级。

## 7. 发布前检查清单

- [ ] `flutter analyze` 无错误
- [ ] `flutter test` 全绿
- [ ] 版本号与 tag 一致，`versionCode` 比上一版大
- [ ] Release notes 包含功能、修复、已知问题、风控提示
- [ ] APK 与 SHA-256 均已上传
- [ ] APK 用 `apksigner verify --print-certs` 确认签名证书指纹与上一版一致
- [ ] 未提交 `key.properties`、`*.jks`、Cookie、HAR、含签名的抓包
- [ ] 隐私与安装说明可从 Release 页面访问

## 8. 密钥丢失 / 泄露

- **丢失**：老用户无法覆盖安装。发布公告说明需先卸载再安装，并提醒会清空本机登录数据。
- **泄露**：立即停止使用该证书发布；生成新证书意味着新的应用签名，所有用户都需要卸载重装。不要试图通过修改包名绕过，避免产生多个不兼容安装包。