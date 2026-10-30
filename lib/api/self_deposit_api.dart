import 'dart:async';
import 'history_page.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/platform/app_platform.dart';
import '../core/util/error_text.dart';
import '../services/auth_storage.dart';
import '../services/permissions_service.dart';
import '../services/provider_service.dart';
import 'api_client.dart';

/// «شحن رصيد الصفحة» — الإيداع الذاتيّ في الساس (Self Deposit).
///
/// هي شاشة الساس «ايداع مالي» وزرّها «تعبئة» (`manager/selfDeposit`): المدير
/// يضيف لرصيد صفحته مالاً من خارجها — زين كاش، أو كارت تعبئة الساس، أو كارت
/// كوشك، أو فاتورة «تسديد» تُدفع بمنفذ. ليست «شحن» المدير الفرعيّ (تحويلٌ من
/// رصيد الأب لابنه، `managers/:id/deposit`) — تلك عمليّةٌ أخرى.
///
/// ── من يقرّر ──────────────────────────────────────────────────────────
/// **الخادم وحده.** التطبيق لا يخاطب الساس ولا يعرف عنوانه
/// (`no_direct_sas_test`)، ولا يعرف الوسائل التي فعّلتها الشركة ولا صلاحيّة
/// `prm_managers_self_deposit` — يقرأ ما يقوله خادمنا:
///
///   GET  /api/v2/self-deposit/options      → الوسائل + الحالة + الرصيد
///   POST /api/v2/self-deposit/request      {method_id, amount?, pin?, name?, phone?}
///   POST /api/v2/self-deposit/complete     {psid, return_url}
///   GET  /api/v2/self-deposit/status/:psid
///
/// والميزة كلّها خلف مفتاحٍ مطفأٍ افتراضيّاً (`pro_settings`، يُفتح لكلّ مالكٍ
/// بطلبه): ما لم يقل الخادم `enabled:true` صراحةً **لا يظهر شيءٌ جديد** — لا
/// بطاقة ولا قفل. وغياب المسار (خادمٌ أقدم ⇒ ٤٠٤) كالإطفاء.
///
/// ── المال ─────────────────────────────────────────────────────────────
/// • لا «فشل» كاذب: مهلةٌ أو ٥xx بعد إرسال الطلب = «تعذّر التأكّد» لا «فشل».
///   الساس قد يردّ فشلاً وهو نفّذ (قيس على `manager/deposit` ٢٠٢٦-٠٩-١٣).
/// • لا إعادة تلقائيّة للطلب (`request`) أبداً — POST لا يُكرَّر في المعترض.
/// • زين كاش: التوكن الراجع هو الدليل الوحيد على الدفع، فيُحفظ فور التقاطه
///   ([SelfDepositPendingStore]) ويُعاد إرساله ([SelfDepositSync]) حتّى يقول
///   الخادم إنّه استلمه (`received`) أو حسمه (`final`) — والخادم يحفظ ما لا يعرفه
///   للمراجعة بدل أن يرفضه، فلا ردّ ٤xx يمحو الدليل من الجهتين.
/// • رمز الكارت (PIN) لا يُطبع في أيّ سجلّ، ولا يُحفظ.

// ═════════════════════════ أدوات القراءة ═════════════════════════

String? _str(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty || s == 'null') ? null : s;
}

num? _numOrNull(Object? v) {
  if (v == null || v is bool) return null;
  if (v is num) return v;
  return num.tryParse(v.toString().replaceAll(',', '').trim());
}

int? _intOrNull(Object? v) => _numOrNull(v)?.round();

bool? _boolOrNull(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v == 1 || v == '1' || v == 'true') return true;
  if (v == 0 || v == '0' || v == 'false') return false;
  return null;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

List<String> _strings(Object? v) {
  if (v is String) return [if (v.trim().isNotEmpty) v.trim()];
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (_str(e) != null) _str(e)!,
  ];
}

void _log(String what, Object e) {
  // ⚠️ بلا جسم الطلب ولا الردّ: فيهما رمز الكارت أو توكن زين كاش.
  if (kDebugMode) debugPrint('🔴 [SelfDeposit] $what: ${e.runtimeType}');
}

// ═════════════════════════ الوسائل ═════════════════════════

/// كيف تجري الوسيلة.
enum SelfDepositFlow {
  /// صفحة دفعٍ خارجيّة (زين كاش) تُفتح داخل التطبيق ثمّ ترجع للساس.
  redirect,

  /// رمز كارت (كارت تعبئة الساس، كوشك) — يُضاف الرصيد فوراً.
  pin,

  /// فاتورة تُدفع في منفذ («تسديد») — يُضاف الرصيد بعد التسديد.
  invoice,

  /// وسيلةٌ لا تعمل داخل التطبيق (HyperPay/Switch: سكربتات دفعٍ في
  /// المتصفّح) — تُستعمل من لوحة الشركة على المتصفّح.
  panel,
}

/// وسيلة دفعٍ فعّلتها الشركة في الساس (`paymentgateway/list/acp`) — بعد أن
/// صفّاها الخادم إلى `id` و`name` و`internal_name` وحدها.
@immutable
class SelfDepositMethod {
  const SelfDepositMethod({
    required this.id,
    required this.internalName,
    required this.flow,
    this.name,
    this.minAmount,
    this.maxAmount,
  });

  /// معرّف البوّابة في الساس — يُعاد للخادم كما وصل.
  final Object id;

  /// الاسم الداخليّ بحروفٍ صغيرة: `zaincash` · `zaincashv2` · `voucher` ·
  /// `kushok` · `tasdid` · `hyperpay` · `switch` …
  final String internalName;

  /// الاسم الذي كتبته الشركة في الساس — للعرض حين لا نعرف الوسيلة.
  final String? name;

  final SelfDepositFlow flow;

  /// حدود المبلغ إن أرسلها الخادم (الساس نفسه لا يعلنها).
  final int? minAmount;
  final int? maxAmount;

  bool get isZainCash => internalName.startsWith('zaincash');

  /// تعمل داخل التطبيق؟ (`panel` = من لوحة الشركة فقط).
  bool get inApp => flow != SelfDepositFlow.panel;

  bool get needsAmount =>
      flow == SelfDepositFlow.redirect || flow == SelfDepositFlow.invoice;
  bool get needsPin => flow == SelfDepositFlow.pin;
  bool get needsPayer => internalName == 'tasdid';

  /// الاسم بالعربيّة — الوسائل المعروفة بأسمائها، وغيرها باسم الشركة.
  String get label => switch (internalName) {
        'zaincash' || 'zaincashv2' => 'زين كاش',
        'voucher' => 'كارت تعبئة',
        'kushok' => 'كارت كوشك',
        'tasdid' => 'تسديد',
        'hyperpay' => 'هايبر باي',
        'switch' => 'سويتش',
        _ => name ?? 'وسيلة دفع',
      };

  /// سطرٌ يشرح الوسيلة تحت اسمها.
  String get hint => switch (flow) {
        SelfDepositFlow.redirect => 'ادفع من محفظتك وتُضاف للرصيد فوراً',
        SelfDepositFlow.pin => internalName == 'kushok'
            ? 'اكتب رمز كارت كوشك'
            : 'اكتب الرمز السرّيّ (PIN) لكارت الساس',
        SelfDepositFlow.invoice => 'فاتورة تسدّدها في أقرب منفذ',
        SelfDepositFlow.panel => 'من لوحة الشركة على المتصفّح',
      };

  /// الوسيلة من الاسم الداخليّ حين لا يقول الخادم `flow`.
  static SelfDepositFlow flowOf(String internalName) => switch (internalName) {
        'zaincash' || 'zaincashv2' => SelfDepositFlow.redirect,
        'voucher' || 'kushok' => SelfDepositFlow.pin,
        'tasdid' => SelfDepositFlow.invoice,
        _ => SelfDepositFlow.panel,
      };

  static SelfDepositFlow? _flowFrom(Object? v) => switch (_str(v)) {
        'redirect' => SelfDepositFlow.redirect,
        'pin' => SelfDepositFlow.pin,
        'invoice' => SelfDepositFlow.invoice,
        'panel' || 'external' => SelfDepositFlow.panel,
        _ => null,
      };

  static SelfDepositMethod? fromJson(Map<String, dynamic> j) {
    final id = j['id'] ?? j['method_id'];
    if (id == null || _str(id) == null) return null;
    final internal = (_str(j['internal_name']) ??
            _str(j['type']) ??
            _str(j['gateway']) ??
            '')
        .toLowerCase();
    var flow = _flowFrom(j['flow']) ?? flowOf(internal);
    // الخادم يقول «لا تعمل داخل التطبيق» ⇒ تُحترم، مهما كان نوعها.
    if (_boolOrNull(j['in_app']) == false) flow = SelfDepositFlow.panel;
    // وسيلة دفعٍ بتحويلٍ لا نعرفها لا تُفتح في الـWebView: التقاط الرجوع
    // مبنيٌّ على مسارات زين كاش وحدها.
    if (flow == SelfDepositFlow.redirect && !internal.startsWith('zaincash')) {
      flow = SelfDepositFlow.panel;
    }
    return SelfDepositMethod(
      id: id,
      internalName: internal,
      name: _str(j['name']),
      flow: flow,
      minAmount: _intOrNull(j['min_amount'] ?? j['min']),
      maxAmount: _intOrNull(j['max_amount'] ?? j['max']),
    );
  }
}

// ═════════════════════════ الحالة ═════════════════════════

/// لماذا لا تُفتح الميزة — كلّ سببٍ بقفله الخاصّ (لا «اطلبها من مديرك»
/// لما لا يملك أحدٌ منحه).
enum SelfDepositBlock {
  /// مفتوحة.
  none,

  /// الميزة مطفأة لهذا الحساب (أو الخادم أقدم منها) — لا تظهر أصلاً.
  disabled,

  /// موظّف: الشحن لصاحب الحساب وحده.
  ownerOnly,

  /// المزوّد لا يملك شحناً (ايرث لنك، المشروع الوطنيّ).
  provider,

  /// صفحة الساس بلا صلاحيّة «ايداع مالي» — يمنحها المدير الأعلى في الساس.
  noPermission,

  /// الشركة لم تفعّل أيّ وسيلة دفعٍ إلكترونيّ في الساس.
  noGateways,

  /// المفتاح أُغلق ولصاحب الحساب عمليّاتٌ لم تُحسم — السجلّ و«تحقّق» وحدهما،
  /// بلا عمليّاتٍ جديدة (البطاقة تبقى مفتوحة لها).
  paused,
}

/// ردّ `GET /api/v2/self-deposit/options`.
@immutable
class SelfDepositOptions {
  const SelfDepositOptions({
    required this.enabled,
    this.supported,
    this.reason,
    this.methods = const [],
    this.balance,
    this.currency,
    this.panelUrl,
    this.message,
    this.companyName,
    this.sasUsername,
    this.capture,
  });

  /// المفتاح مفتوحٌ لهذا الحساب.
  final bool enabled;

  /// `true` مدعوم · `false` غير مدعوم ([reason] يقول لماذا) · `null` تعذّرت
  /// قراءة الساس (لا يُقال «غير مدعوم» عن شيءٍ لم يُعرف).
  final bool? supported;
  final String? reason;
  final List<SelfDepositMethod> methods;

  /// رصيد الصفحة الآن من الساس — `null` = غير معروف (لا صفر).
  final num? balance;
  final String? currency;

  /// لوحة الشركة (`…/#/manager/selfDeposit`) للوسائل التي لا تعمل هنا.
  final String? panelUrl;
  final String? message;

  /// اسم الشركة في دليلنا ويوزر الصفحة في الساس — لسطر «أيّ صفحة» حين لا
  /// يعرفهما التطبيق.
  final String? companyName;
  final String? sasUsername;

  /// مسارات الرجوع إن أرسلها الخادم مع الوسائل (والمضيف يأتي مع رابط الدفع).
  final SelfDepositCapture? capture;

  static const off = SelfDepositOptions(enabled: false);

  List<SelfDepositMethod> get inAppMethods =>
      methods.where((m) => m.inApp).toList(growable: false);

  /// السبب كما يُعرض — الخادم أوّلاً، ثمّ ما نعرفه محلّيّاً (دفاعٌ ثانٍ لا
  /// يفترض أنّ الخادم لا يخطئ: الموظّف وايرث لنك مقفلان مهما قال).
  SelfDepositBlock get block {
    if (!enabled) return SelfDepositBlock.disabled;
    // المزوّد أوّلاً: ايرث لنك والمشروع الوطنيّ لا يملكان الشحن أصلاً — فموظّفهما
    // أيضاً يرى «غير متاح لدى …» (السبب الأصدق) لا «لصاحب الحساب».
    if (ProviderService.isEarthlink || ProviderService.isFtth || ProviderService.isFiberx) {
      return SelfDepositBlock.provider;
    }
    if (PermissionsService.isEmployee) return SelfDepositBlock.ownerOnly;
    switch (reason) {
      case 'provider':
        return SelfDepositBlock.provider;
      case 'employee' || 'owner_only':
        return SelfDepositBlock.ownerOnly;
      case 'paused':
        return SelfDepositBlock.paused;
      case 'no_permission' || 'permission':
        return SelfDepositBlock.noPermission;
      case 'no_gateways' || 'no_methods':
        return SelfDepositBlock.noGateways;
      case 'disabled':
        return SelfDepositBlock.disabled;
      // not_ready · read_failed: لم تُقرأ (supported:null) — ليست «غير مدعومة».
    }
    if (supported == false) return SelfDepositBlock.noGateways;
    if (supported == true && methods.isEmpty) return SelfDepositBlock.noGateways;
    return SelfDepositBlock.none;
  }

  /// نسخةٌ برصيدٍ جديد (بعد عمليّة) بلا طلب.
  SelfDepositOptions withBalance(num? b) => b == null
      ? this
      : SelfDepositOptions(
          enabled: enabled,
          supported: supported,
          reason: reason,
          methods: methods,
          balance: b,
          currency: currency,
          panelUrl: panelUrl,
          message: message,
          companyName: companyName,
          sasUsername: sasUsername,
          capture: capture,
        );

  /// العملة للعرض — الساس يكتبها `IQD` غالباً.
  String get currencyLabel {
    final c = currency?.trim() ?? '';
    if (c.isEmpty || c.toUpperCase() == 'IQD' || c.contains('دينار')) {
      return 'د.ع';
    }
    if (c.toUpperCase() == 'USD') return r'$';
    return c;
  }

  /// ردٌّ يحمل كلام الميزة فعلاً؟ — `{success:true}` بلا حقولها (الردّ الآمن
  /// الفارغ لمسارٍ لا يعرفه وسيط ايرث لنك) ليس «مفتوحاً».
  static bool _speaks(Map<String, dynamic> j) =>
      j.containsKey('enabled') ||
      j.containsKey('supported') ||
      j.containsKey('methods');

  static SelfDepositOptions fromJson(Map<String, dynamic> j) {
    if (!_speaks(j)) return off;
    final enabled = _boolOrNull(j['enabled']) ?? true;
    final rows = j['methods'];
    final methods = <SelfDepositMethod>[
      if (rows is List)
        for (final r in rows.whereType<Map>())
          if (SelfDepositMethod.fromJson(Map<String, dynamic>.from(r))
              case final m?)
            m,
    ];
    return SelfDepositOptions(
      enabled: enabled,
      supported: _boolOrNull(j['supported']),
      reason: _str(j['reason'])?.toLowerCase(),
      methods: methods,
      balance: _numOrNull(j['balance']),
      currency: _str(j['currency']),
      panelUrl: _str(j['panel_url']),
      message: _str(j['message']),
      companyName: _str(_map(j['company'])['name']),
      sasUsername: _str(_map(j['manager'])['username']),
      capture: j['capture'] == null ? null : SelfDepositCapture.fromJson(j['capture']),
    );
  }
}

// ═════════════════════════ رجوع زين كاش ═════════════════════════

/// كيف يُعرف رجوع صفحة الدفع إلى الساس — من الخادم مع رابط الدفع.
@immutable
class SelfDepositCapture {
  const SelfDepositCapture({this.hosts = const {}, this.routes = defaultRoutes});

  /// مضيفو الساس: أيّ تنقّلٍ إليهم هو الرجوع — يُلتقط ولا يُحمَّل.
  final Set<String> hosts;

  /// مسارات الرجوع (في الهاش أو المسار) — تلتقط الرجوع وإن جاء بمضيفٍ آخر
  /// للساس نفسه (عنوان IP بدل الاسم مثلاً).
  final List<String> routes;

  static const defaultRoutes = ['/zaincash/process', '/zaincashv2/process'];

  static String? _hostOf(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return null;
    final u = Uri.tryParse(s.contains('://') ? s : 'https://$s');
    final h = u?.host ?? '';
    return h.isEmpty ? null : (h.endsWith('.') ? h.substring(0, h.length - 1) : h);
  }

  static String _route(String r) {
    var s = r.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (!s.startsWith('/')) s = '/$s';
    return s.toLowerCase();
  }

  static SelfDepositCapture fromJson(Object? raw) {
    final j = _map(raw);
    final hosts = <String>{
      for (final k in const ['host', 'sas_host', 'hosts', 'origin', 'origins'])
        for (final v in _strings(j[k]))
          if (_hostOf(v) case final h?) h,
    };
    final routes = <String>{
      for (final r in defaultRoutes) r,
      for (final r in _strings(j['routes'])) _route(r),
    }.toList(growable: false);
    return SelfDepositCapture(hosts: hosts, routes: routes);
  }
}

// ═════════════════════════ النتائج ═════════════════════════

/// حال عمليّةٍ كما يعرفها الخادم (آلة الحالات في `pro_self_deposits`).
enum SelfDepositStatus {
  /// أُضيف الرصيد.
  success,

  /// رُفضت (كارتٌ غير صحيح، دفعٌ لم يكتمل…).
  failed,

  /// بانتظار الدفع أو تأكيده (`pending` · `processing`).
  pending,

  /// الساس ينتظر تأكيد زين كاش (`awaiting_webhook`).
  awaiting,

  /// الساس ردّ ردّاً لا يُحسم — قد تكون نُفّذت.
  unverified,

  /// انتهت مهلة العمليّة بلا رجوع.
  expired,

  /// فاتورة «تسديد» أُنشئت.
  invoice,
}

SelfDepositStatus _statusFrom(Object? v) => switch (_str(v)?.toLowerCase()) {
      'success' || 'processed' || 'done' || 'credited' || 'ok' =>
        SelfDepositStatus.success,
      'failed' || 'rejected' || 'cancelled' || 'canceled' || 'declined' =>
        SelfDepositStatus.failed,
      'expired' => SelfDepositStatus.expired,
      'awaiting_webhook' || 'waiting_webhook' || 'awaiting' =>
        SelfDepositStatus.awaiting,
      'unverified' => SelfDepositStatus.unverified,
      'invoice' || 'invoiced' => SelfDepositStatus.invoice,
      // pending · processing · requested · redirected — وكلّ ما لا نعرفه:
      // لا يُحكم بفشلٍ على ما لم يُعرف.
      _ => SelfDepositStatus.pending,
    };

/// نتيجة عمليّة — بعد الكارت أو الفاتورة أو تأكيد زين كاش أو الاستعلام.
@immutable
class SelfDepositOutcome {
  const SelfDepositOutcome({
    required this.status,
    this.credited,
    this.amount,
    this.balance,
    this.message,
    this.code,
    this.ref,
    this.psid,
    this.offline = false,
    this.serverFinal,
    this.received,
  });

  final SelfDepositStatus status;

  /// ما أُضيف فعلاً (من فرق الرصيد عند الخادم) — `null` = غير معروف.
  final num? credited;

  /// المبلغ المطلوب (زين كاش/الفاتورة).
  final num? amount;

  /// الرصيد بعد العمليّة — `null` = غير معروف.
  final num? balance;
  final String? message;
  final String? code;

  /// رقم العمليّة للمراجعة مع الشركة (رقم حركة زين كاش `pay_ref`).
  final String? ref;
  final String? psid;

  /// لم يصل حكمٌ من الخادم (شبكة/مهلة/مشغولٌ مؤقّتاً) — والتوكن (إن وُجد)
  /// باقٍ في [SelfDepositPendingStore] ليُعاد.
  final bool offline;

  /// `final` كما قاله الخادم مع صفّ العمليّة — `null` = ردٌّ بلا صفّ.
  final bool? serverFinal;

  /// `received` من الخادم: استلم رجوع زين كاش وصار هو حامل الدليل (حسمه، أو
  /// يراجعه، أو ينتظر إشعار الشركة) — فلا حاجة لنسخة الهاتف.
  final bool? received;

  /// حكمٌ نهائيّ يُغلق العمليّة. الخادم أوّلاً (`final`)، وإلّا ما نعرفه:
  /// نجح/رُفض/فاتورة. «انتهت المهلة» ليست نهائيّة — «تحقّق» يراجع سجلّ الشركة.
  bool get isFinal {
    if (offline) return false;
    final f = serverFinal;
    if (f != null) return f;
    return status == SelfDepositStatus.success ||
        status == SelfDepositStatus.failed ||
        status == SelfDepositStatus.invoice;
  }

  /// تُمحى نسخة رابط الرجوع من الهاتف: حكمٌ نهائيّ، أو الخادم استلمه.
  /// ⚠️ لا تُمحى بردٍّ بلا صفّ (٤٠٤ · ٤٠٠ · ٤١٠ من خادمٍ أقدم) ولا بانقطاع.
  bool get settled => !offline && (isFinal || received == true);

  /// يستحقّ زرّ «تحقّق الآن».
  bool get checkable =>
      !isFinal &&
      (offline ||
          status == SelfDepositStatus.pending ||
          status == SelfDepositStatus.awaiting ||
          status == SelfDepositStatus.unverified ||
          status == SelfDepositStatus.expired);

  static SelfDepositOutcome fromJson(Map<String, dynamic> j,
      {SelfDepositStatus? fallback, String? psid, bool offline = false}) {
    final code = _str(j['code']);
    final raw = j['status'];
    SelfDepositStatus status;
    if (raw != null) {
      status = _statusFrom(raw);
    } else if (code == 'UNVERIFIED') {
      status = SelfDepositStatus.unverified;
    } else if (fallback != null) {
      status = fallback;
    } else {
      status = j['success'] == true
          ? SelfDepositStatus.success
          : SelfDepositStatus.failed;
    }
    return SelfDepositOutcome(
      status: status,
      credited: _numOrNull(j['credited']),
      amount: _numOrNull(j['amount']),
      balance: _numOrNull(j['balance'] ?? j['balance_after']),
      message: _str(j['message']),
      code: code,
      ref: _str(j['pay_ref'] ?? j['ref']),
      psid: _str(j['psid']) ?? psid,
      offline: offline,
      serverFinal: _boolOrNull(j['final']),
      received: _boolOrNull(j['received']),
    );
  }
}

/// بداية العمليّة — ردّ `request`.
@immutable
class SelfDepositStart {
  const SelfDepositStart._({
    this.psid,
    this.payUrl,
    this.capture,
    this.outcome,
    this.message,
    this.code,
    this.notSent = false,
  });

  /// زين كاش: افتح [payUrl] داخل التطبيق والتقط الرجوع بـ[capture].
  const SelfDepositStart.redirect({
    required String psid,
    required Uri payUrl,
    required SelfDepositCapture capture,
  }) : this._(psid: psid, payUrl: payUrl, capture: capture);

  /// نتيجةُ عمليّةٍ بدأت (كارت، فاتورة، أو حكمٌ من الخادم عليها).
  const SelfDepositStart.done(SelfDepositOutcome outcome)
      : this._(outcome: outcome);

  /// رفضٌ قبل أن يبدأ شيء (حقلٌ ناقص، حدّ المحاولات، الطلب لم يُرسل).
  const SelfDepositStart.rejected(String message,
      {String? code, bool notSent = false})
      : this._(message: message, code: code, notSent: notSent);

  final String? psid;
  final Uri? payUrl;
  final SelfDepositCapture? capture;
  final SelfDepositOutcome? outcome;
  final String? message;
  final String? code;

  /// لم يصل الطلب للخادم أصلاً (لا اتّصال) — إعادته آمنة.
  final bool notSent;

  bool get isRedirect => payUrl != null && psid != null;
}

/// عمليّةٌ في سجلّ الشحن (`GET /history`).
@immutable
class SelfDepositRecord {
  const SelfDepositRecord({
    required this.psid,
    required this.outcome,
    required this.flow,
    this.gateway = '',
    this.gatewayName,
    this.createdAt,
  });

  final String psid;
  final SelfDepositOutcome outcome;
  final SelfDepositFlow flow;

  /// الاسم الداخليّ (`zaincash` · `voucher` …).
  final String gateway;
  final String? gatewayName;
  final DateTime? createdAt;

  static SelfDepositRecord? fromJson(Map<String, dynamic> j) {
    final psid = _str(j['psid']);
    if (psid == null) return null;
    final gateway = (_str(j['gateway']) ?? '').toLowerCase();
    final flow = switch (_str(j['flow'])) {
      'redirect' => SelfDepositFlow.redirect,
      'pin' => SelfDepositFlow.pin,
      'invoice' => SelfDepositFlow.invoice,
      _ => SelfDepositMethod.flowOf(gateway),
    };
    final at = DateTime.tryParse(_str(j['created_at']) ?? '');
    return SelfDepositRecord(
      psid: psid,
      outcome: SelfDepositOutcome.fromJson(j,
          fallback: SelfDepositStatus.pending, psid: psid),
      flow: flow,
      gateway: gateway,
      gatewayName: _str(j['gateway_name']),
      createdAt: at?.toLocal(),
    );
  }

  /// اسم الوسيلة بالعربيّة كما في بلاطاتها.
  String get label => SelfDepositMethod(
        id: psid,
        internalName: gateway,
        flow: flow,
        name: gatewayName,
      ).label;
}

// ═════════════════════════ الطلبات ═════════════════════════

class SelfDepositApi {
  SelfDepositApi._();

  static const _base = '/api/v2/self-deposit';

  /// طلبات المال (request · complete · status?check=1) أطول من مهلة العميل
  /// العامّة (٣٠ث): الخادم قد يقرأ الحساب ثمّ ينتظر الساس ٣٠ث ثمّ يتحقّق من
  /// الرصيد — فمهلةٌ أقصر تجعل نتيجةً كانت ستصل «غير محسومة».
  static Options get _money =>
      Options(receiveTimeout: const Duration(seconds: 90));

  /// رموزٌ تقول «لم يُحسم بعد، أعد لاحقاً» — لا حكمٌ على العمليّة. (الدفع
  /// محفوظٌ عند الخادم، والتوكن يبقى على الهاتف ليُعاد.)
  static const _retryLater = {
    'IN_PROGRESS',
    'NOT_READY',
    'SAS_UNREACHABLE',
    'SAS_SESSION_EXPIRED',
    'IDENTITY_UNKNOWN',
    'IDENTITY_MISMATCH',
  };

  /// الطلب لم يغادر الهاتف (لا اتّصال) — لا شيء نُفِّذ.
  static bool _notSent(Object e) =>
      e is DioException &&
      (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout);

  /// ردٌّ من **خادمنا** (JSON بكلامه) داخل استثناء ٥xx — حكمٌ يُقرأ لا عطلٌ.
  /// صفحة HTML من الوسيط (٥٠٢ Cloudflare) ليست كذلك.
  static (int, Map<String, dynamic>)? _ourReply(Object e) {
    if (e is! DioException) return null;
    final r = e.response;
    final data = r?.data;
    if (r == null || data is! Map) return null;
    final body = Map<String, dynamic>.from(data);
    if (!body.containsKey('success')) return null;
    return (r.statusCode ?? 0, body);
  }

  /// GET options — `null` = تعذّر الوصول (الشبكة)، و[SelfDepositOptions.off]
  /// = الميزة غير موجودة/مطفأة لهذا الحساب. [probe] = «مفعّلة لحسابي؟» وحدها
  /// بلا أيّ نداءٍ للساس (لبطاقة «قوائم أخرى»).
  static Future<({SelfDepositOptions? data, String? message, int? status})>
      options({bool probe = false}) async {
    // بلا جلسة لا سؤال (وهي حال الاختبارات بلا خزنة).
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) {
      return (data: null, message: null, status: null);
    }
    try {
      final r = await ApiClient.dio.get<Object?>(
        '$_base/options',
        queryParameters: probe ? const {'probe': 1} : null,
      );
      return _optionsFrom(r.statusCode ?? 0, _map(r.data));
    } catch (e) {
      _log('options', e);
      final ours = _ourReply(e);
      if (ours != null) return _optionsFrom(ours.$1, ours.$2);
      return (
        data: null,
        message: humanError(e, fallback: 'تعذّر جلب وسائل الدفع'),
        status: null,
      );
    }
  }

  static ({SelfDepositOptions? data, String? message, int? status})
      _optionsFrom(int code, Map<String, dynamic> body) {
    // ٤٠٤ (خادمٌ أقدم بلا المسار) · ٤٠٣ بلا كلام الميزة (موظّف ايرث لنك:
    // OWNER_ONLY ولا نعرف مفتاح مديره) ⇒ لا شيء يظهر.
    if (code == 404 || code == 501) {
      return (data: SelfDepositOptions.off, message: null, status: code);
    }
    if (code == 403 && !SelfDepositOptions._speaks(body)) {
      return (data: SelfDepositOptions.off, message: null, status: code);
    }
    if (code >= 400 && !SelfDepositOptions._speaks(body)) {
      return (
        data: null,
        message: _str(body['message']) ?? 'تعذّر جلب وسائل الدفع',
        status: code,
      );
    }
    return (data: SelfDepositOptions.fromJson(body), message: null, status: code);
  }

  /// POST request — يبدأ العمليّة. **لا يُعاد تلقائيّاً أبداً.**
  static Future<SelfDepositStart> request({
    required SelfDepositMethod method,
    int? amount,
    String? pin,
    String? name,
    String? phone,
  }) async {
    try {
      final r = await ApiClient.dio.post<Object?>(
        '$_base/request',
        options: _money,
        data: {
          'method_id': method.id,
          if (method.needsAmount && amount != null) 'amount': amount,
          if (method.needsPin && pin != null) 'pin': pin,
          if (method.needsPayer && name != null) 'name': name,
          if (method.needsPayer && phone != null) 'phone': phone,
          // زين كاش يكتمل من التطبيق وحده (الويب لا يلتقط الرجوع) — صريحاً
          // لا من ترويسة الجهاز وحدها.
          'client': 'app',
        },
      );
      return _startFrom(r.statusCode ?? 0, _map(r.data));
    } catch (e) {
      _log('request', e);
      final ours = _ourReply(e);
      if (ours != null) return _startFrom(ours.$1, ours.$2);
      if (_notSent(e)) {
        return SelfDepositStart.rejected(
          humanError(e, fallback: 'تعذّر الاتّصال بالخادم'),
          notSent: true,
        );
      }
      // وصل الطلب ولم يصل الحكم: لا «فشل» — قد يكون الساس نفّذ.
      return const SelfDepositStart.done(SelfDepositOutcome(
        status: SelfDepositStatus.unverified,
        offline: true,
      ));
    }
  }

  static SelfDepositStart _startFrom(int code, Map<String, dynamic> body) {
    if (body['success'] != true) {
      // رفضٌ **لعمليّةٍ بدأت** (لها صفّ: كارتٌ خاطئ، رفض الشركة، تعذّر التأكّد…)
      // ⇒ نتيجتها. ورفضٌ قبل أن تبدأ (حقلٌ ناقص، مشغول، حدّ المحاولات) ⇒ رسالة.
      if (body.containsKey('status') || _str(body['code']) == 'UNVERIFIED') {
        return SelfDepositStart.done(SelfDepositOutcome.fromJson(body,
            fallback: SelfDepositStatus.failed));
      }
      return SelfDepositStart.rejected(
        _str(body['message']) ?? _rejectedText(code),
        code: _str(body['code']),
      );
    }
    final flow = _str(body['flow'])?.toLowerCase();
    if (flow == 'redirect' || (flow == null && _str(body['pay_url']) != null)) {
      final psid = _str(body['psid']);
      final pay = Uri.tryParse(_str(body['pay_url']) ?? '');
      // رابط دفعٍ غير مشفَّر أو بلا معرّف عمليّة: لا يُفتح — لا التقاط بلا psid.
      if (psid == null || pay == null || pay.scheme != 'https' || pay.host.isEmpty) {
        return const SelfDepositStart.rejected(
            'تعذّر فتح صفحة الدفع — أعد المحاولة');
      }
      return SelfDepositStart.redirect(
        psid: psid,
        payUrl: pay,
        capture: SelfDepositCapture.fromJson(body['capture']),
      );
    }
    if (flow == 'invoice') {
      return SelfDepositStart.done(SelfDepositOutcome.fromJson(body,
          fallback: SelfDepositStatus.invoice));
    }
    return SelfDepositStart.done(SelfDepositOutcome.fromJson(body,
        fallback: SelfDepositStatus.success));
  }

  /// POST complete — يسلّم رابط الرجوع (وفيه التوكن) للخادم ليُتمّ الإيداع.
  /// آمنٌ للتكرار: الخادم يمنع التوكن نفسه مرّتين (sha256 فريد).
  static Future<SelfDepositOutcome> complete({
    required String psid,
    required String returnUrl,
  }) async {
    try {
      final r = await ApiClient.dio.post<Object?>(
        '$_base/complete',
        options: _money,
        data: {'psid': psid, 'return_url': returnUrl, 'client': 'app'},
      );
      return _verdict(r.statusCode ?? 0, _map(r.data), psid);
    } catch (e) {
      _log('complete', e);
      final ours = _ourReply(e);
      if (ours != null) return _verdict(ours.$1, ours.$2, psid);
      return SelfDepositOutcome(
          status: SelfDepositStatus.pending, psid: psid, offline: true);
    }
  }

  /// GET status/:psid?check=1 — حال عمليّةٍ لم يصل رجوعها (أُغلقت الصفحة، أو
  /// الساس ينتظر تأكيد زين كاش)، ويراجع الخادم سجلّ حركات الدفع في الساس.
  static Future<SelfDepositOutcome> status(String psid) async {
    try {
      final r = await ApiClient.dio.get<Object?>(
        '$_base/status/${Uri.encodeComponent(psid)}',
        queryParameters: const {'check': 1},
        options: _money,
      );
      return _verdict(r.statusCode ?? 0, _map(r.data), psid);
    } catch (e) {
      _log('status', e);
      final ours = _ourReply(e);
      if (ours != null) return _verdict(ours.$1, ours.$2, psid);
      return SelfDepositOutcome(
          status: SelfDepositStatus.pending, psid: psid, offline: true);
    }
  }

  /// GET history — آخر عمليّات الشحن للحساب. `null` = تعذّرت القراءة.
  static Future<List<SelfDepositRecord>?> history({int limit = 10}) async =>
      (await historyPage(limit: limit))?.rows;

  /// GET history بصفحات: `before` = psid آخر صفٍّ معروض (ما قبله)، `query` = رقم العمليّة (الخادم 824b597).
  /// `null` = تعذّرت القراءة.
  static Future<HistoryPage<SelfDepositRecord>?> historyPage({
    int limit = 10,
    String? before,
    String? query,
  }) async {
    try {
      final r = await ApiClient.dio.get<Object?>(
        '$_base/history',
        queryParameters: {
          'limit': limit,
          if (before != null) 'before': before,
          if (query != null) 'q': query,
        },
      );
      final body = _map(r.data);
      if (body['success'] != true) return null;
      final items = body['items'];
      return HistoryPage(
        [
          if (items is List)
            for (final e in items.whereType<Map>())
              if (SelfDepositRecord.fromJson(Map<String, dynamic>.from(e))
                  case final rec?)
                rec,
        ],
        hasMore: body['has_more'] == true,
      );
    } catch (e) {
      _log('history', e);
      return null;
    }
  }

  static SelfDepositOutcome _verdict(
      int code, Map<String, dynamic> body, String psid) {
    final serverCode = _str(body['code']);
    // مشغولٌ، أو الشركة لا تُجيب، أو الجلسة: لم يُحكم بعد — يبقى ويُعاد.
    if (_retryLater.contains(serverCode) ||
        code == 429 ||
        code == 401 ||
        code == 408 ||
        (code >= 500 && !body.containsKey('status'))) {
      return SelfDepositOutcome(
        status: SelfDepositStatus.pending,
        message: _str(body['message']),
        code: serverCode,
        psid: psid,
        offline: true,
      );
    }
    // ردٌّ بصفّ العمليّة: حاله وfinal/received منه (الخادم يحفظ ما لا يعرفه
    // للمراجعة ويقول received — فلا رفضٌ مجرّد لرجوعٍ وصله).
    if (body.containsKey('status')) {
      return SelfDepositOutcome.fromJson(body,
          fallback: SelfDepositStatus.pending, psid: psid);
    }
    if (code == 409 && serverCode == 'UNVERIFIED') {
      return SelfDepositOutcome.fromJson(body,
          fallback: SelfDepositStatus.unverified, psid: psid);
    }
    if (body['success'] == true) {
      return SelfDepositOutcome.fromJson(body,
          fallback: SelfDepositStatus.pending, psid: psid);
    }
    // 🚨 رفضٌ **بلا صفّ** (٤٠٤ «غير موجودة»، ٤٠٠ رابطٌ بلا رمز، ٤١٠ من خادمٍ
    // أقدم…): ليس حكماً على المال ولا إقراراً بالاستلام — «تعذّر التأكّد»، ولا
    // يُمحى رابط الرجوع المحفوظ (settled = false).
    return SelfDepositOutcome(
      status: SelfDepositStatus.unverified,
      message: _str(body['message']),
      code: serverCode ?? (code == 404 ? 'NOT_FOUND' : null),
      psid: psid,
    );
  }

  static String _rejectedText(int code) => switch (code) {
        429 => 'محاولاتٌ كثيرة — انتظر قليلاً ثمّ أعد المحاولة',
        403 => 'لا تملك صلاحيّة هذه العمليّة',
        _ => 'تعذّر بدء العمليّة',
      };
}

// ═════════════════════════ حال الجلسة ═════════════════════════

/// ما يُرسم في «قوائم أخرى» — آخر ردّ options في هذه الجلسة.
///
/// الجلب **كسول**: يبدأ حين يستمع أحدٌ للحالة ([gate] — بطاقة «قوائم أخرى»)
/// وكانت قديمة، فلا طلب لمن لا يفتح القائمة. وهو `probe` (بلا نداءٍ للساس):
/// «مفعّلة لحسابي؟» وحدها. وبلا جلسة لا طلب أبداً. والفشل لا يمسح ما نعرفه،
/// ولا يُظهر ما لم يقل الخادم إنّه مفتوح.
class SelfDepositState {
  SelfDepositState._();

  static final ValueNotifier<SelfDepositOptions?> gate = _LazyGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;
  static bool _unsupported = false;

  static const ttl = Duration(minutes: 5);
  static const _cooldown = Duration(seconds: 30);

  /// يضبطهما [SelfDepositSync.install] (بلا استيرادٍ دائريّ): الاستماع للبطاقة
  /// فرصةٌ أخرى لتسليم روابط رجوعٍ معلّقة، ومسح الجلسة يوقف إعاداتها.
  static VoidCallback? onListen;
  static VoidCallback? onReset;

  /// تُؤخذ قبل الطلب: ردٌّ يصل بعد تبديل الجلسة لا يُكتب.
  static int get epoch => _epoch;

  /// البطاقة تُعرض؟ (مفتوحةً أو مقفلةً بسببها) — `false` ما لم يقل الخادم
  /// `enabled` صراحةً.
  ///
  /// ويندوز: مخفيّة — صفحة الدفع تحتاج WebView يلتقط رابط الرجوع قبل تحميله، ولا WebView
  /// معتمدٌ لويندوز بعد (windows-app-plan). الشحن من الهاتف كما هو.
  static bool get visible => !AppPlatform.isDesktop && (gate.value?.enabled ?? false);

  /// يجلب الحالة إن كانت قديمة. طلبٌ واحدٌ جارٍ على الأكثر، وبعد الفشل تبريد.
  static Future<void> ensureFresh({bool force = false}) {
    if (AppPlatform.isDesktop) return Future<void>.value();
    final running = _inflight;
    if (running != null) return running;
    if (!force) {
      if (_unsupported) return Future<void>.value();
      final now = DateTime.now();
      final at = _fetchedAt;
      if (at != null && now.difference(at) < ttl) return Future<void>.value();
      final failed = _failedAt;
      if (failed != null && now.difference(failed) < _cooldown) {
        return Future<void>.value();
      }
    }
    final epoch = _epoch;
    late final Future<void> run;
    run = SelfDepositApi.options(probe: true).then((r) {
      if (epoch != _epoch) return;
      final data = r.data;
      if (data == null) {
        if (r.status != null || r.message != null) _failedAt = DateTime.now();
        return;
      }
      apply(data, epoch: epoch, probe: true);
      if (r.status == 404) _unsupported = true;
    }).whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  /// ردٌّ حيّ (من الشاشة أو من [ensureFresh]).
  ///
  /// [probe] يقول «مفعّلة» وحدها: لا يمحو تفاصيل قرأتها الشاشة في الجلسة نفسها
  /// (صفحةٌ بلا صلاحيّة، شركةٌ بلا وسائل) — فتبقى البطاقة مقفلةً بسببها.
  static void apply(SelfDepositOptions o, {int? epoch, bool probe = false}) {
    if (epoch != null && epoch != _epoch) return;
    _fetchedAt = DateTime.now();
    _failedAt = null;
    final cur = gate.value;
    if (probe &&
        o.enabled &&
        cur != null &&
        cur.enabled &&
        (cur.supported != null || cur.reason != null)) {
      return;
    }
    gate.value = o;
  }

  /// رصيدٌ جديد بعد عمليّة — يُحدَّث في الحالة بلا طلب.
  static void noteBalance(num? balance) {
    final o = gate.value;
    if (o == null || balance == null) return;
    gate.value = o.withBalance(balance);
  }

  /// من [SessionManager.clearAllSessionData] — لا يرى المدير التالي حال سابقه.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    _unsupported = false;
    gate.value = null;
    onReset?.call();
  }

  @visibleForTesting
  static void debugSet(SelfDepositOptions? o) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _unsupported = false;
    _fetchedAt = o == null ? null : DateTime.now();
    gate.value = o;
  }
}

/// حالةٌ تطلب نفسها حين يُستمع إليها — فبطاقة «قوائم أخرى» تجلب ما تحتاجه
/// بلا سطرٍ في شاشةٍ لا تملك حالة.
class _LazyGate extends ValueNotifier<SelfDepositOptions?> {
  _LazyGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجلب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(() {
      SelfDepositState.ensureFresh();
      SelfDepositState.onListen?.call();
    });
  }
}
