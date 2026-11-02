import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'national_sheet_api.dart';

/// «تعديل معلومات الجهاز» و«تنصيب الجهاز» للمشروع الوطنيّ في التطبيق (٢ نوفمبر — نسخة الموقع
/// `client-v2/src/components/ftth/{WataniFatEdit,WataniInstall}.tsx`؛ الخادم `server/watani/wataniPortalBeta.js`):
///   GET/PUT  /api/v2/ftth/subscriptions/:sid/network (+ /fats?fdt=)       الفات — مفتاح `watani_fat` (`lookups.fat_edit`)
///   GET/PUT  /api/v2/ftth/subscriptions/:sid/device {field, value}         السيريال/الماك/الرمز/النوع — `watani_device`
///   GET      /api/v2/ftth/tasks/:id/install (+ /fats?fdt=، /username?u=)   «اعداد مشترك» — `watani_install`
///   POST     /api/v2/ftth/tasks/:id/install                                 «تأشير كمكتمل»
/// كلّ حفظٍ نداءٌ واحد بلا إعادة: النتيجة applied/accepted/not_applied/unknown، و«لم يتأكّد» (202) يُعرض كما هو. الرمز الحاليّ يصل
/// لصاحب الحساب ولموظّفٍ يملك «تعديل المشترك» وحدهما، ولا يُخزَّن في التطبيق (يعيش في حالة النافذة وحدها).

String _s(dynamic v) => v == null ? '' : v.toString().trim();
String? _sn(dynamic v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

/// عنصر شبكةٍ أو نوع جهاز: {id, name}.
class NationalNetRef {
  const NationalNetRef(this.id, this.name);
  final String id;
  final String name;

  static NationalNetRef? from(dynamic v) {
    if (v is! Map) return null;
    final id = _s(v['id']);
    if (id.isEmpty) return null;
    final name = _s(v['name']);
    return NationalNetRef(id, name.isEmpty ? id : name);
  }

  static List<NationalNetRef> listOf(dynamic v) =>
      v is List ? v.map(NationalNetRef.from).whereType<NationalNetRef>().toList() : const <NationalNetRef>[];
}

/// شرطٌ من البوّابة (نمطٌ + وصفٌ بالعربيّ من الخادم).
class NationalRule {
  const NationalRule({this.pattern, this.description});
  final String? pattern;
  final String? description;

  static NationalRule? from(dynamic v) => v is Map ? NationalRule(pattern: _sn(v['pattern']), description: _sn(v['description'])) : null;

  /// نمطٌ لا يفهمه محرّك Dart ⇒ البوّابة تحكم (يمرّ).
  bool passes(String v, {RegExp? fallback}) {
    final p = pattern;
    if (p != null) {
      try {
        return RegExp(p).hasMatch(v);
      } catch (_) {
        return true;
      }
    }
    return fallback == null || fallback.hasMatch(v);
  }
}

/// الفات الحاليّ وقائمتاه (FDTs زون المشترك، وفاتات الـFDT الحاليّ).
class NationalNetInfo {
  const NationalNetInfo({this.fdt, this.fat, this.locked = false, this.fdts = const [], this.fats = const []});
  final NationalNetRef? fdt;
  final NationalNetRef? fat;
  final bool locked;
  final List<NationalNetRef> fdts;
  final List<NationalNetRef> fats;

  static NationalNetInfo fromJson(Map<String, dynamic> j) => NationalNetInfo(
        fdt: NationalNetRef.from(j['fdt']),
        fat: NationalNetRef.from(j['fat']),
        locked: j['locked'] == true,
        fdts: NationalNetRef.listOf(j['fdts']),
        fats: NationalNetRef.listOf(j['fats']),
      );

  String get path => [if (fdt != null) fdt!.name, if (fat != null) fat!.name].join(' ← ');
}

/// جهاز الاشتراك: اسمه وسيريال الـONT ونوعه والماك وقفله، والأنواع وشرط الرمز، والرمز الحاليّ لمن يُسمح له.
class NationalDeviceInfo {
  const NationalDeviceInfo({
    this.username,
    this.serial,
    this.vendor,
    this.mac,
    this.lockedMac,
    this.locked = false,
    this.vendors,
    this.passwordRule,
    this.password,
    this.passwordHidden = false,
  });
  final String? username;
  final String? serial;
  final NationalNetRef? vendor;
  final String? mac;
  final String? lockedMac;

  /// البوّابة تقفل عناصر الشبكة (السيريال والنوع) لهذا الاشتراك الآن.
  final bool locked;

  /// null = تعذّرت قراءة الأنواع (النوع يُعرض ولا يُغيَّر).
  final List<NationalNetRef>? vendors;
  final NationalRule? passwordRule;
  final String? password;

  /// موظّفٌ بلا «تعديل المشترك»: الرمز محجوب.
  final bool passwordHidden;

  static NationalDeviceInfo fromJson(Map<String, dynamic> j) => NationalDeviceInfo(
        username: _sn(j['username']),
        serial: _sn(j['serial']),
        vendor: NationalNetRef.from(j['vendor']),
        mac: _sn(j['mac']),
        lockedMac: _sn(j['locked_mac']),
        locked: j['locked'] == true,
        vendors: j['vendors'] is List ? NationalNetRef.listOf(j['vendors']) : null,
        passwordRule: NationalRule.from(j['password_rule']),
        password: j['password'] is String && (j['password'] as String).isNotEmpty ? j['password'] as String : null,
        passwordHidden: j['password_hidden'] == true,
      );
}

/// ما سُجّل بتنصيب مهمّةٍ مكتملة.
class NationalInstallSaved {
  const NationalInstallSaved({
    this.username,
    this.password,
    this.passwordHidden = false,
    this.serial,
    this.pointSupply,
    this.vendor,
    this.fdt,
    this.fat,
  });
  final String? username;
  final String? password;
  final bool passwordHidden;
  final String? serial;
  final String? pointSupply;
  final NationalNetRef? vendor;
  final NationalNetRef? fdt;
  final NationalNetRef? fat;

  static NationalInstallSaved? from(dynamic v) {
    if (v is! Map) return null;
    return NationalInstallSaved(
      username: _sn(v['username']),
      password: v['password'] is String && (v['password'] as String).isNotEmpty ? v['password'] as String : null,
      passwordHidden: v['password_hidden'] == true,
      serial: _sn(v['serial']),
      pointSupply: _sn(v['point_supply']),
      vendor: NationalNetRef.from(v['vendor']),
      fdt: NationalNetRef.from(v['fdt']),
      fat: NationalNetRef.from(v['fat']),
    );
  }
}

/// نافذة «تنصيب الجهاز»: المهمّة، ومراجع النموذج (المفتوحة) أو ما سُجّل (المكتملة).
class NationalInstallInfo {
  const NationalInstallInfo({
    required this.taskId,
    this.status = '',
    this.zone,
    this.customer,
    this.requestId,
    this.done = false,
    this.saved,
    this.fdts = const [],
    this.vendors = const [],
    this.usernameRule,
    this.passwordRule,
    this.codeRequired = true,
  });
  final String taskId;
  final String status;
  final String? zone;
  final String? customer;
  final String? requestId;
  final bool done;
  final NationalInstallSaved? saved;
  final List<NationalNetRef> fdts;
  final List<NationalNetRef> vendors;
  final NationalRule? usernameRule;
  final NationalRule? passwordRule;
  final bool codeRequired;

  bool get completed => status.toLowerCase() == 'completed';

  static NationalInstallInfo fromJson(Map<String, dynamic> j) {
    final t = j['task'] is Map ? j['task'] as Map : const {};
    return NationalInstallInfo(
      taskId: _s(t['id']),
      status: _s(t['status']),
      zone: _sn(t['zone']),
      customer: _sn(t['customer']),
      requestId: _sn(t['request_id']),
      done: j['done'] == true,
      saved: NationalInstallSaved.from(j['saved']),
      fdts: NationalNetRef.listOf(j['fdts']),
      vendors: NationalNetRef.listOf(j['vendors']),
      usernameRule: NationalRule.from(j['username_rule']),
      passwordRule: NationalRule.from(j['password_rule']),
      codeRequired: j['code_required'] != false,
    );
  }
}

/// فحص اسم مستخدم الجهاز: متاحٌ أم لا (ورسالة السبب)، أو لم يُعرف بعد.
class NationalUserCheck {
  const NationalUserCheck({this.valid, this.taken = false, this.message, this.retry = false});
  final bool? valid;
  final bool taken;
  final String? message;

  /// اسأل ثانيةً بعد لحظة (pending أو «لحظة» من الخادم).
  final bool retry;
}

enum NationalEditState { ok, unconfirmed, failed }

/// نتيجة حفظ: ok بنتيجةٍ ([outcome]: applied · accepted · not_applied · unknown)، أو «لم يتأكّد»، أو رفضٌ لم يتغيّر به شيء.
class NationalEditResult {
  const NationalEditResult(this.state, {this.outcome, this.message, this.portalMessage, this.code, this.requestRef, this.raw = const {}});
  final NationalEditState state;
  final String? outcome;
  final String? message;
  final String? portalMessage;
  final String? code;
  final String? requestRef;
  final Map<String, dynamic> raw;

  bool get ok => state == NationalEditState.ok;
  bool get unconfirmed => state == NationalEditState.unconfirmed;
  bool get applied => ok && outcome == 'applied';

  /// النصّ للعرض: رسالتنا ثمّ نصّ البوّابة ومرجع طلبها (إن وُجدا).
  String get text => [
        message ?? 'تعذّر التنفيذ — لم يتغيّر شيء',
        if (portalMessage != null) portalMessage!,
        if (requestRef != null) requestRef!,
      ].join('\n');
}

class NationalDeviceApi {
  NationalDeviceApi._();

  /// الحفظ: مهلة الخادم ٣٠ث للكتابة + قراءةٌ قبلها وبعدها — لا نقطع قبله فنظنّه «لم يتأكّد».
  static const _writeTimeout = Duration(seconds: 80);

  static String _sub(String sid) => '/api/v2/ftth/subscriptions/${Uri.encodeComponent(sid)}';
  static String _task(String id) => '/api/v2/ftth/tasks/${Uri.encodeComponent(id)}/install';

  /// قراءة: ok(data) · ok(null) = pending (اسأل بعد لحظة) · locked · fail.
  static Future<NationalSheetResult<Map<String, dynamic>?>> _read(String path, [Map<String, Object?> query = const {}]) async {
    try {
      final r = await ApiClient.dio.get<dynamic>(path, queryParameters: {
        for (final e in query.entries)
          if (e.value != null && e.value.toString().isNotEmpty) e.key: e.value,
      });
      return readOf(r.data);
    } on DioException catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $path: ${e.response?.statusCode}');
      final b = e.response?.data;
      if (b is Map) return readOf(b);
      return const NationalSheetResult.fail('تعذّر الاتّصال — أعد المحاولة');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $path: $e');
      return const NationalSheetResult.fail('تعذّر الاتّصال — أعد المحاولة');
    }
  }

  static NationalSheetResult<Map<String, dynamic>?> readOf(dynamic b) {
    if (b is! Map) return const NationalSheetResult.fail('تعذّر جلب البيانات من بوّابة المشروع الوطني');
    final lock = NationalLock.of(b);
    if (lock != null) return NationalSheetResult.locked(lock);
    if (b['locked'] == true) return NationalSheetResult.locked(NationalLock(message: _s(b['message'])));
    if (b['success'] != true) {
      final code = _sn(b['code']);
      final m = _s(b['message']);
      return NationalSheetResult.fail(
        m.isNotEmpty && m.length < 220 ? m : 'تعذّر جلب البيانات من بوّابة المشروع الوطني',
        code: code,
        relogin: code == 'FTTH_RELOGIN' || code == 'PROVIDER_RELOGIN',
      );
    }
    if (b['pending'] == true) return const NationalSheetResult.ok(null);
    return NationalSheetResult.ok(Map<String, dynamic>.from(b));
  }

  static Future<NationalEditResult> _send(String method, String path, Map<String, dynamic> body) async {
    try {
      final r = await ApiClient.dio.request<dynamic>(
        path,
        data: body,
        options: Options(method: method, receiveTimeout: _writeTimeout, sendTimeout: _writeTimeout),
      );
      return editOf(r.data, status: r.statusCode);
    } on DioException catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $method $path: ${e.response?.statusCode}');
      final b = e.response?.data;
      if (b is Map) return editOf(b, status: e.response?.statusCode);
      // أُرسل ولم يصل الردّ: ربّما حُفظ — لا «فشل» ولا إعادة. أمّا تعذّر الاتّصال أصلاً فلم يُرسل شيء.
      if (e.type == DioExceptionType.receiveTimeout) {
        return const NationalEditResult(NationalEditState.unconfirmed,
            message: 'انقطع الاتّصال قبل الردّ — ربّما حُفظ، افتح المعلومات ثانيةً وتحقّق قبل الإعادة', code: 'UNCONFIRMED');
      }
      return const NationalEditResult(NationalEditState.failed, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $method $path: $e');
      return const NationalEditResult(NationalEditState.failed, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    }
  }

  /// ردّ الحفظ ⇒ نتيجته (القفل والمفاتيح المطفأة رفضٌ لم يُرسل شيئاً).
  static NationalEditResult editOf(dynamic b, {int? status}) {
    if (b is! Map) return const NationalEditResult(NationalEditState.failed, message: 'تعذّر التنفيذ — لم يتغيّر شيء');
    final raw = Map<String, dynamic>.from(b);
    final code = _sn(b['code']);
    if (status == 202 || code == 'UNCONFIRMED') {
      return NationalEditResult(NationalEditState.unconfirmed,
          message: _sn(b['message']) ?? 'لم يتأكّد الحفظ — افتح المعلومات ثانيةً وتحقّق قبل الإعادة', code: 'UNCONFIRMED', raw: raw);
    }
    final lock = NationalLock.of(b);
    if (lock != null || b['locked'] == true) {
      return NationalEditResult(NationalEditState.failed, message: lock?.message ?? _sn(b['message']), code: code ?? 'LOCKED', raw: raw);
    }
    if (b['success'] == true) {
      return NationalEditResult(NationalEditState.ok, outcome: _sn(b['outcome']) ?? 'accepted', message: _sn(b['message']), raw: raw);
    }
    final m = _s(b['message']);
    return NationalEditResult(
      NationalEditState.failed,
      message: m.isNotEmpty && m.length < 240 ? m : 'تعذّر التنفيذ — لم يتغيّر شيء',
      portalMessage: _sn(b['portal_message']),
      code: code,
      requestRef: _sn(b['request_ref']),
      raw: raw,
    );
  }

  /* ───────────── «تغيير الفات» ───────────── */

  static Future<NationalSheetResult<NationalNetInfo?>> network(String sid) async {
    final r = await _read('${_sub(sid)}/network');
    if (!r.ok || r.data == null) return _pass(r);
    final d = r.data!['data'];
    return d is Map ? NationalSheetResult.ok(NationalNetInfo.fromJson(Map<String, dynamic>.from(d))) : const NationalSheetResult.fail('ردٌّ غير متوقّع من الخادم');
  }

  static Future<NationalSheetResult<List<NationalNetRef>?>> networkFats(String sid, String fdtId) async {
    final r = await _read('${_sub(sid)}/network/fats', {'fdt': fdtId});
    if (!r.ok || r.data == null) return _pass(r);
    return NationalSheetResult.ok(NationalNetRef.listOf(r.data!['data']));
  }

  static Future<NationalEditResult> saveNetwork(String sid, {required String fdtId, required String fatId}) =>
      _send('PUT', '${_sub(sid)}/network', {'fdt_id': fdtId, 'fat_id': fatId});

  /* ───────────── «تعديل معلومات الجهاز» ───────────── */

  static Future<NationalSheetResult<NationalDeviceInfo?>> device(String sid) async {
    final r = await _read('${_sub(sid)}/device');
    if (!r.ok || r.data == null) return _pass(r);
    final d = r.data!['data'];
    return d is Map ? NationalSheetResult.ok(NationalDeviceInfo.fromJson(Map<String, dynamic>.from(d))) : const NationalSheetResult.fail('ردٌّ غير متوقّع من الخادم');
  }

  /// [field]: serial · mac (فارغٌ = فكّ القفل) · password · vendor (معرّفه).
  static Future<NationalEditResult> saveDevice(String sid, {required String field, required String value}) =>
      _send('PUT', '${_sub(sid)}/device', {'field': field, 'value': value});

  /* ───────────── «تنصيب الجهاز» ───────────── */

  static Future<NationalSheetResult<NationalInstallInfo?>> install(String taskId) async {
    final r = await _read(_task(taskId));
    if (!r.ok || r.data == null) return _pass(r);
    final d = r.data!['data'];
    return d is Map ? NationalSheetResult.ok(NationalInstallInfo.fromJson(Map<String, dynamic>.from(d))) : const NationalSheetResult.fail('ردٌّ غير متوقّع من الخادم');
  }

  static Future<NationalSheetResult<List<NationalNetRef>?>> installFats(String taskId, String fdtId) async {
    final r = await _read('${_task(taskId)}/fats', {'fdt': fdtId});
    if (!r.ok || r.data == null) return _pass(r);
    return NationalSheetResult.ok(NationalNetRef.listOf(r.data!['data']));
  }

  /// متاحٌ هذا الاسم؟ تعذّر السؤال ⇒ valid null (الإرسال يفحصه الخادم ثانيةً على كلّ حال).
  static Future<NationalUserCheck> checkUsername(String taskId, String u) async {
    try {
      final r = await ApiClient.dio.get<dynamic>('${_task(taskId)}/username', queryParameters: {'u': u});
      final b = r.data;
      if (b is! Map) return const NationalUserCheck();
      if (r.statusCode == 429 || b['code'] == 'TOO_FAST' || b['pending'] == true) return const NationalUserCheck(retry: true);
      if (b['success'] != true || b['valid'] is! bool) return const NationalUserCheck();
      return NationalUserCheck(valid: b['valid'] as bool, taken: b['taken'] == true, message: _sn(b['message']));
    } catch (_) {
      return const NationalUserCheck();
    }
  }

  static Future<NationalEditResult> submitInstall(
    String taskId, {
    required String username,
    required String password,
    required String pointSupply,
    required String serial,
    required String vendorId,
    required String fdtId,
    required String fatId,
    required String code,
  }) =>
      _send('POST', _task(taskId), {
        'username': username,
        'password': password,
        'point_supply': pointSupply,
        'serial': serial,
        'vendor_id': vendorId,
        'fdt_id': fdtId,
        'fat_id': fatId,
        'code': code,
      });

  static NationalSheetResult<T?> _pass<T>(NationalSheetResult<Map<String, dynamic>?> r) {
    if (r.locked) return NationalSheetResult.locked(r.lock!);
    if (!r.ok) return NationalSheetResult.fail(r.error, code: r.code, relogin: r.relogin);
    return const NationalSheetResult.ok(null); // pending
  }
}
