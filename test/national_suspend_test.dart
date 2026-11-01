import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_limits.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';
import 'visual_perm/visual_perm_harness.dart' as vp;

/// «تعليق المشترك» / «تشغيل» للمشروع الوطنيّ (١ نوفمبر — الخادم: setEnabled على providerKit ومفتاح watani_toggle): الكلمات
/// كبوّابته («تعليق/تشغيل»، الحال «موقوف»)، لا «فصل» (البوّابة لا تسمح به للمقاول) ولا تعليق جماعيّ (ميزانيّة البوّابة)، ورسالة
/// الخادم نفسها عند الرفض، و«كما هو» يُقال كما هو، وتنبيه «موقوف» قبل الدفع في شيت التفعيل.
const _idx = '13293073';

Map<String, Object?> _row({bool online = true, bool enabled = true}) => {
      'idx': _idx,
      'username': 'FBG885F15P1',
      'firstname': 'مريم',
      'lastname': 'عبد الله',
      'phone': '07701000001',
      'profile_name': 'BASIC',
      'profile_id': 11,
      'expiration': '2026-11-20 10:00:00',
      'remaining_days': 19,
      'online_status': online ? 1 : 0,
      'enabled': enabled ? 1 : 0,
      'notes': '0',
    };

/// قدرات صاحب حساب الوطنيّ والتعليق مفتوح (canonicalPermissions: toggle بلا disconnect).
const _ownerCaps = <String, bool>{
  'subscribers.view': true,
  'subscribers.activate': true,
  'subscribers.toggle': true,
  'subscribers.disconnect': false,
  'subscribers.edit': false,
  'subscribers.delete': false,
  'subscribers.extend': false,
  'subscribers.pay_debt': true,
  'subscribers.add_debt': true,
};

void main() {
  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  test('الوطنيّ وحده يقول «تعليق/تشغيل»', () {
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    expect(ProviderService.togglesAsSuspend, isTrue);
    for (final p in ['nabd', 'accessgate', 'fiberx', 'earthlink', null]) {
      ProviderService.debugSet(p);
      expect(ProviderService.togglesAsSuspend, isFalse, reason: '$p');
    }
  });

  test('«فصل» والتعليق الجماعيّ: مخفيّان للوطنيّ، و«فصل» الشركة المُضافة بقدرتها، وموظّفها كما كان', () {
    ProviderService.debugSet('watani');
    PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _ownerCaps);
    expect(subscriberDisconnectHidden(), isTrue);
    expect(bulkToggleHidden(), isTrue);
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.toggle': true});
    expect(subscriberDisconnectHidden(), isTrue, reason: 'وموظّف الوطنيّ أيضاً');

    ProviderService.debugSet('nabd', label: 'نبض');
    PermissionsService.debugSet(
        isEmployee: false, managerRestricted: true, managerCaps: const {'subscribers.toggle': true, 'subscribers.disconnect': true});
    expect(subscriberDisconnectHidden(), isFalse);
    expect(bulkToggleHidden(), isFalse);
    PermissionsService.debugSet(
        isEmployee: false, managerRestricted: true, managerCaps: const {'subscribers.toggle': true, 'subscribers.disconnect': false});
    expect(subscriberDisconnectHidden(), isTrue, reason: 'قدرة الشركة false لصاحبها');
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.toggle': true});
    expect(subscriberDisconnectHidden(), isFalse, reason: 'موظّف الشركة المُضافة: كما كان');

    ProviderService.debugSet(null);
    PermissionsService.debugSet(isEmployee: false);
    expect(subscriberDisconnectHidden(), isFalse, reason: 'ساس كما كان');
  });

  test('toggleResultOf: رسالة الرفض (409) و«كما هو» من الخادم', () {
    final rejected = SubscribersApi.toggleResultOf({
      'success': false,
      'code': 'PROVIDER_REJECTED',
      'message': 'الاشتراك منتهٍ — البوّابة لا تعلّق المنتهي (لم يتغيّر شيء)',
    });
    expect(rejected.ok, isFalse);
    expect(rejected.message, contains('لا تعلّق المنتهي'));
    final same = SubscribersApi.toggleResultOf({
      'success': true,
      'data': {'idx': _idx, 'enabled': false, 'unchanged': true},
    });
    expect((same.ok, same.unchanged, same.message), (true, true, null));
    final ok = SubscribersApi.toggleResultOf({'success': true, 'data': {'idx': _idx, 'enabled': false}});
    expect((ok.ok, ok.unchanged), (true, false));
    final none = SubscribersApi.toggleResultOf(null);
    expect((none.ok, none.message), (false, null));
  });

  test('الحال «موقوف» للوطنيّ في البطاقة والأيّام، و«معطّل» لغيره', () {
    final s = Subscriber.fromJson(Map<String, dynamic>.from(_row(enabled: false)));
    ProviderService.debugSet('watani');
    expect(SubscriberCardV3.statusOf(s).label, 'موقوف');
    expect(SubscriberCardV3.daysOf(s).small, 'موقوف');
    ProviderService.debugSet('nabd');
    expect(SubscriberCardV3.statusOf(s).label, 'معطّل');
  });

  group('صفحة المشترك', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
      SubscribersApi.clearAllCaches();
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
    });

    const v = SimVariant(430, dark: false);

    Future<void> openDetail(WidgetTester t, {bool online = true, bool enabled = true}) async {
      final sub = Subscriber.fromJson(Map<String, dynamic>.from(_row(online: online, enabled: enabled)));
      await pumpSim(t, v, home: (_) => SubscriberDetailScreen(sub: sub), settle: false);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      // التحديث بعد الكتابة (SubscriberEvents ⇒ جلب القائمة بمهلة ٢٠ث) يكمل قبل نهاية الاختبار
      await t.pump(const Duration(seconds: 25));
    }

    testWidgets('متّصلٌ يعمل: «تعليق» بلا «فصل»؛ والتعليق يرسل enabled:false ويقول «تم تعليق المشترك»', (t) async {
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _ownerCaps);
      server.reply('POST', '/api/v2/subscribers/$_idx/toggle-enabled', 200, {
        'success': true,
        'data': {'idx': _idx, 'enabled': false},
      });
      await openDetail(t);
      expect(find.text('تعليق'), findsOneWidget);
      expect(find.byIcon(LucideIcons.pause), findsOneWidget);
      expect(find.text('فصل'), findsNothing, reason: 'لا فصل للمقاول في البوّابة');
      expect(find.text('تعطيل'), findsNothing);
      await t.tap(find.text('تعليق'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('تعليق المشترك'), findsOneWidget);
      expect(find.textContaining('حتى تضغط «تشغيل»'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'تعليق'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(server.bodies('POST', '/api/v2/subscribers/$_idx/toggle-enabled').single, {'enabled': false});
      expect(find.text('تم تعليق المشترك'), findsOneWidget);
      await close(t);
    });

    testWidgets('موقوف: «تشغيل» والحال «موقوف»؛ رفض الخادم ⇒ رسالته نفسها لا «تعذّر»', (t) async {
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _ownerCaps);
      server.reply('POST', '/api/v2/subscribers/$_idx/toggle-enabled', 409, {
        'success': false,
        'code': 'PROVIDER_REJECTED',
        'message': 'الاشتراك منتهٍ — جدّده («تفعيل») ثمّ شغّله (لم يتغيّر شيء)',
      });
      await openDetail(t, online: false, enabled: false);
      expect(find.text('تشغيل'), findsOneWidget);
      expect(find.text('موقوف'), findsWidgets);
      expect(find.text('معطّل'), findsNothing);
      await t.tap(find.text('تشغيل'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('تشغيل المشترك'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'تشغيل'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(server.bodies('POST', '/api/v2/subscribers/$_idx/toggle-enabled').single, {'enabled': true});
      expect(find.textContaining('جدّده («تفعيل») ثمّ شغّله'), findsOneWidget);
      expect(find.text('تعذّر التشغيل'), findsNothing);
      await close(t);
    });

    testWidgets('«كما هو»: المشترك موقوفٌ أصلاً', (t) async {
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _ownerCaps);
      server.reply('POST', '/api/v2/subscribers/$_idx/toggle-enabled', 200, {
        'success': true,
        'data': {'idx': _idx, 'enabled': false, 'unchanged': true},
      });
      await openDetail(t, online: false);
      await t.tap(find.text('تعليق'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(find.widgetWithText(FilledButton, 'تعليق'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('المشترك موقوف أصلاً'), findsOneWidget);
      await close(t);
    });

    testWidgets('موظّفٌ بلا subscribers.toggle: «تعليق» بمكانه مقفلاً، و«فصل» غائب', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true, 'subscribers.toggle': false});
      await openDetail(t);
      final tile = find.text('تعليق');
      expect(tile, findsOneWidget);
      expect(find.byType(PermLockBadge), findsWidgets);
      expect(find.text('فصل'), findsNothing);
      await t.tap(tile);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text('تعليق المشترك'), findsNothing, reason: 'المقفل لا يفتح التأكيد');
      expect(server.calls('POST', '/api/v2/subscribers/$_idx/toggle-enabled'), isEmpty);
      await close(t);
    });

    testWidgets('شيت التفعيل: تنبيه «موقوف» من الخادم قبل الدفع', (t) async {
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _ownerCaps);
      server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, {
        'success': true,
        'data': {
          'idx': _idx, 'username': 'FBG885F15P1', 'profile_name': 'BASIC', 'profile_id': 11, 'user_price': 40000,
          'price_after_discount': 40000, 'base_price': 40000, 'current_balance': 0, 'manager_balance': 478063,
          'provider': 'watani', 'provider_label': 'المشروع الوطني',
          'packages': [{'id': 11, 'name': 'BASIC', 'price': 40000, 'cost': 35000, 'days': 30}],
          'package_change_allowed': false, 'package_change_timing': ['now'],
          'provider_notice': 'المشترك موقوف في البوّابة — التفعيل يمدّد اشتراكه لكنّه يبقى موقوفاً حتى تضغط «تشغيل»',
        },
      });
      final sub = Subscriber.fromJson(Map<String, dynamic>.from(_row(enabled: false)));
      await pumpSim(t, v, home: (_) => simLauncher((c) => showActivateSheet(c, sub)));
      await simOpen(t);
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      expect(find.textContaining('يبقى موقوفاً حتى تضغط «تشغيل»'), findsOneWidget);
      await simDrain(t);
    });
  });

  group('شريط التحديد', () {
    void tolerateRowNoise() {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflowed')) return;
        prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
    }

    testWidgets('الوطنيّ: لا «تعطيل/تشغيل» جماعيّ ولا «فصل المتصلين»؛ والساس كما كان', (t) async {
      tolerateRowNoise();
      await vp.visualSetUp(vp.s1bSasOwner);
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _ownerCaps);
      await vp.pumpVisual(t, vp.phone, home: (_) => const SubscribersScreen());
      await vp.settle(t, seconds: 2);
      final row = find.byType(SubscriberCardV3).first;
      await t.longPress(row);
      await vp.settle(t, seconds: 1);
      expect(find.textContaining('تعطيل'), findsNothing);
      expect(find.textContaining('subscribers.disable'), findsNothing);
      expect(find.textContaining('فصل المتصلين'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await vp.visualTearDown();
    });

    testWidgets('مرجع: مالك ساس يرى «تعطيل» الجماعيّ', (t) async {
      tolerateRowNoise();
      await vp.visualSetUp(vp.s1bSasOwner);
      await vp.pumpVisual(t, vp.phone, home: (_) => const SubscribersScreen());
      await vp.settle(t, seconds: 2);
      await t.longPress(find.byType(SubscriberCardV3).first);
      await vp.settle(t, seconds: 1);
      expect(find.textContaining('تعطيل'), findsWidgets);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await vp.visualTearDown();
    });
  });
}
