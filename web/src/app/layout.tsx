import type { Metadata, Viewport } from "next";
import { Analytics } from "@vercel/analytics/next";
import { links } from "@/lib/links";
import "./globals.css";

/**
 * Fonts are loaded with plain <link> tags rather than next/font/google so the
 * build never touches the network. globals.css carries the fallback stacks.
 */
const fontsHref =
  "https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap";

const title = "Carry — Everything your phone knows, on your agent's desk";
const description =
  "Carry puts what your phone knows in front of desktop agents like Claude Code, Codex and Cursor. No Carry server: your iCloud carries it, your Mac reads it. Open source, MIT.";

export const metadata: Metadata = {
  metadataBase: new URL(links.siteUrl),
  title,
  description,
  alternates: { canonical: "/" },
  openGraph: {
    type: "website",
    url: links.siteUrl,
    siteName: "Carry",
    title,
    description,
    locale: "en_US",
  },
  twitter: {
    card: "summary",
    title,
    description,
  },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  colorScheme: "light dark",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#F6F1E9" },
    { media: "(prefers-color-scheme: dark)", color: "#141310" },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin="anonymous"
        />
        <link href={fontsHref} rel="stylesheet" />
      </head>
      <body className="min-h-dvh bg-paper text-ink font-sans">
        {children}
        <Analytics />
      </body>
    </html>
  );
}
