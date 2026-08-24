// Main.qml — shared data service for all entry points (the single poller).
//
// Mirrors how the reference plugin (todo) centralizes state in Main.qml:
// every view reaches this instance through `pluginApi.mainInstance`.
// Fetches api.z.ai/api/monitor/usage/quota/limit, normalizes it via Logic.js
// into an ai-usagebar-shaped entry and exposes `now` ticks for live
// countdowns.
import QtQuick
import Quickshell
import qs.Commons
import "Logic.js" as Logic

Item {
  id: root

  property var pluginApi: null

  // Normalized entry from Logic.parseQuota().entry, or null before first
  // successful fetch. Kept on later failures so views can show stale data.
  property var entry: null
  property string lastError: ""
  property bool fetching: false
  property real now: Date.now()

  readonly property string endpoint: "https://api.z.ai/api/monitor/usage/quota/limit"

  // Settings key takes precedence; environment is the fallback so the widget
  // works out of the box for users who already export Z_AI_API_KEY.
  readonly property string apiKey: {
    var k = pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings.apiKey ? pluginApi.pluginSettings.apiKey : "";
    if (k)
      return k;
    return Quickshell.env("Z_AI_API_KEY") || "";
  }

  readonly property bool hasKey: apiKey !== ""

  readonly property int refreshMs: {
    var m = Number(pluginApi && pluginApi.pluginSettings ? pluginApi.pluginSettings.refreshMinutes : 5);
    if (!isFinite(m) || m <= 0)
      m = 5;
    return Math.max(1, Math.min(60, Math.round(m))) * 60000;
  }

  readonly property bool showWeekly: pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings.showWeekly !== undefined ? pluginApi.pluginSettings.showWeekly : true

  function fetchNow() {
    if (root.fetching)
      return;
    if (!root.hasKey) {
      root.lastError = "api key not set";
      return;
    }

    root.fetching = true;
    var xhr = new XMLHttpRequest();
    xhr.open("GET", root.endpoint);
    xhr.setRequestHeader("Authorization", "Bearer " + root.apiKey);
    xhr.setRequestHeader("Accept-Language", "en-US,en");
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return;
      root.fetching = false;
      if (xhr.status !== 200) {
        // Keep the last good entry; views mark it as stale.
        root.lastError = "HTTP " + xhr.status;
        Logger.w("ZaiUsage", "fetch failed: " + root.lastError);
        return;
      }
      var doc = null;
      try {
        doc = JSON.parse(xhr.responseText);
      } catch (e) {
        root.lastError = "invalid JSON";
        Logger.w("ZaiUsage", root.lastError);
        return;
      }
      var r = Logic.parseQuota(doc, Date.now());
      if (r.ok) {
        root.entry = r.entry;
        root.lastError = "";
        Logger.d("ZaiUsage", "usage updated");
      } else {
        root.lastError = r.error;
        Logger.w("ZaiUsage", "parse failed: " + r.error);
      }
    };
    xhr.send();
  }

  // Poll the API. Retriggered automatically when refreshMinutes changes.
  Timer {
    id: pollTimer
    interval: root.refreshMs
    running: root.hasKey
    repeat: true
    triggeredOnStart: true
    onTriggered: root.fetchNow()
  }

  // 30-second tick so reset countdowns advance without a refetch.
  Timer {
    id: tickTimer
    interval: 30000
    running: true
    repeat: true
    onTriggered: root.now = Date.now()
  }

  Component.onCompleted: {
    if (!pluginApi)
      return;
    // Defensive defaults (the framework merges manifest defaults, but a
    // missing key must never produce NaN intervals).
    if (!pluginApi.pluginSettings) {
      Logger.w("ZaiUsage", "pluginSettings unavailable");
      return;
    }
    if (pluginApi.pluginSettings.refreshMinutes === undefined)
      pluginApi.pluginSettings.refreshMinutes = 5;
    if (pluginApi.pluginSettings.showWeekly === undefined)
      pluginApi.pluginSettings.showWeekly = true;
    Logger.i("ZaiUsage", "service started");
  }
}
