// Main.qml v2 — shared data service: one poller per configured provider.
//
// State is exposed for every entry point via `pluginApi.mainInstance`:
//   providers        — migrated provider configs (array)
//   entries          — { providerId: normalized entry } (last good fetch)
//   errors           — { providerId: message } ('' when healthy)
//   fetching         — { providerId: bool }
//   activeProviderId / activeEntry — convenience for bar & CC widgets
//
// Each adapter may declare several HTTP requests (e.g. OpenRouter credits+key);
// they are all resolved before adapter.parse() runs.
import QtQuick
import Quickshell
import qs.Commons
import "Logic.js" as Logic

Item {
  id: root

  property var pluginApi: null

  property var providers: []
  property string activeProviderId: ""
  property var entries: ({})
  property var errors: ({})
  property var fetching: ({})
  property real now: Date.now()

  readonly property int refreshMs: {
    var m = Number(pluginApi && pluginApi.pluginSettings ? pluginApi.pluginSettings.refreshMinutes : 5);
    if (!isFinite(m) || m <= 0)
      m = 5;
    return Math.max(1, Math.min(60, Math.round(m))) * 60000;
  }

  readonly property bool showBackground: pluginApi && pluginApi.pluginSettings && pluginApi.pluginSettings.showBackground !== undefined ? pluginApi.pluginSettings.showBackground : true

  function settingsObj() {
    return pluginApi ? pluginApi.pluginSettings : null;
  }

  function saveSettings() {
    if (pluginApi && pluginApi.saveSettings)
      pluginApi.saveSettings();
  }

  // Load + migrate provider list (v0.2 single key → v0.3 list), persisted once.
  function loadProviders() {
    var s = settingsObj();
    if (!s)
      return;
    var migrated = Logic.migrateSettings(s);
    var changed = !Array.isArray(s.providers) || s.activeProviderId === undefined;
    s.providers = migrated.providers;
    s.activeProviderId = migrated.activeProviderId;
    if (changed)
      saveSettings();
    root.providers = s.providers;
    root.activeProviderId = s.activeProviderId;
  }

  function providerById(id) {
    for (var i = 0; i < root.providers.length; i++) {
      if (root.providers[i].id === id)
        return root.providers[i];
    }
    return null;
  }

  function adapterFor(p) {
    return p ? Logic.PROVIDERS[p.type] : null;
  }

  // Display helpers shared by all widgets.
  function displayLabel(p) {
    if (!p)
      return "";
    if (p.label && p.label !== "")
      return p.label;
    var a = adapterFor(p);
    return a ? a.name : p.type;
  }

  function chipFor(p) {
    var a = adapterFor(p);
    return a ? { monogram: a.monogram, color: a.color, name: a.name } : { monogram: '?', color: '#7c80b4', name: p ? p.type : '' };
  }

  function setActive(id) {
    var s = settingsObj();
    if (!s || !providerById(id))
      return;
    s.activeProviderId = id;
    root.activeProviderId = id;
    saveSettings();
  }

  // The headline metric for compact views: session % for window vendors,
  // balance for money vendors. Returns the metric section or null.
  function headlineSection(entry) {
    if (!entry)
      return null;
    var s = Logic.sectionByKey(entry, 'session');
    if (s)
      return s;
    return Logic.sectionByKey(entry, 'balance');
  }

  // "46" (left) for percent metrics; null for balance vendors.
  function leftPercent(entry) {
    var s = headlineSection(entry);
    if (!s || s.percent === null || s.percent === undefined)
      return -1;
    return 100 - s.percent;
  }

  readonly property var activeProvider: providerById(activeProviderId)
  readonly property var activeEntry: entries[activeProviderId] !== undefined ? entries[activeProviderId] : null
  readonly property string activeError: errors[activeProviderId] !== undefined ? errors[activeProviderId] : ""

  // ------------------------------------------------------------------ fetch

  function fetchProvider(p) {
    if (!p || !p.apiKey || p.apiKey === "")
      return;
    var adapter = adapterFor(p);
    if (!adapter) {
      root.errors = Object.assign({}, root.errors, (function () { var o = {}; o[p.id] = 'unknown provider type'; return o; })());
      return;
    }
    if (root.fetching[p.id])
      return;
    var f = Object.assign({}, root.fetching);
    f[p.id] = true;
    root.fetching = f;

    var responses = {};
    var pending = adapter.requests.length;
    var finishOne = function () {
      pending--;
      if (pending > 0)
        return;
      var r = adapter.parse(responses, Date.now());
      var e = Object.assign({}, root.entries);
      var er = Object.assign({}, root.errors);
      var fDone = Object.assign({}, root.fetching);
      if (r.ok) {
        e[p.id] = r.entry;
        er[p.id] = '';
      } else {
        er[p.id] = r.error;
        Logger.w("AiUsage", p.type + " parse failed: " + r.error);
      }
      fDone[p.id] = false;
      root.entries = e;
      root.errors = er;
      root.fetching = fDone;
    };
    for (var i = 0; i < adapter.requests.length; i++) {
      (function (req) {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", req.url);
        var hdrs = req.headers(p.apiKey);
        for (var k in hdrs)
          xhr.setRequestHeader(k, hdrs[k]);
        xhr.onreadystatechange = function () {
          if (xhr.readyState !== XMLHttpRequest.DONE)
            return;
          if (xhr.status === 200) {
            try {
              responses[req.id] = JSON.parse(xhr.responseText);
            } catch (e2) {
              responses[req.id] = null;
            }
          } else {
            responses[req.id] = null;
            Logger.w("AiUsage", p.type + " " + req.id + " HTTP " + xhr.status);
          }
          finishOne();
        };
        xhr.send();
      })(adapter.requests[i]);
    }
  }

  function fetchAll() {
    for (var i = 0; i < root.providers.length; i++) {
      var p = root.providers[i];
      if (p.enabled)
        fetchProvider(p);
    }
  }

  function fetchNow() {
    fetchAll();
  }

  // ------------------------------------------------------------------ timers

  Timer {
    id: pollTimer
    interval: root.refreshMs
    running: root.providers.length > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.fetchAll()
  }

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
    loadProviders();
    Logger.i("AiUsage", "service started, " + root.providers.length + " provider(s)");
  }

  onPluginApiChanged: {
    if (pluginApi)
      loadProviders();
  }
}
