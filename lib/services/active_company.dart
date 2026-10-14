import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/account_api.dart';
import 'auth_storage.dart';
import 'company_creds_store.dart';

/// الشركة المفتوحة الآن: اسمها للعرض + كود ساسها + يوزر الدخول.
@immutable
class ActiveCompanyInfo {
  const ActiveCompanyInfo({
    required this.label,
    required this.sasCode,
    required this.sasUrl,
    required this.username,
    this.parentUsername,
    this.isEmployee = false,
    this.resolved = false,
  });

  /// اسم الشركة — من «شركاتي»/الدليل، أو تقديرٌ (مضيف الرابط) قبل الحسم.
  final String label;

  /// كود الساس (`jt`، `earthlink`، `supernet`…) — فارغٌ إن جُهل.
  final String sasCode;

  /// رابط ساس الجلسة (فارغ = الساس الأصليّ).
  final String sasUrl;

  /// يوزر الدخول كما كُتب (الموظّف: يوزره هو).
  final String username;

  /// الموظّف: يوزر مديره الأب — الحساب الذي يعمل تحته.
  final String? parentUsername;

  final bool isEmployee;

  /// الاسم من الخادم (الدليل/«شركاتي») لا تقديرٌ محلّيّ.
  final bool resolved;

  /// اليوزر المعروض بجانب الشركة: المدير ← يوزره، الموظّف ← مديره الأب.
  String get shownUsername {
    final p = parentUsername?.trim() ?? '';
    return isEmployee && p.isNotEmpty ? p : username.trim();
  }

  /// الاسم المختصر للسطر المدمج: «ايرث لنك (Earthlink)» ← «ايرث لنك».
  ///
  /// أسماء الدليل يكتبها المالك بالعربيّ وبين قوسين اللاتينيّ (أو العكس)،
  /// والسطر تحت اسم المدير لا يتّسع للاثنين على شاشة ٣٦٠. يُؤخذ الجزء العربيّ،
  /// وإلّا ما خارج القوسين. الاسم الكامل يبقى في [label] (للدلالات).
  String get shortLabel {
    final full = label.trim();
    final m = RegExp(r'^(.*?)\s*\(([^()]*)\)\s*(.*)$').firstMatch(full);
    if (m == null) return full;
    final outside = '${m.group(1)} ${m.group(3)}'.trim();
    final inside = m.group(2)!.trim();
    if (outside.isEmpty) return inside.isEmpty ? full : inside;
    if (inside.isEmpty) return outside;
    final arabic = RegExp(r'[؀-ۿ]');
    return arabic.hasMatch(inside) && !arabic.hasMatch(outside)
        ? inside
        : outside;
  }

  ActiveCompanyInfo copyWith({String? label, String? sasCode, bool? resolved}) =>
      ActiveCompanyInfo(
        label: label ?? this.label,
        sasCode: sasCode ?? this.sasCode,
        sasUrl: sasUrl,
        username: username,
        parentUsername: parentUsername,
        isEmployee: isEmployee,
        resolved: resolved ?? this.resolved,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'code': sasCode,
        'url': sasUrl,
        'u': username,
        if (parentUsername != null) 'parent': parentUsername,
        'emp': isEmployee,
        'res': resolved,
      };

  static ActiveCompanyInfo? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final label = (j['label'] ?? '').toString().trim();
      if (label.isEmpty) return null;
      final parent = j['parent']?.toString().trim() ?? '';
      return ActiveCompanyInfo(
        label: label,
        sasCode: (j['code'] ?? '').toString(),
        sasUrl: (j['url'] ?? '').toString(),
        username: (j['u'] ?? '').toString(),
        parentUsername: parent.isEmpty ? null : parent,
        isEmployee: j['emp'] == true,
        resolved: j['res'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// «من خلال أيّ شركة أنا داخل؟» — Pro البند ٤.
///
/// المدير يربط عدّة شركات (ساسات / موزّعي ايرث لنك) بحساب إيميل واحد ويتنقّل
/// بينها من «شركاتي»، ولم يكن شيءٌ داخل التطبيق يقول أيّها المفتوحة — فقد
/// يفعّل أو يمدّد في شركةٍ وهو يظنّها أخرى. هذه الخدمة مصدر سطر الشركة تحت اسم
/// المدير في ترويسة الرئيسيّة وبجانب العدد في رأس المشتركين (`ActiveCompanyLine`).
///
/// على نسق [ProviderService]: ذاكرةٌ جارية + خزنةٌ آمنة + `ValueNotifier`.
/// تُحفظ عند اكتمال الدخول (`SasLoginFlow`، وتبديل المدير الفرعيّ)، وتُمسح مع
/// الجلسة (`SessionManager`) فلا يرى الحساب التالي شركة سابقه، وتُستعاد عند
/// الإقلاع (`main`).
class ActiveCompany {
  ActiveCompany._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  static const _kActive = 'company.active';

  /// كود الساس الأصليّ في الخادم (`HOME_SAS`): المعرّف العاري (بلا `:`) له.
  static const homeSasCode = 'supernet';

  /// احتياطٌ إن تعذّر الحسم — المرجع دليل الشركات الذي يضبطه المالك.
  static const _fallbackNames = <String, String>{
    'supernet': 'سوبرنت',
    'earthlink': 'ايرث لنك',
  };

  static final ValueNotifier<ActiveCompanyInfo?> _current =
      ValueNotifier<ActiveCompanyInfo?>(null);
  static bool _loaded = false;
  static String? _resolveTriedFor;

  static ValueListenable<ActiveCompanyInfo?> get listenable => _current;
  static ActiveCompanyInfo? get current => _current.value;

  /// كود الساس من معرّف المدير كما يؤهّله الخادم: `jt:6836` ← `jt`،
  /// `earthlink:12` ← `earthlink`، والعاري ← الأصل. فارغٌ إن جُهل.
  static String codeFromAdminId(String adminId) {
    final s = adminId.trim();
    if (s.isEmpty) return '';
    final i = s.indexOf(':');
    if (i < 0) return homeSasCode;
    final code = s.substring(0, i).toLowerCase();
    return RegExp(r'^[a-z0-9-]{2,16}$').hasMatch(code) ? code : '';
  }

  static String _fallbackLabel(String sasCode, String sasUrl) {
    final named = _fallbackNames[sasCode];
    if (named != null) return named;
    final host = CompanyCredsStore.hostOf(sasUrl);
    if (host.isNotEmpty) return host;
    return sasCode.isNotEmpty ? sasCode : '—';
  }

  /// يُستعاد للذاكرة مرّةً عند الإقلاع. لا يُعتمد المحفوظ إلّا إن خصّ الجلسة
  /// القائمة فعلاً (نفس الساس واليوزر)؛ وإلّا يُشتقّ منها (جلسةٌ سبقت هذه
  /// الميزة، أو استعادة iCloud) ويُحسم الاسم لاحقاً ([resolveLabel]).
  static Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final r = await Future.wait<String?>([
        _storage.read(key: _kActive),
        AuthStorage.readToken(),
        AuthStorage.readSasUrl(),
        AuthStorage.readAdminUsername(),
        AuthStorage.readAdminId(),
      ]);
      final token = r[1] ?? '';
      if (token.isEmpty) {
        // لا جلسة: أيّ محفوظٍ بقايا.
        if (r[0] != null) await _storage.delete(key: _kActive);
        return;
      }
      final sasUrl = r[2] ?? '';
      final adminUsername = (r[3] ?? '').trim();
      final isEmp = await AuthStorage.isEmployee();
      final stored = ActiveCompanyInfo.tryParse(r[0]);
      if (stored != null && _sameSession(stored, sasUrl, adminUsername, isEmp)) {
        _current.value = stored;
        return;
      }
      final code = codeFromAdminId(r[4] ?? '');
      _current.value = ActiveCompanyInfo(
        label: _fallbackLabel(code, sasUrl),
        sasCode: code,
        sasUrl: sasUrl,
        username: isEmp ? '' : adminUsername,
        parentUsername: isEmp && adminUsername.isNotEmpty ? adminUsername : null,
        isEmployee: isEmp,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('ActiveCompany.init failed: $e');
    }
  }

  static bool _sameSession(
      ActiveCompanyInfo i, String sasUrl, String adminUsername, bool isEmp) {
    if (i.isEmployee != isEmp) return false;
    if (CompanyCredsStore.hostOf(i.sasUrl) != CompanyCredsStore.hostOf(sasUrl)) {
      return false;
    }
    // المدير: يوزر الساس نفسه؛ الموظّف: AuthStorage يحفظ يوزر الأب.
    final who = isEmp ? (i.parentUsername ?? '') : i.username;
    return who.trim().toLowerCase() == adminUsername.toLowerCase();
  }

  /// بعد دخولٍ ناجح: شركة الجلسة الجديدة تحلّ محلّ السابقة.
  ///
  /// [label]/[sasCode] من «شركاتي» أو الدليل إن عُرفا. وإلّا فتبديل المدير
  /// الفرعيّ داخل الساس نفسه يرث اسم [previous]، وغيره يُقدَّر ثمّ يُحسم.
  static Future<void> saveFromLogin({
    required String sasUrl,
    required String adminId,
    required String loginUsername,
    required String adminUsername,
    required bool isEmployee,
    String? label,
    String? sasCode,
    ActiveCompanyInfo? previous,
  }) {
    final url = sasUrl.trim();
    var code = sasCode?.trim() ?? '';
    if (code.isEmpty) code = codeFromAdminId(adminId);
    var name = label?.trim() ?? '';
    var resolved = name.isNotEmpty;
    if (!resolved &&
        previous != null &&
        CompanyCredsStore.hostOf(previous.sasUrl) == CompanyCredsStore.hostOf(url)) {
      name = previous.label;
      resolved = previous.resolved;
      if (code.isEmpty) code = previous.sasCode;
    }
    if (name.isEmpty) name = _fallbackLabel(code, url);
    final parent = adminUsername.trim();
    return _save(ActiveCompanyInfo(
      label: name,
      sasCode: code,
      sasUrl: url,
      username: loginUsername.trim(),
      parentUsername: isEmployee && parent.isNotEmpty ? parent : null,
      isEmployee: isEmployee,
      resolved: resolved,
    ));
  }

  static Future<void> _save(ActiveCompanyInfo info) async {
    _loaded = true;
    _current.value = info;
    try {
      await _storage.write(key: _kActive, value: jsonEncode(info.toJson()));
    } catch (e) {
      if (kDebugMode) debugPrint('ActiveCompany.save failed: $e');
    }
  }

  /// يحسم الاسم من «شركاتي» (اسم الدليل الذي يضبطه المالك) إن كان المعروض
  /// تقديراً. مرّةً لكلّ جلسة؛ الفشل يُبقي التقدير بلا إزعاج.
  static Future<void> resolveLabel() async {
    final info = _current.value;
    if (info == null || info.resolved) return;
    final key = '${info.sasCode}|${info.sasUrl}|${info.shownUsername}';
    if (_resolveTriedFor == key) return;
    _resolveTriedFor = key;
    try {
      final hit = _match(await AccountApi.companies(), info);
      if (hit == null) return;
      final label = hit.label.trim();
      // الجلسة تبدّلت أثناء الطلب ← لا يُكتب اسم شركةٍ على غيرها.
      if (label.isEmpty || !identical(_current.value, info)) return;
      final code = hit.sasCode.trim();
      await _save(info.copyWith(
        label: label,
        sasCode: code.isNotEmpty ? code : info.sasCode,
        resolved: true,
      ));
    } catch (e) {
      if (kDebugMode) debugPrint('ActiveCompany.resolveLabel: $e');
    }
  }

  /// الاسم يتبع الساس (اسم الدليل لكوده)، فيكفي تطابق الساس — بالكود أو
  /// بالمضيف — ويُفضَّل صفّ اليوزر نفسه.
  static LinkedCompany? _match(List<LinkedCompany> items, ActiveCompanyInfo info) {
    final host = CompanyCredsStore.hostOf(info.sasUrl);
    final users = <String>{
      info.username.trim().toLowerCase(),
      (info.parentUsername ?? '').trim().toLowerCase(),
    }..remove('');
    LinkedCompany? sameSas;
    for (final c in items) {
      final byCode = info.sasCode.isNotEmpty && c.sasCode == info.sasCode;
      final byHost =
          host.isNotEmpty && CompanyCredsStore.hostOf(c.sasUrl ?? '') == host;
      if (!byCode && !byHost) continue;
      if (users.contains(c.username.trim().toLowerCase())) return c;
      sameSas ??= c;
    }
    return sameSas;
  }

  /// من فلو الخروج وقبل كلّ دخول (`SessionManager`).
  static Future<void> clear() async {
    _current.value = null;
    _resolveTriedFor = null;
    try {
      await _storage.delete(key: _kActive);
    } catch (e) {
      if (kDebugMode) debugPrint('ActiveCompany.clear failed: $e');
    }
  }
}
