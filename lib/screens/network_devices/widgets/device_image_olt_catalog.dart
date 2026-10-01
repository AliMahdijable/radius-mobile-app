// ⚙️ **ملفٌّ مولَّد — لا يُحرَّر يدويّاً.**
//
// أولتيات (OLT). ثلاثة مصادرَ رسميّة، وكلّ صورةٍ حُمِّلت فعلاً
// وفُحصت بالعين أنّها صورة منتجٍ لا مخطّط شبكةٍ ولا لافتةٍ تسويقيّة:
//
//   · **VSOL** ‏(vsolcn.com) — 22 طرازاً. الصورة مربوطةٌ بالطراز
//     باسم ملفّها على الخادم (`V1600D81.jpg` لـV1600D8).
//   · **C-Data** ‏(cdatatec.com) — رمز الطراز في مسار الصفحة وفي اسم
//     الصورة معاً.
//   · **FiberHome** ‏(en.fiberhome.com) — الصورة تحمل عنوانها في
//     HTML نفسه (`<span><p>AN6000-17</p></span>`).
//
// ⚠️ **لا مطابقةَ بالتخمين.** على C-Data تعرض صفحة FD1304E صورة
// FD1304S-B2 وبالعكس (كتلة «منتجاتٌ ذات صلة»)، فقاعدة «أوّل صورةٍ
// باسم طراز» كانت ستُسنِد لكلٍّ صورة الآخر. القاعدة المستعملة: اسم
// الملفّ يبدأ برمز الطراز — وهي وحدها نجت من هذه المصيدة.
//
// ما **لم** يُحصَد ولماذا: Huawei وZTE يردّان 403 أو صفحةً فارغة
// تُبنى بجافاسكربت؛ وBDCOM يضع صوره على CDN بأسماءٍ معمّاة
// (`20260826094720ptki28.jpg`) فلا تُثبَت نسبة صورةٍ إلى طراز؛
// وHSGQ بلا موقعٍ أصلاً. ولا نأخذها من وسطاء البيع: صورة أولت
// خطأ تبدو صحيحةً ويُبنى عليها قرار.
//
// 58 مفتاحاً · 44 صورة · vsol 28 · olt 30
library;

/// مفتاح مطبَّع ← مسار الملفّ داخل `assets/devices-images/`.
const Map<String, String> kOltCatalog = <String, String>{
  'an600015': 'olt/AN6000-15.png',
  'an600017': 'olt/AN6000-17.png',
  'an60002': 'olt/AN6000-2.png',
  'an60007': 'olt/AN6000-7.png',
  'an6001': 'olt/AN6001-G16.png',
  'an6001g16': 'olt/AN6001-G16.png',
  'fd1304e': 'olt/FD1304E-B1.png',
  'fd1304eb1': 'olt/FD1304E-B1.png',
  'fd1304s': 'olt/FD1304S-B2.png',
  'fd1304sb2': 'olt/FD1304S-B2.png',
  'fd1601gs': 'olt/FD1601GS.jpg',
  'fd1601sb1': 'olt/FD1601S-B1.jpg',
  'fd1601sc2': 'olt/FD1601S-C2.png',
  'fd1602sb1': 'olt/FD1602S-B1.jpg',
  'fd1602sc2': 'olt/FD1602S-C2.png',
  'fd1604e': 'olt/FD1604E-C1.jpg',
  'fd1604ec1': 'olt/FD1604E-C1.jpg',
  'fd1604s': 'olt/FD1604S-B1.jpg',
  'fd1604sb1': 'olt/FD1604S-B1.jpg',
  'fd1608s': 'olt/FD1608S-B1.jpg',
  'fd1608sb1': 'olt/FD1608S-B1.jpg',
  'fd1608y': 'olt/FD1608Y.jpg',
  'fd1608yb1m': 'olt/FD1608Y-B1M.png',
  'fd1616s': 'olt/FD1616S-B2.jpg',
  'fd1616sb2': 'olt/FD1616S-B2.jpg',
  'fd1801sc1': 'olt/FD1801S-C1.jpg',
  'fd1801sc2': 'olt/FD1801S-C2.png',
  'fd1801ts': 'olt/FD1801TS.jpg',
  'fd1816s': 'olt/FD1816S-B1.jpg',
  'fd1816sb1': 'olt/FD1816S-B1.jpg',
  'v1600d': 'vsol/V1600D8.jpg',
  'v1600d16': 'vsol/V1600D8.jpg',
  'v1600d4': 'vsol/V1600D8.jpg',
  'v1600d8': 'vsol/V1600D8.jpg',
  'v1600dmini': 'vsol/V1600DMINI.jpg',
  'v1600g0b': 'vsol/V1600G0B.jpg',
  'v1600g1b': 'vsol/V1600G1B.jpg',
  'v1600g1r': 'vsol/V1600G1-R.jpg',
  'v1600g1weob': 'vsol/V1600G1WEO-B.jpg',
  'v1600g2b': 'vsol/V1600G2B.jpg',
  'v1600g2r': 'vsol/V1600G2-R.jpg',
  'v1600gs': 'vsol/V1600GS-F.jpg',
  'v1600gsf': 'vsol/V1600GS-F.jpg',
  'v1600gso32': 'vsol/V1600GS-O32.jpg',
  'v1600gsr': 'vsol/V1600GS-R.jpg',
  'v1600gszf': 'vsol/V1600GS-F.jpg',
  'v1600gt': 'vsol/V1600GT.jpg',
  'v1600gtz': 'vsol/V1600GT-Z.jpg',
  'v1600xg02': 'vsol/V1600XG02.jpg',
  'v1600xg02w': 'vsol/V1600XG02-W.jpg',
  'v1601e02dp': 'vsol/V1601E02-DP.jpg',
  'v1601e04dp': 'vsol/V1601E04-DPBT.jpg',
  'v1601e04dpbt': 'vsol/V1601E04-DPBT.jpg',
  'v3600g1c': 'vsol/V3600G1-C.jpg',
  'v3600g2r': 'vsol/V3600G2-R.jpg',
  'v3600gs': 'vsol/V3600GS.jpg',
  'v5600x2': 'vsol/V5600X2.jpg',
  'v5600x7': 'vsol/V5600X7.jpg',
};
