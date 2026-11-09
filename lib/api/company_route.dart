import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, VoidCallback, visibleForTesting;
import 'package:flutter/widgets.dart' show BuildContext, ModalRoute, Navigator;

/// «كل الشركات» في التطبيق (٢١ أكتوبر، المالك: «ابدي بيها خل نكملها» — تصميمنا لا كودكس).
///
/// نداءٌ يخصّ شركةً من شركات حساب Pro يمرّ بخادمنا **بتوكن الحساب وحده** + `x-company-key`، فيأخذ الخادم جلسة تلك الشركة
/// المخزّنة عنده ويبدّلها على الطلب نفسه (server/companyRouting.js) — لا دخول ولا خروج، ولا توكن شركةٍ يصل الهاتف أبداً.
/// هذا الملفّ: أيّ طلبٍ لأيّ شركة (النطاق)، ومراجع النوافذ (`x-company-ref`)، ونصوص الأخطاء. المعترض في api_client.dart.
///
/// **قاعدة الوجهة (٩ نوفمبر — مراجعة 179، [decide]):**
/// ١. صريحٌ أوّلاً: `extra['companyKey']`/`extra['companyOpen']` من معامل النداء، ثمّ أعمق نطاقٍ ([run]/[pin]/[runOpen]).
/// ٢. الكتابة (غير GET وغير [readsByPost]) لا تأخذ وجهة قسمٍ أبداً: بلا اختيارٍ صريح ⇒ المفتوحة — إلّا إن كان أعلى نطاقٍ يطابق
///    مسارها قسماً موجَّهاً لشركةٍ أخرى (الشاشة تعرض غيرها) ⇒ لا تُرسل أصلاً ([RouteDecision.refused]: «لم يُنفَّذ شيء»).
/// ٣. القراءة بلا اختيارٍ صريح تأخذ وجهة **أعلى** نطاقٍ ظاهرٍ يطابق مسارها ([enterSection]) — والنطاق يُرتَّب بصفحته لا بلحظة
///    دخوله ([orderOf]): صفحةٌ للمفتوحة فوق القسم ([enterOpen]: إشعار، جرس، «الصفحات»، مشتركٌ بلا مفتاح، «الكلّ») تغطّيه.
/// ٤. قسمٌ مخفيّ أو مغطّى لا يوجِّه؛ وطلبٌ ضمنيّ يطابق بادئاته ذهب لغير شركته يُعلمه ([enterSection] `onTaint`) فلا تبقى شاشته
///    بأرقام شركةٍ تحت اسم أخرى.
class CompanyRoute {
  CompanyRoute._();

  static const Symbol _zoneKey = #companyRouteKey;

  /// مفتاح الشركة: c + 12 hex (= accountOverview.companyKey بالخادم — مُحدِّدٌ لا إثبات).
  static final RegExp keyRe = RegExp(r'^c[0-9a-f]{12}$');

  /// يشغّل [body] — وكلّ نداء ApiClient يطلقه ولو بعد await — موجَّهاً للشركة [key]. key null ⇒ كما هو (الوضع العاديّ).
  /// النداءات التي تبدأ من زرٍّ لاحقاً تخرج من النطاق: كلّ نداءٍ يخصّ مشتركاً مدموجاً يُغلَّف بمفتاح صفّه.
  /// أعمق نطاقٍ يغلب: [run] داخل [runOpen] لشركته (يُلغي «المفتوحة» الموروثة).
  static Future<T> run<T>(String? key, Future<T> Function() body) {
    if (key == null || !keyRe.hasMatch(key)) return body();
    return runZoned(body, zoneValues: {_zoneKey: key, _openKey: false});
  }

  static const Symbol _openKey = #companyRouteOpen;

  /// يشغّل [body] للشركة المفتوحة صراحةً — لا يأخذ وجهة قسمٍ مفتوح ([enterSection]) ولو طابقت بادئاته (٨ نوفمبر): حال المفتوحة
  /// المشترك (عدّاد «طلبات التفعيل» بالجرس…) يُحدَّث بالخلفيّة وقسمٌ موجَّه لغيرها مفتوحٌ بالبادئات نفسها — فلا يُكتب فوقه رقم غيرها.
  static Future<T> runOpen<T>(Future<T> Function() body) => runZoned(body, zoneValues: {_openKey: true, _zoneKey: null});

  /// شركةٌ صريحة لما يُنفَّذ في [body]: مفتاحٌ صالح ⇒ لها ([run])، وإلّا ⇒ المفتوحة ([runOpen]). لما يلتقط شركته لحظة فتحه
  /// (شيت كتابةٍ في قسم، صفحةٌ تُقرأ دوريّاً) فلا يغيّرها ما يتبدّل تحته بعد ذلك (الشريط، قسمٌ يُخفى أو يُغطّى).
  static Future<T> pin<T>(String? key, Future<T> Function() body) =>
      key != null && keyRe.hasMatch(key) ? run(key, body) : runOpen(body);

  /// خيارات نداءٍ بشركةٍ صريحة — كـ[pin] لنداءٍ واحد: مفتاحٌ ⇒ `extra['companyKey']`، وnull ⇒ `extra['companyOpen']` (المفتوحة
  /// صراحةً). المعامل الصريح يغلب كلّ نطاق.
  static Options explicit(String? key, [Options? base]) {
    final o = base ?? Options();
    final k = key != null && keyRe.hasMatch(key) ? key : null;
    return o.copyWith(extra: {
      ...?o.extra,
      if (k != null) 'companyKey': k else 'companyOpen': true,
    });
  }

  /// مفتاح النطاق الحاليّ (null خارج أيّ نطاق).
  static String? get currentKey {
    final z = Zone.current[_zoneKey];
    return z is String && keyRe.hasMatch(z) ? z : null;
  }

  /// بعد كلّ كتابةٍ موجَّهة وصلت الخادم — أيّاً كان ردّها — تُسقط قائمة شركتها فتُجلب من جديد (كبطاقتها في «لوحة حسابي»).
  static void Function(String key)? onWrite;

  // ── «كل الصفحات» للموظّف (٩ نوفمبر — المالك: «الموظف… يشوف كل الصفحات مثل المدير… حسب الصلاحيات المعطاه اله») ──
  // الموظّف يوجَّه بتوكنه هو (Bearer + x-auth-token كطلبه العاديّ) + المفتاح — لا توكن حسابٍ له ولا يُرسل أبداً. والخادم ينفّذ
  // الطلب بصفّه في تلك الصفحة وبصلاحيّاتها هي. المعترض (api_client.dart) يقرّر بالجلسة نفسها؛ وهذه منافذ [MergedMode] إليه.

  /// سبب قفل الكتابة على صفحة [key] من «كل الصفحات» (null = مفتوحة) — يضبطه MergedMode من ردّ صفحاته (`writes` لكلّ صفحة).
  /// كتابةٌ على مشترك صفحةٍ مقفلة لا تُرسل أصلاً: ردٌّ محلّيّ 409 COMPANY_ROUTE_WRITES_PAUSED بهذا السبب.
  static String? Function(String key)? writeLockOf;

  /// الخادم أطفأ «كل الصفحات» (409 COMPANY_ROUTE_DISABLED على طلبٍ موجَّهٍ للموظّف) — MergedMode يعيده لصفحته برسالة الخادم.
  static void Function(String? message)? onEmployeeRouteStopped;

  /// اسم الشركة [key] لرسالة الرفض ([ambiguousText]) — يضبطه MergedMode (الملفّ لا يعرف الشركات).
  static String? Function(String key)? nameOf;

  /// «كل الشركات» فعّال الآن — يضبطه MergedMode. فيه تُرفض كلّ كتابةٍ **ضمنيّة** على مسار مشترك ([decide]): كلّ كتابةٍ شرعيّة على
  /// مشتركٍ في الوضع صريحة (MergedOps بمفتاح صفّه، وبلا مفتاح ⇒ المفتوحة صراحةً) — والضمنيّة لا تعرف لأيّ شركةٍ رقم الصفّ.
  static bool Function()? mergedActive;

  /// مسار مشترك: `/api/v2/subscribers` (إضافة) أو ما تحته (`/:idx/...`).
  static bool isSubscriberPath(String path) => path == '/api/v2/subscribers' || path.startsWith('/api/v2/subscribers/');

  /// «كل الصفحات» للموظّف: كلمة «صفحة» بدل «شركة» في رسالة الرفض — يضبطه MergedMode.
  static bool Function()? employeeWords;

  /// طلباتٌ غير GET لا تغيّر قائمة مشتركي الشركة فلا تُسقطها ([onWrite]): قراءةٌ بـPOST، أو قراءات «تنبيه المشترك» إلى جدولنا
  /// (٤ نوفمبر — تُرفع بعد كلّ موجة فحص، فإسقاطها كان يعيد جلب قائمة كلّ شركةٍ معها).
  static const Set<String> keepsList = {
    '/api/v2/subscribers/device-batch',
    '/api/v2/subscribers/last-macs',
    '/api/v2/connection-alerts/readings',
    // «المبيعات» (٨ نوفمبر): حالة تسديد البيع على الدين قراءةٌ بـPOST — لا تُسقط قائمة الشركة كلّما فُتح القسم
    '/api/v2/sales/debt-status',
  };

  /// قراءاتٌ بـPOST — تُعامَل قراءةً في [decide] (تتبع القسم كالـGET). الخادم: last-macs وdevice-batch وsales-debt-status
  /// (companyRoutingAllow R بـPOST)؛ وفحص خطر الرقم قراءةٌ لا يوجّهها الخادم (يرفضها موجَّهةً كما كان).
  static const Set<String> readsByPost = {
    '/api/v2/subscribers/device-batch',
    '/api/v2/subscribers/last-macs',
    // بحث الحساب الكبير بأرقام/يوزرات (big_subscribers_api lookup) — قراءة
    '/api/v2/subscribers/lookup',
    '/api/v2/sales/debt-status',
    '/api/v2/whatsapp/contact-risk',
    '/api/v2/whatsapp/bulk-risk',
  };

  /// قراءةٌ لا كتابة: GET (أو HEAD)، أو POST على إحدى [readsByPost] — بـPOST وحده (مراجعة 179): PUT/PATCH/DELETE على مسارٍ منها
  /// كتابةٌ تُحكم كالكتابة (لا تأخذ وجهة قسمٍ ولا تمرّ بلا رفض).
  static bool isRead(String method, String path) {
    final m = method.toUpperCase();
    return m == 'GET' || m == 'HEAD' || (m == 'POST' && readsByPost.contains(path));
  }

  // ─────────────────────────────── النطاقات ───────────────────────────────

  /// «قوائم أخرى» بـ«كل الشركات» (٨ نوفمبر — المالك: «كل الاقسام مال قائمة المزيد لازم تخضع لهذا النظام شركتين بدقة»): قسمٌ
  /// مفتوحٌ بشركةٍ غير المفتوحة ⇒ **قراءات** بادئات مساراته — من أيّ زرٍّ أو شيتٍ فيه — موجَّهةٌ لها، وما سواها كما هو (الرئيسيّة
  /// والإشعارات بالخلفيّة لا تتأثّر). [MergedSection] (lib/widgets/merged_section.dart) يضعه ويرفعه.
  ///
  /// الأقسام والصفحات المفتوحة للمفتوحة ([enterOpen]) نطاقاتٌ مرتّبةٌ **بموضع صفحتها** ([orderOf]: الجذر فوق أقسام الحاسبة، ثمّ
  /// ظهور الصفحة) — المسار يأخذ وجهة أعلاها مطابقةً. قسمٌ يُفتح من داخل قسم («تسوية الحساب ←» من الصرفيات) فوقه، وإغلاق
  /// الداخليّ لا يمحو الخارجيّ؛ وصفحةٌ للمفتوحة فوق قسمٍ تغطّيه حتى تُغلق.
  static final List<_Scope> _scopes = [];
  static int _seq = 0;
  static int _reg = 0;
  static final Expando<int> _routeSeq = Expando<int>('companyRouteSeq');

  /// يرتفع بعد كلّ تغيّرٍ في النطاقات (دخولٌ أو خروجٌ أو إخفاء) — الأقسام تعيد حساب ما يغطّيها. يُبلَّغ بعد البناء الجاري.
  static final ValueNotifier<int> scopes = ValueNotifier<int>(0);
  static bool _bumpQueued = false;

  static void _bump() {
    if (_bumpQueued) return;
    _bumpQueued = true;
    scheduleMicrotask(() {
      _bumpQueued = false;
      scopes.value = scopes.value + 1;
    });
  }

  /// موضع صفحة [context]: الطبقة (1 = Navigator الجذر، 0 = Navigator قسمٍ على الحاسبة — الجذر فوقه دائماً) ثمّ ترتيب ظهور الصفحة
  /// (أوّل ما يُرى نطاقٌ فيها). يُنادى من didChangeDependencies أو build (يعتمد على الصفحة).
  static ScopeOrder orderOf(BuildContext context) {
    final route = ModalRoute.of(context);
    final nav = Navigator.maybeOf(context);
    final root = Navigator.maybeOf(context, rootNavigator: true);
    final level = nav == null || identical(nav, root) ? 1 : 0;
    if (route == null) return (level: level, seq: ++_seq);
    final s = _routeSeq[route] ??= ++_seq;
    return (level: level, seq: s);
  }

  static _Scope? _find(Object owner) {
    for (final s in _scopes) {
      if (identical(s.owner, owner)) return s;
    }
    return null;
  }

  static void _put(
    Object owner, {
    required String? key,
    required List<String>? prefixes,
    String? adminId,
    ScopeOrder? order,
    VoidCallback? onTaint,
    bool parked = false,
  }) {
    final cur = _find(owner);
    if (cur != null) {
      final changed =
          cur.key != key || cur.parked != parked || !_samePrefixes(cur.prefixes, prefixes) || (order != null && cur.order != order);
      cur
        ..key = key
        ..prefixes = prefixes
        ..adminId = adminId
        ..parked = parked;
      if (order != null) cur.order = order;
      if (onTaint != null) cur.onTaint = onTaint;
      if (changed) _bump();
      return;
    }
    _scopes.add(_Scope(
      owner: owner,
      key: key,
      prefixes: prefixes,
      adminId: adminId,
      order: order ?? (level: 1, seq: ++_seq),
      reg: ++_reg,
      onTaint: onTaint,
    )..parked = parked);
    _bump();
  }

  static bool _samePrefixes(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// قسمٌ يعرض الشركة [key]: قراءات [prefixes] موجَّهةٌ لها ما دام أعلى نطاقٍ يطابقها. [adminId] معرّف مدير الشركة المختارة —
  /// لمسارات `/:adminId` في القسم ([sectionAdminIdFor]) بدل المفتوحة. [order] موضع صفحته ([orderOf]) — بلاه: فوق ما سبقه.
  /// [parked] مخفيٌّ (جزء حاسبةٍ غير ظاهر): لا يوجِّه، ويبقى معروفاً لـ[onTaint]. [onTaint]: طلبٌ ضمنيّ يطابق بادئاته ذهب لغير
  /// شركته وهو مخفيٌّ أو مغطّى — شاشته قد تكون طلبته فلا تُعرض أرقامه تحت اسمها.
  static void enterSection(
    Object owner,
    String key,
    List<String> prefixes, {
    String? adminId,
    ScopeOrder? order,
    VoidCallback? onTaint,
    bool parked = false,
  }) {
    if (!keyRe.hasMatch(key)) return;
    _put(owner,
        key: key,
        prefixes: List<String>.unmodifiable(prefixes),
        adminId: adminId,
        order: order,
        onTaint: onTaint,
        parked: parked);
  }

  /// صفحةٌ للشركة المفتوحة صراحةً (٩ نوفمبر): كلّ قراءةٍ تحتها — أيّ مسار — للمفتوحة، وما تحتها من أقسامٍ موجَّهة مغطّى حتى
  /// تُغلق. الإشعار والجرس و«الصفحات» ومشتركٌ بلا مفتاح و«الكلّ» المثبَّت للمفتوحة ([OpenCompanyScope]، `MergedSection.openCompany`).
  static void enterOpen(Object owner, {ScopeOrder? order}) => _put(owner, key: null, prefixes: null, order: order);

  /// يرفعه صاحبه وحده (قسمٌ أُغلق بعد أن فتح غيره لا يرفع قسم الآخر).
  static void leaveSection(Object owner) {
    final n = _scopes.length;
    _scopes.removeWhere((s) => identical(s.owner, owner));
    if (_scopes.length != n) _bump();
  }

  /// أعلى نطاقٍ ظاهرٍ يطابق [path] — البادئة نفسها أو ما تحتها (`/x` لا `/xy`)؛ الصفحة المفتوحة للمفتوحة تطابق كلّ مسار.
  static _Scope? _top(String path) {
    _Scope? best;
    for (final s in _scopes) {
      if (s.parked || !s.matches(path)) continue;
      if (best == null || s.isAbove(best)) best = s;
    }
    return best;
  }

  /// مفتاح أعلى قسمٍ لمسار القراءة — أو null (لا قسم، أو صفحةٌ للمفتوحة فوقه).
  static String? sectionKeyFor(String path) => _top(path)?.key;

  /// معرّف مدير الشركة المختارة إن كان [path] لقسمٍ موجَّه — وإلّا null (المفتوحة كما كانت).
  static String? sectionAdminIdFor(String path) {
    final s = _top(path);
    return s == null || s.key == null ? null : s.adminId;
  }

  /// معرّف مدير الشركة [key] (MergedMode يضبطه) — لمسارات `/:adminId` في نطاقٍ صريح.
  static String? Function(String key)? adminIdOf;

  /// معرّف مدير شركة الطلب لمسارات `/:adminId` — بقاعدة [decide] نفسها: نطاقٌ صريح ([run]/[pin]) ⇒ مدير شركته، والمفتوحة صراحةً
  /// ⇒ null (معرّف الجلسة كما كان)، وإلّا أعلى قسمٍ لمساره ([sectionAdminIdFor]). فلا يذهب طلبٌ لشركةٍ بمعرّف مدير غيرها.
  static String? adminIdFor(String path) {
    final z = currentKey;
    if (z != null) return adminIdOf?.call(z);
    if (Zone.current[_openKey] == true) return null;
    return sectionAdminIdFor(path);
  }

  /// مغطّى: صفحةٌ للمفتوحة ([enterOpen]) فوقه — قراءات بادئاته لها لا له حتى تُغلق.
  static bool shadowed(Object owner) {
    final s = _find(owner);
    if (s == null) return false;
    for (final o in _scopes) {
      if (identical(o, s) || o.parked || o.prefixes != null || o.key != null) continue;
      if (o.isAbove(s)) return true;
    }
    return false;
  }

  /// وجهة أعلى نطاقٍ ظاهر (أيّ مسار) — للاختبار.
  @visibleForTesting
  static String? get sectionKey {
    _Scope? best;
    for (final s in _scopes) {
      if (s.parked) continue;
      if (best == null || s.isAbove(best)) best = s;
    }
    return best?.key;
  }

  @visibleForTesting
  static void debugReset() {
    _scopes.clear();
    _bumpQueued = false;
  }

  /// قرار وجهة الطلب — القاعدة أعلى الملفّ.
  static RouteDecision decide(RequestOptions o) {
    final x = o.extra['companyKey'];
    if (x is String && keyRe.hasMatch(x)) return RouteDecision._(x);
    if (o.extra['companyOpen'] == true) return const RouteDecision._(null);
    final z = currentKey;
    if (z != null) return RouteDecision._(z);
    if (Zone.current[_openKey] == true) return const RouteDecision._(null);
    final path = o.uri.path;
    final top = _top(path);
    if (!isRead(o.method, path)) {
      // الكتابة لا تأخذ وجهة قسم: الشاشة تعرض شركةً أخرى لهذا المسار ولم يقل النداء لأيّها ⇒ لا تُرسل
      final shown = top?.key;
      if (shown != null) return RouteDecision._(null, refusedFor: shown);
      // «كل الشركات»: كتابةٌ ضمنيّة على مشترك ⇒ لا تُرسل (التحقّق الثاني من 179: «تحديد الكلّ» بجدول الحاسبة أرسل أرقام صفوف
      // شركاتٍ أخرى للمفتوحة) — الشرعيّة كلّها صريحة.
      if (isSubscriberPath(path) && (mergedActive?.call() ?? false)) return const RouteDecision._(null, unscoped: true);
      _taint(path, null, top);
      return const RouteDecision._(null);
    }
    final key = top?.key;
    _taint(path, key, top);
    return RouteDecision._(key);
  }

  /// مفتاح شركة الطلب — [decide] بلا الرفض (كتابةٌ مرفوضة ⇒ null).
  static String? keyFor(RequestOptions o) => decide(o).key;

  /// طلبٌ ضمنيّ ذهب لـ[decided] ومساره من بادئات قسمٍ موجَّهٍ لغيرها مخفيٍّ أو مغطّى: شاشته قد تكون طلبته.
  static void _taint(String path, String? decided, _Scope? top) {
    for (final s in _scopes) {
      if (identical(s, top) || s.key == null || s.key == decided || !s.matches(path)) continue;
      final cb = s.onTaint;
      if (cb != null) scheduleMicrotask(cb);
    }
  }

  /// نصّ رفض كتابةٍ ضمنيّة على مشتركٍ في «كل الشركات» ([RouteDecision.unscoped]).
  static String unscopedText() => (employeeWords?.call() ?? false)
      ? 'لم يُنفَّذ شيء — في «كل الصفحات» نفّذها من صفحة المشترك نفسه لتذهب لصفحته'
      : 'لم يُنفَّذ شيء — في «كل الشركات» نفّذها من صفحة المشترك نفسه لتذهب لشركته';

  /// نصّ رفض الكتابة بلا شركةٍ صريحة ([RouteDecision.refused]).
  static String ambiguousText(String key) {
    final emp = employeeWords?.call() ?? false;
    final n = (nameOf?.call(key) ?? '').trim();
    final where = n.isEmpty ? (emp ? 'صفحةً أخرى' : 'شركةً أخرى') : '«$n»';
    return emp
        ? 'لم يُنفَّذ شيء — هذا الإجراء لم يحدّد صفحته وأنت تعرض $where هنا. نفّذه من القسم نفسه'
        : 'لم يُنفَّذ شيء — هذا الإجراء لم يحدّد شركته وأنت تعرض $where هنا. نفّذه من القسم نفسه';
  }
}

/// موضع نطاقٍ بين الصفحات ([CompanyRoute.orderOf]).
typedef ScopeOrder = ({int level, int seq});

/// قرار [CompanyRoute.decide]: [key] الوجهة (null = المفتوحة)، و[refusedFor] كتابةٌ لا تُرسل.
class RouteDecision {
  const RouteDecision._(this.key, {this.refusedFor, this.unscoped = false});
  final String? key;

  /// كتابةٌ بلا شركةٍ صريحة وأعلى نطاقٍ لمسارها قسمٌ يعرض الشركة [refusedFor] ⇒ لا تُرسل (ردٌّ محلّيّ 409).
  final String? refusedFor;

  /// كتابةٌ ضمنيّة على مشتركٍ و«كل الشركات» فعّال ⇒ لا تُرسل ([CompanyRoute.unscopedText]).
  final bool unscoped;
  bool get refused => refusedFor != null || unscoped;

  /// نصّ الرفض للردّ المحلّيّ.
  String get refusalText => refusedFor != null ? CompanyRoute.ambiguousText(refusedFor!) : CompanyRoute.unscopedText();
}

class _Scope {
  _Scope({
    required this.owner,
    required this.key,
    required this.prefixes,
    required this.adminId,
    required this.order,
    required this.reg,
    this.onTaint,
  });
  final Object owner;

  /// null = المفتوحة.
  String? key;

  /// null = كلّ المسارات (صفحةٌ للمفتوحة).
  List<String>? prefixes;
  String? adminId;
  ScopeOrder order;
  final int reg;
  bool parked = false;
  VoidCallback? onTaint;

  bool matches(String path) {
    final ps = prefixes;
    if (ps == null) return true;
    for (final p in ps) {
      if (path == p || path.startsWith('$p/')) return true;
    }
    return false;
  }

  bool isAbove(_Scope o) => order.level != o.order.level
      ? order.level > o.order.level
      : order.seq != o.order.seq
          ? order.seq > o.order.seq
          : reg > o.reg;
}

/// نوع مرجع النافذة — كما في server/companyRoutingAllow.js (refKind).
enum CompanyRefKind { subject, activate, extend }

/// مراجع النوافذ (`x-company-ref`): يسكّها الخادم على قراءة هويّة المشترك (subject)، وبيانات التفعيل (activate)، وخيارات
/// التمديد (extend) — مربوطةً بـ(الحساب، الشركة، idx) — ويطلبها على كلّ كتابةٍ على المشترك: ناقصٌ أو منتهٍ أو لغيره ⇒ 409 قبل
/// أيّ نداءٍ لساس (لم يُنفَّذ شيء). تُحفظ هنا لكلّ (شركة، idx، نوع)؛ عرض السعر يُستهلك بنجاح العمليّة فيُسقط معه.
class CompanyRefs {
  CompanyRefs._();

  static final Map<String, String> _refs = {};
  static final RegExp _refRe = RegExp(r'^r_[A-Za-z0-9_-]{22}$');
  static final RegExp _base = RegExp(r'^/api/v2/subscribers/([^/]+)(?:/([a-z-]+))?$');

  /// مساراتٌ تحت /api/v2/subscribers/ ليست مشتركاً.
  static const Set<String> _notIdx = {'last-macs', 'bulk-activate', 'device-batch', 'lookup', 'bulk'};

  /// كتاباتٌ بمرجع النافذة (subject) — كجدول الخادم (W بـSUBJECT).
  static const Set<String> _subjectWrites = {
    '', 'pay-debt', 'add-debt', 'discount', 'price', 'disconnect', 'toggle-enabled', 'cancel-profile-change',
    'account-password', 'send-info', 'send-link', 'send-debt-reminder', 'generate-link', 'portal-qr-token',
    // «ملاحظة خاصّة» (٣١ أكتوبر): الحفظ والحذف بمرجع النافذة (companyRoutingAllow private-note-set/remove).
    'private-note',
  };

  static String _k(String key, String idx, CompanyRefKind kind) => '$key|$idx|${kind.name}';

  static ({String idx, String tail})? _parse(String path) {
    final m = _base.firstMatch(path);
    if (m == null) return null;
    final idx = Uri.decodeComponent(m.group(1)!);
    if (_notIdx.contains(idx)) return null;
    return (idx: idx, tail: m.group(2) ?? '');
  }

  /// قراءةٌ يسكّ الخادم عليها مرجعاً — (idx، النوع) أو null.
  static ({String idx, CompanyRefKind kind})? mintOf(String method, String path) {
    if (method.toUpperCase() != 'GET') return null;
    final p = _parse(path);
    if (p == null) return null;
    return switch (p.tail) {
      '' => (idx: p.idx, kind: CompanyRefKind.subject),
      'activation-data' => (idx: p.idx, kind: CompanyRefKind.activate),
      'extension-options' => (idx: p.idx, kind: CompanyRefKind.extend),
      _ => null,
    };
  }

  /// البيع من «المبيعات» (٨ نوفمبر — companyRoutingAllow sales-sell bodySubject): المشترك في الجسم — customer.kind ==
  /// 'subscriber' (تفسير الخادم حرفاً) ⇒ مرجع نافذته لـ customer.idx المقصوص؛ الزبون العابر بلا مرجع.
  static String? _bodySubject(String method, String path, Object? data) {
    if (method != 'POST' || path != '/api/v2/sales' || data is! Map) return null;
    final c = data['customer'];
    if (c is! Map || c['kind'] != 'subscriber') return null;
    final raw = c['idx'];
    final idx = (raw is String || raw is num) ? '$raw'.trim() : '';
    return RegExp(r'^\d{1,12}$').hasMatch(idx) ? idx : null;
  }

  /// كتابةٌ يطلب الخادم لها مرجعاً — (idx، النوع) أو null. [data] جسم الطلب (للمشترك في الجسم).
  static ({String idx, CompanyRefKind kind})? requireOf(String method, String path, [Object? data]) {
    final m = method.toUpperCase();
    if (m == 'GET') return null;
    final body = _bodySubject(m, path, data);
    if (body != null) return (idx: body, kind: CompanyRefKind.subject);
    final p = _parse(path);
    if (p == null) return null;
    if (m == 'POST' && p.tail == 'activate') return (idx: p.idx, kind: CompanyRefKind.activate);
    if (m == 'POST' && p.tail == 'extend') return (idx: p.idx, kind: CompanyRefKind.extend);
    if (_subjectWrites.contains(p.tail)) return (idx: p.idx, kind: CompanyRefKind.subject);
    return null;
  }

  /// يحفظ مرجع ردٍّ موجَّه إن سكّه الخادم.
  static void capture(String key, String method, String path, Headers headers) {
    final mint = mintOf(method, path);
    if (mint == null) return;
    final v = headers.value('x-company-ref');
    if (v == null || !_refRe.hasMatch(v)) return;
    _refs[_k(key, mint.idx, mint.kind)] = v;
  }

  static String? lookup(String key, String idx, CompanyRefKind kind) => _refs[_k(key, idx, kind)];

  /// بعد نجاح تفعيلٍ/تمديد: عرض السعر استُهلك بالخادم.
  static void consume(String key, String method, String path) {
    final r = requireOf(method, path);
    if (r == null || r.kind == CompanyRefKind.subject) return;
    _refs.remove(_k(key, r.idx, r.kind));
  }

  static void reset() => _refs.clear();
}

/// رموز رفض الخادم للطلب الموجَّه (server/companyRouting.js CODES) — نصّه العربيّ يصل في `message` ويُعرض كما هو.
class CompanyRouteCodes {
  CompanyRouteCodes._();

  static const sessionExpired = 'COMPANY_SESSION_EXPIRED';
  static const needsLogin = 'COMPANY_NEEDS_LOGIN';
  static const disabled = 'COMPANY_ROUTE_DISABLED';
  static const writesPaused = 'COMPANY_ROUTE_WRITES_PAUSED';
  static const notAllowed = 'COMPANY_ROUTE_NOT_ALLOWED';
  static const unavailable = 'COMPANY_UNAVAILABLE';
  static const upstream = 'COMPANY_UPSTREAM_UNAVAILABLE';
  static const busy = 'COMPANY_ROUTE_BUSY';
  static const rate = 'COMPANY_ROUTE_RATE';

  /// ردٌّ موجَّه بلا صدى المفتاح — لا يُقبل (قد تكون بيانات الشركة المفتوحة لا شركة الصفّ).
  static const echo = 'COMPANY_ROUTE_ECHO';

  /// كتابةٌ لم تحدّد شركتها وقسمٌ يعرض شركةً أخرى لمسارها ([CompanyRoute.decide]) — لم تُرسل (ردٌّ محلّيّ، لم يُنفَّذ شيء).
  static const ambiguous = 'COMPANY_ROUTE_AMBIGUOUS';

  static bool isRouteCode(Object? code) => code is String && (code.startsWith('COMPANY_') || code == 'OWNER_ONLY');

  // ── «كل الصفحات» للموظّف (٩ نوفمبر): رفض حرّاس التوجيه لطلبه — نصّه العربيّ في message، ويحمل صدى المفتاح ──
  static const employeeOnly = 'EMPLOYEE_ONLY';
  static const sessionRequired = 'SESSION_REQUIRED';
  static const personDisabled = 'PERSON_DISABLED';
  static const employeeDisabled = 'EMPLOYEE_DISABLED';
  static const pageUnsupported = 'PAGE_UNSUPPORTED';
  static const employeeDeviceLimit = 'EMPLOYEE_DEVICE_LIMIT';
  static const deviceIdRequired = 'DEVICE_ID_REQUIRED';

  static const _employeeCodes = {
    employeeOnly,
    sessionRequired,
    personDisabled,
    employeeDisabled,
    pageUnsupported,
    employeeDeviceLimit,
    deviceIdRequired,
  };

  /// رفضٌ من حرّاس التوجيه لطلب الموظّف (رموز المالك + رموزه) — لا بيانات فيه تُنسب لصفحةٍ خطأ.
  static bool isEmployeeRouteCode(Object? code) => isRouteCode(code) || _employeeCodes.contains(code);
}
