import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/account_api.dart';
import '../api/api_client.dart';
import '../api/big_subscribers_api.dart';
import '../api/company_route.dart';
import '../api/employee_merged_api.dart';
import '../api/subscribers_api.dart';
import '../models/merged_company.dart';
import '../models/subscriber.dart';
import 'account_service.dart';
import 'active_company.dart';
import 'auth_storage.dart';
import 'employee_session.dart';
import 'merged_rows.dart';
import 'permissions_service.dart';

/// «كل الشركات» في التطبيق (٢١ أكتوبر، المالك: «ابدي بيها خل نكملها» — تصميمنا): الرئيسية والمشتركين تعرض شركات حساب Pro
/// كلّها معاً، والعمليّات على المشترك تُنفَّذ في مكانها — كلّ نداءٍ موجَّهٌ لشركة صفّه بتوكن الحساب وحده (CompanyRoute).
/// صاحب الحساب حين يفتحه الخادم (routing) ولحسابه شركتان صالحتان فأكثر. الجلسة المفتوحة تبقى كما هي: الأجهزة و«قوائم أخرى»
/// لها، والخروج من الوضع لا يمسح شيئاً.
///
/// **«كل الصفحات» للموظّف** (٩ نوفمبر — المالك: «الموظف… يشوف كل الصفحات مثل المدير… حاله حال المدير حسب الصلاحيات
/// المعطاه اله»): موظّفٌ مربوطٌ بصفحتين فأكثر يرى صفحاته بالشاشات نفسها — صفحاته من خادمنا بتوكنه
/// ([EmployeeMergedApi]، لا حساب له)، وكلّ طلبٍ موجَّهٍ بتوكنه هو + المفتاح فينفّذه الخادم بصفّه في تلك الصفحة وبصلاحيّاتها.
/// صفحته الحاليّة (`current`) هي «المفتوحة»، وكتابتها وحدها تُنفَّذ من هنا الآن (`writes` لكلّ صفحة — [writeLockFor]).
class MergedMode {
  MergedMode._();

  /// الوضع مفعّلٌ الآن.
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);

  /// آخر ردّ الشركات (null = لم يُعرف بعد).
  static final ValueNotifier<MergedCompaniesData?> data = ValueNotifier<MergedCompaniesData?>(null);

  /// الشركة المختارة داخل الوضع (null = كلّ الشركات) — مشتركةٌ بين الرئيسية والمشتركين والتقرير الماليّ كشريط الويب
  /// (client-v2 CompanyStrip ← setScope): شركةٌ مختارة تُعرض وحدها كأنّها مفتوحة، والكلّ مدموجٌ بلا تكرار.
  static final ValueNotifier<String?> focus = ValueNotifier<String?>(null);

  /// الشركة المختارة ما دامت صالحة — وإلّا null (الكلّ).
  static MergedCompany? get focused {
    final k = focus.value;
    if (k == null) return null;
    for (final c in usable) {
      if (c.key == k) return c;
    }
    return null;
  }

  static const freshFor = Duration(seconds: 60);

  @visibleForTesting
  static Future<Map<String, dynamic>?> Function() fetchRaw = AccountApi.mergedCompaniesRaw;

  /// صفحات الموظّف (ردّ [EmployeeMergedApi.companiesRaw] بتوكنه).
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function() fetchEmployeeRaw = EmployeeMergedApi.companiesRaw;

  @visibleForTesting
  static String? Function() accountUid = () => AccountService.currentUser?.uid;

  /// اسم دخول الموظّف (صفّه الأصليّ) — مفتاح تفضيله: الشخص نفسه في كلّ صفحاته، لا صفّ الصفحة.
  @visibleForTesting
  static String? Function() employeeLogin = _defaultEmployeeLogin;

  static String? _defaultEmployeeLogin() {
    final pages = PermissionsService.employeePages;
    for (final p in pages) {
      if (p.primary && (p.loginUsername ?? '').trim().isNotEmpty) return p.loginUsername;
    }
    for (final p in pages) {
      if ((p.loginUsername ?? '').trim().isNotEmpty) return p.loginUsername;
    }
    final a = ActiveCompany.current;
    return a != null && a.isEmployee && a.username.trim().isNotEmpty ? a.username : null;
  }

  static DateTime? _at;
  static Future<MergedCompaniesData>? _inFlight;
  static int _generation = 0;

  /// المالك (صاحب الحساب أو مديرٌ — لا موظّف).
  static bool get ownerSession => !PermissionsService.isEmployee && !EmployeeSession.isActive;

  /// «كل الصفحات»: جلسة موظّف (مباشر، أو صفّ موظّفٍ من «شركاتي») — صفحاته من خادمنا بتوكنه.
  static bool get employeeSession => !ownerSession;

  static List<MergedCompany> get companies => data.value?.companies ?? const [];
  static List<MergedCompany> get usable => data.value?.usable ?? const [];
  static bool get writes => data.value?.writes ?? false;

  /// يُعرض خيار «كل الشركات» («كل الصفحات» للموظّف): التوجيه مفتوح، وشركتان (صفحتان) صالحتان فأكثر.
  static bool get eligible => (data.value?.routing ?? false) && usable.length >= 2;

  /// «كل الصفحات»: الخادم أطفأه (مفتاح الإيقاف — 409 COMPANY_ROUTE_DISABLED) — رسالته تُعرض في «صفحاتي» مكان الخيار.
  static final ValueNotifier<String?> stopped = ValueNotifier<String?>(null);

  /// يرتفع حين يُعاد الموظّف لصفحته لأنّ الخادم أطفأ الوضع وهو فيه — MainShell يعرض [stopped] مرّةً.
  static final ValueNotifier<int> fellBack = ValueNotifier<int>(0);

  /// صفحة الموظّف الحاليّة بين صفحاته (`current:true`) — «المفتوحة» في وضعه. null للمالك (ردّه بلا current).
  static MergedCompany? get currentPage {
    if (!employeeSession) return null;
    for (final c in companies) {
      if (c.current) return c;
    }
    return null;
  }

  /// معرّف مدير الشركة المفتوحة كما تقارنه شاشات الوضع بـ`MergedCompany.adminId`: المالك ⇒ معرّف جلسته المحفوظ (كما كان
  /// حرفاً)؛ الموظّف ⇒ معرّف صفحته الحاليّة من ردّ صفحاته — جلسته تحفظ معرّف مدير الصفحة بصيغةٍ قد تختلف.
  static Future<String?> openAdminId() async {
    final cur = currentPage;
    if (cur != null && cur.adminId.trim().isNotEmpty) return cur.adminId.trim();
    try {
      return (await AuthStorage.readAdminId())?.trim();
    } catch (_) {
      return null;
    }
  }

  /// اسم المفتوحة لسطور «للمفتوحة وحدها» — الموظّف: اسم صفحته الحاليّة من ردّ صفحاته؛ null ⇒ يبقى ما كان يُعرض.
  static String? get currentPageName {
    final n = currentPage?.name.trim() ?? '';
    return n.isEmpty ? null : n;
  }

  /// كتابةٌ على صفحةٍ غير صفحته الحاليّة — يُقفل قبل الإرسال (المرحلة الأولى: الخادم ينفّذ كتابة الصفحة الحاليّة وحدها).
  static const writeLockedText = 'انتقل إلى الصفحة من «صفحاتي» لتنفيذها';

  /// الخادم أوقف التنفيذ من «كل الصفحات» حتى على صفحته الحاليّة — يخرج من الوضع وينفّذها في صفحته كالمعتاد.
  static const writePausedHereText = 'التنفيذ من «كل الصفحات» متوقّف الآن — اخرج منها ونفّذها من صفحتك';

  /// سبب قفل الكتابة على صفحة [key] من «كل الصفحات» — null: مفتوحة. المالك ⇒ null دائماً (الخادم يحكم كما كان، لا قفل مسبق).
  /// الموظّف: الصفحة مفتوحةٌ للكتابة إن فتح الخادم الكتابة (`writes`) وقالت صفحتها نعم (`writes` لكلّ صفحة؛ غيابها ⇒ صفحته
  /// الحاليّة وحدها).
  static String? writeLockFor(String? key) {
    if (key == null || !employeeSession) return null;
    final d = data.value;
    final c = companyOf(key);
    if (d == null || c == null) return null;
    if (d.writes && (c.writes ?? c.current)) return null;
    return c.current ? writePausedHereText : writeLockedText;
  }

  /// صلاحيّته في تلك الصفحة غيرها هنا: رفضها يُسمّيها.
  static String deniedText(MergedCompany c) => 'ليس لديك صلاحيّة لهذا في «${c.name}»';

  // ── صلاحيّاته لكلّ صفحة (٩ نوفمبر — المنسّق: «حسب الصلاحيات المعطاه اله» لكلّ صفحة؛ الخادم يرسل `permissions` لكلّ صفحة) ──
  // PermissionsService = صفحته الحاليّة وحدها؛ وكلّ بوّابةٍ في التطبيق تُطبَّق على كلّ صفحةٍ بخريطتها هي: ما لا يملكه هناك لا يُطلب
  // ويُسمّى «لا صلاحيّة لك …» باسمها، ولا يُجمع. لا خريطة (المالك، خادمٌ أقدم) ⇒ ما كان (null من [pagePerm]).

  /// صلاحيّة [perm] للموظّف في صفحة [key] من خريطتها — null: لا خريطة (المالك، أو خادمٌ أقدم، أو صفّ الوضع العاديّ بلا مفتاح).
  static bool? pagePerm(String? key, String perm) {
    if (!employeeSession || key == null) return null;
    final m = companyOf(key)?.permissions;
    if (m == null) return null;
    return m[perm] == true;
  }

  /// أيٌّ من [perms] في صفحة [key] — null: لا خريطة.
  static bool? pagePermAny(String? key, Iterable<String> perms) {
    if (!employeeSession || key == null) return null;
    final m = companyOf(key)?.permissions;
    if (m == null) return null;
    return perms.any((p) => m[p] == true);
  }

  /// صلاحيّة [perm] لصفّ صفحة [key] — خريطتها إن وُجدت، وإلّا صلاحيّات الجلسة (Perms) كما كان: لزرٍّ كان يقرأ Perms.has.
  static bool can(String? key, String perm) => pagePerm(key, perm) ?? PermissionsService.has(perm);

  /// «لا صلاحيّة لك على [what]» — سبب صفحةٍ خارج رقمٍ أو قائمة (يُسبق باسمها حيث يُعرض).
  static String noAccess(String what) => 'لا صلاحيّة لك على $what';

  /// نصّ تعذّر [c] من ردّ الخادم ([body]، و[status] إن عُرف): رسالته إن وُجدت وإلّا [fallback] — كما كان للمالك حرفاً. وفي
  /// «كل الصفحات» للموظّف يُسمّي الصفحة دائماً: رفض صلاحيّته فيها (403 — صلاحيّاته هناك غيرها هنا) ⇒ [deniedText]، ورسالةٌ لا
  /// تذكرها تُسبق باسمها — فلا يُقرأ رفض صفحةٍ كأنّه للكلّ، ولا يُعدّ صفراً.
  static String failText(MergedCompany c, Object? body, String fallback, {int? status}) {
    String? m;
    if (body is Map) {
      final x = body['message'];
      if (x is String && x.trim().isNotEmpty) m = x.trim();
    }
    if (!employeeSession) return m ?? fallback;
    final code = body is Map ? body['code'] : null;
    if (code == 'PERMISSION_DENIED' || (status == 403 && !CompanyRouteCodes.isEmployeeRouteCode(code))) return deniedText(c);
    final t = m ?? fallback;
    return t.contains(c.name) ? t : '«${c.name}»: $t';
  }

  static MergedCompany? companyOf(String? key) {
    if (key == null) return null;
    for (final c in companies) {
      if (c.key == key) return c;
    }
    return null;
  }

  /// شركات الحساب الآن (طلبٌ واحدٌ جارٍ على الأكثر) — وللموظّف صفحاته ([fetchEmployeeRaw]). لا يرمي — فشلٌ ⇒ آخر ما عُرف.
  static Future<MergedCompaniesData> load({bool fresh = false}) {
    final at = _at;
    final cur = data.value;
    if (!fresh && cur != null && at != null && DateTime.now().difference(at) < freshFor) return Future.value(cur);
    final emp = employeeSession;
    if (emp) _installEmployeeHooks();
    final running = _inFlight;
    if (running != null) return running;
    final gen = _generation;
    late final Future<MergedCompaniesData> req;
    req = (emp ? fetchEmployeeRaw() : fetchRaw()).then((raw) {
      final d = MergedCompaniesData.from(raw);
      if (gen == _generation && raw != null) {
        data.value = d;
        _at = DateTime.now();
        if (emp) _afterEmployeeLoad(raw);
      }
      return raw == null ? (data.value ?? d) : d;
    }, onError: (_) => data.value ?? const MergedCompaniesData(routing: false, writes: false, companies: [])).whenComplete(() {
      if (identical(_inFlight, req)) _inFlight = null;
    });
    _inFlight = req;
    return req;
  }

  /// منافذ المعترض للموظّف: قفل الكتابة لكلّ صفحة، ومفتاح الإيقاف (دالّتان بلا حالٍ — تقرآن الوضع لحظة الطلب).
  static void _installEmployeeHooks() {
    CompanyRoute.writeLockOf ??= writeLockFor;
    CompanyRoute.onEmployeeRouteStopped ??= _routeStopped;
  }

  /// ردّ صفحاته وصل: رسالة الإيقاف إن أطفأه الخادم، ومن كان فيه ولم يعد متاحاً يعود لصفحته.
  static void _afterEmployeeLoad(Map<String, dynamic> raw) {
    String? stop;
    if (raw['stopped'] == true) {
      final m = '${raw['message'] ?? ''}'.trim();
      stop = m.isEmpty ? EmployeeMergedApi.stoppedText : m;
    }
    stopped.value = stop;
    if (active.value && !eligible) _fallBack(stop);
  }

  /// طلبٌ موجَّهٌ للموظّف ردّ 409 COMPANY_ROUTE_DISABLED: «كل الصفحات» أُطفئ الآن ⇒ يعود لصفحته برسالة الخادم.
  static void _routeStopped(String? message) {
    if (!employeeSession) return;
    final m = (message ?? '').trim();
    final text = m.isEmpty ? EmployeeMergedApi.stoppedText : m;
    // موجةٌ من الطلبات المتوازية تُرفض معاً — الأوّل يكفي (لا إعادة رسمٍ ولا رسالةٍ لكلٍّ منها)
    if (!active.value && stopped.value == text && !(data.value?.routing ?? false)) return;
    final cur = data.value;
    data.value = MergedCompaniesData(routing: false, writes: false, companies: cur?.companies ?? const []);
    _at = null; // السؤال التالي طازج: يعود الخيار حين يفتحه الخادم
    stopped.value = text;
    if (active.value) _fallBack(text);
  }

  /// يعود الموظّف لصفحته (الجلسة كما هي، والتفضيل باقٍ: يعود الوضع عند فتح التطبيق إن فتحه الخادم ثانيةً).
  static void _fallBack(String? why) {
    focus.value = null;
    active.value = false;
    MergedSubscribers.reset();
    if (why != null) fellBack.value = fellBack.value + 1;
  }

  static String? _prefKey() {
    if (employeeSession) {
      // مفتاح الموظّف غير مفتاح المالك: الشخص (اسم دخوله، مُجزَّأً) — لا يرث موظّفٌ وضع غيره على الجهاز نفسه
      final login = (employeeLogin() ?? '').trim().toLowerCase();
      if (login.isEmpty) return null;
      return 'merged.active.emp.${sha256.convert(utf8.encode(login)).toString().substring(0, 16)}';
    }
    final uid = accountUid();
    return uid == null || uid.isEmpty ? null : 'merged.active.$uid';
  }

  /// يدخل الوضع (بعد سؤالٍ طازج) — false إن لم يعد متاحاً.
  static Future<bool> enter() async {
    await load(fresh: true);
    if (!eligible) return false;
    active.value = true;
    await _persist(true);
    return true;
  }

  /// يخرج إلى الشركة المفتوحة (لا يمسح شيئاً).
  static Future<void> exit() async {
    focus.value = null;
    active.value = false;
    MergedSubscribers.reset();
    await _persist(false);
  }

  /// عند فتح التطبيق: يعود الوضع إن كان مفعّلاً لهذا الحساب (أو لهذا الموظّف) وما زال متاحاً.
  static Future<void> restore() async {
    final k = _prefKey();
    if (k == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(k) != true) return;
    } catch (_) {
      return;
    }
    await load(fresh: true);
    if (eligible) active.value = true;
  }

  static Future<void> _persist(bool on) async {
    final k = _prefKey();
    if (k == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      if (on) {
        await p.setBool(k, true);
      } else {
        await p.remove(k);
      }
    } catch (_) {/* تفضيلٌ لا شرط */}
  }

  /// مع الجلسة (SessionManager): تبديل شركة أو خروج — لا يرث أحدٌ وضع سابقه ولا مراجعه.
  static void reset() {
    _generation++;
    _inFlight = null;
    _at = null;
    data.value = null;
    focus.value = null;
    active.value = false;
    stopped.value = null;
    CompanyRefs.reset();
    MergedSubscribers.reset();
  }
}

/// قائمة شركةٍ واحدة في «كل الشركات».
class MergedCompanyList {
  const MergedCompanyList({
    required this.company,
    this.rows,
    this.partial = false,
    this.error,
    this.bigTotal,
    this.denied = false,
  });

  final MergedCompany company;

  /// صفوفها مربوطةً بها — null: لم تُجلب (خطأ، أو حسابٌ كبير).
  final List<Subscriber>? rows;

  /// قائمةٌ ناقصة من مزوّدها (partial) — الأرقام ظاهرة وقد تكون أقلّ.
  final bool partial;

  /// نصّ التعذّر العربيّ (من الخادم إن وُجد).
  final String? error;

  /// حسابٌ كبير (≥ BigSubscribersApi.threshold) — قائمته الكاملة لا تُجلب هنا (٨٩ ألفاً ≈ ٩٦ث)؛ يُفتح منفرداً.
  final int? bigTotal;

  /// «كل الصفحات»: لا صلاحيّة له على مشتركي هذه الصفحة (خريطتها بلا subscribers.view) — لم تُطلب، وتُسمّى ولا تُعدّ.
  final bool denied;
}

/// الصفوف المدموجة وحال قوائم الشركات تحتها.
class MergedListResult {
  const MergedListResult({required this.rows, required this.parts, required this.missing});

  final List<Subscriber> rows;
  final List<MergedCompanyList> parts;

  /// شركات الحساب غير الصالحة الآن (تحتاج دخول، موقوفة، FTTH من الويب…) — تُسمّى ولا تدخل.
  final List<MergedCompany> missing;

  List<MergedCompanyList> get failed => parts.where((p) => p.rows == null && p.bigTotal == null).toList();
  List<MergedCompanyList> get big => parts.where((p) => p.bigTotal != null).toList();
  List<MergedCompanyList> get partial => parts.where((p) => p.partial).toList();

  MergedCompanyList? partOf(String key) {
    for (final p in parts) {
      if (p.company.key == key) return p;
    }
    return null;
  }

  /// صفوف العرض: الكلّ مدموجاً بلا تكرار، أو قائمة الشركة المختارة كما وصلت (كأنّها مفتوحة وحدها — عددها عددها هناك).
  List<Subscriber> rowsFor(String? key) => key == null ? rows : (partOf(key)?.rows ?? const <Subscriber>[]);

  /// مشتركو شركةٍ بلا «المهمَل» (عدّاد الرئيسية والقائمة نفسه) — null: قائمتها لم تُجلب (كبيرة أو تعذّرت).
  int? countOf(String key) => partOf(key)?.rows?.where((s) => !s.isAbandoned).length;

  /// مشتركو «الكل» بلا «المهمَل».
  int get total => rows.where((s) => !s.isAbandoned).length;

  /// من تراه صفحتان مربوطتان (المدير الفرعيّ وأمّه) يُعدّ في «الكل» مرّةً: مجموع القوائم − المدموج. ربطان للمدير نفسه
  /// قائمةٌ واحدة لا تُعدّ هنا.
  int get folded {
    final same = sameManagerOf([for (final p in parts) p.company]);
    var sum = 0;
    for (final p in parts) {
      if (p.rows != null && !same.containsKey(p.company.key)) sum += p.rows!.where((s) => !s.isAbandoned).length;
    }
    final d = sum - total;
    return d > 0 ? d : 0;
  }
}

/// قوائم الشركات ودمجها. كلّ قائمةٍ تُطلب موجّهةً لشركتها (الطلب نفسه للوضع العاديّ: GET /api/v2/subscribers)، وتُخبّأ ٤٥ث
/// لكلّ شركة، ولا تلمس مخابئ الشركة المفتوحة (قائمتها ولا نسخة القرص).
class MergedSubscribers {
  MergedSubscribers._();

  static const ttl = Duration(seconds: 45);

  /// قائمتان ثقيلتان معاً على الأكثر — كخانات الخادم لكلّ حساب (ثقيلتان).
  static const concurrency = 2;

  static final Map<String, ({DateTime at, MergedCompanyList value})> _cache = {};
  static final Map<String, Future<MergedCompanyList>> _inFlight = {};
  static int _generation = 0;

  /// جلسات كلّ شركة (عنوان الجلسة ومدّتها والتحميل والجهاز) بمفتاح اليوزر بحروفٍ صغيرة — ٤٥ث كالقوائم. عليها تقوم حالة
  /// الاتصال بالكارت (٢٢ أكتوبر): قائمة المشتركين بلا عنوان جلسة، والوضع العاديّ يأخذه من online-users (_fetchAndMerge).
  static final Map<String, ({DateTime at, Map<String, OnlineSessionInfo> value})> _online = {};
  static final Map<String, Future<Map<String, OnlineSessionInfo>?>> _onlineFlight = {};

  /// جلساتٌ أقدم من هذا لا تُلصق بقائمةٍ جديدة (تجعل المشترك «متصلاً») — الإثراء التالي يجلب الطازجة.
  static const _sessionsReuse = Duration(minutes: 2);

  /// آخر دمجٍ (للشاشات التي تقرأ بلا طلب: الرئيسية بعد المشتركين).
  static final ValueNotifier<MergedListResult?> last = ValueNotifier<MergedListResult?>(null);

  /// بعد كتابةٍ موجَّهة: قائمة شركتها تُجلب من جديد عند الطلب التالي.
  static void install() => CompanyRoute.onWrite ??= invalidate;

  static void reset() {
    _generation++;
    _cache.clear();
    _inFlight.clear();
    _online.clear();
    _onlineFlight.clear();
    last.value = null;
  }

  /// يُسقط قائمة شركةٍ بعد عمليّةٍ عليها فتُجلب من جديد.
  static void invalidate(String key) => _cache.remove(key);

  /// نصّ تعذّر قائمة [c] — [MergedMode.failText] (للمالك رسالة الخادم أو [fallback] كما كان؛ للموظّف باسم الصفحة دائماً).
  static String _err(MergedCompany c, Object? body, String fallback, [int? status]) =>
      MergedMode.failText(c, body, fallback, status: status);

  /// قائمة شركة: صفٌّ واحد يحسم «كبير؟» ثمّ القائمة الكاملة. صفحةٌ لا يرى الموظّف مشتركيها ⇒ لا طلب، وتُسمّى.
  static Future<MergedCompanyList> fetchCompany(MergedCompany c, {bool fresh = false}) {
    if (MergedMode.pagePerm(c.key, 'subscribers.view') == false) {
      return Future.value(MergedCompanyList(
        company: c,
        error: '«${c.name}»: ${MergedMode.noAccess('مشتركيها')}',
        denied: true,
      ));
    }
    final hit = _cache[c.key];
    if (!fresh && hit != null && DateTime.now().difference(hit.at) < ttl) return Future.value(hit.value);
    final running = _inFlight[c.key];
    if (running != null) return running;
    final gen = _generation;
    final f = CompanyRoute.run(c.key, () => _fetch(c)).then((v) {
      // آخر جلساتٍ طازجة لشركتها تُلصق فوراً — قائمةٌ جديدة (بعد عمليّة، أو تحديث) لا تُسقط عناوين الجلسات حتى الإثراء التالي
      final s = _online[c.key];
      final out = s != null && DateTime.now().difference(s.at) < _sessionsReuse ? _applySessions(v, s.value) : v;
      if (gen == _generation && out.rows != null) _cache[c.key] = (at: DateTime.now(), value: out);
      return out;
    }).whenComplete(() {
      // كتلةٌ لا سهم: remove يعيد المستقبل نفسه، وwhenComplete ينتظر ما يُعاد — فينتظر نفسه أبداً
      _inFlight.remove(c.key);
    });
    _inFlight[c.key] = f;
    return f;
  }

  /// جلسات شركة [c] موجَّهةً لها (GET /api/v2/online-users — مسار الوضع العاديّ نفسه، ثقيلٌ بالخادم). null: تعذّرت.
  static Future<Map<String, OnlineSessionInfo>?> fetchOnline(MergedCompany c, {bool fresh = false}) {
    final hit = _online[c.key];
    if (!fresh && hit != null && DateTime.now().difference(hit.at) < ttl) return Future.value(hit.value);
    final running = _onlineFlight[c.key];
    if (running != null) return running;
    final gen = _generation;
    final f = CompanyRoute.run(c.key, () => ApiClient.dio.get<Map<String, dynamic>>('/api/v2/online-users'))
        .then<Map<String, OnlineSessionInfo>?>((r) {
      final b = r.data ?? const {};
      if (b['success'] != true) return null;
      final m = SubscribersApi.onlineFromRows((b['data'] as List?) ?? const []);
      if (gen == _generation) _online[c.key] = (at: DateTime.now(), value: m);
      return m;
    }).catchError((Object _) => null).whenComplete(() {
      // كتلةٌ لا سهم (انظر fetchCompany)
      _onlineFlight.remove(c.key);
    });
    _onlineFlight[c.key] = f;
    return f;
  }

  /// [s] بجلسته إن وُجدت — كالوضع العاديّ حرفاً (_fetchAndMerge): الجلسة تُثري الصفّ (العنوان، المدّة، التحميل، الجهاز)
  /// وتجعله متصلاً، وغيابها لا يُنزله.
  static Subscriber withSession(Subscriber s, Map<String, OnlineSessionInfo> online) {
    final x = online[s.username.trim().toLowerCase()];
    if (x == null) return s;
    return s.copyWithOnline(
      online: true,
      ip: x.ip,
      session: x.sessionTime,
      dl: x.downloadBytes,
      ul: x.uploadBytes,
      device: x.device,
    );
  }

  static MergedCompanyList _applySessions(MergedCompanyList l, Map<String, OnlineSessionInfo> online) => l.rows == null
      ? l
      : MergedCompanyList(
          company: l.company,
          rows: [for (final s in l.rows!) withSession(s, online)],
          partial: l.partial,
          error: l.error,
          bigTotal: l.bigTotal,
        );

  /// آخر جلساتٍ معروفة لشركة (بلا طلب) — لصفٍّ يُعاد جلبه وحده بعد عمليّة.
  static Map<String, OnlineSessionInfo>? sessionsOf(String? key) => key == null ? null : _online[key]?.value;

  /// [r] بجلسات شركاتها — كالوضع العاديّ: القائمة تُعرض أوّلاً ثمّ تُثرى (شركتان معاً على الأكثر — خانتا الحساب الثقيلتان).
  /// المتعذّرة تبقى كما هي، والمُثرى يحلّ مكان الأصل في المخبأ (بوقته) فلا تومض الجلسات مع التحديث التالي.
  static Future<MergedListResult> withSessions(MergedListResult r, {bool fresh = false}) async {
    final gen = _generation;
    final todo = [
      for (final p in r.parts)
        if (p.rows != null) p,
    ];
    if (todo.isEmpty) return r;
    final sessions = <String, Map<String, OnlineSessionInfo>>{};
    var next = 0;
    Future<void> worker() async {
      while (next < todo.length) {
        final p = todo[next++];
        final m = await fetchOnline(p.company, fresh: fresh);
        if (m != null) sessions[p.company.key] = m;
      }
    }

    await Future.wait([for (var w = 0; w < concurrency && w < todo.length; w++) worker()]);
    if (sessions.isEmpty || gen != _generation) return r;
    final parts = [
      for (final p in r.parts)
        if (sessions[p.company.key] case final m?) _applySessions(p, m) else p,
    ];
    for (var i = 0; i < parts.length; i++) {
      final k = r.parts[i].company.key;
      final hit = _cache[k];
      if (hit != null && identical(hit.value, r.parts[i])) _cache[k] = (at: hit.at, value: parts[i]);
    }
    final out = _combine(parts, r.missing);
    if (gen == _generation) last.value = out;
    return out;
  }

  static MergedListResult _combine(List<MergedCompanyList> parts, List<MergedCompany> missing) => MergedListResult(
        rows: mergeRows([
          for (final p in parts)
            if (p.rows != null) MergePart(company: p.company, rows: p.rows!, partial: p.partial),
        ]),
        parts: parts,
        missing: missing,
      );

  static Future<MergedCompanyList> _fetch(MergedCompany c) async {
    try {
      final probe = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers',
        queryParameters: const {'page': 1, 'size': 1},
      );
      final pb = probe.data ?? const {};
      if (pb['success'] == false) {
        return MergedCompanyList(company: c, error: _err(c, pb, 'تعذّر جلب مشتركي «${c.name}» الآن', probe.statusCode));
      }
      final total = pb['total'] is num ? (pb['total'] as num).toInt() : int.tryParse('${pb['total']}') ?? 0;
      if (pb['paged'] == true && total >= BigSubscribersApi.threshold) {
        return MergedCompanyList(company: c, bigTotal: total);
      }
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/subscribers');
      final b = r.data ?? const {};
      if (b['success'] != true) {
        return MergedCompanyList(company: c, error: _err(c, b, 'تعذّر جلب مشتركي «${c.name}» الآن', r.statusCode));
      }
      final rows = <Subscriber>[
        for (final m in (b['data'] as List?) ?? const [])
          if (m is Map) Subscriber.fromJson(Map<String, dynamic>.from(m)).withCompany(c.key),
      ];
      return MergedCompanyList(company: c, rows: rows, partial: b['partial'] == true);
    } on DioException catch (e) {
      return MergedCompanyList(
          company: c, error: _err(c, e.response?.data, 'تعذّر الوصول لمشتركي «${c.name}» الآن', e.response?.statusCode));
    } catch (_) {
      return MergedCompanyList(company: c, error: 'تعذّر جلب مشتركي «${c.name}» الآن');
    }
  }

  /// كلّ الشركات الصالحة (قائمتان معاً على الأكثر) ثمّ الدمج.
  static Future<MergedListResult> load({bool fresh = false}) async {
    install();
    final d = await MergedMode.load();
    final usable = d.usable;
    final missing = d.companies.where((c) => !c.usable).toList();
    final gen = _generation;
    final results = List<MergedCompanyList?>.filled(usable.length, null);
    var next = 0;
    Future<void> worker() async {
      while (next < usable.length) {
        final i = next++;
        results[i] = await fetchCompany(usable[i], fresh: fresh);
      }
    }

    await Future.wait([for (var w = 0; w < concurrency && w < usable.length; w++) worker()]);
    final parts = results.whereType<MergedCompanyList>().toList();
    final out = _combine(parts, missing);
    if (gen == _generation) last.value = out;
    return out;
  }
}

/// العمليّات على مشتركٍ مدموج: كلّ نداءٍ يخصّه موجَّهٌ لشركة صفّه (Subscriber.companyKey)، والكتابة تسبقها هويّته من ساس
/// شركته (GET /api/v2/subscribers/:idx — يسكّ الخادم عليها مرجع النافذة الذي تطلبه كلّ كتابة). الوضع العاديّ كما هو حرفاً.
class MergedOps {
  MergedOps._();

  /// قراءةٌ أو نداءٌ بمرجعه الخاصّ (عرض السعر للتفعيل والتمديد) — موجَّهٌ لشركة [s].
  static Future<T> run<T>(Subscriber s, Future<T> Function() body) => CompanyRoute.run(s.companyKey, body);

  /// كتابةٌ على [s] (تسديد، دين، خصم، فصل، تعطيل، تعديل، حذف…): مرجع النافذة أوّلاً ثمّ النداء موجَّهاً.
  static Future<T> write<T>(Subscriber s, Future<T> Function() body) => writeAt(s.companyKey, s.idx, body);

  /// [write] بمفتاح الشركة والـidx (شاشاتٌ لا تحمل الصفّ كاملاً: السعر الثابت).
  static Future<T> writeAt<T>(String? key, String? idx, Future<T> Function() body) async {
    if (key == null) return body();
    await ensureSubjectAt(key, idx);
    return CompanyRoute.run(key, body);
  }

  /// يسكّ مرجع النافذة لـ[s] إن لم يكن محفوظاً. فشله لا يرمي: الكتابة بعده يرفضها الخادم برسالته («لم يُنفَّذ شيء»).
  static Future<void> ensureSubject(Subscriber s) => ensureSubjectAt(s.companyKey, s.idx);

  static Future<void> ensureSubjectAt(String? key, String? idx) async {
    if (key == null || idx == null || idx.isEmpty) return;
    if (CompanyRefs.lookup(key, idx, CompanyRefKind.subject) != null) return;
    try {
      await CompanyRoute.run(key, () => ApiClient.dio.get<dynamic>('/api/v2/subscribers/${Uri.encodeComponent(idx)}'));
    } catch (_) {/* الخادم يرفض الكتابة بلا مرجعٍ برسالته */}
  }

  /// إجراءٌ مساره خارج جدول التوجيه: في «كل الشركات» لا يُنفَّذ (كان سيقع على الشركة المفتوحة لا شركة الصفّ).
  static String? unsupported(Subscriber s) => unsupportedAt(s.companyKey);

  /// [unsupported] بمفتاح الشركة وحده — لودجتٍ لا تحمل الصفّ كاملاً (كارت الجهاز: حفظ إعداد الجهاز خارج جدول التوجيه).
  static String? unsupportedAt(String? key) => key == null
      ? null
      : MergedMode.employeeSession
          ? 'هذا الإجراء يعمل من الصفحة وحدها — انتقل إليها من «صفحاتي»'
          : 'هذا الإجراء يعمل من الشركة وحدها — افتحها من «تبديل الشركة»';

  /// «كل الصفحات» للموظّف: كتابةٌ على مشترك [s] مقفلةٌ قبل الإرسال — سببها ([MergedMode.writeLockFor]) أو null (مفتوحة؛
  /// والمالك دائماً null). الزرّ يبقى بمكانه مقفلاً بهذا السبب، والمعترض لا يرسلها ولو وصلت.
  static String? writeLock(Subscriber s) => MergedMode.writeLockFor(s.companyKey);

  /// [writeLock] بمفتاح الصفحة وحده.
  static String? writeLockAt(String? key) => MergedMode.writeLockFor(key);

  /// مزوّد شركة الصفّ المدموج (null في الوضع العاديّ ⇒ مزوّد الجلسة المفتوحة يحسم كما كان): شاشةٌ تفرّق بين ساسٍ وايرث لنك
  /// تسأل عن شركة المشترك لا الشركة المفتوحة.
  static bool? isEarthlink(Subscriber s) {
    final c = MergedMode.companyOf(s.companyKey);
    return c == null ? null : c.provider == MergedProvider.earthlink;
  }

  /// الصفّ نفسه من قائمة شركته الطازجة (بعد عمليّة) — null إن تعذّر.
  static Future<Subscriber?> refetch(Subscriber s) async {
    final c = MergedMode.companyOf(s.companyKey);
    if (c == null) return null;
    final l = await MergedSubscribers.fetchCompany(c, fresh: true);
    for (final r in l.rows ?? const <Subscriber>[]) {
      if (s.idx != null && r.idx == s.idx) return r;
    }
    for (final r in l.rows ?? const <Subscriber>[]) {
      if (r.username == s.username) return r;
    }
    return null;
  }
}
