import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/core/widgets/app_sheet.dart';
import 'package:rad_mysvcs/models/network_device.dart';
import 'package:rad_mysvcs/screens/network_devices/network_device_form_sheet.dart';
import 'package:rad_mysvcs/screens/network_devices/network_devices_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/regions_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/devices_filter_bar.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/device_alerts_service.dart';
import 'package:rad_mysvcs/theme/spacing.dart';

import 'sim_el/sim_harness.dart';
import 'support/ai_status_overlay.dart';
import 'support/devices_demo_data.dart';
import 'visual_perm/visual_perm_harness.dart';

/// شاشة الأجهزة تطلب صلاحيّة الإشعارات المحلّيّة عند فتحها — لا منصّة هنا.
class _NoLocalNotifications extends FlutterLocalNotificationsPlatform {}

/// أعلى صفحة الأجهزة بعد ١ نوفمبر (المالك: «٤ حقول فلاتر واضافات وتوزيع اجهزه ومناطق ماخذات هواي من الصفحه»):
/// سطر البحث وأدواته كما هو و«+» قائمة الإضافات كلّها، ثمّ شريطٌ رفيعٌ واحد — «فلاتر» (ورقة الحالة والنوع والمناطق بعدد
/// الفعّال) والتوزيع شرائحَ تُرشِّح بنقرة — بدل بلاطات الإجمالي/المتّصل/المفصول وصفّي الأنواع والمناطق.
///
/// بياناتٌ تجريبيّة ([DevicesDemoData]): ١٤ جهازاً بأربع مناطق. والفحص الحيّ مطفأ (`isActive: false`) — في الاختبار يجعل
/// كلّ جهازٍ «مفصولاً»، فتبقى الحالات كما ردّها الخادم.
void main() {
  setUpAll(() async {
    await simSetUpAll();
    FlutterLocalNotificationsPlatform.instance = _NoLocalNotifications();
  });

  /// موظّفٌ بـ«عرض الأجهزة» وحدها — بلا إدارة.
  const viewer = Scenario(
    id: 'T_dev_filters_viewer',
    title: 'موظّف — عرض الأجهزة',
    actor: Actor.elEmployee,
    provider: null,
    keys: {'devices.view': true},
  );

  final names = {
    for (final j in DevicesDemoData.devices()) j['id'] as int: NetworkDevice.fromJson(j).name,
  };
  Finder device(int id) => find.text(names[id]!);
  Finder key(String k) => find.byKey(ValueKey(k));
  final sheet = find.byType(DevicesFilterSheet);
  Finder inSheet(String text) => find.descendant(of: sheet, matching: find.text(text));
  Finder inStrip(String text) => find.descendant(of: key('devices-strip'), matching: find.text(text));

  /// الشريحة التي تحمل [label] في [scope] — لقراءة عددها وحالها.
  DeviceFilterChip chipIn(WidgetTester t, Finder scope, String label) => t.widget<DeviceFilterChip>(find
      .ancestor(of: find.descendant(of: scope, matching: find.text(label)), matching: find.byType(DeviceFilterChip))
      .first);

  Future<void> settle(WidgetTester t, {int ms = 1500}) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t, {Scenario s = s1bSasOwner, double width = 390, bool desk = false}) async {
    NetworkDevicesScreen.debugResetView();
    final inner = await visualSetUp(s);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff, routes: DevicesDemoData.routes());
    AiAssistantState.reset();
    final screen = NetworkDevicesScreen(isActive: ValueNotifier<bool>(false));
    await pumpSim(t, SimVariant(width, dark: false),
        settle: false, home: (_) => desk ? DesktopScope(child: Scaffold(body: screen)) : screen);
    await settle(t);
    expect(t.takeException(), isNull);
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
    await visualTearDown();
    AiAssistantState.reset();
    DeviceAlertsService.instance.unreadCount.value = 0;
    AppPlatform.debugIsDesktop = null;
  }

  Future<void> openSheet(WidgetTester t) async {
    await t.tap(key('devices-filters'));
    await settle(t, ms: 800);
    expect(sheet.hitTestable(), findsOneWidget);
  }

  testWidgets('سطران لا خمسة: البحث وأدواته ثمّ شريطٌ واحد — والقائمة تبدأ في الربع الأعلى', (t) async {
    await open(t);
    expect(key('devices-strip'), findsOneWidget);
    expect(t.getSize(key('devices-strip')).height, H.chipSm, reason: 'صفٌّ واحد لا يلتفّ');
    // الكتل القديمة ذهبت: بلاطة «الإجمالي»، وصفّ المناطق («كلّ المناطق» في الورقة وحدها).
    expect(find.text('الإجمالي'), findsNothing);
    expect(find.text('كلّ المناطق'), findsNothing);
    expect(find.text('برج الشهداء'), findsWidgets, reason: 'شارة المنطقة على الكروت باقية');
    // التوزيع بأعداده في الشريط
    expect(chipIn(t, key('devices-strip'), 'الكلّ').count, 14);
    expect(chipIn(t, key('devices-strip'), 'الكلّ').selected, isTrue);
    expect(chipIn(t, key('devices-strip'), 'متّصل').count, 11);
    expect(chipIn(t, key('devices-strip'), 'مفصول').count, 2);
    expect(chipIn(t, key('devices-strip'), 'سكاتر').count, 5);
    expect(chipIn(t, key('devices-strip'), 'فلاتر').badge, 0);
    // أوّل جهاز (الترتيب بالعنوان) قريبٌ من الأعلى: كان تحت ~٣٠٥ نقطة من أربع كتل.
    expect(t.getTopLeft(device(9)).dy, lessThan(230));
    await finish(t);
  });

  testWidgets('شرائح الشريط: نقرةٌ تُرشِّح والثانية تُلغي، والنوع يُسحب إلى النظر', (t) async {
    await open(t);
    await t.tap(key('devices-status-offline'));
    await settle(t, ms: 500);
    expect(device(3), findsOneWidget);
    expect(device(13), findsOneWidget);
    expect(device(9), findsNothing, reason: 'المتّصل خارج المرشّح');
    expect(chipIn(t, key('devices-strip'), 'فلاتر').badge, 1);
    expect(chipIn(t, key('devices-strip'), 'الكلّ').selected, isFalse);
    // الأنواع ضمن «مفصول»: سكترٌ وأولت وحدهما
    expect(inStrip('سكاتر'), findsOneWidget);
    expect(inStrip('لنكات'), findsNothing, reason: 'لا لنك مفصول — الشريط لا يملؤه صفر');
    await t.tap(key('devices-status-offline'));
    await settle(t, ms: 500);
    expect(device(9), findsOneWidget);
    expect(chipIn(t, key('devices-strip'), 'فلاتر').badge, 0);
    // نوعٌ من آخر الشريط
    await t.ensureVisible(inStrip('راوترات'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(inStrip('راوترات'));
    await settle(t, ms: 500);
    expect(device(9), findsOneWidget);
    expect(device(14), findsOneWidget);
    expect(device(1), findsNothing);
    expect(chipIn(t, key('devices-strip'), 'راوترات').selected, isTrue);
    await finish(t);
  });

  testWidgets('ورقة «فلاتر»: المنطقة والحالة معاً، فوراً، بأعدادٍ ضمن المرشّحات الأخرى — وشريحة المنطقة تُزال', (t) async {
    await open(t);
    await openSheet(t);
    for (final s in ['الحالة', 'النوع', 'المنطقة', 'كلّ المناطق', 'بلا منطقة']) {
      expect(inSheet(s), findsOneWidget, reason: s);
    }
    expect(inSheet('إدارة المناطق'), findsOneWidget, reason: 'المالك يدير المناطق من هنا أيضاً');
    expect(inSheet('عرض 14 جهازاً'), findsOneWidget);
    await t.tap(inSheet('الكورنيش'));
    await settle(t, ms: 400);
    expect(inSheet('عرض 3 أجهزة'), findsOneWidget);
    expect(inSheet('يعرض 3 من 14'), findsOneWidget);
    expect(chipIn(t, sheet, 'مفصول').count, 1, reason: 'المفصول في الكورنيش وحدها');
    expect(chipIn(t, sheet, 'برج الشهداء').count, 4, reason: 'عدّاد المناطق لا يتقيّد بالمنطقة المختارة');
    // تُطبَّق فوراً — القائمة خلف الورقة تغيّرت قبل إغلاقها.
    expect(device(9), findsNothing);
    await t.tap(inSheet('متّصل'));
    await settle(t, ms: 400);
    expect(inSheet('عرض جهازين'), findsOneWidget);
    await t.tap(inSheet('عرض جهازين'));
    await settle(t, ms: 800);
    expect(sheet, findsNothing);
    expect(device(5), findsOneWidget);
    expect(device(10), findsOneWidget);
    expect(device(13), findsNothing, reason: 'أولت الكورنيش مفصول');
    // الشريط: «فلاتر» بعددها، والمنطقة شريحةٌ بـ✕ في أوّله
    expect(chipIn(t, key('devices-strip'), 'فلاتر').badge, 2);
    expect(key('devices-region-chip'), findsOneWidget);
    expect(find.descendant(of: key('devices-region-chip'), matching: find.text('الكورنيش')), findsOneWidget);
    expect(chipIn(t, key('devices-strip'), 'مفصول').count, 1, reason: 'التوزيع داخل المنطقة');
    await t.tap(key('devices-region-chip'));
    await settle(t, ms: 500);
    expect(key('devices-region-chip'), findsNothing);
    expect(chipIn(t, key('devices-strip'), 'فلاتر').badge, 1);
    expect(device(9), findsOneWidget, reason: 'المتّصل في كلّ المناطق');
    // «الكلّ» يمسح ما بقي
    await t.tap(key('devices-clear-filters'));
    await settle(t, ms: 500);
    expect(chipIn(t, key('devices-strip'), 'فلاتر').badge, 0);
    expect(chipIn(t, key('devices-strip'), 'الكلّ').selected, isTrue);
    await finish(t);
  });

  testWidgets('«إعادة تعيين» في الورقة يمسح الثلاثة، و«بلا منطقة» مرشّحٌ كأيّ منطقة', (t) async {
    await open(t);
    await openSheet(t);
    await t.tap(inSheet('بلا منطقة'));
    await settle(t, ms: 400);
    expect(inSheet('عرض جهاز واحد'), findsOneWidget);
    await t.tap(inSheet('راوترات'));
    await t.tap(inSheet('مفصول'));
    await settle(t, ms: 400);
    expect(inSheet('لا نتائج — غيّر الفلاتر'), findsOneWidget, reason: 'راوتر الطوارئ لم يُفحص — ليس مفصولاً');
    await t.tap(inSheet('إعادة تعيين'));
    await settle(t, ms: 400);
    expect(inSheet('عرض 14 جهازاً'), findsOneWidget);
    expect(chipIn(t, sheet, 'كلّ المناطق').selected, isTrue);
    await t.tap(find.byIcon(Icons.close_rounded));
    await settle(t, ms: 800);
    expect(sheet, findsNothing);
    expect(chipIn(t, key('devices-strip'), 'فلاتر').badge, 0);
    await finish(t);
  });

  testWidgets('نوعٌ من الورقة شريحته خارج المرئيّ من الشريط ⇒ تُسحب إلى النظر', (t) async {
    await open(t);
    expect(inStrip('أخرى').hitTestable(), findsNothing, reason: 'آخر الشريط على ٣٩٠ خارج الشاشة');
    await openSheet(t);
    await t.tap(inSheet('أخرى'));
    await settle(t, ms: 400);
    await t.tap(inSheet('عرض جهازين'));
    await settle(t, ms: 1200);
    expect(inStrip('أخرى').hitTestable(), findsOneWidget);
    expect(chipIn(t, key('devices-strip'), 'أخرى').selected, isTrue);
    expect(device(8), findsOneWidget);
    expect(device(13), findsOneWidget);
    await finish(t);
  });

  testWidgets('«+» قائمة الإضافات: جهاز، اكتشاف أجهزة الشبكة، المناطق — و«إضافة جهاز» تفتح النموذج', (t) async {
    await open(t);
    await t.tap(find.byIcon(LucideIcons.plus));
    await settle(t, ms: 600);
    for (final s in ['إضافة جهاز', 'اكتشاف أجهزة الشبكة', 'إدارة المناطق']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    await t.tap(find.text('إضافة جهاز'));
    await settle(t, ms: 800);
    expect(find.byType(NetworkDeviceFormSheet), findsOneWidget);
    await finish(t);
  });

  testWidgets('«إدارة المناطق» من الورقة تُغلقها وتفتح شاشة المناطق', (t) async {
    await open(t);
    await openSheet(t);
    await t.tap(inSheet('إدارة المناطق'));
    await settle(t, ms: 1200);
    expect(sheet, findsNothing);
    expect(find.byType(RegionsScreen), findsOneWidget);
    await finish(t);
  });

  testWidgets('موظّفٌ بالعرض وحده: الشريط والورقة كما هما، بلا «+» ولا «إدارة المناطق»', (t) async {
    await open(t, s: viewer);
    expect(find.byIcon(LucideIcons.plus), findsNothing);
    expect(key('devices-strip'), findsOneWidget);
    await openSheet(t);
    expect(inSheet('المنطقة'), findsOneWidget);
    expect(inSheet('إدارة المناطق'), findsNothing);
    await finish(t);
  });

  testWidgets('وضع التحديد: الشريط نفسه، والمرشّح يبقى — «تحديد الكلّ» يأخذ المعروض', (t) async {
    await open(t);
    await t.tap(key('devices-status-offline'));
    await settle(t, ms: 500);
    await t.longPress(device(13));
    await settle(t, ms: 500);
    expect(find.text('1 مُحدَّد'), findsOneWidget);
    expect(key('devices-strip'), findsOneWidget);
    expect(chipIn(t, key('devices-strip'), 'مفصول').selected, isTrue);
    await t.tap(find.byTooltip('تحديد الكل'));
    await settle(t, ms: 500);
    expect(find.text('2 مُحدَّد'), findsOneWidget);
    await finish(t);
  });

  testWidgets('٣٢٠ وخطّ ١٫٢: الشريط والورقة بلا فيضان', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await open(t, width: 320);
    await openSheet(t);
    expect(t.takeException(), isNull);
    await t.tap(inSheet('الحيدريّة'));
    await settle(t, ms: 400);
    expect(t.takeException(), isNull);
    await finish(t);
  });

  testWidgets('الحاسبة: السطران نفسهما، والورقة نافذةٌ في الوسط، و«+» قائمة', (t) async {
    AppPlatform.debugIsDesktop = true;
    await open(t, width: 1260, desk: true);
    expect(key('devices-strip'), findsOneWidget);
    // على عرض الحاسبة يتّسع الشريط كلّه — آخر نوعٍ ظاهرٌ بلا تمرير.
    expect(inStrip('أخرى').hitTestable(), findsOneWidget);
    await t.tap(key('devices-filters'));
    await settle(t, ms: 800);
    expect(find.byType(DeskSheetDialog), findsOneWidget);
    expect(sheet, findsOneWidget);
    await t.tap(inSheet('المركز'));
    await settle(t, ms: 400);
    expect(inSheet('عرض 3 أجهزة'), findsOneWidget);
    await t.tap(inSheet('عرض 3 أجهزة'));
    await settle(t, ms: 800);
    expect(find.byType(DeskSheetDialog), findsNothing);
    expect(chipIn(t, key('devices-strip'), 'فلاتر').badge, 1);
    await t.tap(find.byIcon(LucideIcons.plus));
    await settle(t, ms: 600);
    expect(find.text('اكتشاف أجهزة الشبكة'), findsOneWidget);
    await finish(t);
  });
}
