# 抖音 Web API 调研报告

> 调研时间：2026-11-04
> 目标：第三方抖音客户端 v1 —— 基础登录 + 推荐视频浏览
> 性质：对抖音 PC Web 端内部接口的黑盒调研，**非官方公开 API**，随时可能变更。本文档仅用于个人学习 / 技术研究，请勿用于批量抓取、内容搬运或其他违反抖音用户协议的场景。

---

## 0. 结论速览（TL;DR）

| 能力 | 结论 | 签名要求 |
| --- | --- | --- |
| 登录态复用 | 核心是 cookie `sessionid`（+ `sessionid_ss`） | 无 |
| 登录态校验 | `GET /aweme/v1/web/user/profile/self/` | 无 |
| 扫码登录 | `/passport/web/get_qrcode/` + `/passport/web/check_qrconnect/` | 需要 passport/account SDK 参数 |
| 推荐流 | `GET https://www.douyin.com/aweme/v1/web/tab/feed/` | **当前无签名也可用**（带 cookie） |
| 视频播放 | 直接用 `aweme_list[].video.play_addr.url_list[]` | 无（CDN 支持 Range） |
| 视频详情 | `/aweme/v1/web/aweme/detail/` | **必须签名** |
| 评论列表 | `/aweme/v1/web/comment/list/` | **必须签名**（无签名返回空 body） |
| 用户主页 | `/aweme/v1/web/user/profile/other/` | 无 |
| 相关推荐 | `/aweme/v1/web/aweme/related/` | 无 |

**对 v1 最重要的三点：**

1. **登录建议用 WebView 完成**：加载官方抖音登录页，用户在 WebView 内扫码/短信登录，客户端读取 WebView CookieStore 里的 `sessionid`、`ttwid` 等 cookie。自己实现扫码轮询需要 passport JS SDK 的签名参数，成本高且容易失效。
2. **推荐流可以纯 HTTP 实现**：带上 `sessionid` + `ttwid` 两个 cookie，加 UA/Referer，直接请求 `tab/feed` 即可拿到 `aweme_list` 和视频 CDN 直链，v1 不需要集成签名算法。
3. **详情页/评论需要签名**：这些接口在无签名时会被 Argus 风控拦截（403 `Signature Not Found` / 空响应）。如果 v1 不做详情页，可以先不处理；后续可以在隐藏 WebView 里复用官方 webmssdk 自动签名，或把相关页面直接用 WebView 承载。

---

## 1. 调研环境与方法

- 使用已登录抖音的 Chrome（真实账号、真实 IP），通过 CDP 自动化浏览器打开 `https://www.douyin.com/`。
- 用 HAR 录制首页、推荐流、视频播放、登录弹窗的网络请求；用页面内 `XMLHttpRequest` 主动调用目标接口并用 `agent-browser network request <id>` 取完整响应体。
- Cookie 从 Chrome profile 中解密后注入独立浏览器会话（值不落盘到仓库，仅用于本次调研）。
- 页面实际 UA 为 Chrome 156（本机安装的是 Chrome 152，站点侧 UA 可能被浏览器/环境改写），`version_code=170400`、`version_name=17.4.0`。
- 下文所有“实测”结论均基于 2026-11-04 的抖音 PC Web 线上环境，**抖音随时可能改版**。

---

## 2. 登录

### 2.1 登录态的本质：Cookie

抖音 Web 登录成功后，服务端通过 `Set-Cookie` 写入一组 cookie。调研时账号下共有 79 个 `*.douyin.com` cookie，其中与登录/风控直接相关的核心项：

| Cookie | 作用 | 备注 |
| --- | --- | --- |
| `sessionid` | **核心登录凭证** | 实测：仅凭它即可调用 `user/profile/self` |
| `sessionid_ss` | 同上（服务端会话） | 通常与 `sessionid` 一起下发 |
| `sid_tt` / `sid_guard` | 会话签名/元数据 | 建议保留 |
| `uid_tt` / `uid_tt_ss` | 用户标识会话 | 建议保留 |
| `ttwid` | 设备/Web 追踪 ID | **推荐流接口实测必需**（仅 `sessionid` 会失败） |
| `odin_tt` | 安全 SDK token | 建议保留 |
| `passport_csrf_token` | passport 写操作的 CSRF token | 登录相关 POST 需要 |
| `s_v_web_id` | 设备指纹 | 建议保留 |
| `UIFID` / `UIFID_TEMP` | 风控设备指纹 | 请求参数里也会带 `uifid` |
| `n_mh` | 账号安全标识 | 建议保留 |
| `d_ticket` / `has_biz_token` | 业务票据 | 建议保留 |
| `bd_ticket_guard_*` | 设备票据/证书 | 建议保留 |
| `passport_auth_status` / `_ss` | 登录状态标记 | 建议保留 |
| `x_tt_token` / `passport_assist_user` | 登录辅助 token | 建议保留 |

> `msToken` 不在 cookie 里，它是 webmssdk 在每次请求时动态生成并追加到 query 的。

**实测最小 cookie 组合：**

| 场景 | 最小 cookie | 结果 |
| --- | --- | --- |
| 查询登录用户 | `sessionid` | 200，返回 `user` |
| 推荐流 | `sessionid` + `ttwid` | 200，返回 `aweme_list` |
| 推荐流（只带 `sessionid`） | `sessionid` | 失败（无数据/异常） |

生产环境建议保存**完整 cookie 集**，因为风控会综合判断；只带最少 cookie 可能在换 IP、换 UA 或触发风控后失效。

**安全要求：**

- Cookie 等价于账号密码，必须加密存储（Android Keystore / iOS Keychain / 系统凭据库），不要明文写日志、不要提交到 Git。
- 不要把 cookie 发送到任何第三方服务器。
- 退出登录时同时清理本地 cookie 与服务端会话（调用 `/passport/web/logout/`）。

### 2.2 登录态校验

**接口：**

```
GET https://www.douyin.com/aweme/v1/web/user/profile/self/
```

**最小请求参数：**

```
device_platform=webapp&aid=6383&channel=channel_pc_web&pc_client_type=1&version_code=170400&version_name=17.4.0
```

**请求头：**

```
User-Agent: <桌面 Chrome UA>
Referer: https://www.douyin.com/
Cookie: sessionid=<...>; ...
```

**实测：**

- HTTP 200，`status_code=0`，`user` 对象存在即表示已登录。
- 仅带 `sessionid` 也能成功。
- 返回的 `user` 字段（节选）：`uid`、`sec_uid`、`nickname`、`unique_id`、`short_id`、`avatar_thumb`、`follower_count`、`following_count`、`aweme_count`、`total_favorited`、`signature`、`is_star` 等；`extra` 里还有 `user_collect_count`、`user_watchlater_count`。

**登出：**

```
POST https://www.douyin.com/passport/web/logout/
```

调用后服务端会清除会话 cookie；客户端仍需清本地存储。参数与签名要求未在 v1 中实测（建议直接走 WebView 内登出，或仅清本地 cookie）。

### 2.3 扫码登录流程（Web 端）

官方登录弹窗（未登录访问抖音首页自动弹出）的流程如下：

```
1) GET  /passport/web/get_qrcode/          获取二维码 + token
2) 渲染二维码（base64 PNG），每 ~2s 轮询
3) POST /passport/web/check_qrconnect/     携带 token 查询扫码状态
4) data.status: new -> scanned -> confirmed
5) confirmed 后浏览器收到 Set-Cookie，登录完成
```

#### 2.3.1 获取二维码

```
GET https://www.douyin.com/passport/web/get_qrcode/
```

关键 query（实际抓包，值已脱敏）：

| 参数 | 示例/说明 |
| --- | --- |
| `aid` | `6383` |
| `next` | `https://www.douyin.com` |
| `need_short_url` | `true` |
| `need_logo` | `false` |
| `is_new_login` | `1` |
| `is_from_iesaccountsaas` | `1` |
| `device_platform` | `web_app` |
| `passport_jssdk_version` | `3.4.13-beta.9` |
| `passport_jssdk_type` | `normal` |
| `is_from_ttaccountsdk` | `1` |
| `language` | `zh` |
| `account_app_language` | `en-US` |
| `p_ui` | `2.4.14-beta.9` |
| `p_js_v` / `p_js_t` / `p_zt` | passport SDK 版本信息 |
| `p_no` | SDK 生成的随机/签名串 |
| `p_ts` | 毫秒时间戳 |
| `sign` | SDK 生成的签名 |
| `qs` | SDK 生成的编码串 |
| `request_host` | `https%3A%2F%2Fwww.douyin.com` |
| `account_sdk_source` | `web` |
| `account_sdk_source_info` | SDK 生成的设备/环境编码 |
| `msToken` / `a_bogus` | webmssdk 自动追加的签名/token |
| `ts` / `biz_trace_id` | 时间戳 / 追踪 ID |

**响应（节选，已脱敏/截断）：**

```json
{
  "data": {
    "app_name": "抖音",
    "captcha": "",
    "copywriting": "{\"title\":\"请使用已登录账号的设备扫码\",...}",
    "error_code": 0,
    "expire_time": 1793730585,
    "frontier_params": {
      "access_key": "<redacted>",
      "frontier_device": "<redacted>",
      "method": 1,
      "product_id": 971,
      "service_id": 1024
    },
    "is_frontier": true,
    "qrcode": "iVBORw0KGgoAAAANSUhEUg...",
    "qrcode_index_url": "https://api.amemv.com/ucenter_web/...",
    "token": "<QR_TOKEN>",
    "web_name": "抖音"
  },
  "message": "success"
}
```

- `qrcode` 是 **base64 PNG**，可直接解码渲染；`expire_time` 约 60 秒后过期（实测 `p_ts` 与 `expire_time` 相差约 60s）。
- `token` 用于后续轮询。

#### 2.3.2 轮询扫码状态

```
POST https://www.douyin.com/passport/web/check_qrconnect/
Content-Type: application/x-www-form-urlencoded
```

form body（实际抓包）：

```
need_logo=false&is_frontier=true&token=<QR_TOKEN>&is_new_login=1&next=https%3A%2F%2Fwww.douyin.com&need_short_url=true
```

**等待扫码时的响应：**

```json
{
  "data": {
    "captcha": "",
    "desc_url": "",
    "description": "",
    "error_code": 0,
    "extra": "",
    "scan_app_id": 0,
    "status": "new"
  },
  "message": "success"
}
```

`data.status` 的状态机（从前端代码与抓包推断）：

| status | 含义 |
| --- | --- |
| `new` | 未扫码 |
| `scanned` | 已扫码，等待手机端确认 |
| `confirmed` | 手机端已确认，登录完成 |

`confirmed` 后浏览器会收到登录 `Set-Cookie`（`sessionid` 等）。客户端如果是 WebView 方案，此时直接从 CookieManager 读取即可。

> **重要限制**：`get_qrcode` / `check_qrconnect` 由 passport account SDK 生成 `p_no`、`qs`、`sign` 等参数，并被 webmssdk 追加 `msToken`/`a_bogus`。我们在已登录页面上下文里直接手写 XHR 调用 `get_qrcode` 时，被风控返回：
>
> ```json
> {"data":{"captcha":"","desc_url":"","description":"您正在尝试访问的网站存在安全风险，为保护您的抖音账号安全与隐私，已阻止此次访问。","error_code":4031},"message":"error"}
> ```
>
> 因此**不建议自己拼扫码登录请求**，除非能把官方 passport JS SDK 完整跑起来。

#### 2.3.3 其他登录方式（端点记录）

以下端点均来自登录页 JS bundle，实际调用同样依赖 passport SDK 签名，v1 建议交给 WebView：

| 方式 | 端点 | 主要参数（来自 JS） |
| --- | --- | --- |
| 短信验证码 | `POST /passport/web/send_code/` | `mobile`, `type`（默认 24）, `is6Digits=1`, `verify_ticket` |
| 短信登录 | `POST /passport/web/sms_login/` | `mobile`, `code`, `service=next`, 可选 `login_only=1` |
| 密码登录 | `POST /passport/web/user/login/` | `account`, `password`, `account_type=0`, `service=next`, `need_check_base_info=true`, `safe_mobile_register_to_login` |
| 一键登录 | `POST /passport/web/one_login/` | `sec_user_id`, `service`, `one_login_ticket` + `bd-ticket-guard` 请求头 |
| 二维码过期 | `POST /passport/web/expire_qrcode/` | token 等 |
| 登录状态查询 | `GET /passport/sso/check_login` | — |

### 2.4 v1 登录实现建议

| 方案 | 做法 | 优点 | 缺点 | 建议 |
| --- | --- | --- | --- | --- |
| **A. WebView 登录（推荐）** | 内嵌官方登录页（`https://www.douyin.com/` 或登录弹窗），用户扫码/短信登录；登录成功后从 WebView CookieStore 读取 `sessionid`、`ttwid` 等 | 实现简单、官方签名/风控链路完整、稳定性最好 | 需要 WebView 组件；UI 不完全可控 | ✅ v1 采用 |
| B. 自研扫码登录 | 自己调用 `get_qrcode` + `check_qrconnect`，渲染二维码 | UI 完全可控 | 需要运行 passport SDK，签名参数复杂；已被 4031 拦截 | ❌ 不建议 v1 |
| C. Cookie 导入 | 用户从浏览器导出 cookie，粘贴/导入 App | 开发调试最快 | 用户体验差、cookie 易泄露、不适合正式产品 | ⚠️ 仅开发调试 |

**WebView 方案流程：**

```
App 启动
  └─ 检查本地是否有 cookie
       ├─ 无 → 打开 WebView 登录页
       │        └─ 用户完成扫码/短信登录
       │             └─ 登录成功后读取 WebView CookieStore
       │                  └─ 加密保存 cookie（sessionid/ttwid/...）
       └─ 有 → 调用 user/profile/self 校验
            ├─ 200 且 user 存在 → 进入推荐流
            └─ 失败 → 回登录页
```

---

## 3. 推荐流 API（v1 核心）

### 3.1 端点

```
GET https://www.douyin.com/aweme/v1/web/tab/feed/
```

### 3.2 请求参数

#### 公共参数（建议都带上）

| 参数 | 值 | 说明 |
| --- | --- | --- |
| `device_platform` | `webapp` | 固定 |
| `aid` | `6383` | 抖音 Web 的 app id |
| `channel` | `channel_pc_web` | 固定 |
| `pc_client_type` | `1` | PC |
| `pc_libra_divert` | `Linux` / `Windows` / `Mac` | 按真实平台填写 |
| `support_h265` | `1` | 是否支持 H.265 |
| `support_dash` | `1` | 是否支持 DASH |
| `version_code` | `170400` | 调研时版本 |
| `version_name` | `17.4.0` | 调研时版本 |
| `cookie_enabled` | `true` | — |
| `screen_width` / `screen_height` | 如 `2560` / `1600` | 屏幕尺寸 |
| `browser_language` | 如 `zh-CN` | — |
| `browser_platform` | 如 `Linux x86_64` | — |
| `browser_name` | `Chrome` | — |
| `browser_version` | 如 `156.0.0.0` | — |
| `browser_online` | `true` | — |
| `engine_name` | `Blink` | — |
| `engine_version` | 同 `browser_version` | — |
| `os_name` | `Linux` / `Windows` / `Mac OS X` | — |
| `os_version` | 如 `x86_64` | — |
| `platform` | `PC` | — |
| `downlink` | `10` | 网络下行（Mbps） |
| `effective_type` | `4g` | — |
| `round_trip_time` | `200` | RTT（ms） |
| `webid` | 设备 web id | 可从 cookie/`ttwid` 体系获取；可省略测试 |
| `uifid` | 设备 UIFID | 建议带；详情接口必需 |

#### 业务参数

| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `count` | int | 请求条数，实测服务端会限制；建议 6~10 |
| `refresh_index` | int | **翻页/刷新序号**，首屏 1，之后递增 2、3、4... |
| `filterGids` | string | 上一批最后一条（或当前播放）的 `aweme_id`，用于去重 |
| `pull_type` | int | 首屏 `0`；加载更多/下拉刷新可试 `1` |
| `video_type_select` | int | 固定 `1` |
| `tag_id` | string | 频道/话题 ID，推荐流留空 |
| `share_aweme_id` | string | 分享场景才用；留空 |
| `live_insert_type` | string | 直播插入策略；可留空 |
| `pc_launch_live_filters` | string | 直播过滤；可留空 |
| `aweme_pc_rec_raw_data` | string(JSON) | 推荐原始数据，前端内部使用；可留空 |
| `globalwid` | string | 全局窗口 ID；可留空 |
| `refresh_type` | int | 刷新类型；可留空 |
| `min_window` | int | 小窗模式；可留空 |
| `free_right` | bool/int | 权限相关；可留空 |
| `view_count` | int | 播放次数上报；可留空 |
| `req_count` | int | 请求计数；可留空 |
| `plug_block` | int | 插件屏蔽；可留空 |
| `need_translation` | int | 翻译；可留空 |

#### 实测最小可用请求（Python 直连）

```http
GET https://www.douyin.com/aweme/v1/web/tab/feed/?device_platform=webapp&aid=6383&channel=channel_pc_web&pc_client_type=1&version_code=170400&version_name=17.4.0&count=6&refresh_index=2&video_type_select=1&pull_type=1&filterGids=<上一批最后一条 aweme_id>
User-Agent: <桌面 Chrome UA>
Referer: https://www.douyin.com/?recommend=1
Cookie: sessionid=<SESSIONID>; ttwid=<TTWID>
```

> 实测 **不带 `a_bogus`/`msToken` 也能成功**。但如果“部分”带签名（例如只带 `msToken`、缺 `a_bogus`），会被拒绝：`403 Blocked by ArgusSecurityPlugin Sign Invalid`。因此要么全不带，要么由 SDK 全量生成。

### 3.3 分页语义（实测）

| `refresh_index` | `filterGids` | `pull_type` | `count` | 实测返回 |
| --- | --- | --- | --- | --- |
| `1` | 空 | `0` | `6`/`10` | 约 2 条（首屏冷启动） |
| `2` | 上一批最后一条 | `0` | `6` | 6 条，`has_more=1` |
| `3` | 上一批最后一条 | `1` | `6` | 6 条，`has_more=1` |

**建议客户端逻辑：**

```text
refresh_index = 1
filterGids = ""
loop:
    resp = GET tab/feed (count=6, refresh_index, filterGids, pull_type = (refresh_index == 1 ? 0 : 1))
    if resp.aweme_list empty: break
    append(resp.aweme_list)
    filterGids = resp.aweme_list[-1].aweme_id
    refresh_index += 1
    sleep(1~3s)  # 控制频率
```

- 响应没有 `cursor`，只有 `has_more` 和 `aweme_list`。
- 去重建议客户端按 `aweme_id` 再做一次。
- 不要并发狂刷；推荐流对频率敏感，建议串行 + 2~3 秒间隔。

### 3.4 请求头

| Header | 值/说明 |
| --- | --- |
| `User-Agent` | 与平台一致的桌面 Chrome UA；建议固定不变 |
| `Referer` | `https://www.douyin.com/?recommend=1`（推荐流）或 `https://www.douyin.com/` |
| `Accept` | `application/json, text/plain, */*` |
| `Accept-Language` | 如 `zh-CN,zh;q=0.9` |
| `Cookie` | 见 2.1，至少 `sessionid` + `ttwid` |
| `sec-ch-ua` / `sec-ch-ua-mobile` / `sec-ch-ua-platform` | 建议与 UA 保持一致（可选） |

### 3.5 响应结构

**顶层：**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `status_code` | int | `0` 表示成功 |
| `aweme_list` | array | 视频/图文列表 |
| `has_more` | int/bool | 是否还有更多 |
| `log_pb` | object | 日志/追踪信息 |

**`aweme_list[]` 核心字段：**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `aweme_id` | string | 作品 ID（19 位数字字符串） |
| `group_id` | string | 同 `aweme_id` |
| `aweme_type` | int | `0` 视频；图文/其他类型见官方枚举 |
| `media_type` | int | 实测视频为 `4` |
| `create_time` | int | 发布时间，Unix 秒 |
| `desc` | string | 文案（含话题） |
| `item_title` | string | 标题（可能为空） |
| `duration` | int | 时长（毫秒，在 `video.duration`） |
| `share_url` | string | 分享页 URL（`iesdouyin.com/share/video/...`） |
| `author` | object | 作者信息，见下 |
| `video` | object | 视频信息，见下 |
| `statistics` | object | 互动数据，见下 |
| `music` | object | 音乐信息 |
| `text_extra` | array | 话题/提及列表：`hashtag_id`、`hashtag_name`、`start`、`end` |
| `user_digged` | int | 当前用户是否点赞（`0/1`） |
| `is_top` | int | 是否置顶 |
| `images` | array/null | 图文作品的图片列表 |

**`author`：**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `uid` | string | 用户 ID |
| `sec_uid` | string | 加密用户 ID（主页 API 用） |
| `nickname` | string | 昵称 |
| `unique_id` | string | 抖音号（可能为空） |
| `avatar_thumb` / `avatar_medium` / `avatar_larger` | object | 头像，含 `url_list` |
| `follower_count` / `following_count` / `aweme_count` | int | 粉丝/关注/作品数（**feed 里不一定返回，详情/主页接口才有**） |
| `signature` | string | 签名（feed 里可能为空） |

**`video`：**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `duration` | int | 毫秒 |
| `width` / `height` | int | 分辨率 |
| `ratio` | string | 宽高比标识 |
| `is_long_video` | int | 是否长视频 |
| `play_addr` | object | 默认播放地址（通常 720p） |
| `play_addr_h264` | object | H.264 播放地址 |
| `play_addr_265` | object | H.265/HEVC 播放地址（体积更小） |
| `cover` / `dynamic_cover` / `origin_cover` | object | 封面/动态封面/原始封面，含 `url_list` |
| `bit_rate` | array | 多码率列表（19 项左右），可做清晰度切换 |
| `bit_rate_audio` | array | 音频码率 |

**`play_addr` / `cover` 结构：**

```json
{
  "data_size": 53695007,
  "file_cs": "...",
  "file_hash": "...",
  "height": 1080,
  "width": 1920,
  "uri": "v0d00fg10000...",
  "url_key": "...",
  "url_list": [
    "https://v26-weba.douyinvod.com/<signed>/video/tos/cn/...",
    "https://v3-weba.douyinvod.com/...",
    "https://v95-web-sz.douyinvod.com/..."
  ]
}
```

- `url_list` 通常 3 个镜像，**选第一个可用即可**，失败再降级到下一个。
- 视频 URL 带 CDN 过期时间（`x-expires` 风格参数），**每次拉 feed 都会变，不要长期缓存**。
- 实测 CDN 支持 `Range: bytes=0-1023`，返回 `206 Partial Content`，**不需要 cookie、不需要 Referer**。
- 封面图同理，直接 HTTP GET 即可。

**`statistics`：**

```json
{
  "collect_count": 1157,
  "comment_count": 59,
  "digg_count": 10633,
  "download_count": 4,
  "forward_count": 0,
  "play_count": 0,
  "recommend_count": 189,
  "share_count": 475
}
```

> Web 端 `play_count` 通常为 0（不公开）；`digg_count` / `comment_count` / `collect_count` / `share_count` 可用。

### 3.6 实测响应样例（字段已脱敏/截断）

```json
{
  "status_code": 0,
  "has_more": 1,
  "aweme_list": [
    {
      "aweme_id": "7703206229157416235",
      "aweme_type": 0,
      "media_type": 4,
      "create_time": 1793578081,
      "desc": "破局名场面：…… #抖音精选 #……",
      "item_title": "破局名场面：……",
      "author": {
        "uid": "130163525296012",
        "sec_uid": "MS4wLjABAAAA...",
        "nickname": "<作者昵称>",
        "avatar_thumb": {
          "url_list": ["https://p3-pc.douyinpic.com/aweme/100x100/...jpeg"]
        }
      },
      "video": {
        "duration": 237819,
        "width": 1920,
        "height": 1080,
        "play_addr": {
          "data_size": 53695007,
          "url_list": [
            "https://v26-weba.douyinvod.com/<signed>/video/tos/cn/..."
          ]
        },
        "cover": {
          "url_list": ["https://p9-pc-sign.douyinpic.com/image-cut-tos-priv/...jpeg"]
        }
      },
      "statistics": {
        "digg_count": 10633,
        "comment_count": 59,
        "collect_count": 1157,
        "share_count": 475
      },
      "music": {
        "title": "@<作者>创作的原声",
        "author": "<作者昵称>"
      },
      "text_extra": [
        {"hashtag_id": "1597179861293063", "hashtag_name": "破局"}
      ]
    }
  ],
  "log_pb": {"impr_id": "..."}
}
```

### 3.7 播放实现建议

1. 从 `aweme_list[].video.play_addr.url_list` 取第一个 URL，交给播放器（ExoPlayer/AVPlayer/mpv/ffmpeg）。
2. 如果播放失败，依次尝试 `url_list[1]`、`url_list[2]`，再尝试 `play_addr_h264` / `play_addr_265`。
3. 不要下载完整文件后再播放；CDN 支持 Range，直接流式播放。
4. `play_addr` 的 URL 会过期；重新拉 feed 获取新 URL，或对当前视频重新请求详情（需要签名，见 4.1）。
5. 封面用 `video.cover.url_list[0]`，列表页先展示封面，点击后再起播。

---

## 4. 辅助接口（按签名要求分组）

### 4.1 视频详情（需要签名）

```
GET https://www.douyin.com/aweme/v1/web/aweme/detail/?aweme_id=<AWEME_ID>&...
```

- 实测带完整签名（页面内 XHR 自动生成）返回 200，`aweme_detail` 字段约 200 个。
- 外部直连（仅 cookie + `uifid`）：
  - 不带 `uifid`：`403 Blocked by ArgusSecurityPlugin Uifid Not Found`
  - 带 `uifid` 但无签名：`403 Blocked by ArgusSecurityPlugin Signature Not Found`
- 结论：**必须签名**。
- 响应核心：`aweme_detail`（结构同 feed 的单个 aweme，但字段更全，含 `author.follower_count`、`video.bit_rate` 等）。

### 4.2 评论列表（需要签名）

```
GET https://www.douyin.com/aweme/v1/web/comment/list/?aweme_id=<ID>&cursor=0&count=20&item_type=0
```

- 带签名：200，返回 `comments`、`cursor`、`has_more`、`total`。
- 无签名（剥离全部签名参数）：200 但 **body 为空**（不是 403，但同样不可用）。
- 评论对象核心字段：`cid`、`text`、`create_time`、`digg_count`、`reply_comment_total`、`ip_label`、`is_author_digged`、`user{}`、`reply_comment{}`。
- 分页：`cursor` 用响应里的 `cursor`，`has_more=1` 继续。
- 评论回复：`GET /aweme/v1/web/comment/list/reply/?comment_id=<CID>&cursor=0&count=20`。

### 4.3 用户主页（无需签名）

**他人主页：**

```
GET https://www.douyin.com/aweme/v1/web/user/profile/other/?sec_user_id=<SEC_UID>&publish_video_strategy_type=2
```

- 实测无签名可通（200，`user` 对象）。
- 关键字段：`uid`、`sec_uid`、`nickname`、`unique_id`、`signature`、`follower_count`、`following_count`、`aweme_count`、`total_favorited`、`avatar_*`。

**自己的主页：**

```
GET https://www.douyin.com/aweme/v1/web/user/profile/self/
```

- 实测无签名可通；仅 `sessionid` 即可。
- 用于登录态校验与“我的”页。

**用户作品列表：**

```
GET https://www.douyin.com/aweme/v1/web/aweme/post/?sec_user_id=<SEC_UID>&max_cursor=0&count=20
```

- 调研中未单独验证签名要求；按同类接口推断可能需要签名，接入前需实测。

### 4.4 相关推荐（无需签名）

```
GET https://www.douyin.com/aweme/v1/web/aweme/related/?aweme_id=<ID>&count=20
```

- 实测无签名可通（200，`aweme_list` 10 条，`has_more`）。
- 可用于“相关视频”列表。

### 4.5 互动类写接口（v1 不做）

从 JS bundle 中提取到以下端点，写操作涉及签名、CSRF、设备票据，v1 不建议实现：

| 功能 | 端点 |
| --- | --- |
| 点赞 | `POST /aweme/v1/web/commit/item/digg/` |
| 取消点赞 | `POST /aweme/v1/web/cancel/item/digg/multi/` |
| 关注 | `POST /aweme/v1/web/commit/follow/user/` |
| 收藏 | `POST /aweme/v1/web/aweme/collect/` |
| 评论发布 | `POST /aweme/v1/web/comment/publish` |
| 评论点赞 | `POST /aweme/v1/web/comment/digg` |
| 分享 | `POST /aweme/v1/web/aweme/share/`（具体路径待确认） |

---

## 5. 签名与风控说明（重要）

### 5.1 webmssdk 自动签名

在抖音页面上下文里，`XMLHttpRequest` 被 webmssdk 包装。请求匹配受保护路径时，SDK 会自动追加：

| 位置 | 参数/头 | 说明 |
| --- | --- | --- |
| Query | `msToken` | 动态 token |
| Query | `a_bogus` | 主签名 |
| Query | `timestamp` | 时间戳 |
| Query | `uifid` | 设备指纹 |
| Query | `verifyFp` / `fp` | 验证指纹 |
| Query | `x-secsdk-web-signature` | 二次签名 |
| Query/Header | `sign`、`qs`、`p_no` 等 | passport SDK 专用 |

**实测结论：**

| 请求方式 | 结果 |
| --- | --- |
| 页面内 XHR（SDK 自动签名）调用 `tab/feed` | 200 |
| 外部直连，**完全不带**签名参数，仅 cookie + base params | 200 |
| 外部直连，带部分签名参数（如 `msToken`）但缺 `a_bogus` | 403 `Sign Invalid` |
| 外部直连 `aweme/detail`，带 `uifid` 无签名 | 403 `Signature Not Found` |
| 外部直连 `comment/list`，剥离全部签名 | 200 但空 body |
| 外部直连 `user/profile/self`、`user/profile/other`、`aweme/related` | 200 |

> **策略建议**：feed 走“无签名”直连；一旦需要 detail/comment 等接口，就在隐藏 WebView 里执行官方页面上下文请求（SDK 自动签名），把响应回传给原生层。不要在无签名请求里混入部分签名参数。

### 5.2 风控要点

- **IP / UA / Cookie 绑定**：换网络、换 UA、换设备指纹都可能触发验证码或空响应。
- **频率**：推荐流接口对高频请求敏感；建议串行、2~3 秒间隔、失败指数退避。
- **指纹**：`ttwid`、`s_v_web_id`、`UIFID`、`bd_ticket_guard_*` 等 cookie 不要随意丢弃；完整的 cookie 集比“最小集”稳。
- **验证码**：headless 浏览器首次访问容易触发滑块验证码；桌面 headed 浏览器 + 真实 cookie 基本不触发。App 内 WebView 登录场景通常也不触发。
- **签名会变**：`a_bogus` 算法、参数名、版本号（`version_code`/`version_name`）会随抖音前端发版变化；v1 依赖无签名 feed 的前提下，也要做好“随时失效”的准备。

---

## 6. 客户端架构建议（v1）

### 6.1 推荐架构

```
┌─────────────────────────────────────────────┐
│                App (Android/iOS/Desktop)    │
│                                             │
│  ┌──────────────┐      ┌─────────────────┐  │
│  │ Login WebView│      │  Cookie Store   │  │
│  │ (official)   │─────▶│  (encrypted)    │  │
│  └──────────────┘      └────────┬────────┘  │
│                                 │           │
│  ┌──────────────┐      ┌────────▼────────┐  │
│  │ Video Player │◀─────│  Feed Client    │  │
│  │ (Exo/AVPlayer)│      │  HTTP + cookies │  │
│  └──────────────┘      └────────┬────────┘  │
│                                 │           │
│  ┌──────────────┐      ┌────────▼────────┐  │
│  │  UI (feed)   │◀─────│  JSON parser    │  │
│  └──────────────┘      └─────────────────┘  │
│                                             │
│  可选：Hidden WebView + webmssdk（详情/评论）│
└─────────────────────────────────────────────┘
```

### 6.2 模块划分

| 模块 | 职责 |
| --- | --- |
| `AuthWebView` | 加载官方登录页，登录成功后读取并加密保存 cookie |
| `SessionStore` | 保存/读取 cookie（Keystore/Keychain），提供 `sessionid`、`ttwid` 等 |
| `AuthService` | 调用 `user/profile/self` 校验登录态；处理 401/空响应→重新登录 |
| `FeedService` | 调用 `tab/feed`，维护 `refresh_index`、`filterGids`、去重、重试 |
| `FeedRepository` | 缓存当前 feed 列表、封面、播放进度 |
| `PlayerService` | 从 `play_addr.url_list` 选流，处理镜像降级、Range、错误重试 |
| `SignatureService`（可选） | 隐藏 WebView 内执行官方页面 XHR，处理 detail/comment 等签名接口 |

### 6.3 关键实现细节

1. **Cookie 注入**：原生 HTTP 客户端每次请求带 `Cookie` 头；播放器请求 CDN 不需要 cookie。
2. **UA 一致**：登录 WebView 的 UA 与原生 HTTP 请求的 UA 保持一致，减少风控差异。
3. **Referer**：feed 请求带 `Referer: https://www.douyin.com/?recommend=1`。
4. **首次加载**：`refresh_index=1` 可能只返回 2 条，属正常；继续翻页即可。
5. **翻页**：`filterGids = 上一批最后一条 aweme_id`，`refresh_index += 1`，`pull_type=1`。
6. **失败处理**：
   - 403 / 空 body → 可能是风控或 cookie 失效；先校验 `profile/self`，再决定重新登录或退避。
   - 视频 403/404 → 换 `url_list` 下一个镜像，或重新拉 feed 刷新 URL。
7. **合规**：不要缓存/分发视频文件；只做在线播放；遵守抖音用户协议与版权要求。

### 6.4 技术选型参考

| 平台 | 推荐 |
| --- | --- |
| Android | Kotlin + Jetpack Compose + ExoPlayer/Media3 + WebView（登录） |
| iOS | Swift + SwiftUI + AVPlayer + WKWebView（登录） |
| 跨平台 | Flutter（`webview_flutter` + `video_player`/`media_kit`） |
| 桌面 | Electron/Tauri（登录用 BrowserWindow/WebView2，播放用 `<video>` 或 mpv） |

---

## 7. 风险与限制

1. **非官方接口**：随时可能变更、加签、下线；必须保留降级方案（WebView 兜底）。
2. **账号风险**：高频请求、异常 UA/IP、共享 cookie 可能触发风控、验证码，甚至封号；建议控制频率、单账号单设备。
3. **用户协议**：第三方客户端可能违反抖音用户协议；本文档仅供个人学习/研究，请勿商用或批量抓取。
4. **版权**：视频、封面、音乐版权归原作者/抖音所有；客户端只做在线播放，不下载、不转存、不二次分发。
5. **Cookie 安全**：cookie = 账号凭证；必须加密存储，避免日志、崩溃上报、备份泄露。
6. **数据准确性**：本文档的字段/参数/状态码均来自 2026-11-04 的实测与 JS bundle 阅读，抖音改版后可能失效。

---

## 8. 附录

### 8.1 实测矩阵（2026-11-04）

| # | 请求 | 签名 | 结果 |
| --- | --- | --- | --- |
| 1 | `tab/feed` 页面内 XHR | SDK 自动 | 200，`aweme_list` |
| 2 | `tab/feed` 外部直连（cookie + base params） | 无 | 200，`aweme_list` |
| 3 | `tab/feed` 只带 `sessionid` | 无 | 失败 |
| 4 | `tab/feed` `sessionid` + `ttwid` | 无 | 200，6 条 |
| 5 | `tab/feed` 带 `msToken` 缺 `a_bogus` | 部分 | 403 `Sign Invalid` |
| 6 | `aweme/detail` 页面内 XHR | SDK 自动 | 200 |
| 7 | `aweme/detail` 外部直连 + `uifid` | 无 | 403 `Signature Not Found` |
| 8 | `aweme/detail` 外部直连 | 无 | 403 `Uifid Not Found` |
| 9 | `comment/list` 页面内 XHR | SDK 自动 | 200，20 条 |
| 10 | `comment/list` 外部直连 | 无 | 200 空 body |
| 11 | `user/profile/self` 外部直连 | 无 | 200，`user` |
| 12 | `user/profile/other` 外部直连 | 无 | 200，`user` |
| 13 | `aweme/related` 外部直连 | 无 | 200，10 条 |
| 14 | 视频 CDN Range 请求 | 无 | 206，`video/mp4` |
| 15 | 封面 CDN GET | 无 | 200，`image/jpeg` |
| 16 | `passport/web/get_qrcode` 页面内手写 XHR | 无 passport SDK 签名 | 200，`error_code=4031`（风控拦截） |
| 17 | `passport/web/get_qrcode` 官方登录页 | SDK 自动 | 200，返回二维码 + token |
| 18 | `passport/web/check_qrconnect` 官方页面轮询 | SDK 自动 | 200，`status=new`（等待扫码） |

### 8.2 开发期 cookie 导出

仅限本机开发调试，推荐用自动化浏览器（如 agent-browser / Playwright）打开已登录的抖音页面，然后从浏览器上下文导出 cookie：

```bash
# 示例：使用 agent-browser 打开抖音后导出当前域 cookie
agent-browser open https://www.douyin.com/
agent-browser cookies get --json > /tmp/douyin-cookies.json
```

注意事项：

- 导出的 JSON 含 `sessionid` 等敏感值，**不要提交到 Git**，用完即删。
- 生产 App 不要提供“粘贴 cookie 登录”功能；用 WebView 官方登录。
- 调研时从 Chrome profile 解密 cookie 的方法仅用于本地研究，不建议在产品中实现。

### 8.3 页面路由参考

| 页面 | URL |
| --- | --- |
| 推荐流（全屏播放器） | `https://www.douyin.com/?recommend=1` |
| 精选（PC 首页） | `https://www.douyin.com/jingxuan` |
| 视频详情 | `https://www.douyin.com/video/<aweme_id>` |
| 用户主页 | `https://www.douyin.com/user/<sec_uid>` |
| 搜索 | `https://www.douyin.com/search/<keyword>` |
| 登录弹窗 | 未登录访问首页自动弹出；登录页 JS 在 passport bundle 中 |

### 8.4 最小 Python 示例（推荐流）

```python
import json
import requests

COOKIES = {
    "sessionid": "<SESSIONID>",
    "ttwid": "<TTWID>",
}

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36"
    ),
    "Referer": "https://www.douyin.com/?recommend=1",
    "Accept": "application/json, text/plain, */*",
}

BASE = {
    "device_platform": "webapp",
    "aid": "6383",
    "channel": "channel_pc_web",
    "pc_client_type": "1",
    "version_code": "170400",
    "version_name": "17.4.0",
    "video_type_select": "1",
}


def fetch_feed(refresh_index: int, filter_gids: str = "", count: int = 6):
    params = {
        **BASE,
        "count": str(count),
        "refresh_index": str(refresh_index),
        "pull_type": "0" if refresh_index == 1 else "1",
        "filterGids": filter_gids,
    }
    r = requests.get(
        "https://www.douyin.com/aweme/v1/web/tab/feed/",
        params=params,
        headers=HEADERS,
        cookies=COOKIES,
        timeout=20,
    )
    r.raise_for_status()
    return r.json()


def main():
    refresh_index = 1
    filter_gids = ""
    for _ in range(3):
        data = fetch_feed(refresh_index, filter_gids)
        items = data.get("aweme_list") or []
        print(f"[page {refresh_index}] {len(items)} items, has_more={data.get('has_more')}")
        for item in items:
            video = item.get("video") or {}
            play_urls = (video.get("play_addr") or {}).get("url_list") or []
            print(
                item["aweme_id"],
                item.get("desc", "")[:40],
                (item.get("author") or {}).get("nickname"),
                play_urls[0] if play_urls else "(no play url)",
            )
        if not items:
            break
        filter_gids = items[-1]["aweme_id"]
        refresh_index += 1


if __name__ == "__main__":
    main()
```

### 8.5 术语

| 术语 | 含义 |
| --- | --- |
| `aweme` | 抖音对“作品/视频”的内部叫法 |
| `aweme_id` | 作品 ID |
| `sec_uid` | 加密用户 ID，用户主页接口使用 |
| `a_bogus` | 抖音 Web 主签名参数 |
| `msToken` | 动态 token，由 webmssdk 生成 |
| `webmssdk` | 抖音 Web 安全 SDK，负责签名与风控 |
| `passport` | 抖音登录/账号体系 |
| `ttwid` | 设备/Web 追踪 ID，推荐流必需 |
| `uifid` | 设备指纹 ID |

---

> 文档结束。后续如果要做详情页、评论、点赞等能力，建议在本文基础上补充“隐藏 WebView + webmssdk 签名代理”的专项调研。