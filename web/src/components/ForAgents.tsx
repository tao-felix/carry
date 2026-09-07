import { links } from "@/lib/links";
import { Section } from "./Section";
import { CopyButton } from "./CopyButton";

const snippets: { title: string; where: string; code: string; note?: string }[] = [
  {
    title: "Claude Code",
    where: "Terminal",
    code: links.mcpAddClaude,
    note: "Registers the stdio MCP server. Tools: today, search, recent, status.",
  },
  {
    title: "Codex",
    where: links.mcpCodexPath,
    code: links.mcpCodexToml,
    note: "Cursor and any other MCP client: same command, carry mcp, over stdio.",
  },
  {
    title: "CLAUDE.md / AGENTS.md",
    where: "Paste into your project or home file",
    code: links.agentsMd,
    note: "No MCP needed. The agent reads the file like any other file.",
  },
];

export function ForAgents() {
  return (
    <Section
      id="agents"
      number="06"
      title="For agents"
      lede="Three ways in. The file is enough; MCP adds search."
    >
      <div className="grid gap-4">
        {snippets.map((s) => (
          <div key={s.title} className="overflow-hidden rounded-card border border-line">
            <div className="flex flex-wrap items-center justify-between gap-x-4 gap-y-2 border-b border-line bg-paper2 px-4 py-2.5 sm:px-5">
              <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1">
                <h3 className="text-[16px] leading-[22px] font-medium text-ink">{s.title}</h3>
                <span className="font-mono text-mono-sm text-ink2">{s.where}</span>
              </div>
              <CopyButton text={s.code} />
            </div>
            <pre className="overflow-x-auto whitespace-pre-wrap px-4 py-4 font-mono text-mono text-ink sm:px-5">
              <code>{s.code}</code>
            </pre>
            {s.note ? (
              <p className="border-t border-line px-4 py-2.5 text-[14px] leading-[20px] text-ink2 sm:px-5">{s.note}</p>
            ) : null}
          </div>
        ))}
      </div>
    </Section>
  );
}
