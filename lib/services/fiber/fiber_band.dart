import '../../theme/colors.dart';

/// رتب الضوء عند الـONU بالـdBm — مصدرٌ واحد للوحة الأولت وشاشات الألياف (التصميم المعتمد، المالك ٢٧ أكتوبر):
///
///   جيّد      : أعلى من −25
///   حدّي      : من −25 إلى ما فوق −27
///   ضعيف      : −27 وأقلّ  (حسّاسيّة الـONU الشائعة −27: EPON PX20+ وGPON B+)
///   قويّ زيادة : أعلى من −8 (خطر إشباع المستقبِل؛ وفوق −5 خطر)
///
/// الحدود كما يقرؤها الفنّيّ: «‎-25.4» = «25» ⇒ حدّي، و«‎-27.0» ضعيف.
enum FiberBand { strong, good, marginal, weak }

class FiberBands {
  FiberBands._();

  static const double goodAbove = -25;
  static const double weakAtOrBelow = -27;
  static const double strongAbove = -8;
  static const double overloadAbove = -5;

  /// `null` لقراءةٍ غائبة أو غير معقولة — لا رتبة لما لم يُقرأ.
  static FiberBand? of(double? rx) {
    if (!plausible(rx)) return null;
    final v = rx!;
    if (v > strongAbove) return FiberBand.strong;
    if (v > goodAbove) return FiberBand.good;
    if (v > weakAtOrBelow) return FiberBand.marginal;
    return FiberBand.weak;
  }

  static AppTone tone(double? rx) {
    final b = of(rx);
    return switch (b) {
      null => AppTone.neutral,
      FiberBand.good => AppTone.success,
      FiberBand.marginal => AppTone.warning,
      FiberBand.weak => AppTone.danger,
      FiberBand.strong => rx! > overloadAbove ? AppTone.danger : AppTone.warning,
    };
  }

  static String label(FiberBand b) => switch (b) {
        FiberBand.strong => 'قويّ زيادة',
        FiberBand.good => 'جيّد',
        FiberBand.marginal => 'حدّي',
        FiberBand.weak => 'ضعيف',
      };

  /// يحتاج انتباهاً: حدّيٌّ أو ضعيف أو قويّ زيادة.
  static bool needsAttention(double? rx) {
    final b = of(rx);
    return b != null && b != FiberBand.good;
  }

  /// قراءةٌ يُعقل أن تكون ضوءاً حقيقيّاً عند ONU متّصلة: من −36 (أبعد من حسّاسيّة أيّ وحدةٍ شائعة — دونها لا تبقى متّصلة)
  /// إلى +5. ما خارجها (‏‎-40/-50 «لا ضوء» عند بعض الأجهزة، أو صفرٌ حارس) لا يُعرض.
  static bool plausible(double? rx) => rx != null && rx.isFinite && rx >= -36 && rx <= 5 && rx != 0;

  /// خانة المدرّج: (k−1, k] بـk = ⌈rx⌉، فـ«‎-25.2» في خانة «‎-25». الحدّان (−25 و−27) على حدود الخانات فلا تختلط رتبتان.
  static int bin(double rx) => rx.ceil();

  /// رتبة خانة المدرّج كلّها (تطابق رتبة كلّ قراءةٍ فيها).
  static FiberBand bandOfBin(int k) {
    if (k > strongAbove) return FiberBand.strong;
    if (k > goodAbove) return FiberBand.good;
    if (k > weakAtOrBelow) return FiberBand.marginal;
    return FiberBand.weak;
  }
}
