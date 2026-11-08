import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/api_client.dart';
import '../api/company_route.dart';
import '../core/util/error_text.dart';
import 'provider_service.dart';

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
///
/// «كل الشركات»: صفٌّ مدموج يحمل شركته ([company] = Subscriber.companyKey) —
/// مفتاحه «الشركة|idx» (رقمان من ساسين قد يلتقيان)، ودفعته لشركته وحدها
/// موجَّهةً إليها. كان يُسأل عنه الشركة المفتوحة فيرجع فارغاً.
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

  /// عمود «الاستهلاك» ظاهرٌ في جدول الحاسبة: إظهاره هو طلب رؤية الاستهلاك، فيُجلب كما لو فُعّل «عرض الاستهلاك»
  /// (المالك ٢٤ أكتوبر: «الاستهلاك ما يظهر» — العمود ظهر افتراضيّاً والجلب بقي معلّقاً على التفضيل المطفأ). يضبطه
  /// الجدول عند بنائه؛ الهاتف كما كان (التفضيل وحده).
  static bool columnShown = false;

  static String _key(String idx, String? company) =>
      company == null ? idx : '$company|$idx';

  // ── ⑯ «عند الطلب» (المشروع الوطنيّ، المالك ٥ نوفمبر: «كونه ثكيل استعلامته… ينقر ع عرض الاستهلاك حتى يكون بطلب منفصل») ──
  // لا دفعات للصفوف الظاهرة: كلّ مشتركٍ بلمسة ([requestOne] — `?ids=<idx>&one=1`، والتحديث `&fresh=1`). الشركة المفتوحة من
  // مزوّدها ([ProviderService.usageOnDemand])، وأيّ شركةٍ ردّت دفعتها `on_demand` (صفوف «كل الشركات») تُعرف من ردّها.
  static final _onDemand = <String>{}; // '' = الشركة المفتوحة، وإلّا مفتاح شركة الصفّ
  static final _oneBusy = <String>{};
  static final _err = <String, String>{};

  /// صفوف هذه الشركة «عند الطلب» (زرّ «عرض الاستهلاك») لا دفعات.
  static bool isOnDemand(String? company) => company == null
      ? (ProviderService.usageOnDemand || _onDemand.contains(''))
      : _onDemand.contains(company);

  /// حال صفٍّ «عند الطلب»: يُجلب · قيمته (تبقى بعد جلبها) · سبب التعذّر — وكلّها فارغة = لم يُطلب بعد.
  static ({bool loading, SubscriberUsage? v, String? err}) one(String idx, {String? company}) {
    final k = _key(idx, company);
    return (loading: _oneBusy.contains(k), v: _cache[k]?.v, err: _err[k]);
  }

  /// لمسة «عرض الاستهلاك» (أو التحديث بـ[fresh]): طلبٌ لمشتركٍ واحد — الخادم يجلب جلسته وسجلّه وحده.
  static Future<void> requestOne(String idx, {String? company, bool fresh = false}) async {
    final k = _key(idx, company);
    if (idx.isEmpty || _oneBusy.contains(k)) return;
    final gen = _gen;
    _oneBusy.add(k);
    _err.remove(k);
    version.value++;
    SubscriberUsage? v;
    String? msg;
    try {
      final r = await CompanyRoute.run(
        company,
        () => ApiClient.dio.get<Map<String, dynamic>>(
          '/api/v2/subscribers-usage',
          queryParameters: {'ids': idx, 'one': '1', if (fresh) 'fresh': '1'},
        ),
      );
      final body = r.data ?? const {};
      final d = body['data'];
      final u = d is Map ? d[idx] : null;
      if (body['success'] == true && u is Map) {
        v = SubscriberUsage(today: _int(u['today']), month: _int(u['month']));
      } else {
        msg = (body['message'] ?? 'تعذّر جلب الاستهلاك — أعد بعد قليل').toString();
      }
    } catch (e) {
      msg = humanError(e, fallback: 'تعذّر جلب الاستهلاك — أعد بعد قليل');
    }
    if (gen != _gen) return; // حسابٌ آخر الآن
    _oneBusy.remove(k);
    if (v != null) {
      _cache[k] = (at: DateTime.now(), v: v);
    } else {
      _err[k] = msg ?? 'تعذّر جلب الاستهلاك';
    }
    if (_err.length > 2000) _err.remove(_err.keys.first);
    version.value++;
  }

  static String? _companyOf(String key) {
    final i = key.indexOf('|');
    return i < 0 ? null : key.substring(0, i);
  }

  /// `null` = لم يصل بعد · قيمة `v` null = تعذّر.
  static ({SubscriberUsage? v})? get(String idx, {String? company}) {
    final e = _cache[_key(idx, company)];
    return e == null ? null : (v: e.v);
  }

  static void want(String idx, {String? company}) {
    if (isOnDemand(company)) return; // ⑯ لمسةٌ لكلّ مشترك، لا دفعة
    final k = _key(idx, company);
    if (idx.isEmpty || _busy.contains(k) || _queue.contains(k)) return;
    final e = _cache[k];
    if (e != null &&
        DateTime.now().difference(e.at) < (e.v != null ? _ttl : _failTtl)) {
      return;
    }
    _queue.add(k);
    _timer ??= Timer(const Duration(milliseconds: 150), () {
      _timer = null;
      _pump();
    });
  }

  static Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && (UsagePrefs.enabled.value || columnShown)) {
        final gen = _gen;
        // دفعةٌ لشركةٍ واحدة (الشركة المفتوحة، أو شركة صفٍّ مدموج)
        final company = _companyOf(_queue.first);
        final batch =
            _queue.where((k) => _companyOf(k) == company).take(_batch).toList();
        _queue.removeAll(batch);
        _busy.addAll(batch);
        final ids = [
          for (final k in batch)
            company == null ? k : k.substring(company.length + 1),
        ];
        Map<String, dynamic> data = const {};
        var ok = false;
        var od = false;
        try {
          final r = await CompanyRoute.run(
            company,
            () => ApiClient.dio.get<Map<String, dynamic>>(
              '/api/v2/subscribers-usage',
              queryParameters: {'ids': ids.join(',')},
            ),
          );
          final body = r.data ?? const {};
          ok = body['success'] == true;
          od = body['on_demand'] == true;
          final d = body['data'];
          if (d is Map<String, dynamic>) data = d;
        } catch (e) {
          if (kDebugMode) debugPrint('🔴 subscribers-usage: $e');
        }
        _busy.removeAll(batch);
        if (gen != _gen) continue; // حسابٌ آخر الآن
        // ⑯ خادم الشركة يقول «عند الطلب»: ما بقي بلا قيمة يصير زرّاً (لا «—» ولا إعادة) وتُترك دفعاتها
        if (od) {
          _onDemand.add(company ?? '');
          _queue.removeWhere((k) => _companyOf(k) == company);
        }
        final now = DateTime.now();
        for (var i = 0; i < batch.length; i++) {
          final u = data[ids[i]];
          if (od && u is! Map) continue;
          _cache[batch[i]] = (
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

  // ── الترتيب بالاستهلاك (٨ نوفمبر — المالك: «فترتب المشتركين… اضف حسب الاستهلاك الشهري واليوم تصاعدي وتنازلي») ──
  // الساس لا يعطي استهلاك الشهر في صفّ القائمة ولا تقريراً جماعيّاً له — يُقرأ لكلّ مشتركٍ من خادمنا (تقرير user/traffic، ويخبّئه
  // الخادم ١٠ دقائق). فالترتيب به طلبٌ صريح: يُجلب لصفوف القائمة كلّها دفعةً بعد دفعة (٤٠، شركةً شركة، طلبٌ واحد في وقته — لا
  // ضغطٌ على الساس)، بلا شرط «عرض الاستهلاك»، وما جُلب قبل ٥ دقائق لا يُعاد. «كل الشركات»: كلّ صفٍّ لشركته موجَّهاً لها.

  static int _sortGen = 0;

  /// يوقف جلب الترتيب الجاري (ترتيبٌ آخر أو مغادرة القائمة) — ما وصل يبقى في الكاش.
  static void cancelSortFetch() => _sortGen++;

  /// يجلب استهلاك [rows] (idx وشركة الصفّ) الناقص أو القديم. [onProgress] بعد كلّ دفعة (ما قُرئ من الكلّ). صفوف شركةٍ «عند الطلب»
  /// (الوطنيّ) لا تُجلب هنا — تبقى بلا قيمة. يعود حين ينتهي أو يُلغى ([cancelSortFetch]) أو تتبدّل الجلسة.
  static Future<void> ensureFor(
    List<({String idx, String? company})> rows, {
    void Function(int done, int total)? onProgress,
  }) async {
    final myGen = ++_sortGen;
    final gen = _gen;
    final now = DateTime.now();
    final need = <String>[];
    final seen = <String>{};
    for (final r in rows) {
      if (r.idx.isEmpty || isOnDemand(r.company)) continue;
      final k = _key(r.idx, r.company);
      if (!seen.add(k)) continue;
      final e = _cache[k];
      if (e != null && now.difference(e.at) < (e.v != null ? _ttl : _failTtl)) continue;
      need.add(k);
    }
    final total = need.length;
    var done = 0;
    onProgress?.call(done, total);
    while (need.isNotEmpty) {
      if (myGen != _sortGen || gen != _gen) return;
      final company = _companyOf(need.first);
      final batch = need.where((k) => _companyOf(k) == company).take(_batch).toList();
      need.removeWhere(batch.contains);
      final ids = [for (final k in batch) company == null ? k : k.substring(company.length + 1)];
      Map<String, dynamic> data = const {};
      var ok = false;
      var od = false;
      try {
        final r = await CompanyRoute.run(
          company,
          () => ApiClient.dio.get<Map<String, dynamic>>(
            '/api/v2/subscribers-usage',
            queryParameters: {'ids': ids.join(',')},
          ),
        );
        final body = r.data ?? const {};
        ok = body['success'] == true;
        od = body['on_demand'] == true;
        final d = body['data'];
        if (d is Map<String, dynamic>) data = d;
      } catch (e) {
        if (kDebugMode) debugPrint('🔴 subscribers-usage (sort): $e');
      }
      if (gen != _gen) return; // حسابٌ آخر الآن
      if (od) {
        _onDemand.add(company ?? '');
        need.removeWhere((k) => _companyOf(k) == company);
      }
      final at = DateTime.now();
      for (var i = 0; i < batch.length; i++) {
        final u = data[ids[i]];
        if (od && u is! Map) continue;
        _cache[batch[i]] = (
          at: at,
          v: ok && u is Map ? SubscriberUsage(today: _int(u['today']), month: _int(u['month'])) : null,
        );
      }
      while (_cache.length > 5000) {
        _cache.remove(_cache.keys.first);
      }
      done += batch.length;
      version.value++;
      if (myGen == _sortGen) onProgress?.call(done > total ? total : done, total);
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
    _onDemand.clear();
    _oneBusy.clear();
    _err.clear();
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
