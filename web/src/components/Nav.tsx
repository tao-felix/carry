import { links } from "@/lib/links";
import { Container } from "./Section";
import { Mark } from "./Mark";

const items = [
  { href: "#how", label: "How it works" },
  { href: "#sources", label: "Sources" },
  { href: "#pro", label: "Pro" },
  { href: "#agents", label: "For agents" },
];

export function Nav() {
  return (
    <nav className="sticky top-0 z-20 border-b border-line bg-paper">
      <Container className="flex h-14 items-center justify-between">
        <a
          href="#top"
          className="flex items-center gap-2 font-serif text-[24px] leading-none text-ink"
          aria-label="Carry, back to top"
        >
          <Mark size={18} />
          Carry
        </a>
        <div className="flex items-center gap-5 text-small sm:gap-7">
          {items.map((it) => (
            <a
              key={it.href}
              href={it.href}
              className="hidden text-ink2 transition-colors duration-150 hover:text-ink md:inline"
            >
              {it.label}
            </a>
          ))}
          <a
            href={links.github}
            target="_blank"
            rel="noreferrer"
            className="inline-flex items-center gap-1.5 text-ink transition-colors duration-150 hover:text-tangerine"
          >
            GitHub
            <svg viewBox="0 0 16 16" width="11" height="11" aria-hidden="true" fill="none" className="stroke-current" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M4 12L12 4M6 4h6v6" />
            </svg>
          </a>
        </div>
      </Container>
    </nav>
  );
}
