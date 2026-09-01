import 'dart:async';
import 'dart:collection';

/// مجدول الجلسات العميقة — سقفٌ عالميّ لما يفتحه الهاتف معاً.
///
/// ── لماذا سقف أصلاً ───────────────────────────────────────────────
/// الجلسة العميقة (معالج/ذاكرة/إشارة) تحتاج اتّصالاً كاملاً بالجهاز:
/// SSH لـUBNT (تبادل مفاتيح بـDart خالص، بلا تعجيل عتاديّ)، أو TCP
/// 8728 لميكروتك، أو SNMP لميموزا. وأكبر حساب فيه ثمانون جهازاً، ٧٤
/// منها UBNT. ثمانون مصافحةً معاً تُجمّد الواجهة — وهي أزمة الـANR
/// نفسها التي أُصلحت في آب.
///
/// ── لماذا مجدول لا مجرّد سقف في الحلقة ───────────────────────────
/// الجدار لا يملك حلقة: بطاقاته تُبنى وتُهدم مع التمرير، وكلٌّ منها
/// يطلب جلسته بنفسها. فالسقف يجب أن يكون **عالميّاً عبر البطاقات**،
/// لا داخل دالّة واحدة.
///
/// ── الإلغاء هو نصف الفائدة ───────────────────────────────────────
/// بطاقة خرجت من الشاشة قبل أن يحين دورها تُسحب من الطابور ولا تُفتح
/// لها جلسة أصلاً. بلا هذا يبقى التمرير السريع يفتح جلساتٍ لأجهزةٍ لم
/// يعد أحد ينظر إليها.
class DeepProbeScheduler {
  DeepProbeScheduler._();
  static final DeepProbeScheduler instance = DeepProbeScheduler._();

  /// ستّ جلسات — عدد البطاقات المرئيّة على شاشة هاتف تقريباً.
  ///
  /// وهي كلفة لوحة جهاز واحد اليوم مضروبة بستّة، لا بثمانين.
  static const maxConcurrent = 6;

  final Queue<_Job> _pending = Queue<_Job>();
  int _active = 0;

  int get activeCount => _active;
  int get pendingCount => _pending.length;

  /// يُدرج مهمّة باسم [owner]. المالك مفتاح الإلغاء — مرّر البطاقة
  /// نفسها (`this` من الـState) فيسهل سحبها عند التخلّص منها.
  ///
  /// مهمّة بنفس المالك تُلغي سابقتها المنتظِرة: بطاقة تُعيد الطلب مع
  /// كلّ نبضة مؤقّت، ولا معنى لتكديس طلبين لنفس الجهاز.
  void submit(Object owner, Future<void> Function() job) {
    _pending.removeWhere((j) => identical(j.owner, owner));
    _pending.add(_Job(owner, job));
    _pump();
  }

  /// يسحب ما لم يبدأ بعد. لا يوقف جلسةً جارية — المقبس مفتوح فعلاً،
  /// وقطعه لا يُعيد الوقت. لكنّ نتيجتها تُهمَل لأنّ صاحبها زال.
  void cancel(Object owner) {
    _pending.removeWhere((j) => identical(j.owner, owner));
  }

  void _pump() {
    while (_active < maxConcurrent && _pending.isNotEmpty) {
      final job = _pending.removeFirst();
      _active++;
      // نلتقط كلّ خطأ هنا: مهمّة ساقطة يجب أن تُحرّر خانتها، وإلّا
      // امتلأ السقف بجلسات ميّتة وتوقّف الجدار كلّه.
      job.run().catchError((_) {}).whenComplete(() {
        _active--;
        _pump();
      });
    }
  }

  /// للاختبار فقط — يُعيد المجدول إلى حالته الابتدائيّة.
  void resetForTest() {
    _pending.clear();
    _active = 0;
  }
}

class _Job {
  _Job(this.owner, this._fn);
  final Object owner;
  final Future<void> Function() _fn;
  Future<void> run() => _fn();
}
