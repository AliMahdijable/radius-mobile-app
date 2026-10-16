import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// حالة باسورد إيداع ايرث لنك المحفوظ — بلا نصّه أبداً.
@immutable
class ElDepositStatus {
  const ElDepositStatus({
    required this.saved,
    required this.canManage,
    this.updatedAt,
  });

  final bool saved;

  /// صاحب الحساب (لا موظّف): يحفظ ويغيّر ويمسح.
  final bool canManage;
  final String? updatedAt;

  static const none = ElDepositStatus(saved: false, canManage: false);
}

/// باسورد إيداع ايرث لنك محفوظاً على الخادم (طلب المستخدم ١٦ أكتوبر: «مزعج كلّ
/// تفعيل يحط باسورد»).
///
/// الخادم يحفظه مشفّراً بطلب صاحب الحساب وحده، ويضيفه بنفسه لعمليّات الرصيد
/// (تفعيل/إضافة/تحويل/كشف) حين لا يُرسَل — فالموظّف يفعّل به دون أن يصل نصّه
/// للتطبيق. رفضته ايرث لنك ⇒ يمسحه ويردّ `saved_cleared` فيعود الحقل للإدخال.
///
/// [status] يتشاركه كلّ شيتٍ وشاشة؛ يُفرَّغ مع كلّ خروجٍ/تبديل حساب
/// (`SessionManager`) فلا يرى المدير التالي حالة سابقه.
class ElDepositPassword {
  ElDepositPassword._();

  /// `null` = لم يُحمَّل بعد.
  static final ValueNotifier<ElDepositStatus?> status =
      ValueNotifier<ElDepositStatus?>(null);
  static Future<ElDepositStatus>? _inflight;
  static DateTime? _at;

  /// جيل الجلسة — ردٌّ سُئل عنه قبل [reset] يخصّ حساباً سابقاً فلا يُطبَّق.
  static int _gen = 0;

  static Future<ElDepositStatus> load({bool force = false}) {
    final cur = status.value;
    final at = _at;
    if (!force &&
        cur != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(minutes: 5)) {
      return Future.value(cur);
    }
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  static Future<ElDepositStatus> _fetch() async {
    final gen = _gen;
    ElDepositStatus st;
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/el/deposit-password');
      final body = r.data ?? const {};
      final d = body['data'];
      st = body['success'] == true && d is Map
          ? ElDepositStatus(
              saved: d['saved'] == true,
              canManage: d['can_manage'] == true,
              updatedAt: d['updated_at']?.toString(),
            )
          // موظّفٌ بلا صلاحيّة (403) أو ردٌّ غير متوقّع ⇒ «غير محفوظ»: الحقل كما كان.
          : ElDepositStatus.none;
    } catch (e) {
      _log(e);
      st = status.value ?? ElDepositStatus.none;
    }
    if (gen != _gen) return ElDepositStatus.none;
    status.value = st;
    _at = DateTime.now();
    return st;
  }

  /// يُنادى بجسم كلّ ردٍّ لعمليّة رصيد (نجاحاً أو رفضاً): حُفظ الآن، أو مُسح
  /// لأنّ ايرث لنك رفضته.
  static void observe(Object? body) {
    if (body is! Map) return;
    final cur = status.value ?? ElDepositStatus.none;
    if (body['saved_cleared'] == true ||
        (body['code'] == 'DEPOSIT_PASSWORD_REQUIRED' && cur.saved)) {
      status.value = ElDepositStatus(saved: false, canManage: cur.canManage);
    } else if (body['deposit_password_saved'] == true && !cur.saved) {
      status.value = ElDepositStatus(
        saved: true,
        canManage: cur.canManage,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  /// PUT — صاحب الحساب وحده؛ الخادم يتحقّق منه لدى ايرث لنك (قراءة كشف الحساب
  /// بلا صرف) قبل أن يحفظه.
  static Future<({bool ok, String? message})> save(String password) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/v2/el/deposit-password',
        data: {'depositPassword': password},
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      if (ok) {
        status.value = ElDepositStatus(
          saved: true,
          canManage: true,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        );
        _at = DateTime.now();
      }
      return (
        ok: ok,
        message: body['message']?.toString() ??
            (ok ? null : 'تعذّر حفظ الباسورد'),
      );
    } on DioException catch (e) {
      _log(e);
      final b = e.response?.data;
      return (
        ok: false,
        message: (b is Map ? b['message']?.toString() : null) ??
            'تعذّر حفظ الباسورد — تحقّق من الاتصال',
      );
    } catch (e) {
      _log(e);
      return (ok: false, message: 'تعذّر حفظ الباسورد');
    }
  }

  /// DELETE — صاحب الحساب وحده.
  static Future<({bool ok, String? message})> remove() async {
    try {
      final r = await ApiClient.dio
          .delete<Map<String, dynamic>>('/api/v2/el/deposit-password');
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      if (ok) {
        final cur = status.value ?? ElDepositStatus.none;
        status.value = ElDepositStatus(saved: false, canManage: cur.canManage);
        _at = DateTime.now();
      }
      return (
        ok: ok,
        message: body['message']?.toString() ??
            (ok ? null : 'تعذّر مسح الباسورد'),
      );
    } on DioException catch (e) {
      _log(e);
      final b = e.response?.data;
      return (
        ok: false,
        message: (b is Map ? b['message']?.toString() : null) ??
            'تعذّر مسح الباسورد — تحقّق من الاتصال',
      );
    } catch (e) {
      _log(e);
      return (ok: false, message: 'تعذّر مسح الباسورد');
    }
  }

  /// خروجٌ/تبديل حساب — `SessionManager.clearAllSessionData`.
  static void reset() {
    _gen++;
    _inflight = null;
    _at = null;
    status.value = null;
  }

  static void _log(Object e) {
    if (kReleaseMode) return;
    if (e is DioException) {
      debugPrint('🔴 el/deposit-password: status=${e.response?.statusCode} type=${e.type.name}');
    } else {
      debugPrint('🔴 el/deposit-password: $e');
    }
  }
}
