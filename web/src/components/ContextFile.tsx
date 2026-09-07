import type { ReactNode } from "react";
import { Section } from "./Section";

/* A realistic but fictional digest. Every value here is invented. */

function H({ children }: { children: ReactNode }) {
  return <span className="text-ink">{children}</span>;
}
function Dim({ children }: { children: ReactNode }) {
  return <span className="text-ink2">{children}</span>;
}
function Time({ children }: { children: ReactNode }) {
  return <span className="text-ink2">{children}</span>;
}
function ProTag() {
  return (
    <span className="font-serif italic text-[15px] text-ink" title="Text produced by Carry Pro on your Mac">
      [Pro]
    </span>
  );
}

const sectionGap = "\n\n";

/* Notes in the rail beside the file. */
const notes: { k: ReactNode; v: ReactNode }[] = [
  {
    k: "Sections",
    v: "follow the sources you switched on. Nothing you turned off is read, so nothing you turned off appears.",
  },
  {
    k: <span className="font-serif italic text-[16px]">[Pro]</span>,
    v: "marks text your Mac made from a picture or a recording. Without Pro the line still exists; it just has no text.",
  },
  {
    k: "Off",
    v: "stays visible, so you can see that it is off.",
  },
  {
    k: "latest.md",
    v: "always points at today. week.md is the rolling seven days.",
  },
];

export function ContextFile() {
  return (
    <Section
      number="01"
      title="What your agent sees"
      lede={
        <>
          A plain Markdown file, rewritten every 15 minutes. Any agent can{" "}
          <code className="font-mono text-[15px] text-ink">cat</code> it.
        </>
      }
    >
      <div className="grid gap-8 lg:grid-cols-[minmax(0,1fr)_236px] lg:gap-10">
        <figure className="min-w-0">
          <div className="overflow-hidden rounded-card border border-line bg-paper2">
            <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 border-b border-line px-4 py-2.5 font-mono text-mono-sm sm:px-5">
              <span className="text-ink">~/.carry/context/2026-09-07.md</span>
              <span className="text-ink2">
                rewritten <span className="text-ok">21:30</span> · 4.1 KB
              </span>
            </div>
            <pre className="overflow-x-auto whitespace-pre-wrap px-4 py-5 font-mono text-[13px] leading-[21px] text-ink2 sm:px-6 sm:text-mono">
              <code>
                <H># Monday 7 September 2026</H>
                {"\n"}
                <Dim>Mac read 21:30 · 6 screenshots · 2 notes · 1 memo · Pro</Dim>
                {sectionGap}
                <H>## Inbox (3)</H>
                {"\n"}
                - <Time>13:05</Time> url · &ldquo;The case for local-first software&rdquo;
                {"\n"}
                {"  "}note: read this before Tuesday&rsquo;s design review
                {"\n"}
                - <Time>17:42</Time> image · screenshot from Safari
                {"\n"}
                {"  "}<ProTag /> text: &ldquo;Invoice #0921 · Total due $1,284.00 · Pay by Sep 30&rdquo;
                {"\n"}
                - <Time>19:10</Time> text · &ldquo;ask why brctl download hangs on placeholders&rdquo;
                {sectionGap}
                <H>## Health</H>
                {"\n"}
                - Sleep 7h12m · 23:40 → 07:05 · deep 1h05m · REM 1h38m
                {"\n"}
                - HRV 48 ms · resting HR 54 bpm · blood oxygen 97%
                {"\n"}
                - Steps 8,412 · active 41 min · 386 kcal · synced <Time>20:58</Time> (phone unlocked)
                {sectionGap}
                <H>## Places</H>
                {"\n"}
                - <Time>09:12–11:40</Time> Xuhui, Shanghai (2h28m)
                {"\n"}
                - <Time>14:20–16:05</Time> Wukang Road, Shanghai (1h45m)
                {sectionGap}
                <H>## Screenshots (6)</H>
                {"\n"}
                - <Time>10:22</Time> <ProTag /> &ldquo;Flight CA1832 · PVG → PEK · Sep 12 · 08:35 · Seat 14A&rdquo;
                {"\n"}
                - <Time>16:48</Time> <ProTag /> &ldquo;Reservation confirmed · Table for 4 · 19:30 · Fu He Hui&rdquo;
                {"\n"}
                - 4 more without readable text
                {sectionGap}
                <H>## Voice memos (1)</H>
                {"\n"}
                - <Time>12:31</Time> 2m14s · <ProTag /> transcript:
                {"\n"}
                {"  "}&ldquo;…the first screen has to answer three things: read, goes to, seen by…&rdquo;
                {sectionGap}
                <H>## Notes edited (2)</H>
                {"\n"}
                - Design review agenda <Dim>(edited 18:02)</Dim>
                {"\n"}
                - Groceries <Dim>(edited 08:15)</Dim>
                {sectionGap}
                <H>## Calendar (4)</H>
                {"\n"}
                - <Time>10:00</Time> Standup · <Time>12:30</Time> Lunch with Chen · <Time>15:00</Time> 1:1 · <Time>19:30</Time> Dinner
                {sectionGap}
                <H>## Messages</H>
                {"\n"}
                off <Dim>(you chose)</Dim>
              </code>
            </pre>
          </div>
          <figcaption className="sr-only">
            An example daily digest written by Carry on the Mac. Every value is invented.
          </figcaption>
        </figure>

        <dl className="grid content-start gap-5 border-t border-line pt-5 lg:gap-6 lg:border-t-0 lg:border-l lg:pt-1 lg:pl-8">
          {notes.map((n, i) => (
            <div key={i}>
              <dt className="font-mono text-[13px] leading-[20px] text-ink">{n.k}</dt>
              <dd className="mt-1 text-[14px] leading-[21px] text-ink2">{n.v}</dd>
            </div>
          ))}
        </dl>
      </div>
    </Section>
  );
}
