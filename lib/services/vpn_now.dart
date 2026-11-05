import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/vpn_now_api.dart';

export '../api/vpn_now_api.dart' show VpnNowKind, VpnSubReading, VpnDeviceResult, VpnNowResult;

enum VpnBarPhase { idle, running, done, failed }

/// فحصٌ واحد عبر الـVPN (المشتركون أو الأجهزة) — الشريط يرسمه: يتّصل ⇒ «يفحص… ١٢٠ من ٣١٠» ⇒ النتيجة أو السبب.
/// الضغطة والفحص جارٍ لا تبدأ ثانياً (والخادم نفسه يعيد الفحص نفسه خلال دقيقتين).
class VpnNowJob extends ChangeNotifier {
  VpnNowJob(this.kind);
  final VpnNowKind kind;

  VpnBarPhase phase = VpnBarPhase.idle;
  String? line;
  String? sub;

  /// التقدّم ٠..١ — null = غير محدّد (يتّصل/يقرأ السكترات).
  double? value;
  VpnNowResult? result;

  /// سبب الفشل من الخادم (tunnel_failed، no_vpn…) — يقرّر زرّ «صفحة VPN».
  String? reason;
  int _gen = 0;

  bool get busy => phase == VpnBarPhase.running;
  String get _what => kind == VpnNowKind.devices ? 'أجهزتك' : 'مشتركينك';

  Future<void> run() async {
    if (busy) return;
    final gen = ++_gen;
    phase = VpnBarPhase.running;
    line = 'يتّصل بالـVPN…';
    sub = 'تقدر تطلع من الشاشة — الفحص يكمل';
    value = null;
    result = null;
    reason = null;
    notifyListeners();
    final st = await VpnNowApi.start(kind);
    if (gen != _gen) return;
    final id = st.id;
    if (id == null) {
      _fail(st.error ?? 'تعذّر الفحص الآن — حاول بعد قليل');
      return;
    }
    final started = DateTime.now();
    var misses = 0;
    while (gen == _gen) {
      await Future<void>.delayed(VpnNow.pollEvery);
      if (gen != _gen) return;
      final p = await VpnNowApi.poll(id);
      if (gen != _gen) return;
      if (p == null) {
        if (++misses >= 6) {
          _fail('انقطع الاتّصال بالخادم — أعد المحاولة');
          return;
        }
        continue;
      }
      misses = 0;
      if (p.done) {
        _finish(p.result ?? const VpnNowResult(ok: false, message: 'تعذّر الفحص الآن — حاول بعد قليل'));
        return;
      }
      _progress(p.progress);
      if (DateTime.now().difference(started) > VpnNow.maxWait) {
        _fail('الفحص أطول من المعتاد — أعد بعد قليل');
        return;
      }
    }
  }

  void _progress(VpnNowProgress? pr) {
    if (pr == null) return;
    switch (pr.phase) {
      case 'online':
        line = 'يجلب المتّصلين…';
        value = null;
      case 'sectors':
        line = 'يقرأ السكترات…';
        value = null;
      case 'olts':
        line = 'يقرأ الأولت…';
        value = null;
      case 'probing':
        if (pr.total > 0) {
          line = 'يفحص $_what… ${pr.done} من ${pr.total}';
          value = (pr.done / pr.total).clamp(0.0, 1.0);
        } else {
          line = 'يفحص $_what…';
          value = null;
        }
      case 'finishing':
        line = 'يجمع النتيجة…';
        value = 1;
      default:
        line = 'يتّصل بالـVPN…';
        value = null;
    }
    notifyListeners();
  }

  void _finish(VpnNowResult r) {
    result = r;
    if (!r.ok) {
      _fail(r.message, reason: r.reason);
      return;
    }
    VpnNow._apply(kind, r);
    phase = VpnBarPhase.done;
    line = r.message;
    sub = r.detail;
    value = null;
    notifyListeners();
  }

  void _fail(String msg, {String? reason}) {
    phase = VpnBarPhase.failed;
    line = msg;
    sub = null;
    value = null;
    this.reason = reason;
    notifyListeners();
  }

  /// يُغلق النتيجة أو الخطأ (لا يوقف فحصاً جارياً بالخادم).
  void clear() {
    if (busy) return;
    phase = VpnBarPhase.idle;
    line = null;
    sub = null;
    result = null;
    reason = null;
    notifyListeners();
  }

  /// تبديل الحساب/الخروج: يُنسى كلّ شيء ويُترك أيّ استطلاعٍ جارٍ.
  void reset() {
    _gen++;
    phase = VpnBarPhase.idle;
    line = null;
    sub = null;
    value = null;
    result = null;
    reason = null;
    notifyListeners();
  }
}

/// «فحص الآن» عبر VPN (٥ نوفمبر — المالك: «الوكيل… مو ضمن الشبكة… فحص الان بالمشتركين… وكذلك الاجهزة»): نتائج آخر فحص
/// (قراءة كلّ مشترك وحال كلّ جهاز، ٣٠ دقيقة) لكروت القائمة، وطريق الوكيل (مربوط أم لا)، وإخفاء الهنت لليوم.
class VpnNow {
  VpnNow._();

  @visibleForTesting
  static Duration pollEvery = const Duration(milliseconds: 2500);
  static Duration maxWait = const Duration(minutes: 6);
  static const ttl = Duration(minutes: 30);

  static final subscribers = VpnNowJob(VpnNowKind.subscribers);
  static final devices = VpnNowJob(VpnNowKind.devices);
  static VpnNowJob jobOf(VpnNowKind k) => k == VpnNowKind.devices ? devices : subscribers;

  /// يرتفع مع كلّ نتيجة — كروت القائمة تستمع له.
  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static final _readings = <String, VpnSubReading>{};
  static DateTime? _readAt;
  static final _devices = <int, VpnDeviceResult>{};
  static DateTime? _devAt;

  static bool _fresh(DateTime? at) => at != null && DateTime.now().difference(at) < ttl;

  /// قراءة مشتركٍ من آخر فحصٍ عبر الـVPN (≤ ٣٠ دقيقة) — null إن لم يُفحص.
  static VpnSubReading? readingFor(String username) {
    if (!_fresh(_readAt)) return null;
    return _readings[username.trim().toLowerCase()];
  }

  static VpnDeviceResult? deviceFor(int id) => _fresh(_devAt) ? _devices[id] : null;

  static void _apply(VpnNowKind k, VpnNowResult r) {
    if (k == VpnNowKind.devices) {
      _devices
        ..clear()
        ..addEntries(r.devices.map((d) => MapEntry(d.id, d)));
      _devAt = DateTime.now();
    } else {
      _readings
        ..clear()
        ..addAll(r.readings);
      _readAt = DateTime.now();
    }
    version.value++;
  }

  @visibleForTesting
  static void debugApply(VpnNowKind k, VpnNowResult r) => _apply(k, r);

  // ── طريق الوكيل (مربوط أم لا) — خمس دقائق ──
  static ({bool linked, String? via})? _route;
  static DateTime? _routeAt;
  static Future<({bool linked, String? via})?>? _routeP;

  @visibleForTesting
  static Future<({bool linked, String? via})?> Function() routeSource = VpnNowApi.route;

  static Future<({bool linked, String? via})?> route({bool force = false}) {
    final at = _routeAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(minutes: 5)) return Future.value(_route);
    return _routeP ??= routeSource().then((r) {
      _route = r;
      _routeAt = DateTime.now();
      return r;
    }).whenComplete(() => _routeP = null);
  }

  // ── إخفاء الهنت لباقي اليوم ──
  static final ValueNotifier<int> dismissals = ValueNotifier<int>(0);
  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  static String _key(VpnNowKind k) => 'vpnnow.dismiss.${k.wire}';

  static Future<bool> dismissedToday(VpnNowKind k) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString(_key(k)) == _today();
    } catch (_) {
      return false;
    }
  }

  static Future<void> dismiss(VpnNowKind k) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key(k), _today());
    } catch (_) {/* الذاكرة تكفي للجلسة */}
    dismissals.value++;
  }

  /// يُعيد الهنت (من قائمة القسم: «فحص عبر VPN»).
  static Future<void> undismiss(VpnNowKind k) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key(k));
    } catch (_) {}
    dismissals.value++;
  }

  /// خروجٌ/تبديل حساب — `SessionManager.clearAllSessionData`.
  static void reset() {
    _readings.clear();
    _devices.clear();
    _readAt = null;
    _devAt = null;
    _route = null;
    _routeAt = null;
    subscribers.reset();
    devices.reset();
    version.value++;
  }
}
