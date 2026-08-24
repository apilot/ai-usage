# AI Usage — Noctalia Shell plugin

Multi-provider **AI plan usage monitor** for [Noctalia Shell v4](https://docs.noctalia.dev):

- ⚡ **z.ai GLM Coding Plan** — 5-hour session window, weekly MCP-tools quota, live reset countdown
- 💰 **DeepSeek** — balance (granted/topped-up breakdown, USD/CNY)
- 💰 **OpenRouter** — credits balance, consumption %, key meta (label, free tier, rate limit)
- ⚡ **Kimi** — session window + weekly quota

One card on the desktop, a capsule in the bar, a tile in the Control Center, a detailed panel with provider tabs — pick what you use. Several providers can be added side by side; the active one headlines the widget, others are one click away.

```
┌────────────────────────────┐
│ (Z) z.ai · pro      46%   │   ← active provider: chip + plan + remaining
│ ▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░  │   ← severity-colored usage bar
│ сброс 21:07 · через 1ч23м │   ← live reset countdown (local TZ)
│ до 15.09 · 22 дн          │   ← optional plan validity (manual)
│ (K) Kimi            80%   │   ← other providers: compact rows
└────────────────────────────┘
```

## Attribution

This plugin is **based on [akitaonrails/ai-usagebar](https://github.com/akitaonrails/ai-usagebar)** (MIT).
`UsageBar.qml`, `UsageRow.qml` and the parsing/logic layer are ported from its
KDE-plasmoid frontend to Noctalia's `qs.Commons` design system; provider
endpoints are fetched natively in QML (`XMLHttpRequest`) instead of shelling
out to the Rust binary.

The z.ai and Kimi endpoints are undocumented (reverse-engineered) and treated
as fragile: parsing is defensive and degrades gracefully instead of breaking
the widget.

## Install

```bash
git clone https://github.com/aboyarinov/noctalia-ai-usage ~/.config/noctalia/plugins/ai-usage
```

Enable the plugin (Noctalia Settings → Plugins, or add `"ai-usage": {"enabled": true, "sourceUrl": "…"}` to `~/.config/noctalia/plugins.json` `states`) and restart the shell (`qs -c noctalia-shell`).

## Configure

1. Open plugin **Settings**
2. Pick a **provider type**, paste the **API key**, press **Add** — the widget
   fetches immediately (a wrong key shows the error inline, nothing breaks)
3. Optionally set a **display name**, a **plan override** (`pro`, `lite`…) and
   **valid until** (`YYYY-MM-DD`) — the card then shows «until 15.09 · 22 d»
   and highlights the date when ≤ 7 days remain
4. Repeat for every provider you use; click a row to make it the active one

| Setting | Meaning |
|---|---|
| Providers | List of `{type, apiKey, label, planLabel, validUntil, enabled}` |
| Refresh interval | 1–60 min (default 5) |
| Widget background | Card background on the desktop |

## Where to add the widget

| Surface | How |
|---|---|
| Desktop | Edit mode → drag **AI Usage** anywhere (e.g. under the weather card) |
| Bar | Bar settings → widgets → **AI Usage** |
| Control Center | CC settings → **Shortcuts** → add **AI Usage** (plugin badge) |
| Clock dropdown | Optional manual patch — see below |

### Optional: inside the Clock dropdown

The clock panel only renders its hardcoded cards. To place the widget under
the weather card, patch a user copy of the shell:

```bash
cp -r /etc/xdg/quickshell/noctalia-shell ~/.config/quickshell/noctalia-shell
```

In `~/.config/quickshell/noctalia-shell/Modules/Panels/Clock/ClockPanel.qml`
add `import qs.Modules.Panels.ControlCenter` and, in the cards `switch`
`default:` branch:

```qml
return ControlCenterWidgetRegistry.isPluginWidget(modelData.id) ? pluginCard : null;
```

with an inline `Component` `pluginCard` containing
`ControlCenterWidgetLoader { widgetId: modelData.id; widgetScreen: root.screen; widgetProps: ({}) }`,
then append `{"enabled": true, "id": "plugin:ai-usage"}` to `calendar.cards`
in `~/.config/noctalia/settings.json`.

## Provider endpoints

| Provider | Endpoint | Notes |
|---|---|---|
| z.ai | `api.z.ai/api/monitor/usage/quota/limit` | undocumented, `TOKENS_LIMIT` = 5h window |
| DeepSeek | `api.deepseek.com/user/balance` | documented API |
| OpenRouter | `openrouter.ai/api/v1/credits` + `/api/v1/key` | documented API |
| Kimi | `api.kimi.com/coding/v1/usages` | undocumented, tolerant parsing |

## Development

```bash
node tests/logic.test.mjs          # 22 unit tests for the data layer
timeout 25 qs -p <bench-dir>       # QML component smoke test
```

## License

MIT — see [LICENSE](LICENSE) (includes the ai-usagebar attribution notice).
