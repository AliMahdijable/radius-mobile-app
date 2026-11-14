import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «تلغرام بحساب الوكيل» (١٤ نوفمبر ٢٠٢٦ — المالك: «جلسه تلي يعني يرسل من التلي مباشر وليس بوت … يخيره النظام تريد بوت لو
/// تريد بحسابك مباشرا»): طريقة إرسال تلغرام لهذه الصفحة (البوت / حسابي) وربط حساب الوكيل برقمه والرمز أو برمز QR.
/// الخادم `server/tgAccount/routes.js` (/api/v2/tg-account) — مطفأٌ ما لم يُفتح للحساب (enabled:false ⇒ لا بطاقة).
class TgAccountUser {
  const TgAccountUser({this.name, this.username, this.phoneTail});
  final String? name;
  final String? username;
  final String? phoneTail;

  static TgAccountUser? fromJson(dynamic v) {
    if (v is! Map) return null;
    String? s(dynamic x) {
      final t = x?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    }

    return TgAccountUser(name: s(v['name']), username: s(v['username']), phoneTail: s(v['phone_tail']));
  }

  /// «الاسم · @اليوزر» كما في الويب.
  String get display => [if (name != null) name!, if (username != null) '@$username'].join(' · ');
}

class TgAccountStatus {
  const TgAccountStatus({
    required this.enabled,
    this.serviceUp = true,
    this.configured,
    this.mode = 'bot',
    this.linked = false,
    this.status,
    this.user,
    this.dailyNewCap,
    this.todayNew,
    this.limitedUntil,
  });

  final bool enabled;
  final bool serviceUp;
  final bool? configured;

  /// 'bot' | 'account'
  final String mode;
  final bool linked;

  /// 'connected' | 'disconnected' | 'limited'
  final String? status;
  final TgAccountUser? user;
  final int? dailyNewCap;
  final int? todayNew;
  final DateTime? limitedUntil;

  bool get accountMode => enabled && mode == 'account';

  static TgAccountStatus fromJson(Map d) {
    int? i(dynamic x) => x is int ? x : int.tryParse('${x ?? ''}');
    return TgAccountStatus(
      enabled: d['enabled'] == true,
      serviceUp: d['service'] != 'down',
      configured: d['configured'] is bool ? d['configured'] as bool : null,
      mode: d['mode']?.toString() == 'account' ? 'account' : 'bot',
      linked: d['linked'] == true,
      status: d['status']?.toString(),
      user: TgAccountUser.fromJson(d['user']),
      dailyNewCap: i(d['daily_new_cap']),
      todayNew: i(d['today_new']),
      limitedUntil: DateTime.tryParse(d['limited_until']?.toString() ?? '')?.toLocal(),
    );
  }
}

/// نتيجة خطوةٍ في الربط: نجاحٌ ببياناته، أو رسالة الخادم العربيّة.
typedef TgStep = ({bool ok, Map<String, dynamic> data, String? message});

class TgAccountApi {
  TgAccountApi._();

  static const String base = '/api/v2/tg-account';

  static String msgOf(Object e, String fallback) {
    if (e is DioException) {
      final b = e.response?.data;
      final m = b is Map ? b['message']?.toString() : null;
      if (m != null && m.trim().isNotEmpty) return m;
    }
    return fallback;
  }

  /// حال الصفحة — null إن تعذّر (لا بطاقة توهم بشيء).
  static Future<TgAccountStatus?> status(String adminId) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(base, queryParameters: {'adminId': adminId});
      final b = r.data ?? const {};
      if (b['success'] != true || b['data'] is! Map) return null;
      return TgAccountStatus.fromJson(b['data'] as Map);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 tg-account status: $e');
      return null;
    }
  }

  static Future<TgStep> _post(String path, Map<String, dynamic> body, String fallback, {bool put = false}) async {
    try {
      final r = put
          ? await ApiClient.dio.put<Map<String, dynamic>>('$base$path', data: body)
          : await ApiClient.dio.post<Map<String, dynamic>>('$base$path', data: body);
      final b = r.data ?? const <String, dynamic>{};
      if (b['success'] != true) return (ok: false, data: b, message: b['message']?.toString() ?? fallback);
      return (ok: true, data: b, message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 tg-account $path: $e');
      return (ok: false, data: const <String, dynamic>{}, message: msgOf(e, fallback));
    }
  }

  static Future<TgStep> setMode(String adminId, String mode) =>
      _post('/mode', {'adminId': adminId, 'mode': mode}, 'تعذّر تغيير الطريقة', put: true);

  static Future<TgStep> loginPhone(String adminId, String phone) =>
      _post('/login/phone', {'adminId': adminId, 'phone': phone}, 'تعذّر إرسال الرمز');

  static Future<TgStep> loginCode(String adminId, String loginId, String code) =>
      _post('/login/code', {'adminId': adminId, 'login_id': loginId, 'code': code}, 'تعذّر الدخول');

  static Future<TgStep> loginPassword(String adminId, String loginId, String password) =>
      _post('/login/password', {'adminId': adminId, 'login_id': loginId, 'password': password}, 'تعذّر الدخول');

  static Future<TgStep> loginQr(String adminId) => _post('/login/qr', {'adminId': adminId}, 'تعذّر بدء رمز QR');

  static Future<TgStep> pollQr(String adminId, String loginId) =>
      _post('/login/qr/poll', {'adminId': adminId, 'login_id': loginId}, 'تعذّر قراءة حال الرمز');

  static Future<void> cancel(String adminId, String loginId) async {
    await _post('/login/cancel', {'adminId': adminId, 'login_id': loginId}, '');
  }

  static Future<TgStep> logout(String adminId) => _post('/logout', {'adminId': adminId}, 'تعذّر الفصل');

  /// «data:image/png;base64,…» ⇒ بايتات الصورة، أو null.
  static Uint8List? pngOf(dynamic dataUrl) {
    final s = dataUrl?.toString() ?? '';
    final i = s.indexOf('base64,');
    if (i < 0) return null;
    try {
      return base64Decode(s.substring(i + 7));
    } catch (_) {
      return null;
    }
  }
}
