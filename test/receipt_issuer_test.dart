import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/receipt_issuer_api.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/screens/print_templates/issuer_names_sheet.dart';
import 'package:rad_mysvcs/services/receipt_service.dart';
import 'package:rad_mysvcs/services/sale_print.dart';
import 'package:rad_mysvcs/api/sales_api.dart';

import 'sim_el/sim_harness.dart';

/// «أصدره» على الوصل باسمٍ عربيّ يختاره المدير لنفسه ولكلّ موظّف (٢ نوفمبر — الخادم 5c2172e): الإعدادات تحمل issuer_name لمن
/// يطبع، والطباعة تأخذه بدل اليوزر (والفارغ كما كان)، والنافذة تقرأ وتحفظ الأسماء.
const _v = SimVariant(390, dark: false);
const _path = '/api/v2/receipt-settings/issuer-names';

void main() {
  test('الإعدادات: issuer_name ⇒ «أصدره» بدل اليوزر، والفارغ أو الغائب كما كان', () {
    final s = ReceiptSettings.fromJson({'issuer_name': 'علي الموسوي'});
    expect(s.issuerName, 'علي الموسوي');
    expect(ReceiptService.issuerOf(s, 'admin@supernet'), 'علي الموسوي');
    expect(ReceiptService.issuerOf(ReceiptSettings.fromJson({'issuer_name': '  '}), 'admin@supernet'), 'admin@supernet');
    expect(ReceiptService.issuerOf(ReceiptSettings.fromJson(const {}), 'admin@supernet'), 'admin@supernet');
    expect(ReceiptService.issuerOf(null, null), isNull);
  });

  test('فاتورة البيع: البائع الموظّف كما كان، وإلّا الاسم المختار', () {
    final look = ReceiptSettings.fromJson({'issuer_name': 'علي'});
    final mine = Sale.fromJson({'id': 1, 'total': 1000, 'lines': const []})!;
    expect(SalePrint.doc(mine, look: look, shop: 'محل', issuer: ReceiptService.issuerOf(look, 'admin@x')).issuer, 'علي');
    final emp = Sale.fromJson({'id': 2, 'total': 1000, 'lines': const [], 'employee_id': 7, 'by': 'hasan'})!;
    expect(SalePrint.doc(emp, look: look, shop: 'محل', issuer: ReceiptService.issuerOf(look, 'admin@x')).issuer, 'hasan');
  });

  test('النموذج: الموظّفون بأسمائهم، والتسمية الاسم الكامل أو اليوزر', () {
    final d = IssuerNames.fromJson({
      'owner': 'علي',
      'owner_default': 'admin@x',
      'max': 40,
      'employees': [
        {'id': 7, 'username': 'hasan', 'full_name': 'Hasan K', 'active': true, 'name': 'حسن'},
        {'id': 9, 'username': 'zainab', 'full_name': null, 'active': false, 'name': null},
      ],
    })!;
    expect((d.owner, d.ownerDefault, d.max, d.employees.length), ('علي', 'admin@x', 40, 2));
    expect((d.employees[0].label, d.employees[0].name, d.employees[1].label, d.employees[1].active), ('Hasan K', 'حسن', 'zainab', false));
  });

  group('النافذة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': '2268', 'auth.admin_username': 'admin@x'});
    });

    testWidgets('تقرأ الأسماء ثمّ تحفظها بجسمٍ بالضبط (الفارغ يمحو)', (t) async {
      server.reply('GET', _path, 200, {
        'success': true,
        'data': {
          'owner': null,
          'owner_default': 'admin@x',
          'max': 40,
          'employees': [
            {'id': 7, 'username': 'hasan', 'full_name': null, 'active': true, 'name': 'حسن'},
          ],
        },
      });
      server.reply('PUT', _path, 200, {'success': true, 'data': {'owner': 'علي الموسوي', 'owner_default': 'admin@x', 'max': 40, 'employees': []}});
      server.reply('GET', '/api/v2/receipt-settings', 200, {'success': true, 'data': {'issuer_name': 'علي الموسوي'}});
      await pumpSim(t, _v, home: (_) => simLauncher((c) => showIssuerNamesSheet(c)));
      await simOpen(t);
      await t.pumpAndSettle();
      expect(find.text('اسم «أصدره» على الوصل'), findsOneWidget);
      expect(find.text('بدل admin@x'), findsOneWidget);
      await t.enterText(find.byType(TextField).at(0), '  علي الموسوي ');
      await t.enterText(find.byType(TextField).at(1), '');
      await t.tap(find.text('حفظ'));
      await t.pumpAndSettle();
      expect(server.bodies('PUT', _path).single, {'owner': 'علي الموسوي', 'employees': {'7': ''}});
      expect(find.text('اسم «أصدره» على الوصل'), findsNothing, reason: 'أُغلقت');
      await t.pump(const Duration(seconds: 4));
      await simDrain(t);
    });

    testWidgets('خادمٌ أقدم ⇒ رسالةٌ بلا زرّ حفظ', (t) async {
      server.reply('GET', _path, 404, {'success': false, 'message': 'غير موجود'});
      await pumpSim(t, _v, home: (_) => simLauncher((c) => showIssuerNamesSheet(c)));
      await simOpen(t);
      await t.pumpAndSettle();
      expect(find.text('تحتاج تحديث الخادم'), findsOneWidget);
      expect(find.text('حفظ'), findsNothing);
      await simDrain(t);
    });
  });
}
