import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/managers_api.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/managers/sheets/balance_op_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'sim_el/sim_harness.dart';

/// رسالة «حركة مالية» للمدير بعد شحن/سحب/نقاط — «ديون أخرى» من دفتر ديون المدراء، لا صفرٌ ثابت.
///
/// المالك ٣٠ أكتوبر (لقطة «إضافة نقاط» لمصطفى حمزه): «ديون اخرى مجاي يرسله النظام» — الرسالة قالت «ديون أخرى: 0»
/// و«المجموع: 167,000» وعليه 125,000 ديوناً أخرى ظاهرةً في قائمة المدراء نفسها.
void main() {
  const v = SimVariant(390, dark: false);
  setUpAll(simSetUpAll);

  const template = 'ديون الساس: {sas_debts}\nديون أخرى: {other_debts}\nالمجموع: {total_debts}';
  const m = Manager(
    id: 1520,
    username: 'admin@must1982',
    firstname: 'مصطفى',
    lastname: 'حمزه',
    mobile: '07725200465',
    totalDebt: 167000,
  );

  Future<SimServer> setUpServer({Object? summary}) async {
    final server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@popq'});
    WhatsAppApi.clearCaches();
    PermissionsService.debugSet(isEmployee: false);
    server.reply('POST', '/api/v2/managers/1520/add-points', 200, {'success': true});
    if (summary != null) server.reply('GET', '/api/admin/manager-debts/summary', 200, summary);
    server.reply('GET', '/api/whatsapp/templates/2', 200, {
      'success': true,
      'templates': [
        {'template_type': 'manager_agent', 'is_active': 1, 'message_content': template},
      ],
    });
    server.reply('POST', '/api/whatsapp/send-message', 200, {'success': true});
    server.reply('POST', '/api/fcm/send-manager-balance-update', 200, {'success': true});
    return server;
  }

  Future<void> addTwoPoints(WidgetTester t, {num? listed}) async {
    await pumpSim(
      t,
      v,
      home: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showBalanceOpSheet(ctx, m, preselected: BalanceOpKind.addPoints, otherDebts: listed),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '2');
    await t.pumpAndSettle();
    await t.tap(find.byType(SheetFooterBar));
    await t.pumpAndSettle();
  }

  testWidgets('«ديون أخرى» = الباقي في دفتر ديون المدراء (يُقرأ وقت الإرسال)، والمجموع ساس + أخرى', (t) async {
    final server = await setUpServer(summary: {
      'success': true,
      'perDebtor': [
        {'debtor_admin_id': 1520, 'total_remaining': 125000, 'total_amount': 125000, 'debts_count': 1},
        {'debtor_admin_id': 9, 'total_remaining': 5000, 'total_amount': 5000, 'debts_count': 1},
      ],
    });
    await addTwoPoints(t, listed: 0);
    final sent = server.bodies('POST', '/api/whatsapp/send-message').single;
    expect(sent['message'], 'ديون الساس: 167,000\nديون أخرى: 125,000\nالمجموع: 292,000');
    final push = server.bodies('POST', '/api/fcm/send-manager-balance-update').single;
    expect([push['previousDebt'], push['currentDebt']], [292000, 292000], reason: 'الإشعار يقول الدين كلّه كورقة التسديد');
    await simDrain(t);
  });

  testWidgets('تعذّر قراءة الدفتر ⇒ ما عرضته قائمة المدراء، لا صفر', (t) async {
    final server = await setUpServer();
    await addTwoPoints(t, listed: 125000);
    final sent = server.bodies('POST', '/api/whatsapp/send-message').single;
    expect(sent['message'], 'ديون الساس: 167,000\nديون أخرى: 125,000\nالمجموع: 292,000');
    await simDrain(t);
  });
}
