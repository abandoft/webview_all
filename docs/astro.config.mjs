import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

export default defineConfig({
  site: 'https://abandoft.github.io',
  base: '/webview_all',
  integrations: [
    starlight({
      title: 'WebView All',
      description:
        'Commercial-grade Flutter WebView documentation for Android, iOS, macOS, Windows, Linux, OHOS, and web.',
      locales: {
        root: {
          label: 'English',
          lang: 'en',
        },
        zh: {
          label: '简体中文',
          lang: 'zh-CN',
        },
      },
      defaultLocale: 'root',
      logo: {
        src: './src/assets/logo.svg',
        alt: 'WebView All',
      },
      customCss: ['./src/styles/custom.css'],
      components: {
        Header: './src/components/Header.astro',
      },
      routeMiddleware: './src/starlight-route-data.ts',
      editLink: {
        baseUrl: 'https://github.com/abandoft/webview_all/edit/main/docs/',
      },
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/abandoft/webview_all',
        },
      ],
      sidebar: [
        {
          label: 'Start',
          translations: { 'zh-CN': '开始' },
          items: [
            { label: 'Overview', translations: { 'zh-CN': '概览' }, slug: '' },
            {
              label: 'Installation',
              translations: { 'zh-CN': '安装' },
              slug: 'getting-started/installation',
            },
            {
              label: 'Quick Start',
              translations: { 'zh-CN': '快速开始' },
              slug: 'getting-started/quick-start',
            },
            {
              label: 'Platform Setup',
              translations: { 'zh-CN': '平台设置' },
              slug: 'getting-started/platform-setup',
            },
            {
              label: 'Migration',
              translations: { 'zh-CN': '迁移' },
              slug: 'getting-started/migration',
            },
          ],
        },
        {
          label: 'Guides',
          translations: { 'zh-CN': '指南' },
          items: [
            {
              label: 'Controller',
              translations: { 'zh-CN': '控制器' },
              slug: 'guides/controller',
            },
            {
              label: 'Navigation',
              translations: { 'zh-CN': '导航' },
              slug: 'guides/navigation',
            },
            {
              label: 'Cookies',
              translations: { 'zh-CN': 'Cookie' },
              slug: 'guides/cookies',
            },
            {
              label: 'JavaScript',
              translations: { 'zh-CN': 'JavaScript' },
              slug: 'guides/javascript',
            },
            {
              label: 'Permissions',
              translations: { 'zh-CN': '权限' },
              slug: 'guides/permissions',
            },
            {
              label: 'Files, Assets, HTML',
              translations: { 'zh-CN': '文件、Asset 和 HTML' },
              slug: 'guides/files-assets-html',
            },
            {
              label: 'Debugging',
              translations: { 'zh-CN': '调试' },
              slug: 'guides/debugging',
            },
            {
              label: 'Security',
              translations: { 'zh-CN': '安全' },
              slug: 'guides/security',
            },
          ],
        },
        {
          label: 'Platforms',
          translations: { 'zh-CN': '平台' },
          items: [
            {
              label: 'Capability Matrix',
              translations: { 'zh-CN': '能力矩阵' },
              slug: 'platforms/capability-matrix',
            },
            {
              label: 'Android',
              translations: { 'zh-CN': 'Android' },
              slug: 'platforms/android',
            },
            {
              label: 'iOS and macOS',
              translations: { 'zh-CN': 'iOS 和 macOS' },
              slug: 'platforms/ios-macos',
            },
            {
              label: 'Windows',
              translations: { 'zh-CN': 'Windows' },
              slug: 'platforms/windows',
            },
            {
              label: 'Linux',
              translations: { 'zh-CN': 'Linux' },
              slug: 'platforms/linux',
            },
            {
              label: 'OHOS',
              translations: { 'zh-CN': 'OHOS' },
              slug: 'platforms/ohos',
            },
            { label: 'Web', translations: { 'zh-CN': 'Web' }, slug: 'platforms/web' },
          ],
        },
        {
          label: 'Reference',
          translations: { 'zh-CN': '参考' },
          items: [
            {
              label: 'Common API',
              translations: { 'zh-CN': '通用接口' },
              slug: 'reference/common-api',
            },
            {
              label: 'Platform API',
              translations: { 'zh-CN': '平台专属接口' },
              slug: 'reference/platform-specific-api',
            },
            {
              label: 'Errors and Limits',
              translations: { 'zh-CN': '错误与限制' },
              slug: 'reference/errors-and-limits',
            },
          ],
        },
      ],
    }),
  ],
});
