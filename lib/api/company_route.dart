import 'dart:async';

import 'package:dio/dio.dart';

/// «كل الشركات» في التطبيق (٢١ أكتوبر، المالك: «ابدي بيها خل نكملها» — تصميمنا لا كودكس).
///
/// نداءٌ يخصّ شركةً من شركات حساب Pro يمرّ بخادمنا **بتوكن الحساب وحده** + `x-company-key`، فيأخذ الخادم جلسة تلك الشركة
/// المخزّنة عنده ويبدّلها على الطلب نفسه (server/companyRouting.js) — لا دخول ولا خروج، ولا توكن شركةٍ يصل الهاتف أبداً.
/// هذا الملفّ: أيّ طلبٍ لأيّ شركة (النطاق)، ومراجع النوافذ (`x-company-ref`)، ونصوص الأخطاء. المعترض في api_client.dart.
class CompanyRoute {
  CompanyRoute._();

  static const Symbol _zoneKey = #companyRouteKey;

  /// مفتاح الشركة: c + 12 hex (= accountOverview.companyKey بالخادم — مُحدِّدٌ لا إثبات).
  static final RegExp keyRe = RegExp(r'^c[0-9a-f]{12}$');

  /// يشغّل [body] — وكلّ نداء ApiClient يطلقه ولو بعد await — موجَّهاً للشركة [key]. key null ⇒ كما هو (الوضع العاديّ).
  /// النداءات التي تبدأ من زرٍّ لاحقاً تخرج من النطاق: كلّ نداءٍ يخصّ مشتركاً مدموجاً يُغلَّف بمفتاح صفّه.
  static Future<T> run<T>(String? key, Future<T> Function() body) {
    if (key == null || !keyRe.hasMatch(key)) return body();
    return runZoned(body, zoneValues: {_zoneKey: key});
  }

  /// مفتاح النطاق الحاليّ (null خارج أيّ نطاق).
  static String? get currentKey {
    final z = Zone.current[_zoneKey];
    return z is String && keyRe.hasMatch(z) ? z : null;
  }

  /// بعد كلّ كتابةٍ موجَّهة وصلت الخادم — أيّاً كان ردّها — تُسقط قائمة شركتها فتُجلب من جديد (كبطاقتها في «لوحة حسابي»).
  static void Function(String key)? onWrite;

  /// مفتاح شركة الطلب: `extra['companyKey']` صراحةً أوّلاً، ثمّ النطاق.
  static String? keyFor(RequestOptions o) {
    final x = o.extra['companyKey'];
    if (x is String && keyRe.hasMatch(x)) return x;
    return currentKey;
  }
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

  /// كتابةٌ يطلب الخادم لها مرجعاً — (idx، النوع) أو null.
  static ({String idx, CompanyRefKind kind})? requireOf(String method, String path) {
    final m = method.toUpperCase();
    if (m == 'GET') return null;
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

  static bool isRouteCode(Object? code) => code is String && (code.startsWith('COMPANY_') || code == 'OWNER_ONLY');
}
