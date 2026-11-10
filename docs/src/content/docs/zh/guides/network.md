---
title: 网络控制
description: 原生内容规则、HTTP 请求决策与预声明的自定义协议。
---

## 查询原生能力

`getNetworkCapabilities()` 分别报告各项原生能力。不支持的设置会打印原因并返回
`false`，应用继续运行。该接口不注入 fetch/XHR hook，也不会通过 Dart 重新发送允许的请求。

| 能力 | Android | iOS / macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- |
| 静态阻止／允许规则 | 仅 URL | 原生资源类型 | 原生资源类型 | 原生资源类型 | 仅 URL | 不支持 |
| HTTP(S) 允许／阻止／响应 | WebView 有限拦截 | 不支持 | WebView2 拦截 | 不支持 | 不支持 | 不支持 |
| HTTP 请求体 | 无法读取 | — | 可克隆且有大小限制 | — | — | — |
| 预声明自定义协议 | 支持 | 非引擎内置协议 | 创建环境时注册 | WebKit context 注册 | WebEngine 初始化前注册 | 不支持 |
| 自定义协议请求体 | 无法读取 | 原生可读取的请求体 | 可克隆且有大小限制 | WebKitGTK 2.40+ | 非分块且有大小限制 | — |
| 增量响应 | 支持 | 支持 | 仅文件／字节 | 支持 | 支持 | — |

原生引擎对重定向、worker 请求及资源分类的覆盖不同。检查 `resourceTypes`、
`requestBodies`、`customSchemeRequestBodies` 和 `limitation`。
请求体超过 4 MiB 或无法读取原生流时，`bodyAvailable` 为 `false`、`body` 为 `null`，
不能据此判断原请求体为空。原生无法可靠识别主 frame 时，`isForMainFrame` 为 `null`。
不能将这些代理当作覆盖浏览器所有请求的防火墙。

Android 可导航到自定义协议页面，但 Chromium 会在原生拦截前拒绝该协议的 fetch/XHR。检查 `customSchemeFetch`；JavaScript 需要 fetch 本地数据时，使用插件资源 URL。

## 静态规则

```dart
await controller.setContentRules([
  WebViewContentRule(urlPattern: 'https://ads.example/*'),
  WebViewContentRule(
    urlPattern: 'https://ads.example/required.js',
    action: WebViewContentRuleAction.allow,
  ),
]);
await controller.setContentRules([]); // 移除该 controller 的规则。
```

匹配完整 URL，`*` 表示任意长度字符，默认忽略大小写，最后一条匹配规则生效。
最多接受 256 条规则。`resourceTypes` 可选，指定不支持的资源类型会拒绝更新，
不会扩大匹配范围；编译失败保留旧规则。规则先于资源代理执行，`allow` 仍允许
后续代理处理请求，不会绕过浏览器安全策略或应用的其他规则。

## HTTP 请求决策

```dart
await controller.setRequestDelegate(WebViewRequestDelegate(
  urlPatterns: ['https://example.com/api/*'],
  onRequest: (request) async {
    if (request.uri.path.endsWith('/blocked')) {
      return const WebViewRequestDecision.block();
    }
    return const WebViewRequestDecision.allow();
  },
));
await controller.setRequestDelegate(null);
```

使用 `WebViewRequestDecision.respond(WebViewResourceResponse.bytes(...))` 提供响应。
允许时继续原生请求，保留请求体、Cookie 和请求头，不会另发一次 HTTP 请求。
Android 回调不能读取 POST 请求体，也不覆盖所有重定向或 worker 请求。
Apple 没有通用 HTTP 拦截的公开接口；Linux/OHOS 无法在认领异步请求后安全地恢复原请求，
因此不提供该代理。替换或移除代理会取消其待处理决策，晚到的 `allow` 不会重发已取消的请求。
原生请求有超时限制，应及时完成决策。

## 自定义协议

在**创建第一个原生环境之前**声明协议，再为 controller 设置代理。声明属于创建参数：

```dart
final controller = WebViewController.fromPlatformCreationParams(
  const PlatformWebViewControllerCreationParams(customSchemes: ['appdata']),
);
await controller.setCustomSchemeDelegate(WebViewResourceDelegate(
  onRequest: (request) => WebViewResourceResponse.bytes(
    Uint8List.fromList(utf8.encode('<h1>本地页面</h1>')),
    mimeType: 'text/html',
  ),
));
await controller.loadRequest(Uri.parse('appdata://assets/index.html'));
```

示例需导入 `dart:convert` 和 `dart:typed_data`。协议名使用小写 ASCII 字符，不能替换引擎保留协议。
Windows 需要 `scheme://host/path` 格式，并复用进程已有环境，环境启动后不能再增加协议。
OHOS 每个进程最多注册 10 个协议，且必须在 WebEngine 启动前完成；其他配置最多声明 16 个。
注册失败会打印说明，不会阻止普通网页加载。

协议不会被标记为安全或本地协议，也不会绕过 CSP、CORS。跨域使用时提供合适的响应头，
浏览器 fetch 限制仍然生效。即使原生注册属于引擎或 context，代理仍按 controller 区分，
移除某个页面的代理不会移除其他页面的处理器。不需要任意协议名时，优先使用
`setResourceDelegate` / `getResourceUri` 提供的应用资源 URL，二者相互独立。

响应复用应用资源的文件、字节、流和 Range 处理，Windows 仅支持文件及字节响应。
页面或代理关闭时会传递流取消，应用应在收到取消后释放自己的数据生产资源。

## 按站点生效的条件与原生动作

Apple、Linux 还支持 `ifDomains`、`unlessDomains`、`ifTopUrls`、`unlessTopUrls` 和
`loadTypes`（`firstParty`／`thirdParty`）。域名使用小写 ASCII，前缀 `*` 包含子域名；每条
规则至多使用一组域名或顶层 URL 条件。顶层 URL 沿用 `urlPattern` 的通配符语法，匹配主文档。

`hideElements` 通过 `selector: '.advertisement'` 使用原生 CSS 隐藏元素，
`upgradeToHttps` 使用内核的 HTTPS 升级规则。这些动作可能累积，`allow` 会忽略此前匹配的
规则。CSS 语法和 HTTPS／端口限制以原生内核为准，WebKit 可能忽略无效 CSS 选择器。
先查询 `ruleActions`、`ruleConditions`；不支持的组合会整组拒绝并保留旧规则，
不会忽略条件后改为更宽泛的 URL 规则。
