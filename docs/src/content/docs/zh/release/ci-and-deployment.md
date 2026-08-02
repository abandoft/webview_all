---
title: CI 和 Pages
description: 代码如何验证，以及文档如何部署到 GitHub Pages。
---

文档站点位于 `docs/`，使用 Starlight 和 pnpm。

## 本地命令

```sh
cd docs
pnpm install
pnpm dev
pnpm build
```

本地预览路径包含 base path：

```text
http://127.0.0.1:4321/webview_all
```

中文文档路径：

```text
http://127.0.0.1:4321/webview_all/zh
```

## 代码 CI

`.github/workflows/ci.yml` 会在 pull request、push 到 `main` 和手动触发时
运行。OHOS 需要独立 Flutter toolchain，因此有意不纳入该 workflow。

workflow 会：

- 在最低 Flutter 3.35.7 和当前 3.44 stable 上分析、测试所有非 OHOS Dart 包
  及两个示例应用；
- 在 Chrome 运行 Web 测试并构建 Web 示例；
- 在两条 Flutter 版本线上运行 Android native unit test 并构建 APK；
- 在两条 Flutter 版本线上编译 iOS、macOS 示例，并在最低版本线上编译
  Linux、Windows 示例，从而在对应 runner 验证 native 插件代码。

## GitHub Pages

workflow 文件是 `.github/workflows/docs.yml`。只有 `docs/` 下文件发生变化并
push 到 `main` 时才会自动运行，也可以手动触发。

构建流程：

1. checkout 代码。
2. 安装 pnpm 10.19.0。
3. 安装 Node 24，并启用 pnpm cache。
4. 在 `docs/` 执行 `pnpm install --frozen-lockfile`。
5. 执行 `pnpm build`。
6. 上传 `docs/dist`。
7. 使用 GitHub Pages Actions 部署。

## 线上地址

Astro 配置：

```js
site: 'https://abandoft.github.io',
base: '/webview_all',
```

部署后地址：

```text
https://abandoft.github.io/webview_all
```

中文地址：

```text
https://abandoft.github.io/webview_all/zh
```

GitHub 仓库设置中 Pages source 需要选择 `GitHub Actions`。
