import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// آخر ردودٍ مرفوضة من خادمنا — لـ«اشرحلي» وحدها (المساعد الذكيّ).
///
/// «اشرحلي» يشرح الخطأ **الذي ظهر للمدير**، ونصّ الإشعار وحده لا يحمل رمز
/// الخادم ولا العمليّة. فهذا المعترض يحفظ **في الذاكرة** (لا على القرص) آخر
/// بضعة ردودٍ مرفوضة: الرمز ونصّ الرسالة والحالة والمسار، ومن جسم الطلب ما
/// يصف العمليّة وحده — طريقة الدفع إن كانت من قائمتها المعروفة، وهل هو تغيير
/// باقةٍ (حالاً أو عند الانتهاء). **لا قيمة أخرى من الجسم أبداً**: لا كلمة سرّ
/// ولا باسورد إيداع ولا رمز كارت ولا اسم.
///
/// ثمّ يطابقها الإشعار بنصّه ([AiAssistantState.explainFor]) — فلا يظهر الزرّ
/// على رسالةٍ محلّيّة («أدخل المبلغ») ولا على خطأٍ لم يره أحد.
///
/// ما لا يُحفظ: ٤٠١ (مسار التجديد/الطرد، لا رسالة) إلّا على الدخول نفسه،
/// ونداءات المساعد نفسه، وأخطاء النقل بلا ردّ، وردٌّ ليس بكلام خادمنا (صفحة
/// HTML من الوسيط). لا يغيّر الطلب ولا الردّ، ولا يرمي.
class ApiErrorTap extends Interceptor {
  ApiErrorTap();

  /// السقف — يكفي ما يظهر على الشاشة في ثوانٍ.
  static const _keep = 8;

  static final List<ApiErrorNote> _notes = <ApiErrorNote>[];

  /// الأحدث آخراً.
  static List<ApiErrorNote> get recent => List.unmodifiable(_notes);

  /// مصدر الوقت — يُستبدل في الاختبارات.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// من [AiAssistantState.reset] — لا يُشرح للمدير التالي خطأ سابقه.
  static void clear() => _notes.clear();

  static final _code = RegExp(r'^[A-Za-z0-9_.:-]{2,64}$');

  /// الدخول وحده: ٤٠١ هنا رفضٌ لبيانات الدخول لا انتهاء جلسة.
  static final _loginPaths =
      RegExp(r'/api/auth/(?:login|employee-login|2fa/verify)$');

  /// طرق الدفع المعروفة وحدها (`method` في التفعيل/التمديد/الإضافة).
  static const _methods = {
    'credit',
    'card',
    'cash',
    'deposit',
    'test',
    'user_balance',
    'zaincash',
    'voucher',
  };

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _safe(() =>
        _note(response.requestOptions, response.statusCode, response.data));
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final r = err.response;
    if (r != null) _safe(() => _note(err.requestOptions, r.statusCode, r.data));
    handler.next(err);
  }

  static void _safe(void Function() f) {
    try {
      f();
    } catch (_) {/* لا يُفشل طلباً أبداً */}
  }

  static void _note(RequestOptions o, int? status, Object? data) {
    final code = status ?? 0;
    final path = o.path;
    if (path.contains('/api/v2/ai/')) return;
    if (code == 401 && !_loginPaths.hasMatch(path)) return;
    if (data is! Map) return; // ليس كلام خادمنا
    final ok = data['success'];
    if (code < 400 && ok != false) return;
    final c = data['code'] ?? data['error'];
    final sCode = c is String && _code.hasMatch(c) ? c : null;
    final m = data['message'];
    final msg = m is String && m.trim().isNotEmpty ? _cut(m.trim(), 400) : null;
    if (sCode == null && msg == null) return;
    final body = o.data;
    String? method;
    var packageChange = false;
    String? changeType;
    if (body is Map) {
      final mv = body['method'];
      if (mv is String && _methods.contains(mv)) method = mv;
      if (body['profile_id'] != null && o.method.toUpperCase() == 'PUT') {
        packageChange = true;
        final ct = body['change_type'];
        if (ct == 'immediate' || ct == 'schedule') changeType = ct as String;
      }
    }
    _notes.add(ApiErrorNote(
      at: now(),
      method: o.method.toUpperCase(),
      path: path,
      status: code,
      code: sCode,
      message: msg,
      payMethod: method,
      packageChange: packageChange,
      changeType: changeType,
    ));
    while (_notes.length > _keep) {
      _notes.removeAt(0);
    }
  }

  static String _cut(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  @visibleForTesting
  static void debugNote(ApiErrorNote n) {
    _notes.add(n);
    while (_notes.length > _keep) {
      _notes.removeAt(0);
    }
  }
}

/// ردٌّ مرفوض واحد كما حفظه [ApiErrorTap] — بلا أيّ قيمةٍ من جسم الطلب
/// سوى ما يصف العمليّة.
@immutable
class ApiErrorNote {
  const ApiErrorNote({
    required this.at,
    required this.method,
    required this.path,
    required this.status,
    this.code,
    this.message,
    this.payMethod,
    this.packageChange = false,
    this.changeType,
  });

  final DateTime at;
  final String method;
  final String path;
  final int status;
  final String? code;
  final String? message;

  /// طريقة الدفع من قائمتها المعروفة وحدها.
  final String? payMethod;

  /// تعديل مشتركٍ يحمل باقةً جديدة (`profile_id`).
  final bool packageChange;

  /// `immediate` · `schedule` — كما أرسلها التطبيق.
  final String? changeType;
}
