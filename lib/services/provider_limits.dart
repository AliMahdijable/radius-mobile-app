import 'package:easy_localization/easy_localization.dart';

import 'active_company.dart';
import 'provider_service.dart';

/// ما يمنعه **مزوّد الساس نفسه** لا الصلاحيّة — ونصّ سببه.
///
/// الإجراء الذي يمنعه المزوّد يبقى **بمكانه مقفلاً بسببه** (لا مخفيّاً، ولا
/// «اطلبها من مديرك»: لا صلاحيّة تفتحه) للمالك ولموظّفه معاً — كزرّ التجديد
/// الجماعيّ لايرث لنك (`bulkActivateUnavailableReason`).

/// جلسة ايرث لنك: المزوّد المحفوظ (`/api/auth/me`)، أو رمز الشركة النشطة قبل
/// أن يردّ (الدخول التلقائيّ والتبديل).
bool get sessionIsEarthlink =>
    ProviderService.isEarthlink ||
    ActiveCompany.current?.sasCode == 'earthlink';

/// حذف المشترك — ايرث لنك لا تسمح به (قرار المستخدم ١٨ أكتوبر: «حذف مشترك
/// لايرث لنك غير مسموح عدهم»؛ والخادم يُبقي `subscribers.delete=false`).
/// `null` = متاح (شركات SAS4)، والقفل حينها بالصلاحيّة وحدها كما كان.
String? subscriberDeleteUnavailableReason() =>
    sessionIsEarthlink ? 'subscribers.delete_el_unavailable'.tr() : null;
