import 'package:flutter/foundation.dart';

/// منسّق مسح الأجهزة — يمنع مسحين متوازيين.
///
/// شاشة الأجهزة تمسح كلّ ٢٠ ثانية ما دامت حيّةً و«مرئيّة» بمعنى التبويب.
/// لكنّ فتح جدار الأجهزة يدفع مساراً **فوقها**، ولا يُبطل ذلك علَم
/// التبويب — فتبقى تمسح خلف صفحةٍ تمسح أيضاً: ضِعف الشبكة، وتنبيهان
/// لكلّ سقوط.
///
/// الجدار يرفع العدّاد عند دخوله ويخفضه عند خروجه، والشاشة تسأل
/// [suspended] قبل كلّ جولة. عدّاد لا علَم، لأنّ مسارين قد يُفتحان
/// فوق بعضهما (جدار ← تفاصيل ← رجوع) فيُطفئ الأوّلُ خروجاً حقّاً
/// للثاني.
class DeviceSweep {
  DeviceSweep._();

  static final ValueNotifier<int> holders = ValueNotifier<int>(0);

  /// هل يوجد من يمسح نيابةً عن شاشة الأجهزة الآن؟
  static bool get suspended => holders.value > 0;

  static void acquire() => holders.value = holders.value + 1;

  static void release() {
    final n = holders.value - 1;
    holders.value = n < 0 ? 0 : n;
  }

  // ── أجهزةٌ قراءة «الفحص الشامل» لها جارية (المراجعة الثانية) ──
  // الإمساك ينتهي بانتهاء الجولة عند السقف، وقراءة الجهاز المسقوف تبقى جارية لتحلّ محلّ سطره حين تصل — فكانت بطاقته والتسخين
  // يفتحان عليه جلسةً ثانية بعد ثوانٍ، على أبطأ الأجهزة بالذات.
  static final Map<int, ({int n, DateTime since})> _busy = {};

  /// قراءة الفحص لهذا الجهاز ما زالت جارية — لا جلسة بطاقةٍ أو تسخينٍ أو برجٍ عليه حتى تنتهي. ١٠ د حدٌّ أقصى للأمان.
  static bool busy(int id) {
    final b = _busy[id];
    return b != null && DateTime.now().difference(b.since) < const Duration(minutes: 10);
  }

  static void readStarted(int id) {
    final b = _busy[id];
    _busy[id] = (n: (b?.n ?? 0) + 1, since: b?.since ?? DateTime.now());
  }

  static void readEnded(int id) {
    final b = _busy[id];
    if (b == null) return;
    if (b.n <= 1) {
      _busy.remove(id);
    } else {
      _busy[id] = (n: b.n - 1, since: b.since);
    }
  }

  @visibleForTesting
  static void resetBusyForTest() => _busy.clear();
}
