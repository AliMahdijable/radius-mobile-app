import '../../../theme/colors.dart';

/// سلّم التدريج الموحّد للوحات الأجهزة.
///
/// كان في الخمس لوحات **٢٤ دالّة تدريج** مكرّرة (`_signalColor` ·
/// `_snrColor` · `_percentColor` · `_tempColor` · `_speedColor` ·
/// `_ccqColor` · `_rssiColor` · `_rxColor` · `_errColor` ·
/// `_voltageColor` · `_linkSpeedColor` …) تعيد نفس الرتب بعتبات
/// متفرّقة — وبعضها متناقض داخل الملفّ الواحد (mimosa كان يعيد `success`
/// لرتبتَي «ممتاز» و«جيّد» معاً بينما ubnt يفصلهما).
///
/// ── لماذا ثلاث رتب لا أربع ──────────────────────────────────────────
/// الرتبة الرابعة (السماويّة) كانت تفصل «جيّد» عن «ممتاز»، لكنّ اللوحات
/// **تعرض النصّ العربي بجانب القيمة أصلاً** (ممتازة · جيّدة · مقبولة ·
/// ضعيفة). فاللون يحمل الحكم الإجرائي (سليم / انتبه / تدخّل) والنصّ
/// يحمل الدرجة. أربع رتب لونيّة على قيمة واحدة تُنتج تمييزاً لا يقرؤه
/// أحد، وتضيف عائلة لونيّة كاملة إلى اللوحة بلا مقابل.
///
/// ── العَود إلى النغمة ───────────────────────────────────────────────
/// كلّ دالّة تُرجع [AppTone] لا `Color`، فتأتي التعبئة والخلفيّة والحدّ
/// والنصّ من اللوحة معاً — وهذا ما يجعل الوضع الليلي صحيحاً بلا اشتقاق
/// شفافيّة.
class Grade {
  Grade._();

  /// قوّة الإشارة اللاسلكيّة بالـdBm (كلّما اقترب من الصفر كان أفضل).
  static AppTone signal(num? dbm) {
    if (dbm == null) return AppTone.neutral;
    if (dbm >= -65) return AppTone.success;
    if (dbm >= -80) return AppTone.warning;
    return AppTone.danger;
  }

  /// نسبة الإشارة إلى الضوضاء بالـdB.
  static AppTone snr(num? v) {
    if (v == null) return AppTone.neutral;
    if (v >= 20) return AppTone.success;
    if (v >= 12) return AppTone.warning;
    return AppTone.danger;
  }

  /// قدرة الاستقبال الضوئيّة للـONT بالـdBm.
  static AppTone rxPower(num? dbm) {
    if (dbm == null) return AppTone.neutral;
    if (dbm >= -27 && dbm <= -8) return AppTone.success;
    if (dbm >= -30 && dbm <= -5) return AppTone.warning;
    return AppTone.danger;
  }

  /// نسبة مئويّة **كلّما ارتفعت كان أفضل** — CCQ · جودة الرابط.
  static AppTone percentHigherBetter(num? p) {
    if (p == null) return AppTone.neutral;
    if (p >= 70) return AppTone.success;
    if (p >= 40) return AppTone.warning;
    return AppTone.danger;
  }

  /// نسبة مئويّة **كلّما ارتفعت كان أسوأ** — حمل المعالج والذاكرة
  /// والقرص. الخلط بين هذه وسابقتها كان أكثر أخطاء اللوحات تكراراً.
  static AppTone percentLowerBetter(num? p) {
    if (p == null) return AppTone.neutral;
    if (p >= 85) return AppTone.danger;
    if (p >= 65) return AppTone.warning;
    return AppTone.success;
  }

  /// حرارة الجهاز بالدرجة المئويّة.
  static AppTone temperature(num? c) {
    if (c == null || c <= 0) return AppTone.neutral;
    if (c >= 75) return AppTone.danger;
    if (c >= 60) return AppTone.warning;
    return AppTone.success;
  }

  /// فولتيّة PoE — الطبيعي 24V أو 48V، والانحراف الكبير عطل.
  static AppTone voltage(num? v) {
    if (v == null) return AppTone.neutral;
    if (v < 20 || v > 60) return AppTone.danger;
    if (v < 22 || v > 55) return AppTone.warning;
    return AppTone.success;
  }

  /// سرعة الرابط بالميغابت.
  static AppTone speedMbps(num? mbps) {
    if (mbps == null || mbps <= 0) return AppTone.neutral;
    if (mbps >= 100) return AppTone.success;
    if (mbps >= 10) return AppTone.warning;
    return AppTone.danger;
  }

  /// سرعة منفذ مكتوبة نصّاً («1Gbps» · «100M» · «10Mbps»).
  static AppTone linkSpeedText(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('g') ||
        r.contains('10000') ||
        r.contains('2500') ||
        r.contains('1000')) {
      return AppTone.success;
    }
    if (r.contains('100')) return AppTone.success;
    if (r.contains('10m') || r.contains('10 m')) return AppTone.warning;
    return AppTone.neutral;
  }

  /// نسبة أخطاء/فقد الحزم — كلّما ارتفعت كان أسوأ.
  static AppTone errorRate(num? p) {
    if (p == null) return AppTone.neutral;
    if (p >= 5) return AppTone.danger;
    if (p >= 1) return AppTone.warning;
    return AppTone.success;
  }
}
