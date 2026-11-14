import 'package:easy_localization/easy_localization.dart';

import '../../api/account_api.dart';

/// تاريخ اشتراك الحساب بالأرقام والأيّام الباقية — المالك ١٤ نوفمبر: «التواريخ حولها ارقام وليس اسماء يعني ينتهي
/// في فلان مدة ولديك كذا ايام» (كانت «14 ديسمبر 2026»). مثل لوحة المالك («2026/12/14» · «متبقٍّ 30 يوماً»)
/// وتاريخ كرت المشترك («2026/09/03»).

/// «2026/12/14» — سنة/شهر/يوم بأرقام (من اليمين: يومٌ فشهرٌ فسنة)، و«—» بلا تاريخ.
String accountDate(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)}';
}

/// أيّام التقويم من يوم [now] إلى يوم [end] (0 = اليوم، سالبٌ = مضى) — بالتاريخ لا بالساعات: `daysLeft` من الخادم
/// يقرّب الساعات للأعلى فيقول «باقي 25 يوم» لتاريخٍ بعد 24 يوماً، وهنا الرقم يطابق التاريخ المكتوب بجانبه.
int calendarDaysUntil(DateTime end, DateTime now) {
  final a = DateTime.utc(now.year, now.month, now.day);
  final b = DateTime.utc(end.year, end.month, end.day);
  return b.difference(a).inDays;
}

extension AccountSubscriptionDatesX on AccountSubscription {
  /// الأيّام الباقية كما تُعرض في كلّ مكان (الكرت، الشاشة، «شركاتي»، الحبّة) — بالتقويم إلى [endsAt] ولا تقلّ عن 0،
  /// وبلا تاريخٍ [daysLeft] كما من الخادم (المجّانيّ الدائم 36500 قيمةٌ حارسة لا تُعرض).
  int daysLeftOn(DateTime now) {
    final e = endsAt;
    if (e == null) return daysLeft;
    final d = calendarDaysUntil(e, now);
    return d < 0 ? 0 : d;
  }

  int get shownDaysLeft => daysLeftOn(DateTime.now());

  /// «ينتهي في 2026/12/14 · باقي 30 يوم» ([withDays]، و«ينتهي اليوم» في يومه الأخير) أو «ينتهي في 2026/12/14»
  /// (حين تُقال الأيّام في العنوان فوقه)؛ null بلا تاريخ انتهاء.
  String? endsLine({bool withDays = true, DateTime? now}) {
    final e = endsAt;
    if (e == null) return null;
    if (!withDays) return 'account.ends_on'.tr(args: [accountDate(e)]);
    final days = daysLeftOn(now ?? DateTime.now());
    if (days == 0) return 'account.chip_today'.tr();
    return 'account.ends_on_days'.tr(args: [accountDate(e), '$days']);
  }
}
