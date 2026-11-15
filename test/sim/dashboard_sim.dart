// محاكي «سرعة الرئيسيّة ودقّتها» (١٦ نوفمبر ٢٠٢٦ — المالك: «سوي محاكاة بحيث تضمن دقه المعلومات والسرعه»).
//
// يشغّل **الكود الحقيقيّ** للرئيسيّة (DashboardScreen وكلّ ما تحته: الفحص، القائمة، ترتيب «المشتركين أوّلاً»، البطاقات) على خادمٍ
// وهميّ بنموذج شبكةٍ وساس معايَر على الواقع:
//   • الشبكة: ٨ اتّصالات للمضيف (ApiClient)، والشبكة لا تجيب قبل «إحماء» أوّل فتح (DNS/TLS) — قِيس على المحاكي ١٦ نوفمبر:
//     كلّ طلبات الموجة الأولى انتهت معاً ~١٫١٥ث بعد فتح الرئيسيّة؛ وموجة البداية (app-gate، employees/me، auth/me، ai/status…)
//     تُحقن بمواعيدها المقيسة فتزاحم كما في الواقع.
//   • الساس: زمن الخادم لكلّ نداء — ثابتٌ معايَر (دافئ/بارد كما قِيس) أو عيّنةٌ من توزيع nginx الحقيقيّ لكلّ الوكلاء (١٥ نوفمبر).
// ويقيس لكلّ فتح: متى ظهرت أرقام المشتركين/الرصيد/الواتساب/النشاطات/الإيرادات/الباقات، وكم طلباً للساس، ويتحقّق من الدقّة:
// الأرقام من القائمة الحيّة لهذا الفتح نفسه، قائمةٌ كاملة واحدة، الكبير بلا قائمة كاملة أبداً، والبقيّة خلف المشتركين.
//
// المحرّك وحده (بلا main): dashboard_load_sim_test.dart يقارن ويكتب النتائج، وdashboard_fast_open_test.dart يحرس السرعة.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/dashboard/dashboard_screen.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/recent_activities.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/stats_grid.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/subscribers_card.dart';
import 'package:rad_mysvcs/services/dashboard_load_order.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../visual_perm/visual_perm_harness.dart';

export '../visual_perm/visual_perm_harness.dart' show fixtureSubscribers, visualSetUpAll;

// ─────────────────────────────── النموذج ───────────────────────────────

/// زمن الخادم (ثوانٍ) للنداءات المعتمدة على الساس في فتحٍ واحد.
class Sas {
  const Sas(this.probe, this.list, this.packages);
  final double probe, list, packages;
}

class Profile {
  const Profile(this.name, this.sas, {this.storedSmall = true, this.bigTotal});
  final String name;
  final Sas sas;

  /// الجهاز يعرف الحساب صغيراً من فتحٍ سابق (يُزرع حكم ①؛ الفرع القديم لا يقرؤه أصلاً).
  final bool storedSmall;

  /// حسابٌ كبير: الفحص يعيد هذا المجموع.
  final int? bigTotal;
}

/// معايَرة على القياس الحيّ (١٦ نوفمبر، المحاكي، admin@popq):
/// - الشبكة تجهز ~٠٫٩٢ث بعد أوّل طلب في فتحٍ بارد للتطبيق؛ ذهاب/إياب ٠٫١ث؛ مصافحة اتّصالٍ جديد ٠٫١ث.
/// - الساس دافئ: الفحص ٠٫٢١٥ث والقائمة ٠٫٨١٨ث كاملتين ⇒ خادمٌ ٠٫١١٥/٠٫٧٢؛ بارد (الدخول): ٢٫٩٨٧/٢٫٨٦٥/٢٫٩٢٧ ⇒ ٢٫٨٩/٢٫٧٧/٢٫٨٣.
const kWarmUp = 0.92, kRtt = 0.10, kHandshake = 0.10, kMaxConn = 8;
const warm = Sas(0.115, 0.72, 0.02);
const cold = Sas(2.89, 2.77, 2.83);

/// زمن خادمٍ لما ليس من الساس.
const _serverTime = <String, double>{
  '/api/admin/view-scope': 0.03,
  '/api/reports/finance': 0.03,
  '/api/v2/admin-widgets': 0.09,
  '/api/activities/daily-activations': 0.035,
};

/// موجة بداية التطبيق (ليست من الرئيسيّة) بمواعيدها المقيسة نسبةً لفتح الرئيسيّة (فتحٌ بارد، ١٦ نوفمبر).
/// (ai/status وrenew-settings وtickets/summary تطلبها الرئيسيّة نفسها — لا تُحقن مرّتين.)
const _wave = <(int, String, String)>[
  (0, 'GET', '/api/app-gate'),
  (0, 'GET', '/api/v2/employees/me'),
  (166, 'GET', '/api/v2/employee-ledger/me'),
  (179, 'GET', '/api/auth/me'),
  (354, 'POST', '/api/fcm/register'),
];

class Req {
  Req(this.method, this.path, this.query, this.start);
  final String method, path, query;
  final double start;
  double? end;
  bool get isList => path == '/api/v2/subscribers' && !query.contains('page=');
  bool get isProbe => path == '/api/v2/subscribers' && query.contains('size=1');
  Map<String, Object?> toJson() => {'m': method, 'p': path, 'q': query, 's': _r(start), 'e': end == null ? null : _r(end!)};
}

double _r(double v) => (v * 1000).roundToDouble() / 1000;

class _Conn {
  bool busy = true;
  double lastUsed = 0;
}

/// الشبكة والخادم الوهميّان — فوق VisualServer (أجوبته) بزمنٍ معايَر.
class NetSim implements HttpClientAdapter {
  NetSim(this.inner, this.p, this.t0Wall);
  final VisualServer inner;
  final Profile p;
  final DateTime t0Wall;
  final reqs = <Req>[];
  final _conns = <_Conn>[];
  final _waiters = <Completer<_Conn>>[];
  double? _netReady;
  bool _waveStarted = false;

  double now() => TestWidgetsFlutterBinding.instance.clock.now().difference(t0Wall).inMicroseconds / 1e6;

  Future<void> _sleep(double s) => s <= 0 ? Future<void>.value() : Future<void>.delayed(Duration(microseconds: (s * 1e6).round()));

  Future<_Conn> _acquire() {
    final t = now();
    _conns.removeWhere((c) => !c.busy && t - c.lastUsed >= 15);
    for (final c in _conns) {
      if (!c.busy) {
        c.busy = true;
        return Future.value(c);
      }
    }
    if (_conns.length < kMaxConn) {
      final c = _Conn();
      _conns.add(c);
      return Future.value(c..lastUsed = -1); // جديد
    }
    final w = Completer<_Conn>();
    _waiters.add(w);
    return w.future;
  }

  void _release(_Conn c) {
    c.lastUsed = now();
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(c);
    } else {
      c.busy = false;
    }
  }

  double _server(RequestOptions o) {
    final path = o.uri.path;
    if (path == '/api/v2/subscribers') return o.uri.queryParameters.containsKey('page') ? p.sas.probe : p.sas.list;
    if (path == '/api/reports/finance/packages') return p.sas.packages;
    if (path.startsWith('/api/whatsapp/connection-status/')) return 0.02;
    return _serverTime[path] ?? 0.05;
  }

  void _startWave() {
    if (_waveStarted) return;
    _waveStarted = true;
    for (final (ms, method, path) in _wave) {
      unawaited(_sleep(ms / 1000).then((_) => ApiClient.dio
          .request<Object?>(path, options: Options(method: method))
          .then((_) {}, onError: (_) {})));
    }
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cancel) async {
    final rec = Req(o.method.toUpperCase(), o.uri.path, o.uri.query, now());
    reqs.add(rec);
    // فتح الرئيسيّة = أوّل طلبٍ منها ⇒ موجة البداية معه والشبكة «تُحمّى» من هنا
    _netReady ??= rec.start + kWarmUp;
    _startWave();
    final c = await _acquire();
    final fresh = c.lastUsed < 0;
    final wait = math.max(0.0, _netReady! - now());
    await _sleep(wait + (fresh ? kHandshake : 0) + kRtt + _server(o));
    final resp = await _respond(o);
    rec.end = now();
    _release(c);
    return resp;
  }

  Future<ResponseBody> _respond(RequestOptions o) async {
    // الفحص كالخادم الحقيقيّ: مرقَّمٌ بمجموعه وصفٌّ واحد
    if (o.uri.path == '/api/v2/subscribers' && o.uri.queryParameters['size'] == '1') {
      final total = p.bigTotal ?? fixtureSubscribers.length;
      return ResponseBody.fromString(
          jsonEncode({'success': true, 'paged': true, 'total': total, 'last_page': total, 'data': [fixtureSubscribers.first]}), 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          });
    }
    return inner.fetch(o, null, null);
  }

  @override
  void close({bool force = false}) {}
}

// ─────────────────────────────── القياس ───────────────────────────────

class Run {
  Run(this.profile, this.seed);
  final String profile;
  final int seed;
  final m = <String, double?>{};
  final checks = <String, Object?>{};
  List<Req> reqs = const [];
  Map<String, Object?> toJson() => {
        'profile': profile,
        'seed': seed,
        'milestones': {for (final e in m.entries) e.key: e.value == null ? null : _r(e.value!)},
        'checks': checks,
        'requests': [for (final q in reqs) q.toJson()],
      };
}

bool _subsShown(WidgetTester t) {
  final f = find.byType(SubscribersCard);
  return f.evaluate().isNotEmpty && t.widget<SubscribersCard>(f.first).stats != null;
}

Object? _stats(WidgetTester t) {
  final f = find.byType(SubscribersCard);
  if (f.evaluate().isEmpty) return null;
  final s = t.widget<SubscribersCard>(f.first).stats;
  if (s == null) return null;
  return {'total': s.total, 'active': s.active, 'online': s.online, 'offline': s.offline, 'expired': s.expired, 'near': s.nearExpiry};
}

bool _walletShown(WidgetTester t) {
  final f = find.byType(StatsGrid);
  return f.evaluate().isNotEmpty && t.widget<StatsGrid>(f.first).wallet != null;
}

bool _debtShown(WidgetTester t) {
  final f = find.byType(StatsGrid);
  return f.evaluate().isNotEmpty && t.widget<StatsGrid>(f.first).debtors != null;
}

bool _waShown(WidgetTester t) => find
    .byWidgetPredicate((w) => w.runtimeType.toString() == '_WAStatusChip' && (w as dynamic).loaded == true)
    .evaluate()
    .isNotEmpty;

bool _actShown(WidgetTester t) =>
    find.byType(RecentActivities).evaluate().isNotEmpty ||
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_NoActivitiesYet').evaluate().isNotEmpty;

Future<Run> simulate(WidgetTester t, Profile p, int seed) async {
  final run = Run(p.name, seed);
  final server = await visualSetUp(s1bSasOwner);
  BigSubscribersApi.reset();
  SubscribersApi.clearAllCaches();
  DashboardLoadOrder.debugReset();
  // حكم ① من «فتحٍ سابق» — مفتاحه: المدير|الدور|اسم الدخول (visualSetUp: supernet:12 / mahdi)
  SharedPreferences.setMockInitialValues({
    if (p.storedSmall)
      'subs_known_size_v1': jsonEncode({
        'supernet:12|m|mahdi': {
          'size': p.bigTotal ?? fixtureSubscribers.length,
          'paged': true,
          'at': DateTime.now().millisecondsSinceEpoch,
        },
      }),
  });
  final sim = NetSim(server, p, TestWidgetsFlutterBinding.instance.clock.now());
  ApiClient.dio.httpClientAdapter = sim;

  await pumpVisual(t, phone, home: (_) => const DashboardScreen());
  const step = Duration(milliseconds: 20);
  double? t0;
  for (var i = 0; i < 45000 ~/ 20; i++) { // ٤٥ث: أبعد من مهلة التطبيق (٢٠ث) فتنتهي كلّ عيّنة بأرقامٍ أو بـ«تعذّر»
    await t.pump(step);
    t0 ??= sim.reqs.isEmpty ? null : sim.reqs.first.start;
    if (t0 == null) continue;
    final now = sim.now() - t0;
    void mark(String k, bool shown) {
      if (shown && run.m[k] == null) run.m[k] = now;
    }

    mark('subs', _subsShown(t));
    mark('debt', _debtShown(t));
    mark('wallet', _walletShown(t));
    mark('wa', _waShown(t));
    mark('act', _actShown(t));
    if (run.m['subs'] != null && run.checks['stats'] == null) run.checks['stats'] = _stats(t);
    // كلّ شيءٍ ظهر وكلّ طلبٍ انتهى ⇒ نصف ثانيةٍ للتأكّد ثمّ نكفّ
    final done = ['subs', 'wallet', 'wa', 'act'].every((k) => run.m[k] != null) &&
        sim.reqs.any((q) => q.path == '/api/reports/finance/packages' && q.end != null) &&
        sim.reqs.any((q) => q.path == '/api/reports/finance' && q.end != null) &&
        sim.reqs.every((q) => q.end != null);
    if (done && run.m['_done'] == null) run.m['_done'] = now;
    if (run.m['_done'] != null && now - run.m['_done']! > 0.5) break;
    // الكبير لا تظهر حلقته من هذا الخادم الوهميّ (لا ملخّص فيه) — يكفيه ما يثبت أنّ القائمة الكاملة لم تُطلب
    if (p.bigTotal != null && now > 10) break;
  }
  run.m.remove('_done');
  final base = t0 ?? 0;
  double? endOf(bool Function(Req) f) {
    final r = sim.reqs.where(f).where((q) => q.end != null).toList();
    return r.isEmpty ? null : r.first.end! - base;
  }

  run.m['sections'] = endOf((q) => q.path == '/api/admin/view-scope');
  run.m['probe_end'] = endOf((q) => q.isProbe);
  run.m['list_end'] = endOf((q) => q.isList);
  run.m['revenue'] = endOf((q) => q.path == '/api/reports/finance');
  run.m['packages'] = endOf((q) => q.path == '/api/reports/finance/packages');
  final shown = ['subs', 'wallet', 'wa', 'act', 'revenue', 'packages'].map((k) => run.m[k]).whereType<double>();
  run.m['all'] = shown.isEmpty ? null : shown.reduce(math.max);

  // ── الدقّة ──
  final lists = sim.reqs.where((q) => q.isList).toList();
  run.checks['list_requests'] = lists.length;
  run.checks['probe_requests'] = sim.reqs.where((q) => q.isProbe).length;
  run.checks['numbers_from_this_open'] =
      run.m['subs'] == null ? null : lists.isNotEmpty && lists.first.end != null && lists.first.end! - base <= run.m['subs']! + 1e-6;
  // البقيّة (الرصيد/الواتساب/النشاطات) خلف المشتركين أو مهلتهم (٦ث)
  final listEnd = run.m['list_end'];
  final rest = sim.reqs.where((q) =>
      q.path == '/api/v2/admin-widgets' ||
      q.path.startsWith('/api/whatsapp/connection-status/') ||
      q.path == '/api/activities/daily-activations');
  run.checks['rest_after_subs'] = rest.every((q) {
    final s = q.start - base;
    return (listEnd != null && s >= listEnd - 0.05) || s >= DashboardLoadOrder.maxWait.inMilliseconds / 1000 - 0.05;
  });
  run.reqs = sim.reqs;

  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 30)); // مؤقّتات الرئيسيّة (التبريد، مهلة الترتيب، التجديد الخلفيّ)
  await visualTearDown();
  return run;
}

// ─────────────────────────────── التوزيع الحقيقيّ ───────────────────────────────

List<double> latencyQuantiles(Map<String, dynamic> j, String k) => [for (final v in (j['quantiles'][k]['q'] as List)) (v as num).toDouble()];

double quantileAt(List<double> q, double u) {
  final x = u * (q.length - 1);
  final i = x.floor();
  if (i >= q.length - 1) return q.last;
  return q[i] + (q[i + 1] - q[i]) * (x - i);
}


// ─────────────────────────────── الدقّة ───────────────────────────────

/// مخالفات الدقّة لفتحٍ واحد ([] = سليم). لا رقم يظهر إلّا من قائمة هذا الفتح الحيّة وبقيمة الحقيقة؛ ولا تكرار للقائمة؛ والبقيّة خلف
/// المشتركين. فتحٌ لم تصل قائمته قبل مهلة التطبيق (٢٠ث، ذيل الساس) لا يعرض رقماً — وهذا صحيح لا مخالفة (يُعدّ «تعذّر»).
List<String> violations(Run r, {bool big = false}) {
  final v = <String>[];
  final lists = r.checks['list_requests'] as int;
  if (big) {
    if (lists != 0) v.add('حسابٌ كبير طُلبت قائمته الكاملة');
    return v;
  }
  if (lists > 1) v.add('أكثر من قائمةٍ كاملة في فتحٍ واحد');
  if (r.checks['rest_after_subs'] != true) v.add('بطاقةٌ سبقت المشتركين (ترتيب ١٤ نوفمبر)');
  final s = r.checks['stats'] as Map?;
  if (s != null) {
    if (r.checks['numbers_from_this_open'] != true) v.add('أرقامٌ ظهرت قبل وصول قائمة هذا الفتح');
    if (s['total'] != fixtureSubscribers.length) v.add('مجموع المشتركين غير الحقيقة: ${s['total']}');
  } else {
    final le = r.m['list_end'];
    final timedOut = le == null || le > 20 - 0.05; // مهلة fetchDebtors ٢٠ث
    if (!timedOut) v.add('لم تظهر الأرقام مع أنّ القائمة وصلت في وقتها');
  }
  return v;
}

