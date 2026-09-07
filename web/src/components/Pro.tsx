import { links } from "@/lib/links";
import { Section } from "./Section";

const pro = [
  "Screenshot and photo OCR",
  "Voice memo and audio transcription",
];

const free = [
  "All twelve sources",
  "The daily digest and week.md",
  "MCP server",
  "CLI: today, recent, status",
  "Full-text search",
  "The source code, MIT",
];

function Check({ tone }: { tone: "tangerine" | "moss" }) {
  return (
    <svg
      viewBox="0 0 16 16"
      width="14"
      height="14"
      aria-hidden="true"
      fill="none"
      className={`mt-[6px] shrink-0 ${tone === "tangerine" ? "stroke-tangerine" : "stroke-moss"}`}
      strokeWidth="1.75"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M3 8.5l3 3 7-7" />
    </svg>
  );
}

export function Pro() {
  return (
    <Section
      id="pro"
      number="05"
      title={
        <>
          <span className="italic">Pro</span>
        </>
      }
      lede="Pro turns pictures and audio into text your agent can read."
    >
      <div className="grid overflow-hidden rounded-card border border-line md:grid-cols-2">
        <div className="p-6 sm:p-8">
          <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
            <h3 className="font-serif text-[28px] leading-[32px] text-ink">
              Carry <span className="italic">Pro</span>
            </h3>
            <p className="font-mono text-mono text-ink">{links.proPrice}</p>
          </div>
          <p className="mt-2 font-mono text-mono-sm text-ink2">One plan. No tiers.</p>
          <ul className="mt-6 grid gap-3">
            {pro.map((t) => (
              <li key={t} className="flex gap-3 text-body text-ink">
                <Check tone="tangerine" />
                {t}
              </li>
            ))}
          </ul>
          <a
            href={links.appStore}
            className="mt-8 inline-flex h-11 items-center justify-center rounded-card border border-ink px-5 text-[15px] font-medium text-ink transition-colors duration-150 hover:bg-ink hover:text-paper"
          >
            Subscribe in the iPhone app
          </a>
          <p className="mt-3 font-mono text-mono-sm text-ink2">
            Your Mac verifies the receipt offline. Cancel any time.
          </p>
        </div>

        <div className="border-t border-line bg-paper2 p-6 sm:p-8 md:border-t-0 md:border-l">
          <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
            <h3 className="font-serif text-[28px] leading-[32px] text-ink">Free, forever</h3>
            <p className="font-mono text-mono text-ink">$0</p>
          </div>
          <p className="mt-2 font-mono text-mono-sm text-ink2">Everything else.</p>
          <ul className="mt-6 grid gap-3">
            {free.map((t) => (
              <li key={t} className="flex gap-3 text-body text-ink">
                <Check tone="moss" />
                {t}
              </li>
            ))}
          </ul>
        </div>
      </div>
      <p className="mt-6 font-mono text-mono text-ink2">
        Runs on your Mac. Nothing is uploaded to us. <span className="text-ink">There is no us.</span>
      </p>
    </Section>
  );
}
