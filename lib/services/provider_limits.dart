import 'active_company.dart';
import 'provider_service.dart';

/// ما يمنعه **مزوّد الساس نفسه** لا الصلاحيّة.
///
/// الأصل: الإجراء الذي يمنعه المزوّد يبقى **بمكانه مقفلاً بسببه** (لا «اطلبها
/// من مديرك»: لا صلاحيّة تفتحه) للمالك ولموظّفه معاً — كزرّ التجديد الجماعيّ
/// لايرث لنك (`bulkActivateUnavailableReason`). والاستثناء بقرار المالك:
/// [subscriberDeleteHidden].

/// جلسة ايرث لنك: المزوّد المحفوظ (`/api/auth/me`)، أو رمز الشركة النشطة قبل
/// أن يردّ (الدخول التلقائيّ والتبديل).
bool get sessionIsEarthlink =>
    ProviderService.isEarthlink ||
    ActiveCompany.current?.sasCode == 'earthlink';

/// حذف المشترك — ايرث لنك لا تسمح به (المالك ١٨ أكتوبر: «حذف مشترك لايرث لنك
/// غير مسموح عدهم»)، وقرار المالك ١٩ أكتوبر: **لا يظهر «حذف» لجلساتها أصلاً**
/// (فرديّاً وجماعيّاً، مالكاً وموظّفاً) — لا مقفلاً بالسبب كما كان؛ والخادم يردّ
/// `DELETE /api/v2/subscribers/:idx` بـ409 `EL_DELETE_UNSUPPORTED` قبل أيّ نداء.
/// `false` = شركات SAS4 وFTTH: كما كان (القفل بالصلاحيّة وحدها).
bool subscriberDeleteHidden() => sessionIsEarthlink;
