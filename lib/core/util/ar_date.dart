import 'package:easy_localization/easy_localization.dart';

/// تواريخ التقارير بالأرقام اللاتينيّة «2026/11/16» لا بأسماء الأشهر — المالك ١٦ نوفمبر: «باوع التواريخ بتقارير كلها
/// بدله من اسم شهر الى رقم شهر اجنبي في جميع التقارير بالكامل تطبيق وويب» (كانت «16 تشرين الثاني» منذ ٢٤ أكتوبر).
/// سنة/شهر/يوم كتاريخ الاشتراك (`account_dates.dart`) وسجلّ الرسائل، والسنة تُكتب دائماً: «11/16» بلا سنة يقرؤه
/// العراقيّ يوماً فشهراً. القيم تبقى YYYY-MM-DD / YYYY-MM كما هي للخادم؛ هذه للعرض وحده. نفس قواعد الويب
/// (`client-v2/src/lib/ar-date.ts`).

final _period = RegExp(r'^(\d{4})-(\d{2})$');
final _ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

String _two(int n) => n.toString().padLeft(2, '0');

/// '2026-10' ⇒ «2026/10».
String iqPeriodLabel(String? period) {
  final m = _period.firstMatch(period ?? '');
  if (m == null) return period ?? '';
  return '${m[1]}/${m[2]}';
}

/// '2026-10-05' (أو بداية نصٍّ بهذا الشكل) ⇒ «2026/10/05». [today] لا أثر له الآن (السنة تُكتب دائماً) — باقٍ لمن يمرّره.
String iqDateLabel(String? ymd, {DateTime? today}) {
  final m = _ymd.firstMatch(ymd ?? '');
  if (m == null) return ymd ?? '';
  return '${m[1]}/${m[2]}/${m[3]}';
}

/// يومٌ بعينه ⇒ «2026/10/05» مثل [iqDateLabel].
String iqDateOf(DateTime d, {DateTime? today}) => '${d.year}/${_two(d.month)}/${_two(d.day)}';

/// فترة راتب كما تُعرض: الشهريّة '2026-11' ⇒ «2026/11»، والأسبوعيّة (مفتاحها يوم صرفها '2026-11-10') ⇒
/// «أسبوع 2026/11/10». نصّ الخادم ([serverLabel]: «تشرين الثاني 2026» / «أسبوع 2026-11-10») لما لا يُعرف مفتاحه.
String iqPayPeriodLabel(String? key, String? serverLabel) {
  final k = key ?? '';
  if (_period.hasMatch(k)) return iqPeriodLabel(k);
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(k)) return 'أسبوع ${iqDateLabel(k)}';
  return serverLabel ?? k;
}

String _month(String mm) {
  final i = int.tryParse(mm) ?? 0;
  return i >= 1 && i <= 12 ? 'rexp.m$i'.tr() : mm;
}

/// يومٌ كامل ⇒ «السبت 24 تشرين الأوّل 2026» — رأس الرئيسيّة على الحاسبة (ليس تقريراً: يبقى بالاسم).
String iqLongDate(DateTime d) =>
    '${'settle.wd${d.weekday}'.tr()} ${d.day} ${_month(d.month.toString().padLeft(2, '0'))} ${d.year}';

final _recurringSuffix = RegExp(r'\s*\(ثابتة[^)]*\)');

/// الملاحظة بلا لاحقة «(ثابتة …)» التي يكتبها الخادم للصرفيّة المولَّدة — الشارة تقولها بالشهر.
String stripRecurringSuffix(String note) => note.replaceAll(_recurringSuffix, '').trim();
