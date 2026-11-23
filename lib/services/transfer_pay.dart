import 'package:flutter/foundation.dart';

import '../api/transfer_pay_api.dart';

/// «الحوالات» (٢٣ نوفمبر — المالك: «نحتاج طريقة نعلم انه الفلوس هو استلمهن عن طريق الماستر كارد… مو اجت… مال الصندوق مباشرة»):
/// طريقة استلام المبلغ في التفعيل النقديّ والتسديد وإضافة الرصيد — كاش (الافتراضيّ) أو حوالة بطريقتها. الكاش يدخل الصندوق وبيد
/// مستلمه؛ الحوالة رصيدٌ لطريقتها خارج الصندوق (ولا على الموظّف) حتى «سحب للصندوق». رصيدٌ لكلّ طريقة: زين كاش، ماستر، وأخرى باسمها.
class PaidVia {
  const PaidVia(this.key, [this.name]);

  /// cash | zaincash | master | other — يُرسَل كما هو (`paid_via`).
  final String key;

  /// اسم «أخرى» كما كتبه الوكيل (`paid_via_name`).
  final String? name;

  static const cash = PaidVia('cash');
  static const zaincash = PaidVia('zaincash');
  static const master = PaidVia('master');

  bool get isCash => key == 'cash';
  bool get isTransfer => !isCash;

  /// «أخرى» بلا اسم لا تُرسَل.
  bool get valid => key != 'other' || (name ?? '').trim().isNotEmpty;

  String get label => switch (key) {
        'zaincash' => 'زين كاش',
        'master' => 'ماستر',
        'other' => (name ?? '').trim().isEmpty ? 'أخرى' : name!.trim(),
        _ => 'كاش',
      };

  /// ما يُضاف لجسم الطلب — والكاش لا يُرسل شيئاً (خادمٌ أقدم وأحدث يعدّانه كاشاً كما كان).
  Map<String, Object?> toBody() => isCash ? const {} : {'paid_via': key, if (key == 'other') 'paid_via_name': name!.trim()};

  /// من طريقة طلب البوّابة (renew/debt-pay: zaincash | master | other). «تحويل آخر» ⇒ «أخرى» بلا اسم: يكتبه الوكيل (كالموقع).
  static PaidVia fromRequest(String? payMethod) => switch (payMethod) {
        'zaincash' => zaincash,
        'master' => master,
        'other' => const PaidVia('other', ''),
        _ => cash,
      };

  @override
  bool operator ==(Object other) => other is PaidVia && other.key == key && (other.name ?? '') == (name ?? '');

  @override
  int get hashCode => Object.hash(key, name ?? '');
}

/// هل يعرف الخادم «الحوالات» لهذه الصفحة؟ (المفتاح `transfer_pay` — GET /api/v2/transfer-pay). قبله لا يُعرض الاختيار ولا يُرسل
/// شيء (كلّ شيءٍ كاش كما كان). للشركة المفتوحة وحدها: صفُّ شركةٍ أخرى في «كل الشركات» بلا اختيار.
abstract final class TransferPay {
  static final ValueNotifier<bool> available = ValueNotifier<bool>(false);

  /// أسماء «أخرى» التي استعملها الوكيل (للاختيار السريع).
  static final ValueNotifier<List<String>> recentOthers = ValueNotifier<List<String>>(const []);

  static DateTime? _at;
  static Future<void>? _inflight;
  static int _gen = 0;

  /// يسأل الخادم — مرّةً كلّ ٦٠ث (شيت مالٍ يُفتح ⇒ يسأل)، والطلبات المتزامنة طلبٌ واحد. تعذّرٌ يُبقي ما كان.
  static Future<void> refresh({bool force = false}) {
    final at = _at;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(seconds: 60)) return Future<void>.value();
    final f = _inflight;
    if (f != null) return f;
    final next = _fetch();
    _inflight = next;
    return next;
  }

  static Future<void> _fetch() async {
    final gen = _gen;
    try {
      final r = await TransferPayApi.info();
      if (gen != _gen || r == null) return; // جلسةٌ أخرى بدأت بينهما، أو تعذّرت القراءة
      available.value = r.available;
      recentOthers.value = r.names;
      _at = DateTime.now();
    } finally {
      if (gen == _gen) _inflight = null;
    }
  }

  /// «طلب تجديد/تسديد» حوّل بزين كاش/ماستر/غيرهما: صفحة المشترك تُفتح منه ⇒ شيت المال يختار طريقته مسبقاً (١٠ دقائق).
  static final Map<String, ({PaidVia via, DateTime at})> _hints = {};

  static void hint(String? idx, PaidVia via) {
    final k = (idx ?? '').trim();
    if (k.isEmpty || via.isCash) return;
    _hints[k] = (via: via, at: DateTime.now());
  }

  /// الاختيار المسبق لمشتركٍ إن وُجد (ولم يمضِ عليه ١٠ دقائق) — وإلّا كاش.
  static PaidVia initialFor(String? idx) {
    final k = (idx ?? '').trim();
    final h = _hints[k];
    if (h == null) return PaidVia.cash;
    if (DateTime.now().difference(h.at) > const Duration(minutes: 10)) {
      _hints.remove(k);
      return PaidVia.cash;
    }
    return h.via;
  }

  static void clearHint(String? idx) => _hints.remove((idx ?? '').trim());

  @visibleForTesting
  static void debugSet({required bool on, List<String> names = const []}) {
    available.value = on;
    recentOthers.value = names;
    _at = DateTime.now();
  }

  /// جلسةٌ جديدة (خروج/تبديل شركة): لا يرث أحدٌ إعداد سابقه ولا أسماءه ولا اختياراته المسبقة.
  static void reset() {
    _gen++;
    _inflight = null;
    _at = null;
    available.value = false;
    recentOthers.value = const [];
    _hints.clear();
  }
}
