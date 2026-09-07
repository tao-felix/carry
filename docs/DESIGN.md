# Carry design system

Carry has one job: put what your phone knows in front of your desktop agent, and make you feel exactly what is being read and where it goes. Every screen and every page must answer three questions without scrolling: **what is read, where it goes, who can see it.**

## Brand

- Name: **Carry**. What you carry in your pocket, carried to your agent's desk.
- Tagline (EN): *Everything your phone knows, on your agent's desk.*
- Tagline (ZH): *把手机里的你，带到 Agent 面前。*
- Voice: plain, precise, calm. No hype. Say "your iCloud", "your Mac", never "the cloud". Never say "AI-powered".
- One promise repeated everywhere: **No Carry server. Your iCloud carries it. Your Mac reads it.**

## Color

Two channels get two colors. Use them consistently in the app, the CLI, and the site.

| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` | `#F6F1E9` | `#141310` | page background |
| `paper2` | `#EDE6DA` | `#1F1D18` | cards, code blocks |
| `line` | `#D9D0C1` | `#2E2B24` | hairlines |
| `ink` | `#141310` | `#F6F1E9` | primary text |
| `ink2` | `#5C574D` | `#A39D90` | secondary text |
| `moss` | `#2E5E4E` | `#7FB39E` | **iCloud channel** (Apple already syncs it) |
| `tangerine` | `#E8562B` | `#FF7A4D` | **Carry app channel** (only the app can capture it); also the one accent |
| `ok` | `#2E5E4E` | `#7FB39E` | success, "Mac read this" |
| `warn` | `#B8860B` | `#E0B54A` | needs attention (permission, unlocked-phone rule) |

Never introduce a third accent. Pro is not a color; Pro is a small serif word.

## Type

- Display: **Instrument Serif** (web, Google Fonts). On iOS use the system serif (`.font(.system(.largeTitle, design: .serif))`), which is New York. Headlines are sentence case, never all caps.
- Body: **Inter** on web; SF on iOS.
- Mono: **JetBrains Mono** on web; SF Mono on iOS. Use mono for paths, commands, file names, timestamps.
- Scale (web): display 56/64, h2 32/40, h3 22/28, body 17/26, small 14/20, mono 14/22.
- Scale (iOS): largeTitle serif for screen titles, `.title3` for section heads, `.body` for text, `.footnote` mono for paths and times.

## Layout and components

- Max content width on web: 1040px. Generous whitespace; hairlines instead of shadows; corners 12px; no gradients; no glassmorphism.
- **Source card**: name, one-line "what is read", channel badge (`via iCloud` in moss, `via Carry app` in tangerine), toggle. Disabled cards fade to 55% opacity, never disappear.
- **Status line**: mono, e.g. `Mac read 12 min ago · 40 photos · 2 notes · Pro`. Or, honestly, `No Mac has read this yet → install the CLI`.
- **Plain-language privacy block** (present on the site, on the app's first screen, and in `carry init` output):
  1. Read: the sources you switched on.
  2. Goes to: your iCloud Drive (folder `Carry`), then your Mac.
  3. Seen by: the agents you point at `~/.carry/context/`. Nobody else. There is no Carry server.
- **Pro**: exactly one plan, one price, one sentence: *Pro turns pictures and audio into text your agent can read.* Show what stays free right next to it.

## Motion

Almost none. 150ms fades. No bouncing, no confetti. A sync in progress is a mono line that updates, not a spinner.

## CLI

- `rich` output, but restrained: tables with hairline rules, moss for iCloud sources, tangerine for app sources, dim for disabled.
- Every command that reads data ends with one line stating where output went, e.g. `→ ~/.carry/context/2026-09-07.md`.
