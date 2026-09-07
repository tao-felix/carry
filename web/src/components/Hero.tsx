import { links } from "@/lib/links";
import { Container } from "./Section";
import { CopyButton } from "./CopyButton";

/* The three questions every Carry surface must answer without scrolling. */
const answers = [
  { k: "Read", v: <>the sources you switch on, on your phone.</> },
  { k: "Goes to", v: <>your iCloud Drive, then your Mac. Nowhere else.</> },
  {
    k: "Seen by",
    v: (
      <>
        the agents you point at <code>~/.carry/context/</code>. Nobody else.
      </>
    ),
  },
];

export function Hero() {
  const install = `${links.cliInstall}\n${links.cliInit}`;

  return (
    <header id="top" className="pt-14 pb-12 sm:pt-24 sm:pb-16">
      <Container>
        <p className="mb-6 font-mono text-mono-sm text-ink2 sm:mb-8">
          Mac + iPhone · Open source, MIT · v0.1
        </p>
        <h1 className="max-w-[820px] font-serif text-display-sm sm:text-display">
          Everything your phone knows, on your agent&rsquo;s desk.
        </h1>
        <p className="mt-6 max-w-[620px] text-body text-ink2 sm:text-[19px] sm:leading-[29px]">
          Desktop agents can read your whole computer and nothing on your phone.
          Carry closes that gap without a server: your iCloud carries it, your
          Mac reads it.
        </p>

        {/* Two apps, two buttons. The CLI is the developer path and stays one quiet line. */}
        <div className="mt-10 grid gap-3 sm:mt-12 sm:grid-cols-2 md:max-w-[640px]">
          <div className="flex flex-col gap-2">
            <a
              href={links.macDownload}
              className="inline-flex h-[52px] items-center justify-center gap-2 rounded-card bg-ink px-6 text-[16px] font-medium text-paper transition-opacity duration-150 hover:opacity-90"
            >
              <svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true" fill="none" className="stroke-current" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <rect x="1.5" y="3" width="13" height="8.5" rx="1.5" />
                <path d="M5 14h6" />
              </svg>
              Download Carry for Mac
            </a>
            <p className="text-center font-mono text-mono-sm text-ink2">
              macOS 14+ · notarized · one switch, once
            </p>
          </div>
          <div className="flex flex-col gap-2">
            <a
              href={links.appStore}
              className="inline-flex h-[52px] items-center justify-center gap-2 rounded-card bg-tangerine px-6 text-[16px] font-medium text-paper transition-opacity duration-150 hover:opacity-90"
            >
              <svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true" fill="none" className="stroke-current" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <rect x="4" y="1.5" width="8" height="13" rx="1.8" />
                <path d="M7 12.5h2" />
              </svg>
              Get Carry for iPhone
            </a>
            <p className="text-center font-mono text-mono-sm text-ink2">
              TestFlight first, App Store next.
            </p>
          </div>
        </div>

        <p className="mt-6 flex flex-wrap items-center gap-x-3 gap-y-1 font-mono text-mono-sm text-ink2">
          <span>Developers, headless Macs:</span>
          <code className="text-ink">{links.cliInstall}</code>
          <CopyButton text={install} />
        </p>

        <p className="mt-8 font-mono text-mono text-ink2">
          <span className="text-ink">No Carry server.</span>{" "}
          <span className="text-moss">Your iCloud carries it.</span>{" "}
          <span className="text-ink">Your Mac reads it.</span>
        </p>

        {/* What is read, where it goes, who sees it: answered before the fold. */}
        <dl className="prose-code mt-10 grid gap-5 border-t border-line pt-6 sm:mt-12 sm:grid-cols-3 sm:gap-8 sm:pt-7">
          {answers.map((a) => (
            <div key={a.k}>
              <dt className="font-serif text-[22px] leading-[26px] text-ink">{a.k}</dt>
              <dd className="mt-1.5 text-[15px] leading-[22px] text-ink2">{a.v}</dd>
            </div>
          ))}
        </dl>
      </Container>
    </header>
  );
}
