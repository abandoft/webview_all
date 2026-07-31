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

## 平台差异

| 平台 | 存储 | 说明 |
| --- | --- | --- |
| Android | Android WebView `CookieManager` | 支持第三方 cookie 策略。 |
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
