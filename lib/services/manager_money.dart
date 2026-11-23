import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'auth_storage.dart';

/// «كاش المدراء يدخل الصندوق» (٢٣ نوفمبر — server/managerBox.js؛ المالك: «تمام، كاش المدراء يدخل الصندوق… الماستر يستلمها ككاش
/// يكتبها يعلمها ككاش او تبقى بالماستر وبعدين هو يسحبها يعلمها كاش بالتقارير»). حال الصفحة من GET /api/v2/managers/money-settings:
///   [box] — نقد المدراء الفرعيّين (الشحن النقديّ وفائدته، تسديد دينهم، سحب رصيدهم) يدخل الصندوق «تسوية الحساب».
///   [transfers] — ونوافذهم تعرض «استلمته»/«أرجعته» (كاش أو حوالة بطريقتها) — [box] مع «الحوالات».
/// غيابه/تعذّره/خادمٌ أقدم ⇒ [off]: لا اختيار ولا سطر — كلّ شيءٍ كما كان.
@immutable
class ManagerMoney {
  const ManagerMoney({required this.box, required this.transfers});

  final bool box;
  final bool transfers;

  static const off = ManagerMoney(box: false, transfers: false);

  static ManagerMoney fromJson(Object? raw) {
    if (raw is! Map) return off;
    final box = raw['manager_box'] == true;
    return ManagerMoney(box: box, transfers: box && raw['transfers'] == true);
  }

  @override
  bool operator ==(Object other) => other is ManagerMoney && other.box == box && other.transfers == transfers;

  @override
  int get hashCode => Object.hash(box, transfers);
}

/// حال الميزة لهذه الجلسة — نوافذ مال المدير الفرعيّ تبنى عليها بلا انتظار ([ensureFresh] عند فتحها). تبديل الجلسة يصفّرها ([reset]).
abstract final class ManagerMoneyState {
  static final ValueNotifier<ManagerMoney> gate = ValueNotifier<ManagerMoney>(ManagerMoney.off);

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 2);
  static const _cooldown = Duration(seconds: 30);

  static Future<void> ensureFresh({bool force = false}) {
    final running = _inflight;
    if (running != null) return running;
    if (!force) {
      final now = DateTime.now();
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
      final failed = _failedAt;
      if (failed != null && now.difference(failed) < _cooldown) return Future<void>.value();
    }
    final epoch = _epoch;
    late final Future<void> run;
    run = _probe().then((m) {
      if (epoch != _epoch) return;
      if (m == null) {
        _failedAt = DateTime.now();
        return;
      }
      _fetchedAt = DateTime.now();
      _failedAt = null;
      gate.value = m;
    }).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  /// بلا جلسة ⇒ لا نداء. ردٌّ بلا success (خادمٌ أقدم بلا المسار: 404) ⇒ [ManagerMoney.off] محفوظاً؛ عطل الشبكة ⇒ null (يُعاد بعد مهلة).
  static Future<ManagerMoney?> _probe() async {
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) return null;
    try {
      final r = await ApiClient.dio.get<Object?>('/api/v2/managers/money-settings');
      final b = r.data;
      if (b is! Map || b['success'] != true) return ManagerMoney.off;
      return ManagerMoney.fromJson(b['data']);
    } catch (_) {
      return null;
    }
  }

  /// تبديل الجلسة: لا ترى الصفحة التالية حال سابقتها.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    gate.value = ManagerMoney.off;
  }

  @visibleForTesting
  static void debugSet(ManagerMoney m) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = DateTime.now();
    gate.value = m;
  }
}
