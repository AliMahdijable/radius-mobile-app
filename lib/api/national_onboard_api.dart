import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'national_device_api.dart';
import 'national_sheet_api.dart';

/// «إضافة مشترك» — طلب «تسجيل زبون جديد» في بوّابة المشروع الوطنيّ (٢ نوفمبر — نسخة الموقع `WataniOnboardSheet.tsx`؛ الخادم
/// `server/watani/wataniOnboarding.js`؛ المالك: «هي نفسها بالطلبات الي اضافة مشترك»):
///   GET  /api/v2/ftth/onboarding/meta             الزونات، الباقات بأسعارها، خيار التركيب، نصّ العقد، القواعد
///   POST /api/v2/ftth/onboarding/validate-id      فحص البطاقة الموحّدة (الصلاحية ١٠ سنوات — سبب الإلغاء الحيّ — ثمّ البوّابة)
///   POST /api/v2/ftth/onboarding/files?kind=…     صورةٌ واحدة خامّاً (JPEG، والتوقيع PNG) ⇒ معرّفها في البوّابة
///   POST /api/v2/ftth/onboarding                  الطلب كلّه ⇒ معرّفه، ثمّ يصل رمزٌ لهاتف المشترك
///   POST /api/v2/ftth/onboarding/:rid/otp         الرمز ⇒ صحيح؟
/// لصاحب الحساب وحده (الخادم ADMIN_ONLY). الصور تمرّ للبوّابة وحدها ولا تُحفظ في التطبيق ولا عندنا.

String _s(dynamic v) => v == null ? '' : v.toString().trim();
String? _sn(dynamic v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

int? _int(dynamic v) {
  if (v is num && v.isFinite) return v.round();
  if (v is String) return num.tryParse(v.trim())?.round();
  return null;
}

class OnboardRef {
  const OnboardRef(this.id, this.name, {this.price});
  final String id;
  final String name;
  final int? price;
}

class OnboardPlan {
  const OnboardPlan({required this.name, required this.title, this.speed, this.price});
  final String name;
  final String title;
  final String? speed;
  final int? price;
}

class OnboardMeta {
  const OnboardMeta({required this.zones, required this.plans, required this.options, this.contract, this.cardYears = 10, this.warnDays = 30});
  final List<OnboardRef> zones;
  final List<OnboardPlan> plans;
  final List<OnboardRef> options;
  final String? contract;
  final int cardYears;
  final int warnDays;

  static OnboardMeta fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> l(dynamic v) => v is List ? v.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
    final rules = j['rules'] is Map ? Map<String, dynamic>.from(j['rules'] as Map) : const <String, dynamic>{};
    return OnboardMeta(
      zones: [for (final z in l(j['zones'])) if (_s(z['id']).isNotEmpty) OnboardRef(_s(z['id']), _sn(z['name']) ?? _s(z['id']))],
      plans: [
        for (final p in l(j['plans']))
          if (_s(p['name']).isNotEmpty) OnboardPlan(name: _s(p['name']), title: _sn(p['title']) ?? _s(p['name']), speed: _sn(p['speed']), price: _int(p['price'])),
      ],
      options: [for (final o in l(j['install_options'])) if (_s(o['id']).isNotEmpty) OnboardRef(_s(o['id']), _sn(o['name']) ?? _s(o['id']), price: _int(o['price']))],
      contract: _sn(j['contract_text']),
      cardYears: _int(rules['card_years']) ?? 10,
      warnDays: _int(rules['card_warn_days']) ?? 30,
    );
  }
}

/// الأرقام العربيّة والفارسيّة ⇒ لاتينيّة (الباقي كما هو).
String onboardLatin(String v) {
  final b = StringBuffer();
  for (final r in v.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else {
      b.writeCharCode(r);
    }
  }
  return b.toString();
}

/// تاريخٌ كما على البطاقة ⇒ يومه، أو null: «2018-03-21» أو «21/3/2018» (والأرقام العربيّة)، بين ١٩٠٠ واليوم.
DateTime? parseOnboardDate(String raw, {DateTime? now}) {
  final m = RegExp(r'^(\d{1,4})\s*[-/.]\s*(\d{1,2})\s*[-/.]\s*(\d{1,4})$').firstMatch(onboardLatin(raw).trim());
  if (m == null) return null;
  final int y, mo, d;
  if (m[1]!.length == 4) {
    (y, mo, d) = (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  } else if (m[3]!.length == 4) {
    (y, mo, d) = (int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
  } else {
    return null;
  }
  if (y < 1900 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(y, mo, d);
  if (dt.month != mo || dt.day != d) return null;
  final n = now ?? DateTime.now();
  return dt.isAfter(DateTime(n.year, n.month, n.day)) ? null : dt;
}

/// انتهاء البطاقة الموحّدة: الإصدار + [years] ⇒ (expired, on 'YYYY-MM-DD', days) — أو null لتاريخٍ غير صالح.
({bool expired, String on, int days})? onboardCardExpiry(DateTime? issued, int years, {DateTime? now}) {
  if (issued == null) return null;
  final exp = DateTime.utc(issued.year + years, issued.month, issued.day);
  final n = (now ?? DateTime.now()).toUtc();
  final on = '${exp.year.toString().padLeft(4, '0')}-${exp.month.toString().padLeft(2, '0')}-${exp.day.toString().padLeft(2, '0')}';
  final days = exp.difference(n).inDays;
  return (expired: !exp.isAfter(n), on: on, days: days);
}

enum OnboardState { applied, unconfirmed, repeated, failed }

class OnboardResult {
  const OnboardResult(this.state, {this.requestId, this.sentTo, this.message, this.field, this.code});
  final OnboardState state;
  final String? requestId;
  final String? sentTo;
  final String? message;
  final String? field;
  final String? code;

  static OnboardResult of(dynamic b, {int? status}) {
    if (b is! Map) return const OnboardResult(OnboardState.failed, message: 'ردٌّ غير متوقّع من الخادم — لم يُرسل شيء');
    final code = _sn(b['code']);
    final msg = [_sn(b['message']), _sn(b['portal_message'])].whereType<String>().join(' — ');
    if (b['success'] == true) {
      final d = b['data'] is Map ? Map<String, dynamic>.from(b['data'] as Map) : const <String, dynamic>{};
      return OnboardResult(OnboardState.applied, requestId: _sn(d['request_id']), sentTo: _sn(d['otp_sent_to']));
    }
    if (status == 202 || code == 'UNCONFIRMED') {
      return OnboardResult(OnboardState.unconfirmed, code: code, message: msg.isEmpty ? 'لم يتأكّد إرسال الطلب — افتح «الطلبات» وتحقّق قبل إعادته' : msg);
    }
    if (code == 'REPEATED') return OnboardResult(OnboardState.repeated, code: code, message: msg);
    return OnboardResult(OnboardState.failed, code: code, field: _sn(b['field']), message: msg.isEmpty ? 'تعذّر إرسال الطلب — لم يتغيّر شيء' : msg);
  }
}

class NationalOnboardApi {
  NationalOnboardApi._();

  static const _base = '/api/v2/ftth/onboarding';
  static const _writeTimeout = Duration(seconds: 90);

  static Future<NationalSheetResult<OnboardMeta?>> meta() async {
    try {
      final r = await ApiClient.dio.get<dynamic>('$_base/meta');
      final x = NationalDeviceApi.readOf(r.data);
      if (!x.ok || x.data == null) {
        if (x.locked) return NationalSheetResult.locked(x.lock!);
        if (!x.ok) return NationalSheetResult.fail(x.error, code: x.code, relogin: x.relogin);
        return const NationalSheetResult.ok(null);
      }
      final d = x.data!['data'];
      return d is Map ? NationalSheetResult.ok(OnboardMeta.fromJson(Map<String, dynamic>.from(d))) : const NationalSheetResult.fail('ردٌّ غير متوقّع من الخادم');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 onboarding/meta: $e');
      return const NationalSheetResult.fail('تعذّر الاتّصال — أعد المحاولة');
    }
  }

  static Future<Map<String, dynamic>?> _post(String path, Object? body, {Options? options}) async {
    try {
      final r = await ApiClient.dio.post<dynamic>(path, data: body, options: options ?? Options(receiveTimeout: _writeTimeout, sendTimeout: _writeTimeout));
      final b = r.data;
      return b is Map ? {...Map<String, dynamic>.from(b), '__status': r.statusCode} : null;
    } on DioException catch (e) {
      if (!kReleaseMode) debugPrint('🔴 POST $path: ${e.response?.statusCode}');
      final b = e.response?.data;
      if (b is Map) return {...Map<String, dynamic>.from(b), '__status': e.response?.statusCode};
      if (e.type == DioExceptionType.receiveTimeout) return {'success': false, 'code': 'UNCONFIRMED', '__status': 202};
      return null;
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 POST $path: $e');
      return null;
    }
  }

  /// فحص البطاقة ⇒ (valid, message, expiresOn, warn, error, field, code).
  static Future<({bool? valid, String? message, String? expiresOn, String? warn, String? error, String? field, String? code})> validateId(Map<String, dynamic> body) async {
    final b = await _post('$_base/validate-id', body);
    if (b == null) return (valid: null, message: null, expiresOn: null, warn: null, error: 'تعذّر الاتّصال — أعد المحاولة', field: null, code: null);
    if (b['success'] != true) {
      return (valid: false, message: null, expiresOn: null, warn: null, error: _sn(b['message']) ?? 'تعذّر فحص البطاقة', field: _sn(b['field']), code: _sn(b['code']));
    }
    final d = b['data'] is Map ? Map<String, dynamic>.from(b['data'] as Map) : const <String, dynamic>{};
    return (valid: d['valid'] == true, message: _sn(d['message']), expiresOn: _sn(d['expires_on']), warn: _sn(d['warn']), error: null, field: null, code: null);
  }

  /// رفع صورةٍ واحدة خامّاً ⇒ (id, error).
  static Future<({String? id, String? error})> upload(String kind, Uint8List bytes, {required String contentType}) async {
    final b = await _post(
      '$_base/files?kind=${Uri.encodeQueryComponent(kind)}',
      Stream<List<int>>.value(bytes),
      options: Options(
        receiveTimeout: _writeTimeout,
        sendTimeout: _writeTimeout,
        headers: {Headers.contentTypeHeader: contentType, Headers.contentLengthHeader: bytes.length},
      ),
    );
    if (b == null) return (id: null, error: 'تعذّر رفع الصورة — أعدها');
    if (b['success'] != true) return (id: null, error: _sn(b['message']) ?? 'تعذّر رفع الصورة — أعدها');
    final d = b['data'] is Map ? Map<String, dynamic>.from(b['data'] as Map) : const <String, dynamic>{};
    final id = _sn(d['id']);
    return id == null ? (id: null, error: 'لم تُرجع البوّابة معرّف الصورة — أعدها') : (id: id, error: null);
  }

  static Future<OnboardResult> create(Map<String, dynamic> body, {bool confirmRepeat = false}) async {
    final b = await _post(_base, {...body, if (confirmRepeat) 'confirmRepeat': true});
    if (b == null) return const OnboardResult(OnboardState.failed, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    return OnboardResult.of(b, status: b['__status'] is int ? b['__status'] as int : null);
  }

  /// الرمز الذي وصل لهاتف المشترك ⇒ (valid, message).
  static Future<({bool? valid, String? message})> otp(String rid, {required String mobile, required String code}) async {
    final b = await _post('$_base/${Uri.encodeComponent(rid)}/otp', {'mobile': mobile, 'otp': code});
    if (b == null) return (valid: null, message: 'تعذّر الاتّصال — أعد المحاولة');
    if (b['success'] != true) return (valid: false, message: _sn(b['message']) ?? 'تعذّر فحص الرمز');
    final d = b['data'] is Map ? Map<String, dynamic>.from(b['data'] as Map) : const <String, dynamic>{};
    return (valid: d['valid'] == true, message: _sn(d['message']));
  }
}
