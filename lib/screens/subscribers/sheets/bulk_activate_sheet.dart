import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/api_client.dart';
import '../../../api/auth_api.dart';
import '../../../api/bulk_activate_api.dart';
import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../models/subscriber.dart';
import '../../../services/active_company.dart';
import '../../../services/provider_service.dart';
import '../../../services/subscriber_events.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/util/amount_input.dart';
import 'bulk_activate_guard.dart';

/// Bulk activate / renew sheet — direct port of v1's bulk_renew_sheet
/// from mobile-app/lib/screens/subscribers/bulk_renew_sheet.dart with
/// v2's design language.
///
/// Flow:
///   1. On open, ask the server whether this manager can bulk-activate at
///      all ([BulkActivateApi] — cached; «لا نعرف» never locks). Then fetch
///      /api/v2/subscribers/:idx/activation-data with bounded concurrency
///      ([bulkPrefetchConcurrency]); a 401/403 stops the prefetch instead
///      of firing hundreds of doomed calls. Each row gets package/price/
///      discount/current-balance + the manager's cost and balance.
///   2. Sheet lists every selected subscriber as a card with a 3-way
///      payment method picker (دين / نقدي / جزئي), defaulting to
///      دين. Partial mode reveals an amount field with chips.
///   3. Header summary chip + a 'تعيين الكل' row (3 ghost buttons)
///      that bulk-applies a method to all renewable rows.
///   4. Pre-flight: when the manager's balance and the rows' cost are
///      known and the balance can't cover them all, the sheet says so and
///      the confirm dialog offers the leading rows it covers (the rest are
///      «لم يُنفَّذ») — or «جرّب الكلّ»: some SAS allow a negative balance,
///      so it's a warning, not a block.
///   5. Submit runs [runBulkActivations] — one row at a time, like the SAS
///      panel itself — and STOPS at the first hard refusal (session,
///      permission, balance, server bulk refusal) or unclear outcome; a
///      refusal that only concerns one row never stops the others (like the
///      web). A SAS session that expired mid-run (409 SAS_SESSION_EXPIRED)
///      is refreshed like the interceptor does on 401 and the row re-sent
///      once. A banner sums it up: تمّ · رُفض · لم يُنفَّذ · غير مؤكّد, with
///      the reason. Done and unclear rows are never re-sent; «تجديد الباقين»
///      re-runs the rest.
///   6. One run takes the first [bulkDefaultMaxBatch] (or the server's
///      `limits.max_batch`) of the selection; the rest stay selected for the
///      next run — a bigger selection is never refused outright.
///
/// Returns the idx of the subscribers that stay selected once the sheet
/// closes — however it closes (button, back, drag) — like the web: not
/// activated and safe to send again (refused, not run, not loaded, beyond
/// the batch). Empty ⇒ the caller exits selection. `null` ⇒ the sheet never
/// opened (blocked — the selection stays as it is).
///
/// ايرث لنك، أو مديرٌ حكم الخادم بأنّه لا يجدّد دفعة: لا تُفتح
/// ([bulkActivateUnavailableReason]) — رسالة السبب بدلها.
Future<Set<String>?> showBulkActivateSheet(
  BuildContext context, {
  required List<Subscriber> subs,
}) async {
  final blocked = bulkActivateUnavailableReason();
  if (blocked != null) {
    // مقفلٌ بحكم الخادم: قد يكون أقدم من منح الصلاحيّة — يُسأل ثانيةً.
    BulkActivateApi.recheckIfLocked();
    showNoPermission(context, action: true, message: blocked);
    return null;
  }
  final outcome = _BulkOutcome(subs);
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _BulkActivateSheet(subs: subs, outcome: outcome),
  );
  return outcome.keep();
}

/// ما يبقى محدّداً بعد الإغلاق — يُقرأ من حال الصفوف لحظة الإغلاق، لا من
/// قيمة `pop`: سحبُ الورقة بعد دفعةٍ يعيد `null`، وإبقاء الكلّ محدّداً حينها
/// يُبقي المتمّ — وإعادته شهرٌ ثانٍ يُحتسب على الرصيد.
class _BulkOutcome {
  _BulkOutcome(this.all);
  final List<Subscriber> all;

  /// صفوف الدفعة بعد جلبها — `null` قبله (أُغلقت أو مُنعت قبل أيّ شيء: لم
  /// يُفعَّل أحد، فيبقى الكلّ كما هو).
  List<_RenewRow>? rows;

  /// ما بعد حدّ الدفعة من التحديد — لم يُجلب ولم يُرسَل.
  List<Subscriber> deferred = const [];

  Set<String> keep() {
    final rs = rows;
    if (rs == null) {
      return {for (final s in all) if (s.idx != null) s.idx!};
    }
    return {
      for (final r in rs)
        if (r.keepAfterClose && r.sub.idx != null) r.sub.idx!,
      for (final s in deferred) if (s.idx != null) s.idx!,
    };
  }
}

/// تجديد الجلسة حين يقول الخادم «انتهت جلسة الساس» في منتصف الدفعة —
/// [ApiClient.refreshSession] (المسار المشترك مع المعترض، بلا طرد). قابلٌ
/// للاستبدال في الاختبار وحده.
@visibleForTesting
Future<bool> Function() bulkSessionRefresher =
    () async => await ApiClient.refreshSession() == RefreshOutcome.ok;

/// لماذا لا يتاح التجديد الجماعيّ لهذه الجلسة؟ `null` = متاح.
///
/// ايرث لنك: تفعيلها يحتاج طريقته لكلّ مشترك — رصيد أون‑لاين بباسورد الإيداع
/// أو كارت برقمه — وهذه الورقة لا ترسلها؛ فكان الخادم يقع على `user/extend`
/// (تمديد ٢٤ ساعة) ويقيّد سعر باقةٍ كاملة في الدفتر، وصار يرفضها بـ409
/// `EL_METHOD_REQUIRED` (١٨ أكتوبر). فزرّ «تجديد» الجماعيّ يبقى بمكانه **مقفلاً
/// بهذا السبب** (لا مخفيّاً، ولا «اطلبها من مديرك» — لا صلاحيّة تفتحه)، للمالك
/// ولموظّفه، والتفعيل من نافذة كلّ مشترك.
///
/// شركات SAS4: حكم الخادم ([capability]، وإلّا آخر حكمٍ في الكاش) — مديرٌ
/// يفعّل بالكارت وحده (لا تفعيل من الرصيد في الساس)، أو ساسٌ لا يقبل الدفعة.
/// الحكم المجهول لا يقفل أبداً: الخادم يرفض الصفّ برمزه والورقة تقف عنده.
String? bulkActivateUnavailableReason({BulkActivateCapability? capability}) {
  if (ProviderService.isEarthlink ||
      ActiveCompany.current?.sasCode == 'earthlink') {
    return 'subscribers.bulk_renew_el_unavailable'.tr();
  }
  final cap = capability ?? BulkActivateApi.cached;
  if (cap == null || !cap.blocked) return null;
  return bulkCapabilityReason(cap);
}

/// نصّ المنع: رسالة الخادم كما كتبها، وإلّا جملتنا بحسب الرمز.
String bulkCapabilityReason(BulkActivateCapability cap) {
  final m = cap.message;
  if (m != null && m.isNotEmpty) return m;
  if ((cap.code ?? '').toUpperCase() == 'CARD_ONLY') {
    return 'subscribers.bulk_renew_credit_unavailable'.tr();
  }
  return 'subscribers.bulk_renew_unavailable'.tr();
}

/// انتظار حكم الخادم عند فتح الورقة بلا كاش — بعده «لا نعرف» (لا قفل).
const _capabilityWait = Duration(seconds: 6);

/// ما اختاره المدير في حوار التأكيد: ما يكفيه الرصيد وحده، أو الكلّ.
enum _RunChoice { fit, all }

enum _PayMethod { debt, cash, partial }

extension _PayMethodX on _PayMethod {
  String get label => switch (this) {
        _PayMethod.debt => 'sheets.pay_debt'.tr(),
        _PayMethod.cash => 'sheets.pay_cash'.tr(),
        _PayMethod.partial => 'sheets.pay_partial'.tr(),
      };
  IconData get icon => switch (this) {
        _PayMethod.debt => LucideIcons.creditCard,
        _PayMethod.cash => LucideIcons.banknote,
        _PayMethod.partial => LucideIcons.walletCards,
      };
  Color get color => switch (this) {
        _PayMethod.debt => AppColors.error,
        _PayMethod.cash => AppColors.brand,
        _PayMethod.partial => AppColors.brandAccent,
      };

  /// Maps to the backend's expected enum on POST
  /// /api/v2/subscribers/:idx/activate.
  String get apiValue => switch (this) {
        _PayMethod.debt => 'non-cash',
        _PayMethod.cash => 'cash',
        _PayMethod.partial => 'partial-cash',
      };
}

/// Per-row state. Activation-data is cached here as `data` so the
/// submit call can echo it back verbatim (the backend enforces this —
/// see server.js comment about SAS4 session locks). The partial-amount
/// controller is owned by the row so each card stays independent.
class _RenewRow {
  _RenewRow.success({
    required this.sub,
    required this.data,
    required this.originalPrice,
    required this.discount,
    required this.effectivePrice,
    required this.currentBalance,
    this.cost,
    this.managerBalance,
  })  : loadFailed = false,
        loadError = null,
        loadStopped = false,
        partialCtrl = TextEditingController(),
        method = _PayMethod.debt;

  _RenewRow.failed(this.sub, {this.loadError, this.loadStopped = false})
      : data = null,
        originalPrice = 0,
        discount = 0,
        effectivePrice = 0,
        currentBalance = 0,
        cost = null,
        managerBalance = null,
        loadFailed = true,
        partialCtrl = TextEditingController(),
        method = _PayMethod.debt;

  final Subscriber sub;
  final Map<String, dynamic>? data;
  final double originalPrice;
  final double discount;

  /// Price the admin pays — originalPrice - discount, never negative.
  final double effectivePrice;

  /// Signed balance (negative = debt, positive = credit). v1 calls
  /// this currentBalance.
  final double currentBalance;

  /// ما يخصمه الساس من رصيد المدير لهذا الصفّ (`manager_cost`) — `null` = لا نعرف.
  final double? cost;

  /// رصيد المدير في الساس كما قرأته activation-data — `null` = لا نعرف.
  final double? managerBalance;
  final bool loadFailed;

  /// لماذا لم تُجلب بياناته (رسالة الخادم أو توقّف الجلب).
  final String? loadError;

  /// لم يُجلب لأنّ الجلب وقف عند رفضٍ قاطع (جلسة/صلاحيّة/كثرة طلبات) — لا
  /// «تعذّر الجلب»: سببه [loadError] وحده (صلاحيّةٌ ناقصة ليست عطلاً).
  final bool loadStopped;
  final TextEditingController partialCtrl;

  _PayMethod method;
  int partialAmount = 0;
  bool _suppressFormat = false;

  BulkRowStatus status = BulkRowStatus.waiting;

  /// يجوز إرساله (ثانيةً)؟ لا للمتمّ ولا لغير المؤكّد ولا لما فُعِّل قبل
  /// لحظات (حارس التكرار) — إعادتها تفعيلٌ ثانٍ يُحتسب على الرصيد.
  bool retryable = true;
  String? err;

  bool get renewable => !loadFailed;

  bool get sendable =>
      renewable &&
      retryable &&
      status != BulkRowStatus.done &&
      status != BulkRowStatus.unclear &&
      status != BulkRowStatus.running;

  /// يبقى محدّداً بعد إغلاق الورقة؟ — من لم يُفعَّل ويجوز إرساله ثانيةً
  /// (كالويب): لم تُجلب بياناته، أو رُفض، أو لم يُنفَّذ (توقّفت الدفعة قبله،
  /// أو لا يكفيه الرصيد، أو لم يُرسَل أصلاً). لا المتمّ، ولا غير المؤكّد،
  /// ولا الجاري لحظة الإغلاق (نتيجته لم تُعرف)، ولا ما فُعِّل قبل لحظات أو
  /// عليه عمليّةٌ أخرى (`retryable=false`).
  bool get keepAfterClose {
    if (loadFailed) return true;
    if (!retryable) return false;
    return status == BulkRowStatus.waiting ||
        status == BulkRowStatus.failed ||
        status == BulkRowStatus.skipped;
  }

  double get cashIn => switch (method) {
        _PayMethod.cash => effectivePrice,
        _PayMethod.partial => partialAmount.toDouble(),
        _PayMethod.debt => 0,
      };

  /// Mirrors v1's newBalance / v2's _balanceAfter:
  ///   cash    → balance unchanged
  ///   debt    → balance - price
  ///   partial → balance - price + partialAmount
  double get balanceAfter => switch (method) {
        _PayMethod.cash => currentBalance,
        _PayMethod.partial => currentBalance - effectivePrice + partialAmount,
        _PayMethod.debt => currentBalance - effectivePrice,
      };

  bool get ready {
    if (!sendable) return false;
    // Partial only requires positive amount. Excess over the package
    // price lands as a credit on the subscriber's notes — same as v1
    // (مطلب المستخدم 2026-06-07).
    if (method == _PayMethod.partial && partialAmount <= 0) return false;
    return true;
  }

  void dispose() => partialCtrl.dispose();
}

class _BulkActivateSheet extends StatefulWidget {
  const _BulkActivateSheet({required this.subs, required this.outcome});
  final List<Subscriber> subs;

  /// يقرؤه المستدعي بعد الإغلاق (من يبقى محدّداً).
  final _BulkOutcome outcome;

  @override
  State<_BulkActivateSheet> createState() => _BulkActivateSheetState();
}

class _BulkActivateSheetState extends State<_BulkActivateSheet> {
  bool _loading = true;
  bool _submitting = false;
  bool _stopRequested = false;
  int _doneCount = 0;
  int _runTotal = 0;
  int _fetched = 0;
  final List<_RenewRow> _rows = [];

  /// الدفعة: أوّل حدّ الخادم من التحديد (أو [bulkDefaultMaxBatch])، والباقون
  /// خارجها يبقون محدّدين للدفعة التالية.
  List<Subscriber> _batch = const [];
  List<Subscriber> _deferred = const [];

  /// حكم الخادم عند الفتح — المجهول لا يقفل.
  BulkActivateCapability _capability = BulkActivateCapability.unknown;

  /// منعٌ ظهر بعد الفتح (حكمٌ لم يكن في الكاش): الورقة تعرض السبب وحده.
  String? _blockedReason;

  /// توقّف الجلب المسبق عند رفضٍ قاطع (401/403/429) — سببه.
  String? _fetchStopReason;

  /// حصيلة آخر دفعة وسبب توقّفها، وكم تمّ وتعذّر ما بعده (APPLIED_WITH_ERRORS).
  BulkRunReport? _report;
  String? _stopText;
  int _warned = 0;

  /// ما خصمته هذه الورقة من رصيد المدير منذ قُرئ — لتقدير الرصيد الباقي.
  double _spent = 0;

  /// الساس قال «الرصيد لا يكفي» والتقدير قال يكفي: الرقم المقروء لم يعد
  /// يُصدَّق — لا سطر رصيدٍ بأرقامٍ قد تكذب حتّى تُفتح الورقة من جديد.
  bool _balanceStale = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    final cap = await BulkActivateApi.capability().timeout(
      _capabilityWait,
      onTimeout: () => BulkActivateCapability.unknown,
    );
    if (!mounted) return;
    final blocked = bulkActivateUnavailableReason(capability: cap);
    if (blocked != null) {
      setState(() {
        _blockedReason = blocked;
        _loading = false;
      });
      return;
    }
    _capability = cap;
    // تحديدٌ أكبر من حدّ الدفعة لا يُرفض: أوّله هنا، والباقون للدفعة التالية.
    final max = cap.maxBatch ?? bulkDefaultMaxBatch;
    setState(() {
      _batch = widget.subs.take(max).toList();
      _deferred = widget.subs.skip(max).toList();
    });
    widget.outcome.deferred = _deferred;
    await _loadAll();
  }

  /// جلبٌ لن ينجح لغيره: الجلسة (401)، الصلاحيّة (403)، كثرة الطلبات (429).
  static bool _isHardFetchFailure(ActivationDataFetch r) =>
      r.data == null &&
      (r.status == 401 || r.status == 403 || r.status == 429);

  Future<void> _loadAll() async {
    // تزامنٌ محدود ([bulkPrefetchConcurrency]) بدل دفعاتٍ تنتظر أبطأ صفّ،
    // ورفضٌ قاطع يوقف طلب الجديد: مئتا مشترك بجلسةٍ منتهية كانت مئتي نداء.
    final subs = _batch;
    const noIdx = (data: null, status: null, code: 'NO_IDX', message: null);
    String? stopReason;
    final results = await boundedFetch<Subscriber, ActivationDataFetch>(
      items: subs,
      concurrency: (_capability.prefetchConcurrency ?? bulkPrefetchConcurrency)
          .clamp(1, bulkMaxPrefetchConcurrency),
      fetch: (s) async => s.idx == null
          ? noIdx
          : await SubscribersApi.fetchActivationDataDetailed(s.idx!),
      stopAfter: (r) {
        if (!_isHardFetchFailure(r)) return false;
        stopReason ??= _fetchFailureText(r);
        return true;
      },
      shouldStop: () => !mounted,
      onEach: (_, __) {
        if (mounted) setState(() => _fetched++);
      },
    );
    if (!mounted) return;
    final rows = <_RenewRow>[];
    for (var i = 0; i < subs.length; i++) {
      final s = subs[i];
      final f = results[i];
      if (f == null) {
        rows.add(_RenewRow.failed(s,
            loadError: 'sheets.bulk_row_not_fetched'.tr(), loadStopped: true));
        continue;
      }
      final ad = f.data;
      if (ad == null) {
        final hard = _isHardFetchFailure(f);
        rows.add(_RenewRow.failed(s,
            loadError: hard ? _fetchFailureText(f) : f.message,
            loadStopped: hard));
        continue;
      }
      double readD(String key) => bulkNumOrNull(ad[key]) ?? 0;
      final originalPrice = readD('user_price');
      final discount = readD('discount_amount');
      final effective = readD('price_after_discount');
      final cost = bulkNumOrNull(ad['manager_cost']);
      rows.add(
        _RenewRow.success(
          sub: s,
          data: ad,
          originalPrice: originalPrice,
          discount: discount,
          effectivePrice: effective > 0 ? effective : (originalPrice - discount),
          currentBalance: readD('current_balance'),
          cost: (cost != null && cost > 0) ? cost : null,
          managerBalance: ad.containsKey('manager_balance')
              ? bulkNumOrNull(ad['manager_balance'])
              : null,
        ),
      );
    }
    setState(() {
      _rows
        ..clear()
        ..addAll(rows);
      _fetchStopReason = stopReason;
      _loading = false;
    });
    // من الآن يُحسب «من يبقى محدّداً» من حال الصفوف (قبله: الكلّ كما هو).
    widget.outcome.rows = _rows;
  }

  String _fetchFailureText(ActivationDataFetch r) {
    final m = r.message;
    if (m != null && m.trim().isNotEmpty) return m.trim();
    return switch (r.status) {
      401 => 'sheets.bulk_stop_session'.tr(),
      403 => 'sheets.bulk_stop_permission'.tr(),
      _ => 'sheets.bulk_stop_refused'.tr(),
    };
  }

  /// رصيد المدير المعروف الآن: أقلّ ما قرأته activation-data للصفوف (الساس
  /// يرسله مع كلّ صفّ) — ناقصاً ما خصمته هذه الورقة منذ قُرئ.
  double? get _balance {
    if (_balanceStale) return null;
    double? min;
    for (final r in _rows) {
      final b = r.managerBalance;
      if (b != null && (min == null || b < min)) min = b;
    }
    return min == null ? null : min - _spent;
  }

  void _setAll(_PayMethod m) {
    setState(() {
      for (final r in _rows) {
        if (r.sendable) r.method = m;
      }
    });
  }

  void _setRowMethod(_RenewRow r, _PayMethod m) {
    setState(() => r.method = m);
  }

  void _onPartialChanged(_RenewRow r) {
    if (r._suppressFormat) return;
    final digits = r.partialCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    final formatted = _formatThousands(parsed);
    if (formatted != r.partialCtrl.text) {
      r._suppressFormat = true;
      r.partialCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      r._suppressFormat = false;
    }
    if (parsed != r.partialAmount) {
      setState(() => r.partialAmount = parsed);
    }
  }

  void _addToPartial(_RenewRow r, int chip) {
    final next = r.partialAmount + chip;
    final formatted = _formatThousands(next);
    r._suppressFormat = true;
    r.partialCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    r._suppressFormat = false;
    setState(() => r.partialAmount = next);
  }

  static String _formatThousands(int v) {
    if (v == 0) return '';
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// ما يُرسَل في الضغطة القادمة: الصفوف التي يجوز إرسالها (لا المتمّ ولا
  /// غير المؤكّد) — فبعد دفعةٍ ناقصة يعدّ الشريط الباقين وحدهم.
  ({int debt, int cash, int partial, double cashTotal, int failed})
      get _summary {
    var d = 0, c = 0, p = 0, f = 0;
    var ct = 0.0;
    for (final r in _rows) {
      if (!r.renewable) {
        // ما أوقف الجلبَ عنده رفضٌ قاطع يقوله الشريط مرّةً — لا «فشل تحميل».
        if (!r.loadStopped) f++;
        continue;
      }
      if (!r.sendable) continue;
      switch (r.method) {
        case _PayMethod.debt:
          d++;
          break;
        case _PayMethod.cash:
          c++;
          ct += r.cashIn;
          break;
        case _PayMethod.partial:
          p++;
          ct += r.cashIn;
          break;
      }
    }
    return (debt: d, cash: c, partial: p, cashTotal: ct, failed: f);
  }

  List<_RenewRow> get _readyRows => _rows.where((r) => r.ready).toList();

  /// طرق الدفع وما يُقبض نقداً لصفوفٍ بعينها — لحوار التأكيد (الدفعة كما
  /// ستُرسَل، لا كلّ ما في الورقة).
  static ({int debt, int cash, int partial, double cashTotal}) _methodsOf(
      Iterable<_RenewRow> rows) {
    var d = 0, c = 0, p = 0;
    var ct = 0.0;
    for (final r in rows) {
      switch (r.method) {
        case _PayMethod.debt:
          d++;
        case _PayMethod.cash:
          c++;
          ct += r.cashIn;
        case _PayMethod.partial:
          p++;
          ct += r.cashIn;
      }
    }
    return (debt: d, cash: c, partial: p, cashTotal: ct);
  }

  BulkPreflight _preflightFor(List<_RenewRow> rows) => BulkPreflight.compute(
        balance: _balance,
        costs: [for (final r in rows) r.cost],
      );

  bool get _canSubmit {
    if (_loading || _submitting || _blockedReason != null) return false;
    return _readyRows.isNotEmpty;
  }

  /// بعد دفعة: صفوفٌ يجوز إرسالها ثانيةً (رُفضت أو لم تُنفَّذ).
  bool get _afterRun => _report != null;

  Future<void> _confirmAndSubmit() async {
    final ready = _readyRows;
    if (ready.isEmpty) return;
    final pf = _preflightFor(ready);
    // لا يكفي الرصيد (تقديرٌ من رصيد الساس وكلفة كلّ صفّ): الخيار الأوّل
    // دفعةٌ مقصورة على ما يكفيه من رأسها. و«جرّب الكلّ» يبقى — بعض الساسات
    // تسمح برصيدٍ سالب، والتقدير تنبيهٌ لا منع؛ والدفعة تقف عند أوّل رفض.
    final short = pf.insufficient;
    final fit = short ? (pf.fitCount ?? 0) : ready.length;
    final cur = 'common.currency'.tr();
    Widget summary(Iterable<_RenewRow> rows) {
      final s = _methodsOf(rows);
      return Text(
        'sheets.bulk_renew_summary'.tr(namedArgs: {
          'debt': '${s.debt}',
          'cash': '${s.cash}',
          'partial': '${s.partial}',
          'total': formatIQD(s.cashTotal.round()),
          'currency': cur,
        }),
        style: AppType.subtitle(color: AppColors.textMid),
      );
    }

    final choice = await showDialog<_RunChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'sheets.confirm_bulk_renew'
              .tr(namedArgs: {'n': '${fit > 0 ? fit : ready.length}'}),
          style: AppType.label(color: AppColors.textHi)
              .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            summary(fit > 0 ? ready.take(fit) : ready),
            if (pf.balance != null) ...[
              const SizedBox(height: Sp.sm),
              _PreflightLine(preflight: pf),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('common.cancel'.tr()),
          ),
          if (short)
            TextButton(
              key: const ValueKey('bulk-try-all'),
              onPressed: () => Navigator.of(ctx).pop(_RunChoice.all),
              child: Text('sheets.bulk_renew_try_all'
                  .tr(namedArgs: {'n': '${ready.length}'})),
            ),
          if (fit > 0)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
              onPressed: () => Navigator.of(ctx)
                  .pop(short ? _RunChoice.fit : _RunChoice.all),
              child: Text(short
                  ? 'sheets.bulk_renew_fit_only'.tr(namedArgs: {'n': '$fit'})
                  : 'sheets.renew_now'.tr()),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == _RunChoice.fit) {
      await _submit(ready.take(fit).toList(),
          noBalance: ready.skip(fit).toList());
    } else {
      await _submit(ready);
    }
  }

  Future<void> _submit(
    List<_RenewRow> batch, {
    List<_RenewRow> noBalance = const [],
  }) async {
    if (batch.isEmpty) return;
    // الطبقة الجذريّة قبل الدفعة: إن سُحبت الورقة لتُغلق أثناءها (السحب لا
    // يمرّ بـPopScope) تقف بعد الصفّ الجاري، والحصيلة تظهر فوق ما تحتها.
    final rootOverlay = Overlay.maybeOf(context, rootOverlay: true);
    setState(() {
      _submitting = true;
      _stopRequested = false;
      _doneCount = 0;
      _runTotal = batch.length;
      _report = null;
      _stopText = null;
      for (final r in batch) {
        r.status = BulkRowStatus.waiting;
        r.err = null;
      }
      for (final r in noBalance) {
        r.status = BulkRowStatus.skipped;
        r.err = 'sheets.bulk_row_no_balance'.tr();
        r.retryable = true;
      }
    });
    final report = await runBulkActivations<_RenewRow>(
      items: batch,
      // واحدٌ تلو واحد — كلوحة الساس نفسها والويب: تفعيلان معاً على رصيدٍ
      // واحد قد يتجاوزان فحص الرصيد عند الساس.
      concurrency: 1,
      shouldStop: () => !mounted || _stopRequested,
      onStart: (r) {
        if (mounted) setState(() => r.status = BulkRowStatus.running);
      },
      // جلسة الساس انتهت في المنتصف (409 SAS_SESSION_EXPIRED — لم يُكتب شيء
      // لذلك الصفّ): تُجدَّد كما يفعل المعترض عند 401 ويُعاد الصفّ مرّةً، بدل
      // أن تقف الدفعة وتطلب من المدير دخولاً لا يلزمه.
      activate: (r) => activateWithSessionRetry(
        send: () => SubscribersApi.activateDetailed(
          idx: r.sub.idx!,
          paymentType: r.method.apiValue,
          activationData: r.data!,
          partialAmount:
              r.method == _PayMethod.partial ? r.partialAmount : null,
          bulk: true,
        ),
        refresh: () => bulkSessionRefresher(),
      ),
      onStep: (r, step) {
        r.status = step.status;
        r.err = _rowText(step);
        r.retryable = _retryable(step);
        if (step.status == BulkRowStatus.done) _spent += r.cost ?? 0;
        if (mounted) setState(() => _doneCount++);
      },
    );
    // الساس نفسه قال «لا يكفي» (لا فحصنا المسبق): الرقم المقروء كان أكبر من
    // الحقيقة — لا نبني عليه بعد الآن.
    if (report.stoppedBy == BulkStopKind.balance) _balanceStale = true;
    report.skipped += noBalance.length;
    if (report.stoppedBy == null && noBalance.isNotEmpty) {
      report.stoppedBy = BulkStopKind.balance;
    }
    // تغيّر شيءٌ في الساس (أو ربّما): القوائم تُحدَّث.
    if (report.done > 0 || report.unclear > 0) SubscriberEvents.notifyChange();
    // رفضٌ بصلاحيّةٍ أو رفضٌ للدفعة: حكم القدرة المكاش قديم — يُعاد من الخادم
    // فيُقفل الزرّ في الشريط بسببه قبل المحاولة التالية.
    if (report.stoppedBy == BulkStopKind.permission ||
        report.stoppedBy == BulkStopKind.refused) {
      BulkActivateApi.invalidate();
      unawaited(BulkActivateApi.capability(fresh: true));
    }
    if (!mounted) {
      if (rootOverlay != null && report.total > 0) {
        final why = _stopReasonText(report);
        unawaited(showSheetSnackOn(
          rootOverlay,
          why == null ? _reportCounts(report) : '${_reportCounts(report)}\n$why',
          isError: report.done != batch.length,
          duration: const Duration(seconds: 6),
        ));
      }
      return;
    }
    // تمّ وتعذّر ما بعده: يبقى أمام المدير (لا تُغلق الورقة على تنبيهٍ يضيع).
    final warned = batch
        .where((r) => r.status == BulkRowStatus.done && r.err != null)
        .length;
    final allDone =
        report.done == batch.length && noBalance.isEmpty && warned == 0;
    setState(() {
      _submitting = false;
      _report = report;
      _warned = warned;
      _stopText = _stopReasonText(report);
    });
    final countsText = _reportCounts(report);
    showSheetSnack(
      context,
      allDone ? 'sheets.renewed_n'.tr(namedArgs: {'n': '${report.done}'}) : countsText,
      isError: !allDone,
    );
    final pending = _rows.any((r) => r.renewable && r.status != BulkRowStatus.done);
    if (allDone && !pending && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// يجوز إرسال الصفّ ثانيةً بعد هذا الحكم؟
  static bool _retryable(BulkStep step) => switch (step.status) {
        BulkRowStatus.failed => true,
        // لم يُرسَل (توقّفت الدفعة قبله) ⇒ نعم. فُعِّل قبل لحظات أو عمليّةٌ
        // أخرى عليه (رسالةٌ من الخادم) ⇒ لا: إعادته تفعيلٌ ثانٍ محتمل.
        BulkRowStatus.skipped => step.message == null,
        BulkRowStatus.waiting => true,
        _ => false,
      };

  String? _rowText(BulkStep step) => switch (step.status) {
        // تمّ وتعذّر ما بعده (APPLIED_WITH_ERRORS): رسالة الخادم تنبيهاً.
        BulkRowStatus.done => step.message,
        BulkRowStatus.failed => step.message ?? 'common.error'.tr(),
        BulkRowStatus.unclear => step.message ?? 'sheets.bulk_row_unclear'.tr(),
        BulkRowStatus.skipped => step.message ?? 'sheets.bulk_row_skipped'.tr(),
        _ => null,
      };

  String _reportCounts(BulkRunReport r) {
    final base = 'sheets.bulk_report'.tr(namedArgs: {
      'done': '${r.done}',
      'failed': '${r.failed}',
      'skipped': '${r.skipped}',
    });
    if (r.unclear == 0) return base;
    return '$base · ${'sheets.bulk_report_unclear'.tr(namedArgs: {'n': '${r.unclear}'})}';
  }

  String? _stopReasonText(BulkRunReport r) {
    final kind = r.stoppedBy;
    if (kind == null) return null;
    final base = switch (kind) {
      BulkStopKind.session => 'sheets.bulk_stop_session'.tr(),
      BulkStopKind.permission => 'sheets.bulk_stop_permission'.tr(),
      BulkStopKind.balance => 'sheets.bulk_stop_balance'.tr(),
      BulkStopKind.refused => 'sheets.bulk_stop_refused'.tr(),
      BulkStopKind.unclear => 'sheets.bulk_stop_unclear'.tr(),
      BulkStopKind.cancelled => 'sheets.bulk_stop_cancelled'.tr(),
    };
    final m = r.stopMessage?.trim();
    if (m == null || m.isEmpty || kind == BulkStopKind.cancelled) return base;
    // رسالة الخادم تقول السبب بدقّة (وما يُفعل بعده) — إلّا العامّة منها.
    if (_genericFailures.contains(m)) return base;
    return 'sheets.bulk_stop_with'.tr(namedArgs: {'msg': m});
  }

  /// رسائلُ لا تقول سبباً — مكانها جملتنا بحسب نوع التوقّف.
  static const _genericFailures = {'فشل التفعيل', 'تعذّر التفعيل'};

  void _requestStop() {
    if (!_submitting || _stopRequested) return;
    HapticFeedback.selectionClick();
    setState(() => _stopRequested = true);
  }

  String get _footerLabel {
    final s = _summary;
    final n = s.debt + s.cash + s.partial;
    if (_submitting) {
      return _stopRequested
          ? 'sheets.bulk_stopping'.tr()
          : 'sheets.renewing_progress'.tr(namedArgs: {
              'done': '$_doneCount',
              'total': '$_runTotal',
            });
    }
    final cash = s.cashTotal > 0
        ? ' (${formatIQD(s.cashTotal.round())} ${'common.currency'.tr()} ${'sheets.cash_word'.tr()})'
        : '';
    return (_afterRun
            ? 'sheets.renew_rest'.tr(namedArgs: {'n': '$n'})
            : 'sheets.renew_n_subs'.tr(namedArgs: {'n': '$n'})) +
        cash;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = _summary;
    final blocked = _blockedReason;
    final ready = _loading || blocked != null ? const <_RenewRow>[] : _readyRows;
    final pf = ready.isEmpty ? null : _preflightFor(ready);
    final anyRenewable = _rows.any((r) => r.renewable);
    // عدد الدفعة (أوّل حدّ الخادم من التحديد) — والباقون في سطرٍ تحت الشريط.
    final batchN = _batch.length;
    final subtitle = blocked != null
        ? '${widget.subs.length} ${'dashboard.subscriber_singular'.tr()}'
        : _loading
            ? (_fetched > 0
                ? 'sheets.bulk_fetch_progress'.tr(namedArgs: {
                    'done': '$_fetched',
                    'total': '$batchN',
                  })
                : 'sheets.loading_activation_data'.tr())
            : '$batchN ${'dashboard.subscriber_singular'.tr()}'
                '${s.failed > 0 ? ' (${'sheets.load_failed_n'.tr(namedArgs: {
                        'n': '${s.failed}'
                      })})' : ''}';
    return PopScope(
      // دفعةٌ جارية لا تُغلق برجوعٍ عابر — زرّ الإيقاف يقفها بعد الصفّ الحاليّ
      // فتبقى الحصيلة أمام المدير.
      canPop: !_submitting,
      child: DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.calendarPlus,
          title: 'sheets.bulk_renew_title'.tr(),
          subtitle: subtitle,
          // من يبقى محدّداً يُحسب من حال الصفوف ([_BulkOutcome]) لا من قيمة الإغلاق.
          onClose: _submitting ? () {} : () => Navigator.of(context).pop(),
        ),
        footer: blocked != null
            ? SheetFooterBar(
                label: 'common.close'.tr(),
                icon: LucideIcons.x,
                color: AppColors.textMid,
                onPressed: () => Navigator.of(context).pop(),
              )
            : SheetFooterBar(
                label: _footerLabel,
                icon: LucideIcons.calendarPlus,
                enabled: _canSubmit,
                busy: _submitting,
                onPressed: _confirmAndSubmit,
                // تحذيرٌ وحده فوق الزرّ (رصيدٌ لا يكفي الكلّ) — والسطر الكامل
                // (رصيدك · الكلفة) في حوار التأكيد، فلا يطول الشريط بلا داعٍ.
                above: (!_submitting && pf != null && pf.insufficient)
                    ? _PreflightLine(preflight: pf)
                    : null,
                leading: _submitting
                    ? Semantics(
                        button: true,
                        label: 'sheets.bulk_stop'.tr(),
                        excludeSemantics: true,
                        child: SheetFooterIconButton(
                          key: const ValueKey('bulk-stop'),
                          icon: LucideIcons.circleStop,
                          color: AppColors.error,
                          onTap: _stopRequested ? null : _requestStop,
                        ),
                      )
                    : null,
              ),
        maxHeightFactor: 0.97,
        scrollable: false,
        bodyPadding: EdgeInsets.zero,
        body: blocked != null
            ? _BlockedPanel(reason: blocked)
            : Column(
                children: [
                  if (!_loading) ...[
                    // لا صفّ يُجدَّد (الجلب وقف كلّه): لا شريط عدٍّ ولا «تعيين
                    // الكل» فوق قائمةٍ لا يُختار فيها شيء.
                    if (anyRenewable) _SummaryStrip(summary: s),
                    if (_report != null)
                      _RunReportBanner(
                        counts: _reportCounts(_report!),
                        reason: [
                          if (_stopText != null) _stopText!,
                          if (_warned > 0)
                            'sheets.bulk_report_warned'
                                .tr(namedArgs: {'n': '$_warned'}),
                        ].join('\n'),
                        stopped: _report!.stopped,
                        hasUnclear: _report!.unclear > 0 || _warned > 0,
                      )
                    else if (_fetchStopReason != null)
                      _RunReportBanner(
                        counts: 'sheets.bulk_fetch_stopped'.tr(),
                        reason: _fetchStopReason,
                        stopped: true,
                        hasUnclear: false,
                      ),
                    // تحديدٌ أكبر من حدّ الدفعة: أوّله هنا، والباقون يبقون محدّدين.
                    if (_deferred.isNotEmpty)
                      _DeferredNote(
                        text: 'sheets.bulk_first_n'.tr(namedArgs: {
                          'n': '$batchN',
                          'all': '${widget.subs.length}',
                          'rest': '${_deferred.length}',
                        }),
                      ),
                    if (anyRenewable)
                      _SetAllRow(
                        onSetAll: _setAll,
                        enabled: !_submitting,
                      ),
                  ],
                  Expanded(
                    child: _loading
                        ? Center(
                            child:
                                CircularProgressIndicator(color: AppColors.brand),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(
                                Sp.lg, Sp.sm, Sp.lg, Sp.md),
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: Sp.sm),
                            itemBuilder: (_, i) {
                              final r = _rows[i];
                              return _RenewRowCard(
                                row: r,
                                enabled: !_submitting && r.sendable,
                                onMethod: (m) => _setRowMethod(r, m),
                                onPartialChanged: () => _onPartialChanged(r),
                                onPartialChip: (v) => _addToPartial(r, v),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// المنع داخل الورقة — حكمٌ وصل بعد فتحها (لم يكن في الكاش): قفلٌ وسببه.
class _BlockedPanel extends StatelessWidget {
  const _BlockedPanel({required this.reason});
  final String reason;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.xl, Sp.xl, Sp.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: LockedStyle.box,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const PermLockIcon(size: 24),
          ),
          const SizedBox(height: Sp.md),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: AppType.label(color: AppColors.textMid)
                .copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// سطر الفحص المسبق: رصيدك · الكلفة عليك — وتحذيرٌ حين لا يكفي.
class _PreflightLine extends StatelessWidget {
  const _PreflightLine({required this.preflight});
  final BulkPreflight preflight;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final pf = preflight;
    final cur = 'common.currency'.tr();
    final bad = pf.insufficient;
    final color = bad ? AppColors.error : AppColors.textMid;
    final balance = formatIQD((pf.balance ?? 0).round());
    final line = pf.knownCost <= 0
        ? 'sheets.bulk_balance_only'
            .tr(namedArgs: {'balance': balance, 'currency': cur})
        : (pf.costKnown
                ? 'sheets.bulk_balance_line'
                : 'sheets.bulk_balance_line_partial')
            .tr(namedArgs: {
            'balance': balance,
            'cost': formatIQD(pf.knownCost.round()),
            'currency': cur,
          });
    final fit = pf.fitCount ?? 0;
    final warn = !bad
        ? null
        : fit > 0
            ? 'sheets.bulk_balance_short'.tr(namedArgs: {
                'fit': '$fit',
                'n': '${pf.count}',
                'short': formatIQD((pf.shortfall ?? 0).round()),
                'currency': cur,
              })
            : 'sheets.bulk_balance_none'.tr();
    return Container(
      key: const ValueKey('bulk-preflight'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bad ? AppColors.dangerSoftBg : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(
            color: bad ? AppColors.dangerSoftBorder : AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(bad ? LucideIcons.triangleAlert : LucideIcons.wallet,
                size: 14, color: color),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  line,
                  style: AppType.muted(color: color).copyWith(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (warn != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    warn,
                    style: AppType.muted(color: AppColors.error).copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// تحديدٌ أكبر من حدّ الدفعة: هذه الدفعة أوّله، والباقون يبقون محدّدين
/// للدفعة التالية (لا رفضٌ للتحديد كلّه — كالويب).
class _DeferredNote extends StatelessWidget {
  const _DeferredNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      key: const ValueKey('bulk-deferred'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(LucideIcons.info, size: 14, color: AppColors.textMid),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppType.muted(color: AppColors.textMid).copyWith(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// حصيلة الدفعة: تمّ · رُفض · لم يُنفَّذ (· غير مؤكّد) — وسبب التوقّف.
class _RunReportBanner extends StatelessWidget {
  const _RunReportBanner({
    required this.counts,
    required this.reason,
    required this.stopped,
    required this.hasUnclear,
  });
  final String counts;
  final String? reason;
  final bool stopped;
  final bool hasUnclear;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final tone = hasUnclear
        ? (AppColors.warningSoftBg, AppColors.warningSoftBorder, AppColors.warning)
        : stopped
            ? (AppColors.dangerSoftBg, AppColors.dangerSoftBorder, AppColors.error)
            : (AppColors.brandSoftBg, AppColors.brandSoftBorder, AppColors.brand);
    return Container(
      key: const ValueKey('bulk-report'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tone.$1,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: tone.$2),
      ),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                hasUnclear
                    ? LucideIcons.circleHelp
                    : stopped
                        ? LucideIcons.octagonX
                        : LucideIcons.listChecks,
                size: 15,
                color: tone.$3,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    counts,
                    style: AppType.label(color: AppColors.textHi).copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (reason != null && reason!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      reason!,
                      style: AppType.muted(color: AppColors.textMid).copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.summary});
  final ({
    int debt,
    int cash,
    int partial,
    double cashTotal,
    int failed
  }) summary;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _SummaryChip(
              label: 'sheets.pay_debt'.tr(),
              count: summary.debt,
              color: AppColors.error),
          const SizedBox(width: 6),
          _SummaryChip(
              label: 'sheets.pay_cash'.tr(),
              count: summary.cash,
              color: AppColors.brand),
          const SizedBox(width: 6),
          _SummaryChip(
              label: 'sheets.pay_partial'.tr(),
              count: summary.partial,
              color: AppColors.brandAccent),
          const Spacer(),
          if (summary.cashTotal > 0)
            Text(
              '${formatIQD(summary.cashTotal.round())} ${'common.currency'.tr()}',
              style: AppType.label(color: AppColors.textHi).copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label $count',
        style: AppType.muted(color: color).copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// One-row "تعيين الكل" — three ghost buttons that set the same
/// method on every renewable row. Mirrors v1's quick-set row.
class _SetAllRow extends StatelessWidget {
  const _SetAllRow({required this.onSetAll, required this.enabled});
  final ValueChanged<_PayMethod> onSetAll;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.xs),
      child: Row(
        children: [
          Text(
            'sheets.set_all'.tr(),
            style: AppType.muted(color: AppColors.textMid).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: Sp.sm),
          for (final m in _PayMethod.values) ...[
            Expanded(
              child: _SetAllBtn(
                method: m,
                enabled: enabled,
                onTap: () => onSetAll(m),
              ),
            ),
            if (m != _PayMethod.values.last) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}

class _SetAllBtn extends StatelessWidget {
  const _SetAllBtn({
    required this.method,
    required this.enabled,
    required this.onTap,
  });
  final _PayMethod method;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final color = method.color;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(method.icon, color: color, size: 12),
              const SizedBox(width: 3),
              Text(
                method.label,
                style: AppType.muted(color: color).copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RenewRowCard extends StatelessWidget {
  const _RenewRowCard({
    required this.row,
    required this.enabled,
    required this.onMethod,
    required this.onPartialChanged,
    required this.onPartialChip,
  });
  final _RenewRow row;
  final bool enabled;
  final ValueChanged<_PayMethod> onMethod;
  final VoidCallback onPartialChanged;
  final ValueChanged<int> onPartialChip;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (row.loadFailed) {
      return _FailedRowCard(
          sub: row.sub, reason: row.loadError, stopped: row.loadStopped);
    }
    final settled = row.status != BulkRowStatus.waiting &&
        row.status != BulkRowStatus.running;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(
          color: _statusBorderColor(row),
          width: settled ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header — name + price chip + status icon
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.sub.fullName,
                      style: AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.sub.profileName ?? row.sub.username,
                            style: AppType.muted(color: AppColors.textLow)
                                .copyWith(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _PriceChip(row: row),
              if (row.status != BulkRowStatus.waiting) ...[
                const SizedBox(width: 6),
                _RowStatusIcon(status: row.status),
              ],
            ],
          ),
          // Current balance line
          if (row.currentBalance != 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  row.currentBalance < 0
                      ? LucideIcons.creditCard
                      : LucideIcons.wallet,
                  size: 11,
                  color: row.currentBalance < 0
                      ? AppColors.error
                      : AppColors.brand,
                ),
                const SizedBox(width: 4),
                Text(
                  row.currentBalance < 0
                      ? '${'sheets.current_debt'.tr()} '
                      : '${'sheets.current_credit'.tr()} ',
                  style: AppType.muted(color: AppColors.textMid).copyWith(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${formatIQD(row.currentBalance.abs().round())} د.ع',
                  style: AppType.muted(
                    color: row.currentBalance < 0
                        ? AppColors.error
                        : AppColors.brand,
                  ).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // ⚠️ `SheetChoiceTiles` نفسها التي يستعملها شيت التفعيل المفرد
          // لا بلاطات خاصّة: نفس العمليّة بواجهتين تُربك، والخاصّة كانت
          // تُلوّن الحدّ بلون الطريقة فيبدو الصفّ ثلاثة تنبيهات متجاورة.
          // الطقم يُبرز المختار وحده ويُبقي الباقي محايداً.
          SheetChoiceTiles(
            labels: [
              for (final m in _PayMethod.values) m.label,
            ],
            icons: [
              for (final m in _PayMethod.values) m.icon,
            ],
            selectedIndex: _PayMethod.values.indexOf(row.method),
            enabled: enabled,
            onSelect: (i) => onMethod(_PayMethod.values[i]),
          ),
          if (row.method == _PayMethod.partial) ...[
            const SizedBox(height: 8),
            _PartialField(
              row: row,
              enabled: enabled,
              onChanged: onPartialChanged,
              onChip: onPartialChip,
            ),
          ],
          // Live after-balance preview when there's something to show
          if (row.method != _PayMethod.cash || row.currentBalance != 0) ...[
            const SizedBox(height: 6),
            _AfterRow(balanceAfter: row.balanceAfter),
          ],
          if (row.err != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                      row.status == BulkRowStatus.skipped
                          ? LucideIcons.info
                          : LucideIcons.triangleAlert,
                      size: 12,
                      color: _errColor(row.status)),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    row.err!,
                    style: AppType.muted(color: _errColor(row.status)).copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Color _statusBorderColor(_RenewRow r) => switch (r.status) {
        BulkRowStatus.done => AppColors.brandSoftBorder,
        BulkRowStatus.failed => AppColors.dangerSoftBorder,
        BulkRowStatus.unclear => AppColors.warningSoftBorder,
        BulkRowStatus.skipped => AppColors.borderStrong,
        _ => r.ready ? AppColors.brandSoftBorder : AppColors.border,
      };

  static Color _errColor(BulkRowStatus s) => switch (s) {
        BulkRowStatus.unclear || BulkRowStatus.done => AppColors.warning,
        BulkRowStatus.skipped => AppColors.textMid,
        _ => AppColors.error,
      };
}

/// حال الصفّ بعد الإرسال: تمّ · رُفض · غير مؤكّد · لم يُنفَّذ · جارٍ.
class _RowStatusIcon extends StatelessWidget {
  const _RowStatusIcon({required this.status});
  final BulkRowStatus status;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (status == BulkRowStatus.running) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppColors.brand),
      );
    }
    final (icon, color, label) = switch (status) {
      BulkRowStatus.done => (
          LucideIcons.circleCheck,
          AppColors.brand,
          'sheets.bulk_state_done'.tr()
        ),
      BulkRowStatus.failed => (
          LucideIcons.circleX,
          AppColors.error,
          'sheets.bulk_state_failed'.tr()
        ),
      BulkRowStatus.unclear => (
          LucideIcons.circleHelp,
          AppColors.warning,
          'sheets.bulk_state_unclear'.tr()
        ),
      _ => (
          LucideIcons.circleMinus,
          AppColors.textLow,
          'sheets.bulk_state_skipped'.tr()
        ),
    };
    return Icon(icon, color: color, size: 18, semanticLabel: label);
  }
}

class _FailedRowCard extends StatelessWidget {
  const _FailedRowCard({required this.sub, this.reason, this.stopped = false});
  final Subscriber sub;

  /// لماذا لم تُجلب بياناته — رسالة الخادم، أو «توقّف الجلب».
  final String? reason;

  /// وقف الجلب عند رفضٍ قاطع: السبب وحده (بلا «تعذّر جلب»)، وإطارٌ محايد.
  final bool stopped;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final why = (reason == null || reason!.trim().isEmpty) ? null : reason!.trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: stopped ? AppColors.surfaceSunken : AppColors.dangerSoftBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(
            color: stopped ? AppColors.border : AppColors.dangerSoftBorder),
      ),
      child: Row(
        children: [
          Icon(stopped ? LucideIcons.circleMinus : LucideIcons.triangleAlert,
              color: stopped ? AppColors.textLow : AppColors.error, size: 14),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sub.fullName,
                  style: AppType.label(color: AppColors.textHi).copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (stopped)
                  Text(
                    why ?? 'sheets.bulk_row_not_fetched'.tr(),
                    style: AppType.muted(color: AppColors.textMid).copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Text(
                    'sheets.bulk_row_fetch_failed'.tr(),
                    style: AppType.muted(color: AppColors.error).copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (!stopped && why != null)
                  Text(
                    why,
                    style: AppType.muted(color: AppColors.textMid).copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({required this.row});
  final _RenewRow row;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final hasDiscount = row.discount > 0 && row.discount < row.originalPrice;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.warningSoftBg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(
          color: AppColors.warningSoftBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasDiscount) ...[
            Text(
              formatIQD(row.originalPrice.round()),
              style: AppType.muted(color: AppColors.textLow).copyWith(
                fontSize: 9.5,
                decoration: TextDecoration.lineThrough,
              ),
            ),
            const SizedBox(width: 3),
          ],
          Text(
            '${formatIQD(row.effectivePrice.round())} د.ع',
            style: AppType.muted(color: AppColors.warning).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PartialField extends StatelessWidget {
  const _PartialField({
    required this.row,
    required this.enabled,
    required this.onChanged,
    required this.onChip,
  });
  final _RenewRow row;
  final bool enabled;
  final VoidCallback onChanged;
  final ValueChanged<int> onChip;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final accent = AppColors.brandAccent;
    final price = row.effectivePrice.round();
    final chips = const [5000, 10000, 15000, 25000, 35000, 50000]
        .where((c) => c < price)
        .toList();
    // Hint when the partial amount exceeds the package price — the
    // excess will be credited to the subscriber's balance (matches
    // v1's behaviour). Informational only; doesn't block submission.
    final overshoot = row.partialAmount > price;
    // Wire onChanged once via a listener — but since the parent already
    // calls onChanged via _onPartialChanged on every controller event,
    // we don't add another listener here; we just render the field.
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'sheets.paid_cash_amount'.tr(),
            style: AppType.label(color: AppColors.textHi).copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          _PartialTextField(
            controller: row.partialCtrl,
            enabled: enabled,
            onChanged: onChanged,
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final amount in chips)
                  InkWell(
                    onTap: enabled
                        ? () {
                            HapticFeedback.selectionClick();
                            onChip(amount);
                          }
                        : null,
                    borderRadius: BorderRadius.circular(R.pill),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.pill),
                        border: Border.all(
                          color: accent.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        formatIQD(amount),
                        style: AppType.muted(color: accent).copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (overshoot) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(LucideIcons.info, size: 11, color: AppColors.success),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'sheets.overpay_becomes_credit'.tr(namedArgs: {
                      'amt':
                          '${formatIQD((row.partialAmount - price).round())} ${'common.currency'.tr()}'
                    }),
                    style: AppType.muted(color: AppColors.success).copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Tiny dedicated text-field widget so the controller listener fires
/// every keystroke without re-creating the InputDecoration on each
/// parent rebuild.
class _PartialTextField extends StatefulWidget {
  const _PartialTextField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  State<_PartialTextField> createState() => _PartialTextFieldState();
}

class _PartialTextFieldState extends State<_PartialTextField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_relay);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_relay);
    super.dispose();
  }

  void _relay() => widget.onChanged();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // ⚠️ `AmountTextField` نفسها التي يستعملها شيت المشترك المفرد لا
    // حقلاً خاماً: نفس العمليّة بواجهتين مختلفتين تُربك، والخام كان
    // بنصف قطر `R.sm` وحدٍّ مسطّح بينما المفرد مستدير. واختصار المبلغ
    // (25 ← 25,000) بداخلها فلا يُعاد تركيبه هنا.
    return AmountTextField(
      controller: widget.controller,
      enabled: widget.enabled,
      currency: 'common.currency'.tr(),
      hint: 'sheets.amount_example_10k'.tr(),
      onValue: (_) => _relay(),
    );
  }
}

class _AfterRow extends StatelessWidget {
  const _AfterRow({required this.balanceAfter});
  final double balanceAfter;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final isDebt = balanceAfter < 0;
    final color = isDebt ? AppColors.error : AppColors.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.arrowRight, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            'sheets.after_renewal'.tr(),
            style: AppType.label(color: AppColors.textHi).copyWith(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            isDebt
                ? '${'subscribers.debt_short'.tr()} '
                : '${'subscribers.balance_short'.tr()} ',
            style: AppType.muted(color: color).copyWith(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '${formatIQD(balanceAfter.abs().round())} د.ع',
            style: AppType.label(color: color).copyWith(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ───────── shared sheet chrome (copy of activate_sheet's) ─────────
