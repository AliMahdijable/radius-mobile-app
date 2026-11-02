import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'national_device_api.dart';
import 'national_sheet_api.dart';

/// «فريقي» — الإضافة والتعديل والحذف للمشروع الوطنيّ في التطبيق (٢ نوفمبر — نسخة الموقع `WataniTeamSheet.tsx` و`FtthTeam.tsx`؛
/// الخادم `wataniPortalBeta.js` teamMeta/teamUsername/teamAdd/teamEdit/teamDelete):
///   GET    /api/v2/ftth/team/meta              الوظائف (بالعربيّ ووصفها، تصرف مالاً؟ كلّ الزونات؟) والزونات وشروط كلمة السرّ
///   GET    /api/v2/ftth/team/username?u=       الاسم مأخوذ؟ (مرّةً كلّ ١٫٢ث للحساب — 429 TOO_FAST ⇒ اسأل بعد لحظة)
///   POST   /api/v2/ftth/team                   {username, first_name, last_name, phone, password, role_id, zone_ids, wallet}
///   PUT    /api/v2/ftth/team/:id               ما تغيّر وحده (الاسمان، الهاتف، الوظيفة، الزونات)
///   DELETE /api/v2/ftth/team/:id {confirm:true}
/// لصاحب الحساب وحده (الخادم ADMIN_ONLY)، وخلف «الأقسام» ومفتاح الكتابة وصلاحيّة البوّابة «إدارة أعضاء الفريق». كتابةٌ واحدة بلا
/// إعادة، و«لم يتأكّد» يُعرض كما هو. كلمة السرّ تمرّ للبوّابة وحدها — لا تُخزَّن في التطبيق.

String _s(dynamic v) => v == null ? '' : v.toString().trim();
String? _sn(dynamic v) {
  final s = _s(v);
  return s.isEmpty ? null : s;
}

class TeamRole {
  const TeamRole({required this.id, this.code, required this.label, this.description, this.monetary = false, this.allZones = false});
  final String id;
  final String? code;
  final String label;
  final String? description;

  /// الوظيفة تصرف مالاً (تحويلٌ بين المحافظ…).
  final bool monetary;

  /// ترى كلّ زونات الشريك — لا اختيار زونات.
  final bool allZones;

  static TeamRole? from(dynamic v) {
    if (v is! Map) return null;
    final id = _s(v['id']);
    if (id.isEmpty) return null;
    return TeamRole(
      id: id,
      code: _sn(v['code']),
      label: _sn(v['label']) ?? _sn(v['code']) ?? id,
      description: _sn(v['description']),
      monetary: v['monetary'] == true,
      allZones: v['all_zones'] == true,
    );
  }
}

class TeamZone {
  const TeamZone(this.id, this.name);
  final String id;
  final String name;
}

/// شروط كلمة السرّ من البوّابة (passwords/policies) — كالخادم passwordProblem.
class TeamPolicy {
  const TeamPolicy({this.minLength = 12, this.digits = 1, this.lower = 1, this.upper = 1, this.notUsername = true});
  final int minLength;
  final int digits;
  final int lower;
  final int upper;
  final bool notUsername;

  static TeamPolicy from(dynamic v) {
    if (v is! Map) return const TeamPolicy();
    int n(dynamic x, int d) => x is num ? x.toInt() : d;
    return TeamPolicy(
      minLength: n(v['min_length'], 12),
      digits: n(v['digits'], 0),
      lower: n(v['lower'], 0),
      upper: n(v['upper'], 0),
      notUsername: v['not_username'] == true,
    );
  }

  static int _count(String p, RegExp re) => re.allMatches(p).length;

  /// قائمة الشروط بحالها لكلمة السرّ — تُعرض علاماتٍ تحت الحقل.
  List<({String label, bool ok})> checks(String pw, String username) => [
        (label: '$minLength حرفاً على الأقلّ', ok: pw.length >= minLength && pw.length <= 64),
        if (digits > 0) (label: 'رقم', ok: _count(pw, RegExp(r'[0-9]')) >= digits),
        if (lower > 0) (label: 'حرفٌ إنكليزيّ صغير', ok: _count(pw, RegExp(r'[a-z]')) >= lower),
        if (upper > 0) (label: 'حرفٌ إنكليزيّ كبير', ok: _count(pw, RegExp(r'[A-Z]')) >= upper),
        (label: 'بلا مسافات', ok: pw.isNotEmpty && !RegExp(r'\s').hasMatch(pw)),
        if (notUsername) (label: 'ليست اسم المستخدم', ok: pw.isNotEmpty && pw.toLowerCase() != username.toLowerCase()),
      ];

  bool ok(String pw, String username) => pw.isNotEmpty && checks(pw, username).every((c) => c.ok);
}

class TeamMeta {
  const TeamMeta({required this.roles, required this.zones, required this.policy, this.policyAssumed = false});
  final List<TeamRole> roles;
  final List<TeamZone> zones;
  final TeamPolicy policy;

  /// تعذّرت قراءة شروط البوّابة — المعروضة افتراضيّة (البوّابة تتحقّق عند الحفظ).
  final bool policyAssumed;

  static TeamMeta fromJson(Map<String, dynamic> j) => TeamMeta(
        roles: [
          if (j['roles'] is List)
            for (final r in j['roles'] as List)
              if (TeamRole.from(r) != null) TeamRole.from(r)!,
        ],
        zones: [
          if (j['zones'] is List)
            for (final z in j['zones'] as List)
              if (z is Map && _s(z['id']).isNotEmpty) TeamZone(_s(z['id']), _sn(z['name']) ?? _s(z['id'])),
        ],
        policy: TeamPolicy.from(j['password']),
        policyAssumed: j['password_assumed'] == true,
      );
}

/// أرقامٌ عربيّة/فارسيّة ⇒ لاتينيّة، بلا مسافاتٍ ولا شُرط.
String teamDigits(String v) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in v.split('')) {
    final i = ar.indexOf(ch);
    final j = fa.indexOf(ch);
    b.write(i >= 0 ? '$i' : j >= 0 ? '$j' : ch);
  }
  return b.toString().replaceAll(RegExp(r'[\s-]'), '');
}

final RegExp teamPhoneOk = RegExp(r'^(?:07\d{9}|\+9647\d{9})$');
final RegExp teamUserOk = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._@-]{2,39}$');
const int teamWalletMax = 100000000;

class NationalTeamApi {
  NationalTeamApi._();

  static const _writeTimeout = Duration(seconds: 80);

  static Future<NationalEditResult> _send(String method, String path, Map<String, dynamic> body) async {
    try {
      final r = await ApiClient.dio.request<dynamic>(path,
          data: body, options: Options(method: method, receiveTimeout: _writeTimeout, sendTimeout: _writeTimeout));
      return NationalDeviceApi.editOf(r.data, status: r.statusCode);
    } on DioException catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $method $path: ${e.response?.statusCode}');
      final b = e.response?.data;
      if (b is Map) return NationalDeviceApi.editOf(b, status: e.response?.statusCode);
      if (e.type == DioExceptionType.receiveTimeout) {
        return const NationalEditResult(NationalEditState.unconfirmed,
            message: 'انقطع الاتّصال قبل الردّ — ربّما حُفظ، حدّث «فريقي» وتحقّق قبل الإعادة', code: 'UNCONFIRMED');
      }
      return const NationalEditResult(NationalEditState.failed, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 $method $path: $e');
      return const NationalEditResult(NationalEditState.failed, message: 'تعذّر الاتّصال — لم يُرسل شيء، أعد المحاولة');
    }
  }

  /// الوظائف والزونات وشروط كلمة السرّ — ok(null) = pending (اسأل بعد لحظة).
  static Future<NationalSheetResult<TeamMeta?>> meta() async {
    try {
      final r = await ApiClient.dio.get<dynamic>('/api/v2/ftth/team/meta');
      final x = NationalDeviceApi.readOf(r.data);
      if (!x.ok || x.data == null) {
        if (x.locked) return NationalSheetResult.locked(x.lock!);
        if (!x.ok) return NationalSheetResult.fail(x.error, code: x.code, relogin: x.relogin);
        return const NationalSheetResult.ok(null);
      }
      final d = x.data!['data'];
      return d is Map ? NationalSheetResult.ok(TeamMeta.fromJson(Map<String, dynamic>.from(d))) : const NationalSheetResult.fail('ردٌّ غير متوقّع من الخادم');
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 team/meta: $e');
      return const NationalSheetResult.fail('تعذّر الاتّصال — أعد المحاولة');
    }
  }

  /// الاسم مأخوذ؟ taken null = لم يُعرف (retry = اسأل بعد لحظة؛ error = سببٌ يُعرض).
  static Future<({bool? taken, bool retry, String? error})> usernameTaken(String u) async {
    try {
      final r = await ApiClient.dio.get<dynamic>('/api/v2/ftth/team/username', queryParameters: {'u': u});
      final b = r.data;
      if (b is! Map) return (taken: null, retry: false, error: null);
      if (r.statusCode == 429 || b['code'] == 'TOO_FAST' || b['pending'] == true) return (taken: null, retry: true, error: null);
      if (b['success'] != true) return (taken: null, retry: false, error: _sn(b['message']));
      return (taken: b['taken'] == true ? true : (b['taken'] == false ? false : null), retry: false, error: null);
    } catch (_) {
      return (taken: null, retry: false, error: null);
    }
  }

  static Future<NationalEditResult> add({
    required String username,
    required String firstName,
    required String lastName,
    required String phone,
    required String password,
    required String roleId,
    required List<String> zoneIds,
    required bool limited,
    int? amount,
  }) =>
      _send('POST', '/api/v2/ftth/team', {
        'username': username,
        'first_name': firstName,
        'last_name': lastName,
        'phone': phone,
        'password': password,
        'role_id': roleId,
        'zone_ids': zoneIds,
        'wallet': limited ? {'limited': true, 'amount': amount ?? 0} : {'limited': false},
      });

  /// ما تغيّر وحده: first_name · last_name · phone · role_id · zone_ids.
  static Future<NationalEditResult> edit(String id, Map<String, dynamic> body) =>
      _send('PUT', '/api/v2/ftth/team/${Uri.encodeComponent(id)}', body);

  static Future<NationalEditResult> remove(String id) => _send('DELETE', '/api/v2/ftth/team/${Uri.encodeComponent(id)}', {'confirm': true});
}
