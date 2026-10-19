import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/balance_card.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_actions.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// بلاغ ٢٠٢٦-١٠-١٤: إجراء المشترك بلا مفتاح **يبقى بمكانه مقفلاً** —
/// بلاطةٌ بشارة قفل، صفٌّ بقفلٍ مكان السهم، زرٌّ بلا تعبئة — ونقرته رسالة
/// القفل وحدها: لا نداء، لا شيت، لا طلب شبكة. والمالك لا يرى قفلاً.
///
/// العدّ بالنوع (`PermLockBadge`/`PermLockIcon`) لا بالنصّ.
Map<String, Object?> _row(int idx) => {
      'idx': '$idx',
      'username': 'user$idx',
      'firstname': 'علي',
      'lastname': 'حسن',
      'phone': '07701000001',
      'profile_name': 'Economy',
      'profile_id': 7,
      'expiration': '2026-10-15 10:00:00',
      'remaining_days': 1,
      'online_status': 1,
      'enabled': 1,
      'notes': '-35000',
    };

void main() {
  group('الودجات', () {
    Future<void> pump(WidgetTester t, Widget child) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(body: ListView(children: [child])),
      ));
    }

    testWidgets('بلاطة مقفلة: شارة قفل، والنقر لا يستدعي النداء',
        (t) async {
      var called = 0;
      await pump(
        t,
        SubscriberActionTiles(actions: [
          SubAction(icon: Icons.add, label: 'تمديد', onTap: () => called++),
          SubAction(
              icon: Icons.edit,
              label: 'تعديل',
              locked: true,
              onTap: () => called++),
        ]),
      );
      expect(find.byType(PermLockBadge), findsOneWidget);
      await t.tap(find.text('تعديل'));
      await t.pump(const Duration(seconds: 3));
      expect(called, 0);
      await t.tap(find.text('تمديد'));
      expect(called, 1);
    });

    testWidgets('القفل يغلب onTap == null: المقفل يردّ برسالة لا بصمت',
        (t) async {
      await pump(
        t,
        const SubscriberActionTiles(actions: [
          SubAction(icon: Icons.edit, label: 'تعديل', locked: true, onTap: null),
        ]),
      );
      await t.tap(find.text('تعديل'));
      await t.pump();
      expect(find.text('locked.toast_action'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('زرّ التجديد المقفل: قفلٌ مكان الأيقونة ولا نداء', (t) async {
      var called = 0;
      await pump(
        t,
        SubscriberPrimaryAction(
          icon: Icons.refresh,
          label: 'تجديد',
          locked: true,
          onTap: () => called++,
        ),
      );
      expect(find.byIcon(Icons.refresh), findsNothing);
      await t.tap(find.text('تجديد'));
      await t.pump(const Duration(seconds: 3));
      expect(called, 0);
    });

    testWidgets('بطاقة الرصيد: الزرّ المقفل يبقى بمكانه ولا يفتح شيئاً',
        (t) async {
      final sub = Subscriber(
        username: 'u1',
        firstname: 'علي',
        lastname: 'حسن',
        mobile: '9647700000000',
        hasDebtFlag: true,
        debt: 5000,
      );
      await pump(t, BalanceCard(sub: sub, addDebtLocked: true, payLocked: true));
      expect(find.text('إضافة دين'), findsOneWidget);
      expect(find.text('تسديد'), findsOneWidget);
      // لا نداء مُمرَّر أصلاً — النقر رسالةٌ فقط ولا يرمي.
      await t.tap(find.text('تسديد'));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('locked.toast_action'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('المالك (بلا قفل): البطاقة كما كانت', (t) async {
      final sub = Subscriber(
        username: 'u1',
        firstname: 'علي',
        lastname: 'حسن',
        mobile: '9647700000000',
        hasDebtFlag: true,
        debt: 5000,
      );
      await pump(t, BalanceCard(sub: sub, onPay: () {}, onAddDebt: () {}));
      expect(find.byType(PermLockIcon), findsNothing);
      expect(find.byType(PermLockBadge), findsNothing);
    });
  });

  group('شاشة المشترك', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp();
      SubscribersApi.clearAllCaches();
    });
    tearDown(() {
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });

    const v = SimVariant(430, dark: false);

    Future<void> openDetail(WidgetTester t) async {
      final sub = Subscriber.fromJson(Map<String, dynamic>.from(_row(1)));
      await pumpSim(t, v,
          home: (_) => SubscriberDetailScreen(sub: sub), settle: false);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    }

    Future<void> openMore(WidgetTester t) async {
      await t.tap(find.text('المزيد'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
    }

    for (final el in [false, true]) {
      testWidgets(
          'موظّف ${el ? 'ايرث لنك' : 'ساس'} بـsubscribers.view وحدها: '
          'البلاطات والشيت مقفلة بمكانها، والنقر بلا طلب', (t) async {
        ProviderService.debugSet(el ? 'earthlink' : null);
        PermissionsService.debugSet(
            isEmployee: true, permissions: const {'subscribers.view': true});
        await openDetail(t);
        // تمديد · تعديل · تعطيل · فصل (متّصل) — شارة قفلٍ لكلٍّ منها.
        expect(find.byType(PermLockBadge), findsNWidgets(4));

        final before = server.requests.length;
        await t.tap(find.byType(PermLockBadge).first);
        await t.pump(const Duration(seconds: 3));
        expect(find.byType(AlertDialog), findsNothing);
        expect(server.requests.length, before,
            reason: 'البلاطة المقفلة لا تطلب شيئاً');

        await openMore(t);
        expect(find.text('إجراءات أخرى'), findsOneWidget);
        final sheetLocks = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(PermLockIcon),
        );
        expect(sheetLocks, findsWidgets);
        // النقر على صفٍّ مقفل لا يغلق الشيت ولا يطلب.
        final mid = server.requests.length;
        await t.tap(sheetLocks.first, warnIfMissed: false);
        await t.pump(const Duration(seconds: 3));
        expect(find.text('إجراءات أخرى'), findsOneWidget);
        expect(server.requests.length, mid);
        // الحذف (آخر الشيت): عند موظّف الساس صفٌّ مقفلٌ بمكانه بالصلاحيّة؛
        // وعند ايرث لنك **لا يظهر أصلاً** (قرار المالك ١٩ أكتوبر: ايرث لنك لا
        // تسمح بحذف المشترك ⇒ مخفيٌّ لا مقفل). نمرّر إلى نهاية الشيت أوّلاً،
        // فالقائمة كسولةٌ لا تبني ما تحت الطيّ.
        await t.drag(
            find.descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Scrollable)).first,
            const Offset(0, -2000));
        await t.pump(const Duration(milliseconds: 500));
        final del = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.text('common.delete'.tr()));
        final atDelete = server.requests.length;
        if (el) {
          expect(del, findsNothing, reason: 'ايرث لنك: لا «حذف» أصلاً');
          expect(find.text('subscribers.group_danger'.tr()), findsNothing,
              reason: 'مجموعةٌ فارغة لا تُعرض');
        } else {
          expect(del, findsOneWidget);
          await t.tap(del, warnIfMissed: false);
          await t.pump();
          expect(find.text('locked.toast_action'.tr()), findsWidgets);
        }
        expect(server.requests.length, atDelete, reason: 'لا حذف يُطلب');
        await t.pump(const Duration(seconds: 3));
        await close(t);
      });
    }

    testWidgets('المالك: لا قفل في الشاشة ولا في الشيت', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await openDetail(t);
      expect(find.byType(PermLockBadge), findsNothing);
      expect(find.byType(PermLockIcon), findsNothing);
      await openMore(t);
      expect(find.byType(PermLockIcon), findsNothing);
      await close(t);
    });
  });
}
