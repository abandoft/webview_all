---
title: CI and Pages
description: How code is validated and documentation is deployed to GitHub Pages.
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
http://127.0.0.1:4321/webview_all/zh
```

## Code CI

`.github/workflows/ci.yml` runs for pull requests, pushes to `main`, and manual
dispatch. It intentionally excludes OHOS because that platform requires its
separate Flutter toolchain.

The workflow:

- analyzes and tests every non-OHOS Dart package on the minimum Flutter 3.35.7
  line and the current 3.44 stable line, including both example applications;
- runs web tests in Chrome and builds the web example;
- runs Android native unit tests and builds an APK on both supported Flutter
  lines;
- compiles the iOS and macOS examples on both supported Flutter lines, and
  compiles the Linux and Windows examples on the minimum line, so native plugin
  code is validated on its host OS.

## GitHub Pages

The workflow file is `.github/workflows/docs.yml`. It runs on a push to `main`
only when a file under `docs/` changes, or by manual dispatch.

Build flow:

1. Checks out the repository.
2. Installs pnpm 10.19.0.
3. Installs Node 24 with pnpm caching enabled.
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
https://abandoft.github.io/webview_all/zh
```

In GitHub repository settings, Pages source must be set to `GitHub Actions`.
