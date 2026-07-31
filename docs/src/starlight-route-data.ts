import {
  defineRouteMiddleware,
  type StarlightRouteData,
} from '@astrojs/starlight/route-data';

type SidebarEntry = StarlightRouteData['sidebar'][number];
type SidebarLink = Extract<SidebarEntry, { type: 'link' }>;

const siteBase = '/webview_all';

function withoutTrailingSlash(path: string): string {
  return path === '/' ? path : path.replace(/\/+$/, '');
}

function version12Href(href: string, locale: string | undefined): string {
  const localeBase = `${siteBase}${locale ? `/${locale}` : ''}`;
  const normalizedHref = withoutTrailingSlash(href);
  if (normalizedHref === localeBase) {
    return `${localeBase}/1.2/`;
  }
  if (!normalizedHref.startsWith(`${localeBase}/`)) {
    return href;
  }
  return `${localeBase}/1.2/${normalizedHref.slice(localeBase.length + 1)}/`;
}

function version12Link(
  link: SidebarLink,
  locale: string | undefined,
  currentPath: string,
): SidebarLink {
  const href = version12Href(link.href, locale);
  return {
    ...link,
    href,
    isCurrent: withoutTrailingSlash(href) === currentPath,
  };
}

function version12SidebarEntry(
  entry: SidebarEntry,
  locale: string | undefined,
  currentPath: string,
): SidebarEntry {
  if (entry.type === 'link') {
    return version12Link(entry, locale, currentPath);
  }
  return {
    ...entry,
    entries: entry.entries.map((child) =>
      version12SidebarEntry(child, locale, currentPath),
    ),
  };
}

export const onRequest = defineRouteMiddleware(async (context, next) => {
  const route = context.locals.starlightRoute;
  const localeBase = `${siteBase}${route.locale ? `/${route.locale}` : ''}`;
  const currentPath = withoutTrailingSlash(context.url.pathname);
  const isVersion12 =
    currentPath === `${localeBase}/1.2` ||
    currentPath.startsWith(`${localeBase}/1.2/`);

  if (isVersion12) {
    route.siteTitleHref = `${localeBase}/1.2/`;
    route.sidebar = route.sidebar.map((entry) =>
      version12SidebarEntry(entry, route.locale, currentPath),
    );
    route.pagination = {
      prev: route.pagination.prev
        ? version12Link(route.pagination.prev, route.locale, currentPath)
        : undefined,
      next: route.pagination.next
        ? version12Link(route.pagination.next, route.locale, currentPath)
        : undefined,
    };
  }

  await next();
});
