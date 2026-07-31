import { defineCollection } from 'astro:content';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({
    loader: docsLoader({
      // Astro's default GitHub-style slugger removes dots from path segments
      // (`1.2` becomes `12`). Documentation versions are public URL
      // contracts, so preserve the source path verbatim.
      generateId: ({ entry }) =>
        entry
          .replace(/\.(?:markdown|mdown|mkdn|mkd|mdwn|md|mdx)$/, '')
          .replace(/\\/g, '/')
          .replace(/\/index$/, ''),
    }),
    schema: docsSchema(),
  }),
};
