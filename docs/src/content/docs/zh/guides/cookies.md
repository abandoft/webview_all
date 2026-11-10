---
title: Cookies
description: 管理共享 WebView cookie 和平台特有 cookie 元数据。
---

`WebViewCookieManager` 管理底层 WebView 引擎的 cookie。

```dart
final cookies = WebViewCookieManager();

await cookies.setCookie(
  const WebViewCookie(
    name: 'session',
    value: 'abc',
    domain: 'example.com',
    path: '/',
  ),
);

final list = await cookies.getCookies(
  domain: Uri.parse('https://example.com'),
);
final hadCookies = await cookies.clearCookies();
```

## 通用行为

| 方法 | 作用 |
| --- | --- |
| `setCookie` | 设置 Cookie 及可选的过期时间、安全属性和 SameSite。 |
| `getCookies` | 返回指定 URL 可见的 Cookie。 |
| `clearCookies` | 清空 cookie，并在平台可报告时返回清空前是否存在 cookie。 |
| `getCapabilities` | 查询属性读取和删除能力。 |
| `deleteCookie` | 按 name/domain/path 删除 Cookie。 |

cookie 名称、domain 和 path 会做基本校验。非空 path 必须以 `/` 开头。

## 清理全部网站数据

注销时即使没有正在使用的 controller，也可直接清理共享数据：

```dart
final result = await WebViewDataManager().clearAllWebsiteData();

if (!result.isComplete) {
  debugPrint('不支持：${result.unsupportedDataTypes}');
  debugPrint('失败：${result.failures}');
}
```

该 manager 操作普通 WebView 共用的数据区；Windows 和 Linux 使用已选共享环境，其他平台使用默认数据区。它按平台能力清理 Cookie、缓存、local/session storage、IndexedDB、WebSQL、Cache Storage 和 service worker，并明确返回每类数据是已清理、不支持还是失败。注销流程必须检查 `isComplete`，不能把部分成功当成完整清理。密码、自动填充、下载记录、浏览记录和引擎设置不在该接口范围内。

Windows 和 Linux 的自定义目录应在首次创建 WebView、操作 Cookie 或清理网站
数据前配置。从 1.4.7 起，默认 manager 会复用已选环境，无需重复传参。如果首次
操作就是清理，可通过 `WindowsWebViewDataManagerCreationParams` 或
`LinuxWebViewDataManagerCreationParams` 指定环境。显式参数必须与已选配置一致，
冲突会记录在 `result.failures` 中。Windows 使用临时 native controller，但不会
启动图形捕获或创建 Flutter 纹理；Linux 清理时无需创建 WebView。

| 平台 | 行为 |
| --- | --- |
| Android | 系统 WebView 支持时使用 AndroidX WebKit 的完整清理接口；旧版本清理 Cookie、缓存、local storage 和 WebSQL，其余类型标记为不支持。 |
| iOS/macOS | 清理 `WKWebsiteDataStore.default()` 中的对应数据类型。 |
| Windows | 清理 WebView2 暴露的 Cookie、DOM storage 类型和磁盘缓存；session storage 与 service worker 注册标记为不支持，旧 Runtime 没有 profile 清理接口时全部标记为不支持。 |
| Linux | 清理已选共享 WebKitGTK 环境中的全部网站数据。 |
| OHOS | 无需创建 WebView 即可清理 Cookie、共享资源缓存、local storage 和 WebSQL；session storage、IndexedDB、Cache Storage 和 service worker 注册标记为不支持。 |
| Web | 全部标记为不支持，因为宿主页无权清理任意 iframe origin 或 `HttpOnly` Cookie。 |

## 平台差异

| 平台 | 存储 | 说明 |
| --- | --- | --- |
| Android | Android WebView `CookieManager` | 保留编码 name/value 和值中的 `=`，支持第三方 cookie 策略。 |
| iOS/macOS | `WKWebsiteDataStore.defaultDataStore` | 按域名、路径、协议和过期时间过滤。 |
| Windows | WebView2 cookie manager | 支持通用属性及原有平台扩展。 |
| Linux | WebKitGTK cookie bridge | 支持常用属性及定向删除。 |
| OHOS | ArkWeb `CookieManager` | 支持第三方 cookie 策略。 |
| Web | `document.cookie` | 只能访问宿主页可见 cookie。 |

## Cookie 属性与定向删除

```dart
final capabilities = await cookies.getCapabilities();
await cookies.setCookie(WebViewCookie(
  name: 'session', value: 'abc', domain: '.example.com', path: '/',
  expires: DateTime.now().toUtc().add(const Duration(days: 7)),
  isSecure: true,
  isHttpOnly: true,
  sameSite: WebViewCookieSameSite.lax,
));
await cookies.deleteCookie(name: 'session', domain: '.example.com', path: '/');
```

`expires`、`isSecure`、`isHttpOnly`、`sameSite` 用于写入，`isSession` 是读取元数据。
`SameSite=None` 需同时设置 `isSecure: true`。删除时须提供实际的名称、域名和路径；
返回 `true` 表示操作已完成，不代表该 Cookie 原先一定存在。

Android 的 System WebView 支持 `GET_COOKIE_INFO` 时，可读取原生路径、HttpOnly、过期时间
及可用的 SameSite 等属性，并区分同名不同路径的 Cookie；缺失的 SameSite 保留为未知。
旧版 Android 内核和 OHOS 仍只提供名称和值，其余属性保留 `null`；此时返回的 domain/path
是兼容字段，不能用来推断存储中的 Cookie 身份。
iOS、macOS、Windows、Linux 可读取原生属性，具体见 `readableAttributes`。
Web 只可操作宿主页可见 Cookie，无法操作 `HttpOnly` Cookie；请求创建它时会打印
说明并跳过，避免设置成普通 Cookie。

Windows 的全局 Cookie 接口会在应用的浏览器会话内保留会话 Cookie，包括首次加载页面之前。
需要跨应用启动保留时请设置过期时间；会话 manager 遵循所属 Profile 的生命周期。
原有 Windows 专用 Cookie 接口继续可用。

## 第三方 cookie

Android：

```dart
await (WebViewCookieManager().platform as AndroidWebViewCookieManager)
    .setAcceptThirdPartyCookies(
  controller.platform as AndroidWebViewController,
  true,
);
```

OHOS：

```dart
await (WebViewCookieManager().platform as OhosWebViewCookieManager)
    .setAcceptThirdPartyCookies(
  controller.platform as OhosWebViewController,
  true,
);
```

## Web 限制

Web 实现使用 `document.cookie`：

- 不能读取 `HttpOnly` cookie。
- 不能管理无关域名 cookie。
- 不能绕过 `SameSite`、`Secure`、分区和浏览器隐私策略。
- `getCookies` 只接受与当前文档 scheme、host、path 完全一致的 URL；其他
  context 返回空列表。
- `document.cookie` 不提供原始 domain/path，因此返回项使用当前 host 和 `/`。
- `clearCookies` 会对可见父 domain/path 做尽力清理，只有至少一个可见 Cookie
  消失时才返回 `true`。


## 分类清理网站数据

```dart
final manager = WebViewDataManager(); // 会话内使用 session.dataManager。
final types = {WebViewDataType.cookies, WebViewDataType.cache};
final capabilities = await manager.getCapabilities();
final result = await manager.clearWebsiteData(dataTypes: types);
if (!result.isComplete) {
  debugPrint('${result.unsupportedDataTypes}: ${result.failures}');
}
```

只会处理请求的类别，不能独立清理的类别会标记为不支持，不会扩大删除范围。
`isComplete` 表示本次请求的全部类别都已成功清理；空集合不执行清理并返回成功。
`capabilities.canClear(types)` 可提前检查某种组合，`clearingGroups` 描述必须一起
请求的原生类别组。会话 manager 操作其对应的数据区。

iOS、macOS、Linux 支持单独清理全部列出的类别；Windows 支持 Cookie、磁盘缓存、
local storage、IndexedDB、WebSQL 和 Cache Storage，受 Runtime 版本限制。
Android、OHOS 可单独清理 Cookie 和可用的缓存；Android 新版 WebView 还支持
完整清理，但其他存储类别不能因此单独删除。OHOS 会话内不清理共享缓存。
Web 不支持任意网站数据清理。网页仍可继续写入数据，应用应先停止相关页面活动。

删除单个 Cookie 时应使用实际存储的 domain/path，保留 domain 的前导 `.`；不要用读取结果中的兼容占位值猜测其身份。Android、OHOS、Web 使用过期 Cookie 删除时会区分仅主机与域 Cookie，并保留安全前缀要求的标记。
