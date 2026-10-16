import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';

/// استهلاك مشتركٍ واحد (بايت) — `today` null لشهرٍ مضى.
@immutable
class SubscriberUsage {
  const SubscriberUsage({this.today, this.month});
  final int? today;
  final int? month;
}

/// «عرض الاستهلاك» بقائمة المشتركين (طلب المستخدم ١٦ أكتوبر) — مخفيّ افتراضاً،
/// يُحفظ لكلّ جهاز.
class UsagePrefs {
  UsagePrefs._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );
  static const _kEnabled = 'subs.show_usage';

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  /// مرّةً في `main()` — صامتٌ إن تعذّرت الخزنة.
  static Future<void> init() async {
    try {
      enabled.value = (await _storage.read(key: _kEnabled)) == '1';
    } catch (_) {
      enabled.value = false;
    }
  }

  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
    try {
      await _storage.write(key: _kEnabled, value: v ? '1' : '0');
    } catch (_) {
      // القيمة في الذاكرة تكفي للجلسة الحاليّة.
    }
  }
}

/// استهلاك اليوم + الشهر للصفوف **المبنيّة على الشاشة** وحدها: كلّ كارتٍ يُبنى
/// يطلب مشتركه ([want])، فتُجمَع الطلبات المتقاربة بدفعاتٍ ≤٤٠ من
/// `/api/v2/subscribers-usage` (الخادم: SAS4 من تقرير user/traffic، وايرث لنك
/// من الجلسات موزَّعةً على مدّتها). كاشٌ ٥ دقائق (الخادم يكاش ١٠).
class SubscriberUsageStore {
  SubscriberUsageStore._();

  static const _batch = 40;
  static const _ttl = Duration(minutes: 5);
  static const _failTtl = Duration(minutes: 1);

  static final _cache = <String, ({DateTime at, SubscriberUsage? v})>{};
  static final _queue = <String>{};
  static final _busy = <String>{};
  static Timer? _timer;
  static bool _running = false;
  static int _gen = 0;

  /// يرتفع مع كلّ دفعةٍ وصلت — كارتات القائمة تستمع له.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  /// `null` = لم يصل بعد · قيمة `v` null = تعذّر.
  static ({SubscriberUsage? v})? get(String idx) {
    final e = _cache[idx];
    return e == null ? null : (v: e.v);
  }

  static void want(String idx) {
    if (idx.isEmpty || _busy.contains(idx) || _queue.contains(idx)) return;
    final e = _cache[idx];
    if (e != null &&
        DateTime.now().difference(e.at) < (e.v != null ? _ttl : _failTtl)) {
      return;
    }
    _queue.add(idx);
    _timer ??= Timer(const Duration(milliseconds: 150), () {
      _timer = null;
      _pump();
    });
  }

  static Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && UsagePrefs.enabled.value) {
        final gen = _gen;
        final batch = _queue.take(_batch).toList();
        _queue.removeAll(batch);
        _busy.addAll(batch);
        Map<String, dynamic> data = const {};
        var ok = false;
        try {
          final r = await ApiClient.dio.get<Map<String, dynamic>>(
            '/api/v2/subscribers-usage',
            queryParameters: {'ids': batch.join(',')},
          );
          final body = r.data ?? const {};
          ok = body['success'] == true;
          final d = body['data'];
          if (d is Map<String, dynamic>) data = d;
        } catch (e) {
          if (kDebugMode) debugPrint('🔴 subscribers-usage: $e');
        }
        _busy.removeAll(batch);
        if (gen != _gen) continue; // حسابٌ آخر الآن
        final now = DateTime.now();
        for (final id in batch) {
          final u = data[id];
          _cache[id] = (
            at: now,
            v: ok && u is Map
                ? SubscriberUsage(today: _int(u['today']), month: _int(u['month']))
                : null,
          );
        }
        if (_cache.length > 5000) {
          _cache.remove(_cache.keys.first);
        }
        version.value++;
      }
    } finally {
      _running = false;
    }
  }

  static int? _int(Object? v) {
    if (v == null) return null;
    if (v is num) return v.round();
    return num.tryParse(v.toString())?.round();
  }

  /// خروجٌ/تبديل حساب — `SessionManager.clearAllSessionData`.
  static void reset() {
    _gen++;
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _busy.clear();
    _cache.clear();
    version.value++;
  }
}

/// بايت ⇒ «5.6 GB» / «820 MB» — ٠ يُكتب «0» (استهلاكٌ صفر حقيقيّ لا «—»).
String formatUsageBytes(int? b) {
  if (b == null) return '—';
  if (b <= 0) return '0';
  final mb = b / 1048576;
  if (mb < 1) return '<1 MB';
  if (mb < 1024) return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
  final gb = mb / 1024;
  if (gb < 1024) {
    return '${gb < 10 ? gb.toStringAsFixed(2) : gb < 100 ? gb.toStringAsFixed(1) : gb.round()} GB';
  }
  return '${(gb / 1024).toStringAsFixed(2)} TB';
}
