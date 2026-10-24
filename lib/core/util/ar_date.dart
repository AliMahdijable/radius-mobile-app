import 'package:easy_localization/easy_localization.dart';

/// تواريخ بأسماء الأشهر — بدل «2026/10/24» و«2026-10» (المالك ٢٤ أكتوبر: «الاشهر تكتب رقم انكليزي»). بالعربيّة
/// كما تُقال في العراق (`rexp.m1..m12`: كانون الثاني … كانون الأوّل)، وبالإنكليزيّة January…. القيم تبقى
/// YYYY-MM-DD / YYYY-MM كما هي للخادم؛ هذه للعرض وحده. نفس قواعد الويب (`client-v2/src/lib/ar-date.ts`).

final _period = RegExp(r'^(\d{4})-(\d{2})$');
final _ymd = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

String _month(String mm) {
  final i = int.tryParse(mm) ?? 0;
  return i >= 1 && i <= 12 ? 'rexp.m$i'.tr() : mm;
}

/// '2026-10' ⇒ «تشرين الأوّل 2026».
String iqPeriodLabel(String? period) {
  final m = _period.firstMatch(period ?? '');
  if (m == null) return period ?? '';
  return '${_month(m[2]!)} ${m[1]}';
}

/// '2026-10-05' ⇒ «5 تشرين الأوّل»، والسنة حين لا تكون سنة [today] (اليوم إن غاب).
String iqDateLabel(String? ymd, {DateTime? today}) {
  final m = _ymd.firstMatch(ymd ?? '');
  if (m == null) return ymd ?? '';
  final y = (today ?? DateTime.now()).year.toString();
  return '${int.parse(m[3]!)} ${_month(m[2]!)}${m[1] == y ? '' : ' ${m[1]}'}';
}

/// يومٌ بعينه ⇒ مثل [iqDateLabel].
String iqDateOf(DateTime d, {DateTime? today}) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return iqDateLabel('${d.year}-$m-$day', today: today);
}

/// يومٌ كامل ⇒ «السبت 24 تشرين الأوّل 2026» — رأس الرئيسيّة على الحاسبة (بدل «السبت · 2026/10/24 · …»).
String iqLongDate(DateTime d) =>
    '${'settle.wd${d.weekday}'.tr()} ${d.day} ${_month(d.month.toString().padLeft(2, '0'))} ${d.year}';

final _recurringSuffix = RegExp(r'\s*\(ثابتة[^)]*\)');

/// الملاحظة بلا لاحقة «(ثابتة …)» التي يكتبها الخادم للصرفيّة المولَّدة — الشارة تقولها بالشهر.
String stripRecurringSuffix(String note) => note.replaceAll(_recurringSuffix, '').trim();
