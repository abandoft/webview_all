---
title: CI 和 Pages
description: 文档如何构建并部署到 GitHub Pages。
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
http://127.0.0.1:4321/webview_all/zh/1.2
```

## GitHub Pages

workflow 文件是 `.github/workflows/docs.yml`。它在 push 到 `main` 和手动触发时运行。

构建流程：

1. checkout 代码。
2. 安装 pnpm 10.19.0。
3. 安装 Node 22，并启用 pnpm cache。
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
https://abandoft.github.io/webview_all/zh/1.2
```

GitHub 仓库设置中 Pages source 需要选择 `GitHub Actions`。
