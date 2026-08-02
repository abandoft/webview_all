## 各插件包的信息同步

1. webview_all目录里的中英文README需要同步覆盖到根目录
2. webview_all目录里的中英文CHANGELOG需要同步覆盖到各个子插件
3. 也就是说只在主插件目录里维护一份即可

## 与官方插件包的同步

webview_all的主插件、interface、android、iOS/macOS、web插件都源自于官方插件（且需要兼容官方插件）。因此需要记录当前同步到了官方的哪个pub版本，以及该版本的更新时间。

是否同步相关内容需要手动确认，比如依赖的版本更新、最低支持Flutter版本的更新、不兼容的变更等

### 官方插件同步记录

| 本仓库插件 | 官方插件 | 兼容性对齐至官方 pub 版本 | 官方版本发布时间（UTC+8） | 已审查至 |
| --- | --- | --- | --- | --- |
| `webview_all` | `webview_flutter` | `4.14.1` | `2026-07-08 01:29:37` | `4.14.1` |
| `webview_platform_interface` | `webview_flutter_platform_interface` | `2.15.1` | `2026-03-26 03:24:16` | `2.15.1` |
| `webview_all_android` | `webview_flutter_android` | `4.13.0` | `2026-06-05 01:07:52` | `4.13.0` |
| `webview_all_wkwebview` | `webview_flutter_wkwebview` | `3.26.0` | `2026-06-05 01:08:05` | `3.26.0` |
| `webview_all_web` | `webview_flutter_web` | `0.2.3+4` | `2024-11-13 05:49:07` | `0.2.3+4` |

表中的时间为“兼容性对齐至”版本在 pub.dev 的发布时间。“兼容性对齐”表示在不提高本仓库 Flutter 3.35 / Dart 3.9 最低版本的前提下，已迁移能够安全落地的上游行为和 API；它不代表照搬上游的新最低版本或构建工具。

- Android 已对齐 4.13.0 的原生 `WebView` binding 访问入口、AndroidX annotation 更新、private API lint 标注和 Built-in Kotlin 构建结构。binding 入口通过 Flutter 3.35 已有的 engine plugin registry 实现；构建脚本按官方兼容方案在 AGP 8 及以下应用 Kotlin Gradle Plugin，在 AGP 9 及以上使用 Built-in Kotlin，最低版本保持不变。
- WKWebView 已对齐 3.26.0 的应用、scene 和 engine 生命周期清理，以及 iOS registrar 原生 `WKWebView` 访问入口。插件通过公开协议和 selector 的运行时能力检测，在 Flutter 3.38+ 注册 scene delegate，在 Flutter 3.44+ 使用 registrar 官方查询接口；Flutter 3.35–3.43 使用按 engine 隔离的弱引用兼容查询，最低版本保持不变。

fork 后由本仓库自行增加的功能和修复不改变上表记录的官方同步基线。
