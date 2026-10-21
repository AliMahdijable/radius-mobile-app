import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/subscriber.dart';
import '../services/auth_storage.dart';
import 'api_client.dart';

/// الحسابات الكبيرة (٢١ أكتوبر ٢٠٢٦): من [threshold] مشتركاً فأكثر لا تُطلب القائمة الكاملة — ٨٩ ألف مشترك ≈ ٩٦ث و٥٩
/// ميغا (admin@full) تتجاوز مهلة ٣٠ث، وشاشة المشتركين كانت تعيدها كلّ ٥ ثوانٍ. تُجلب الصفحة المعروضة من الساس
/// (`/api/v2/subscribers?page=`) بتبويبها وبحثها وترتيبها وفلتر المدير، والعدّادات من `/api/v2/subscribers-summary?for=app`
/// — بتعريفات هذا التطبيق نفسها (summary.app: الفعّال/المنتهي/المتصل يشمل المعطّل، و«قارب الانتهاء» أقلّ من ٤ أيّام، والجرس:
/// انتهى اليوم وأقلّ من ٢٤ ساعة، والدين من notes حين يُعرف). الأصغر كما كان.
class BigSubscribersApi {
  BigSubscribersApi._();

  static const int threshold = 5000;
  static const Duration _probeTtl = Duration(minutes: 10);

  static int? _probeTotal;
  static DateTime? _probeAt;
  static String? _probeToken;
  static Future<int>? _probeInFlight;

  /// الملخّص يُطلب من ثلاث جهات معاً (الرئيسية، الجرس، المشتركين) — نداءٌ واحد لكلّ ٢٠ثانية لكلّ فلتر.
  static const Duration _summaryTtl = Duration(seconds: 20);
  static final Map<String, ({DateTime at, BigCounts value})> _summaryCache = {};
  static final Map<String, Future<BigCounts?>> _summaryInFlight = {};

  /// آخر ما عُرف: الحساب كبير (≥ [threshold]). لا يسأل الشبكة.
  static bool get knownBig => (_probeTotal ?? 0) > 0;

  /// عدد مشتركي الحساب إن كان كبيراً، وإلّا ٠. صفٌّ واحد من الساس (`?page=1&size=1`) — بلا القائمة الكاملة.
  /// ردٌّ بلا `paged` (ايرث لنك/FTTH، أو خادمٌ أقدم) أو فشلٌ = ليس كبيراً ⇒ المسار المعتاد كما كان. لا يرمي.
  static Future<int> probe() async {
    final token = await AuthStorage.readToken();
    if (token == null || token.isEmpty) return 0;
    final at = _probeAt;
    if (_probeTotal != null && at != null && _probeToken == token && DateTime.now().difference(at) < _probeTtl) {
      return _probeTotal!;
    }
    final running = _probeInFlight;
    if (running != null) return running;
    final f = _probe(token);
    _probeInFlight = f;
    try {
      return await f;
    } finally {
      _probeInFlight = null;
    }
  }

  static Future<int> _probe(String token) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers',
        queryParameters: const {'page': 1, 'size': 1},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final b = r.data ?? const {};
      final total = b['total'] is num ? (b['total'] as num).toInt() : int.tryParse('${b['total']}') ?? 0;
      final big = b['success'] == true && b['paged'] == true && total >= threshold ? total : 0;
      _probeTotal = big;
      _probeAt = DateTime.now();
      _probeToken = token;
      return big;
    } catch (e) {
      if (kDebugMode) debugPrint('🟡 big probe: $e');
      return 0; // لا نحكم بلا جواب — المسار المعتاد
    }
  }

  /// صفحةٌ من التبويب — الصفوف بشكل القائمة الكاملة نفسه (الدين، الأسعار، الخصم)، و`total` مجموع التبويب كلّه.
  /// يرمي [BigListException] عند الفشل (الشاشة تقول «تعذّر» ولا تعرض قائمةً ناقصة).
  static Future<BigPage> page({
    required int page,
    int size = 50,
    required String tab,
    String? query,
    String? sort,
    String dir = 'asc',
    int? parentId,
  }) async {
    final token = await AuthStorage.readToken();
    if (token == null || token.isEmpty) throw const BigListException('انتهت الجلسة — سجّل الدخول من جديد');
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers',
        queryParameters: {
          'page': page,
          'size': size,
          'tab': tab,
          if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
          if (sort != null) 'sort': sort,
          'dir': dir,
          if (parentId != null && parentId > 0) 'parent_id': parentId,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final b = r.data ?? const {};
      if (b['success'] != true || b['paged'] != true) {
        // ApiClient يقبل 4xx ردّاً (لا استثناءً) — فالرمز يُقرأ هنا أيضاً (TAB_UNSUPPORTED ⇒ نصّ «مديون» لا خطأ)
        throw BigListException(
          (b['message'] as String?)?.trim().isNotEmpty == true ? b['message'] as String : 'تعذّر جلب صفحة المشتركين',
          code: b['code'] is String ? b['code'] as String : null,
        );
      }
      final rows = ((b['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Subscriber.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      int n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      return BigPage(
        rows: rows,
        total: n(b['total']),
        lastPage: n(b['last_page']) <= 0 ? 1 : n(b['last_page']),
        approx: b['approx'] == true,
      );
    } on DioException catch (e) {
      final d = e.response?.data is Map ? e.response!.data as Map : const {};
      final m = d['message'];
      throw BigListException(
        m is String && m.trim().isNotEmpty ? m : 'تعذّر جلب صفحة المشتركين — تحقّق من الاتصال',
        code: d['code'] is String ? d['code'] as String : null,
      );
    }
  }

  /// مشتركٌ واحد بيوزره (ومعرّفه إن عُرف) — للحساب الكبير بدل البحث في القائمة الكاملة (فتح إشعار، تحديث شاشة التفاصيل).
  /// `null` إن لم يُوجد أو فشل — لا يرمي.
  static Future<Subscriber?> findOne({String? idx, required String username}) async {
    final u = username.trim();
    if (u.isEmpty) return null;
    try {
      final p = await page(page: 1, size: 20, tab: 'all', query: u);
      if (idx != null) {
        for (final s in p.rows) {
          if (s.idx == idx) return s;
        }
      }
      for (final s in p.rows) {
        if (s.username.toLowerCase() == u.toLowerCase()) return s;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// عدّادات الساس بتعريفات هذا التطبيق (summary.app) — لفلتر مديرٍ إن مُرّر. `null` عند الفشل — لا أصفار مزعومة.
  /// [fresh] يتخطّى ذاكرة الـ٢٠ثانية (السحب للتحديث، وبعد عمليّة).
  static Future<BigCounts?> summary({int? parentId, bool fresh = false}) async {
    final token = await AuthStorage.readToken();
    if (token == null || token.isEmpty) return null;
    final key = '${token.hashCode}|${parentId ?? -1}';
    final hit = _summaryCache[key];
    if (!fresh && hit != null && DateTime.now().difference(hit.at) < _summaryTtl) return hit.value;
    final running = _summaryInFlight[key];
    if (running != null) return running;
    final f = _summary(token, parentId);
    _summaryInFlight[key] = f;
    try {
      final v = await f;
      if (v != null) _summaryCache[key] = (at: DateTime.now(), value: v);
      return v;
    } finally {
      _summaryInFlight.remove(key);
    }
  }

  static Future<BigCounts?> _summary(String token, int? parentId) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers-summary',
        queryParameters: {'for': 'app', if (parentId != null && parentId > 0) 'parent_id': parentId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final b = r.data ?? const {};
      final s = b['summary'];
      if (b['success'] != true || s is! Map || s['app'] is! Map) return null;
      return BigCounts.fromJson(Map<String, dynamic>.from(s['app'] as Map));
    } catch (e) {
      if (kDebugMode) debugPrint('🟡 big summary: $e');
      return null;
    }
  }

  /// من `SessionManager` — لا يرث الحساب التالي حكم سابقه.
  static void reset() {
    _probeTotal = null;
    _probeAt = null;
    _probeToken = null;
    _probeInFlight = null;
    _summaryCache.clear();
    _summaryInFlight.clear();
  }

  @visibleForTesting
  static void debugSetBig(int total) {
    _probeTotal = total;
    _probeAt = DateTime.now();
  }
}

/// بحث الساس بعد توقّف الكتابة لشاشات «اختر من المشتركين» (الخصومات، الأسعار) في الحساب الكبير — صفحةٌ واحدة من «الكل»
/// (الأوائل بلا بحث). جيلٌ لكلّ طلب: جوابٌ سبقه بحثٌ أحدث لا يُسلَّم.
class BigSearch {
  BigSearch({this.size = 100, this.delay = const Duration(milliseconds: 350)});
  final int size;
  final Duration delay;
  Timer? _timer;
  int _gen = 0;

  void search(String q, {required void Function(List<Subscriber> rows) onRows, void Function(String message)? onError, bool now = false}) {
    _timer?.cancel();
    final gen = ++_gen;
    Future<void> run() async {
      try {
        final t = q.trim();
        final p = await BigSubscribersApi.page(page: 1, size: size, tab: 'all', query: t.isEmpty ? null : t);
        if (gen == _gen) onRows(p.rows);
      } on BigListException catch (e) {
        if (gen == _gen) onError?.call(e.message);
      }
    }

    if (now) {
      unawaited(run());
    } else {
      _timer = Timer(delay, run);
    }
  }

  void dispose() => _timer?.cancel();
}

class BigPage {
  const BigPage({required this.rows, required this.total, required this.lastPage, this.approx = false});
  final List<Subscriber> rows;
  final int total;
  final int lastPage;

  /// المجموع تقريبيّ (مثلاً «مديون» قبل أن يكتمل عدّه في الخادم).
  final bool approx;
}

/// عدّادات summary.app. الدين `null` حين لا يُعرف (شركةٌ دينها على دفترنا، أو قبل أن يكتمل عدّه: [debtorsPending]).
class BigCounts {
  const BigCounts({
    required this.all,
    required this.active,
    required this.expired,
    required this.online,
    required this.offline,
    required this.disabled,
    required this.nearExpiry,
    required this.onlineNoPlan,
    this.expiredToday,
    this.expiring24h,
    this.debtors,
    this.totalDebt,
    this.debtorsPending = false,
    this.debtorsAt,
  });

  final int all;
  final int active;
  final int expired;
  final int online;
  final int offline;
  final int disabled;
  final int nearExpiry;
  final int onlineNoPlan;

  /// الجرس وصندوق الإشعارات: انتهى اليوم، ومتبقٍّ أقلّ من ٢٤ ساعة. `null` من خادمٍ أقدم.
  final int? expiredToday;
  final int? expiring24h;

  /// المدينون ومجموع ديونهم (notes سالبة) — `null` = غير معروف (لا صفر).
  final int? debtors;
  final double? totalDebt;
  final bool debtorsPending;
  final DateTime? debtorsAt;

  factory BigCounts.fromJson(Map<String, dynamic> j) {
    int n(String k) => j[k] is num ? (j[k] as num).toInt() : int.tryParse('${j[k]}') ?? 0;
    int? on(String k) => j[k] == null ? null : (j[k] is num ? (j[k] as num).toInt() : int.tryParse('${j[k]}'));
    final td = j['totalDebt'];
    final at = j['debtorsAt'];
    return BigCounts(
      all: n('all'),
      active: n('active'),
      expired: n('expired'),
      online: n('online'),
      offline: n('offline'),
      disabled: n('disabled'),
      nearExpiry: n('nearExpiry'),
      onlineNoPlan: n('onlineNoPlan'),
      expiredToday: on('expiredToday'),
      expiring24h: on('expiring24h'),
      debtors: on('debtors'),
      totalDebt: td is num ? td.toDouble() : double.tryParse('${td ?? ''}'),
      debtorsPending: j['debtorsPending'] == true,
      debtorsAt: at is num ? DateTime.fromMillisecondsSinceEpoch(at.toInt()) : null,
    );
  }
}

class BigListException implements Exception {
  const BigListException(this.message, {this.code});
  final String message;

  /// رمز الخادم إن وُجد (TAB_UNSUPPORTED: «مديون» لشركةٍ دينها على دفترنا).
  final String? code;
  @override
  String toString() => message;
}
