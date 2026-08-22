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
| `setCookie` | 设置 name/value/domain/path。 |
| `getCookies` | 返回指定域名可见的 cookie。 |
| `clearCookies` | 清空 cookie，并在平台可报告时返回清空前是否存在 cookie。 |

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

该 manager 操作普通 WebView 共用的默认持久化数据区，按平台能力清理 Cookie、缓存、local/session storage、IndexedDB、WebSQL、Cache Storage 和 service worker，并明确返回每类数据是已清理、不支持还是失败。注销流程必须检查 `isComplete`，不能把部分成功当成完整清理。密码、自动填充、下载记录、浏览记录和引擎设置不在该接口范围内。

Windows 会为该操作创建临时 controller，因此可能同时初始化共享 WebView2
环境。需要自定义环境参数时，通过
`WindowsWebViewDataManagerCreationParams` 构造 manager；相同配置会复用已有
环境，配置冲突则明确失败。

| 平台 | 行为 |
| --- | --- |
| Android | 系统 WebView 支持时使用 AndroidX WebKit 的完整清理接口；旧版本清理 Cookie、缓存、local storage 和 WebSQL，其余类型标记为不支持。 |
| iOS/macOS | 清理 `WKWebsiteDataStore.default()` 中的对应数据类型。 |
| Windows | 清理 WebView2 暴露的 Cookie、DOM storage 类型和磁盘缓存；session storage 与 service worker 注册标记为不支持，旧 Runtime 没有 profile 清理接口时全部标记为不支持。 |
| Linux | 清理默认 WebKitGTK context 的全部网站数据。 |
| OHOS | 清理 Cookie，以及 ArkWeb 暴露的 local/session storage 和 WebSQL；其余类型标记为不支持。 |
| Web | 全部标记为不支持，因为宿主页无权清理任意 iframe origin 或 `HttpOnly` Cookie。 |

## 平台差异

| 平台 | 存储 | 说明 |
| --- | --- | --- |
| Android | Android WebView `CookieManager` | 保留编码 name/value 和值中的 `=`，支持第三方 cookie 策略。 |
| iOS/macOS | `WKWebsiteDataStore.defaultDataStore` | 按 domain matching 过滤。 |
| Windows | WebView2 cookie manager | 提供扩展元数据。 |
| Linux | WebKitGTK cookie bridge | 支持通用字段。 |
| OHOS | ArkWeb `CookieManager` | 支持第三方 cookie 策略。 |
| Web | `document.cookie` | 只能访问宿主页可见 cookie。 |

## Windows 完整 cookie

```dart
final manager = WebViewCookieManager().platform
    as WindowsWebViewCookieManager;

await manager.setWindowsCookie(
  WindowsWebViewCookie(
    name: 'session',
    value: 'abc',
    domain: 'example.com',
    path: '/',
    isHttpOnly: true,
    isSecure: true,
    sameSite: WindowsWebViewCookieSameSite.lax,
  ),
);
```

Windows 还支持按完整 cookie、name+url、name+domain+path 删除。

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
