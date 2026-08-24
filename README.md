# Z.AI Usage — Noctalia Shell plugin

Desktop / bar / panel widget for [Noctalia Shell v4](https://docs.noctalia.dev) that monitors the **GLM Coding Plan** usage on z.ai:

- ⚡ **Session (5h)** — how much of the 5-hour rolling token window is left, with a live reset countdown
- 📅 **Weekly MCP-tools quota** — search-prime / web-reader / zread breakdown
- 🎨 Severity-colored usage bars, compact bar capsule, detailed panel, settings UI (en/ru)

```
┌────────────────────────────┐
│ ⚡ z.ai · pro      46%    │
│ ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░  │
│ сброс 21:07 · через 1ч23м │
└────────────────────────────┘
```

## Attribution

This plugin is **based on [akitaonrails/ai-usagebar](https://github.com/akitaonrails/ai-usagebar)** (MIT).
The `UsageBar.qml` / `UsageRow.qml` components and the logic layer are ported from its
KDE-plasmoid frontend to Noctalia's `qs.Commons` design system, with the z.ai
fetch implemented natively in QML (`XMLHttpRequest`) instead of shelling out to
the Rust binary.

The z.ai endpoint `api.z.ai/api/monitor/usage/quota/limit` is undocumented
(reverse-engineered); parsing is defensive and degrades gracefully.

## Install

```bash
git clone https://github.com/aboyarinov/noctalia-zai-usage ~/.config/noctalia/plugins/zai-usage
```

Then enable the plugin in Noctalia settings (or add it to `~/.config/noctalia/plugins.json`),
and restart the shell (`qs -c noctalia-shell`).

## Configure

1. Open plugin **Settings**
2. Paste your **API key** (from z.ai → API keys). If left empty, the widget
   reads `Z_AI_API_KEY` from the environment.
3. Tweak the refresh interval (1–60 min, default 5) and visibility options.

## Entry points

| Point | File | What it shows |
|---|---|---|
| Desktop widget | `DesktopWidget.qml` | Draggable card: session % bar + reset countdown |
| Bar widget | `BarWidget.qml` | Compact capsule `⚡ 46%` |
| Panel | `Panel.qml` | Full report: session + weekly + MCP breakdown + refresh |
| Settings | `Settings.qml` | API key, interval, toggles |
| Main | `Main.qml` | Shared fetch service (single poller for all views) |

## License

MIT — see [LICENSE](LICENSE) (includes the ai-usagebar attribution notice).
