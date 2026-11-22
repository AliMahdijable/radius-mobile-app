// حالاتٌ مولَّدة + ناتج كود الموقع نفسه عليها ⇒ test/debts_import/parity_cases.json (التطبيق يقارن نقله بها حرفاً).
const fs = require('fs');
const path = require('path');
const WEB = process.env.WEB;
const Module = require('module');
// xlsx من node_modules الموقع
const origResolve = Module._resolveFilename;
Module._resolveFilename = function (req, ...a) {
  if (req === 'xlsx') return require.resolve(path.join(WEB, 'node_modules/xlsx'));
  return origResolve.call(this, req, ...a);
};
const pdf = require(__dirname + '/out/debts-pdf.js');
const mt = require(__dirname + '/out/debts-match.js');
const hz = require(__dirname + '/out/harness.js');
const XLSX = require(path.join(WEB, 'node_modules/xlsx'));

let seed = 20261123;
const rnd = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const pick = (a) => a[Math.floor(rnd() * a.length)];
const chance = (p) => rnd() < p;

// ─── المفردات ───
const FIRST = ['علي', 'محمد', 'حسين', 'حسن', 'أحمد', 'مصطفى', 'عباس', 'زينب', 'فاطمة', 'مريم', 'عبد الله', 'عبدالله', 'أبو علي', 'ام حسين', 'سجاد', 'كرار', 'حيدر', 'رقية', 'نور الهدى', 'إسراء', 'آية', 'مؤمل', 'ضياء', 'عيسى', 'هدى'];
const LAST = ['الموسوي', 'كاظم', 'جاسم', 'عبد الأمير', 'الحسيني', 'التميمي', 'سالم', 'رضا', 'محمد', 'علي', 'نعمة', 'جواد', 'طالب', 'الشمري', 'العبيدي', 'الزبيدي', ''];
const PRES = { 'م': 'ﻣ', 'ح': 'ﺤ', 'د': 'ﺪ', 'ع': 'ﻋ', 'ل': 'ﻠ', 'ي': 'ﻲ', 'س': 'ﺳ', 'ن': 'ﻦ', 'ا': 'ﺎ', 'ه': 'ﻫ', 'ر': 'ﺮ', 'ب': 'ﺑ' };
function decorate(name) {
  let s = name;
  if (chance(0.15)) s = [...s].map((c) => (PRES[c] && chance(0.6) ? PRES[c] : c)).join(''); // أشكال عرض كـPDF
  if (chance(0.1)) s = s.replace(/ا/, 'ـا'); // تطويل
  if (chance(0.1)) s = '‏' + s + '‬'; // علامات اتّجاه
  if (chance(0.1)) s = s.replace(/ /g, '  ');
  if (chance(0.1)) s = s + 'ُ'; // تشكيل
  if (chance(0.08)) s = s.replace('ة', 'ه').replace('أ', 'ا').replace('ي', 'ى');
  if (chance(0.05)) s = 'لا' + 'ﻻ' + s; // ligature لا
  return s;
}
const fullName = () => `${pick(FIRST)} ${pick(LAST)}`.trim();
function phoneVariant(p) {
  // p = 07XXXXXXXXX
  const local = p.slice(1);
  const v = [p, '964' + local, '+964 ' + local, '00964' + local, local, p.replace(/(\d{4})(\d{3})(\d{4})/, '$1 $2 $3'), p.split('').map((d) => '٠١٢٣٤٥٦٧٨٩'[+d]).join(''), p.split('').map((d) => '۰۱۲۳۴۵۶۷۸۹'[+d]).join('')];
  return pick(v);
}
const newPhone = () => '07' + pick(['7', '8', '5', '9']) + Array.from({ length: 8 }, () => Math.floor(rnd() * 10)).join('');

// ─── ١) التطبيع ───
const texts = [];
for (let i = 0; i < 250; i++) texts.push(decorate(fullName()));
// تركيب الهمزة والمدّة وترتيب الحركات (NFKC)
for (const base of ['ا', 'و', 'ي', 'ە', 'ہ', 'ے', 'ه', 'ب']) for (const mk of ['\u0653', '\u0654', '\u0655']) for (const h of ['', '\u064E', '\u0651', '\u0651\u064E', '\u0670']) {
  texts.push(base + mk + h, base + h + mk, 'م' + base + h + mk + 'د', base + mk + mk, base + '\u0655' + mk);
}
texts.push('آَ', 'أُ', 'إِ', 'ئِّ', 'ؤْ', 'ﺁ', 'ﺃ', 'ﺅ', 'ﺇ', 'ﺉ', 'ﺋ', 'ﺌ', 'ﺊ', 'ﮤ', 'ﮥ', 'ﮰ', 'ﮱ');
texts.push('', '   ', 'ali.k@sn', 'ABC Def', 'ـــ', 'ﻻ إله', 'ﷲ', 'ﷺ', 'ﺍﻟﻤﺠﻤﻮﻉ', '１２３ＡＢＣ', 'x y', 'ك', 'ک', 'ی', 'ۀ', 'هٔ', 'آ', 'ؤ', 'abc-def_ghi.jkl', 'سيد علي', 'ابو الحسن', 'حجي عباس');
const normalize = texts.map((t) => ({ in: t, clean: pdf.cleanText(t), fold: pdf.foldArabic(t), words: mt.nameWords(t) }));

// ─── ٢) الهواتف ───
const phones = [];
for (let i = 0; i < 150; i++) phones.push(phoneVariant(newPhone()));
phones.push('', '123', '07701', '7701234567', '9647701234567', '009647701234567', '+9647701234567', '964 770 123 4567', '0770-123-4567', '(0770) 123 4567', 'tel: 0770 123 4567', '١٢٣٤٥٦٧', '96412345678901', '964770123456');
const phoneOut = phones.map((p) => ({ in: p, out: pdf.normalizePhone(p) }));

// ─── ٣) العناوين ───
const heads = ['username', 'amount', 'الاسم', 'رقم الهاتف', 'الباقة', 'تاريخ النفاذ', 'اسم المستخدم', 'اليوزر', 'الدين', 'الديون', 'المبلغ', 'المتبقي', 'المدفوع', 'المسدد', 'تسديد', 'Paid', 'Debt', 'Amount Due', 'Phone', 'Mobile', 'tel', 'Tel.', 'الهاتف', 'موبايل', 'جوال', '#', 'ت', 'م', 'No.', 'N', 'ر.م', 'تسلسل', 'التسلسل', 'سعر الإشتراك', 'السعر', 'Price', 'الخدمة', 'Profile', 'Package', 'Plan', 'تاريخ الانتهاء', 'Expiry', 'expiration', 'اسم المشترك', 'المشترك', 'Name', 'Customer', 'login', 'User Name', 'اسم الدخول', 'مديونية', 'الدين المتبقي', '', '  ', 'ملاحظات', 'ﺍﻻﺳﻢ', 'ﺍﻟﺪﻳﻦ', 'رقم', 'المديونيه'];
const headOut = heads.map((h) => ({ in: h, out: pdf.classifyHeader(h) }));

// ─── ٤) المبالغ ───
const amounts = ['25000', '25,000', '٢٥٠٠٠', '۲۵۰۰۰', '٢٥,٠٠٠', '25،000', '25٬000', '-25000', '(25000)', '25000 د.ع', 'IQD 25000', '25.5', '25,000.75', '', 'لا شيء', '0', '0.4', '1', ' 3 000 ', 'abc12def34', '12.34.56', '1e5', '٣٥٠٠٠ دينار', '-', '..5', '0007', '99999999999999999999999', 'x-5y'];
for (let i = 0; i < 60; i++) amounts.push(String(Math.floor(rnd() * 500000)) + pick(['', ' د.ع', ',000', '.5', ' IQD']));
const amountOut = amounts.map((a) => ({ in: a, out: (() => { const v = hz.parseAmountCell(a); return Number.isFinite(v) ? v : null; })() }));

// ─── ٥) CSV ───
const csvs = [
  'username,amount\nali,25000\nzainab,"30,000"\n',
  'sep=;\nusername;amount\nali;25000\n',
  '﻿sep=;\r\nusername;amount\r\nali;25 000\r\n',
  'username;amount;الاسم\nali;"25,000";"علي ""الكبير"""\n\n\nmo;0;x\n',
  'a\tb\n1\t2\n',
  '"x,y",z\n"multi\nline",2\n',
  '',
  ',,,\n,,\n',
  'username,amount\r\nali,1\r\n',
  'one cell only',
  'q"uote,b\nc,d',
  '"unterminated,1\n2,3',
];
const csvOut = csvs.map((c) => ({ in: c, out: hz.parseCsv(c) }));

// ─── ٦) جداولٌ ⇒ صفوف (العناوين) ───
const tables = [
  [['username', 'amount', 'الاسم', 'رقم الهاتف'], ['ali1', '25000', 'علي', '07701234567'], ['', '30,000', 'زينب', '07801234567']],
  [['اسم المستخدم', 'الدين'], ['ali1', '٢٥٠٠٠']],
  [['ali1', '25000'], ['zainab', '30000']],
  [['الاسم', 'الهاتف', 'الدين', 'المدفوع'], ['علي حسن', '0770 123 4567', '25,000', '10,000']],
  [['#', 'المشترك', 'المديونية', 'موبايل'], ['1', 'حسين', '15000', '9647701112233']],
  [['name', 'amount']],
  [['username', 'paid'], ['ali', '5000']],
  [['phone', 'debt'], ['07701234567', '5000'], ['', '']],
];
const tableOut = tables.map((t) => ({ in: t, out: hz.tableRows(t).map((r) => ({ username: r.username, amount: Number.isFinite(r.amount) ? r.amount : null, phone: r.phone, name: r.name })) }));

// ─── ٧) المطابقة: مشتركون + صفوف ───
const scenarios = [];
for (let sc = 0; sc < 160; sc++) {
  const subs = [];
  const n = 3 + Math.floor(rnd() * 25);
  const sharedPhone = newPhone();
  for (let i = 0; i < n; i++) {
    const nm = fullName().split(' ');
    subs.push({
      username: chance(0.1) ? '' : `u${sc}_${i}${chance(0.2) ? '@SN' : ''}`,
      phone: chance(0.15) ? '' : chance(0.12) ? sharedPhone : chance(0.5) ? phoneVariant(newPhone()) : newPhone(),
      firstname: chance(0.1) ? '' : nm[0],
      lastname: nm.slice(1).join(' '),
    });
  }
  const rows = [];
  const m = 2 + Math.floor(rnd() * 20);
  for (let j = 0; j < m; j++) {
    const s = pick(subs);
    const kind = rnd();
    const amount = chance(0.08) ? (chance(0.5) ? 0 : chance(0.5) ? NaN : 0.5) : Math.floor(rnd() * 100000) + 1;
    if (kind < 0.35 && s.username) {
      rows.push({ username: chance(0.3) ? s.username.toUpperCase() : chance(0.2) ? ` ${s.username} ` : s.username, phone: '', name: '', amount });
    } else if (kind < 0.45) {
      rows.push({ username: 'nobody' + j, phone: '', name: '', amount });
    } else if (kind < 0.85 && s.phone) {
      const nm = chance(0.25) ? fullName() : chance(0.2) ? '' : decorate(`${s.firstname} ${s.lastname}`);
      rows.push({ username: '', phone: phoneVariant(require(__dirname + '/out/debts-pdf.js').normalizePhone(s.phone) || newPhone()), name: nm, amount });
    } else if (kind < 0.92) {
      rows.push({ username: '', phone: chance(0.5) ? sharedPhone : newPhone(), name: chance(0.5) ? fullName() : '', amount });
    } else {
      rows.push({ username: '', phone: chance(0.5) ? '' : '123', name: fullName(), amount });
    }
  }
  const res = mt.matchDebtRows(rows, subs);
  scenarios.push({
    subs,
    rows: rows.map((r) => ({ ...r, amount: Number.isFinite(r.amount) ? r.amount : null })),
    out: res.map((o) => ({ kind: o.kind, sub: o.sub ? subs.indexOf(o.sub) : null, note: o.note ?? null })),
  });
}

// ─── ٨) Excel: SheetJS يكتب، والموقع يقرأ ───
async function xlsxCases() {
  const sheets = [
    [['username', 'amount', 'الاسم', 'رقم الهاتف', 'الباقة', 'تاريخ النفاذ'], ['ali1', 25000, 'علي حسن', '07701234567', 'Economy', '2026-12-01'], ['zainab', 30000.5, 'زينب', 7801234567, '', ''], ['', '', '', '', '', ''], ['mo', '٣٥٠٠٠', '  مو  ', '', 'Plus', '']],
    [[null, null, null], [null, 'username', 'amount'], [null, 'x1', 1000], [null, 'x2', true], [null, 'x3', 12345678901]],
    [['اسم المستخدم', 'الدين'], ['a', -5000], ['b', 0.1], ['c', 1e21]],
  ];
  const out = [];
  for (const aoa of sheets) {
    const ws = XLSX.utils.aoa_to_sheet(aoa);
    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, ws, 'Debts');
    const buf = XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' });
    const rows = await hz.readSpreadsheetRows(buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength));
    out.push({ b64: Buffer.from(buf).toString('base64'), rows });
  }
  return out;
}

(async () => {
  const xlsx = await xlsxCases();
  const json = { generatedFrom: 'client-v2 debts-pdf.ts + debts-match.ts + pages/DebtsImport.tsx (transpiled) — xlsx ' + XLSX.version, normalize, phones: phoneOut, headers: headOut, amounts: amountOut, csv: csvOut, tables: tableOut, scenarios, xlsx };
  fs.writeFileSync(process.env.OUT, JSON.stringify(json));
  const kinds = {};
  for (const s of scenarios) for (const o of s.out) kinds[o.kind] = (kinds[o.kind] || 0) + 1;
  console.log('normalize', normalize.length, 'phones', phoneOut.length, 'headers', headOut.length, 'amounts', amountOut.length, 'csv', csvOut.length, 'tables', tableOut.length, 'scenarios', scenarios.length, 'rows', Object.values(kinds).reduce((a, b) => a + b, 0), JSON.stringify(kinds), 'xlsx', xlsx.length);
})();
