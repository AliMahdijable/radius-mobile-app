/// «أكثر من موظّف بالفلاتر» (المالك ٢٣ نوفمبر: «ماكدر اختار اكثر من موظف بالفلاتر بجميع التقارير»؛ عقد الخادم من d9):
/// موظّفٌ واحد ⇒ `employee_id` (يفهمه الخادم القديم والجديد)، اثنان فأكثر ⇒ `employee_ids=1,2` (حدّه ٥٠). الخادم الذي طبّقها
/// يعلّم ردّه بـ`employee_filter` = المعرّفات المطبَّقة — في `data` للمال (/api/reports/finance)، وفي أعلى الردّ للقوائم.
/// اثنان فأكثر وغابت الإشارة (أو اختلفت) ⇒ [kEmployeesUnsupported] بلا أرقام: لا أرقام غير مفلترة كأنّها مفلترة.
library;

const kEmployeesUnsupported = 'الخادم لا يدعم أكثر من موظّف بعد — اختر موظّفاً واحداً';

/// المعرّفات بلا تكرار ومرتّبة.
List<int> normEmployeeIds(Iterable<int> ids) => ids.toSet().toList()..sort();

/// بارامترات الطلب لـ[ids].
Map<String, String> employeeQuery(Iterable<int> ids) {
  final s = normEmployeeIds(ids);
  if (s.isEmpty) return const {};
  if (s.length == 1) return {'employee_id': '${s.single}'};
  return {'employee_ids': s.join(',')};
}

/// هل يُعتمد الردّ لفلتر [asked]؟ واحدٌ أو لا أحد ⇒ نعم دائماً؛ اثنان فأكثر ⇒ فقط إن حمل [where] `employee_filter` بالمعرّفات نفسها.
bool employeeFilterHonored(Iterable<int> asked, Object? where) {
  final want = normEmployeeIds(asked);
  if (want.length < 2) return true;
  final f = where is Map ? where['employee_filter'] : null;
  if (f is! List) return false;
  final got = normEmployeeIds([for (final x in f) int.tryParse('$x') ?? -1]);
  return got.length == want.length && got.every(want.contains);
}
