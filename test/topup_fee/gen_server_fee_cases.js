'use strict';
// حالات «الفائدة» من وحدة الخادم الحيّة نفسها (managerTopupFees.js) — التطبيق يُفحص عليها (لا حسابٌ مكتوبٌ باليد).
const fs = require('node:fs');
const src = fs.readFileSync(process.argv[2], 'utf8');
const m = { exports: {} };
const stub = { parseSetting: () => ({}), enabledFor: () => false, createSettings: () => ({}) };
new Function('require', 'module', 'exports', src)((p) => (p === './deletedDebts' ? stub : require(p)), m, m.exports);
const F = m.exports;
const specs = [
  ['percent', 2, 100000], ['percent', 2.5, 33333], ['percent', 1.5, 100001], ['percent', 0.01, 50], ['percent', 0.01, 49],
  ['percent', 100, 5000], ['percent', 12.34, 77777], ['percent', 3, 5000], ['fixed', 500, 25000], ['fixed', 2000.5, 100000],
  ['fixed', 25000, 25000], ['percent', 0.5, 999], ['percent', 7, 1234567],
];
const cases = specs.map(([kind, value, base]) => {
  const p = F.parseFee({ kind, value });
  const amount = p.ok && p.fee ? F.feeAmountFor(p.fee, base) : null;
  return { kind, value, base, ok: p.ok, amount, label: p.ok && p.fee ? F.feeLabel(p.fee, amount) : null };
});
const raws = ['2', '2.5', '٢٫٥', '۲.۵', '1,000', '٥٬٠٠٠', ' 3 ', '2.555', '-1', 'abc', '', '0', '1e3', '.5', '5.'];
const values = raws.map((r) => ({ raw: r, value: F.valueOf(r) }));
const bad = [{ kind: 'percent', value: 101 }, { kind: 'percent', value: 0 }, { kind: 'bonus', value: 2 }, { kind: 'fixed', value: -5 }]
  .map((f) => ({ ...f, ...(({ ok, code }) => ({ ok, code }))(F.parseFee(f)) }));
process.stdout.write(JSON.stringify({ meta: { from: 'server/managerTopupFees.js (live)', max_percent: F.MAX_PERCENT }, cases, values, bad }, null, 1));
