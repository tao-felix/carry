# Carry — website

The landing page for Carry. Static, single route (`/`), no server code, no data fetching. It only describes the product; it never sees data.

## Develop

```bash
pnpm install    # if the registry is unreachable: pnpm install --registry https://registry.npmmirror.com
pnpm dev        # http://localhost:4720
pnpm build      # production build; also type-checks. Needs no network.
pnpm start      # serve the production build on :4720
```

Stack: Next.js 15 (app router), React 19, Tailwind v4, `@vercel/analytics`.

Fonts (Instrument Serif, Inter, JetBrains Mono) are loaded with plain `<link>` tags in `src/app/layout.tsx`, not `next/font/google`, so the build never fetches anything. Each face has a local fallback stack in `src/app/globals.css`.

## Deploy

From this folder:

```bash
vercel --prod
```

## Where things live

- **All links, commands and numbers**: `src/lib/links.ts` (GitHub URL, App Store / TestFlight links, install command, Pro price, site URL, the agent snippets). Nothing else on the page hard-codes these.
- Page order and sections: `src/app/page.tsx` → `src/components/*` (Nav, Hero, ContextFile, HowItWorks, Sources, Privacy, Pro, ForAgents, Footer).
- Design tokens (paper/ink palette, dark mode via `prefers-color-scheme`, type scale, font stacks): `src/app/globals.css`, following `../docs/DESIGN.md`.
- The two-channel diagram: `src/components/ChannelsDiagram.tsx` (one wide SVG for `lg` and up, one tall SVG below).
- Sources grid content: `src/components/Sources.tsx`, mirrors `../docs/DATA-CONTRACT.md` §3.
- The example digest: `src/components/ContextFile.tsx`. Every value in it is invented.
- Favicon: `src/app/icon.svg` (the luggage-tag mark; `src/components/Mark.tsx` is the same shape inline).
