import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/screens/network_devices/device_alerts_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/network_devices_screen.dart';
import 'package:rad_mysvcs/screens/network_devices/widgets/device_big_card.dart';
import 'package:rad_mysvcs/screens/top_actions.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/device_alerts_service.dart';

import 'sim_el/sim_harness.dart';
import 'support/ai_status_overlay.dart';
import 'visual_perm/visual_perm_harness.dart';

/// شاشة الأجهزة تطلب صلاحيّة الإشعارات المحلّيّة عند فتحها — لا منصّة هنا.
class _NoLocalNotifications extends FlutterLocalNotificationsPlatform {}

/// تبويب «الأجهزة» بعد ٢٠ أكتوبر: لا AppBar — رأس التبويب الموحّد (العنوان +
/// أزرار الأعلى)، وأدوات القائمة التي كان الشريط يحملها (تنبيهات الأجهزة ·
/// التحديث · المزيد · الإضافة) جنب البحث في سطرٍ مثبَّت. لم تتغيّر وظيفة أيٍّ
/// منها — هذه الاختبارات تحرس أنّها كلّها باقية وتعمل، وأنّ «تحديث» يبقى طريق
/// إعادة المحاولة بعد فشل التحميل.
void main() {
  setUpAll(() async {
    await simSetUpAll();
    FlutterLocalNotificationsPlatform.instance = _NoLocalNotifications();
  });

  late AiStatusOverlay server;
  const devicesPath = '/api/v2/admin/devices';

  /// موظّف ساس بـ«عرض الأجهزة» وحدها — بلا إدارة.
  const viewer = Scenario(
    id: 'T_dev_viewer',
    title: 'موظّف ساس — عرض الأجهزة',
    actor: Actor.elEmployee,
    provider: null,
    keys: {'devices.view': true},
  );

  final siren = find.byIcon(LucideIcons.siren);
  final view = find.byIcon(LucideIcons.list);
  final refresh = find.byIcon(LucideIcons.refreshCw);
  final more = find.byIcon(LucideIcons.ellipsisVertical);
  final add = find.byIcon(LucideIcons.plus);

  Future<void> settle(WidgetTester t, {int seconds = 2}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester t, Scenario s, {Set<String>? failing}) async {
    NetworkDevicesScreen.debugResetView();
    final inner = await visualSetUp(s);
    server = AiStatusOverlay(inner, status: aiStatusOff, failing: failing);
    ApiClient.dio.httpClientAdapter = server;
    AiAssistantState.reset();
    await pumpSim(t, const SimVariant(390, dark: false),
        settle: false,
        home: (_) =>
            NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
    await settle(t);
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
    await visualTearDown();
    AiAssistantState.reset();
    DeviceAlertsService.instance.unreadCount.value = 0;
  }

  testWidgets('المالك: العنوان الموحّد، والبحث وأدواته الأربع بترتيبها',
      (t) async {
    await open(t, s1bSasOwner);
    expect(t.takeException(), isNull);
    expect(find.byType(AppBar), findsNothing, reason: 'لا شريط علويّ بعد الآن');
    expect(find.byType(TabHeader), findsOneWidget);
    expect(find.text('الأجهزة'), findsOneWidget);
    expect(find.byType(TopActions), findsOneWidget);
    for (final f in [siren, view, refresh, more, add]) {
      expect(f, findsOneWidget);
    }
    // من اليمين: البحث ← التنبيهات ← نوع العرض ← التحديث ← المزيد ← الإضافة.
    final search = t.getRect(find.byType(TextField));
    final xs = [siren, view, refresh, more, add].map((f) => t.getCenter(f).dx);
    expect(search.left, greaterThan(xs.first));
    final list = xs.toList();
    for (var i = 1; i < list.length; i++) {
      expect(list[i], lessThan(list[i - 1]));
    }
    // و«+» تحت الترس تماماً (عمودٌ واحد).
    final gear = find.byKey(const ValueKey('top-actions-settings'));
    expect(t.getCenter(add).dx, moreOrLessEquals(t.getCenter(gear).dx));
    await finish(t);
  });

  testWidgets('موظّفٌ بـ«عرض الأجهزة» وحدها: بلا «+» ولا إدارة المناطق',
      (t) async {
    await open(t, viewer);
    expect(add, findsNothing);
    expect(siren, findsOneWidget);
    expect(refresh, findsOneWidget);
    await t.tap(more);
    await t.pumpAndSettle();
    expect(find.text('نظرة عامّة'), findsNothing, reason: 'أُلغيت (٣١ أكتوبر) — مكانها نوع العرض');
    expect(find.text('إدارة المناطق'), findsNothing);
    expect(find.text('اكتشاف أجهزة الشبكة'), findsNothing);
    await t.tapAt(const Offset(10, 700)); // يُغلق القائمة
    await t.pumpAndSettle();
    await finish(t);
  });

  testWidgets('«المزيد» للمالك: القائمة كما كانت — بلا «نظرة عامّة»', (t) async {
    await open(t, s1bSasOwner);
    await t.tap(more);
    await t.pumpAndSettle();
    expect(find.text('نظرة عامّة'), findsNothing, reason: 'أُلغيت (٣١ أكتوبر) — مكانها نوع العرض');
    expect(find.textContaining('الترتيب · '), findsOneWidget);
    expect(find.text('إدارة المناطق'), findsOneWidget);
    expect(find.text('اكتشاف أجهزة الشبكة'), findsOneWidget);
    await t.tapAt(const Offset(10, 700));
    await t.pumpAndSettle();
    await finish(t);
  });

  testWidgets('نوع العرض: «قائمة» ⇄ «بطاقات كبيرة» (لا «جدول» على الهاتف) — والاختيار يبقى', (t) async {
    await open(t, s1bSasOwner);
    expect(find.byType(DeviceBigCard), findsNothing, reason: 'الافتراضيّ على الهاتف القائمة');
    await t.tap(view);
    await t.pumpAndSettle();
    expect(find.text('قائمة'), findsOneWidget);
    expect(find.text('بطاقات كبيرة'), findsOneWidget);
    expect(find.text('جدول'), findsNothing, reason: 'الجدول للحاسبة وحدها');
    await t.tap(find.text('بطاقات كبيرة'));
    await settle(t);
    expect(t.takeException(), isNull);
    // (هذا الحساب بلا أجهزة — البطاقات نفسها في device_big_card_test.)
    expect(find.byIcon(LucideIcons.galleryVerticalEnd), findsOneWidget, reason: 'أيقونة الزرّ تقول النوع المختار');
    expect(view, findsNothing);
    // يبقى بعد إعادة بناء الشاشة (الخروج من التبويب والعودة)
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
    await pumpSim(t, const SimVariant(390, dark: false),
        settle: false, home: (_) => NetworkDevicesScreen(isActive: ValueNotifier<bool>(true)));
    await settle(t);
    expect(find.byIcon(LucideIcons.galleryVerticalEnd), findsOneWidget, reason: 'الاختيار يبقى بين الزيارات');
    await t.tap(find.byIcon(LucideIcons.galleryVerticalEnd));
    await t.pumpAndSettle();
    await t.tap(find.text('قائمة'));
    await settle(t);
    expect(view, findsOneWidget);
    expect(find.byType(DeviceBigCard), findsNothing);
    await finish(t);
  });

  testWidgets('🚨 فشل التحميل ⇒ الأدوات ظاهرة و«تحديث» يعيد المحاولة',
      (t) async {
    await open(t, s1bSasOwner, failing: {'GET $devicesPath'});
    expect(find.text('لا توجد أجهزة'), findsNothing);
    expect(refresh, findsOneWidget, reason: 'طريق إعادة المحاولة الوحيد');
    expect(add, findsOneWidget);
    expect(find.byType(TopActions), findsOneWidget);
    final before = server.requests.where((r) => r.path == devicesPath).length;
    server.failing.clear();
    await t.tap(refresh);
    await settle(t);
    expect(server.requests.where((r) => r.path == devicesPath).length,
        greaterThan(before));
    expect(find.text('لا توجد أجهزة'), findsOneWidget, reason: 'زال الخطأ');
    await finish(t);
  });

  testWidgets('تنبيهات الأجهزة: عددها على الصفّارة، والنقر يفتح شاشتها',
      (t) async {
    DeviceAlertsService.instance.unreadCount.value = 2;
    await open(t, s1bSasOwner);
    // الشارة على ركن الصفّارة نفسها (لا عددٌ آخر في الشاشة الفارغة).
    expect(find.text('2'), findsOneWidget);
    expect((t.getCenter(find.text('2')) - t.getCenter(siren)).distance,
        lessThan(40));
    await t.tap(siren);
    await settle(t);
    expect(find.byType(DeviceAlertsScreen), findsOneWidget);
    await finish(t);
  });

  testWidgets('الضغط المطوّل على الصفّارة ⇒ إشعارٌ تجريبيّ كما كان', (t) async {
    await open(t, s1bSasOwner);
    await t.longPress(siren);
    await settle(t, seconds: 1);
    expect(find.textContaining('إشعار تجريبي'), findsOneWidget);
    await settle(t, seconds: 4);
    await finish(t);
  });

  // أقصى سلّم خطٍّ يسمح به التطبيق (١٫٢) على أضيق شاشة: لا فيضان في أيّ
  // تبويب بعد إضافة المساعد جنب الجرس ونزول الأدوات جنب البحث.
  testWidgets('٣٢٠ وخطّ ١٫٢: التبويبات الأربعة بلا فيضان', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final inner = await visualSetUp(s1bSasOwner);
    server = AiStatusOverlay(inner, status: aiStatusOn);
    ApiClient.dio.httpClientAdapter = server;
    AiAssistantState.reset();
    await pumpSim(t, const SimVariant(320, dark: false),
        settle: false, home: (_) => const MainShell());
    await settle(t, seconds: 3);
    expect(t.takeException(), isNull, reason: 'الرئيسيّة');
    for (final tab in ['nav.subscribers', 'nav.devices', 'nav.more']) {
      await t.tap(find.text(tab.tr()).last);
      await settle(t, seconds: 3);
      expect(t.takeException(), isNull, reason: tab);
      expect(find.byType(TopActions), findsOneWidget, reason: tab);
    }
    await finish(t);
  });
}
