import '../models/merged_company.dart';
import '../models/subscriber.dart';
import 'active_company.dart';
import 'merged_mode.dart';
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
/// (مفتاحٌ false لصاحب الحساب). موظّف الشركة المُضافة يحكمه ما مُنح كموظّف ايرث لنك — إلّا موظّف المشروع الوطنيّ في مفاتيح أقسام
/// بوّابته ([_nationalPortalOnlyKeys]).
bool providerHidesAction(String key) {
  if (sessionIsFiberx) return _fiberxUnsupported.contains(key);
  if (sessionIsKit) {
    if (Perms.isEmployee) return ProviderService.parentIsZone && _nationalPortalOnlyKeys.contains(key);
    return _kitCapabilityKeys.contains(key) && !Perms.has(key);
  }
  if (sessionIsJazeeraFiber && _addSubscriberKeys.contains(key)) return !Perms.isEmployee && !Perms.has('subscribers.add');
  return false;
}

/// جلسة فايبر الجزيرة: ساس SAS4 حقيقيّ برمز `ftth` في دليل الشركات (ftth.jt.iq) — لا المشروع الوطنيّ (`provider:'ftth'`، رمزه
/// `ftth-iq` — [ProviderService.isFtth]). مالها عند موقع الشحن (pay.jt.iq)، والساس للآيبي والاتصال والاستهلاك والاسم والرمز.
bool get sessionIsJazeeraFiber => !ProviderService.isFtth && ActiveCompany.current?.sasCode == 'ftth';

/// «إضافة مشترك» لفايبر الجزيرة (المالك ١٤ نوفمبر: «اضافة مشترك لازم نخفي الزر الهم لان هم ماعدهم اضافة»): الوكيل لا ينشئ مشتركاً
/// بأيٍّ من صفحتيه (الساس بلا صلاحيّة إنشاء، وموقع الشحن بلا صفحة إضافة — الشركة تنشئه) ⇒ لا يظهر لصاحب الصفحة أصلاً متى قالت قدراتها
/// لا (الخادم f6ac57d: `subscribers.add` = إنشاء الساس لصفحات ftth) — لا مقفلاً بـ«اطلبها من مديرك» ولا مفتوحاً يرفضه الساس. صفحةٌ
/// يمنحها ساسها الإنشاء تبقى كما كانت، والموظّف بما مُنح.
const Set<String> _addSubscriberKeys = {'subscribers.add', 'subscribers.create'};

/// مفتاحان يُمنحان لموظّف المشروع الوطنيّ لأقسام بوّابته وحدها (١ نوفمبر — `ElEmployeePerms.nationalExtraKeys`): «الجلسات» و«تقرير
/// الجلسات» فيها، والتعليق على المهامّ والطلبات. ما يفتحه المفتاح نفسه خارجها — تقرير جلسات الساس العامّ، «سجلّ الجلسات» و«تعديل»
/// المشترك — لا يخدمه الوطنيّ (قدرات صاحبه false)، فيبقى مخفيّاً للموظّف كما هو لصاحب الحساب.
const Set<String> _nationalPortalOnlyKeys = {'reports.sessions', 'subscribers.edit', 'subscribers.add'}; // + «إضافة مشترك» (بوّابته، ٣ نوفمبر)

/// «فصل الاتصال» لا يخدمه مزوّد الجلسة: المشروع الوطنيّ (البوّابة لا تسمح به للمقاول — يُخفى للمالك وللموظّف)، أو شركةٌ مُضافة
/// قدرتها `subscribers.disconnect` false لصاحب الحساب. كان الفصل يتبع `subscribers.toggle` وحده، فيظهر للوطنيّ حين يُفتح التعليق
/// ويردّه الخادم بـ409.
bool subscriberDisconnectHidden() =>
    ProviderService.togglesAsSuspend || (sessionIsKit && !Perms.isEmployee && !Perms.has('subscribers.disconnect'));

/// التعليق/التشغيل الجماعيّ — لا للوطنيّ (كلّ تعليقٍ ~٣ نداءات للبوّابة، والخادم يحدّه ٤/د و٢٠/١٠د لكلّ شريك).
bool bulkToggleHidden() => ProviderService.togglesAsSuspend;

/// «معلومات الجهاز» وفحص أجهزة المشتركين من الهاتف لا يخدمها **المشروع الوطنيّ** (المالك ١٤ نوفمبر: «المشروع الوطني نلغي منه معلومات
/// الجهاز… لان هم بالاصل ماعدهم منجمنت حتى لايصير ضغط بالصفحه»): جهاز المشترك تديره الشركة ولا عنوان إدارةٍ له عند الوكيل، فالكرت
/// كان يدور على جهازٍ لا يصله ويثقّل الصفحة. فلا كرت «معلومات الجهاز» ولا «الجهاز الثاني» بصفحة مشتركه، ولا موجة فحصٍ على قائمته،
/// ولا «فحص الأجهزة» (الرادار) لجلسته. «الليف والموقع» (الضوء من بوّابته) و«تعديل معلومات الجهاز» (بوّابته) يبقيان — ليسا فحصاً
/// من الهاتف. الجلسة: قديمه (`ftth`) وجديده (`watani`) — [ProviderService.parentIsZone] نفسه.
bool get sessionHasNoSubscriberDevices => ProviderService.parentIsZone;

/// شركةٌ في «كل الشركات» لا أجهزة مشتركين لها (المشروع الوطنيّ — كحكم التذاكر: مزوّده `ftth` أو رمزه يبدأ بـ`watani`).
bool companyHasNoSubscriberDevices(MergedCompany c) =>
    c.provider == MergedProvider.ftth || c.code.toLowerCase().startsWith('watani');

/// [sub] من شركةٍ لا أجهزة مشتركين لها: صفٌّ مربوطٌ بشركته في «كل الشركات» ⇒ شركته (المجهولة ⇒ كما كان)، وإلّا الجلسة.
bool subscriberDevicesHidden(Subscriber sub) {
  final key = sub.companyKey;
  if (key == null) return sessionHasNoSubscriberDevices;
  final c = MergedMode.companyOf(key);
  return c != null && companyHasNoSubscriberDevices(c);
}
