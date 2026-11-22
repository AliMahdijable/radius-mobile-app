// يبني من مصادر الموقع نفسها (client-v2) وحدات CJS للمقارنة — لا نسخٌ يدويّ للمنطق.
const fs = require('fs');
const path = require('path');
const WEB = process.env.WEB;
const ts = require(path.join(WEB, 'node_modules/typescript'));
const out = __dirname + '/out';
fs.mkdirSync(out, { recursive: true });
function tr(src, file) {
  const r = ts.transpileModule(src, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020, esModuleInterop: true } });
  fs.writeFileSync(path.join(out, file), r.outputText);
}
tr(fs.readFileSync(WEB + '/src/lib/debts-pdf.ts', 'utf8'), 'debts-pdf.js');
tr(fs.readFileSync(WEB + '/src/lib/debts-match.ts', 'utf8'), 'debts-match.js');
// الدوالّ الخاصّة من pages/DebtsImport.tsx — تُقصّ من الملفّ حرفاً بين علاماتها
const page = fs.readFileSync(WEB + '/src/pages/DebtsImport.tsx', 'utf8');
function cut(startMarker, endMarker) {
  const a = page.indexOf(startMarker);
  const b = page.indexOf(endMarker, a + 1);
  if (a < 0 || b < 0) throw new Error('marker not found: ' + startMarker);
  return page.slice(a, b);
}
const readSheet = cut('async function readSpreadsheetRows', '/** نوع الملفّ من بايتاته');
const amount = cut('function parseAmountCell', '// ──────────────────────────────────────────────────────────\n// CSV parser');
const csv = cut('function detectCsvSeparator', 'export default function DebtsImport');
// كتلة العناوين داخل handleFile — حرفاً (من «const kinds» حتى نهاية extracted = …)
const hb = cut('        const kinds = rows[0].map', '      }\n\n      // مطابقة مع المشتركين');
const harness = `import { classifyHeader } from './debts-pdf';
${readSheet}
${amount}
${csv}
export function tableRows(rows: string[][]) {
  let extracted: { username: string; amount: number; raw: string; phone: string; name: string }[];
${hb}
  return extracted;
}
export { readSpreadsheetRows, parseAmountCell, parseCsv, detectCsvSeparator };
`;
fs.writeFileSync(path.join(out, 'harness.ts'), harness);
tr(harness, 'harness.js');
console.log('built', fs.readdirSync(out).join(' '));
