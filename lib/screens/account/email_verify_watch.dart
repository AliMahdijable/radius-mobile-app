import 'dart:async';

/// مراقب تأكيد البريد — المالك ١٥ نوفمبر («تمام سوي الحل المجاني»): التطبيق يكتشف وحده أنّ صاحب الحساب ضغط رابط التأكيد
/// ويكمل، بدل أن يرجع ويضغط «أكّدت بريدي» بيده.
///
/// يسأل [probe] (قراءة الحساب من جديد): فوراً عند [checkNow] (الرجوع للتطبيق — اللحظة الغالبة: فتح الرابط بالمتصفّح ثمّ
/// عاد)، ودوريّاً ما دام يعمل — كلّ [fast] في أوّل [fastFor] ثمّ كلّ [slow]، ويتوقّف وحده بعد [maxFor] (الزرّ اليدويّ والرجوع
/// للتطبيق يبقيان). لا فحصان معاً: الموعد التالي يُضرب بعد انتهاء الفحص. فشل الفحص أو تأخّره صامت — يُعاد في موعده.
/// أوّل `true` يوقفه ويستدعي [onVerified] مرّةً واحدة؛ إن ردّ [onVerified] بـ`false` (الشاشة ليست في الأمام الآن) عاد يراقب.
class EmailVerifyWatch {
  EmailVerifyWatch({
    required this.probe,
    required this.onVerified,
    this.fast = const Duration(seconds: 4),
    this.slow = const Duration(seconds: 10),
    this.fastFor = const Duration(minutes: 2),
    this.maxFor = const Duration(minutes: 15),
    this.probeTimeout = const Duration(seconds: 10),
  });

  final Future<bool> Function() probe;

  /// تأكّد البريد. `false` = لم يُستعمل الآن (نافذةٌ فوق الشاشة) ⇒ تستمرّ المراقبة ويُعاد في الموعد التالي.
  final bool Function() onVerified;
  final Duration fast;
  final Duration slow;
  final Duration fastFor;
  final Duration maxFor;
  final Duration probeTimeout;

  Timer? _timer;

  /// ما مضى من المدّة = مجموع المواعيد التي حلّت (لا ساعة حائط: يُختبر بزمنٍ وهميّ، ولا يتأثّر بنوم الجهاز).
  Duration _elapsed = Duration.zero;
  bool _running = false;
  bool _probing = false;

  /// يُبطل فحصاً عاد بعد [stop].
  int _epoch = 0;

  /// يراقب الآن (موعدٌ مضروب أو فحصٌ جارٍ ضمن المدّة).
  bool get running => _running;

  /// يبدأ المراقبة (أو يجدّد مدّتها إن كانت تعمل) — أوّل فحصٍ بعد [fast].
  void start() {
    _running = true;
    _elapsed = Duration.zero;
    _schedule();
  }

  void stop() {
    _running = false;
    _epoch++;
    _probing = false;
    _timer?.cancel();
    _timer = null;
  }

  /// فحصٌ الآن (الرجوع للتطبيق) — ويجدّد المدّة: من عاد بعد ربع ساعة يُراقَب من جديد.
  Future<void> checkNow() {
    start();
    return _probe();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (!_running) return;
    if (_elapsed >= maxFor) {
      // انتهت المدّة: لا مواعيد بعدها حتى [start] أو [checkNow]
      _running = false;
      return;
    }
    final wait = _elapsed < fastFor ? fast : slow;
    _timer = Timer(wait, () {
      _elapsed += wait;
      _probe();
    });
  }

  Future<void> _probe() async {
    if (!_running || _probing) return;
    _probing = true;
    final epoch = _epoch;
    var ok = false;
    try {
      ok = await probe().timeout(probeTimeout);
    } catch (_) {
      // شبكةٌ أو مهلة: صامت — الزرّ اليدويّ باقٍ والموعد التالي قادم
    }
    if (epoch != _epoch) return;
    _probing = false;
    if (ok && onVerified()) {
      stop();
      return;
    }
    _schedule();
  }
}
