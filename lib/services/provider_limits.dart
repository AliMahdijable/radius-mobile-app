import 'active_company.dart';
import 'permissions_service.dart';
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

/// جلسة شركةٍ مُضافة (providerKit — نبض، AccessGate…، ٣٠ أكتوبر): المزوّد المحفوظ (`/api/auth/me`، ويُستعاد عند الإقلاع).
/// رمز الشركة وحده لا يكفي: رموزها يسجّلها الخادم ولا يعرفها التطبيق.
bool get sessionIsKit => ProviderService.isKit;

/// إجراءاتٌ **يخدمها مزوّد الشركة المُضافة أو لا** — الخادم يجعل مفتاحها false في قدرات الحساب حين لا يخدمها محوّل
/// الشركة (`adapter.capabilities`، ما جُرِّب حيّاً) أو مفتاح «التفعيل والديون» مطفأٌ لحسابه (`routes.canonicalPermissions`)،
/// وما لا يخدمه أيّ مزوّدٍ مُضاف بعد (الموقع، الجلسات، ديون المدراء) false ثابتاً. لصاحب الحساب لا تظهر أصلاً — كالموقع،
/// لا «لا صلاحيّة» يظنّها تُطلب (المالك وحده يملكها). القائمة ثابتة والقيمة من الخادم: محوّلٌ يكسب قدرةً يظهر زرّها وحده.
const Set<String> _kitCapabilityKeys = {
  'subscribers.activate',
  'subscribers.pay_debt',
  'subscribers.add_debt',
  'subscribers.add_credit',
  'subscribers.extend',
  'subscribers.edit',
  'subscribers.rename',
  'subscribers.toggle',
  'subscribers.disconnect',
  'subscribers.delete',
  'subscribers.add',
  'subscribers.create',
  'subscribers.change_profile',
  'subscribers.change_profile_active',
  'subscribers.show_password',
  'subscribers.edit_location',
  'subscribers.activate_credit',
  'packages.manage',
  'reports.sessions',
  'reports.manager_debts',
};

/// [key] إجراءٌ لا يخدمه مزوّد الجلسة فيُخفى: فايبر اكس بقائمته الثابتة، والشركات المُضافة بقدرات حسابها من الخادم
/// (مفتاحٌ false لصاحب الحساب). موظّف الشركة المُضافة غير موجودٍ بعد — وحين يوجد يحكمه ما مُنح كموظّف ايرث لنك.
bool providerHidesAction(String key) {
  if (sessionIsFiberx) return _fiberxUnsupported.contains(key);
  if (sessionIsKit) {
    return _kitCapabilityKeys.contains(key) && !Perms.isEmployee && !Perms.has(key);
  }
  return false;
}
