/// «طريقة الدفع» بالتقارير (٢٤ نوفمبر — المالك: «طريقة الدفع … ماستر حوالة، او بالدين، او كاش نقدي. بالتقارير ضمنت هاي الشي بالفلاتر؟»
/// ثمّ «يكون ضمنه بكل العمليات المرتبط بها بالتقارير بكشف الحساب …»).
///
/// قاعدة الخادم PAY_KIND_SQL (paykind1، 7d09ac9) واحدةٌ لكلّ التقارير: كلّ سطرٍ بطريقةٍ واحدة — الجزئيّ بطريقة ما دُفع منه (باقيه دينٌ
/// معه)، والتمديد والمزامَن من الساس والتعويض والصرفيّات بلا طريقة. الخادم يُعيد صدى الفلتر (type_filter.pay بالماليّ، pay_filter بسجلّ
/// الحركات)؛ بلا صداه لا أرقام غير مفلترة كأنّها مفلترة ([honored]). كالموقع lib/transfer-pay.ts (PAY_KIND_*).
class PayKinds {
  PayKinds._();

  static const keys = ['cash', 'zaincash', 'master', 'other', 'debt'];
  static const labels = <String, String>{'cash': 'كاش', 'zaincash': 'زين كاش', 'master': 'ماستر', 'other': 'أخرى', 'debt': 'بالدين'};
  static const unsupported = 'فلتر «طريقة الدفع» غير مدعومٍ لهذه الشركة بعد';

  /// خيارات ورقة الفلاتر — لصفحةٍ فُتحت لها «الحوالات».
  static List<(String, String)> options() => [for (final k in keys) (k, labels[k]!)];

  /// بترتيبها الثابت، بلا ما لا يُعرف.
  static List<String> sorted(Iterable<String> kinds) => [
        for (final k in keys)
          if (kinds.contains(k)) k,
      ];

  /// «طريقة الدفع: ماستر، زين كاش» — الشريحة ورأس الملفّ المصدَّر.
  static String chip(Iterable<String> kinds) => 'طريقة الدفع: ${sorted(kinds).map((k) => labels[k]).join('، ')}';

  /// طريقة سطرٍ كما كتبها الخادم (pay_kind) — null لما بلا طريقة أو خادمٍ لا يكتبها.
  static String? of(Object? v) {
    final s = '${v ?? ''}'.trim();
    return keys.contains(s) ? s : null;
  }

  /// هل طبّق الخادم فلتر الطريقة؟ صداه = ما أُرسل. بلا فلتر دائماً نعم.
  static bool honored(Iterable<String> sent, Object? echo) {
    final s = sorted(sent);
    if (s.isEmpty) return true;
    if (echo is! List) return false;
    final e = {for (final x in echo) '$x'};
    return e.length == s.length && s.every(e.contains);
  }
}
