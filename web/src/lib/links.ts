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
  appStore: "#ios",
  testflight: "#ios",

  /** Mac CLI. */
  cliInstall: "uv tool install carry-context",
  cliInit: "carry init",

  /** The single paid plan. */
  proPrice: "$39 / year",
  proPriceMonthly: "$5.99 / month",

  /** Paths and commands quoted on the page. */
  contextDir: "~/.carry/context/",
  mcpAddClaude: "claude mcp add carry -- carry mcp",
  mcpCodexPath: "~/.codex/config.toml",
  mcpCodexToml: '[mcp_servers.carry]\ncommand = "carry"\nargs = ["mcp"]\ndefault_tools_approval_mode = "auto"',
  agentsMd:
    'My phone context lives in ~/.carry/context/. Read latest.md at the start of a session when my request touches my day, my health, places, or things I shared from my phone. Use `carry search "<query>"` for anything older.',
} as const;

export type Links = typeof links;
