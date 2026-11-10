export const docsVersions = ['latest', '1.4.x', '1.2.x'] as const;
export type DocsVersion = (typeof docsVersions)[number];

export function documentId(locale: string | undefined, version: DocsVersion, slug = '') {
  return [locale, version === 'latest' ? '' : version, slug].filter(Boolean).join('/');
}

export function documentHref(base: string, locale: string | undefined, version: DocsVersion, slug = '') {
  const id = documentId(locale, version, slug);
  return `${base}${id ? `/${id}` : ''}/`;
}

export function documentationPath(pathname: string, base: string) {
  const relative = pathname === base ? '' : pathname.slice(base.length);
  const parts = relative.split('/').filter(Boolean);
  const locale = parts[0] === 'zh' ? parts.shift() : undefined;
  const version: DocsVersion = parts[0] === '1.4.x' || parts[0] === '1.2.x'
    ? parts.shift() as DocsVersion : 'latest';
  return { locale, version, slug: parts.join('/') };
}

export function normalizedDocumentId(id: string) {
  return id === 'index' ? '' : id.replace(/\/index$/, '');
}
