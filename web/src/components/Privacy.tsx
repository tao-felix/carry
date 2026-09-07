import { links } from "@/lib/links";
import { Section } from "./Section";

const rows = [
  {
    k: "Read",
    v: <>the sources you switched on.</>,
  },
  {
    k: "Goes to",
    v: (
      <>
        your iCloud Drive (folder <code>Carry</code>), then your Mac.
      </>
    ),
  },
  {
    k: "Seen by",
    v: (
      <>
        the agents you point at <code>{links.contextDir}</code>. Nobody else. There is no Carry server.
      </>
    ),
  },
];

export function Privacy() {
  return (
    <Section id="privacy" number="04" title="What is read, where it goes, who sees it">
      <dl className="prose-code overflow-hidden rounded-card border border-line">
        {rows.map((r, i) => (
          <div
            key={r.k}
            className={`grid gap-1 px-5 py-5 sm:grid-cols-[160px_1fr] sm:gap-6 sm:px-8 sm:py-6 ${
              i > 0 ? "border-t border-line" : ""
            }`}
          >
            <dt className="font-serif text-[24px] leading-[30px] text-ink">{r.k}</dt>
            <dd className="text-body text-ink sm:text-[19px] sm:leading-[30px]">{r.v}</dd>
          </div>
        ))}
      </dl>
      <p className="mt-6 flex max-w-[760px] items-start gap-3 text-[15px] leading-[23px] text-ink2">
        <span className="mt-[9px] h-1.5 w-1.5 shrink-0 rounded-full bg-warn" aria-hidden="true" />
        <span>
          One honest limit: Apple only lets apps read Health while the phone is unlocked, so Health syncs roughly
          hourly, not live.
        </span>
      </p>
    </Section>
  );
}
