import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/subscriber.dart';
import '../services/auth_storage.dart';
import 'api_client.dart';

/// الحسابات الكبيرة (٢١ أكتوبر ٢٠٢٦): من [threshold] مشتركاً فأكثر لا تُطلب القائمة الكاملة — ٨٩ ألف مشترك ≈ ٩٦ث و٥٩
/// ميغا (admin@full) تتجاوز مهلة ٣٠ث، وشاشة المشتركين كانت تعيدها كلّ ٥ ثوانٍ. تُجلب الصفحة المعروضة من الساس
/// (`/api/v2/subscribers?page=`) بتبويبها وبحثها وترتيبها، والعدّادات من `/api/v2/subscribers-summary` — بتعريفات هذا
/// التطبيق نفسها (summary.app: الفعّال/المنتهي/المتصل يشمل المعطّل، و«قارب الانتهاء» أقلّ من ٤ أيّام). الأصغر كما كان.
class BigSubscribersApi {
  BigSubscribersApi._();

  static const int threshold = 5000;
  static const Duration _probeTtl = Duration(minutes: 10);

  static int? _probeTotal;
  static DateTime? _probeAt;
  static String? _probeToken;
  static Future<int>? _probeInFlight;

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
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final b = r.data ?? const {};
      if (b['success'] != true || b['paged'] != true) {
        throw BigListException((b['message'] as String?)?.trim().isNotEmpty == true
            ? b['message'] as String
            : 'تعذّر جلب صفحة المشتركين');
      }
      final rows = ((b['data'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Subscriber.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      int n(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
      return BigPage(rows: rows, total: n(b['total']), lastPage: n(b['last_page']) <= 0 ? 1 : n(b['last_page']));
    } on DioException catch (e) {
      final m = e.response?.data is Map ? (e.response!.data as Map)['message'] : null;
      throw BigListException(m is String && m.trim().isNotEmpty ? m : 'تعذّر جلب صفحة المشتركين — تحقّق من الاتصال');
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

  /// عدّادات الساس بتعريفات هذا التطبيق (summary.app). `null` عند الفشل — لا أصفار مزعومة.
  static Future<BigCounts?> summary() async {
    final token = await AuthStorage.readToken();
    if (token == null || token.isEmpty) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers-summary',
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
  }

  @visibleForTesting
  static void debugSetBig(int total) {
    _probeTotal = total;
    _probeAt = DateTime.now();
  }
}

class BigPage {
  const BigPage({required this.rows, required this.total, required this.lastPage});
  final List<Subscriber> rows;
  final int total;
  final int lastPage;
}

/// عدّادات summary.app — الدين `null` (في notes الساس ولا يُفلتر هناك).
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
  });

  final int all;
  final int active;
  final int expired;
  final int online;
  final int offline;
  final int disabled;
  final int nearExpiry;
  final int onlineNoPlan;

  factory BigCounts.fromJson(Map<String, dynamic> j) {
    int n(String k) => j[k] is num ? (j[k] as num).toInt() : int.tryParse('${j[k]}') ?? 0;
    return BigCounts(
      all: n('all'),
      active: n('active'),
      expired: n('expired'),
      online: n('online'),
      offline: n('offline'),
      disabled: n('disabled'),
      nearExpiry: n('nearExpiry'),
      onlineNoPlan: n('onlineNoPlan'),
    );
  }
}

class BigListException implements Exception {
  const BigListException(this.message);
  final String message;
  @override
  String toString() => message;
}
