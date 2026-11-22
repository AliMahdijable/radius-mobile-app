import 'report_kit.dart';

/// «عمر الدين» (٢٢ نوفمبر — بند المقترح لديون المدراء وديون المحذوفين: «المجموع، وعمر الدين، وتقسيم حسب الشركة والمدير»):
/// خمس فئاتٍ بترتيب العمر لا بالمبلغ، و«بلا تاريخ» آخرها — دينٌ بلا تاريخٍ لا يُنسب لفئةٍ تخميناً.
class DebtAge {
  DebtAge._();

  static const buckets = ['أقلّ من شهر', 'شهر – 3 أشهر', '3 – 6 أشهر', 'أكثر من 6 أشهر', 'بلا تاريخ'];

  /// أقدم من 3 أشهر (90 يوماً) — بطاقة «أقدم من 3 أشهر».
  static const oldDays = 90;

  static String bucketOf(DateTime? at, DateTime now) {
    if (at == null) return buckets[4];
    final days = now.difference(at).inDays;
    if (days < 30) return buckets[0];
    if (days < 90) return buckets[1];
    if (days < 180) return buckets[2];
    return buckets[3];
  }

  static bool isOld(DateTime? at, DateTime now) => at != null && now.difference(at).inDays >= oldDays;

  /// الحصص بترتيب الفئات (الفارغة لا تُعرض)، والنسبة من المبلغ.
  static List<RpShare> shares<T>(List<T> rows, {required DateTime? Function(T) at, required num Function(T) amount, required DateTime now}) {
    final sum = <String, num>{}, count = <String, int>{};
    for (final r in rows) {
      final b = bucketOf(at(r), now);
      sum[b] = (sum[b] ?? 0) + amount(r);
      count[b] = (count[b] ?? 0) + 1;
    }
    final total = sum.values.fold<num>(0, (a, v) => a + (v > 0 ? v : 0));
    return [
      for (final b in buckets)
        if (count.containsKey(b))
          RpShare(name: b, amount: sum[b]!, count: count[b]!, share: total > 0 && sum[b]! > 0 ? sum[b]! / total : 0),
    ];
  }
}
