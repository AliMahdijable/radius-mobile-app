import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/screens/portal_settings/portal_settings_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «وصف الباقات» لمالك ايرث لنك بعد أن مرّر الخادم المسارين (elPassthrough —
/// ١٨ أكتوبر): القائمة من حسابه في ايرث لنك، فالنصوص تقول «ايرث لنك» لا «SAS».
/// وقائمةٌ وصلت فارغة قد تكون تعذّراً عند المزوّد (الخادم يردّ `[]` لا خطأً)
/// — فتُعاد بمكانها ولا يُضطرّ المالك لمغادرة الشاشة.
const _settings = '/api/v2/portal/settings';
const _packages = '/api/v2/admin/portal-packages';
const _v = SimVariant(360, dark: false);

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    PermissionsService.debugSet(isEmployee: false);
    server.reply('GET', _settings, 200,
        {'success': true, 'enabled': true, 'agent_code': '402917'});
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Future<void> openPackages(WidgetTester t) async {
    await pumpSim(t, _v, home: (_) => const PortalSettingsScreen());
    await t.tap(find.text('وصف الباقات'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  void packages(List<Map<String, Object?>> list) =>
      server.reply('GET', _packages, 200, {'success': true, 'packages': list});

  const economy = {
    'profile_id': 101,
    'sas_name': 'Economy',
    'price': 25000,
    'display_name': null,
    'description': null,
    'image_url': null,
    'display_order': 100,
    'is_hidden': false,
  };

  testWidgets(
      '🚨 ايرث لنك بلا باقات: «إعدادات ايرث لنك» لا SAS + «إعادة المحاولة» تعيد الطلب',
      (t) async {
    ProviderService.debugSet('earthlink');
    packages(const []);
    await openPackages(t);
    expect(find.text('لا توجد باقات — تحقّق من إعدادات ايرث لنك الخاصّة بك'),
        findsOneWidget);
    expect(find.textContaining('SAS'), findsNothing);
    expect(server.calls('GET', _packages), hasLength(1));

    packages(const [economy]); // المزوّد عاد
    await t.tap(find.text('إعادة المحاولة'));
    await t.pumpAndSettle();
    expect(server.calls('GET', _packages), hasLength(2));
    expect(find.text('Economy'), findsOneWidget);
  });

  testWidgets('القائمة الفارغة تُسحب للتحديث أيضاً', (t) async {
    ProviderService.debugSet('earthlink');
    packages(const []);
    await openPackages(t);
    packages(const [economy]);
    await t.fling(find.byType(SingleChildScrollView).last,
        const Offset(0, 400), 1200);
    await t.pumpAndSettle();
    expect(server.calls('GET', _packages), hasLength(2));
    expect(find.text('Economy'), findsOneWidget);
  });

  testWidgets('SAS4 بلا باقات: النصّ كما كان («إعدادات SAS»)', (t) async {
    packages(const []);
    await openPackages(t);
    expect(find.text('لا توجد باقات — تحقّق من إعدادات SAS الخاصّة بك'),
        findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
  });

  for (final (provider, name) in [('earthlink', 'ايرث لنك'), (null, 'SAS')]) {
    testWidgets('محرّر الباقة والاستعادة يقولان «$name»', (t) async {
      ProviderService.debugSet(provider);
      packages(const [economy]);
      await openPackages(t);
      await t.tap(find.text('Economy'));
      await t.pumpAndSettle();
      expect(find.text('لو فارغ، يستعمل الاسم الأصلي من $name'),
          findsOneWidget);
      if (provider != null) expect(find.textContaining('SAS'), findsNothing);
      // زرّ الاستعادة في تذييل الشيت ← حوار التأكيد.
      await t.tap(find.byIcon(LucideIcons.rotateCcw));
      await t.pumpAndSettle();
      expect(
          find.text(
              'الباقة سترجع لبياناتها الأصلية من $name (الاسم الأصلي، بدون وصف/صورة).'),
          findsOneWidget);
      await t.tap(find.text('إلغاء'));
      await t.pumpAndSettle();
    });
  }
}
