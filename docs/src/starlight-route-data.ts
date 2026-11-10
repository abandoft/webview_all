import { getCollection } from 'astro:content';
import { defineRouteMiddleware, type StarlightRouteData } from '@astrojs/starlight/route-data';
import { documentationPath, documentHref, documentId, normalizedDocumentId } from './versions';

type SidebarEntry = StarlightRouteData['sidebar'][number];
type SidebarLink = Extract<SidebarEntry, { type: 'link' }>;
const siteBase = '/webview_all';
const normalized = (path: string) => path.replace(/\/+$/, '') || '/';

export const onRequest = defineRouteMiddleware(async (context, next) => {
  const route = context.locals.starlightRoute;
  const current = normalized(context.url.pathname);
  const { locale, version } = documentationPath(context.url.pathname, siteBase);
  if (version !== 'latest') {
    const pages = new Set((await getCollection('docs')).map((entry) => normalizedDocumentId(entry.id)));
    function entryForVersion(entry: SidebarEntry): SidebarEntry | undefined {
      if (entry.type === 'link') {
        if (!entry.href.startsWith(`${siteBase}/`) && normalized(entry.href) !== siteBase) return entry;
        const { slug } = documentationPath(entry.href, siteBase);
        if (!pages.has(documentId(locale, version, slug))) return undefined;
        const href = documentHref(siteBase, locale, version, slug);
        return { ...entry, href, isCurrent: normalized(href) === current };
      }
      const entries = entry.entries.map(entryForVersion).filter((child): child is SidebarEntry => child !== undefined);
      return entries.length ? { ...entry, entries } : undefined;
    }
    route.siteTitleHref = documentHref(siteBase, locale, version);
    route.sidebar = route.sidebar.map(entryForVersion).filter((entry): entry is SidebarEntry => entry !== undefined);
    const flatten = (entries: SidebarEntry[]): SidebarLink[] => entries.flatMap(
      (entry) => entry.type === 'link' ? [entry] : flatten(entry.entries),
    );
    const links = flatten(route.sidebar);
    const index = links.findIndex((link) => link.isCurrent);
    route.pagination = {
      prev: index > 0 ? links[index - 1] : undefined,
      next: index >= 0 ? links[index + 1] : undefined,
    };
  }
  await next();
});
