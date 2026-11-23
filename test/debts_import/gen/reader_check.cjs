// «قارئ PDF الديون» (pdf-reader.html) في chromium حقيقيّ بسياسة /v2 الإنتاج — كما يشغّله تطبيق الهاتف: القناة PdfReader، الملفّ قطعاً
// base64 ⇒ __pdfAppend ⇒ __pdfRun. لا شبكة خارجيّة: خادمٌ محلّيّ يخدم DIST (البناء الحيّ أو المرحلي).
//   PDF=<ملفّ>  EXP=<صفوف المصدر JSON — اختياريّ>  OUT=<يكتب النتيجة JSON — للمقارنة بين بناءين>  LIB=modern (‎?lib=modern)
//   OLD=stream   ⇒ يحاكي WebKit (سفاري/آيفون): بلا ReadableStream[Symbol.asyncIterator] في الصفحة والعامل
//   OLD=safari16 ⇒ فوقه يحذف كلّ ما هو أحدث من سفاري 16.4 (Promise.withResolvers، Math.sumPrecise، URL.parse، getOrInsert…)
//   EXPECT_FAIL=1 ⇒ النجاح = أن يردّ القارئ خطأً (فحص أنّ المحاكاة تعضّ)
const http = require('http');
const fs = require('fs');
const path = require('path');
const puppeteer = require(process.env.PUPPETEER_CORE || '/home/ali/projects/zuhoor/node_modules/puppeteer-core');
const DIST = process.env.DIST;
const PDF = process.env.PDF;
const EXP = process.env.EXP;
const OUT = process.env.OUT;
const OLD = process.env.OLD || '';
const LIB = process.env.LIB || '';
const EXPECT_FAIL = process.env.EXPECT_FAIL === '1';
const PORT = Number(process.env.PORT || 3187);
const CSP = [
  "default-src 'self'", "base-uri 'self'", "font-src 'self' https: data:", "form-action 'self'", "frame-ancestors 'self'",
  "img-src 'self' data: https://*.googleusercontent.com https://tile.openstreetmap.org https://server.arcgisonline.com",
  "object-src 'none'", "script-src 'self' 'sha256-HPNMfW0qj0HgxQa7O2NgI+4UR6GvpYWVGCTDeqOzWOc=' https://apis.google.com", "script-src-attr 'none'",
  "style-src 'self' https: 'unsafe-inline'",
  "connect-src 'self' https://identitytoolkit.googleapis.com https://securetoken.googleapis.com https://www.googleapis.com https://apis.google.com",
  "frame-src 'self' https://myservices-radius.firebaseapp.com https://accounts.google.com https://apis.google.com",
].join('; ');
const STREAM = `(()=>{try{delete ReadableStream.prototype[Symbol.asyncIterator];delete ReadableStream.prototype.values;}catch(e){}})();`;
const SAFARI16 = `(()=>{const d=(o,k)=>{try{if(o&&Object.prototype.hasOwnProperty.call(o,k))delete o[k];}catch(e){}};
d(Promise,'withResolvers');d(Promise,'try');for(const C of [Map,WeakMap]){d(C.prototype,'getOrInsert');d(C.prototype,'getOrInsertComputed');}
d(Map,'groupBy');d(Object,'groupBy');d(Math,'sumPrecise');d(Math,'f16round');d(URL,'parse');d(URL,'canParse');
d(Uint8Array,'fromBase64');d(Uint8Array,'fromHex');for(const k of ['toBase64','toHex','setFromBase64','setFromHex'])d(Uint8Array.prototype,k);
d(Array,'fromAsync');for(const k of ['union','intersection','difference','symmetricDifference','isSubsetOf','isSupersetOf','isDisjointFrom'])d(Set.prototype,k);
const IP=Object.getPrototypeOf(Object.getPrototypeOf([][Symbol.iterator]()));for(const k of ['map','filter','take','drop','flatMap','reduce','toArray','forEach','some','every','find'])d(IP,k);
d(globalThis,'Iterator');for(const k of ['transfer','transferToFixedLength','detached'])d(ArrayBuffer.prototype,k);
d(globalThis,'Float16Array');d(RegExp,'escape');d(Error,'isError');d(Atomics,'pause');
if(typeof Response!=='undefined')d(Response.prototype,'bytes');if(typeof Blob!=='undefined')d(Blob.prototype,'bytes');})();`;
const PROLOGUE = OLD === 'stream' ? STREAM : OLD === 'safari16' ? STREAM + SAFARI16 : '';
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.json': 'application/json', '.wasm': 'application/wasm' };
let workerPatched = 0;
const srv = http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  if (PROLOGUE && u.pathname === '/v2/__old.js') { res.writeHead(200, { 'Content-Type': 'text/javascript', 'Content-Security-Policy': CSP }); return res.end(PROLOGUE); }
  if (!u.pathname.startsWith('/v2/')) { res.writeHead(404); return res.end(); }
  const f = path.join(DIST, u.pathname.slice(4));
  if (!f.startsWith(DIST) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end(); }
  const head = { 'Content-Type': TYPES[path.extname(f)] || 'application/octet-stream', 'Content-Security-Policy': CSP };
  if (PROLOGUE && /pdf-reader\.html$/.test(f)) {
    res.writeHead(200, head); return res.end(fs.readFileSync(f, 'utf8').replace('<head>', '<head><script src="/v2/__old.js"></script>'));
  }
  if (PROLOGUE && /\/assets\/pdf\.worker[^/]*\.mjs$/.test(f)) { workerPatched++; res.writeHead(200, head); return res.end(PROLOGUE + '\n' + fs.readFileSync(f, 'utf8')); }
  res.writeHead(200, head);
  fs.createReadStream(f).pipe(res);
});
(async () => {
  await new Promise((r) => srv.listen(PORT, '127.0.0.1', r));
  const prof = fs.mkdtempSync(path.join(process.env.HOME, 'snap/chromium/common/pdfreader_'));
  const browser = await puppeteer.launch({ executablePath: process.env.CHROME || '/snap/bin/chromium', headless: true, userDataDir: prof, args: ['--no-sandbox'] });
  let failures = 0;
  const fail = (m) => { failures++; console.log('✗', m); };
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', (e) => errors.push(String(e)));
    page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
    const notFound = [];
    page.on('response', (r) => { if (r.status() >= 400) notFound.push(r.status() + ' ' + r.url()); });
    await page.evaluateOnNewDocument(() => { window.__msgs = []; window.PdfReader = { postMessage: (s) => window.__msgs.push(s) }; });
    await page.goto(`http://127.0.0.1:${PORT}/v2/pdf-reader.html?d=2026-11-23${LIB ? '&lib=' + LIB : ''}`, { waitUntil: 'load' });
    await page.waitForFunction(() => window.__msgs.some((s) => s.includes('"ready"')), { timeout: 30000 });
    if (OLD) {
      const sim = await page.evaluate(() => [typeof ReadableStream.prototype[Symbol.asyncIterator], typeof Promise.withResolvers]);
      console.log(`  محاكاة ${OLD}: الصفحة asyncIterator=${sim[0]} withResolvers=${sim[1]} (قبل القراءة)`);
    }
    const b64 = fs.readFileSync(PDF).toString('base64');
    const CH = 200000; // كالتطبيق
    for (let i = 0; i < b64.length; i += CH) await page.evaluate((c) => window.__pdfAppend(c), b64.slice(i, i + CH));
    const t0 = Date.now();
    await page.evaluate(() => { window.__pdfRun(); });
    await page.waitForFunction(() => window.__msgs.some((s) => s.includes('"ok"')), { timeout: 90000 });
    const msg = JSON.parse(await page.evaluate(() => window.__msgs.find((s) => s.includes('"ok"'))));
    if (OLD) console.log(`  العامل مُحاكى: ${workerPatched ? 'نعم' : 'لا'}`);
    if (EXPECT_FAIL) {
      if (msg.ok === false) console.log(`✓ يفشل كما يُنتظر (${Date.now() - t0}ms): ${msg.error}`);
      else fail(`expected failure but got ${msg.result?.rows?.length} rows`);
    } else {
      console.log(`${msg.ok ? '✓' : '✗'} result in ${Date.now() - t0}ms ok=${msg.ok} rows=${msg.result?.rows?.length} pages=${msg.result?.pages} ${msg.ok ? '' : msg.error}`);
      if (!msg.ok) fail('reader error: ' + msg.error);
      if (msg.ok && OUT) fs.writeFileSync(OUT, JSON.stringify(msg.result));
      if (msg.ok && EXP) {
        const exp = JSON.parse(fs.readFileSync(EXP, 'utf8'));
        const rows = msg.result.rows;
        if (rows.length !== exp.length) fail(`rows ${rows.length} ≠ ${exp.length}`);
        let ok = 0;
        for (let i = 0; i < Math.min(rows.length, exp.length); i++) {
          const r = rows[i], e = exp[i];
          const ed = e.debt === '' ? null : Number(String(e.debt).replace(/[,-]/g, ''));
          const good = r.name === e.name && r.username === e.username && r.phone === e.phone &&
            (ed === null ? r.debt === null : r.debt === ed) && r.negative === String(e.debt).startsWith('-');
          if (good) ok++; else if (failures < 8) fail(`row ${i + 1}: ${JSON.stringify(r)} vs ${JSON.stringify(e)}`);
        }
        console.log(`✓ ${ok}/${exp.length} صفّاً مطابقة للمصدر (الاسم، اليوزر، الهاتف، الدين، السالب)`);
      }
      if (msg.ok && !OLD) {
        await page.evaluate(() => { window.__msgs = []; window.__pdfAppend(btoa('not a pdf')); window.__pdfRun(); });
        await page.waitForFunction(() => window.__msgs.some((s) => s.includes('"ok"')), { timeout: 30000 });
        const bad = JSON.parse(await page.evaluate(() => window.__msgs[0]));
        if (bad.ok === false && bad.error) console.log('✓ ملفٌّ تالف ⇒ ' + bad.error); else fail('bad pdf not reported');
      }
    }
    const real = errors.filter((e) => !/favicon/.test(e) && !(/404/.test(e) && notFound.every((u) => /favicon\.ico$/.test(u))));
    if (real.length && !EXPECT_FAIL) fail('page errors: ' + real.join(' | '));
  } finally {
    await browser.close();
    srv.close();
  }
  console.log(failures ? `FAILED ${failures}` : 'ALL OK');
  process.exit(failures ? 1 : 0);
})();
