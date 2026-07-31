---
title: CI and Pages
description: How documentation is built and deployed to GitHub Pages.
---

The documentation site lives in `docs/` and uses Starlight with pnpm.

## Local Commands

```sh
cd docs
pnpm install
pnpm dev
pnpm build
```

The local preview path includes the base path:

```text
http://127.0.0.1:4321/webview_all
```

The Simplified Chinese documentation path is:

```text
http://127.0.0.1:4321/webview_all/zh/1.2
```

## GitHub Pages

The workflow file is `.github/workflows/docs.yml`. It runs on every push to `main` and on manual dispatch.

Build flow:

1. Checks out the repository.
2. Installs pnpm 10.19.0.
3. Installs Node 22 with pnpm caching enabled.
4. Runs `pnpm install --frozen-lockfile` in `docs/`.
5. Runs `pnpm build`.
6. Uploads `docs/dist`.
7. Deploys with GitHub Pages Actions.

## Production URL

Astro config:

```js
site: 'https://abandoft.github.io',
base: '/webview_all',
```

Deployed URL:

```text
https://abandoft.github.io/webview_all
```

Simplified Chinese URL:

```text
https://abandoft.github.io/webview_all/zh/1.2
```

In GitHub repository settings, Pages source must be set to `GitHub Actions`.
