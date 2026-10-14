# لقطات الصلاحيّات (test/visual_perm)

أداة مراجعة بصريّة، **لا تُشحن** ولا تُقارن بكسلاً: ترسم شاشات التطبيق الحقيقيّة
بخطّ IBM Plex Sans Arabic وأيقونات Lucide/Material، بالعربيّة (RTL)، وبمجموعة
صلاحيّاتٍ مختارة، أمام خادمٍ وهميّ على `ApiClient.dio` (لا شبكة حقيقيّة)، ثمّ
تحفظ كلّ شاشةٍ PNG. الغاية أن ترى ما يراه الموظّف قبل التعديل وبعده.

## التشغيل

```sh
# قبل التعديل
flutter test test/visual_perm/ --dart-define=VISUAL_OUT=/path/to/shots/before

# بعد التعديل (المجلّد وحده يتغيّر)
flutter test test/visual_perm/ --dart-define=VISUAL_OUT=/path/to/shots/after
```

- `VISUAL_OUT` يُقرأ من `--dart-define` أوّلاً، ثمّ من متغيّر البيئة بالاسم نفسه،
  وإلّا يُكتب في `build/visual_perm/`.
- سيناريو واحد: `--plain-name "S2_el_emp_subs"`، وشاشة واحدة: `--plain-name "S2_el_emp_subs · dashboard"`.
- الجولة كاملةً تأخذ نحو ٥ ثوانٍ و٤٣ لقطة.

## السيناريوهات

| المعرّف | الفاعل | المزوّد | الصلاحيّات |
|---|---|---|---|
| `S1_owner` | مالك | ايرث لنك | كلّها (مرجع: ما يراه المالك اليوم) |
| `S1b_sas_owner` | مالك | ساس (سوبرنت) | كلّها (مرجع S4) |
| `S2_el_emp_subs` | موظّف ايرث لنك | ايرث لنك | `subscribers.view` وحدها (لقطة المالك 10.png) |
| `S3_el_emp_none` | موظّف ايرث لنك | ايرث لنك | لا شيء |
| `S4_sas_subadmin` | مدير فرعيّ ساس | ساس | يعرض المشتركين ويفعّل ويمدّد؛ والباقي `false` |

الضبط عبر `PermissionsService.debugSet` و`ProviderService.debugSet`
و`EmployeeSession.restore()` (بعلامة `employee.direct_session` في الخزنة الوهميّة)
و`ActiveCompany.saveFromLogin`. السيناريوهات في `visual_perm_harness.dart` (`allScenarios`).

## الشاشات (لكلّ سيناريو)

| الملفّ | ما يُرسم |
|---|---|
| `<S>_dashboard.png` | `MainShell` على الرئيسيّة، ‎430×932 @3x |
| `<S>_dashboard_dark.png` | الشيء نفسه بالوضع الليليّ (S1/S2/S3) |
| `<S>_dashboard_ipad.png` | آيباد ‎1024×1366 @2x |
| `<S>_more.png` · `<S>_more_full.png` | «قوائم أخرى» بنقر تبويبها؛ `_full` بطول ‎2400 لترى القائمة كلّها |
| `<S>_fab.png` | ورقة «+» (الإجراءات السريعة) بنقر زرّ الإضافة |
| `<S>_reports.png` | مركز التقارير مدفوعاً كصفحة |
| `<S>_settings.png` · `<S>_settings_full.png` | الإعدادات مدفوعةً كصفحة (كما يفتحها الترس) |

وبجانب كلّ لقطة `<name>.requests.txt`: كلّ نداءٍ أطلقته الشاشة وحالته. يُثبت أنّ
القسم المقفل **لا يكلّف نداءً** — ولا يجوز أن يظهر فيه `403` لموظّف ايرث لنك.

## الخادم الوهميّ

`VisualServer` في `visual_perm_harness.dart`: ردودٌ معقولة لـ`/api/v2/subscribers`
(١٧ مشتركاً)، `/api/reports/finance`، `/api/v2/admin-widgets`،
`/api/activities/daily-activations`، `/api/whatsapp/connection-status/*`،
`/api/admin/view-scope`. ويردّ `403 PERMISSION_DENIED` حين لا يملك الفاعل مفتاح
المسار (كبوّابة الموظّفين)، ويقنّع الرصيد (`balance:null`) بلا `reports.financial`.
وما سواه `200 {success:true, data:[]}`.

⚠️ لمدير الساس الفرعيّ (S4) الـ403 على `reports/finance` **افتراضٌ** هنا: الرئيسيّة
لا تحجب شيئاً عنه اليوم (الحجب لموظّف ايرث لنك وحده)، فإن رفض الخادم الحقيقيّ
ظهر «تعذّر الجلب» ورصيدٌ صفر كما في اللقطة.

## ملاحظات

- لا تُعدِّل `lib/` شيئاً. تُعيد استعمال `simTheme` و`SimDiskLoader` من
  `test/sim_el/sim_harness.dart` و`loadAppFonts` من `test/support/app_fonts.dart`.
- MaterialIcons من حزمة الاختبار، وإلّا من `$FLUTTER_ROOT/bin/cache/artifacts/material_fonts/`.
- رسائل `MissingPluginException(path_provider)` في السجلّ متوقّعة (حفظ القائمة
  للعمل دون اتّصال) ولا تمسّ اللقطة.
