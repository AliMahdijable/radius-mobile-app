import 'dart:async';

import 'order_rules.dart';

/// «الترتيب بالنقر» — المرحلة ٤ (المالك ٢٤ نوفمبر: «تمام ابدي ببيهن»): الموظّفون، المبيعات وموادّها، الكارتات (الباقات والسلاسل)،
/// أرشيف الوصولات، تذاكر المشتركين، طلبات التفعيل — بطاقاتٌ وقوائم ⇒ «رتّب حسب» (RpSortChips). الحقول ومفاتيحها وأسماؤها واتّجاه
/// أوّل نقرة ومفاتيح الحفظ نفسها بالموقع (client-v2 lib/list-sorts.ts) حرفاً. ما يصل «الأحدث أوّلاً» (المبيعات، الوصولات) حقله
/// «التاريخ» طبيعيّ ([OrderPrefs.load] بافتراضه)، وغيره ثلاث نقرات ([nextTriOrder]). ما يُقرأ صفحةً صفحة يُجلب كلّه قبل ترتيبه.

/// الترتيب غير الافتراضيّ لقائمةٍ تُقرأ صفحةً صفحة يحتاجها كلّها: تُجلب صفحاتها حتى هذا الحدّ، وفوقه سطرٌ يقول «أوّل …».
const int sortAllCap = 1000;

/// المتّصل الآن قبل أيّ «آخر ظهور» — كالموقع (Number.MAX_SAFE_INTEGER).
const int _onlineNow = 9007199254740991;

// ─── الموظّفون ───

/// كلّ الحقول — لقراءة المحفوظ؛ والظاهر منها ما تعرضه البطاقة ([empSortShown]).
const empSort = <OrderField>[
  OrderField('name', 'الاسم', OrderKind.text),
  OrderField('seen', 'آخر دخول', OrderKind.date),
  OrderField('ops', 'عمليّات اليوم', OrderKind.number),
  OrderField('owes', 'عليه', OrderKind.number),
  OrderField('created', 'تاريخ الإضافة', OrderKind.date),
];

const _empSeenLive = OrderField('seen', 'آخر ظهور', OrderKind.date);

/// حقول البطاقة: «آخر ظهور» و«عمليّات اليوم» حين «الموظف المتّصل الآن» مفتوح (وإلّا «آخر دخول»)، و«عليه» مع «حساب الموظف».
List<OrderField> empSortShown({required bool presence, required bool ledger}) {
  final out = <OrderField>[];
  for (final f in empSort) {
    if (f.key == 'seen') {
      out.add(presence ? _empSeenLive : f);
    } else if (f.key == 'ops') {
      if (presence) out.add(f);
    } else if (f.key == 'owes') {
      if (ledger) out.add(f);
    } else {
      out.add(f);
    }
  }
  return out;
}

/// حال موظّفٍ من «المتّصل الآن» للترتيب.
typedef EmpPresence = ({bool online, DateTime? lastSeenAt, int? opsToday});

/// قيمة موظّفٍ كما تعرضه بطاقته: المتّصل الآن قبل أيّ «آخر ظهور»، ومن لم يدخل و«عليه» صفراً «—» آخراً. [presence] غائب ⇒ «آخر دخول».
Object? empSortValue(
  String key, {
  required String username,
  String? fullName,
  String? lastLoginAt,
  String? createdAt,
  EmpPresence? presence,
  num? owes,
}) {
  switch (key) {
    case 'name':
      final n = (fullName ?? '').trim();
      return n.isNotEmpty ? n : username;
    case 'seen':
      final p = presence;
      if (p != null) return p.online ? _onlineNow : p.lastSeenAt;
      return lastLoginAt;
    case 'ops':
      return presence?.opsToday;
    case 'owes':
      return owes != null && owes > 0 ? owes : null;
    case 'created':
      return createdAt;
  }
  return null;
}

// ─── المبيعات وموادّها ───

/// «التاريخ» طبيعيّ: القائمة تصل الأحدث أوّلاً ⇒ الافتراض كما كان حرفاً، و«الأقدم» عكسها.
const saleSort = <OrderField>[
  OrderField('date', 'التاريخ', OrderKind.date, natural: OrderDir.desc),
  OrderField('total', 'المبلغ', OrderKind.number),
  OrderField('profit', 'الربح', OrderKind.number),
  OrderField('customer', 'الزبون', OrderKind.text),
];
const saleSortDefault = OrderValue('date', OrderDir.desc);

/// كما يعرضه السطر: الملغى والفاشل بلا ربح («—» آخراً)، والزبون باسمه أو يوزره (بلاهما آخراً).
Object? saleSortValue(String key, {required String status, required num total, required num profit, String? customerName, String? username}) {
  switch (key) {
    case 'total':
      return total;
    case 'profit':
      return status == 'void' || status == 'failed' ? null : profit;
    case 'customer':
      final n = (customerName ?? '').trim();
      return n.isNotEmpty ? n : username;
  }
  return null;
}

const itemSort = <OrderField>[
  OrderField('name', 'الاسم', OrderKind.text),
  // أوّل نقرة الأقلّ كمّيّةً — النافد أوّلاً (ما يُشترى)، والثانية الأكثر
  OrderField('qty', 'الكمّيّة', OrderKind.number, first: OrderDir.asc),
  OrderField('price', 'سعر البيع', OrderKind.number),
  OrderField('value', 'قيمة المخزون', OrderKind.number),
];

Object? itemSortValue(String key, {required String name, required num qty, required num salePrice, required num stockValue}) =>
    switch (key) {
      'name' => name,
      'qty' => qty,
      'price' => salePrice > 0 ? salePrice : null,
      'value' => stockValue,
      _ => null,
    };

// ─── الكارتات ───

const cardStockSort = <OrderField>[
  OrderField('name', 'الباقة', OrderKind.text),
  OrderField('remaining', 'المتبقّي', OrderKind.number),
  OrderField('used', 'المستعمل', OrderKind.number),
  OrderField('value', 'القيمة', OrderKind.number),
];

Object? cardStockSortValue(String key, {required String? name, required num remaining, required num used, required num value}) =>
    switch (key) {
      'name' => name,
      'remaining' => remaining,
      'used' => used,
      'value' => value > 0 ? value : null,
      _ => null,
    };

const cardSeriesSort = <OrderField>[
  OrderField('series', 'السلسلة', OrderKind.text),
  OrderField('name', 'الباقة', OrderKind.text),
  OrderField('remaining', 'المتبقّي', OrderKind.number),
  OrderField('created', 'تاريخ الإنشاء', OrderKind.date),
  // أوّل نقرة الأقرب انتهاءً
  OrderField('expiry', 'الانتهاء', OrderKind.date, first: OrderDir.asc),
];

/// حقلا التاريخين حين تحملهما سلسلةٌ واحدةٌ على الأقلّ — ساسٌ لا يرسلهما ⇒ لا رقاقة بلا أثر.
List<OrderField> cardSeriesShown({required bool created, required bool expiry}) => [
      for (final f in cardSeriesSort)
        if ((f.key != 'created' || created) && (f.key != 'expiry' || expiry)) f,
    ];

Object? cardSeriesSortValue(String key, {required String series, String? name, required num remaining, String? createdAt, String? expiration}) =>
    switch (key) {
      'series' => series,
      'name' => (name ?? '').isEmpty ? null : name,
      'remaining' => remaining,
      'created' => (createdAt ?? '').isEmpty ? null : createdAt,
      'expiry' => (expiration ?? '').isEmpty ? null : expiration,
      _ => null,
    };

// ─── أرشيف الوصولات ───

/// «التاريخ» طبيعيّ: الأرشيف يصل الأحدث أوّلاً صفحةً صفحة.
const receiptSort = <OrderField>[
  OrderField('date', 'التاريخ', OrderKind.date, natural: OrderDir.desc),
  OrderField('amount', 'المبلغ', OrderKind.number),
  OrderField('name', 'المشترك', OrderKind.text),
  OrderField('no', 'رقم الوصل', OrderKind.number),
];
const receiptSortDefault = OrderValue('date', OrderDir.desc);

/// [name] الاسم المعروض (من قائمة المشتركين) — بلا اسمٍ ⇒ اليوزر؛ وما لم يُطبع بلا رقم («—» آخراً).
Object? receiptSortValue(String key, {num? amount, String? username, int? receiptNo, required String name}) {
  switch (key) {
    case 'amount':
      return amount;
    case 'name':
      final n = name.trim();
      return n.isNotEmpty ? n : username;
    case 'no':
      return receiptNo;
  }
  return null;
}

// ─── تذاكر المشتركين ───

/// الافتراض كما يصل (غير المقروءة أوّلاً ثمّ الأحدث نشاطاً) ⇒ ثلاث نقرات.
const ticketSort = <OrderField>[
  OrderField('activity', 'آخر نشاط', OrderKind.date),
  OrderField('opened', 'تاريخ الفتح', OrderKind.date),
  OrderField('name', 'المشترك', OrderKind.text),
];

Object? ticketSortValue(String key, {DateTime? lastActivityAt, DateTime? createdAt, String? name, String? username}) {
  switch (key) {
    case 'activity':
      return lastActivityAt ?? createdAt;
    case 'opened':
      return createdAt;
    case 'name':
      final n = (name ?? '').trim();
      return n.isNotEmpty ? n : username;
  }
  return null;
}

// ─── طلبات التفعيل ───

/// الافتراض كما تعرضه الصفحة («بانتظارك» أوّلاً ثمّ المقبولة، الأحدث في كلٍّ) ⇒ ثلاث نقرات.
const renewSort = <OrderField>[
  OrderField('date', 'تاريخ الطلب', OrderKind.date),
  OrderField('name', 'المشترك', OrderKind.text),
  OrderField('amount', 'المبلغ', OrderKind.number),
];

Object? renewSortValue(String key, {DateTime? createdAt, String? name, String? username, num? amount}) {
  switch (key) {
    case 'date':
      return createdAt;
    case 'name':
      final n = (name ?? '').trim();
      return n.isNotEmpty ? n : username;
    case 'amount':
      return amount != null && amount > 0 ? amount : null;
  }
  return null;
}

/// نقرة حقلٍ بثلاث حالات بقائمة [fields] كاملةً (المخفيّ منها يُهمل) ⇒ الترتيب الجديد، ويُحفظ بمفتاح القائمة.
OrderValue? pickTri(String list, OrderValue? cur, List<OrderField> fields, String key) {
  OrderField? f;
  for (final x in fields) {
    if (x.key == key) f = x;
  }
  if (f == null) return cur;
  final next = nextTriOrder(cur, f);
  unawaited(OrderPrefs.saveTri(OrderPrefs.listKey(list), next));
  return next;
}

/// نقرة حقلٍ في قائمةٍ «التاريخ» فيها طبيعيّ (useSort بالموقع) ⇒ الترتيب الجديد، ويُحفظ.
OrderValue pickOrder(String list, OrderValue cur, List<OrderField> fields, String key) {
  OrderField? f;
  for (final x in fields) {
    if (x.key == key) f = x;
  }
  if (f == null) return cur;
  final next = nextOrder(cur, f);
  unawaited(OrderPrefs.save(OrderPrefs.listKey(list), next));
  return next;
}
