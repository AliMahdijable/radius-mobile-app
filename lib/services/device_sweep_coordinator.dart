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
}
