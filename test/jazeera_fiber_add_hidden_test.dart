import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_limits.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'visual_perm/visual_perm_harness.dart';

/// فايبر الجزيرة (المالك ١٤ نوفمبر: «اني هسه فاتح الصفحه مال جزيرة بالتطبيق ماعنده صلاحيه يمدد او يفعل واضافة مشترك لازم نخفي الزر
/// الهم لان هم ماعدهم اضافة»): الخادم (f6ac57d) يرسل قدرات صفحة ftth — التفعيل والتمديد من موقع الشحن، و`subscribers.add` = إنشاء
/// الساس — والتطبيق يُخفي «إضافة مشترك» لصاحب الصفحة متى قالت قدراتها لا: من «+» والقائمة والأمر الصوتيّ (كلّها عبر
/// [providerHidesAction])، لا مقفلاً بـ«اطلبها من مديرك». والتفعيل والتمديد يتبعان القدرات كأيّ مفتاح.
void main() {
  setUpAll(visualSetUpAll);

  /// قدرات صفحة الجزيرة على الطريق كما يرسلها الخادم الآن (عيّنة ما يمسّ الإضافة والتفعيل).
  const railCaps = <String, bool>{
    'subscribers.view': true,
    'subscribers.create': false,
    'subscribers.add': false,
    'subscribers.activate': true,
    'subscribers.extend': true,
    'subscribers.edit': false,
    'subscribers.change_profile': true,
  };

  Future<void> asCompany(String code, {String adminId = 'ftth:1460', String url = 'https://ftth.jt.iq'}) =>
      ActiveCompany.saveFromLogin(
        sasUrl: url,
        adminId: adminId,
        loginUsername: 'agent.fiber',
        adminUsername: 'agent.fiber',
        isEmployee: false,
        label: 'فايبر الجزيرة',
        sasCode: code,
      );

  group('providerHidesAction — فايبر الجزيرة', () {
    tearDown(() async {
      await ActiveCompany.clear();
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });

    test('صاحب صفحةٍ قدراتها بلا إضافة ⇒ «إضافة مشترك» مخفيّ (المفتاحان)، والتفعيل والتمديد لا يُخفيان', () async {
      await asCompany('ftth');
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: railCaps);
      expect(sessionIsJazeeraFiber, isTrue);
      expect(providerHidesAction('subscribers.add'), isTrue);
      expect(providerHidesAction('subscribers.create'), isTrue);
      for (final k in ['subscribers.activate', 'subscribers.extend', 'subscribers.change_profile', 'subscribers.edit']) {
        expect(providerHidesAction(k), isFalse, reason: k);
      }
      expect(Perms.has('subscribers.activate'), isTrue, reason: 'التفعيل مفتوحٌ بقدرات الخادم');
      expect(Perms.has('subscribers.extend'), isTrue, reason: 'التمديد («دايني») مفتوح');
    });

    test('صفحة فايبر يمنحها ساسها الإنشاء ⇒ الإضافة تبقى', () async {
      await asCompany('ftth');
      PermissionsService.debugSet(
        isEmployee: false,
        managerRestricted: true,
        managerCaps: {...railCaps, 'subscribers.create': true, 'subscribers.add': true},
      );
      expect(providerHidesAction('subscribers.add'), isFalse);
    });

    test('مدير غير مقيَّد (لا قدرات) ⇒ كما كان', () async {
      await asCompany('ftth');
      PermissionsService.debugSet(isEmployee: false);
      expect(providerHidesAction('subscribers.add'), isFalse);
    });

    test('الموظّف بما مُنح — لا إخفاء من هنا', () async {
      await asCompany('ftth');
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
      expect(providerHidesAction('subscribers.add'), isFalse);
    });

    test('غير فايبر الجزيرة بالقدرات نفسها ⇒ كما كان (مقفلٌ بمكانه لا مخفيّ): الجزيرة اللاسلكيّ، الأصل، المشروع الوطنيّ', () async {
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: railCaps);
      await asCompany('jt', adminId: 'jt:6836', url: 'https://sas.jt.iq');
      expect(sessionIsJazeeraFiber, isFalse);
      expect(providerHidesAction('subscribers.add'), isFalse);
      await asCompany('supernet', adminId: '12', url: 'https://reseller-supernet.net');
      expect(providerHidesAction('subscribers.add'), isFalse);
      // المشروع الوطنيّ: provider 'ftth' — ليس فايبر الجزيرة ولو كان الرمز ftth
      await asCompany('ftth');
      ProviderService.debugSet('ftth');
      expect(sessionIsJazeeraFiber, isFalse);
    });

    test('بلا شركةٍ نشطة ⇒ لا إخفاء', () async {
      await ActiveCompany.clear();
      PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: railCaps);
      expect(sessionIsJazeeraFiber, isFalse);
      expect(providerHidesAction('subscribers.add'), isFalse);
    });
  });

  group('ورقة «+» — صاحب صفحة الجزيرة', () {
    Future<void> openQuickAdd(WidgetTester t) async {
      await pumpVisual(t, phone, home: (_) => const MainShell());
      await settle(t, seconds: 2);
      await t.tap(find.byIcon(Icons.add_rounded).last);
      await settle(t, seconds: 2);
    }

    Future<void> drain(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 25));
    }

    const fiberOwner = Scenario(
      id: 'T_jaz_fiber_owner',
      title: 'صاحب صفحة فايبر الجزيرة — بلا إضافة',
      actor: Actor.sasSubAdmin,
      provider: null,
      managerCaps: railCaps,
    );

    Finder inSheet(Finder f) => find.descendant(of: find.byType(BottomSheet), matching: f);

    testWidgets('لا «إضافة مشترك» أصلاً، و«تجديد اشتراك» مفتوحٌ بلا قفل', (t) async {
      await visualSetUp(fiberOwner);
      try {
        await asCompany('ftth');
        await openQuickAdd(t);
        expect(inSheet(find.byIcon(Icons.person_add_rounded)), findsNothing, reason: 'البند غير موجود — لا مقفلاً');
        expect(inSheet(find.byIcon(Icons.bolt_rounded)), findsOneWidget, reason: 'التفعيل بمكانه');
        expect(inSheet(find.text('dashboard.add_subscriber')), findsNothing);
        await drain(t);
      } finally {
        await visualTearDown();
      }
    });

    testWidgets('الصفحة نفسها على ساسٍ آخر بالقدرات نفسها ⇒ «إضافة مشترك» بمكانه مقفلاً كما كان', (t) async {
      await visualSetUp(fiberOwner);
      try {
        await openQuickAdd(t); // الأصل (سوبرنت) من العدّة
        expect(inSheet(find.byIcon(Icons.person_add_rounded)), findsOneWidget);
        await drain(t);
      } finally {
        await visualTearDown();
      }
    });
  });
}
