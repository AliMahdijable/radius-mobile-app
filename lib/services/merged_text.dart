import 'package:easy_localization/easy_localization.dart';

import 'merged_mode.dart';

/// «كل الصفحات» للموظّف (٩ نوفمبر — المالك: «الموظف… يشوف كل الصفحات مثل المدير»): نصوص «كل الشركات» بكلمته هو —
/// «صفحة/صفحات» لا «شركة/شركات»، و«صفحاتي» مكان «تبديل الشركة». مفتاح `merged.<k>` بـ`trm` ⇒ في جلسة موظّفٍ `merged_emp.<k>`
/// إن وُجد، وإلّا المفتاح نفسه كما هو. المالك كما كان حرفاً (`.tr()` نفسه). نصٌّ فقط — لا منطق.
///
/// مفاتيح «كل الشركات» في مجموعاتٍ أخرى (`sales.merged_readonly`، `ai.merged_scope`) ⇒ `merged_emp.sales_merged_readonly`.
extension MergedTr on String {
  String trm({List<String>? args}) {
    if (MergedMode.employeeSession) {
      final k = 'merged_emp.${startsWith('merged.') ? substring('merged.'.length) : replaceAll('.', '_')}';
      if (k.trExists()) return k.tr(args: args);
    }
    return this.tr(args: args);
  }
}

/// النصّ نفسه بكلمة المالك أو الموظّف — لنصوص «كل الشركات» المكتوبة في الكود (ليست في ملفّ الترجمة).
String mergedWord(String owner, String employee) => MergedMode.employeeSession ? employee : owner;
