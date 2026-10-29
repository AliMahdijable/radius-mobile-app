import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_limits.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// فايبر اكس (٢٩ أكتوبر): صفحة المشترك تعرض ما يخدمه وحده — كالموقع (`FIBERX_ACTIONS`). ما لا مسار له (تعديل، تعطيل، فصل،
/// إضافة رصيد، الجلسات، الحذف، إضافة موقع) **لا يظهر أصلاً**، لا مقفلاً بـ«لا صلاحيّة» يظنّه المالك صلاحيّةً تُطلب. و«تمديد»
/// فايبر اكس رسالة واتساب منهم (`extend-notice`) بتأكيد، وتكرارها خلال دقيقتين بتأكيدٍ صريح. وساسٌ بالقدرات نفسها كما كان.
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

/// قدرات وكيل فايبر اكس من الخادم (`fiberxRoutes.canonicalPermissions` والتفعيل مفتوح) — ما يمسّ هذه الشاشة.
const _fxCaps = <String, bool>{
  'subscribers.view': true,
  'fiberx.activate': true,
  'fiberx.extend': true,
  'subscribers.activate': true,
  'subscribers.pay_debt': true,
  'subscribers.add_debt': true,
  'subscribers.edit_location': false,
  'subscribers.edit': false,
  'subscribers.delete': false,
  'subscribers.toggle': false,
  'subscribers.disconnect': false,
  'subscribers.show_password': false,
  'subscribers.extend': false,
  'subscribers.add_credit': false,
  'subscribers.send_whatsapp': true,
  'discounts.manage': true,
  'subscriber_prices.manage': true,
  'reports.account_statement': true,
  'reports.sessions': false,
  'whatsapp.send': true,
};

const _ext = '/api/v2/fiberx/subscribers/1/extend-notice';

void main() {
  test('providerHidesAction: جلسة فايبر اكس وحدها', () {
    ProviderService.debugSet('fiberx');
    for (final k in ['subscribers.edit', 'subscribers.toggle', 'subscribers.delete', 'subscribers.extend',
      'subscribers.add_credit', 'subscribers.edit_location', 'reports.sessions', 'reports.manager_debts',
      'reports.daily_activations']) {
      expect(providerHidesAction(k), isTrue, reason: k);
    }
    for (final k in ['subscribers.activate', 'subscribers.pay_debt', 'subscribers.add_debt', 'fiberx.extend',
      'subscribers.send_whatsapp', 'discounts.manage', 'reports.account_statement']) {
      expect(providerHidesAction(k), isFalse, reason: k);
    }
    for (final p in [null, 'earthlink', 'ftth']) {
      ProviderService.debugSet(p);
      expect(providerHidesAction('subscribers.edit'), isFalse, reason: '$p');
    }
    ProviderService.debugSet(null);
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
      await pumpSim(t, v, home: (_) => SubscriberDetailScreen(sub: sub), settle: false);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
    }

    Future<void> close(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 3));
    }

    Future<void> openMoreToEnd(WidgetTester t) async {
      await t.tap(find.text('المزيد'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      await t.drag(
          find.descendant(of: find.byType(BottomSheet), matching: find.byType(Scrollable)).first,
          const Offset(0, -2000));
      await t.pump(const Duration(milliseconds: 500));
    }

    Finder inSheet(String text) =>
        find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

    testWidgets('فايبر اكس: لا تعديل/تعطيل/فصل ولا قفل، و«تمديد» بمفتاحه', (t) async {
      ProviderService.debugSet('fiberx');
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _fxCaps);
      await openDetail(t);
      expect(find.byType(PermLockBadge), findsNothing, reason: 'ما لا يخدمه المزوّد لا يُعرض مقفلاً');
      expect(find.text('subscribers.op_extend'.tr()), findsOneWidget);
      expect(find.text('subscribers.op_edit'.tr()), findsNothing);
      expect(find.text('subscribers.disable'.tr()), findsNothing);
      expect(find.text('subscribers.disconnect'.tr()), findsNothing);
      expect(find.text('subscribers.renew_subscription'.tr()), findsOneWidget, reason: 'التفعيل يبقى');
      await openMoreToEnd(t);
      expect(inSheet('إضافة رصيد'), findsNothing);
      expect(inSheet('subscribers.op_sessions'.tr()), findsNothing);
      expect(inSheet('subscribers.op_location_add'.tr()), findsNothing);
      expect(inSheet('common.delete'.tr()), findsNothing);
      expect(find.text('subscribers.group_danger'.tr()), findsNothing, reason: 'مجموعةٌ فارغة لا تُعرض');
      expect(inSheet('subscribers.account_statement'.tr()), findsOneWidget);
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(PermLockIcon)), findsNothing);
      await close(t);
    });

    testWidgets('فايبر اكس «تمديد»: تأكيدٌ ثمّ extend-notice، والتكرار بتأكيدٍ صريح', (t) async {
      ProviderService.debugSet('fiberx');
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _fxCaps);
      var n = 0;
      server.on('POST', _ext, (req) {
        n++;
        if (n == 1) {
          return const SimReply(409, {
            'success': false,
            'code': 'RECENT_DUPLICATE',
            'message': 'أُرسلت رسالة التمديد لهذا المشترك قبل قليل — أكّد إن أردت إرسالها ثانيةً',
          });
        }
        return const SimReply(200, {'success': true, 'status': 'delivered'});
      });
      await openDetail(t);
      await t.tap(find.text('subscribers.op_extend'.tr()));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(server.calls('POST', _ext), isEmpty, reason: 'لا إرسال قبل التأكيد');
      await t.tap(find.text('أرسل رسالة التمديد').hitTestable());
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      // الشيت الثاني يحتاج إطاراتٍ لينزلق (الأوّل يُغلق والطلب يعود قبله).
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('أرسلها ثانيةً').hitTestable(), findsOneWidget);
      await t.tap(find.text('أرسلها ثانيةً').hitTestable());
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      final bodies = server.bodies('POST', _ext);
      expect(bodies.length, 2);
      expect(bodies[0]['confirmRepeat'], isNull);
      expect(bodies[1]['confirmRepeat'], isTrue);
      expect(find.text('وصلت رسالة التمديد للمشترك على واتساب'), findsOneWidget);
      await t.pump(const Duration(seconds: 4));
      await close(t);
    });

    testWidgets('ساس بالقدرات نفسها: كما كان — مقفلةٌ بمكانها', (t) async {
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: _fxCaps);
      await openDetail(t);
      // تمديد · تعديل · تعطيل · فصل (متّصل).
      expect(find.byType(PermLockBadge), findsNWidgets(4));
      await close(t);
    });
  });
}
