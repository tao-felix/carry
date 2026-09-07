import { links } from "@/lib/links";
import { Container } from "./Section";
import { Mark } from "./Mark";

export function Footer() {
  return (
    <footer className="border-t border-line py-10 sm:py-12">
      <Container className="flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex items-center gap-2 font-serif text-[22px] leading-none text-ink">
          <Mark size={16} />
          Carry
        </div>
        <ul className="flex flex-wrap items-center gap-x-5 gap-y-2 font-mono text-mono-sm text-ink2">
          <li>MIT</li>
          <li>
            <a href={links.github} target="_blank" rel="noreferrer" className="transition-colors duration-150 hover:text-ink">
              GitHub
            </a>
          </li>
          <li>Made by Tao Fangbo</li>
          <li className="text-ink">Mac + iPhone today. Android next.</li>
        </ul>
      </Container>
    </footer>
  );
}
