import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/ai_api.dart';
import '../api/api_error_tap.dart';

/// حال المساعد الذكيّ في هذه الجلسة — آخر ردّ `GET /api/v2/ai/status`.
///
/// الجلب **كسول** كـ`SelfDepositState`: يبدأ حين يستمع أحدٌ للحالة ([gate]) —
/// بطاقة «كيف أسوّي؟» في «قوائم أخرى»، أو إشعار خطأٍ له ما يُشرح — وكانت
/// قديمة؛ فلا طلب لمن لا يحتاجه. طلبٌ واحدٌ جارٍ على الأكثر، ومهلة ٥ دقائق،
/// وتبريد ٣٠ث بعد الفشل، و[epoch] يُسقط ردّاً وصل بعد تبديل الجلسة. والفشل لا
/// يمسح ما نعرفه، ولا يُظهر ما لم يقل الخادم إنّه مفتوح.
///
/// وتبدّل نوع الجلسة (حسابٌ وحده ⇄ شركة) يُعيد السؤال: «كيف أسوّي؟» لجلسة
/// الشركة وحدها، و«اشرحلي» في شاشات الحساب بتوكن الحساب.
class AiAssistantState {
  AiAssistantState._();

  static final ValueNotifier<AiStatus?> gate = _LazyAiGate();

  static int _epoch = 0;
  static DateTime? _fetchedAt;
  static DateTime? _failedAt;
  static Future<void>? _inflight;

  static const ttl = Duration(minutes: 5);
  static const _cooldown = Duration(seconds: 30);

  /// مراجع الأجوبة التي قيّمها المدير («مفيد»/«الجواب غلط») في هذه الجلسة —
  /// رأيٌ واحد للجواب حتى لو أُعيد بناء سطره.
  static final ratedRefs = <String>{};

  /// مصدر الوقت — يُستبدل في الاختبارات.
  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  /// تُؤخذ قبل الطلب: ردٌّ يصل بعد تبديل الجلسة لا يُكتب.
  static int get epoch => _epoch;

  static AiStatus? get status => gate.value;

  /// بطاقة «كيف أسوّي؟» تُعرض (مفتوحةً أو مقفلةً بمكانها).
  static bool get visible {
    final s = gate.value;
    return s != null && (s.canAsk || (s.locked && s.mode == AiMode.company));
  }

  /// زرّ «اشرحلي» يظهر.
  static bool get canExplain => gate.value?.canExplain ?? false;

  static bool get canAsk => gate.value?.canAsk ?? false;

  /// موظّفٌ بلا الصلاحيّة — البطاقة مقفلةٌ بمكانها.
  static bool get askLocked {
    final s = gate.value;
    return s != null && s.locked && s.mode == AiMode.company;
  }

  /// يجلب الحالة إن كانت قديمة (أو تبدّل نوع الجلسة).
  static Future<void> ensureFresh({bool force = false}) {
    final running = _inflight;
    if (running != null) return running;
    final epoch = _epoch;
    late final Future<void> run;
    run = () async {
      final mode = await AiApi.currentMode();
      if (epoch != _epoch) return;
      final cur = gate.value;
      final modeChanged = cur != null && cur.mode != mode;
      if (!force && !modeChanged) {
        final t = now();
        final at = _fetchedAt;
        if (at != null && t.difference(at) < ttl) return;
        final failed = _failedAt;
        if (failed != null && t.difference(failed) < _cooldown) return;
      }
      if (mode == AiMode.none) {
        apply(const AiStatus(enabled: false), epoch: epoch);
        return;
      }
      final s = await AiApi.status();
      if (epoch != _epoch) return;
      if (s == null) {
        _failedAt = now();
        return;
      }
      apply(s, epoch: epoch);
    }()
        .whenComplete(() {
      if (identical(_inflight, run)) _inflight = null;
    });
    _inflight = run;
    return run;
  }

  /// ردٌّ حيّ — من [ensureFresh].
  static void apply(AiStatus s, {int? epoch}) {
    if (epoch != null && epoch != _epoch) return;
    _fetchedAt = now();
    _failedAt = null;
    gate.value = s;
  }

  /// الحصّة بعد كلّ جواب — تُحدَّث بلا طلب.
  static void applyQuota(AiQuota? q) {
    final s = gate.value;
    if (s == null || q == null || !s.enabled) return;
    gate.value = s.withQuota(q);
  }

  /// الخادم ردّ ٤٠٤ على explain/ask: أُطفئت الآن — تختفي المداخل فوراً.
  static void turnOff() {
    final s = gate.value;
    _fetchedAt = now();
    gate.value = AiStatus(enabled: false, mode: s?.mode ?? AiMode.none);
  }

  /// من [SessionManager.clearAllSessionData] — لا يرى المدير التالي حال سابقه
  /// ولا يُشرح له خطأ سابقه.
  static void reset() {
    _epoch++;
    _fetchedAt = null;
    _failedAt = null;
    _inflight = null;
    gate.value = null;
    ratedRefs.clear();
    ApiErrorTap.clear();
  }

  @visibleForTesting
  static void debugSet(AiStatus? s) {
    _epoch++;
    _inflight = null;
    _failedAt = null;
    _fetchedAt = s == null ? null : now();
    gate.value = s;
  }

  // ───────────── «اشرحلي» من نصّ الإشعار ─────────────

  /// نافذة المطابقة بالنصّ: الإشعار يظهر بعد الردّ مباشرةً.
  static const _textWindow = Duration(seconds: 8);

  /// المطابقة بالوقت وحده (رسالة الشاشة غير رسالة الخادم): لعمليّةٍ
  /// (غير GET) رفضها الخادم برمزٍ قبل لحظات.
  static const _timeWindow = Duration(milliseconds: 2500);

  static final _invisible =
      RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]');

  static String _clean(String s) =>
      s.replaceAll(_invisible, '').replaceAll(RegExp(r'\s+'), ' ').trim();

  /// خطأ الخادم الذي يعرضه إشعارٌ نصّه [shown] — أو `null` (رسالةٌ محلّيّة،
  /// أو لا خطأ حديث). لا يسأل الخادم ولا يعرف شيئاً عن تفعيل الميزة: الزرّ
  /// يظهر بعدها فقط إن قال الخادم إنّها مفتوحة ([canExplain]).
  static ExplainRequest? explainFor(String shown) {
    final clean = _clean(shown);
    if (clean.isEmpty) return null;
    final t = now();
    final notes = ApiErrorTap.recent;
    for (var i = notes.length - 1; i >= 0; i--) {
      final n = notes[i];
      final age = t.difference(n.at);
      if (age.isNegative || age > _textWindow) continue;
      final m = n.message == null ? '' : _clean(n.message!);
      final byText = m.length >= 4 &&
          (clean == m ||
              clean.contains(m) ||
              (clean.length >= 8 && m.contains(clean)));
      final byTime = n.method != 'GET' && n.code != null && age <= _timeWindow;
      if (byText || byTime) return requestFor(n, shown: shown);
    }
    return null;
  }

  /// طلب «اشرحلي» من ردٍّ محفوظ: الشاشة والعمليّة من المسار، ونصّ الإشعار
  /// كما ظهر.
  @visibleForTesting
  static ExplainRequest requestFor(ApiErrorNote n, {required String shown}) {
    final (screen, action) =
        screenFor(n.method, n.path, packageChange: n.packageChange);
    return ExplainRequest(
      code: n.code,
      message: shown,
      screen: screen,
      httpStatus: n.status,
      context: {
        if (action != null) 'action': action,
        if (n.payMethod != null) 'method': n.payMethod!,
        if (n.packageChange && n.changeType != null)
          'package_change_mode':
              n.changeType == 'immediate' ? 'now' : 'at_expiry',
      },
    );
  }

  /// (شاشة، عمليّة) من مسار الطلب — بالقوائم الثابتة في [ExplainRequest].
  static (String, String?) screenFor(String method, String path,
      {bool packageChange = false}) {
    final m = method.toUpperCase();
    final p = path.split('?').first;
    final subItem = RegExp(r'/api/v2/subscribers/[^/]+$');
    if (m == 'PUT' && subItem.hasMatch(p)) {
      return packageChange
          ? ('package_change', 'package_change')
          : ('edit_subscriber', 'edit');
    }
    if (m == 'DELETE' && subItem.hasMatch(p)) {
      return ('subscriber_detail', 'delete');
    }
    if (m == 'POST' && RegExp(r'/api/v2/subscribers/?$').hasMatch(p)) {
      return ('add_subscriber', 'add');
    }
    for (final (re, screen, action) in _routes) {
      if (re.hasMatch(p)) return (screen, action);
    }
    return ('other', null);
  }

  static final _routes = <(RegExp, String, String?)>[
    (RegExp(r'/api/auth/(?:login|2fa/)'), 'login', 'login'),
    (RegExp(r'/api/auth/employee-login'), 'employee_login', 'login'),
    (RegExp(r'/api/account/companies'), 'companies', null),
    (RegExp(r'/api/account/'), 'account', null),
    (RegExp(r'/subscribers/bulk-activate'), 'bulk_activate', 'bulk_activate'),
    (RegExp(r'/subscribers/[^/]+/activat'), 'activate', 'activate'),
    (RegExp(r'/subscribers/[^/]+/extend'), 'extend', 'extend'),
    (
      RegExp(r'/subscribers/[^/]+/cancel-profile-change'),
      'package_change',
      'package_change'
    ),
    (RegExp(r'/subscribers/[^/]+/pay-debt'), 'pay_debt', 'pay_debt'),
    (RegExp(r'/subscribers/[^/]+/add-debt'), 'debts', 'add_debt'),
    (
      RegExp(r'/subscribers/[^/]+/(?:toggle-enabled|disconnect)'),
      'subscriber_detail',
      'toggle'
    ),
    (
      RegExp(r'/api/v2/el/(?:create-options|check-username|create)'),
      'add_subscriber',
      'add'
    ),
    (RegExp(r'/api/v2/el/transfer'), 'other', 'transfer'),
    (RegExp(r'/api/v2/cards'), 'cards', null),
    (RegExp(r'/api/v2/self-deposit'), 'topup', 'topup'),
    (
      RegExp(r'/api/whatsapp/broadcast|/api/telegram/broadcast'),
      'broadcast',
      'broadcast'
    ),
    (RegExp(r'/api/whatsapp/send-message'), 'whatsapp', 'send_whatsapp'),
    (
      RegExp(r'/api/whatsapp/(?:start-session|reconnect)'),
      'whatsapp',
      'connect_whatsapp'
    ),
    (RegExp(r'/api/(?:v2/)?whatsapp'), 'whatsapp', null),
    (RegExp(r'/api/telegram'), 'telegram', null),
    (RegExp(r'/api/v2/employees'), 'employees', null),
    (RegExp(r'/managers'), 'managers', null),
    (RegExp(r'/api/v2/subscriber-prices'), 'prices', null),
    (RegExp(r'/discounts'), 'discounts', null),
    (RegExp(r'/api/v2/(?:packages|price-list)'), 'packages', null),
    (RegExp(r'/api/reports/finance'), 'finance', null),
    (RegExp(r'/api/(?:reports|activities)|/api/v2/sessions'), 'reports', null),
    (RegExp(r'/api/v2/settlements'), 'settlements', null),
    (RegExp(r'/expenses'), 'expenses', null),
    (
      RegExp(r'/api/v2/portal|/api/v2/admin/(?:branding|portal-packages)'),
      'portal',
      null
    ),
    (
      RegExp(r'/api/v2/admin/devices|/api/v2/acl-list|/api/admin/device'),
      'devices',
      null
    ),
    (RegExp(r'/notification-prefs|/connection-alerts'), 'notifications', null),
    (RegExp(r'/api/v2/subscribers'), 'subscribers', null),
  ];
}

/// حالةٌ تطلب نفسها حين يُستمع إليها — فالبطاقة والإشعار يجلبان ما يحتاجانه
/// بلا سطرٍ في شاشةٍ لا تملك حالة.
class _LazyAiGate extends ValueNotifier<AiStatus?> {
  _LazyAiGate() : super(null);

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    // بعد البناء لا أثناءه: الجلب يكتب القيمة فيُعيد بناء المستمعين.
    scheduleMicrotask(() {
      AiAssistantState.ensureFresh();
    });
  }
}
