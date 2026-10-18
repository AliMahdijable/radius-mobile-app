import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/self_deposit_api.dart';
import 'app_resumed_signal.dart';
import 'auth_storage.dart';
import 'self_deposit_pending.dart';

/// ما انتهت إليه جولة تسليم.
@immutable
class SelfDepositSyncReport {
  const SelfDepositSyncReport(this.results, {this.ran = true});
  const SelfDepositSyncReport.skipped()
      : results = const [],
        ran = false;

  /// كلّ رابط رجوعٍ أُرسل وحكم الخادم فيه — الأقدم أوّلاً.
  final List<(SelfDepositPending, SelfDepositOutcome)> results;

  /// `false` = لم تُجرَ (لا جلسة، أو مهلة الجولات، أو لا شيء معلّق).
  final bool ran;

  /// رابطٌ ما زال على الهاتف لم يستلمه الخادم (انقطاع/مشغول).
  bool get pendingLeft => results.any((r) => !r.$2.settled);
}

/// «لا يضيع توكن» — يسلّم روابط رجوع زين كاش المحفوظة على الهاتف إلى خادمنا
/// **مستقلّاً عن شاشة الشحن وعن مفتاح الميزة** (الخادم يُبقي `complete` مفتوحاً
/// ولو أُطفئت الميزة):
///   • عند الإقلاع ([start] من main.dart، بعد ثوانٍ تستعيد فيها الجلسة توكنها)؛
///   • عند العودة للواجهة ([AppResumedSignal])؛
///   • عند الاستماع لبطاقة «قوائم أخرى» وفتح شاشة الشحن و«تحقّق الآن»؛
///   • وبإعادةٍ متباعدة ([retryDelays]) ما دام التطبيق حيّاً بعد رجوعٍ لم يصل.
///
/// **كلّ** قيدٍ فيه رابط رجوع يُرسل (لا أحدث ثلاثة)، الأقدم أوّلاً، ويُمحى حين
/// يقول الخادم إنّه استلمه أو حسمه ([SelfDepositOutcome.settled]) — لا بردٍّ بلا
/// صفّ، ولا بانقطاع. الخادم يمنع الرمز نفسه مرّتين (بصمةٌ فريدة)، فالتكرار آمن.
class SelfDepositSync {
  SelfDepositSync._();

  static bool _installed = false;
  static Future<SelfDepositSyncReport>? _running;
  static DateTime? _lastRun;
  static Timer? _retry;
  static int _retryStep = 0;

  /// أقلّ فاصلٍ بين جولتين آليّتين (عودةٌ للواجهة/البطاقة) — [run] بـ`force`
  /// (شاشة الشحن، «تحقّق الآن»، الإعادة المتباعدة) يتجاوزه.
  static const cooldown = Duration(seconds: 45);

  /// الإعادة بعد رجوعٍ لم يصل الخادم، ما دام التطبيق مفتوحاً (بديلُ «عاد
  /// الاتّصال»). تنتهي بالقائمة، وتبدأ من أوّلها بعد أيّ جولةٍ بلا انقطاع.
  @visibleForTesting
  static List<Duration> retryDelays = const [
    Duration(seconds: 20),
    Duration(minutes: 1),
    Duration(minutes: 3),
    Duration(minutes: 10),
  ];

  /// يزيد كلّما حُسم رجوعٌ أو استُلم — شاشة الشحن تستمع فتحدّث سجلّها، وتقرأ
  /// [lastReport] لتعرض النتيجة.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// آخر جولةٍ أرسلت شيئاً.
  static SelfDepositSyncReport? lastReport;

  /// من main.dart مرّةً عند الإقلاع.
  static void start() {
    install();
    Future<void>.delayed(const Duration(seconds: 5), () => run());
  }

  /// يربط مصادر التشغيل الآليّة — آمنٌ للتكرار.
  static void install() {
    if (_installed) return;
    _installed = true;
    AppResumedSignal.tick.addListener(_onResume);
    SelfDepositState.onListen = () => unawaited(run());
    SelfDepositState.onReset = resetSession;
  }

  static void _onResume() => unawaited(run());

  /// جولة تسليم. طلبٌ جارٍ واحد على الأكثر (من يطلب أثناءه يأخذ نتيجته).
  static Future<SelfDepositSyncReport> run({bool force = false}) {
    final running = _running;
    if (running != null) return running;
    final last = _lastRun;
    if (!force && last != null && DateTime.now().difference(last) < cooldown) {
      return Future.value(const SelfDepositSyncReport.skipped());
    }
    late final Future<SelfDepositSyncReport> f;
    f = _run().whenComplete(() {
      if (identical(_running, f)) _running = null;
    });
    _running = f;
    return f;
  }

  static Future<SelfDepositSyncReport> _run() async {
    _lastRun = DateTime.now();
    String? adminId;
    String? token;
    try {
      adminId = await AuthStorage.readAdminId();
      token = await AuthStorage.readToken();
    } catch (_) {
      return const SelfDepositSyncReport.skipped();
    }
    if (adminId == null || adminId.isEmpty || token == null || token.isEmpty) {
      return const SelfDepositSyncReport.skipped();
    }
    final items = [
      for (final p in await SelfDepositPendingStore.forAdmin(adminId))
        if (p.returnUrl != null) p,
    ];
    if (items.isEmpty) {
      _stopRetry();
      return const SelfDepositSyncReport.skipped();
    }
    final results = <(SelfDepositPending, SelfDepositOutcome)>[];
    for (final p in items) {
      final o = await SelfDepositApi.complete(psid: p.psid, returnUrl: p.returnUrl!);
      if (o.settled) await SelfDepositPendingStore.remove(p.psid);
      results.add((p, o));
    }
    final report = SelfDepositSyncReport(results);
    lastReport = report;
    if (results.any((r) => r.$2.settled)) changes.value = changes.value + 1;
    if (results.any((r) => r.$2.offline)) {
      retrySoon();
    } else {
      _stopRetry();
    }
    return report;
  }

  /// رجوعٌ لم يصل الخادم: إعادةٌ متباعدة ما دام التطبيق مفتوحاً.
  static void retrySoon() {
    if (_retry != null) return;
    final delays = retryDelays;
    if (_retryStep >= delays.length) return;
    final d = delays[_retryStep++];
    _retry = Timer(d, () {
      _retry = null;
      unawaited(run(force: true));
    });
  }

  static void _stopRetry() {
    _retry?.cancel();
    _retry = null;
    _retryStep = 0;
  }

  /// مسح الجلسة: تتوقّف الإعادات (القيود باقية لصاحبها ويُسلَّم ما فيها عند
  /// دخوله التالي).
  static void resetSession() {
    _stopRetry();
    _lastRun = null;
  }

  @visibleForTesting
  static void debugReset() {
    _stopRetry();
    _lastRun = null;
    _running = null;
    lastReport = null;
    if (_installed) {
      AppResumedSignal.tick.removeListener(_onResume);
      SelfDepositState.onListen = null;
      SelfDepositState.onReset = null;
      _installed = false;
    }
  }
}
