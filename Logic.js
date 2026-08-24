// Logic.js — data layer of the Z.AI Usage plugin for Noctalia Shell.
//
// Ported from akitaonrails/ai-usagebar (MIT):
//   kde-plasmoid/package/contents/code/plasmoid-logic.mjs
// (safeText / finitePercent / severityOf bands / defensive normalization),
// adapted to parse the z.ai quota response natively instead of consuming
// `ai-usagebar usage --json`.
//
// QML V4 engine rules (as documented in the source project):
//   - no ES2019 optional catch binding (`catch {`)
//   - no Unicode property escapes (`\p{...}`) — silently false in V4
//
// Produces an ai-usagebar-shaped entry so the UI layer stays a pure
// presentation layer:
//   { id, label, plan, status, error, sections[] }
//     section metric: { type, key, label, value, percent, detail, resetAt, severity }
//     section block:  { type, key, label, body: [lines] }
//
// z.ai response facts (reverse-engineered, fragile):
//   GET api.z.ai/api/monitor/usage/quota/limit
//   data.level                     → plan name ("pro")
//   data.limits[].type TOKENS_LIMIT→ 5h session: percentage = USED %,
//                                    nextResetTime = epoch ms of window reset
//   data.limits[].type TIME_LIMIT  → weekly MCP-tools quota: usage = limit,
//                                    currentValue = used, usageDetails[] per tool

.pragma library

var SEVERITIES = ['low', 'mid', 'high', 'critical'];

// Severity bands mirror ai-usagebar: >=90 critical, >=75 high, >=50 mid.
function severityOf(percent) {
  var p = finitePercent(percent);
  if (p === null)
    return 'low';
  return p >= 90 ? 'critical' : p >= 75 ? 'high' : p >= 50 ? 'mid' : 'low';
}

function isSeverity(s) {
  return SEVERITIES.indexOf(String(s)) >= 0;
}

// Strip display-control / bidi characters and markup delimiters; clamp length.
// Report fields come from a remote response, so nothing here may be trusted.
function safeText(value, maxLength) {
  var max = maxLength || 400;
  var s = String(value === null || value === undefined ? '' : value);
  s = s.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f\u202a-\u202e\u2066-\u2069]/g, '');
  s = s.replace(/</g, '‹').replace(/>/g, '›');
  return s.length > max ? s.substring(0, max) : s;
}

function finitePercent(value) {
  var n = Number(value);
  return isFinite(n) ? Math.max(0, Math.min(100, n)) : null;
}

function finiteInt(value) {
  var n = Number(value);
  return isFinite(n) ? Math.round(n) : 0;
}

// ---------------------------------------------------------------------------
// z.ai quota → entry
// ---------------------------------------------------------------------------

function findLimit(limits, type) {
  if (!limits)
    return null;
  for (var i = 0; i < limits.length; i++) {
    var lim = limits[i];
    if (lim && String(lim.type || '') === type)
      return lim;
  }
  return null;
}

// doc: parsed JSON of the quota response; nowMs: Date.now() at fetch time.
// Returns { ok: true, entry } or { ok: false, error }.
function parseQuota(doc, nowMs) {
  if (!doc || typeof doc !== 'object')
    return {ok: false, error: 'empty response'};

  var data = doc.data;
  if (!data || typeof data !== 'object') {
    var apiMsg = doc.msg || doc.message || doc.error;
    if (apiMsg)
      return {ok: false, error: safeText(String(apiMsg), 200)};
    return {ok: false, error: 'unexpected response shape'};
  }

  var limits = Array.isArray(data.limits) ? data.limits : [];
  var session = findLimit(limits, 'TOKENS_LIMIT');
  var weekly = findLimit(limits, 'TIME_LIMIT');
  var sections = [];

  // --- Session (5h) -------------------------------------------------------
  if (session) {
    var sPct = finitePercent(session.percentage);
    sections.push({
      type: 'metric',
      key: 'session',
      percent: sPct,
      value: sPct === null ? '' : String(sPct) + '%',
      detail: '',
      resetAt: finiteInt(session.nextResetTime),
      severity: severityOf(sPct)
    });
  }

  // --- Weekly MCP-tools quota ----------------------------------------------
  if (weekly) {
    var wPct = finitePercent(weekly.percentage);
    var used = weekly.currentValue !== undefined ? finiteInt(weekly.currentValue) : null;
    var cap = weekly.usage !== undefined ? finiteInt(weekly.usage) : null;
    var value = '';
    if (used !== null && cap !== null && cap > 0)
      value = used + ' / ' + cap;
    else if (used !== null)
      value = String(used);
    var wDetail = '';
    if (weekly.remaining !== undefined)
      wDetail = String(finiteInt(weekly.remaining));
    sections.push({
      type: 'metric',
      key: 'weekly',
      percent: wPct,
      value: value,
      detail: wDetail,
      resetAt: finiteInt(weekly.nextResetTime),
      severity: severityOf(wPct)
    });

    // --- MCP tools breakdown ------------------------------------------------
    var details = weekly.usageDetails;
    if (Array.isArray(details) && details.length > 0) {
      var body = [];
      for (var d = 0; d < details.length && d < 32; d++) {
        var row = details[d];
        if (!row)
          continue;
        body.push(safeText(row.modelCode, 60) + ' · ' + finiteInt(row.usage));
      }
      if (body.length > 0)
        sections.push({type: 'block', key: 'tools', body: body});
    }
  }

  return {
    ok: true,
    entry: {
      id: 'zai',
      label: 'z.ai',
      plan: safeText(data.level, 40) || '',
      status: sections.length > 0 ? 'ready' : 'empty',
      error: '',
      fetchedAt: nowMs,
      sections: sections
    }
  };
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

// ms → "2h 05m" / "47m" / "now". Units come from i18n ("units.h"/"units.m").
function formatDuration(ms, hUnit, mUnit) {
  var total = Math.floor(ms / 1000);
  if (total < 0)
    total = 0;
  var h = Math.floor(total / 3600);
  var m = Math.floor((total % 3600) / 60);
  if (h > 0)
    return h + hUnit + ' ' + (m < 10 ? '0' : '') + m + mUnit;
  if (m > 0)
    return m + mUnit;
  return '<1' + mUnit;
}

// Seconds ago → "2m ago" style body is composed by the caller; here only parts.
function remainingMs(resetAt, nowMs) {
  var d = finiteInt(resetAt) - nowMs;
  return d > 0 ? d : 0;
}

// Convenience: find a section by key.
function sectionByKey(entry, key) {
  if (!entry || !entry.sections)
    return null;
  for (var i = 0; i < entry.sections.length; i++) {
    if (entry.sections[i].key === key)
      return entry.sections[i];
  }
  return null;
}
