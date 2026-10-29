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

/// جلسة فايبر اكس (OpenRadius): المزوّد المحفوظ، أو رمز الشركة النشطة قبل أن يردّ.
bool get sessionIsFiberx =>
    ProviderService.isFiberx || ActiveCompany.current?.sasCode == 'fiberx';

/// إجراءات المشترك التي **لا يخدمها فايبر اكس** (لا مسار عنده ولا عندنا) — لا تظهر لجلساته أصلاً، لا مقفلةً بـ«لا صلاحيّة»
/// (مالكٌ يرى «تعديل/حذف/فصل» مقفلةً يظنّها صلاحيّةً تُطلب). كما يعرضها الموقع (`FIBERX_ACTIONS` في SubscriberDetailSheet.tsx)،
/// والخادم يجعل مفاتيحها false (`fiberxRoutes.canonicalPermissions`). «تمديد» فايبر اكس رسالةٌ منهم بمفتاحه `fiberx.extend`
/// لا `subscribers.extend`.
const Set<String> _fiberxUnsupported = {
  'subscribers.extend',
  'subscribers.edit',
  'subscribers.toggle',
  'subscribers.disconnect',
  'subscribers.add_credit',
  'subscribers.delete',
  'subscribers.edit_location',
  'reports.sessions',
  'reports.manager_debts',
  'reports.daily_activations',
};

/// [key] إجراءٌ لا يخدمه مزوّد الجلسة فيُخفى (فايبر اكس وحده الآن).
bool providerHidesAction(String key) =>
    sessionIsFiberx && _fiberxUnsupported.contains(key);
