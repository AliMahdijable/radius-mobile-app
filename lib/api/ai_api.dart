import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';

import '../core/platform/store_policy.dart';
import '../core/util/error_text.dart';
import '../services/account_service.dart';
import '../services/auth_storage.dart';
import '../services/device_id.dart';
import 'api_client.dart';

/// المساعد الذكيّ — المرحلة ١: «اشرحلي» عند الخطأ و«كيف أسوّي؟».
///
///   GET  /api/v2/ai/status
///   POST /api/v2/ai/explain   {code?, message?, screen, http_status?, context?, lang}
///   POST /api/v2/ai/ask       {question, history?, screen?, lang}
///
/// ── من يقرّر ──────────────────────────────────────────────────────────
/// **الخادم وحده يكلّم النموذج** — لا مفتاح في التطبيق، ولا أداة ولا عمليّة:
/// أجوبةٌ فقط. والميزة **مطفأة ومخفيّة افتراضيّاً**: ما لم يقل الخادم
/// `enabled:true` صراحةً لا يظهر شيء — لا زرّ «اشرحلي» ولا بطاقة. وغياب
/// المسار (خادمٌ أقدم ⇒ ٤٠٤) كالإطفاء. الحصّة اليوميّة والصلاحيّة والباقة
/// كلّها من الخادم؛ التطبيق يعرض ما يقوله.
///
/// ── الجلسة ────────────────────────────────────────────────────────────
/// • جلسة شركة (توكن الساس/الموظّف) ⇒ `ApiClient.dio` كأيّ نداء.
/// • حساب Pro وحده (الدخول، «شركاتي») ⇒ «اشرحلي» وحده، بتوكن الحساب في
///   `x-account-token` على عميلٍ مستقلّ — فخطؤه لا يمسّ جلسة الساس أبداً.
///
/// ── الخصوصيّة ─────────────────────────────────────────────────────────
/// الخادم يمرّر النصّ لمزوّد ذكاءٍ اصطناعيّ خارجيّ (Anthropic) — فلا طلب قبل
/// موافقة المدير مرّةً على الجهاز (`AiConsent`، App Store 5.1.2(i)). يُرسَل نصّ
/// الخطأ **كما ظهر** وسؤال المدير كما كتبه، بعد إخفاء الهواتف والأرقام الطويلة
/// والتوكنات وقيم كلمات السرّ ورموز الكارت ([AiText.maskForSend]) — والخادم
/// يخفيها ثانيةً ومعها الأسماء واليوزرات **بأفضل جهدٍ لا ضمان** (اسمٌ بلا علامة
/// قد يمرّ) — فالموافقة تقول ذلك. المحادثة على الهاتف في الذاكرة وحدها وتُمحى
/// بإغلاق النافذة؛ والخادم يحفظ النسخة المخفيّة المرسَلة مع الجواب ٢٤ ساعة (حتى
/// ٣٠ يوماً لما لم يُحلّ أو أُبلغ أنّه غلط أو وجد فيه الفحص الآليّ مشكلة) ثمّ
/// يحذفها، ولا يراها إلّا فريقنا (سياسة الخصوصيّة، البند ٣).

// ═════════════════════════ أدوات القراءة ═════════════════════════

String? _str(Object? v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};

List<String> _strings(Object? v, {int max = 8, int maxLen = 400}) {
  if (v is! List) return const [];
  final out = <String>[];
  for (final e in v) {
    final s = _str(e);
    if (s == null) continue;
    out.add(s.length > maxLen ? s.substring(0, maxLen) : s);
    if (out.length >= max) break;
  }
  return out;
}

void _log(String what, Object e) {
  // ⚠️ بلا جسم الطلب ولا الردّ: فيهما نصّ الخطأ وسؤال المدير.
  if (kDebugMode) debugPrint('🔴 [AI] $what: ${e.runtimeType}');
}

/// نصٌّ محلّيّ بلغة الواجهة — والعربيّ إن لم تُحمَّل الترجمة (اختبار وحدة).
String _t(String key, String ar) => key.trExists() ? key.tr() : ar;

// ═════════════════════════ النماذج ═════════════════════════

/// أيّ جلسةٍ يُسأل بها الخادم.
enum AiMode {
  /// لا جلسة شركة ولا حساب — لا سؤال أصلاً.
  none,

  /// جلسة شركة (مالك أو موظّف).
  company,

  /// حساب Pro وحده (قبل الدخول لشركة) — «اشرحلي» وحده.
  account,
}

/// الحصّة اليوميّة كما يقولها الخادم.
@immutable
class AiQuota {
  const AiQuota({this.left, this.limit, this.scope, this.resetsAt});

  final int? left;
  final int? limit;

  /// `account` · `employee`.
  final String? scope;
  final DateTime? resetsAt;

  static AiQuota? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final left = _int(j['left']);
    final limit = _int(j['limit']);
    if (left == null && limit == null) return null;
    return AiQuota(
      left: left == null ? null : (left < 0 ? 0 : left),
      limit: limit,
      scope: _str(j['scope']),
      resetsAt: DateTime.tryParse(_str(j['resets_at']) ?? ''),
    );
  }

  bool get exhausted => left != null && left! <= 0;
}

/// `GET /api/v2/ai/status` — هل تظهر الميزة، ومقفلةٌ أم مفتوحة.
@immutable
class AiStatus {
  const AiStatus({
    required this.enabled,
    this.canUse,
    this.explain = false,
    this.ask = false,
    this.quota,
    this.planLabel,
    this.upgradeHint,
    this.suggestions = const [],
    this.slogan,
    this.disclaimer,
    this.reason,
    this.lockedText,
    this.mode = AiMode.none,
  });

  /// المطفأ — والافتراضيّ لكلّ ما لا يقوله الخادم صراحةً.
  static const off = AiStatus(enabled: false);

  final bool enabled;

  /// `true` مفتوحة · `false` مقفلة (موظّفٌ بلا الصلاحيّة) · `null` لم يقل.
  final bool? canUse;
  final bool explain;
  final bool ask;
  final AiQuota? quota;
  final String? planLabel;

  /// دعوة الترقية — `null` دائماً على آيفون وللموظّف (والتطبيق لا يعرضها
  /// على آيفون مهما وصل: [StorePolicy.hidePurchaseFlows]).
  final String? upgradeHint;
  final List<String> suggestions;
  final String? slogan;
  final String? disclaimer;
  final String? reason;
  final String? lockedText;
  final AiMode mode;

  bool get usable => enabled && canUse == true;

  /// مقفلةٌ بمكانها (قاعدة «مقفل لا مخفيّ» للموظّف).
  bool get locked => enabled && canUse == false;

  bool get canExplain => usable && explain;

  /// «كيف أسوّي؟» لجلسة الشركة وحدها.
  bool get canAsk => usable && ask && mode == AiMode.company;

  static AiStatus fromJson(Map<String, dynamic> j,
      {AiMode mode = AiMode.none}) {
    if (j['success'] == false || j['enabled'] != true) {
      return AiStatus(enabled: false, mode: mode);
    }
    final cu = j['can_use'];
    final plan = j['plan'];
    return AiStatus(
      enabled: true,
      canUse: cu is bool ? cu : null,
      explain: j['explain'] == true,
      ask: j['ask'] == true,
      quota: AiQuota.fromJson(j['quota']),
      planLabel: plan is Map ? _str(plan['label']) : null,
      upgradeHint: _str(j['upgrade_hint']),
      suggestions: _strings(j['suggestions'], max: 6, maxLen: 120),
      slogan: _str(j['slogan']),
      disclaimer: _str(j['disclaimer']),
      reason: _str(j['reason']),
      lockedText: _str(j['locked_text']),
      mode: mode,
    );
  }

  AiStatus withQuota(AiQuota q) => AiStatus(
        enabled: enabled,
        canUse: canUse,
        explain: explain,
        ask: ask,
        quota: q,
        planLabel: planLabel,
        upgradeHint: upgradeHint,
        suggestions: suggestions,
        slogan: slogan,
        disclaimer: disclaimer,
        reason: reason,
        lockedText: lockedText,
        mode: mode,
      );
}

/// حال الجواب كما صنّفه المساعد.
enum AiAnswerStatus { answered, unknown, offTopic, needsSupport }

/// جوابٌ واحد: عنوان · نصّ · خطوات · ميزاتٌ ذات صلة.
@immutable
class AiAnswer {
  const AiAnswer({
    required this.title,
    this.body = '',
    this.steps = const [],
    this.status = AiAnswerStatus.answered,
    this.related = const [],
    this.iosScrubbed = false,
  });

  final String title;
  final String body;
  final List<String> steps;
  final AiAnswerStatus status;
  final List<String> related;

  /// آيفون: سقطت من الجواب جملةٌ تدعو للشراء/الترقية، أو هو بديل الخادم
  /// لجوابٍ فرغ بعد التنقية («ما أگدر أساعد بهذا هنا») — فالسياق اشتراك
  /// الحساب ولا «تواصل ويّا الدعم» تحته ([AiApi.replyFrom]).
  final bool iosScrubbed;

  /// «ما أعرف» أو «الحلّ عند الشركة» — يُعرض معه التواصل مع الدعم.
  bool get wantsSupport =>
      status == AiAnswerStatus.unknown || status == AiAnswerStatus.needsSupport;

  static final _spaces = RegExp(r'\s+');

  static AiAnswer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    // آيفون: لا جملة تدعو للشراء/الترقية/كود التفعيل/«زيادة الحدّ» حتى لو
    // أفلتت من الخادم — بقواعد المساعد ([StorePolicy.assistantSafeLine]).
    String safe(String s) => StorePolicy.assistantSafeLine(s);
    final rawTitle = _str(j['title']) ?? '';
    final rawBody = _str(j['body']) ?? '';
    final rawSteps = _strings(j['steps'], max: 6, maxLen: 220);
    final rawRelated = _strings(j['related'], max: 4, maxLen: 40);
    final title = safe(rawTitle);
    final body = safe(rawBody);
    final steps = [
      for (final s in rawSteps)
        if (safe(s).isNotEmpty) safe(s),
    ];
    if (title.isEmpty && body.isEmpty && steps.isEmpty) return null;
    final related = [
      for (final r in rawRelated)
        if (safe(r) == r) r,
    ];
    final status = switch (_str(j['status'])) {
      'unknown' => AiAnswerStatus.unknown,
      'off_topic' => AiAnswerStatus.offTopic,
      'needs_support' => AiAnswerStatus.needsSupport,
      _ => AiAnswerStatus.answered,
    };
    // تغيّرٌ في الكلام لا في المسافات (التنقية تطوي الفراغات المتتالية).
    String flat(String s) => s.replaceAll(_spaces, ' ').trim();
    final scrubbed = StorePolicy.hidePurchaseFlows &&
        (flat(title) != flat(rawTitle) ||
            flat(body) != flat(rawBody) ||
            !listEquals([for (final s in steps) flat(s)],
                [for (final s in rawSteps) flat(s)]) ||
            related.length != rawRelated.length ||
            // بديل الخادم على آيفون لجوابٍ لم يبقَ منه شيء بعد تنقيته.
            (status == AiAnswerStatus.unknown &&
                body.isEmpty &&
                steps.isEmpty));
    return AiAnswer(
      title: title,
      body: body,
      steps: steps,
      status: status,
      related: related,
      iosScrubbed: scrubbed,
    );
  }

  /// نصٌّ واحد — للنسخ، وللمحادثة حين يُرسَل الجواب السابق سياقاً.
  String get plainText {
    final b = StringBuffer();
    if (title.isNotEmpty) b.writeln(title);
    if (body.isNotEmpty) b.writeln(body);
    for (var i = 0; i < steps.length; i++) {
      b.writeln('${i + 1}. ${steps[i]}');
    }
    return b.toString().trim();
  }
}

/// روابط الدعم مع «ما أعرف»/«الحلّ عند الشركة» — تلغرام وواتساب وحدهما،
/// بـhttps على مضيفيهما فقط (لا يُفتح رابطٌ آخر مهما وصل).
///
/// الخادم يمرّر قيم المالك كما خزّنها (`pro_settings.support_telegram` /
/// `support_whatsapp`): يوزر تلغرام بلا @ ورقمٌ دوليّ بلا + — كما يقرؤها
/// [SupportInfo] و`SupportContact` — فتُبنى منها الروابط هنا؛ والرابط الكامل
/// يُقبل على المضيفين المسموحين وحدهما.
@immutable
class AiSupport {
  const AiSupport({this.telegram, this.whatsapp});

  final Uri? telegram;
  final Uri? whatsapp;

  bool get isEmpty => telegram == null && whatsapp == null;

  static const _tgHosts = {'t.me', 'telegram.me'};
  static const _waHosts = {'wa.me', 'api.whatsapp.com'};

  /// يوزر تلغرام (٥–٣٢: حرفٌ لاتينيّ أوّلاً ثمّ حروفٌ وأرقام و_).
  static final _tgUser = RegExp(r'^@?([A-Za-z][A-Za-z0-9_]{4,31})$');

  /// رقم واتساب دوليّ: ٨–١٥ رقماً بعد نزع المسافات و+ و- والأقواس و00
  /// (ورقمٌ عراقيّ محلّيّ 07xxxxxxxxx ⇒ 9647xxxxxxxxx).
  static final _waNoise = RegExp(r'[\s()+-]');
  static final _waDigits = RegExp(r'^[1-9]\d{7,14}$');
  static final _iqLocal = RegExp(r'^07\d{9}$');

  /// «t.me/x» بلا مخطّط ⇒ https.
  static final _bareHost =
      RegExp(r'^(?:t\.me|telegram\.me|wa\.me|api\.whatsapp\.com)/');

  static Uri? _safe(String s, Set<String> hosts) {
    final u = Uri.tryParse(_bareHost.hasMatch(s) ? 'https://$s' : s);
    if (u == null ||
        u.scheme != 'https' ||
        !hosts.contains(u.host) ||
        u.userInfo.isNotEmpty ||
        u.hasPort) {
      return null;
    }
    return u;
  }

  static Uri? _telegram(Object? v) {
    final s = _str(v);
    if (s == null) return null;
    final m = _tgUser.firstMatch(s);
    if (m != null) return Uri.https('t.me', '/${m.group(1)}');
    return _safe(s, _tgHosts);
  }

  static Uri? _whatsapp(Object? v) {
    final s = _str(v);
    if (s == null) return null;
    var d = s.replaceAll(_waNoise, '');
    if (d.startsWith('00')) d = d.substring(2);
    if (_iqLocal.hasMatch(d)) d = '964${d.substring(1)}';
    if (_waDigits.hasMatch(d)) return Uri.https('wa.me', '/$d');
    return _safe(s, _waHosts);
  }

  static AiSupport? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = AiSupport(
      telegram: _telegram(raw['telegram']),
      whatsapp: _whatsapp(raw['whatsapp']),
    );
    return s.isEmpty ? null : s;
  }
}

/// رفضٌ أو تعذّرٌ — برسالة الخادم كما هي (عربيّة، ونسخة آيفون منه).
@immutable
class AiFailure {
  const AiFailure(
      {required this.message, this.code, this.status, this.retryAfterSec});

  final String message;
  final String? code;

  /// `null` = لم يصل ردّ (الشبكة).
  final int? status;
  final int? retryAfterSec;

  /// الميزة أُطفئت (أو خادمٌ أقدم) — تختفي من الواجهة.
  bool get isOff => status == 404;
  bool get quotaExhausted => code == 'AI_QUOTA_EXHAUSTED';
  bool get noPermission => code == 'AI_NO_PERMISSION';

  /// لا فائدة من سؤالٍ آخر الآن — الحقل يُقفل.
  bool get blocksInput =>
      isOff ||
      quotaExhausted ||
      noPermission ||
      code == 'AI_NO_PLAN' ||
      code == 'AI_ACCOUNT_REQUIRED' ||
      code == 'EMPLOYEE_ACCESS_DENIED';

  /// تعذّرٌ عابر — «أعد المحاولة» معقولة (ولم يُحسب من الحصّة).
  bool get retryable =>
      status == null ||
      code == 'AI_UNAVAILABLE' ||
      code == 'AI_IDENTITY_RETRY' ||
      code == 'AI_RATE_LIMITED' ||
      code == 'AI_BUSY' ||
      (status != null && status! >= 500);
}

/// ردّ explain/ask: جوابٌ أو رفض، ومعهما الحصّة إن قالها الخادم.
@immutable
class AiReply {
  const AiReply.answer(
    AiAnswer this.answer, {
    this.support,
    this.quota,
    this.cached = false,
    this.ref,
    this.historyText,
    this.historySig,
  }) : failure = null;

  const AiReply.failed(AiFailure this.failure, {this.quota})
      : answer = null,
        support = null,
        cached = false,
        ref = null,
        historyText = null,
        historySig = null;

  final AiAnswer? answer;
  final AiFailure? failure;
  final AiSupport? support;
  final AiQuota? quota;
  final bool cached;

  /// مرجعٌ قصير للدعم (لا معرّف قاعدة).
  final String? ref;

  /// نصّ الجواب للمحادثة وتوقيع الخادم عليه (`history_text` + `history_sig`)
  /// — يُعادان **كما هما حرفيّاً** مع السؤال التالي: الخادم لا يقبل دور
  /// مساعدٍ في السجلّ إلّا موقَّعاً منه لهذا المستخدم. `null` = خادمٌ أقدم
  /// (فلا يُرسل الجواب سياقاً).
  final String? historyText;
  final String? historySig;

  bool get ok => answer != null;

  /// يصلح دوراً سابقاً للمساعد في محادثة «كيف أسوّي؟».
  bool get signed => ok && historyText != null && historySig != null;
}

/// دورٌ واحد في محادثة «كيف أسوّي؟» — في الذاكرة وحدها.
///
/// سؤال المدير يُنقّى قبل الإرسال ([AiText.maskForSend])؛ وجواب المساعد يُرسل
/// **كما وقّعه الخادم حرفيّاً** مع توقيعه ([sig]) — بلا قناعٍ ولا قصّ، وإلّا
/// لا يطابق التوقيع. دور مساعدٍ بلا توقيع لا يُرسل أصلاً ([AiApi.trimHistory]).
@immutable
class AiTurn {
  const AiTurn.user(this.text)
      : fromUser = true,
        sig = null;
  const AiTurn.assistant(this.text, {this.sig}) : fromUser = false;

  final bool fromUser;
  final String text;

  /// دور المساعد وحده: توقيع الخادم على [text] (`history_sig`).
  final String? sig;

  bool get _signed => !fromUser && sig != null && sig!.isNotEmpty;

  Map<String, dynamic> toJson() => fromUser
      ? {'role': 'user', 'text': AiText.cut(AiText.maskForSend(text), 700)}
      : {'role': 'assistant', 'text': text, if (sig != null) 'sig': sig};
}

/// خطأٌ ظهر للمدير، كما يُرسَل لـ«اشرحلي».
///
/// [message] النصّ **كما ظهر** (يُخفى منه الهاتف والأرقام الطويلة قبل الإرسال).
/// [screen] و[context] من قوائمٍ ثابتة (`aiScreens` · [contextValues]) — ما
/// سواها يُسقَط، فلا نصّ حرّ يتسلّل في السياق.
@immutable
class ExplainRequest {
  const ExplainRequest({
    this.code,
    this.message,
    this.screen = 'other',
    this.httpStatus,
    this.context = const {},
  });

  final String? code;
  final String? message;
  final String screen;
  final int? httpStatus;
  final Map<String, String> context;

  static final _codeRe = RegExp(r'^[A-Za-z0-9_.:-]{2,64}$');

  /// الشاشات المعروفة للخادم (SPEC §10.1) — غيرها `other`.
  static const aiScreens = <String>{
    'dashboard',
    'subscribers',
    'subscriber_detail',
    'add_subscriber',
    'edit_subscriber',
    'activate',
    'extend',
    'package_change',
    'bulk_activate',
    'debts',
    'pay_debt',
    'cards',
    'packages',
    'prices',
    'discounts',
    'reports',
    'finance',
    'settlements',
    'expenses',
    'managers',
    'employees',
    'whatsapp',
    'telegram',
    'broadcast',
    'notifications',
    'portal',
    'topup',
    'devices',
    'settings',
    'login',
    'companies',
    'account',
    'employee_login',
    'other',
  };

  /// مفاتيح السياق وقيمها المسموحة وحدها.
  static const contextValues = <String, Set<String>>{
    'action': {
      'activate',
      'extend',
      'package_change',
      'add',
      'edit',
      'delete',
      'pay_debt',
      'add_debt',
      'toggle',
      'bulk_activate',
      'login',
      'connect_whatsapp',
      'send_whatsapp',
      'broadcast',
      'topup',
      'card_order',
      'transfer',
      'other',
    },
    'subscriber_state': {'active', 'expired', 'disabled', 'unknown'},
    'method': {
      'credit',
      'card',
      'cash',
      'deposit',
      'test',
      'user_balance',
      'zaincash',
      'voucher',
      'other',
    },
    'package_change_mode': {'now', 'at_expiry'},
  };

  bool get isEmpty =>
      (code == null || !_codeRe.hasMatch(code!)) &&
      (message == null || message!.trim().isEmpty);

  Map<String, dynamic> toJson({String lang = 'ar'}) {
    final ctx = <String, String>{
      for (final e in context.entries)
        if (contextValues[e.key]?.contains(e.value) ?? false) e.key: e.value,
    };
    final msg =
        message == null ? '' : AiText.cut(AiText.maskForSend(message!), 400);
    final st = httpStatus;
    return {
      if (code != null && _codeRe.hasMatch(code!)) 'code': code,
      if (msg.isNotEmpty) 'message': msg,
      'screen': aiScreens.contains(screen) ? screen : 'other',
      if (st != null && st >= 100 && st <= 599) 'http_status': st,
      if (ctx.isNotEmpty) 'context': ctx,
      'lang': lang == 'en' ? 'en' : 'ar',
    };
  }
}

/// تنقية ما يغادر الهاتف — دفاعٌ أوّل، والخادم يخفي ثانيةً (SPEC §10.3).
///
/// مرآةٌ لقواعد الخادم (`server/ai/sanitize.js` → `maskText`) وللويب
/// (`maskForAi`): قيمة كلمة السرّ/PIN/التوكن/رمز التحقّق/كود التفعيل تُخفى
/// بفاصلٍ أو بلا فاصل وبعد كلمتين تصفان («باسورد الإيداع 5544»، «كلمة المرور
/// للمشترك: zz9911»، «باسوردي 123456») — والقيمة تُخفى فقط إن كان فيها حرفٌ
/// لاتينيّ أو رقم، فـ«باسورد الإيداع غير صحيح» يبقى؛ وأرقام الكارت كاملةً؛
/// وتوكن بوت تلغرام؛ والهواتف بكلّ تجميع («0770 1234 567»، «(0770) 123 4567»).
abstract final class AiText {
  static const _mSecret = '[مخفي]';
  static const _mPhone = '[رقم مخفي]';

  static final _format =
      RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');
  static final _jwt =
      RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');
  // توكن بوت تلغرام: 7123456789:AAH-qTcv… (كان الجزء الرقميّ وحده يُخفى).
  static final _botToken =
      RegExp(r'(?<![A-Za-z0-9_])\d{6,12}:[A-Za-z0-9_-]{30,}');
  static final _email = RegExp(r'[^\s@]+@[^\s@]+\.[^\s@]+');
  static final _hex = RegExp(r'\b[A-Fa-f0-9]{24,}\b');
  static final _b64 = RegExp(r'[A-Za-z0-9+/_-]{28,}={0,2}');

  // ── كلمات السرّ وأخواتها: الكلمة تبقى والقيمة تُخفى ──
  // سوابق ملتصقة (و/ف/ب/ل/ك + ال/لل) وضمائر متّصلة («باسوردي»، «باسورده»).
  static const _pAr = '(?:[وفبلك]?(?:ال|لل)?)';
  static const _sfx = '(?:ي|ك|ه|ها|هم|كم|نا)?';
  static const _arStems = [
    'باس(?:وو?رد)?$_sfx',
    'كلم[ةه]\\s*(?:ال)?(?:سر\\u0651?|مرور)$_sfx',
    '(?:رمز|رقم)\\s*(?:ال)?سر\\u0651?ي$_sfx',
    '(?:رمز|رقم|كود|سيريال|سريال)\\s*(?:ال)?(?:كارت|كرت|بطاق[ةه])',
    '(?:رمز|كود)\\s*(?:ال)?تح\\u0651?ق\\u0651?ق',
    'كود\\s*(?:ال)?تفعيل',
    'توكن$_sfx',
    'رمز\\s*(?:ال)?PIN',
  ];
  // اللاتينيّة بحدودٍ لاتينيّة: BAD_PIN وPIN_LOCKED لا تُمسّ.
  static const _latStems = '(?:password|passwd|passcode|pass|pwd|pin|otp|token'
      '|secret|Password|PASSWORD|Pass|PASS|Pwd|PWD|Pin|PIN|Otp|OTP|Token|TOKEN'
      '|Secret|SECRET)';
  static final _stem = '(?<![\\p{L}\\p{N}_])(?:$_pAr(?:${_arStems.join('|')})'
      '(?![\\p{L}\\p{N}_])|$_pAr\u0640?$_latStems(?![A-Za-z0-9_]))';
  // حتى كلمتين عربيّتين تصفان («الإيداع»، «للمشترك»، «مالتي») ثمّ فاصلٌ اختياريّ.
  static const _qual =
      '(?:\\s+(?:لل|ال|ل|مال|تبع)?[\\u0600-\\u06FF]{2,12}){0,2}';
  static const _sep = '\\s*(?:[:=：]|\\bis\\b|هو|هي)?\\s*';
  static const _end = '(?=[\\s،,؛;.؟?!)\\]»"\']|\$)';
  // لا عددٌ قصير يليه معدودُه («كلمة المرور: 6 أحرف على الأقلّ»).
  static const _counted =
      '(?!\\d{1,3}\\s+(?:أحرف|حروف|حرفاً|حرفا|حرف|أرقام|رقماً'
      '|رقما|رقم|خانات|خانة|خانه|مرات|مرّات|مرة|مره|دقائق|دقيقة|ساعات|ساعة|أيام'
      '|يوماً|يوما|يوم|ثواني|ثانية)(?![\\p{L}]))';
  static const _value = '($_counted\\d(?:[\\s-]?\\d)*$_end'
      '|(?!\\(?(?:PIN|Pin|pin|OTP|otp|PASSWORD|Password|password|TOKEN|Token'
      '|token)\\)?$_end)(?![A-Z][A-Z0-9]*_[A-Z0-9_]+$_end)$_counted'
      '[^\\s،,؛;]*[A-Za-z0-9][^\\s،,؛;]*)';
  static final _secretKv = RegExp('($_stem$_qual$_sep)$_value', unicode: true);
  // «pin1234» / «pass123456» ملتصقة.
  static final _secretGlued = RegExp(
      r'(?<![A-Za-z0-9_])(pin|PIN|Pin|pass|PASS|Pass|pwd|PWD|otp|OTP)(\d{3,})(?![A-Za-z0-9_])');
  // «الكارت 12345678…» بلا «رقم/رمز»: ≥ ٨ أرقام فقط (لا «سعر الكارت 25000»).
  static final _cardBare = RegExp(
    '((?<![\\p{L}\\p{N}_])$_pAr(?:كارت|كرت|بطاق[ةه])(?:ات)?(?![\\p{L}\\p{N}_])'
    '(?:\\s+(?:ال)?(?:تعبئ[ةه]|شحن))?\\s*[:=：]?\\s*)(\\d(?:[\\s-]?\\d){7,})(?!\\d)',
    unicode: true,
  );

  // ── الهواتف والأرقام الطويلة (التواريخ والمبالغ محميّة قبلها) ──
  static final _protect = [
    RegExp(r'\d{4}-\d{1,2}-\d{1,2}(?:[ T]\d{1,2}:\d{2}(?::\d{2})?)?'),
    RegExp(r'\d{1,2}-\d{1,2}-\d{4}(?:\s+\d{1,2}:\d{2}(?::\d{2})?)?'),
    RegExp(r'\d{1,3}(?:,\d{3})+(?:\.\d+)?'),
  ];
  static final _placeholder = RegExp('\uE000([\uE100-\uEFFF])\uE001');
  static final _phoneIntl =
      RegExp(r'(?<!\d)(?:\+|00)?964[\s-]?7\d{2}[\s-]?\d{3}[\s-]?\d{4}(?!\d)');
  static final _phoneLocal =
      RegExp(r'(?<!\d)07\d{2}[\s-]?\d{3}[\s-]?\d{4}(?!\d)');
  static final _phoneBare =
      RegExp(r'(?<!\d)7[3-9]\d[\s-]\d{3}[\s-]\d{4}(?!\d)');
  // ≥ ١٠ أرقام بفواصل مفردة: «0770 1234 567»، «(0770) 123 4567»، كارت ١٦ رقماً.
  static final _sepDigits =
      RegExp(r'(?<!\d)(?:\+|00)?\(?\d(?:[\s.()-]{0,2}\d){9,}(?!\d)');
  static final _longDigits = RegExp(r'\d{9,}');
  static final _upper = RegExp('[A-Z]');
  static final _lower = RegExp('[a-z]');
  static final _digit = RegExp(r'\d');

  static String _latinDigits(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
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

  /// يُخفي الهواتف (بكلّ تجميع) والأرقام الطويلة وأرقام الكارت وPIN والتوكنات
  /// والبريد وقيم كلمات السرّ. التواريخ والمبالغ المجمّعة (`25,000`) والرموز
  /// (`PACKAGE_CHANGE_ACTIVE_FORBIDDEN`، `BAD_PIN`) تبقى، و«‹›» بدل «<>» (لا
  /// تفتح ولا تغلق كتل الطلب عند الخادم).
  static String maskForSend(String s) {
    var out = _latinDigits(s.replaceAll(_format, ''))
        .replaceAll('<', '‹')
        .replaceAll('>', '›');
    out = out
        .replaceAll(_jwt, _mSecret)
        .replaceAll(_botToken, _mSecret)
        .replaceAll(_email, '[بريد مخفي]');
    // التواريخ والمبالغ المفصولة لا تُقرأ رقمَ هاتفٍ ولا قيمةَ كارت.
    final kept = <String>[];
    for (final re in _protect) {
      out = out.replaceAllMapped(re, (m) {
        final v = m.group(0)!;
        if (kept.length >= 3800) return v;
        kept.add(v);
        return '\uE000${String.fromCharCode(0xE100 + kept.length - 1)}\uE001';
      });
    }
    out = out
        .replaceAllMapped(_secretKv, (m) => '${m.group(1)}$_mSecret')
        .replaceAllMapped(_secretGlued, (m) => '${m.group(1)}$_mSecret')
        .replaceAllMapped(_cardBare, (m) => '${m.group(1)}$_mSecret')
        .replaceAll(_hex, _mSecret)
        // سلسلةٌ طويلة بحروفٍ كبيرة وصغيرة وأرقام = توكن/مفتاح.
        .replaceAllMapped(_b64, (m) {
          final t = m.group(0)!;
          return _upper.hasMatch(t) && _lower.hasMatch(t) && _digit.hasMatch(t)
              ? _mSecret
              : t;
        })
        .replaceAll(_phoneIntl, _mPhone)
        .replaceAll(_phoneLocal, _mPhone)
        .replaceAll(_phoneBare, _mPhone)
        .replaceAll(_sepDigits, _mPhone)
        .replaceAll(_longDigits, _mPhone);
    if (kept.isNotEmpty) {
      out = out.replaceAllMapped(_placeholder, (m) {
        final i = m.group(1)!.codeUnitAt(0) - 0xE100;
        return i >= 0 && i < kept.length ? kept[i] : '';
      });
    }
    return out.trim();
  }

  static String cut(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);
}

// ═════════════════════════ الطلبات ═════════════════════════

class AiApi {
  AiApi._();

  static const _base = '/api/v2/ai';

  /// الجواب يأخذ ثوانيَ (النموذج) — أطول من مهلة العميل العامّة (٣٠ث).
  static const _receive = Duration(seconds: 60);
  static const _sendT = Duration(seconds: 15);

  /// عميل وضع الحساب — مستقلّ عن `ApiClient.dio` كـ`AccountApi`: معترض ذاك
  /// يعدّ أيّ ٤٠١ انتهاءَ جلسة الساس فيمسحها، وهنا لا جلسة ساسٍ أصلاً.
  static final Dio _accountDio = Dio(BaseOptions(
    baseUrl: ApiClient.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: _receive,
    sendTimeout: _sendT,
    validateStatus: (s) => s != null && s < 500,
    headers: const {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    },
  ))
    ..interceptors.add(StoreSafeMessagesInterceptor());

  @visibleForTesting
  static Dio get accountDio => _accountDio;

  /// منفذا الاختبار: توكن الحساب ووجود الحساب (Firebase لا يعمل في الاختبار).
  @visibleForTesting
  static Future<String?> Function({bool force}) accountTokenSource =
      AccountService.idToken;
  @visibleForTesting
  static bool Function() hasAccount = () => AccountService.currentUser != null;

  /// جلسة الشركة أوّلاً، ثمّ حساب Pro وحده، وإلّا لا شيء.
  static Future<AiMode> currentMode() async {
    String? token;
    try {
      token = await AuthStorage.readToken();
    } catch (_) {
      token = null;
    }
    if (token != null && token.isNotEmpty) return AiMode.company;
    bool account;
    try {
      account = hasAccount();
    } catch (_) {
      account = false;
    }
    return account ? AiMode.account : AiMode.none;
  }

  static String get _deviceLabel => Platform.isIOS ? 'ios' : 'android';

  static Future<Response<Object?>> _send(
    AiMode mode,
    String method,
    String path, {
    Object? data,
    bool forceToken = false,
  }) async {
    if (mode == AiMode.company) {
      return ApiClient.dio.request<Object?>(
        path,
        data: data,
        options: Options(
            method: method, receiveTimeout: _receive, sendTimeout: _sendT),
      );
    }
    final token = await accountTokenSource(force: forceToken);
    if (token == null || token.isEmpty) throw const _NoSession();
    return _accountDio.request<Object?>(
      path,
      data: data,
      options: Options(method: method, headers: {
        'x-account-token': token,
        'x-device-id': await DeviceId.get(),
        'x-device-label': _deviceLabel,
      }),
    );
  }

  /// ردٌّ من **خادمنا** (JSON بكلامه) داخل استثناء ٥xx — حكمٌ يُقرأ لا عطل.
  static (int, Map<String, dynamic>)? _ourReply(Object e) {
    if (e is! DioException) return null;
    final r = e.response;
    final data = r?.data;
    if (r == null || data is! Map) return null;
    final body = Map<String, dynamic>.from(data);
    if (!body.containsKey('success')) return null;
    return (r.statusCode ?? 0, body);
  }

  /// `null` = لا نعرف (لا ردّ، أو «أعد المحاولة» من الخادم) — تبقى الحالة
  /// المعروفة كما هي. [AiStatus.off] = مطفأة/غير موجودة لهذا الحساب.
  static Future<AiStatus?> status() async {
    final mode = await currentMode();
    if (mode == AiMode.none) return AiStatus.off;
    try {
      final r = await _send(mode, 'GET', '$_base/status');
      return statusFrom(r.statusCode ?? 0, _map(r.data), mode);
    } on _NoSession {
      return const AiStatus(enabled: false, mode: AiMode.none);
    } catch (e) {
      _log('status', e);
      final ours = _ourReply(e);
      if (ours != null) return statusFrom(ours.$1, ours.$2, mode);
      return null;
    }
  }

  @visibleForTesting
  static AiStatus? statusFrom(
      int code, Map<String, dynamic> body, AiMode mode) {
    // ٤٠٤ (مطفأ أو خادمٌ أقدم بلا المسار) · ٤٠١/٤٠٣ (لا هويّة/موظّفٌ معطّل)
    // ⇒ لا شيء يظهر. ٥٠٣ «أعد المحاولة» و٤٢٩ ⇒ لا نعرف بعد.
    if (code == 404 || code == 501 || code == 401 || code == 403) {
      return AiStatus(enabled: false, mode: mode);
    }
    if (code != 200 || body['success'] != true) return null;
    return AiStatus.fromJson(body, mode: mode);
  }

  /// «اشرحلي» — مرّةً لكلّ نقرة (لا إعادة تلقائيّة: قد يُحسب من الحصّة).
  static Future<AiReply> explain(ExplainRequest req,
      {String lang = 'ar'}) async {
    if (req.isEmpty) {
      return AiReply.failed(AiFailure(
          message: _t('ai.err_nothing', 'ماكو خطأ أشرحه'),
          code: 'AI_BAD_INPUT',
          status: 400));
    }
    return _post('$_base/explain', req.toJson(lang: lang),
        about: req.message, code: req.code);
  }

  /// «كيف أسوّي؟» — لجلسة الشركة. [history] آخر ستّ رسائل على الأكثر،
  /// تبدأ بسؤالٍ وتتناوب.
  static Future<AiReply> ask(
    String question, {
    List<AiTurn> history = const [],
    String? screen,
    String lang = 'ar',
  }) {
    final q = AiText.cut(AiText.maskForSend(question), 500);
    return _post(
      '$_base/ask',
      {
        'question': q,
        if (history.isNotEmpty)
          'history': [for (final t in trimHistory(history)) t.toJson()],
        if (screen != null && ExplainRequest.aiScreens.contains(screen))
          'screen': screen,
        'lang': lang == 'en' ? 'en' : 'ar',
      },
      ask: true,
      // كلّ أسئلة المحادثة (والخطأ الذي بدأت به): متابعةٌ قصيرة («طيب منو
      // أكلّم؟») بعد سؤالٍ عن الباقة تبقى في سياقه.
      about: [
        question,
        for (final t in history)
          if (t.fromUser) t.text,
      ].join('\n'),
    );
  }

  static final _refRe = RegExp(r'^[0-9a-f]{8}$');

  /// «مفيد» / «الجواب غلط» على جوابٍ بمرجعه ([AiReply.ref]) — المرجع والرأي
  /// وحدهما، بلا أيّ نصّ. `true` = وصل الخادم.
  static Future<bool> feedback(String ref, {required bool helpful}) async {
    if (!_refRe.hasMatch(ref)) return false;
    final mode = await currentMode();
    if (mode == AiMode.none) return false;
    try {
      final r = await _send(mode, 'POST', '$_base/feedback',
          data: {'ref': ref, 'helpful': helpful});
      return r.statusCode == 200 && _map(r.data)['success'] == true;
    } on _NoSession {
      return false;
    } catch (e) {
      _log('feedback', e);
      return false;
    }
  }

  /// آخر ستّ رسائل، تبدأ بسؤال المدير وتتناوب — ما يقبله الخادم.
  @visibleForTesting
  static List<AiTurn> trimHistory(List<AiTurn> history) {
    final clean = <AiTurn>[];
    for (final t in history) {
      if (t.text.trim().isEmpty) continue;
      // جواب مساعدٍ بلا توقيع الخادم يُسقطه الخادم **مع** السؤال قبله — فلا
      // يُرسلان أصلاً (خادمٌ أقدم بلا توقيع ⇒ لا سياق، لا رفض).
      if (!t.fromUser && !t._signed) {
        if (clean.isNotEmpty && clean.last.fromUser) clean.removeLast();
        continue;
      }
      if (clean.isEmpty && !t.fromUser) continue;
      if (clean.isNotEmpty && clean.last.fromUser == t.fromUser) {
        clean[clean.length - 1] = t; // الأحدث من الدورين المتتاليين
        continue;
      }
      clean.add(t);
    }
    if (clean.isNotEmpty && clean.last.fromUser) clean.removeLast();
    var out = clean.length > 6 ? clean.sublist(clean.length - 6) : clean;
    if (out.isNotEmpty && !out.first.fromUser) out = out.sublist(1);
    return out;
  }

  static Future<AiReply> _post(
    String path,
    Map<String, dynamic> data, {
    bool ask = false,
    String? about,
    String? code,
  }) async {
    final mode = await currentMode();
    if (mode == AiMode.none) return AiReply.failed(_offFailure);
    try {
      var r = await _send(mode, 'POST', path, data: data);
      var body = _map(r.data);
      // توكن حسابٍ قديم (ساعته انقضت) ⇒ يُجدَّد مرّةً ويُعاد.
      if (mode == AiMode.account &&
          r.statusCode == 403 &&
          body['code'] == 'AI_ACCOUNT_REQUIRED') {
        r = await _send(mode, 'POST', path, data: data, forceToken: true);
        body = _map(r.data);
      }
      return replyFrom(r.statusCode ?? 0, body,
          ask: ask, about: about, errorCode: code);
    } on _NoSession {
      return AiReply.failed(_offFailure);
    } catch (e) {
      _log(path, e);
      final ours = _ourReply(e);
      if (ours != null) {
        return replyFrom(ours.$1, ours.$2,
            ask: ask, about: about, errorCode: code);
      }
      return AiReply.failed(AiFailure(
        message: humanError(e,
            fallback:
                _t('ai.err_network', 'تعذّر الوصول للمساعد — أعد المحاولة')),
      ));
    }
  }

  static AiFailure get _offFailure => AiFailure(
      message: _t('ai.err_off', 'المساعد غير متاح حالياً'), status: 404);

  /// رمز خطأٍ عن حدود الحساب أو باقته (`company-limit`، `DEVICE_LIMIT`…).
  static final _planCode = RegExp(
      r'LIMIT|PLAN|LICEN[CS]E|SUBSCRIPTION|UPGRADE|TRIAL',
      caseSensitive: false);

  /// 🍏 آيفون: لا «تواصل ويّا الدعم» حيث يُقرأ تواصلاً للشراء خارج المتجر
  /// (3.1.1) — جوابٌ نُقّي من دعوة شراء أو بديلها ([AiAnswer.iosScrubbed])،
  /// و«ما أعرف» في «كيف أسوّي؟» (السؤال حرّ: قد يكون عن الباقة نفسها)، وخطأٌ
  /// أو محادثةٌ في سياق اشتراك الحساب أو حدوده
  /// ([StorePolicy.isAccountPlanContext]). مرآةٌ لـ`supportFor` في الخادم،
  /// ودفاعٌ ثانٍ إن أرسلها. غير آيفون: كما هي.
  static bool _supportSilenced(AiAnswer a,
      {required bool ask, String? about, String? code}) {
    if (!StorePolicy.hidePurchaseFlows) return false;
    if (a.iosScrubbed) return true;
    if (ask && a.status == AiAnswerStatus.unknown) return true;
    if (code != null && _planCode.hasMatch(code)) return true;
    return about != null && StorePolicy.isAccountPlanContext(about);
  }

  static final _sigRe = RegExp(r'^[A-Za-z0-9_-]{32}$');

  /// [ask] «كيف أسوّي؟» · [about] نصّ الخطأ أو أسئلة المحادثة · [errorCode]
  /// رمز الخطأ المشروح — لقرار روابط الدعم على آيفون وحده ([_supportSilenced]).
  @visibleForTesting
  static AiReply replyFrom(int code, Map<String, dynamic> body,
      {bool ask = false, String? about, String? errorCode}) {
    final quota = AiQuota.fromJson(body['quota']);
    if (code == 200 && body['success'] == true) {
      final answer = AiAnswer.fromJson(body['answer']);
      if (answer != null) {
        // نصّ السجلّ وتوقيعه كما أرسلهما الخادم حرفيّاً (لا قصّ ولا تنقية —
        // التوقيع على النصّ نفسه).
        final ht = body['history_text'];
        final hs = body['history_sig'];
        final signed = ht is String &&
            ht.isNotEmpty &&
            ht.length <= 700 &&
            hs is String &&
            _sigRe.hasMatch(hs);
        final ref = _str(body['ref']);
        return AiReply.answer(
          answer,
          support:
              _supportSilenced(answer, ask: ask, about: about, code: errorCode)
                  ? null
                  : AiSupport.fromJson(body['support']),
          quota: quota,
          cached: body['cached'] == true,
          ref: ref != null && _refRe.hasMatch(ref) ? ref : null,
          historyText: signed ? ht : null,
          historySig: signed ? hs : null,
        );
      }
      return AiReply.failed(
        AiFailure(message: _noAnswerText, status: 502),
        quota: quota,
      );
    }
    if (code == 404) return AiReply.failed(_offFailure, quota: quota);
    final serverCode = _str(body['code']);
    final msg = _str(body['message']);
    return AiReply.failed(
      AiFailure(
        message: msg != null ? StorePolicy.storeSafe(msg) : _fallbackText(code),
        code: serverCode,
        status: code,
        retryAfterSec: _int(body['retry_after_sec']),
      ),
      quota: quota,
    );
  }

  static String get _noAnswerText =>
      _t('ai.err_no_answer', 'تعذّر الحصول على جواب — أعد المحاولة');

  static String _fallbackText(int code) => switch (code) {
        429 =>
          _t('ai.err_rate', 'كثّرت الأسئلة بسرعة — استنّى دقيقة وارجع اسأل'),
        403 => _t('ai.err_forbidden', 'المساعد غير متاح لك حالياً'),
        400 => _t('ai.err_bad_question', 'اكتب سؤالك (من ٣ إلى ٥٠٠ حرف)'),
        >= 500 => _t('ai.err_server', 'المساعد مو متاح هسه — جرّب بعد شوية'),
        _ => _noAnswerText,
      };
}

class _NoSession implements Exception {
  const _NoSession();
}
