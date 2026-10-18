import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../api/subscribers_api.dart';

// ═══════════════════════════════════════════════════════════════════════
// حارس التجديد الجماعيّ — المنطق وحده (بلا واجهة)، فيُختبر بخادمٍ وهميّ.
//
// SAS4 بلا API جماعيّ: الدفعة حلقةُ `activate` صفّاً صفّاً، وكلّ صفٍّ مالٌ
// حقيقيّ يخرج من رصيد المدير. فالقواعد:
//   ١) **تقف الدفعة عند أوّل رفضٍ قاطع** — جلسةٌ انتهت (401)، صلاحيّةٌ
//      ناقصة أو ساسٌ لا يفعّل من الرصيد (403)، رصيدٌ لا يكفي، رفضٌ صريحٌ
//      للدفعة من الخادم — فما يُرفض لصفٍّ سيُرفض للباقين، ومئة نداءٍ فاشل
//      لا تخبر المدير شيئاً لم يخبره الأوّل. أمّا الرفض الذي يخصّ صفّاً
//      بعينه (باقةٌ لا تُفعَّل له…) فلا يوقف غيره ولو تتالى — كالويب؛ وإلّا
//      حبست ثلاثةُ صفوفٍ مرفوضة «تجديد الباقين» إلى الأبد (مراجعة ١٨ أكتوبر).
//   ٢) **«لا نعرف» تقف أيضاً**: ردٌّ لم يصل أو لم يتأكّد (ربّما تفعّل) لا
//      يُبنى فوقه تفعيلٌ آخر، ولا يُعاد ذلك الصفّ آليّاً أبداً.
//      وجلسة الساس المنتهية في الجماعيّ (409 `SAS_SESSION_EXPIRED` — لم
//      يُكتب شيء لذلك الصفّ) تُجدَّد كما يفعل المعترض عند 401 ويُعاد الصفّ
//      مرّةً واحدة ([activateWithSessionRetry]).
//   ٣) **تزامنٌ محدود**: الجلب المسبق (قراءة) بأربعة معاً، والتفعيل في
//      الورقة واحدٌ تلو واحد — كما يفعل الساس نفسه؛ تفعيلان معاً على رصيدٍ
//      واحد قد يتجاوزان فحص الرصيد عنده.
//   ٤) **فحصٌ مسبق للرصيد** حين يُعرف الرصيد والكلفة: دفعةٌ لا يكفيها
//      الرصيد يُعرض قصرُها على ما يكفيه قبل أن تبدأ (تنبيهٌ لا منع — بعض
//      الساسات تسمح برصيدٍ سالب، فـ«جرّب الكلّ» يبقى والساس يحكم).
// ═══════════════════════════════════════════════════════════════════════

/// حال الصفّ في دفعة التجديد.
enum BulkRowStatus {
  /// لم يُرسَل بعد.
  waiting,

  /// يُرسَل الآن.
  running,

  /// تمّ التفعيل.
  done,

  /// رُفض — لم يُفعَّل (قالها الخادم أو الساس صراحةً).
  failed,

  /// لا نعرف إن تفعّل — يُراجَع انتهاؤه قبل أيّ إعادة، ولا يُعاد آليّاً
  /// (ومنه محاولةٌ سابقة عليه لم يُعرف إن نُفّذت — حارس التكرار).
  unclear,

  /// لم يُنفَّذ: توقّفت الدفعة قبله، أو لا يكفيه الرصيد، أو فُعِّل قبل
  /// لحظات (حارس التكرار)، أو عمليّةٌ أخرى جاريةٌ عليه.
  skipped,
}

/// لماذا وقفت الدفعة.
enum BulkStopKind {
  /// 401، أو 409 `SAS_SESSION_EXPIRED` — انتهت جلسة الساس/التطبيق.
  session,

  /// 403 — صلاحيّةٌ ناقصة أو حسابٌ في الساس لا يفعّل من الرصيد.
  permission,

  /// رصيد المدير في الساس لا يكفي.
  balance,

  /// رفضٌ صريحٌ للدفعة (رمز `BULK_*`، طريقةٌ مطلوبة، طلباتٌ كثيرة 429،
  /// اشتراكٌ منتهٍ 402…).
  refused,

  /// ردٌّ غير مؤكّد — ربّما تفعّل؛ لا يُكمَل فوقه.
  unclear,

  /// أوقفها المستخدم.
  cancelled,
}

/// حكم صفٍّ واحد: حاله، وهل تقف الدفعة بعده، ورسالة الخادم إن وُجدت.
@immutable
class BulkStep {
  const BulkStep(this.status, {this.stop, this.message});
  final BulkRowStatus status;

  /// غير `null` ⇒ لا يُرسَل صفٌّ آخر بعد هذا.
  final BulkStopKind? stop;
  final String? message;

  @override
  String toString() => 'BulkStep($status, stop: $stop, message: $message)';
}

/// رموز «انتهت الجلسة» — الجماعيّ يأخذ جلسة الساس المنتهية 409
/// `SAS_SESSION_EXPIRED` لا 401 (فلا يطرده المعترض في منتصف الدفعة).
const bulkSessionCodes = {'SAS_SESSION_EXPIRED', 'SESSION_SUPERSEDED'};

/// رموز «رصيدٌ لا يكفي» (422 `INSUFFICIENT_BALANCE` من رفض الساس).
const bulkBalanceCodes = {'INSUFFICIENT_BALANCE'};

/// رموز «لا يملك هذا الحساب هذه العمليّة» — ومنها 409
/// `BULK_ACTIVATE_UNSUPPORTED` (حسابٌ في الساس يفعّل بالكارت وحده، أو بلا
/// صلاحيّة التفعيل من الرصيد): حكمٌ على الحساب لا على الصفّ.
const bulkPermissionCodes = {
  'PERMISSION_DENIED',
  'CREDIT_NOT_ALLOWED',
  'CARD_NOT_ALLOWED',
  'BULK_ACTIVATE_UNSUPPORTED',
  'EMPLOYEE_ACCESS_DENIED',
  'EMPLOYEE_DISABLED',
};

/// رفضٌ لا يتغيّر من صفٍّ لصفّ — لا معنى لإكمال الدفعة بعده. وكلّ رمزٍ
/// آخر يبدأ بـ`BULK_` منها.
const bulkRefusedCodes = {
  'EL_METHOD_REQUIRED',
  'NO_CARDS',
  'CARDS_HELD',
};

/// «ربّما تفعّل» — لا يُعاد ولا يُكمَل فوقه.
const bulkUnclearCodes = {
  SubscribersApi.activateOutcomeUnknown,
  'NOT_CONFIRMED',
};

/// تمّ التفعيل في الساس وتعذّر ما بعده (الدين/السجلّ) — تمّ بتنبيه، لا يُعاد،
/// والدفعة تكمل: ما تعثّر بعد التفعيل يخصّ هذا الصفّ (والقاعدة المعطّلة
/// تُرفض قبل الساس في الصفّ التالي، فلا تتكرّر).
const bulkAppliedWithErrors = 'APPLIED_WITH_ERRORS';

/// لم يُنفَّذ لهذا الصفّ وحده — يُكمَل غيره: فُعِّل قبل لحظات (حارس التكرار
/// في الخادم)، أو عمليّةٌ أخرى جاريةٌ عليه الآن (لم يُرسَل للساس شيء).
const bulkSkipCodes = {'RECENT_DUPLICATE', 'IN_PROGRESS'};

/// حارس التكرار في الخادم.
const bulkRecentDuplicate = 'RECENT_DUPLICATE';

/// جلسة الساس المنتهية في الجماعيّ (409 لا 401 — فلا يجدّد المعترض وحده).
const bulkSasSessionExpired = 'SAS_SESSION_EXPIRED';

/// حدّ الدفعة حين لا يقوله الخادم (خادمٌ أقدم، أو حكمٌ مجهول) — حدّ الخادم
/// نفسه (`MAX_BATCH` في server/bulkActivateGuard.js)، كالويب. ما بعده من
/// التحديد لا يُرفض: يبقى محدّداً للدفعة التالية.
const bulkDefaultMaxBatch = 100;

/// يحكم على ردّ تفعيلٍ واحد داخل دفعة.
BulkStep judgeBulkActivate(ActivateOutcome o) {
  final r = o.result;
  if (r.ok) return const BulkStep(BulkRowStatus.done);
  final code = (r.code ?? '').trim().toUpperCase();
  final sas = (o.sas4Code ?? '').trim().toLowerCase();
  final status = o.status ?? 0;
  final msg = (r.message == null || r.message!.trim().isEmpty)
      ? null
      : r.message!.trim();
  if (code == bulkAppliedWithErrors) {
    return BulkStep(BulkRowStatus.done, message: msg);
  }
  // محاولةٌ سابقة عليه لم يُعرف إن نُفّذت (حارس التكرار، `last.uncertain`):
  // لا «لم يُنفَّذ» يوحي بأنّه آمنٌ للإعادة — غير مؤكّد برسالة الخادم. والطلب
  // نفسه لم يلمس الساس، فالدفعة تكمل (كالويب).
  if (code == bulkRecentDuplicate && o.lastUncertain) {
    return BulkStep(BulkRowStatus.unclear, message: msg);
  }

  // ربّما تفعّل: بلا ردّ، أو رمزٌ يقوله، أو بوّابةٌ قطعت الطلب (5xx من
  // الوسيط — خادمنا لا يصدر 5xx لرفضٍ معروف، وقد يكون أكمله بعد القطع).
  if (o.noReply || bulkUnclearCodes.contains(code) || status >= 500) {
    return BulkStep(BulkRowStatus.unclear,
        stop: BulkStopKind.unclear, message: msg);
  }
  if (bulkSkipCodes.contains(code)) {
    return BulkStep(BulkRowStatus.skipped, message: msg);
  }
  if (status == 401 || bulkSessionCodes.contains(code)) {
    return BulkStep(BulkRowStatus.failed,
        stop: BulkStopKind.session, message: msg);
  }
  if (bulkBalanceCodes.contains(code) || sas == 'rsp_insufficient_balance') {
    return BulkStep(BulkRowStatus.failed,
        stop: BulkStopKind.balance, message: msg);
  }
  if (status == 403 || bulkPermissionCodes.contains(code)) {
    return BulkStep(BulkRowStatus.failed,
        stop: BulkStopKind.permission, message: msg);
  }
  // 402 = اشتراك MyServices انتهى (`subscription-ended`) — لا رصيد الساس.
  if (status == 402 ||
      status == 429 ||
      sas == 'rsp_rate_limited' ||
      bulkRefusedCodes.contains(code) ||
      code.startsWith('BULK_')) {
    return BulkStep(BulkRowStatus.failed,
        stop: BulkStopKind.refused, message: msg);
  }
  // رفضٌ يخصّ هذا الصفّ (باقةٌ لا تُفعَّل له، مشتركٌ غير موجود…) — يُكمَل غيره.
  return BulkStep(BulkRowStatus.failed, message: msg);
}

/// حصيلة الدفعة: ما تمّ وما رُفض وما لا يُعرف وما لم يُنفَّذ، ولماذا وقفت.
class BulkRunReport {
  int done = 0;
  int failed = 0;
  int unclear = 0;
  int skipped = 0;

  /// `null` = أكملت الدفعة كلّها.
  BulkStopKind? stoppedBy;

  /// رسالة الخادم عند التوقّف.
  String? stopMessage;

  bool get stopped => stoppedBy != null;
  int get total => done + failed + unclear + skipped;

  void _count(BulkRowStatus s) {
    switch (s) {
      case BulkRowStatus.done:
        done++;
      case BulkRowStatus.failed:
        failed++;
      case BulkRowStatus.unclear:
        unclear++;
      case BulkRowStatus.skipped:
        skipped++;
      case BulkRowStatus.waiting:
      case BulkRowStatus.running:
        break;
    }
  }

  @override
  String toString() => 'BulkRunReport(done: $done, failed: $failed, '
      'unclear: $unclear, skipped: $skipped, stoppedBy: $stoppedBy)';
}

/// سقف التفعيلات المتزامنة في [runBulkActivations] مهما طُلب — والورقة
/// تطلب واحداً (كلوحة الساس والويب).
const bulkMaxActivateConcurrency = 3;

/// تزامن الجلب المسبق (قراءة activation-data — نداءان للساس لكلّ صفّ)،
/// ما لم يحدّده الخادم (`limits.prefetch_concurrency`)، وسقفه مهما قال.
const bulkPrefetchConcurrency = 4;
const bulkMaxPrefetchConcurrency = 6;

/// يرسل صفّاً، فإن قال الخادم «انتهت جلسة الساس» (409
/// `SAS_SESSION_EXPIRED` — رفضٌ قبل أيّ كتابة، لم يُفعَّل ذلك الصفّ) جدّد
/// الجلسة بـ[refresh] — المسار الذي يسلكه المعترض عند 401 — وأعاد الصفّ
/// **مرّةً واحدة**. تجديدٌ مرفوض (موظّف، جلسةٌ ميتة) أو متعثّر أو رامٍ ⇒
/// الردّ الأوّل كما هو، فتقف الدفعة بالجلسة. لا حلقة: إعادةٌ واحدة ثمّ حكمها.
Future<ActivateOutcome> activateWithSessionRetry({
  required Future<ActivateOutcome> Function() send,
  required Future<bool> Function() refresh,
}) async {
  final first = await send();
  if (first.result.ok ||
      (first.result.code ?? '').trim().toUpperCase() != bulkSasSessionExpired) {
    return first;
  }
  bool renewed;
  try {
    renewed = await refresh();
  } catch (_) {
    renewed = false;
  }
  if (!renewed) return first;
  return send();
}

/// يشغّل الدفعة: [concurrency] عاملاً (محدودٌ بـ[bulkMaxActivateConcurrency])
/// يسحبون الصفوف بالترتيب. بعد أوّل حكمٍ يقف (`BulkStep.stop`) أو طلب
/// [shouldStop] لا يُرسَل صفٌّ جديد — وما لم يُرسَل يُعلَّم `skipped`. والرفض
/// الذي يخصّ صفّاً بعينه لا يوقف غيره، ولو تتالى.
///
/// [onStart] قبل إرسال الصفّ، و[onStep] بحكمه. [activate] لا يُفترض أن
/// يرمي؛ إن رمى فالصفّ «لا نعرف» والدفعة تقف (لا نعرف إن وصل الطلب).
Future<BulkRunReport> runBulkActivations<T>({
  required List<T> items,
  required Future<ActivateOutcome> Function(T item) activate,
  required void Function(T item, BulkStep step) onStep,
  void Function(T item)? onStart,
  int concurrency = 1,
  bool Function()? shouldStop,
}) async {
  final report = BulkRunReport();
  final workers = math.max(1, math.min(concurrency, bulkMaxActivateConcurrency));
  var next = 0;

  bool halted() {
    if (report.stopped) return true;
    if (shouldStop?.call() ?? false) {
      report.stoppedBy = BulkStopKind.cancelled;
      return true;
    }
    return false;
  }

  Future<void> worker() async {
    while (!halted() && next < items.length) {
      final item = items[next++];
      onStart?.call(item);
      BulkStep step;
      try {
        step = judgeBulkActivate(await activate(item));
      } catch (_) {
        step = const BulkStep(BulkRowStatus.unclear, stop: BulkStopKind.unclear);
      }
      report._count(step.status);
      if (step.stop != null && !report.stopped) {
        report.stoppedBy = step.stop;
        report.stopMessage = step.message;
      }
      onStep(item, step);
    }
  }

  await Future.wait([for (var i = 0; i < workers; i++) worker()]);
  // ما لم يُرسَل قطّ — لم يُنفَّذ.
  for (var i = next; i < items.length; i++) {
    const step = BulkStep(BulkRowStatus.skipped);
    report._count(step.status);
    onStep(items[i], step);
  }
  return report;
}

/// يجلب لكلّ عنصر بتزامنٍ محدود ([concurrency])، ويقف عن طلب الجديد حين
/// يقول [stopAfter] إنّ الردّ قاطعٌ للجميع (401/403) أو يطلب [shouldStop].
/// يُعيد ما جُلب بترتيب [items] (`null` لما لم يُطلب). [onEach] لكلّ ردّ.
Future<List<R?>> boundedFetch<T, R>({
  required List<T> items,
  required Future<R> Function(T item) fetch,
  int concurrency = bulkPrefetchConcurrency,
  bool Function(R result)? stopAfter,
  bool Function()? shouldStop,
  void Function(int index, R result)? onEach,
}) async {
  final out = List<R?>.filled(items.length, null);
  var next = 0;
  var stopped = false;
  Future<void> worker() async {
    while (!stopped && next < items.length) {
      if (shouldStop?.call() ?? false) {
        stopped = true;
        return;
      }
      final i = next++;
      final r = await fetch(items[i]);
      out[i] = r;
      onEach?.call(i, r);
      if (stopAfter?.call(r) ?? false) stopped = true;
    }
  }

  final n = math.max(1, math.min(concurrency, items.length));
  await Future.wait([for (var i = 0; i < n; i++) worker()]);
  return out;
}

/// هل يكفي رصيد المدير الدفعة؟ — حين يُعرف الرصيد والكلفة فقط.
///
/// الكلفة = ما يخصمه الساس من رصيد المدير لكلّ صفّ (`manager_cost`)، لا
/// سعر المشترك. كلفةٌ مجهولة لصفٍّ ⇒ المجموع حدٌّ أدنى: إن تجاوز الرصيد
/// فالدفعة لا تكفي يقيناً، وإلّا فلا حكم (يحكم الساس صفّاً صفّاً).
@immutable
class BulkPreflight {
  const BulkPreflight._({
    required this.balance,
    required this.knownCost,
    required this.unknownCost,
    required this.count,
    required this.fitCount,
  });

  /// رصيد المدير — `null` = لا نعرف.
  final double? balance;

  /// مجموع الكلف المعروفة.
  final double knownCost;

  /// صفوفٌ كلفتها مجهولة.
  final int unknownCost;

  /// صفوف الدفعة.
  final int count;

  /// كم صفّاً من رأس الدفعة (بترتيبها) يكفيه الرصيد يقيناً. `null` = لا حكم.
  final int? fitCount;

  bool get costKnown => unknownCost == 0;

  /// لا يكفي يقيناً: حتّى المعروف من الكلفة يتجاوز الرصيد.
  bool get insufficient => balance != null && knownCost > balance! + _eps;

  /// يكفي يقيناً: الكلفة كلّها معروفة ولا تتجاوز الرصيد.
  bool get sufficient =>
      balance != null && costKnown && knownCost <= balance! + _eps;

  /// العجز حين لا يكفي.
  double? get shortfall => insufficient ? knownCost - balance! : null;

  static const _eps = 0.5;

  static BulkPreflight compute({
    required double? balance,
    required List<double?> costs,
  }) {
    var known = 0.0;
    var unknown = 0;
    for (final c in costs) {
      if (c == null || !c.isFinite || c <= 0) {
        unknown++;
      } else {
        known += c;
      }
    }
    int? fit;
    if (balance != null) {
      // من رأس الدفعة: يُعدّ ما دامت كلفته معروفة والرصيد يكفيه. أوّل كلفةٍ
      // مجهولة توقف العدّ — بعدها لا نعرف.
      var sum = 0.0;
      var n = 0;
      for (final c in costs) {
        if (c == null || !c.isFinite || c <= 0) break;
        if (sum + c > balance + _eps) break;
        sum += c;
        n++;
      }
      fit = n;
    }
    return BulkPreflight._(
      balance: balance,
      knownCost: known,
      unknownCost: unknown,
      count: costs.length,
      fitCount: fit,
    );
  }

  @override
  String toString() => 'BulkPreflight(balance: $balance, knownCost: $knownCost, '
      'unknownCost: $unknownCost, count: $count, fitCount: $fitCount)';
}

/// رقمٌ من قيمة الخادم («IQD 3,120,000.00»، «46000»، 30) — وغير الرقم `null`.
double? bulkNumOrNull(Object? v) {
  if (v == null || v is bool) return null;
  if (v is num) return v.isFinite ? v.toDouble() : null;
  final s = v.toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
  if (s.isEmpty || s == '-' || s == '.') return null;
  final n = double.tryParse(s);
  return (n == null || !n.isFinite) ? null : n;
}
