## 各插件包的信息同步

1. webview_all目录里的中英文README需要同步覆盖到根目录
2. webview_all目录里的中英文CHANGELOG需要同步覆盖到各个子插件
3. 也就是说只在主插件目录里维护一份即可

## 与官方插件包的同步

webview_all的主插件、interface、android、iOS/macOS、web插件都源自于官方插件（且需要兼容官方插件）。因此需要记录当前同步到了官方的哪个pub版本，以及该版本的更新时间。

是否同步相关内容需要手动确认，比如依赖的版本更新、最低支持Flutter版本的更新、不兼容的变更等

### 官方插件同步记录

| 本仓库插件 | 官方插件 | 已同步至官方 pub 版本 | 官方版本发布时间（UTC+8） |
| --- | --- | --- | --- |
| `webview_all` | `webview_flutter` | `4.14.1` | `2026-07-08 01:29:37` |
| `webview_platform_interface` | `webview_flutter_platform_interface` | `2.15.1` | `2026-03-26 03:24:16` |
| `webview_all_android` | `webview_flutter_android` | `4.12.0` | `2026-04-30 02:05:25` |
| `webview_all_wkwebview` | `webview_flutter_wkwebview` | `3.25.0` | `2026-04-30 02:05:37` |
| `webview_all_web` | `webview_flutter_web` | `0.2.3+4` | `2024-11-13 05:49:07` |

表中的时间为对应官方版本在 pub.dev 的发布时间。fork 后由本仓库自行增加的功能和修复不改变上表记录的官方同步基线。
