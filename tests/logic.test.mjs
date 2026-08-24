// logic.test.mjs — zero-dependency test harness for Logic.js (v0.3).
//
// Run: node tests/logic.test.mjs
// RED phase: this file is written BEFORE Logic.js v2 exists (TDD).
//
// The runner strips the `.pragma library` directive (QML-only) and evals the
// source, mirroring how Quickshell loads it. No imports from Logic.js exist
// on disk yet — loading must fail loudly in RED and pass in GREEN.

import { readFileSync } from 'node:fs';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const results = { pass: 0, fail: 0, failures: [] };

function test(name, fn) {
  try {
    fn();
    results.pass++;
    console.log(`  ok  ${name}`);
  } catch (e) {
    results.fail++;
    results.failures.push({ name, e });
    console.log(`FAIL  ${name}\n      ${e.message}`);
  }
}

import { strict as assert } from 'node:assert';
const { equal, ok, notEqual } = assert;

function fixture(name) {
  return JSON.parse(readFileSync(new URL(`./fixtures/${name}.json`, import.meta.url), 'utf8'));
}

// ---------------------------------------------------------------------------
// Load Logic.js
// ---------------------------------------------------------------------------

function loadLogic() {
  const src = readFileSync(new URL('../Logic.js', import.meta.url), 'utf8')
    .replace('.pragma library', '');
  const exportsList = [
    'PROVIDERS', 'parseMoney', 'formatMoney', 'migrateSettings',
    'parseValidUntilDate', 'daysLeft', 'isExpiringSoon', 'newProviderId',
    'severityOf', 'sectionByKey', 'formatDuration', 'remainingMs',
    'safeText', 'finitePercent',
  ];
  const factory = (0, eval)(`(function(){${src}\n; return {${exportsList.join(',')}};})()`);
  for (const name of exportsList)
    if (factory[name] === undefined)
      throw new Error(`Logic.js does not export "${name}"`);
  return factory;
}

let Logic;
try {
  Logic = loadLogic();
  console.log('loaded Logic.js v2 OK\n');
} catch (e) {
  console.log(`LOGIC LOAD FAILED (RED phase expected): ${e.message}\n`);
  console.log(`1..0 # ${e.message}`);
  process.exit(1);
}

const NOW = Date.UTC(2026, 7, 24, 12, 0, 0); // 2026-08-24T12:00:00Z fixed clock

// ---------------------------------------------------------------------------
// Registry shape
// ---------------------------------------------------------------------------

test('registry exposes the 4 v0.3 providers', () => {
  for (const key of ['zai', 'deepseek', 'openrouter', 'kimi'])
    ok(Logic.PROVIDERS[key], `missing provider "${key}"`);
});

test('each provider has identity + requests + parse', () => {
  for (const [key, p] of Object.entries(Logic.PROVIDERS)) {
    equal(typeof p.name, 'string', `${key}.name`);
    ok(p.monogram.length >= 1 && p.monogram.length <= 2, `${key}.monogram 1-2 chars`);
    ok(p.color.startsWith('#'), `${key}.color hex`);
    ok(Array.isArray(p.requests) && p.requests.length >= 1, `${key}.requests`);
    for (const r of p.requests) {
      ok(r.id, `${key}.requests[].id`);
      ok(r.url.startsWith('https://'), `${key}.requests[].url https`);
      equal(typeof p.parse, 'function', `${key}.parse`);
    }
  }
});

test('provider requests build Authorization headers from the key', () => {
  for (const [, p] of Object.entries(Logic.PROVIDERS)) {
    const h = p.requests[0].headers('SECRET_KEY');
    ok(String(h.Authorization).includes('SECRET_KEY'), `${p.name} carries the key`);
  }
});

// ---------------------------------------------------------------------------
// z.ai adapter (live fixture — must stay compatible with v0.2 behaviour)
// ---------------------------------------------------------------------------

test('zai: parses live quota fixture', () => {
  const r = Logic.PROVIDERS.zai.parse({ main: fixture('zai') }, NOW);
  ok(r.ok, 'parse ok');
  const e = r.entry;
  equal(e.plan, 'pro');
  equal(e.status, 'ready');
  const s = Logic.sectionByKey(e, 'session');
  equal(s.percent, 54);
  equal(s.severity, 'mid');
  equal(s.resetAt, 1787598456843);
  const w = Logic.sectionByKey(e, 'weekly');
  equal(w.value, '92 / 1000');
  const t = Logic.sectionByKey(e, 'tools');
  equal(t.body.length, 3);
  ok(t.body[0].includes('search-prime'));
});

test('zai: error wrapper degrades to {ok:false}', () => {
  const r = Logic.PROVIDERS.zai.parse({ main: { code: 500, msg: '404 NOT_FOUND' } }, NOW);
  ok(!r.ok);
  equal(r.error, '404 NOT_FOUND');
});

// ---------------------------------------------------------------------------
// DeepSeek adapter (balance, no window)
// ---------------------------------------------------------------------------

test('deepseek: CNY balance maps to money metric + severity thresholds', () => {
  const r = Logic.PROVIDERS.deepseek.parse({ main: fixture('deepseek_cny') }, NOW);
  ok(r.ok);
  const b = Logic.sectionByKey(r.entry, 'balance');
  ok(b.value.includes('110.00'), `value "${b.value}" contains amount`);
  ok(b.value.includes('CNY'), 'value carries currency');
  equal(b.percent, null, 'balance vendors have no percent');
  // 110 CNY sits in the mid band (7 critical / 35 high / 140 mid)
  equal(b.severity, 'mid');
  const breakdown = Logic.sectionByKey(r.entry, 'breakdown');
  ok(breakdown && breakdown.body.some(l => l.includes('10.00')), 'granted in breakdown');
});

test('deepseek: USD low balance is high severity', () => {
  const r = Logic.PROVIDERS.deepseek.parse({ main: fixture('deepseek_usd') }, NOW);
  const b = Logic.sectionByKey(r.entry, 'balance');
  // 3.50 USD: 1 critical / 5 high / 20 mid
  equal(b.severity, 'high');
});

test('deepseek: !is_available is critical', () => {
  const doc = fixture('deepseek_usd');
  doc.is_available = false;
  const r = Logic.PROVIDERS.deepseek.parse({ main: doc }, NOW);
  const b = Logic.sectionByKey(r.entry, 'balance');
  equal(b.severity, 'critical');
});

// ---------------------------------------------------------------------------
// OpenRouter adapter (credits + key, combined)
// ---------------------------------------------------------------------------

test('openrouter: combines credits+key into balance metric', () => {
  const r = Logic.PROVIDERS.openrouter.parse(
    { credits: fixture('openrouter_credits'), key: fixture('openrouter_key') }, NOW);
  ok(r.ok);
  const b = Logic.sectionByKey(r.entry, 'balance');
  equal(b.value, '$74.50');
  equal(b.percent, 26, 'consumed = 25.5/100 rounded');
  equal(b.severity, 'low');
  const meta = Logic.sectionByKey(r.entry, 'key');
  ok(meta.body.some(l => l.includes('sk-or-main')), 'key label in meta');
});

// ---------------------------------------------------------------------------
// Kimi adapter (tolerant window/weekly)
// ---------------------------------------------------------------------------

test('kimi: window + weekly metrics with RFC3339 resets', () => {
  const r = Logic.PROVIDERS.kimi.parse({ main: fixture('kimi') }, NOW);
  ok(r.ok);
  equal(r.entry.plan, 'kimi-pro');
  const s = Logic.sectionByKey(r.entry, 'session');
  equal(s.percent, 75, 'used 75/100');
  equal(s.severity, 'high');
  equal(s.resetAt, Date.parse('2026-08-24T22:00:00Z'));
  const w = Logic.sectionByKey(r.entry, 'weekly');
  equal(w.percent, 20);
  equal(w.severity, 'low');
});

test('kimi: unknown field layout degrades, never throws', () => {
  const r = Logic.PROVIDERS.kimi.parse({ main: { data: { something: 'else' } } }, NOW);
  ok(r.ok, 'tolerant parse still resolves');
  ok(!Logic.sectionByKey(r.entry, 'session'));
});

// ---------------------------------------------------------------------------
// Settings migration (v0.2 → v0.3)
// ---------------------------------------------------------------------------

test('migration: legacy single apiKey becomes providers[0]', () => {
  const m = Logic.migrateSettings({ apiKey: 'legacy-key', refreshMinutes: 5, showWeekly: true });
  equal(m.providers.length, 1);
  equal(m.providers[0].type, 'zai');
  equal(m.providers[0].apiKey, 'legacy-key');
  equal(m.providers[0].enabled, true);
  equal(m.activeProviderId, m.providers[0].id);
  equal(m.refreshMinutes, 5);
});

test('migration: no legacy key → empty providers', () => {
  const m = Logic.migrateSettings({ refreshMinutes: 10 });
  equal(m.providers.length, 0);
  ok(!m.activeProviderId);
});

test('migration: already v0.3 passes through untouched', () => {
  const current = {
    providers: [{ id: 'zai_1', type: 'zai', apiKey: 'k', label: '', planLabel: '', validUntil: '', enabled: true }],
    activeProviderId: 'zai_1',
    refreshMinutes: 5,
  };
  const m = Logic.migrateSettings(JSON.parse(JSON.stringify(current)));
  equal(m.providers[0].id, 'zai_1');
  equal(m.activeProviderId, 'zai_1');
});

// ---------------------------------------------------------------------------
// validUntil helpers
// ---------------------------------------------------------------------------

test('parseValidUntilDate accepts YYYY-MM-DD only', () => {
  equal(Logic.parseValidUntilDate('2026-09-15'), Date.UTC(2026, 8, 15));
  equal(Logic.parseValidUntilDate('15.09.2026'), null);
  equal(Logic.parseValidUntilDate(''), null);
  equal(Logic.parseValidUntilDate('2026-13-99'), null);
});

test('daysLeft: 22 days ahead; clamped at 0 when past', () => {
  equal(Logic.daysLeft('2026-09-15', Date.UTC(2026, 7, 24)), 22);
  equal(Logic.daysLeft('2026-08-01', Date.UTC(2026, 7, 24)), 0);
});

test('isExpiringSoon: true at ≤7 days', () => {
  equal(Logic.isExpiringSoon(7), true);
  equal(Logic.isExpiringSoon(8), false);
});

test('newProviderId avoids collisions', () => {
  equal(Logic.newProviderId('zai', ['zai_1']), 'zai_2');
  equal(Logic.newProviderId('kimi', ['kimi_1', 'kimi_2']), 'kimi_3');
  equal(Logic.newProviderId('openrouter', []), 'openrouter_1');
});

// ---------------------------------------------------------------------------
// Money helpers
// ---------------------------------------------------------------------------

test('parseMoney: strings and numbers, garbage rejected', () => {
  equal(Logic.parseMoney('110.00'), 110);
  equal(Logic.parseMoney(3.5), 3.5);
  equal(Logic.parseMoney('nope'), null);
});

test('formatMoney: USD symbol prefix, CNY suffix', () => {
  equal(Logic.formatMoney(74.5, 'USD'), '$74.50');
  equal(Logic.formatMoney(110, 'CNY'), '110.00 CNY');
});

// ---------------------------------------------------------------------------
// Preserved v0.2 utilities
// ---------------------------------------------------------------------------

test('severityOf bands 50/75/90', () => {
  equal(Logic.severityOf(10), 'low');
  equal(Logic.severityOf(50), 'mid');
  equal(Logic.severityOf(75), 'high');
  equal(Logic.severityOf(90), 'critical');
  equal(Logic.severityOf('x'), 'low');
});

test('formatDuration and safeText survive the port', () => {
  equal(Logic.formatDuration(4980000, 'h', 'm'), '1h 23m');
  ok(!Logic.safeText('<img>', 50).includes('<'));
});

// ---------------------------------------------------------------------------

console.log(`\n${results.pass} passed, ${results.fail} failed`);
process.exit(results.fail === 0 ? 0 : 1);
