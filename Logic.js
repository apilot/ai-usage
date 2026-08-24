// Logic.js v2 — multi-provider data layer of the AI Usage plugin.
//
// Ported from akitaonrails/ai-usagebar (MIT): the vendor registry pattern and
// the defensive parsing rules of kde-plasmoid/package/contents/code/
// plasmoid-logic.mjs (safeText / finitePercent / severity bands), extended
// with native z.ai / DeepSeek / OpenRouter / Kimi adapters.
//
// QML V4 engine rules (from the source project):
//   - no ES2019 optional catch binding (`catch {`)
//   - no Unicode property escapes (`\p{...}`) — silently false in V4
//
// Provider registry contract:
//   PROVIDERS[type] = {
//     name, monogram (1-2 chars), color (#hex),
//     requests: [{ id, url, headers(key) }],
//     parse(responses: { [requestId]: parsedJson }, nowMs)
//       -> { ok: true, entry } | { ok: false, error }
//   }
//
// Entry contract (ai-usagebar-shaped, same as v0.2):
//   { id, label, plan, status: 'ready'|'empty'|'error', error, fetchedAt,
//     sections: [
//       { type:'metric', key, value, percent|null, detail, resetAt(ms), severity },
//       { type:'block',  key, body: [lines] } ] }

.pragma library

// ---------------------------------------------------------------------------
// Shared utilities
// ---------------------------------------------------------------------------

var SEVERITIES = ['low', 'mid', 'high', 'critical'];

function severityOf(percent) {
  var p = finitePercent(percent);
  if (p === null)
    return 'low';
  return p >= 90 ? 'critical' : p >= 75 ? 'high' : p >= 50 ? 'mid' : 'low';
}

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

function remainingMs(resetAt, nowMs) {
  var d = finiteInt(resetAt) - nowMs;
  return d > 0 ? d : 0;
}

function sectionByKey(entry, key) {
  if (!entry || !entry.sections)
    return null;
  for (var i = 0; i < entry.sections.length; i++) {
    if (entry.sections[i].key === key)
      return entry.sections[i];
  }
  return null;
}

function metric(key, value, percent, detail, resetAt, severity) {
  return {
    type: 'metric',
    key: key,
    value: value,
    percent: percent,
    detail: detail || '',
    resetAt: resetAt || 0,
    severity: severity
  };
}

function blockSection(key, body) {
  return { type: 'block', key: key, body: body };
}

// ---------------------------------------------------------------------------
// Money helpers
// ---------------------------------------------------------------------------

function parseMoney(value) {
  if (typeof value === 'number')
    return isFinite(value) ? value : null;
  var n = Number(String(value === null || value === undefined ? '' : value).replace(/,/g, '.'));
  return isFinite(n) ? n : null;
}

function formatMoney(n, currency) {
  var fixed = (Math.round(n * 100) / 100).toFixed(2);
  if (currency === 'USD')
    return '$' + fixed;
  if (currency && currency !== '')
    return fixed + ' ' + currency;
  return fixed;
}

// ---------------------------------------------------------------------------
// validUntil helpers (manual field — APIs do not expose plan end dates)
// ---------------------------------------------------------------------------

// Strict YYYY-MM-DD → epoch ms, or null. Range-checked by round-trip.
function parseValidUntilDate(s) {
  if (typeof s !== 'string')
    return null;
  var m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m)
    return null;
  var y = Number(m[1]), mo = Number(m[2]), d = Number(m[3]);
  if (mo < 1 || mo > 12 || d < 1 || d > 31)
    return null;
  var t = Date.UTC(y, mo - 1, d);
  var dt = new Date(t);
  if (dt.getUTCMonth() !== mo - 1 || dt.getUTCDate() !== d)
    return null;
  return t;
}

// Whole days until the date; 0 when already past; null when not set/invalid.
function daysLeft(validUntil, nowMs) {
  var t = parseValidUntilDate(validUntil);
  if (t === null)
    return null;
  var d = Math.floor((t - nowMs) / 86400000);
  return d > 0 ? d : 0;
}

function isExpiringSoon(days) {
  return days !== null && days !== undefined && days >= 0 && days <= 7;
}

function newProviderId(type, existingIds) {
  var n = 1;
  var ids = existingIds || [];
  while (ids.indexOf(type + '_' + n) >= 0)
    n++;
  return type + '_' + n;
}

// ---------------------------------------------------------------------------
// Settings migration (v0.2 single key → v0.3 provider list)
// ---------------------------------------------------------------------------

function defaultProviderFields(p) {
  return {
    id: String(p.id || ''),
    type: String(p.type || 'zai'),
    apiKey: String(p.apiKey || ''),
    label: String(p.label || ''),
    planLabel: String(p.planLabel || ''),
    validUntil: String(p.validUntil || ''),
    enabled: p.enabled !== false
  };
}

function migrateSettings(settings) {
  var s = settings || {};
  var out = {
    providers: [],
    activeProviderId: '',
    refreshMinutes: 5,
    showBackground: s.showBackground !== undefined ? s.showBackground : true
  };
  var m = Number(s.refreshMinutes);
  out.refreshMinutes = isFinite(m) && m >= 1 && m <= 60 ? Math.round(m) : 5;

  if (Array.isArray(s.providers)) {
    for (var i = 0; i < s.providers.length; i++) {
      var p = defaultProviderFields(s.providers[i] || {});
      if (p.id !== '' && p.apiKey !== '')
        out.providers.push(p);
    }
    out.activeProviderId = String(s.activeProviderId || '');
    if (out.activeProviderId === '' && out.providers.length > 0)
      out.activeProviderId = out.providers[0].id;
    return out;
  }

  // Legacy v0.2: single apiKey
  if (s.apiKey) {
    var legacy = defaultProviderFields({ id: 'zai_1', type: 'zai', apiKey: s.apiKey });
    out.providers.push(legacy);
    out.activeProviderId = legacy.id;
  }
  return out;
}

// ---------------------------------------------------------------------------
// z.ai adapter
// ---------------------------------------------------------------------------

function findLimit(limits, type) {
  if (!limits)
    return null;
  for (var i = 0; i < limits.length; i++) {
    if (limits[i] && String(limits[i].type || '') === type)
      return limits[i];
  }
  return null;
}

// Kept as a public v0.2 entry point (tests + Main.qml v0.2 parity).
function parseQuota(doc, nowMs) {
  return PROVIDERS.zai.parse({ main: doc }, nowMs);
}

function parseZai(responses, nowMs) {
  var doc = responses.main;
  if (!doc || typeof doc !== 'object')
    return { ok: false, error: 'empty response' };
  var data = doc.data;
  if (!data || typeof data !== 'object') {
    var apiMsg = doc.msg || doc.message || doc.error;
    return apiMsg ? { ok: false, error: safeText(String(apiMsg), 200) } : { ok: false, error: 'unexpected response shape' };
  }
  var limits = Array.isArray(data.limits) ? data.limits : [];
  var session = findLimit(limits, 'TOKENS_LIMIT');
  var weekly = findLimit(limits, 'TIME_LIMIT');
  var sections = [];

  if (session) {
    var sPct = finitePercent(session.percentage);
    sections.push(metric('session', sPct === null ? '' : String(sPct) + '%', sPct, '',
                         finiteInt(session.nextResetTime), severityOf(sPct)));
  }
  if (weekly) {
    var wPct = finitePercent(weekly.percentage);
    var used = weekly.currentValue !== undefined ? finiteInt(weekly.currentValue) : null;
    var cap = weekly.usage !== undefined ? finiteInt(weekly.usage) : null;
    var value = '';
    if (used !== null && cap !== null && cap > 0)
      value = used + ' / ' + cap;
    else if (used !== null)
      value = String(used);
    sections.push(metric('weekly', value, wPct,
                         weekly.remaining !== undefined ? String(finiteInt(weekly.remaining)) : '',
                         finiteInt(weekly.nextResetTime), severityOf(wPct)));
    var details = weekly.usageDetails;
    if (Array.isArray(details) && details.length > 0) {
      var body = [];
      for (var d = 0; d < details.length && d < 32; d++) {
        var row = details[d];
        if (row)
          body.push(safeText(row.modelCode, 60) + ' · ' + finiteInt(row.usage));
      }
      if (body.length > 0)
        sections.push(blockSection('tools', body));
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
// DeepSeek adapter (balance only — no window/percent; thresholds ×7 for CNY)
// ---------------------------------------------------------------------------

function parseDeepseek(responses, nowMs) {
  var doc = responses.main;
  if (!doc || typeof doc !== 'object')
    return { ok: false, error: 'empty response' };
  var infos = Array.isArray(doc.balance_infos) ? doc.balance_infos : [];
  if (infos.length === 0 || !infos[0])
    return { ok: false, error: 'no balance info' };
  var info = infos[0];
  var currency = String(info.currency || '');
  var total = parseMoney(info.total_balance);
  if (total === null)
    return { ok: false, error: 'unparseable balance' };

  var thresholds = currency === 'USD' ? { critical: 1, high: 5, mid: 20 } : { critical: 7, high: 35, mid: 140 };
  var severity = 'low';
  if (doc.is_available === false)
    severity = 'critical';
  else if (total <= thresholds.critical)
    severity = 'critical';
  else if (total <= thresholds.high)
    severity = 'high';
  else if (total <= thresholds.mid)
    severity = 'mid';

  var sections = [metric('balance', formatMoney(total, currency), null, '', 0, severity)];
  var granted = parseMoney(info.granted_balance);
  var topped = parseMoney(info.topped_up_balance);
  if (granted !== null || topped !== null) {
    var body = [];
    if (granted !== null)
      body.push('granted ' + formatMoney(granted, currency));
    if (topped !== null)
      body.push('topped up ' + formatMoney(topped, currency));
    sections.push(blockSection('breakdown', body));
  }
  return {
    ok: true,
    entry: {
      id: 'deepseek',
      label: 'DeepSeek',
      plan: '',
      status: doc.is_available === false ? 'error' : 'ready',
      error: doc.is_available === false ? 'account unavailable' : '',
      fetchedAt: nowMs,
      sections: sections
    }
  };
}

// ---------------------------------------------------------------------------
// OpenRouter adapter (credits + key, two requests combined)
// ---------------------------------------------------------------------------

function parseOpenrouter(responses, nowMs) {
  var cr = responses.credits && responses.credits.data ? responses.credits.data : null;
  var ky = responses.key && responses.key.data ? responses.key.data : null;
  if (!cr)
    return { ok: false, error: 'credits unavailable' };
  var total = parseMoney(cr.total_credits);
  var used = parseMoney(cr.total_usage);
  if (total === null)
    return { ok: false, error: 'unparseable credits' };
  if (used === null)
    used = 0;

  var balance = total - used;
  var consumedPct = total > 0 ? Math.round((used / total) * 100) : null;
  var severity = balance < 0 ? 'critical' : severityOf(consumedPct === null ? 0 : consumedPct);

  var sections = [metric('balance', formatMoney(balance, 'USD'), consumedPct,
                         'of ' + formatMoney(total, 'USD'), 0, severity)];
  var body = [];
  if (ky) {
    if (ky.label)
      body.push(safeText(ky.label, 60));
    if (ky.usage !== undefined && ky.usage !== null)
      body.push('usage ' + formatMoney(parseMoney(ky.usage) || 0, 'USD'));
    if (ky.is_free_tier !== undefined)
      body.push(ky.is_free_tier === true ? 'free tier' : 'paid');
    if (ky.rate_limit && ky.rate_limit.requests !== undefined)
      body.push('rate ' + finiteInt(ky.rate_limit.requests) + '/'
                + safeText(ky.rate_limit.interval || '', 12));
  }
  if (body.length > 0)
    sections.push(blockSection('key', body));

  return {
    ok: true,
    entry: {
      id: 'openrouter',
      label: 'OpenRouter',
      plan: ky && ky.is_free_tier === true ? 'free' : '',
      status: 'ready',
      error: '',
      fetchedAt: nowMs,
      sections: sections
    }
  };
}

// ---------------------------------------------------------------------------
// Kimi adapter (undocumented; hunt fields tolerantly, never throw)
// ---------------------------------------------------------------------------

function kimiFirstObject(d, names) {
  for (var i = 0; i < names.length; i++) {
    var v = d[names[i]];
    if (v && typeof v === 'object' && !Array.isArray(v))
      return v;
  }
  return null;
}

function kimiReadWindow(d, names, flatPrefixes) {
  var obj = kimiFirstObject(d, names);
  var src = obj || d;
  var pick = function (fieldNames) {
    for (var i = 0; i < fieldNames.length; i++) {
      if (src[fieldNames[i]] !== undefined && src[fieldNames[i]] !== null)
        return src[fieldNames[i]];
    }
    return undefined;
  };
  var limit = parseMoney(pick(['limit', 'quota', 'total']));
  var used = parseMoney(pick(['used', 'currentValue', 'usage']));
  var remaining = parseMoney(pick(['remaining', 'left']));
  var resetRaw = pick(['reset_at', 'resetAt', 'reset_time', 'resetTime', 'nextResetTime']);
  var pct = finitePercent(pick(['percentage', 'percent']));

  var resetAt = 0;
  if (typeof resetRaw === 'number')
    resetAt = resetRaw < 1e12 ? Math.round(resetRaw * 1000) : Math.round(resetRaw);
  else if (typeof resetRaw === 'string') {
    var t = Date.parse(resetRaw);
    resetAt = isFinite(t) ? Math.round(t) : 0;
  }
  if (limit !== null && used !== null && limit > 0)
    pct = Math.max(0, Math.min(100, Math.round((used / limit) * 100)));
  var detail = '';
  if (used !== null && limit !== null && limit > 0)
    detail = finiteInt(used) + ' / ' + finiteInt(limit);
  else if (remaining !== null)
    detail = '−' + finiteInt(remaining);
  return { limit: limit, used: used, percent: pct, resetAt: resetAt, detail: detail };
}

function parseKimi(responses, nowMs) {
  var doc = responses.main;
  if (!doc || typeof doc !== 'object')
    return { ok: false, error: 'empty response' };
  var d = doc.data && typeof doc.data === 'object' ? doc.data : doc;

  var plan = safeText(d.plan !== undefined ? d.plan : d.level, 40) || '';
  var win = kimiReadWindow(d, ['window', 'five_hour_window', 'session_window', 'fiveHourWindow', 'session'],
                           ['window', 'session']);
  var week = kimiReadWindow(d, ['weekly', 'weekly_window', 'week'], ['weekly']);

  var sections = [];
  if (win.percent !== null)
    sections.push(metric('session', String(win.percent) + '%', win.percent, win.detail,
                         win.resetAt, severityOf(win.percent)));
  if (week.percent !== null)
    sections.push(metric('weekly', String(week.percent) + '%', week.percent, week.detail,
                         week.resetAt, severityOf(week.percent)));

  return {
    ok: true,
    entry: {
      id: 'kimi',
      label: 'Kimi',
      plan: plan,
      status: sections.length > 0 ? 'ready' : 'empty',
      error: '',
      fetchedAt: nowMs,
      sections: sections
    }
  };
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

var PROVIDERS = {
  zai: {
    name: 'z.ai',
    monogram: 'Z',
    color: '#fff59b',
    requests: [{
      id: 'main',
      url: 'https://api.z.ai/api/monitor/usage/quota/limit',
      headers: function (key) {
        return { 'Authorization': 'Bearer ' + key, 'Accept-Language': 'en-US,en' };
      }
    }],
    parse: parseZai
  },
  deepseek: {
    name: 'DeepSeek',
    monogram: 'DS',
    color: '#4D6BFE',
    requests: [{
      id: 'main',
      url: 'https://api.deepseek.com/user/balance',
      headers: function (key) {
        return { 'Authorization': 'Bearer ' + key, 'Accept-Language': 'en-US,en' };
      }
    }],
    parse: parseDeepseek
  },
  openrouter: {
    name: 'OpenRouter',
    monogram: 'OR',
    color: '#8B5CF6',
    requests: [
      {
        id: 'credits',
        url: 'https://openrouter.ai/api/v1/credits',
        headers: function (key) {
          return { 'Authorization': 'Bearer ' + key };
        }
      },
      {
        id: 'key',
        url: 'https://openrouter.ai/api/v1/key',
        headers: function (key) {
          return { 'Authorization': 'Bearer ' + key };
        }
      }
    ],
    parse: parseOpenrouter
  },
  kimi: {
    name: 'Kimi',
    monogram: 'K',
    color: '#22D3EE',
    requests: [{
      id: 'main',
      url: 'https://api.kimi.com/coding/v1/usages',
      headers: function (key) {
        return { 'Authorization': 'Bearer ' + key, 'Accept-Language': 'en-US,en' };
      }
    }],
    parse: parseKimi
  }
};
