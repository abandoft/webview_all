---
title: 能力矩阵
description: webview_all 1.2.1 的跨平台能力覆盖。
---

标记说明：

| 标记 | 含义 |
| --- | --- |
| 完整 | 由平台引擎或强类型桥完整实现。 |
| 有限制 | 已实现，但有明确浏览器、系统或引擎限制。 |
| 不支持 | 当前不可用，通常会抛错或按文档 no-op。 |

## 核心能力

| 能力 | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `WebViewWidget` | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 |
| `loadRequest` GET | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 |
| GET headers | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 有限制，CORS/fetch |
| POST body | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 有限制，CORS/fetch |
| POST 自定义 headers | 不支持 | 完整 | 完整 | 完整 | 完整 | 不支持 | 有限制，CORS/fetch |
| `loadFile` | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 不支持 |
| `loadFlutterAsset` | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 |
| `loadHtmlString` | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 |
| 历史前进/后退 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 有限制，controller 维护逻辑历史 |

## 导航和错误

| 能力 | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `onNavigationRequest` | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 有限制 |
| 页面开始/完成 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | iframe load 限制 |
| 进度 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 合成 0/100 |
| URL 变化 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 逻辑 URL |
| 资源错误 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | fetch 失败可见 |
| HTTP 错误 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | fetch-backed load 可见 |
| HTTP auth | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 浏览器 iframe 不暴露 |
| SSL auth | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 浏览器 iframe 不暴露 |

## JavaScript、UI 和权限

| 能力 | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| JS 开关 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | iframe sandbox |
| 执行 JS | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 同源限制 |
| JS 返回值 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 同源且需可序列化 |
| JS channel | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 同源限制 |
| Console | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 同源 hook |
| JS dialog | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 同源，confirm/prompt 需同步 |
| 权限请求 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 同源媒体 hook + 浏览器提示 |
| 文件选择 | 完整 | 无通用回调 | 无通用回调 | 无通用回调 | 无通用回调 | 完整 | 浏览器接管 |
| 定位提示 | 完整 | 无平台 API | 无平台 API | 引擎/浏览器接管 | 引擎/浏览器接管 | 完整 | 浏览器接管 |

## 视图状态

| 能力 | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 标题 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 同源限制 |
| 滚动位置 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 同源限制 |
| 滚动条 | 完整 | 完整 | 完整 | CSS 实现 | 完整 | CSS 实现 | CSS 实现 |
| 背景色 | 完整 | 完整 | 有限制 | 完整 | 完整 | 完整 | iframe CSS |
| 缩放 | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | touch-action 限制 |
| UA override | 完整 | 完整 | 完整 | 完整 | 完整 | 完整 | 非空 override 不支持 |
| Overscroll | 完整 | 有限制 | 有限制 | CSS 实现 | 完整 | CSS 实现 | iframe CSS |
