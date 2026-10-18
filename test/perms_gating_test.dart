import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/archive_info.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/screens/reports/reports_hub_screen.dart';
import 'package:rad_mysvcs/screens/settlements/widgets/archive_bar.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

/// حرّاس الحجب بالصلاحيّة — **على الودجت لا على نصّ المصدر**.
///
/// ⚠️ كلّ حرّاس الصلاحيّات قبل اليوم كانت تقرأ نصّ الملفّ: تُمسك حذف
/// سطرٍ ولا تُمسك منطقاً يكذب. وهذه تبني الشجرة فعلاً وتسأل: هل يرى
/// هذا الموظّفُ هذا العنصر؟
///
/// والحالات منقولةٌ من فحصٍ حيٍّ على `admin@poox` (‏2026-10-04) بثلاثة
/// موظّفين حقيقيّين: الخادم يردّ 403 `PERMISSION_DENIED` لمن لا يملك
/// `settlements.view` — فالإخفاء هنا يوافق الخادم لا يسبقه.
void main() {
  tearDown(PermissionsService.debugReset);

  /// العدّ بالنوع لا بالنصّ: الترجمة لا تُحمَّل في بيئة الاختبار،
  /// ومطابقةُ نصٍّ تجعل الحارس رهينةَ ملفّ ترجمة.
  Future<void> show(WidgetTester t, {ArchiveInfo? archive}) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              child: ArchiveBar(
                archive: archive,
                includeArchived: false,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump();
  }

  const full = ArchiveInfo(
    hidden: true,
    included: false,
    settlements: 3,
    lastNumber: 4,
  );

  group('حبّة «تسوية الحساب» في شريط الأرشيف', () {
    testWidgets('🚨 تختفي عن موظّفٍ بلا settlements.view', (t) async {
      // `qa_none` في الفحص الحيّ: يملك `reports.expenses` فيرى الصرفيات
      // والشريط، ولا يملك `settlements.view` فيردّ الخادم 403.
      PermissionsService.debugSet(
        isEmployee: true,
        permissions: const {'reports.expenses': true},
      );
      await show(t, archive: full);
      // حبّتان: «الحاليّة» و«مع الأرشيف». والثالثة محجوبة.
      expect(find.byType(ToneChip), findsNWidgets(2));
      // والشريط نفسه ظاهرٌ — الحجب للحبّة وحدها لا للسياق الذي يشرح
      // لماذا نقصت القائمة.
      expect(find.byType(ArchiveBar), findsOneWidget);
      expect(find.byType(Text), findsWidgets);
    });

    testWidgets('وتظهر لمن يملكها', (t) async {
      // `qa_view` في الفحص الحيّ.
      PermissionsService.debugSet(
        isEmployee: true,
        permissions: const {
          'reports.expenses': true,
          'settlements.view': true,
        },
      );
      await show(t, archive: full);
      expect(find.byType(ToneChip), findsNWidgets(3));
    });

    testWidgets('والمدير يراها دائماً', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await show(t, archive: full);
      expect(find.byType(ToneChip), findsNWidgets(3));
    });
  });

  group('الشريط لا يظهر بلا تسويات', () {
    testWidgets('🚨 صفر تسوياتٍ = لا شريط إطلاقاً', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await show(
        t,
        archive: const ArchiveInfo(
            hidden: false, included: false, settlements: 0),
      );
      expect(find.byType(ToneChip), findsNothing);
    });

    testWidgets('وغيابُ الوصف كلّه كذلك', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await show(t, archive: null);
      expect(find.byType(ToneChip), findsNothing);
    });
  });

  group('منفذ الاختبار نفسه', () {
    test('🚨 قبل الضبط تُرجع has قيمة true — فاختبارٌ ينسى الضبط يمرّ كاذباً',
        () {
      PermissionsService.debugReset();
      expect(PermissionsService.has('settlements.view'), isTrue,
          reason: 'سلوكٌ مقصود في الإنتاج، ومصيدةٌ في الاختبار');
    });

    test('وبعده يُحجب غير الممنوح', () {
      PermissionsService.debugSet(
        isEmployee: true,
        permissions: const {'reports.expenses': true},
      );
      expect(PermissionsService.has('reports.expenses'), isTrue);
      expect(PermissionsService.has('settlements.view'), isFalse);
      expect(PermissionsService.has('managers.edit'), isFalse);
    });

    test('والمدير يملك كلّ شيء', () {
      PermissionsService.debugSet(isEmployee: false);
      expect(PermissionsService.has('settlements.create'), isTrue);
      expect(PermissionsService.has('أيّ مفتاحٍ كان'), isTrue);
    });
  });

  // Pro: المدير الفرعيّ يُضبَط بصلاحيّات الساس المعياريّة (لا كامل الصلاحيّات).
  // دلالةٌ مختلفةٌ عن الموظّف: مفتاحٌ خارج خريطة الساس = مسموح (ميزةٌ تطبيقيّة).
  group('المدير الفرعيّ مقيَّدٌ بصلاحيّات الساس (Pro)', () {
    test('يختفي الممنوع، يظهر المسموح، والمفتاح خارج الخريطة مسموح', () {
      PermissionsService.debugSet(
        isEmployee: false,
        managerRestricted: true,
        managerCaps: const {
          'subscribers.delete': false,
          'subscribers.show_password': true,
          'subscribers.pay_debt': true,
        },
      );
      expect(PermissionsService.has('subscribers.delete'), isFalse);
      expect(PermissionsService.has('subscribers.show_password'), isTrue);
      expect(PermissionsService.has('subscribers.pay_debt'), isTrue);
      // خارج خريطة الساس (ميزةٌ تطبيقيّة لا يحكمها الساس) → مسموح افتراضاً
      expect(PermissionsService.has('settlements.view'), isTrue);
      expect(PermissionsService.isEmployee, isFalse);
    });

    test('hasAll/hasAny للمدير المقيَّد', () {
      PermissionsService.debugSet(
        isEmployee: false,
        managerRestricted: true,
        managerCaps: const {
          'subscribers.delete': false,
          'subscribers.edit': true,
        },
      );
      expect(
          PermissionsService.hasAll(
              const ['subscribers.edit', 'subscribers.delete']),
          isFalse);
      expect(
          PermissionsService.hasAny(
              const ['subscribers.delete', 'subscribers.edit']),
          isTrue);
      expect(PermissionsService.hasAll(const ['x.one', 'x.two']), isTrue);
    });

    test('super-admin غير مقيَّدٍ ولو مرّت خريطة', () {
      PermissionsService.debugSet(isEmployee: false);
      expect(PermissionsService.has('subscribers.delete'), isTrue);
    });
  });

  // ── بلاغ 2026-10-14: القوائم لا تختفي بالصلاحيّة — تبقى مقفلة بمكانها ──
  // العدّ بالنوع: البطاقتان خاصّتان بملفّيهما، فتُعرفان باسم نوعهما.
  Finder byTypeName(String name) =>
      find.byWidgetPredicate((w) => w.runtimeType.toString() == name);
  final moduleCards = byTypeName('_ModuleCard');
  final reportCards = byTypeName('_ReportCard');

  /// المسارات المدفوعة بعد الأوّل — النقر المقفل يجب ألّا يزيدها.
  Future<List<Route<dynamic>>> showScreen(WidgetTester t, Widget screen) async {
    // شاشةٌ طويلة كي تُبنى كلّ البطاقات (ListView يبني الظاهر وحده).
    t.view.physicalSize = const Size(800, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final pushed = <Route<dynamic>>[];
    await t.pumpWidget(MaterialApp(
      navigatorObservers: [_PushSpy(pushed)],
      home: Directionality(textDirection: TextDirection.rtl, child: screen),
    ));
    await t.pump();
    pushed.clear(); // مسار home نفسه
    return pushed;
  }

  group('«قوائم أخرى» — المقفل يبقى بمكانه', () {
    tearDown(() {
      ProviderService.debugSet(null);
      CardsState.badge.value = null;
    });

    testWidgets('🚨 موظّف ساس بـreports.expenses: البقيّة مقفلة لا مخفيّة',
        (t) async {
      PermissionsService.debugSet(
        isEmployee: true,
        permissions: const {'reports.expenses': true},
      );
      await showScreen(t, const MoreModulesScreen());
      // كلّ بطاقات المدير الـ12 حاضرة (ساس: كلّ مفتاحٍ يُمنح)…
      expect(moduleCards, findsNWidgets(12));
      // …مفتوحٌ منها «التقارير» (expenses مفتاح تقرير) و«الصرفيات»، و«بوابة
      // المشترك» لكلّ موظّف (رمز الوكيل — ١٨ أكتوبر).
      expect(find.byType(PermLockIcon), findsNWidgets(12 - 3));
      // ولا «لا صلاحيّات» فارغة.
      expect(find.text('more.empty_perms'), findsNothing);
    });

    testWidgets('🚨 النقر على بطاقةٍ مقفلة لا يفتح شاشة', (t) async {
      PermissionsService.debugSet(isEmployee: true);
      final pushed = await showScreen(t, const MoreModulesScreen());
      // كلّها مقفلة إلّا «بوابة المشترك» (رمز الوكيل لكلّ موظّف).
      expect(find.byType(PermLockIcon), findsNWidgets(11));
      await t.tap(moduleCards.first);
      await t.pump();
      expect(pushed, isEmpty, reason: 'المقفل لا يتنقّل ولا يطلب شيئاً');
      await t.pump(const Duration(seconds: 3)); // مؤقّت رسالة القفل
    });

    testWidgets('المدير: لا قفل، والبطاقات نفسها كما كانت', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await showScreen(t, const MoreModulesScreen());
      expect(moduleCards, findsNWidgets(12));
      expect(find.byType(PermLockIcon), findsNothing);
      // والكارتات حين يقول الخادم enabled.
      CardsState.badge.value = const CardsBadge(enabled: true, remaining: 4);
      await t.pump();
      expect(moduleCards, findsNWidgets(13));
      expect(find.byType(PermLockIcon), findsNothing);
    });

    testWidgets('الكارتات مقفلةً بلا تفعيل/تمديد', (t) async {
      PermissionsService.debugSet(isEmployee: true);
      CardsState.badge.value = const CardsBadge(enabled: true, remaining: 4);
      await showScreen(t, const MoreModulesScreen());
      final tile = find.ancestor(
          of: find.byIcon(LucideIcons.tickets), matching: moduleCards);
      expect(tile, findsOneWidget);
      expect(find.descendant(of: tile, matching: find.byType(PermLockIcon)),
          findsOneWidget);
      // بلا عدد المخزون — رقمٌ لا يملك أن يراه.
      expect(find.descendant(of: tile, matching: find.text('cards.module_hint')),
          findsOneWidget);
    });

    testWidgets('🚨 موظّف ايرث لنك: لا مدراء ولا موظّفون (مفتاحان لا يُمنحان)',
        (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(isEmployee: true);
      await showScreen(t, const MoreModulesScreen());
      expect(find.byIcon(LucideIcons.userCog), findsNothing); // المدراء
      expect(find.byIcon(LucideIcons.users), findsNothing); // الموظّفون
      // وتحويل الرصيد لصاحب الحساب، والتبليغات (البثّ لا يُمنح له).
      expect(find.byIcon(LucideIcons.arrowRightLeft), findsNothing);
      expect(find.byIcon(LucideIcons.bell), findsNothing);
      // وتلغرام لصاحب الحساب كالويب (لا مفتاح صريح له — الدفعة ① ١٨ أكتوبر).
      expect(find.byIcon(LucideIcons.send), findsNothing);
      // و«بوابة المشترك» مفتوحةٌ له (رمز الوكيل — وسيط البوّابة ١٨ أكتوبر)…
      final portal = find.ancestor(
          of: find.byIcon(LucideIcons.smartphone), matching: moduleCards);
      expect(portal, findsOneWidget);
      expect(find.descendant(of: portal, matching: find.byType(PermLockIcon)),
          findsNothing);
      // …والباقي (8) مقفلٌ كلّه بمكانه.
      expect(moduleCards, findsNWidgets(9));
      expect(find.byType(PermLockIcon), findsNWidgets(8));
    });

    // تدقيق ١٨ أكتوبر: تلغرام كان يظهر لموظّف ايرث لنك بـ`whatsapp.send` الضمنيّ
    // (تابعٌ لـ«إرسال واتساب») ويفتح إعداد البوت، والويب يخفيه (ownerOnly).
    // القاعدة الواحدة: لصاحب الحساب ما لم يوجد مفتاحٌ صريح.
    testWidgets('🚨 موظّف ايرث لنك بـ«إرسال واتساب»: لا تلغرام (لصاحب الحساب)',
        (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(isEmployee: true, permissions: const {
        'subscribers.send_whatsapp': true,
        'whatsapp.send': true,
      });
      await showScreen(t, const MoreModulesScreen());
      expect(find.byIcon(LucideIcons.send), findsNothing);
      // «حالة الرسائل» تبقى له — رسائله هو.
      expect(find.byIcon(LucideIcons.messageSquare), findsOneWidget);
    });

    testWidgets('موظّف ساس: تلغرام بمكانه (مقفلاً بلا مفاتيحه) كما كان',
        (t) async {
      PermissionsService.debugSet(isEmployee: true);
      await showScreen(t, const MoreModulesScreen());
      final tile = find.ancestor(
          of: find.byIcon(LucideIcons.send), matching: moduleCards);
      expect(tile, findsOneWidget);
      expect(find.descendant(of: tile, matching: find.byType(PermLockIcon)),
          findsOneWidget);
    });

    // الدفعة ①: «التبليغات» لايرث لنك كباقي الشركات — كانت مخفيّة (١٤ أكتوبر).
    testWidgets('🚨 مالك ايرث لنك: «التبليغات» بمكانها مفتوحةً حين يمنحها الخادم',
        (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(
        isEmployee: false,
        managerRestricted: true,
        managerCaps: const {'whatsapp.broadcast': true},
      );
      await showScreen(t, const MoreModulesScreen());
      final tile =
          find.ancestor(of: find.byIcon(LucideIcons.bell), matching: moduleCards);
      expect(tile, findsOneWidget, reason: 'لا مخفيّة');
      expect(find.descendant(of: tile, matching: find.byType(PermLockIcon)),
          findsNothing, reason: 'مفتوحة — لا قفل');
      expect(
          find.descendant(of: tile, matching: find.text('more.broadcast_hint')),
          findsOneWidget);
    });

    testWidgets('مالك ايرث لنك وخادمٌ لم يمنح البثّ بعد: بمكانها مقفلة',
        (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(
        isEmployee: false,
        managerRestricted: true,
        managerCaps: const {'whatsapp.broadcast': false},
      );
      await showScreen(t, const MoreModulesScreen());
      final tile =
          find.ancestor(of: find.byIcon(LucideIcons.bell), matching: moduleCards);
      expect(tile, findsOneWidget);
      expect(find.descendant(of: tile, matching: find.byType(PermLockIcon)),
          findsOneWidget);
    });

    // تدقيق البوّابة ٢٠٢٦-١٠-١٧ §2.7: لا بوّابة مشتركين لـFTTH، فإعدادات
    // «بوابة المشترك» تُحفظ ولا يقرؤها أحد. البطاقة تبقى بمكانها مقفلةً
    // **بالسبب** — لا مخفيّة، ولا «اطلبها من مديرك». (وايرث لنك كانت مثلها
    // حتى وسيط البوّابة ١٨ أكتوبر — الحالة التالية.)
    testWidgets(
        '🚨 مالك ftth: «بوابة المشترك» بمكانها «غير متوفّرة لشركتك بعد»',
        (t) async {
      ProviderService.debugSet('ftth');
      PermissionsService.debugSet(isEmployee: false);
      final pushed = await showScreen(t, const MoreModulesScreen());
      final tile = find.ancestor(
          of: find.byIcon(LucideIcons.smartphone), matching: moduleCards);
      expect(tile, findsOneWidget, reason: 'بمكانها لا مخفيّة');
      expect(find.descendant(of: tile, matching: find.byType(PermLockIcon)),
          findsOneWidget);
      expect(
          find.descendant(
              of: tile, matching: find.text('portal.unavailable_company')),
          findsOneWidget,
          reason: 'السبب مكان الوصف');
      // المالك يملك كلّ شيء — لا قفل غيرها.
      expect(find.byType(PermLockIcon), findsOneWidget);

      await t.tap(tile);
      await t.pump();
      expect(pushed, isEmpty, reason: 'لا شاشة تحفظ ما لا يُقرأ');
      // الإشعار يقول السبب (البطاقة + الإشعار) لا «اطلبها من مديرك».
      expect(find.text('portal.unavailable_company'), findsNWidgets(2));
      expect(find.text('locked.toast'), findsNothing);
      await t.pump(const Duration(seconds: 3)); // مؤقّت رسالة القفل
    });

    // وسيط البوّابة (١٨ أكتوبر، الخادم fdcc2d7): البوّابة موحّدة لكلّ
    // المزوّدين — مشتركو ايرث لنك يدخلون برمز وكيلهم. فالبطاقة مفتوحة.
    testWidgets('🚨 مالك ايرث لنك: «بوابة المشترك» مفتوحةٌ وتفتح الشاشة',
        (t) async {
      _offline();
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(isEmployee: false);
      final pushed = await showScreen(t, const MoreModulesScreen());
      final tile = find.ancestor(
          of: find.byIcon(LucideIcons.smartphone), matching: moduleCards);
      expect(tile, findsOneWidget);
      expect(find.descendant(of: tile, matching: find.byType(PermLockIcon)),
          findsNothing);
      expect(find.text('portal.unavailable_company'), findsNothing);
      expect(
          find.descendant(of: tile, matching: find.text('portal.subtitle_more')),
          findsOneWidget);
      await t.tap(tile);
      await t.pump();
      expect(pushed, hasLength(1), reason: 'تُفتح «بوابة المشترك»');
      await t.pump(const Duration(seconds: 1)); // ردود الخادم الوهميّ
    });

    // رمز الوكيل يحتاجه كلّ موظّف ليعطيه للمشترك، والخادم يعطيه بلا
    // صلاحيّة — فالبطاقة مفتوحة، والتخصيص داخلها مقفلٌ بـsettings.edit.
    testWidgets('موظّف ساس بلا settings.edit: البوّابة مفتوحة (رمز الوكيل)',
        (t) async {
      _offline();
      PermissionsService.debugSet(isEmployee: true);
      final pushed = await showScreen(t, const MoreModulesScreen());
      final tile = find.ancestor(
          of: find.byIcon(LucideIcons.smartphone), matching: moduleCards);
      expect(find.descendant(of: tile, matching: find.byType(PermLockIcon)),
          findsNothing);
      expect(find.descendant(of: tile, matching: find.text('portal.subtitle_more')),
          findsOneWidget);
      expect(find.text('portal.unavailable_company'), findsNothing);
      await t.tap(tile);
      await t.pump();
      expect(pushed, hasLength(1));
      await t.pump(const Duration(seconds: 1)); // ردود الخادم الوهميّ
    });
  });

  group('للشركة بوّابة مشتركين؟', () {
    tearDown(() => ProviderService.debugSet(null));

    test('SAS4 وايرث لنك نعم (وسيط البوّابة) · FTTH لا', () {
      // SAS4 (ومنه ساس `ftth` فايبر الجزيرة) بلا provider في `/api/auth/me`.
      ProviderService.debugSet(null);
      expect(ProviderService.hasSubscriberPortal, isTrue);
      ProviderService.debugSet('earthlink');
      expect(ProviderService.hasSubscriberPortal, isTrue);
      ProviderService.debugSet('ftth');
      expect(ProviderService.isFtth, isTrue);
      expect(ProviderService.hasSubscriberPortal, isFalse);
    });

    test('رمز QR/رابط المعلومات: SAS4 وحده بعد', () {
      // بطاقة `/api/user-info` لا تقرأ ايرث لنك، وQR ايرث لنك لتطبيق 2.0.7.
      ProviderService.debugSet(null);
      expect(ProviderService.hasPortalQrCard, isTrue);
      ProviderService.debugSet('earthlink');
      expect(ProviderService.hasPortalQrCard, isFalse);
      ProviderService.debugSet('ftth');
      expect(ProviderService.hasPortalQrCard, isFalse);
    });
  });

  group('مركز التقارير — المقفل يبقى بمكانه', () {
    tearDown(() => ProviderService.debugSet(null));

    bool lockedCard(IconData icon) {
      final card = find.ancestor(of: find.byIcon(icon), matching: reportCards);
      return find
          .descendant(of: card, matching: find.byType(PermLockIcon))
          .evaluate()
          .isNotEmpty;
    }

    testWidgets(
        '🚨 موظّف ايرث لنك بلا reports.activations: بطاقتان من ثلاث مقفلتان',
        (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(
        isEmployee: true,
        permissions: const {'reports.activity_log': true},
      );
      final pushed = await showScreen(t, const ReportsHubScreen());
      // 5 تقارير عامّة (ديون المدراء لا تُمنح له فمخفيّة) + 3 لايرث لنك.
      expect(reportCards, findsNWidgets(8));
      expect(lockedCard(LucideIcons.flaskConical), isTrue); // التجريبي
      expect(lockedCard(LucideIcons.package), isTrue); // حسب الباقة
      // السجلّان (العامّ وايرث لنك) مفتوحان بـactivity_log.
      expect(find.byType(PermLockIcon), findsNWidgets(6));
      await t.tap(find.ancestor(
          of: find.byIcon(LucideIcons.flaskConical), matching: reportCards));
      await t.pump();
      expect(pushed, isEmpty);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('موظّف ساس بلا مفاتيح: كلّ التقارير الستّ مقفلة', (t) async {
      PermissionsService.debugSet(isEmployee: true);
      await showScreen(t, const ReportsHubScreen());
      expect(reportCards, findsNWidgets(6));
      expect(find.byType(PermLockIcon), findsNWidgets(6));
      expect(find.text('reports.empty_perms'), findsNothing);
    });

    testWidgets('المدير: لا قفل', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await showScreen(t, const ReportsHubScreen());
      expect(reportCards, findsNWidgets(6));
      expect(find.byType(PermLockIcon), findsNothing);
    });
  });
}

class _PushSpy extends NavigatorObserver {
  _PushSpy(this.pushed);
  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pushed.add(route);
}

/// بلا شبكة: الشاشة التي يفتحها النقر تسأل خادمها فتأخذ ٤٠٤ فوراً — لا
/// نداء حقيقيّ ولا مؤقّتٌ معلَّق بعد نهاية الاختبار.
class _Offline implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async =>
      ResponseBody.fromString('{"success":false}', 404, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

/// ما تحتاجه شاشةٌ تُفتح بالنقر: خزنةٌ وهميّة وخادمٌ بلا شبكة.
void _offline() {
  FlutterSecureStorage.setMockInitialValues({});
  ApiClient.dio.httpClientAdapter = _Offline();
}
