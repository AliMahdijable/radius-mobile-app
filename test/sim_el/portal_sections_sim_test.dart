import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/portal_settings/portal_settings_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// محاكاة «ما يراه مشتركوك» — مفتاحا «حالة الاتصال» و«الاستهلاك» (وسيط
/// البوّابة §11) تحت مفتاح البوّابة في تبويب «رمز الوكيل»، كما يراها المالك
/// والموظّف، بالعروض الثلاثة وبالوضعين. اللقطات في `shots/portal_sections/`.
/// السلوك مفحوصٌ في `test/portal_sections_test.dart`؛ هنا الرسم: لا فيضان حتى
/// ٣٢٠، ولا نصّ خام، والمفتاحان بشكل مفتاح البوّابة نفسه.
///
/// السجلّ فارغٌ عمداً: لا وقتَ نسبيّاً («منذ…» وتاريخٌ قصير) يغيّر اللقطة من
/// تشغيلٍ لتشغيل.
const _shot = 'portal_sections';

/// المتغيّر حبّةٌ مقصودة في التلميح — الأقواس جزءٌ منه لا أثرٌ تقنيّ.
final _allowVariable = [RegExp(r'^\{agent_code\}$')];

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Future<void> sas4() async {
    server = await simSetUp(secure: {'auth.admin_id': '2251'});
    ProviderService.debugSet(null);
  }

  Future<void> earthlink() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
  }

  void serve({bool connection = true, bool usage = true}) {
    server.reply('GET', '/api/v2/portal/settings', 200, {
      'success': true,
      'enabled': true,
      'agent_code': '402917',
      'sections': {'connection': connection, 'usage': usage, 'device': false},
    });
    server.reply(
        'GET', '/api/v2/portal/logins', 200, {'success': true, 'data': []});
  }

  /// الشاشة ثمّ سحبٌ للأعلى يُظهر مفتاح البوّابة والمفتاحين تحته.
  Future<void> open(WidgetTester t, SimVariant v) async {
    await pumpSim(t, v, home: (_) => const PortalSettingsScreen());
    await t.drag(find.text('تفعيل بوابة مشتركيّ'), const Offset(0, -300));
    await t.pumpAndSettle();
    expect(find.text('حالة الاتصال'), findsOneWidget);
    expect(find.text('الاستهلاك'), findsOneWidget);
  }

  simCase(_shot, 'owner', (t, v) async {
    await sas4();
    PermissionsService.debugSet(isEmployee: false);
    serve();
    await open(t, v);
    expect(find.byType(Switch), findsNWidgets(3));
    await simCheck(t, v, _shot, 'owner', allow: _allowVariable);
  });

  simCase(_shot, 'owner_hidden', (t, v) async {
    await sas4();
    PermissionsService.debugSet(isEmployee: false);
    serve(connection: false, usage: false);
    await open(t, v);
    expect(find.text('مخفي عن مشتركيك'), findsNWidgets(2));
    await simCheck(t, v, _shot, 'owner_hidden', allow: _allowVariable);
  });

  simCase(_shot, 'employee', (t, v) async {
    await sas4();
    PermissionsService.debugSet(isEmployee: true);
    serve(usage: false);
    await open(t, v);
    expect(find.byType(Switch), findsNothing);
    await simCheck(t, v, _shot, 'employee', allow: _allowVariable);
  });

  simCase(_shot, 'el_employee', (t, v) async {
    await earthlink();
    PermissionsService.debugSet(
        isEmployee: true, permissions: const {'subscribers.view': true});
    serve();
    await open(t, v);
    expect(find.byType(TabBar), findsNothing);
    await simCheck(t, v, _shot, 'el_employee', allow: _allowVariable);
  });
}
