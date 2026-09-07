/**
 * The two channels, drawn once wide (md and up) and once tall (below md).
 * Colors follow DESIGN.md: moss = iCloud channel, tangerine = Carry app channel.
 * Text over lines uses paint-order:stroke with a paper stroke to knock the line out.
 */

const knock = { paintOrder: "stroke" as const, stroke: "var(--paper)", strokeWidth: 8, strokeLinejoin: "round" as const };

function Node({
  x, y, w, h, children, mono = false, rx = 12, size,
}: {
  x: number; y: number; w: number; h: number; children: string; mono?: boolean; rx?: number; size?: number;
}) {
  return (
    <g>
      <rect x={x} y={y} width={w} height={h} rx={rx} className="fill-paper2 stroke-line" strokeWidth="1" />
      <text
        x={x + w / 2}
        y={y + h / 2}
        textAnchor="middle"
        dominantBaseline="central"
        style={{ fontSize: size ?? (mono ? 13 : 15) }}
        className={mono ? "fill-ink font-mono" : "fill-ink font-sans font-medium"}
      >
        {children}
      </text>
    </g>
  );
}

export function ChannelsDiagramWide() {
  return (
    <svg
      viewBox="0 82 1040 162"
      className="hidden w-full lg:block"
      role="img"
      aria-labelledby="diagram-title-wide"
    >
      <title id="diagram-title-wide">
        iPhone to Mac over two channels (iCloud sync and the Carry app via iCloud Drive), then Mac to ~/.carry/context/ to Claude Code, Codex and Cursor.
      </title>
      <defs>
        <marker id="arrow-moss" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
          <path d="M1 1 L9 5 L1 9" fill="none" className="stroke-moss" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </marker>
        <marker id="arrow-tang" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
          <path d="M1 1 L9 5 L1 9" fill="none" className="stroke-tangerine" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </marker>
        <marker id="arrow-ink" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
          <path d="M1 1 L9 5 L1 9" fill="none" className="stroke-ink2" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </marker>
      </defs>

      {/* iPhone */}
      <Node x={0} y={110} w={112} h={80} size={16}>iPhone</Node>

      {/* Channel 1: iCloud already syncs (moss) */}
      <line x1={112} y1={130} x2={556} y2={130} className="stroke-moss" strokeWidth="1.5" markerEnd="url(#arrow-moss)" />
      <text x={334} y={98} textAnchor="middle" className="fill-moss font-mono text-[14px] font-medium">
        iCloud already syncs
      </text>
      <text x={334} y={118} textAnchor="middle" className="fill-ink2 font-mono text-[13px]">
        Photos · Notes · Messages · Voice Memos · Calendar…
      </text>

      {/* Channel 2: Carry app captures (tangerine), through iCloud Drive › Carry */}
      <line x1={112} y1={170} x2={240} y2={170} className="stroke-tangerine" strokeWidth="1.5" />
      <Node x={240} y={154} w={188} h={32} mono rx={8} size={14}>iCloud Drive › Carry</Node>
      <line x1={428} y1={170} x2={556} y2={170} className="stroke-tangerine" strokeWidth="1.5" markerEnd="url(#arrow-tang)" />
      <text x={334} y={214} textAnchor="middle" className="fill-tangerine font-mono text-[14px] font-medium">
        Carry app captures
      </text>
      <text x={334} y={234} textAnchor="middle" className="fill-ink2 font-mono text-[13px]">
        Health · Location · Share inbox
      </text>

      {/* Mac */}
      <Node x={560} y={110} w={112} h={80} size={16}>Mac</Node>

      {/* Mac → ~/.carry/context/ → agents */}
      <line x1={672} y1={150} x2={702} y2={150} className="stroke-ink2" strokeWidth="1.5" markerEnd="url(#arrow-ink)" />
      <Node x={704} y={134} w={164} h={32} mono rx={8} size={14}>~/.carry/context/</Node>
      <line x1={868} y1={150} x2={898} y2={150} className="stroke-ink2" strokeWidth="1.5" markerEnd="url(#arrow-ink)" />
      <text x={906} y={129} className="fill-ink font-sans text-[16px] font-medium">Claude Code</text>
      <text x={906} y={155} className="fill-ink font-sans text-[16px] font-medium">Codex</text>
      <text x={906} y={181} className="fill-ink font-sans text-[16px] font-medium">Cursor</text>
      <text x={704} y={188} className="fill-ink2 font-mono text-[13px]">
        Markdown · SQLite · MCP
      </text>
    </svg>
  );
}

export function ChannelsDiagramTall() {
  const L = 92; // left column center (moss)
  const R = 268; // right column center (tangerine)
  return (
    <svg
      viewBox="0 0 360 544"
      className="mx-auto w-full max-w-[360px] lg:hidden"
      role="img"
      aria-labelledby="diagram-title-tall"
    >
      <title id="diagram-title-tall">
        iPhone to Mac over two channels (iCloud sync and the Carry app via iCloud Drive), then Mac to ~/.carry/context/ to Claude Code, Codex and Cursor.
      </title>
      <defs>
        <marker id="arrow-moss-t" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
          <path d="M1 1 L9 5 L1 9" fill="none" className="stroke-moss" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </marker>
        <marker id="arrow-tang-t" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
          <path d="M1 1 L9 5 L1 9" fill="none" className="stroke-tangerine" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </marker>
        <marker id="arrow-ink-t" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
          <path d="M1 1 L9 5 L1 9" fill="none" className="stroke-ink2" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </marker>
      </defs>

      {/* iPhone */}
      <Node x={20} y={0} w={320} h={48}>iPhone</Node>

      {/* Channel 1 (moss): straight down to Mac */}
      <line x1={L} y1={48} x2={L} y2={304} className="stroke-moss" strokeWidth="1.5" markerEnd="url(#arrow-moss-t)" />
      <text x={L} y={96} textAnchor="middle" style={knock} className="fill-moss font-mono text-[13px] font-medium">
        iCloud already syncs
      </text>
      {["Photos · Notes", "Messages · Voice Memos", "Calendar · Reminders", "Safari · Screen Time"].map((t, i) => (
        <text key={t} x={L} y={118 + i * 17} textAnchor="middle" style={knock} className="fill-ink2 font-mono text-[12px]">
          {t}
        </text>
      ))}

      {/* Channel 2 (tangerine): down through iCloud Drive › Carry, then to Mac */}
      <line x1={R} y1={48} x2={R} y2={200} className="stroke-tangerine" strokeWidth="1.5" />
      <text x={R} y={96} textAnchor="middle" style={knock} className="fill-tangerine font-mono text-[13px] font-medium">
        Carry app captures
      </text>
      {["Health", "Location", "Share inbox"].map((t, i) => (
        <text key={t} x={R} y={118 + i * 17} textAnchor="middle" style={knock} className="fill-ink2 font-mono text-[12px]">
          {t}
        </text>
      ))}
      <Node x={182} y={200} w={172} h={32} mono rx={8}>iCloud Drive › Carry</Node>
      <line x1={R} y1={232} x2={R} y2={304} className="stroke-tangerine" strokeWidth="1.5" markerEnd="url(#arrow-tang-t)" />

      {/* Mac */}
      <Node x={20} y={308} w={320} h={48}>Mac</Node>

      {/* Mac → context → agents */}
      <line x1={180} y1={356} x2={180} y2={396} className="stroke-ink2" strokeWidth="1.5" markerEnd="url(#arrow-ink-t)" />
      <Node x={100} y={400} w={160} h={32} mono rx={8}>~/.carry/context/</Node>
      <text x={180} y={452} textAnchor="middle" className="fill-ink2 font-mono text-[12px]">
        Markdown · SQLite · MCP
      </text>
      <line x1={180} y1={464} x2={180} y2={504} className="stroke-ink2" strokeWidth="1.5" markerEnd="url(#arrow-ink-t)" />
      <text x={180} y={532} textAnchor="middle" className="fill-ink font-sans text-[15px] font-medium">
        Claude Code · Codex · Cursor
      </text>
    </svg>
  );
}
