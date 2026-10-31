import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// المشروع الوطنيّ — التفعيل بالتطبيق (٣١ أكتوبر، الخادم server/watani/wataniAdapter quote/renew): رفضٌ مقصود من الخادم
/// (409 برسالةٍ عربيّة، مثل «لا سعر بيع… حدّده من «الباقات»») يُعرض نصّه في الشيت بدل «تعذّر تحميل بيانات التفعيل»،
/// والباقة الحاليّة وحدها تُعرض وتُجدَّد بلا profile_id آخر.
const _v = SimVariant(390, dark: false);
const _idx = '13293073';

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Future<void> open(WidgetTester t) async {
    final sub = Subscriber.fromJson({'idx': _idx, 'username': 'dev-user', 'firstname': 'مشترك', 'profile_id': 11, 'profile_name': 'BASIC'});
    await pumpSim(t, _v, home: (_) => Scaffold(
          body: Builder(builder: (c) => Center(child: TextButton(onPressed: () => showActivateSheet(c, sub), child: const Text('open')))),
        ));
    await t.tap(find.text('open'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
  }

  testWidgets('بلا سعر بيع: رسالة الخادم نفسها بدل «تعذّر التحميل»', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 409, {
      'success': false,
      'code': 'SALE_PRICE_MISSING',
      'message': 'لا سعر بيع لباقة «BASIC» — حدّده من «الباقات» ثمّ فعّل (لم يُفعَّل شيء)',
    });
    await open(t);
    expect(find.textContaining('حدّده من «الباقات»'), findsOneWidget);
    expect(server.calls('POST', '/api/v2/subscribers/$_idx/activate'), isEmpty);
    await simDrain(t);
  });

  testWidgets('خطأٌ غير مقصود (500) ⇒ الرسالة العامّة كما كانت', (t) async {
    server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 500, {'success': false, 'message': 'Internal'});
    await open(t);
    expect(find.textContaining('Internal'), findsNothing);
    await simDrain(t);
  });
}
