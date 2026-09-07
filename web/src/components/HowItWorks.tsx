import { links } from "@/lib/links";
import { Section } from "./Section";
import { ChannelsDiagramTall, ChannelsDiagramWide } from "./ChannelsDiagram";

const steps = [
  {
    n: "1",
    title: "Install the CLI on your Mac.",
    body: (
      <>
        <code>{links.cliInstall}</code>, then <code>{links.cliInit}</code>. It finds what iCloud already put on
        the Mac, checks Full Disk Access, and installs a 15-minute sync.
      </>
    ),
  },
  {
    n: "2",
    title: "Install Carry on your iPhone and choose what it covers.",
    body: (
      <>
        The app captures what iCloud does not carry (Health, Location, a share-sheet inbox) and holds the
        one list of switches. Off on the phone means not read on the Mac.
      </>
    ),
  },
  {
    n: "3",
    title: (
      <>
        Point your agent at <code>{links.contextDir}</code> or add the MCP server.
      </>
    ),
    body: (
      <>
        Files first: <code>latest.md</code> is today. <code>carry mcp</code> speaks stdio MCP for Claude Code,
        Codex and Cursor. <code>carry search</code> looks back further.
      </>
    ),
  },
];

export function HowItWorks() {
  return (
    <Section
      id="how"
      number="02"
      title="How it works"
      lede="Two channels, both your own iCloud. One folder on your Mac at the end."
    >
      <div className="rounded-card border border-line px-4 py-8 sm:px-6 sm:py-10">
        <ChannelsDiagramWide />
        <ChannelsDiagramTall />
      </div>

      <ol className="mt-10 grid gap-8 sm:mt-14 md:grid-cols-3 md:gap-10">
        {steps.map((s) => (
          <li key={s.n} className="prose-code grid grid-cols-[32px_1fr] gap-4 md:block">
            <span className="font-serif text-[28px] leading-[28px] text-tangerine md:mb-4 md:block">
              {s.n}
            </span>
            <div>
              <h3 className="text-[19px] leading-[26px] font-medium text-ink">{s.title}</h3>
              <p className="mt-2 text-[15px] leading-[23px] text-ink2">{s.body}</p>
            </div>
          </li>
        ))}
      </ol>
    </Section>
  );
}
