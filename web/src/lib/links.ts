/**
 * Every editable link, command and number on the site lives here.
 * Nothing else on the page hard-codes these.
 */
export const links = {
  /** Public site URL. Used for canonical + Open Graph. */
  siteUrl: "https://carry.app",

  /** Source code. */
  github: "https://github.com/tao-felix/carry",

  /** iPhone app. Placeholders until the app is live. */
  macDownload: "https://github.com/tao-felix/carry/releases/latest/download/Carry-0.1.1-arm64.dmg",
  macReleases: "https://github.com/tao-felix/carry/releases/latest",
  appStore: "#ios",
  testflight: "#ios",

  /** Mac CLI. */
  cliInstall: "uv tool install carry-context",
  cliInit: "carry init",

  /** The single paid plan. */
  proPrice: "$39.99 / year",
  proPriceMonthly: "$5.99 / month",

  /** Paths and commands quoted on the page. */
  contextDir: "~/.carry/context/",
  mcpUrl: "http://127.0.0.1:47850/mcp",
  mcpAddClaude: "claude mcp add --transport http carry http://127.0.0.1:47850/mcp",
  mcpAddClaudeCli: "claude mcp add carry -- carry mcp",
  mcpCodexPath: "~/.codex/config.toml",
  mcpCodexToml: '[mcp_servers.carry]\nurl = "http://127.0.0.1:47850/mcp"\ndefault_tools_approval_mode = "auto"',
  skillUrl: "https://carry-site.vercel.app/SKILL.md",
  skillAsk:
    "Install the Carry skill: fetch https://carry-site.vercel.app/SKILL.md, save it as ~/.claude/skills/carry/SKILL.md (or your agent's skills folder), then read it before answering anything about my phone, my day, or things I shared from my phone.",
  skillCurl:
    "mkdir -p ~/.claude/skills/carry && curl -fsSL https://carry-site.vercel.app/SKILL.md -o ~/.claude/skills/carry/SKILL.md",
  skillCli: "carry skill install",
  agentsMd:
    'My phone context lives in ~/.carry/context/. Read latest.md at the start of a session when my request touches my day, my health, places, or things I shared from my phone. Use `carry search "<query>"` for anything older.',
} as const;

export type Links = typeof links;
