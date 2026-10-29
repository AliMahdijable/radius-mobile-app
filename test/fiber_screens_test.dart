import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/bdcom_epon.dart';
import 'package:rad_mysvcs/api/olt_fiber_reads.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/core/util/bidi.dart';
import 'package:rad_mysvcs/models/fiber_network.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_diagnosis_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_home_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_light_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_link_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_map_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_outage_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_pon_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_search_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_settings_sheet.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_sheets.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_subscriber_card.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_tech_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_widgets.dart';
import 'package:rad_mysvcs/services/fiber/fiber_monitor.dart';
import 'package:rad_mysvcs/services/fiber/fiber_store.dart';
import 'package:rad_mysvcs/services/fiber/fiber_tree.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/theme/typography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';
import 'support/fake_snmp_agent.dart';
import 'support/fiber_fixture.dart';

/// شاشات «شبكة الألياف» كما يراها الوكيل: أولت BDCOM وهميّ (SNMP في الذاكرة) بمنفذين وصناديق، وخادمٌ وهميّ — بعرض
/// الهاتف ٣٦٠/٤٣٠ والحاسبة، نهاراً وليلاً، بلا فيضٍ ولا استثناء، ومعها الأفعال: «التقط بالفصل»، «ثبّت الأكيدة»،
/// الإعدادات، والبحث.
const _phone = Size(360, 780);
const _phoneWide = Size(430, 932);
const _desk = Size(1260, 860);

void main() {
  setUpAll(loadAppFonts);

  late FiberTestServer server;
  late FiberTestOlt olt;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth.token': 't', 'auth.admin_id': '2'});
    SharedPreferences.setMockInitialValues({});
    server = FiberTestServer();
    ApiClient.dio.httpClientAdapter = server;
    // معترضات العميل تقرأ التوكن من خزنة الحاسبة (ملفّ حقيقيّ) — لا تكتمل بزمن الاختبار الوهميّ.
    final interceptors = List<Interceptor>.of(ApiClient.dio.interceptors);
    ApiClient.dio.interceptors.clear();
    // ⚠️ `clear()` يُبقي ImplyContentTypeInterceptor ⇒ الإرجاع كان يضيف نسخةً منه كلّ اختبار، فيمرّ كلّ طلبٍ بعشرات
    // النسخ وتتباطأ الاختبارات الأخيرة حتى تعلق (٢٨ أكتوبر: «الربط» ٢٢ث و«البحث» ٨٦ث). الإرجاع يمسح كلّ شيء.
    addTearDown(() {
      ApiClient.dio.interceptors
        ..clear(keepImplyContentTypeInterceptor: false)
        ..addAll(interceptors);
    });
    olt = FiberTestOlt();
    FiberMonitor.debugReset();
    FiberMonitor.backend = FiberTestBackend(olt);
    FiberStore.reset();
    FiberStore.debugSet(fiberTestLayout());
    FiberLinkScreen.debugReset();
    FiberSubscriberCard.debugReset();
    PermissionsService.debugReset();
  });

  tearDown(() {
    FiberMonitor.debugReset();
    AppColors.setDarkMode(false);
  });

  /// يرسم [screen] بالمقاس والوضع، وينتظر قراءة الأولت الأولى.
  Future<void> pumpScreen(WidgetTester t, Widget screen, {Size size = _phone, bool desk = false, bool dark = false}) async {
    AppColors.setDarkMode(dark);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: AppType.family),
      builder: (ctx, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(
          data: MediaQuery.of(ctx).copyWith(disableAnimations: true),
          child: desk ? DesktopScope(child: child!) : child!,
        ),
      ),
      home: screen,
    ));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 30));
    }
  }

  /// تمريرة الصفحة نفسها (لا شرائح الفلترة الأفقيّة).
  Finder mainScroll() => find.descendant(of: find.byType(FiberPage), matching: find.byType(Scrollable)).first;

  /// يُزيل الشجرة ويُنسي المراقبات (المصدر الوهميّ يبقى).
  Future<void> unmount(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump();
    FiberMonitor.resetAll();
  }

  /// كلّ شاشة × (هاتف ٣٦٠، هاتف ٤٣٠، حاسبة) × (نهار، ليل) — بلا فيضٍ ولا استثناء.
  Future<void> everyLayout(WidgetTester t, Widget Function(FiberMonitor m) build, {void Function(FiberMonitor m)? check}) async {
    for (final (size, desk) in const [(_phone, false), (_phoneWide, false), (_desk, true)]) {
      for (final dark in const [false, true]) {
        final m = FiberMonitor.of(fiberTestDevice());
        await pumpScreen(t, build(m), size: size, desk: desk, dark: dark);
        expect(t.takeException(), isNull, reason: '${size.width} ${desk ? 'حاسبة' : 'هاتف'} ${dark ? 'ليل' : 'نهار'}');
        check?.call(m);
        await unmount(t);
      }
    }
  }

  // ورقةٌ تُفتح: الإطار الأوّل يبدأ انزلاقها والثاني ينهيه — بإطارٍ واحد تبقى تحت الشاشة فتخطئ النقرات.
  Future<void> sheetIn(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
  }

  testWidgets('الرئيسيّة: المتّصلون والضوء والمنافذ والأدوات — والعطل بمكانه حين يسقط صندوق', (t) async {
    await everyLayout(t, (m) => FiberHomeScreen(olts: [fiberTestDevice()], initialOltId: 9));
    // صندوقٌ يسقط كلّه
    olt.drop([for (var i = 1; i <= 12; i++) 300 + i]);
    final m = FiberMonitor.of(fiberTestDevice());
    await pumpScreen(t, FiberHomeScreen(olts: [fiberTestDevice()], initialOltId: 9));
    expect(find.text('شبكة الألياف'), findsWidgets);
    expect(find.textContaining('صندوق 3-أ'), findsWidgets);
    expect(m.outages.single.scopeKey, 'box:2');
    expect(server.to('/api/v2/admin/devices/fiber/events').length, 1, reason: 'العطل يُبلَّغ للخادم مرّةً');
    expect(t.takeException(), isNull);
    await unmount(t);
  });

  testWidgets('المنفذ: الشجرة بصناديقها، وما بلا صندوق ظاهرٌ بعدده', (t) async {
    await everyLayout(t, (m) => FiberPonScreen(monitor: m, pon: 'EPON0/3'));
    await pumpScreen(t, FiberPonScreen(monitor: FiberMonitor.of(fiberTestDevice()), pon: 'EPON0/3'));
    expect(find.textContaining('صندوق 3-أ'), findsWidgets);
    expect(find.textContaining('موزّع رئيسي'), findsWidgets);
    // نصٌّ وحيد (مفتاح «إظهار الصناديق» فوق الشجرة يدفع البطاقة لأسفل — لا `.first` على ما لم يُبنَ بعد).
    await t.scrollUntilVisible(find.textContaining('جهازان بلا صندوق'), 200, scrollable: mainScroll());
    expect(find.textContaining('جهازان بلا صندوق'), findsOneWidget, reason: 'EPON0/3:23 و24 بلا سجلّ');
    await unmount(t);
  });

  // المالك ٢٨ أكتوبر: «من يصيرن صناديق هواي وموزعات هواي لازم اكو امكانيه يسوي توكل المدير ويخفيهن».
  testWidgets('المنفذ: «إظهار الصناديق» مطفأ ⇒ الموزّعات بأرقام ما تحتها، والضغط على الموزّع يكشف صناديقه', (t) async {
    await pumpScreen(t, FiberPonScreen(monitor: FiberMonitor.of(fiberTestDevice()), pon: 'EPON0/3'));
    expect(find.textContaining('صندوق 3-أ'), findsWidgets);
    await t.tap(find.text('إظهار الصناديق'));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('صندوق 3-أ'), findsNothing, reason: 'الصناديق مخفيّة');
    expect(find.textContaining('موزّع رئيسي'), findsWidgets, reason: 'الموزّع يبقى');
    expect(find.textContaining('مخفيّة تحته'), findsOneWidget);
    await t.tap(find.textContaining('موزّع رئيسي').first);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('صندوق 3-أ'), findsWidgets, reason: 'كُشفت صناديق الموزّع');
    expect(t.takeException(), isNull);
    await unmount(t);
  });

  // المالك ٢٨ أكتوبر: «من احدد بوكس ١:٨ مفروض ميتقبل اكثر من هلشي».
  testWidgets('السعة: صندوق ١:٨ فيه ٥ لا يقبل ٤ جدد، والنسبة لا تقلّ عن المستعمل، والموزّع الممتلئ لا يأخذ فرعاً', (t) async {
    final m = FiberMonitor.of(fiberTestDevice());
    await pumpScreen(t, FiberPonScreen(monitor: m, pon: 'EPON0/3'), size: _phoneWide);
    final ctx = t.element(find.byType(FiberPonScreen));
    final tree = FiberPonTree.build(oltId: 9, pon: 'EPON0/3', layout: FiberStore.layout.value, onus: m.onus);
    expect(tree.freePorts(3), 3, reason: 'صندوق 3-ب: ٥ من ٨');

    // ٤ أجهزة من صندوق 3-أ إلى 3-ب ⇒ لا يتّسع
    showFiberAssignSheet(ctx, oltId: 9, pon: 'EPON0/3', onus: tree.all, boxId: 3,
        preselect: {for (var i = 1; i <= 4; i++) 'EPON0/3:$i'});
    await sheetIn(t);
    expect(find.text('الصندوق ما يتّسع'), findsOneWidget);
    expect(find.textContaining('يتّسع لـ'), findsOneWidget);
    final checked = find.byWidgetPredicate((w) => w is CheckboxListTile && w.value == true);
    expect(t.getTopLeft(checked.first).dy < t.getTopLeft(find.byType(CheckboxListTile).last).dy, isTrue,
        reason: 'المختار عند الفتح بأعلى القائمة');
    await t.ensureVisible(checked.first);
    await t.pump(const Duration(milliseconds: 100));
    expect(checked.first.hitTestable(), findsOneWidget);
    await t.tap(checked.first);
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('الصندوق ما يتّسع'), findsNothing, reason: 'ثلاثة تتّسع');
    Navigator.of(ctx).pop();
    await t.pump(const Duration(milliseconds: 400));

    // النسبة: ١:٢ و١:٤ معطّلتان لصندوقٍ فيه ٥
    showFiberBoxSheet(ctx, oltId: 9, pon: 'EPON0/3', initial: FiberStore.layout.value.boxes[3], tree: tree);
    await sheetIn(t);
    ChoiceChip chip(String r) => t.widget<ChoiceChip>(find.byWidgetPredicate(
        (w) => w is ChoiceChip && w.label is Text && ((w.label as Text).data ?? '').contains(r)));
    expect(chip('1:4').onSelected, isNull);
    expect(chip('1:2').onSelected, isNull);
    expect(chip('1:16').onSelected, isNotNull);
    Navigator.of(ctx).pop();
    await t.pump(const Duration(milliseconds: 400));

    // صندوقٌ فاض قبل الحدّ (١:٤ فيه ٥): يبقى يُعدَّل باسمه ونسبته الحاليّة، والتنبيه يقول كبّرها — والتصغير ممنوع.
    final over = FiberStore.layout.value.boxes[3]!.copyWith(ratio: 4);
    FiberStore.debugSet(FiberStore.layout.value.withBox(over));
    await t.pump(const Duration(milliseconds: 100));
    showFiberBoxSheet(ctx, oltId: 9, pon: 'EPON0/3', initial: over, tree: tree);
    await sheetIn(t);
    expect(chip('1:4').onSelected, isNotNull, reason: 'نسبته الحاليّة تبقى');
    expect(chip('1:2').onSelected, isNull);
    expect(find.textContaining('أكثر من نسبته'), findsOneWidget);
    await t.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first, 'صندوق 3-ب الجديد');
    await t.tap(find.text('حفظ'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('النسبة لا تقلّ'), findsNothing);
    expect(server.requests.where((r) => r.method == 'PUT' && r.uri.path.endsWith('/fiber/boxes/3')), hasLength(1),
        reason: 'الحفظ وصل الخادم');
    await t.pump(const Duration(milliseconds: 400));

    // موزّع 1:4 بأربعة فروع ⇒ صندوقٌ جديد تحته يُرفض بسببه
    FiberStore.debugSet(FiberStore.layout.value
        .withBox(const FiberBox(id: 5, oltId: 9, pon: 'EPON0/3', name: 'صندوق 3-د', parentId: 1, ratio: 8)));
    await t.pump(const Duration(milliseconds: 100));
    final full = FiberPonTree.build(oltId: 9, pon: 'EPON0/3', layout: FiberStore.layout.value, onus: m.onus);
    expect(full.canHang(1), isFalse);
    showFiberBoxSheet(ctx, oltId: 9, pon: 'EPON0/3', parentId: 1, tree: full);
    await sheetIn(t);
    await t.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first, 'صندوق جديد');
    expect(find.text('إضافة').hitTestable(), findsOneWidget, reason: 'الزرّ ظاهرٌ تحت الإصبع');
    await t.tap(find.text('إضافة'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.textContaining(RegExp('ممتلئ \\(\u2068?4/4')), findsOneWidget, reason: 'رسالة الرفض بسببها (الرقم معزول الاتّجاه)');
    expect(FiberStore.layout.value.boxes.values.any((b) => b.name == 'صندوق جديد'), isFalse, reason: 'لم يُحفظ');
    expect(t.takeException(), isNull);
    await unmount(t);
  });

  // المالك ٢٩ أكتوبر: «تحديد موقع بقسم الألياف… اختيار موقع يدوي كذلك مثل ما موجود بوضع اليوزر نكدر نحدد احداثيات».
  testWidgets('موقع الصندوق: ثلاث طرق — كتابة/لصق إحداثيّات، اختر من الخريطة، موقعي الآن — واللصق يُحفظ', (t) async {
    await pumpScreen(t, FiberPonScreen(monitor: FiberMonitor.of(fiberTestDevice()), pon: 'EPON0/3'), size: _phoneWide);
    final ctx = t.element(find.byType(FiberPonScreen));
    final tree = FiberPonTree.build(oltId: 9, pon: 'EPON0/3', layout: FiberStore.layout.value, onus: FiberMonitor.of(fiberTestDevice()).onus);

    // صندوقٌ جديد: الطرق الثلاث حاضرة (كتعديل موقع المشترك).
    showFiberBoxSheet(ctx, oltId: 9, pon: 'EPON0/3', tree: tree);
    await sheetIn(t);
    expect(find.text('اختر من الخريطة'), findsOneWidget);
    expect(find.text('موقعي الآن'), findsOneWidget);
    // أربعة حقول: الاسم · المكان · الإحداثيّات · ملاحظة. حقل الإحداثيّات هو الثالث.
    final coords = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).at(2);
    await t.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first, 'صندوق موقعه');
    await t.enterText(coords, '33.312345, 44.361234');
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('إضافة'));
    await t.pump(const Duration(milliseconds: 300));
    final saved = server.to('/api/v2/admin/devices/fiber/boxes/0', 'PUT');
    expect(saved, hasLength(1), reason: 'صندوقٌ جديد يُحفظ بالخادم');
    final body = saved.single.data as Map;
    expect((body['lat'] as num).toStringAsFixed(6), '33.312345');
    expect((body['lng'] as num).toStringAsFixed(6), '44.361234');
    expect(body['name'], 'صندوق موقعه');
    await t.pump(const Duration(milliseconds: 400));

    // إحداثيّاتٌ غير صالحة: لا تُحفظ صامتةً — رسالةٌ تقول السبب، ولا طلب جديد.
    final before = server.to('/api/v2/admin/devices/fiber/boxes/0', 'PUT').length;
    showFiberBoxSheet(ctx, oltId: 9, pon: 'EPON0/3', tree: tree);
    await sheetIn(t);
    await t.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first, 'صندوقٌ ثانٍ');
    await t.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).at(2), 'رابط غير صالح');
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('إضافة'));
    await t.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('ما قدرت أستخرج إحداثيّات'), findsWidgets);
    expect(server.to('/api/v2/admin/devices/fiber/boxes/0', 'PUT').length, before, reason: 'لم يُحفظ بإحداثيّاتٍ فاسدة');
    expect(t.takeException(), isNull);
    await unmount(t);
  });

  // المالك ٢٩ أكتوبر: «البون (الكابينات الفرعية) نضيف زر بحث، واليوزر نظهر ويا اسم عربي».
  testWidgets('المنفذ: البحث يصفّي الأجهزة، والاسم العربيّ يظهر مع اليوزر', (t) async {
    FiberLinkScreen.debugSeed(directory: {'sub1': fiberTestSub('sub1', first: 'علي', last: 'حسن')});
    await pumpScreen(t, FiberPonScreen(monitor: FiberMonitor.of(fiberTestDevice()), pon: 'EPON0/3'));
    final box = find.widgetWithIcon(TextField, LucideIcons.search);
    expect(box, findsOneWidget, reason: 'زرّ/حقل البحث حاضر');
    // بحثٌ بالاسم العربيّ ⇒ نتائج مسطّحة، والاسم عنواناً واليوزر معه.
    await t.enterText(box, 'علي');
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('نتائج البحث'), findsOneWidget);
    expect(find.textContaining('علي حسن'), findsWidgets);
    expect(find.textContaining('sub1'), findsWidgets, reason: 'اليوزر مع الاسم');
    // يوزرٌ بلا اسمٍ بالدليل يُطابق هو، والاسم العربيّ يختفي.
    await t.enterText(box, 'sub2');
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('علي حسن'), findsNothing);
    expect(find.textContaining('sub2'), findsWidgets);
    // لا تطابق ⇒ رسالة.
    await t.enterText(box, 'zzz-nomatch');
    await t.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('لا أجهزة تطابق'), findsOneWidget);
    FiberLinkScreen.debugReset();
    await unmount(t);
  });

  // المالك ٢٨ أكتوبر: «رسم خريطة بمسارات الضوئي ٢d… يوضح سيرفر الترفك والربط».
  testWidgets('مخطّط الشبكة: يُرسم بكلّ مقاس ووضع، والرقائق تخفي الصناديق وما بلا صندوق', (t) async {
    await everyLayout(t, (m) => FiberMapScreen(olts: [fiberTestDevice()], initialOltId: 9));
    await pumpScreen(t, FiberMapScreen(olts: [fiberTestDevice()], initialOltId: 9));
    expect(find.text('مخطّط الشبكة'), findsWidgets);
    expect(find.byType(CustomPaint), findsWidgets);
    // الرقاقة معزولة الاتّجاه (iso) ⇒ تطابقٌ جزئيّ.
    await t.tap(find.textContaining('الصناديق'));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.textContaining('بلا صندوق'));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
    await unmount(t);
  });

  testWidgets('العطل الآن: المكان والسبب والفنّي والمتأثرون', (t) async {
    olt.drop([for (var i = 1; i <= 12; i++) 300 + i]);
    await everyLayout(t, (m) => FiberOutageScreen(monitor: m, scopeKey: 'box:2'));
    await pumpScreen(t, FiberOutageScreen(monitor: FiberMonitor.of(fiberTestDevice()), scopeKey: 'box:2'));
    expect(find.textContaining('قطع بالليف'), findsWidgets);
    expect(find.text('أرسل الموقع للفنّي'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('المتأثرون'), 300, scrollable: mainScroll());
    expect(find.text('المتأثرون · 12'), findsOneWidget);
    await unmount(t);
  });

  testWidgets('تشخيص جهاز: الحكم والخطوات وجهاز الألياف وجيرانه', (t) async {
    await everyLayout(t, (m) => FiberDiagnosisScreen(monitor: m, onuKey: 'EPON0/3:16'));
    await pumpScreen(t, FiberDiagnosisScreen(monitor: FiberMonitor.of(fiberTestDevice()), onuKey: 'EPON0/3:16'));
    expect(find.text('الفحص خطوة بخطوة'), findsOneWidget);
    await t.scrollUntilVisible(find.text('جهاز الألياف').first, 300, scrollable: mainScroll());
    expect(find.textContaining('-28.1'), findsWidgets, reason: 'ضوءه الضعيف ظاهر بقيمته');
    await unmount(t);
  });

  testWidgets('صحّة الضوء: الرتب الأربع والتوزيع وقائمة ما يحتاج انتباهاً', (t) async {
    await everyLayout(t, (m) => FiberLightScreen(monitor: m));
    await pumpScreen(t, FiberLightScreen(monitor: FiberMonitor.of(fiberTestDevice())));
    expect(find.text('توزيع الضوء'), findsOneWidget);
    await t.scrollUntilVisible(find.textContaining('تحتاج انتباهاً'), 300, scrollable: mainScroll());
    expect(find.text('تحتاج انتباهاً الآن · 2'), findsOneWidget, reason: '-26.8 حدّي و-28.1 ضعيف');
    await unmount(t);
  });

  testWidgets('وضع الفنّي: المقياس وقبل/بعد والبلاطات — بلا جهاز يطلب الاختيار', (t) async {
    await everyLayout(t, (m) => FiberTechScreen(monitor: m, onuKey: 'EPON0/3:5'));
    await everyLayout(t, (m) => FiberTechScreen(monitor: m));
    await pumpScreen(t, FiberTechScreen(monitor: FiberMonitor.of(fiberTestDevice()), onuKey: 'EPON0/3:5'));
    expect(find.text('-21.0'), findsWidgets, reason: 'الضوء الآن بالمقياس');
    expect(find.textContaining('قبل ·'), findsOneWidget);
    expect(find.text('الإرسال'), findsOneWidget);
    expect(find.text(iso('2.3 dBm')), findsOneWidget);
    await unmount(t);
  });

  testWidgets('«التقط بالفصل»: الفصل يكشف الجهاز ويختاره، وضوءه قبل الفصل يصير «قبل»', (t) async {
    final m = FiberMonitor.of(fiberTestDevice());
    await pumpScreen(t, FiberTechScreen(monitor: m));
    expect(find.textContaining('اختر الجهاز'), findsWidgets);
    await t.tap(find.byIcon(LucideIcons.unplug));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text('التقط بالفصل'), findsOneWidget);
    expect(find.textContaining('نراقب'), findsOneWidget);
    // الفنّي يفصل ليف ONU 3:7
    olt.unplug(307);
    await t.pump(const Duration(seconds: 2));
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 30));
    }
    expect(find.text('التقط بالفصل'), findsNothing, reason: 'النافذة أغلقت بجهازٍ واحد');
    expect(find.textContaining('ONU 3:7'), findsWidgets);
    expect(find.textContaining('قبل ·'), findsOneWidget, reason: 'ضوءه قبل الفصل محفوظ');
    expect(find.text(iso('-21.6')), findsOneWidget, reason: '-195 - 7×3 = -216');
    expect(m.techRecent.first, 'EPON0/3:7');
    expect(t.takeException(), isNull);
    await unmount(t);
  });

  testWidgets('«التقط بالفصل»: جهازان بنفس اللحظة ⇒ يختار الفنّي من بينهما', (t) async {
    final m = FiberMonitor.of(fiberTestDevice());
    await pumpScreen(t, FiberTechScreen(monitor: m));
    await t.tap(find.byIcon(LucideIcons.unplug));
    await t.pump(const Duration(milliseconds: 50));
    olt.unplug(302);
    olt.unplug(303);
    await t.pump(const Duration(seconds: 2));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('تغيّرت جهازان بنفس اللحظة'), findsOneWidget);
    await t.tap(find.textContaining('sub3').first);
    await t.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('ONU 3:3'), findsWidgets);
    await unmount(t);
  });

  testWidgets('الربط: المقترح بسببه، و«ثبّت الأكيدة» يحفظ للخادم', (t) async {
    FiberLinkScreen.debugSeed(
      sessions: {'ali.k12': '02:00:00:00:03:04'},
      directory: {
        'ali.k12': fiberTestSub('ali.k12', first: 'علي', last: 'كريم'),
        'u20': fiberTestSub('u20'),
      },
    );
    // ONU 3:20 اسمها على الأولت يوزر مشترك، وONU 3:21 ماكها نفسه ماك جلسة ali.k12.
    olt.agent.put('${OltFiberReads.ifAliasOid}.320', snmpText('', 'u20'));
    olt.agent.put('${BdcomEpon.onuMacOid}.321', snmpBytes('', [2, 0, 0, 0, 3, 4]));
    await everyLayout(t, (m) => FiberLinkScreen(monitor: m));
    await pumpScreen(t, FiberLinkScreen(monitor: FiberMonitor.of(fiberTestDevice())));
    expect(find.text('ربط الأجهزة بالمشتركين'), findsWidgets);
    expect(find.textContaining('من 30 جهازاً مربوط بمشترك'), findsOneWidget);
    expect(find.text(iso('3')), findsWidgets, reason: 'المربوط ثلاثة');
    expect(find.text('مقترح · 2'), findsOneWidget);
    expect(find.textContaining('اسم الجهاز على الأولت = يوزره'), findsOneWidget);
    expect(find.textContaining('الجهاز نفسه يتّصل بيوزره'), findsOneWidget);
    expect(find.textContaining('علي كريم', findRichText: true), findsOneWidget, reason: 'الاسم من دليل الحساب لا اليوزر وحده');

    await t.tap(find.text('ثبّت الأكيدة (2)'));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 30));
    }
    final l = FiberStore.layout.value;
    expect(l.recordFor(9, 'EPON0/3:20', null)?.username, 'u20');
    expect(l.recordFor(9, 'EPON0/3:21', '020000000304')?.username, 'ali.k12');
    expect(l.recordFor(9, 'EPON0/3:21', '020000000304')?.source, FiberLinkSource.onuMac);
    final posted = server.to('/api/v2/admin/devices/fiber/onus').single.data as Map;
    expect((posted['records'] as List).map((r) => (r as Map)['username']).toSet(), {'u20', 'ali.k12'});
    expect(find.text('ثُبّتت كلّ الأكيدة'), findsOneWidget);
    expect(find.text(iso('مربوط')), findsNWidgets(2), reason: 'المثبَّت يبقى بمكانه بحبّة «مربوط»');
    expect(t.takeException(), isNull);
    await t.pump(const Duration(seconds: 4)); // رسالة «ثُبّت ربط…» تختفي
    await unmount(t);
  });

  testWidgets('البحث: «3:7» والماك واليوزر — والاختيار لوضع الفنّي يُرجع المفتاح', (t) async {
    await everyLayout(t, (m) => FiberSearchScreen(monitor: m));
    await pumpScreen(t, FiberSearchScreen(monitor: FiberMonitor.of(fiberTestDevice())));
    await t.enterText(find.byType(TextField), 'sub2');
    await t.pump();
    expect(find.text('sub2'), findsOneWidget);
    await t.enterText(find.byType(TextField), '3:7');
    await t.pump();
    expect(find.textContaining('ONU 3:7'), findsWidgets);
    expect(t.takeException(), isNull);
    await unmount(t);
  });

  testWidgets('الإعدادات: رقمٌ غلط يُرفض، والصحيح يُحفظ مع التنبيهات وأقلّ عدد', (t) async {
    t.view.physicalSize = _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(fontFamily: AppType.family),
      builder: (ctx, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showFiberSettingsSheet(ctx, oltId: 9, oltName: 'أولت المركز'),
              child: const Text('افتح'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('افتح'));
    await t.pumpAndSettle();
    expect(find.text('إعدادات شبكة الألياف'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'رقم الفنّي'), '12345');
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(find.textContaining('رقم الفنّي غير صحيح'), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'رقم الفنّي'), '0770 123 4567');
    await t.tap(find.byTooltip('أكثر'));
    await t.pump();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(find.text('إعدادات شبكة الألياف'), findsNothing);
    final s = FiberStore.layout.value.settingsOf(9);
    expect(s.techPhone, '07701234567');
    expect(s.minOnus, 4);
    expect(server.to('/api/v2/admin/devices/fiber/settings/9', 'PUT').length, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('كرت صفحة المشترك: المربوط يرى جهازه وحالته وضوءه، وغير المربوط بلا كرت، والموظّف بلا مراقبة مقفل', (t) async {
    FiberSubscriberCard.devices = () async => [fiberTestDevice()];
    Future<void> card(Subscriber s, {bool dark = false}) async {
      AppColors.setDarkMode(dark);
      t.view.physicalSize = _phone;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(fontFamily: AppType.family),
        builder: (ctx, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
        home: Scaffold(body: ListView(padding: const EdgeInsets.all(16), children: [FiberSubscriberCard(sub: s)])),
      ));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 30));
      }
    }

    for (final dark in [false, true]) {
      await card(fiberTestSub('sub2'), dark: dark);
      expect(find.text('جهاز الألياف'), findsOneWidget);
      expect(find.text(iso('متّصل')), findsOneWidget);
      expect(find.text('تشخيص الجهاز'), findsNothing, reason: 'مطويٌّ أوّلاً');
      await t.tap(find.text('جهاز الألياف'));
      await t.pumpAndSettle();
      expect(find.textContaining('ONU 3:2 · صندوق 3-أ · أولت المركز'), findsOneWidget);
      expect(find.text('تشخيص الجهاز'), findsOneWidget);
      await t.tap(find.text('جهاز الألياف'));
      await t.pumpAndSettle();
      expect(find.text('تشخيص الجهاز'), findsNothing, reason: 'نقرةٌ ثانية تطويه');
      expect(t.takeException(), isNull);
      await unmount(t);
    }

    // ضوءٌ ضعيف (المالك على nael2: ‎-31.0): التنبيه بالعنوان والكرت مطويّ، بعرض ٣٢٠ بلا فيض.
    olt.agent.put('${BdcomEpon.rxOid}.302', snmpInt('', -310));
    FiberMonitor.debugReset();
    FiberMonitor.backend = FiberTestBackend(olt);
    await card(fiberTestSub('sub2'));
    t.view.physicalSize = const Size(320, 700);
    await t.pump();
    expect(find.text(iso('ضوء ضعيف ${iso('-31.0')}')), findsOneWidget);
    expect(find.text(iso('متّصل')), findsNothing);
    expect(t.takeException(), isNull);
    await t.tap(find.text('جهاز الألياف'));
    await t.pumpAndSettle();
    expect(find.text(iso('متّصل')), findsOneWidget, reason: 'مفتوحاً: الحالة بالعنوان والضوء بسطره');
    expect(find.text(iso('ضعيف')), findsOneWidget);
    expect(t.takeException(), isNull);
    await unmount(t);

    await card(fiberTestSub('nobody'));
    expect(find.text('جهاز الألياف'), findsNothing);
    await unmount(t);

    PermissionsService.debugSet(isEmployee: true, permissions: const {'devices.view': true});
    await card(fiberTestSub('sub2'));
    expect(find.text('جهاز الألياف'), findsOneWidget);
    expect(find.text(iso('لا صلاحيّة')), findsOneWidget, reason: 'القفل بالعنوان والكرت مطويّ');
    await t.tap(find.text('جهاز الألياف'));
    await t.pumpAndSettle();
    expect(find.text('لا صلاحيّة'), findsOneWidget, reason: 'وزرّ التشخيص بقفله');
    expect(FiberMonitor.existing(9), isNull, reason: 'بلا صلاحيّة لا يُقرأ الأولت');
    await unmount(t);
  });
}
