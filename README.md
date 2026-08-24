# AI Usage — Noctalia Shell plugin

Desktop / bar / control-center widget for [Noctalia Shell v4](https://docs.noctalia.dev) that monitors your **GLM Coding Plan** usage on z.ai:

- ⚡ **Session (5h)** — how much of the 5-hour rolling token window is left, with a live reset countdown
- 📅 **Weekly MCP-tools quota** — search-prime / web-reader / zread breakdown
- 🎨 Severity-colored usage bars, compact bar capsule, detail panel, settings UI (en/ru)

```
┌────────────────────────────┐
│ ⚡ AI · pro        46%    │
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
git clone https://github.com/aboyarinov/noctalia-ai-usage ~/.config/noctalia/plugins/ai-usage
```

Add to `~/.config/noctalia/plugins.json` (inside `"states"`):

```json
"ai-usage": { "enabled": true, "sourceUrl": "https://github.com/aboyarinov/noctalia-ai-usage" }
```

Restart the shell:

```bash
pkill -x qs && sleep 1 && setsid qs -c noctalia-shell --daemonize
```

## Configure

1. Open plugin **Settings**
2. Paste your **API key** (from z.ai → API keys). If left empty, the widget
   reads `Z_AI_API_KEY` from the environment (note: desktop sessions don't see
   shell rc files — set it via `~/.config/environment.d/` or just use the setting).
3. Tweak the refresh interval (1–60 min, default 5) and visibility options.

## Where to add the widget (all native, via Noctalia Settings GUI)

| Surface | How |
|---|---|
| **Bar** | Settings → Bar → widgets: add **AI Usage** (compact `⚡ 46%` capsule) |
| **Control Center** | Settings → Control Center → Shortcuts → **+**: add **AI Usage** tile (badge “plugin”). Click = panel, right-click = settings |
| **Desktop** | Desktop edit mode → add **AI Usage** card, drag anywhere (e.g. under the weather widget) |

## Optional: inside the Clock dropdown (below weather)

The clock dropdown (calendar + weather) has **no plugin API in Noctalia 0.0.12** —
its card list is hardcoded. Adding the widget there requires a small patch of
your **user copy** of the shell (no root needed, survives nothing — re-apply
after shell updates):

**1.** Make a user copy of the shell (Quickshell prefers `~/.config` over `/etc/xdg`):

```bash
cp -r /etc/xdg/quickshell/noctalia-shell ~/.config/quickshell/noctalia-shell
```

⚠️ After noctalia-qs package updates, re-sync your copy or the shell won't get fixes.

**2.** Patch `~/.config/quickshell/noctalia-shell/Modules/Panels/Clock/ClockPanel.qml`:

- add import: `import qs.Modules.Panels.ControlCenter`
- in the `Repeater`'s `switch`, replace `default: return null;` with:

```qml
default:
  return ControlCenterWidgetRegistry.isPluginWidget(modelData.id) ? pluginCard : null;
```

- inside the same `Loader` delegate, add:

```qml
Component {
  id: pluginCard
  ControlCenterWidgetLoader {
    widgetId: modelData.id
    widgetScreen: root.screen
    widgetProps: ({})
  }
}
```

**3.** Add the card below weather in `~/.config/noctalia/settings.json`:

```json
"calendar": {
  "cards": [
    { "enabled": true, "id": "calendar-header-card" },
    { "enabled": true, "id": "calendar-month-card" },
    { "enabled": true, "id": "weather-card" },
    { "enabled": true, "id": "plugin:ai-usage" }
  ]
}
```

⚠️ Don't reorder clock-panel cards in the Settings GUI afterwards — that tab
rewrites the list and drops unknown IDs.

**4.** Restart the shell (command above). Click the clock → the AI card sits
right under the weather.

## Entry points

| Point | File | What it shows |
|---|---|---|
| Desktop widget | `DesktopWidget.qml` | Draggable card: session % bar + reset countdown |
| Bar widget | `BarWidget.qml` | Compact capsule `⚡ 46%` |
| Control Center | `ControlCenterWidget.qml` | Tile with live tooltip |
| Panel | `Panel.qml` | Full report: session + weekly + MCP breakdown + refresh |
| Settings | `Settings.qml` | API key, interval, toggles |
| Main | `Main.qml` | Shared fetch service (single poller for all views) |

## License

MIT — see [LICENSE](LICENSE) (includes the ai-usagebar attribution notice).
