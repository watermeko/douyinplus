# M2 方案：评论、互动与 GitHub Release 分发

> 状态：主要功能已实现，M2.4 模拟器验收见 §14，误判修复与互动验收见 §15 · 2026-11-05
>
> 前置文档：[`douyin-api.md`](douyin-api.md)
>
> M2.0 签名桥 spike 结果见文末 [§12](#12-m20-spike-结果2026-11-04)。

## 1. 目标与非目标

### 目标

- 用**本机隐藏 WebView + 官方页面上下文 XHR** 做签名桥，读取需要 `a_bogus` / `msToken` 的接口。
- 先做**只读评论**：评论列表、回复列表、分页。
- 再做**点赞 / 收藏**：乐观更新、失败回滚、低频用户触发。
- 通过 **GitHub Release** 分发签名 APK（含校验和、更新说明、隐私/免责声明）。
- 签名桥不可用时，推荐流和本地播放不受影响。

### 非目标（M2 明确不做）

- 评论发布。未来如需发布，只提供“在官方 WebView 中打开”，不在客户端内提交内容。
- 关注 / 取关、私信、搜索、视频下载、批量互动。
- 服务端签名、Cookie 上传、账号共享或任何形式的 Cookie 收集。
- iOS 适配、多账号。

## 2. 关键决策

| 决策 | 选择 | 原因 |
| --- | --- | --- |
| 签名方式 | 隐藏 WebView 内官方页面 XHR | 复用 webmssdk，不自己实现 `a_bogus`；算法变化时只需刷新页面 |
| 评论先读后写 | 只读评论 → 点赞/收藏 | 风险递增；评论发布涉及内容风控和验证码，暂缓 |
| 分发 | GitHub Release APK | 可控、无需应用商店审核；先做侧载和手动更新 |
| 降级 | 功能级 feature flag | 签名失效只影响评论/互动，不影响推荐流 |
| 账号边界 | 每个用户自己的 WebView 登录态 | 不做服务端代理，不收集、不共享 Cookie |

## 3. 架构

```
┌────────────────────────────────────────────────────┐
│ Flutter UI                                         │
│  FeedPage / CommentsSheet / ActionRail             │
└───────────────┬────────────────────────────────────┘
                │
┌───────────────▼────────────────────────────────────┐
│ CommentRepository / InteractionRepository          │
│  - 分页、去重、乐观更新、错误分类                   │
└───────────────┬────────────────────────────────────┘
                │
┌───────────────▼────────────────────────────────────┐
│ SignatureBridge                                    │
│  - 单并发请求队列、超时、重试、健康状态             │
│  - JS channel 请求/响应关联                         │
└───────────────┬────────────────────────────────────┘
                │
┌───────────────▼────────────────────────────────────┐
│ Hidden WebView (douyin.com, 已登录)                 │
│  - webmssdk 自动追加 msToken / a_bogus              │
│  - XHR: comment/list, aweme/detail, digg, collect   │
└────────────────────────────────────────────────────┘

旁路：DouyinApi（feed / profile / related，无需签名）
      SessionStore（加密 Cookie）
```

### 3.1 签名桥

组件：`SignatureBridge` + `SignatureBridgeController`。

- **生命周期**
  - 登录成功后创建；保持一个常驻隐藏 WebView。
  - App 进入后台时尽量暂停/降低活动；回到前台做一次健康检查。
  - 退出登录、切换账号、OOM 恢复时销毁并重建。
- **请求协议**
  - Dart → JS：`{id, method, path, params, body}`。
  - JS → Dart：`{id, status, body, error}`。
  - 只允许白名单路径，避免把桥变成任意请求代理。
- **队列**
  - 单并发、FIFO，全局最小间隔 250–500ms。
  - 超时 15s；网络错误退避重试 1 次；签名/风控错误不自动重试。
  - 响应体上限 2 MB，超出则报错并丢弃。
- **健康状态**
  - `ready / busy / unhealthy / disabled`。
  - 403、`Signature Not Found`、空 body、连续超时 → `unhealthy`，刷新 WebView 页面后恢复。
  - UI 读取 `available` 决定是否显示评论入口或走 WebView 兜底。
- **安全**
  - 不打印请求 URL 查询串、Cookie、响应全文。
  - 日志只记录路径、状态码、耗时、响应长度。
  - 不持久化评论/详情响应；仅内存缓存当前会话。
  - 不使用远程签名服务，不上传 Cookie。

### 3.2 JS 注入

页面加载完成后注入一次幂等脚本：

```js
window.__dpBridgeRequest = function (id, method, path, params, body) {
  const qs = new URLSearchParams(params || {}).toString();
  const xhr = new XMLHttpRequest();
  xhr.open(method, path + (qs ? '?' + qs : ''), true);
  xhr.withCredentials = true;
  if (method === 'POST') {
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
  }
  xhr.onload = function () {
    window.DpBridge.postMessage(JSON.stringify({
      id: id,
      status: xhr.status,
      body: xhr.responseText,
    }));
  };
  xhr.onerror = function () {
    window.DpBridge.postMessage(JSON.stringify({
      id: id, status: -1, body: '', error: 'network',
    }));
  };
  xhr.send(body || null);
};
```

> 实际脚本在 spike 阶段验证 `fetch` / `XMLHttpRequest` 哪种会被 webmssdk 签名；以页面内现有实现为准。

## 4. 接口清单

### 4.1 评论列表（需要签名）

```
GET /aweme/v1/web/comment/list/
  aweme_id, cursor=0, count=20, item_type=0
```

- 响应：`comments[]`、`cursor`、`has_more`、`total`。
- 评论字段：`cid`、`text`、`create_time`、`digg_count`、`reply_comment_total`、`ip_label`、`user{}`、`reply_comment{}`。
- 分页：下一页用响应里的 `cursor`，直到 `has_more=0`。

### 4.2 评论回复（需要签名）

```
GET /aweme/v1/web/comment/list/reply/
  comment_id, cursor=0, count=20
```

- 先做“展开前 3 条回复 + 查看更多”，不做完整盖楼 UI。

### 4.3 视频详情（需要签名）

```
GET /aweme/v1/web/aweme/detail/?aweme_id=<ID>
```

用途：

- 刷新过期播放地址。
- 补全 feed 中缺失的字段（清晰度、作者粉丝数等）。
- 作为评论打开前的可用性检查。

### 4.4 点赞 / 收藏（需要签名）

端点（来自 JS bundle 与页面 UI 抓包）：

- 点赞 / 取消点赞：同一个 `POST /aweme/v1/web/commit/item/digg/`
  - `aweme_id=<id>&item_type=0&type=1` 点赞
  - `aweme_id=<id>&item_type=0&type=0` 取消（web UI 的取消路径）
- 收藏 / 取消收藏：`POST /aweme/v1/web/aweme/collect/`
  - `aweme_id=<id>&action=1&aweme_type=<type>` 收藏
  - `aweme_id=<id>&action=0&aweme_type=<type>` 取消
- `/aweme/v1/web/cancel/item/digg/multi/` 是另一个取消候选端点；实测返回 `status_code=4`，未采用。

实现要求：

- 只在用户点击时触发，不后台自动执行。
- 请求进行中禁用同一按钮，避免重复提交。
- 乐观更新，失败回滚并 toast。
- 不实现批量操作。

## 5. UI / UX

### 5.1 评论面板

- 玻璃底部面板，默认约 60% 屏高，可拖动到 85%。
- 头部：`评论 1.2万`、关闭按钮、当前视频缩略标题（可选）。
- 列表：头像、昵称、评论正文、时间、点赞数、IP 属地、回复数。
- 加载更多：滚动到底部触发；显示“没有更多评论”。
- 状态：首次加载骨架/加载态、空评论、错误重试、签名桥不可用提示。
- 回复：点击“共 N 条回复”展开内联列表；只加载一页，更多跳转/继续加载。
- 不做评论输入框；如需发布，底部提供“在官方页面中打开”入口。

### 5.2 与播放器的关系

建议打开评论面板时暂停视频，关闭后恢复；避免评论滚动时背景视频继续变化影响阅读。该行为可通过设置项关闭。

### 5.3 互动按钮

- 点赞：心形填充/取消，数字即时 +1/-1。
- 收藏：星形填充/取消。
- 签名桥不可用：按钮点击只提示“互动暂不可用”，不阻塞播放。
- 不加入关注按钮（P2）。

## 6. 数据模型与状态

- `Comment`：`cid`、`text`、`createTime`、`diggCount`、`replyCommentTotal`、`ipLabel`、`user`、`replyComment`。
- `CommentPage`：`items`、`cursor`、`hasMore`、`total`。
- `CommentsController`：`items`、`cursor`、`hasMore`、`loading`、`error`、`repliesByCommentId`。
- 去重：按 `cid` 去重；列表 key 使用 `cid`。
- 缓存：仅内存，按 `aweme_id` 保存最近一次评论页；App 重启清空。

错误分类：

| 类型 | 处理 |
| --- | --- |
| 网络/超时 | 可重试，指数退避 |
| 403/签名失效 | 标记桥 unhealthy，刷新页面；提示用户稍后重试 |
| 空 body | 视为签名失效或风控，同 403 |
| 401/Cookie 失效 | 触发重新登录流程 |
| 解析失败 | 记录长度/状态码，不上报原文 |

## 7. GitHub Release 分发

### 7.1 版本与签名

- 版本：`v0.2.0` 起；`pubspec.yaml` 的 `version` 与 Git tag 保持一致。
- Release keystore：本地生成并备份；`key.properties` 与 `*.jks` 继续由 `.gitignore` 排除。
- 签名参数通过 GitHub Secrets 注入：
  - `ANDROID_KEYSTORE_BASE64`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
- 丢失 keystore 会导致老用户无法覆盖安装，发布前必须备份。

### 7.2 CI 流程

Tag 触发 GitHub Actions：

1. 安装 Java 17、Flutter 3.47.x、Android SDK。
2. `flutter pub get`
3. `flutter analyze`
4. `flutter test`
5. `flutter build apk --release`
6. 用 secrets 中的 keystore 签名（或配置 `signingConfigs` 后直接构建签名 APK）。
7. 生成 SHA-256：`douyinplus-v0.2.0.apk.sha256`。
8. 创建 GitHub Release，上传 APK、校验和、CHANGELOG。
9. 不上传含 Cookie 的任何文件；CI 不执行登录、不访问抖音接口。

### 7.3 Release 内容

- `douyinplus-v0.2.0.apk`
- `douyinplus-v0.2.0.apk.sha256`
- 更新说明：新增评论、点赞/收藏、修复项、已知问题。
- 安装说明：允许未知来源、最低 Android 版本（minSdk 24）、卸载旧版/覆盖安装说明。
- 隐私与免责声明链接。
- 账号风险提示：第三方客户端可能触发抖音风控，评论/互动为低频用户主动操作。

### 7.4 自动更新（可选，P2）

- 启动时请求 GitHub Releases API 检查最新 tag；只读公开信息，不上传设备/账号数据。
- 有新版时提示用户手动下载 APK，不做静默安装。

## 8. 测试与验收

### 单元测试

- 签名桥请求/响应 JSON 编解码、id 关联、超时、错误分类。
- 评论分页、去重、`has_more` 终止条件。
- 点赞/收藏乐观更新与失败回滚。

### 集成测试（无网络）

- 用 fake bridge adapter 注入固定评论页，验证 UI 状态机。
- 用 fake interaction API 验证按钮禁用、回滚、计数变化。

### 手动验收

- 模拟器 + 一台真机（Android 10+）。
- 登录 → 打开评论 → 加载 3 页 → 展开回复。
- 点赞/取消、收藏/取消，断网/403 模拟后回滚。
- 退出登录再登录，桥重建正常。
- 签名桥不可用时，推荐流、播放、分享入口不受影响。
- Release APK 能覆盖安装旧版本。

### M2 完成标准

- 正常人类操作频率下，评论首页成功率 ≥ 90%。
- 评论翻页、回复展开无明显卡顿。
- 点赞/收藏失败能正确回滚，不出现重复计数。
- 签名桥故障不影响推荐流。
- Release APK 可安装、可升级、日志无 Cookie/token。
- GitHub Release 资产含 APK、SHA-256、更新说明、免责声明。

## 9. 里程碑

| 阶段 | 内容 | 预估 |
| --- | --- | --- |
| M2.0 | 签名桥 spike：`comment/list` + `aweme/detail`，确认签名和稳定性 | 1–2 天 |
| M2.1 | 评论只读面板 + 回复 + 分页 + 错误/降级 | 3–5 天 |
| M2.2 | 点赞/收藏 + 乐观更新 + feature flag | 2–3 天 |
| M2.3 | GitHub Release 工程：签名、CI、隐私、安装文档 | 2–3 天 |
| M2.4 | 真机回归、风控/异常处理、发布 | 2–3 天 |

**决策关口**：M2.0 结束时如果签名桥在模拟器和真机上都不稳定（频繁验证码/空响应/无法关联响应），停止评论/互动开发，改为“评论入口跳官方 WebView”，把剩余时间投入浏览闭环和播放体验。

## 10. 风险与缓解

| 风险 | 缓解 |
| --- | --- |
| 抖音前端/签名算法变更 | 隐藏 WebView 刷新页面即可换新 SDK；接口路径白名单；功能开关 |
| 风控/验证码/账号风险 | 单并发、低频、用户主动；不做后台/批量；首次启用互动时明确提示 |
| 隐藏 WebView 内存/耗电 | 单实例；后台降频；异常重建；上线前做内存对比 |
| Cookie/日志泄露 | 日志脱敏；不持久化响应；不上报；release 构建关闭调试日志 |
| GitHub Release 签名密钥丢失 | 本地/离线备份；CI secrets；发布文档写明 |
| 商标/应用商店/合规 | 不使用官方 logo/品牌暗示；GitHub 侧载；明确非官方免责声明；不下载/转存内容 |
| 第三方客户端违反抖音协议 | 仅个人学习/研究；不商用、不批量抓取；分发时显著提示账号风险 |

## 11. 待确认项

- 评论面板打开时是否暂停视频（当前建议暂停）。
- 是否在 M2 加入“检查 GitHub 新版本”（建议 P2）。
- 首发最低 Android 版本（当前 minSdk 24）。
- 是否在评论面板底部放“在官方页面打开”入口（建议放）。

## 12. M2.0 spike 结果（2026-11-04）

环境：Android 模拟器 `flclash`（API 34，x86_64），已登录抖音；隐藏 WebView 以 1×1 挂载在 Debug 页面上。

### 已验证

| 接口 | 结果 |
| --- | --- |
| `comment/list` 第 1–3 页 | 3× HTTP 200，30 条评论，`total=4350`，`has_more=1`；冷启动首请求约 12.8s，页面变热后约 200–1500ms |
| `aweme/detail` | HTTP 200，118906 bytes，约 376ms；`aweme_id`、`desc`、`video.width/height`、`play_addr.url_list` 可解析 |
| 登录态共享 | 隐藏 WebView 直接复用 App WebView 的 Cookie，无需额外注入 |
| 验证码 | 只读测试未触发；后续互动写入测试触发了验证码中间页（见 §13） |

### 未通过

- `comment/list/reply`：无论 XHR 还是 `fetch`，请求都会在 25s 后超时，响应 0 bytes。已尝试补充 `item_id`、`aweme_id`、`comment_id`、`cursor`、`count`、`item_type`、`app_name`、`app_type`，仍超时。需要后续确认：
  - 是否正确参数/路径（可能和文档记录的版本不一致）；
  - 该路径是否在 webmssdk 的拦截逻辑里发生死锁；
  - 是否必须由页面自身的回复 UI 触发。
- 真机验证：尚未在物理设备上登录并测试。

### 结论与下一步

- **评论列表 + 视频详情可行**，签名桥不依赖自研签名，且分页稳定。可以进入 M2.1 评论只读面板。
- 回复列表暂缓：先做评论主列表，不把“展开回复”作为 M2.1 的阻塞项；等抓到真实回复请求后再补。
- 后续优化：
  - 登录成功后提前挂载并预热签名 WebView，避免首次评论 10s+ 冷启动。
  - 为回复等异常接口设置更短的超时，避免 UI 卡 25s。
  - 真机登录后复测；确认 WebView 内存与耗电。
  - 若回复接口最终不可用，评论面板仍可上线，只隐藏“展开回复”。

## 13. M2 实现记录（2026-11-04）

### 已交付

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| M2.1 评论只读面板 | ✅ | 生产页已接入：评论列表、分页/去重、图文/表情评论、加载/空/错误状态；打开面板暂停视频，关闭恢复 |
| M2.2 点赞 / 收藏 | ✅ v0.2.1 默认开启 | `InteractionRepository` + `InteractionsController` + ActionRail 激活态/计数；乐观更新、失败回滚、请求中防重复；`aweme/detail` 同步初始状态；四条写路径实测 200 |
| M2.3 GitHub Release | ✅ | release 签名 Gradle 配置、tag 触发 Actions、APK + SHA-256、安装/隐私/发布文档；仓库与 `v0.2.0` Release 已发布 |
| M2.4 测试 | 🟡 部分 | `flutter analyze` 无问题；28 个单元测试通过；release APK 覆盖安装与播放回归通过；评论区被账号验证码阻断，见 §14 |

签名桥补充：
- 只读接口实测：3 页评论 30 条、详情 118906 bytes / 376ms；生产评论面板实测 35 条并触发第二页。
- 新增 `SignatureBridge.post`，写路径仅允许 `commit/item/digg` 与 `aweme/collect`。
- 新增验证码页面检测（标题/URL）与错误状态；评论面板重试时重载签名页。
- 全局请求最小间隔 250ms，避免高频请求。

### 风控事件与处理

开发期为了确认请求体，连续切换点赞状态时，隐藏 WebView 出现“验证码中间页”。此后：

- 停止在用户账号上继续发送写入请求；不自动重试写操作。
- 互动功能通过编译期开关 `DOUYINPLUS_ENABLE_INTERACTIONS` 控制，默认关闭；Release 工作流显式传 `false`。
- 点赞请求本身曾返回 HTTP 200 / `status_code=0`；取消点赞（`type=0`）与收藏（`action=1/0`）**尚未完成线上验证**，不能视为已验收。
- 初始互动状态未知：feed 不返回 `user_digged` / `user_collected`，按钮从“未点赞/未收藏”开始。后续可用 `aweme/detail` 补状态。

### 未完成 / 阻塞

- `comment/list/reply` 仍超时，回复展开未接入。
- 点赞/收藏的取消与收藏写入未验证，M2 验收标准中的“互动失败回滚”目前只有单元测试，不是端到端结果。
- GitHub Release 发布需要：仓库 remote、release keystore、四个 Actions secrets。本机尚未生成发布密钥，也未实际打 tag。
- 真机登录、评论、覆盖安装、签名桥内存/耗电未回归。
- 验证码账号状态需要用户本人处理；不要在未确认前继续测试写入。

### 结论

M2 的评论浏览与发布工程已达到可交付状态；互动代码完成但保持 feature flag 关闭；公开发布仍缺少密钥和仓库侧配置。在完成互动写入验证与 Release APK 安装验证前，不将 M2 标记为全部验收通过。

## 14. M2.4 验收记录（2026-11-04，模拟器）

环境：AVD `flclash`（API 34，x86_64），release APK（未配置 keystore，使用 debug key 签名，仅本机验证）。

| 项目 | 结果 |
| --- | --- |
| analyze / test | 无问题；28 个测试通过 |
| Release 构建 | `flutter build apk --release` 成功（51.2 MB，增量约 100s） |
| 覆盖安装 | 在已装 `0.2.0` 开发构建上 `adb install -r` 成功；`firstInstallTime` 保持 2026-11-04 03:15:43，登录态保留 |
| 登录态 | 个人面板 419 关注 / 29 粉丝；隐藏 WebView 复用会话 |
| 推荐流 + 播放 | 连续滑动切换正常，视频初始化成功（1920×1080 / 1440×1080），无崩溃 |
| 评论区 | 打开暂停视频、错误态与重试可用；加载被账号验证码阻断（见阻塞） |
| 日志脱敏 | logcat 中 `sessionid` / `sid_guard` / `passport_csrf` / `msToken` / `a_bogus` 命中 0 |
| 内存 | 含隐藏签名 WebView，总 PSS ≈ 164 MB |

### 发布链路

- GitHub 仓库：<https://github.com/watermeko/douyinplus>（public）。
- Release keystore 由本机生成（RSA 4096，`CN=DouyinPlus`，有效期 10000 天），凭据保存在 `.release-credentials.txt` 与 `android/key.properties`（均被 `.gitignore` 排除，需离线备份）。
- 四个 Actions secrets 已配置；`v0.2.0` tag 触发 `Release APK` 工作流成功（analyze / test / 签名构建 / SHA-256 / 创建 Release）。
- 下载已发布资产复核：`sha256sum -c` 通过；`apksigner` 证书 `CN=DouyinPlus`，SHA-256 `99:96:45:88:26:c6:64:7f:23:ef:0c:3b:0b:0a:9a:16:c4:1a:d6:1c:d8:cb:8c:02:58:e6:96:1f:39:05:e2:8c`（去冒号后 `99964588...`），与本地构建一致；`versionName=0.2.0`。
- 在全新 AVD 上安装该资产并启动成功，进入登录页（无既有会话）。
- 已发布的 APK 为 release 签名，与此前 `adb install` 的 debug 签名开发版互斥；从开发版切换需卸载一次。

### 发现并修复

1. **切换视频抛异常**：`AnimationController.stop` 报 “Null check operator used on a null value”。`FeedVideoItem.dispose` 先释放 `_disc` 再调用 `_stopVideo()`，而后者仍在调 `_disc.stop()`。已调整为先停播放器再释放 ticker，复测连续滑动无异常。
2. **验证码被误报成超时**：签名页进入 `rmc-verifycenter` 后，签名请求空等 20s 才报“评论加载超时”。新增验证码 DOM 探测（`#captcha_container`、`iframe[src*=captcha]` 等）、请求进行中每 3s 探测、error 状态不再等待 25s ready 超时，并把桥级“安全验证”错误映射为 risk。复测提示约 2s 出现，文案为“需要完成抖音安全验证，请重新登录后再试”。

### 阻塞与未完成

- 隐藏 WebView 当前停在抖音验证码页（开发期写入触发），只读评论请求同样被阻断。该状态需要账号本人完成官方验证或重新登录后才能复测；本轮未继续发写请求，避免加重风控。
- 因此“评论首页成功率 ≥ 90%”“翻页/回复展开”“互动失败回滚端到端”仍未验收。
- 真机回归、载入真实 keystore 的发布构建、GitHub Release 发布仍待完成。
- 首个 feed 条目为图文帖时只显示渐变背景（图文未渲染），非阻塞，待单独排查。

### 结论

Release 构建链路、覆盖安装升级、登录态保留、推荐流与播放、日志脱敏在模拟器上通过；评论与互动的端到端验收受账号验证码阻塞，M2 仍不标记为全部验收通过。

## 15. 验证码误判修复与互动验收（2026-11-05）

### 根因

v0.2.0 上线后，用户登录成功仍然提示“需要完成抖音安全验证”。排查发现抖音正常页面的 DOM 里本来就存在隐藏的验证码容器（`#captcha_container` 等），v0.2.0 的检测只要命中元素就判定为风控页，属于**误判**。

### 修复

- 验证码判定改为“元素可见”才成立：`getBoundingClientRect()` ≥ 80×80 且 `display` / `visibility` / `opacity` 正常。
- 命中时打印 `SignatureBridge risk probe hit:` 便于后续定位（仅标题/标记，不含 URL 查询串）。
- 保留请求进行中每 3s 探测与 error 状态快速失败。

### 复测结果（模拟器，正式签名包）

| 项目 | 结果 |
| --- | --- |
| 评论首屏 | `comment/list` HTTP 200，64246 bytes，729ms，381 条 |
| 评论翻页 | `comment/list` HTTP 200，71710 bytes，401ms |
| 点赞 | `commit/item/digg` type=1 → 200，182 bytes，11473ms（冷启动）/ 416ms（暖态） |
| 取消点赞 | type=0 → 200，182 bytes，416ms |
| 收藏 / 取消收藏 | `aweme/collect` action=1/0 → 200，192 bytes，约 300ms |
| 验证码 | 全过程未出现验证页 |

### 同步的状态修正

- `InteractionsController.hydrate()` 每支视频只拉一次 `aweme/detail` 的 `user_digged` / `user_collected`；用户先点击则不再覆盖。
- `kEnableInteractions` 默认改为 true（v0.2.1），仍可用 `DOUYINPLUS_ENABLE_INTERACTIONS=false` 关闭。

### 发布

- 版本 `0.2.1+3`，release notes `docs/release-notes/v0.2.1.md`，`v0.2.1` tag 由 CI 构建并发布（run 41982524541，success）。
- 发布资产复核：`sha256sum -c` 通过；`apksigner` 证书 `CN=DouyinPlus` 与 v0.2.0 一致；`versionName=0.2.1`、`versionCode=2`。
- 模拟器用 `adb install -r -d` 覆盖安装正式资产，`firstInstallTime` 保持，登录态保留；`comment/list` 200（62744 bytes）。

### 仍未完成

- `comment/list/reply` 超时未解，回复展开未接入。
- 图文帖图片未渲染。
- 真机（Redmi，Android 17）尚未安装回归。
