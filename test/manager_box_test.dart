import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/managers_api.dart';
import 'package:rad_mysvcs/api/settlements_api.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/core/util/amount_input.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/managers/sheets/balance_op_sheet.dart';
import 'package:rad_mysvcs/screens/managers/sheets/pay_debt_sheet.dart';
import 'package:rad_mysvcs/screens/settlements/settle_widgets.dart';
import 'package:rad_mysvcs/services/manager_money.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/transfer_pay.dart';

import 'sim_el/sim_harness.dart';

/// «كاش المدراء يدخل الصندوق» بالتطبيق (٢٣ نوفمبر ٢٠٢٦ — المالك: «تمام، كاش المدراء يدخل الصندوق… والمدير هم يقدر عنده تخيير انه
/// الماستر يستلمها ككاش… او تبقى بالماستر وبعدين هو يسحبها يعلمها كاش بالتقارير»).
/// ١) «تسوية الحساب»: «حركات المدراء» (manager_moves) من ردّ الخادم كما يكتبه (server/accountSettlements — الفحص الطرفيّ) — والخادم
///    الأقدم بلا المفتاح صفر؛ وحركاتها بالاتّجاه واسم المدير الفرعيّ.
/// ٢) نوافذ مال المدير الفرعيّ: «استلمته»/«أرجعته» حين يقول الخادم (money-settings)، والجسم يحمل الطريقة — وبلا الميزة كما كانت حرفاً.
void main() {
  group('«حركات المدراء» في الصندوق', () {
    test('الحساب الحاليّ: المجموع والعدّ وكلّ محصِّل — والخادم الأقدم بلا المفتاح صفر', () {
      final cur = CurrentAccount.fromJson({
        'started': true,
        'head': {'id': 3, 'kind': 'opening', 'status': 'active', 'opening_balance': 1000, 'carried_amount': 1000},
        'totals': {
          'opening_balance': 1000,
          'cash_activations': {'sum': 250000, 'count': 1},
          'debt_payments': {'sum': 0, 'count': 0},
          'cash_in': 250000,
          'expenses': {'sum': 0, 'count': 0},
          'new_debts': {'sum': 0, 'count': 0},
          'employee_moves': {'sum': 0, 'count': 0},
          'manager_moves': {'sum': 472000, 'count': 5},
          'expected_amount': 723000,
        },
        'collectors': [
          {'employee_id': null, 'net_amount': 642000, 'cash_activations': {'sum': 250000, 'count': 1}, 'manager_moves': {'sum': 392000, 'count': 4}},
          {'employee_id': 7, 'name': 'محاسب', 'net_amount': 80000, 'manager_moves': {'sum': 80000, 'count': 1}},
        ],
      })!;
      expect([cur.managerMoves.sum, cur.managerMoves.count, cur.expected], [472000, 5, 723000]);
      expect(cur.moveCount, 6, reason: 'تفعيلٌ واحد + خمس حركات مدراء');
      expect(cur.collectors.firstWhere((c) => c.employeeId == 7).managerMoves.sum, 80000);
      final old = CurrentAccount.fromJson({'started': true, 'totals': {'cash_activations': {'sum': 1, 'count': 1}}})!;
      expect([old.managerMoves.sum, old.managerMoves.count], [0, 0]);
    });

    test('التسوية المحفوظة وقائمة الحركات: السحب خارجٌ بمبلغه الموجب، والعنوان اسم المدير الفرعيّ', () {
      final s = SettlementRecord.fromJson({'id': 9, 'kind': 'settlement', 'status': 'active', 'manager_moves': {'sum': -30000, 'count': 2}})!;
      expect([s.managerMoves.sum, s.managerMoves.count], [-30000, 2]);
      final m = BoxMovement.fromJson({
        'source': 'manager', 'id': 51, 'kind': 'manager_withdraw', 'direction': 'out', 'amount': 50000,
        'created_at': '2026-11-23T19:00:00Z', 'manager': 'sub.mgr', 'description': 'سحب رصيد 50,000 د.ع من المدير sub.mgr',
      })!;
      expect([m.source, m.kind, m.isIn, m.amount, m.manager, m.paymentActivityId], ['manager', 'manager_withdraw', false, 50000, 'sub.mgr', null]);
    });

    test('سطر الصندوق: داخلٌ (+) أو أُعيد (−) بإشارته', () {
      final inL = managerBoxLine(const MoneyCount(472000, 5));
      expect([inL.label, inL.value, inL.out], ['من المدراء الفرعيّين', '+472,000', false]);
      final outL = managerBoxLine(const MoneyCount(-30000, 2));
      expect([outL.label, outL.value, outL.out], ['أُعيد للمدراء الفرعيّين', '−30,000', true]);
    });
  });

  setUpAll(simSetUpAll);
  tearDown(() {
    PermissionsService.debugReset();
    ManagerMoneyState.reset();
    TransferPay.reset();
  });

  List<String> clipped(Finder of) => [
        for (final e in find.descendant(of: of, matching: find.byType(RichText)).evaluate())
          if ((e.renderObject! as RenderParagraph).didExceedMaxLines) (e.renderObject! as RenderParagraph).text.toPlainText(),
      ];

  group('نافذة «شحن رصيد/سحب» (الساس)', () {
    const m = Manager(id: 41, username: 'mgr.north', mobile: '07700000001', balance: 400000);

    Future<SimServer> server({Map<String, Object?>? money}) async {
      final s = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@popq'});
      WhatsAppApi.clearCaches();
      PermissionsService.debugSet(isEmployee: false);
      if (money != null) s.reply('GET', '/api/v2/managers/money-settings', 200, money);
      s.reply('GET', '/api/v2/manager-topup-fees/config', 200, {'success': true, 'enabled': false});
      s.reply('POST', '/api/v2/managers/41/deposit', 200, {'success': true});
      s.reply('POST', '/api/v2/managers/41/withdraw', 200, {'success': true});
      s.reply('GET', '/api/admin/manager-debts/summary', 200, {'success': true, 'perDebtor': []});
      s.reply('GET', '/api/whatsapp/templates/2', 200, {'success': true, 'templates': []});
      s.reply('POST', '/api/whatsapp/send-message', 200, {'success': true});
      s.reply('POST', '/api/fcm/send-manager-balance-update', 200, {'success': true});
      return s;
    }

    Future<void> open(WidgetTester t, {BalanceOpKind kind = BalanceOpKind.deposit, SimVariant v = const SimVariant(390, dark: false)}) async {
      await pumpSim(t, v, home: (ctx) => simLauncher((c) => showBalanceOpSheet(c, m, preselected: kind)));
      await simOpen(t);
      await t.pumpAndSettle();
    }

    // حقل المبلغ نفسه (حقل اسم «أخرى» فوقه حين تُختار)
    Future<void> amount(WidgetTester t, String v) async {
      final f = find.descendant(of: find.byType(AmountShorthandBox), matching: find.byType(TextField));
      await t.ensureVisible(f);
      await t.enterText(f, v);
      await t.pumpAndSettle();
    }

    Future<void> submit(WidgetTester t) async {
      await t.ensureVisible(find.byType(SheetFooterBar));
      await t.tap(find.byType(SheetFooterBar));
      await t.pumpAndSettle();
    }

    final picker = find.byKey(const ValueKey('mgr-paid-via'));

    testWidgets('مفتوح مع «الحوالات»: «استلمته» تحت «شحن نقدي»، واختيار زين كاش يُرسَل — وسطره يقول رصيد طريقتها', (t) async {
      final s = await server(money: {'success': true, 'data': {'manager_box': true, 'transfers': true}});
      await open(t);
      expect(picker, findsOneWidget);
      expect(find.descendant(of: picker, matching: find.text('استلمته')), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('paid-via-zaincash')));
      await t.tap(find.byKey(const ValueKey('paid-via-zaincash')));
      await t.pumpAndSettle();
      expect(find.text('يُحسب على رصيد «زين كاش» — لا يدخل الصندوق حتى تسحبه.'), findsOneWidget);
      await amount(t, '500000');
      await submit(t);
      final body = s.bodies('POST', '/api/v2/managers/41/deposit').single;
      expect([body['amount'], body['isLoan'], body['paid_via']], [500000, false, 'zaincash']);
      expect(body.containsKey('paid_via_name'), isFalse);
      await simDrain(t);
    });

    testWidgets('«آجل»: لا اختيار ولا طريقة في الجسم (لا استلام الآن)', (t) async {
      final s = await server(money: {'success': true, 'data': {'manager_box': true, 'transfers': true}});
      await open(t);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(picker, findsNothing);
      await amount(t, '200000');
      await submit(t);
      final body = s.bodies('POST', '/api/v2/managers/41/deposit').single;
      expect([body['isLoan'], body.containsKey('paid_via')], [true, false]);
      await simDrain(t);
    });

    testWidgets('«أخرى» بلا اسم: لا يُرسل شيء — وباسمها تُرسل مطبَّعة كما كُتبت', (t) async {
      final s = await server(money: {'success': true, 'data': {'manager_box': true, 'transfers': true}});
      await open(t);
      await t.ensureVisible(find.byKey(const ValueKey('paid-via-other')));
      await t.tap(find.byKey(const ValueKey('paid-via-other')));
      await t.pumpAndSettle();
      await amount(t, '60000');
      await submit(t);
      expect(s.calls('POST', '/api/v2/managers/41/deposit'), isEmpty);
      expect(find.text('اكتب اسم الطريقة (أخرى)'), findsWidgets);
      // الرسالة تغطّي الزرّ حتى تختفي
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('paid-via-other-name')), 'آسيا حوالة');
      await t.pumpAndSettle();
      await submit(t);
      final body = s.bodies('POST', '/api/v2/managers/41/deposit').single;
      expect([body['paid_via'], body['paid_via_name']], ['other', 'آسيا حوالة']);
      await simDrain(t);
    });

    testWidgets('أسماء «أخرى» السريعة من الخادم: النافذة تسأل «الحوالات» عند فتحها — ونقرة الاسم تُرسله', (t) async {
      final s = await server(money: {'success': true, 'data': {'manager_box': true, 'transfers': true}});
      s.reply('GET', '/api/v2/transfer-pay', 200, {'success': true, 'data': {'available': true, 'names': ['حوالة الرافدين']}});
      await open(t);
      expect(s.calls('GET', '/api/v2/transfer-pay'), hasLength(1));
      await t.ensureVisible(find.byKey(const ValueKey('paid-via-other')));
      await t.tap(find.byKey(const ValueKey('paid-via-other')));
      await t.pumpAndSettle();
      final chip = find.descendant(of: picker, matching: find.text('حوالة الرافدين'));
      expect(chip, findsOneWidget);
      await t.ensureVisible(chip);
      await t.tap(chip);
      await t.pumpAndSettle();
      await amount(t, '75000');
      await submit(t);
      final body = s.bodies('POST', '/api/v2/managers/41/deposit').single;
      expect([body['paid_via'], body['paid_via_name']], ['other', 'حوالة الرافدين']);
      await simDrain(t);
    });

    testWidgets('السحب: «أرجعته» وسطرها يقول من أين يخرج — كاشاً من الصندوق، وحوالةً من رصيد طريقتها', (t) async {
      final s = await server(money: {'success': true, 'data': {'manager_box': true, 'transfers': true}});
      await open(t, kind: BalanceOpKind.withdraw);
      expect(find.descendant(of: picker, matching: find.text('أرجعته')), findsOneWidget);
      expect(find.text('يخرج من الصندوق.'), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('paid-via-master')));
      await t.tap(find.byKey(const ValueKey('paid-via-master')));
      await t.pumpAndSettle();
      expect(find.text('يُخصم من رصيد «ماستر».'), findsOneWidget);
      await amount(t, '30000');
      await submit(t);
      expect(s.bodies('POST', '/api/v2/managers/41/withdraw').single['paid_via'], 'master');
      await simDrain(t);
    });

    testWidgets('المفتاح مفتوح بلا «الحوالات»: لا اختيار — سطرٌ واحد «يدخل الصندوق.»، والجسم بلا طريقة', (t) async {
      final s = await server(money: {'success': true, 'data': {'manager_box': true, 'transfers': false}});
      await open(t);
      expect(picker, findsNothing);
      expect(find.byKey(const ValueKey('mgr-box-note')), findsOneWidget);
      expect(find.text('يدخل الصندوق.'), findsOneWidget);
      await amount(t, '100000');
      await submit(t);
      expect(s.bodies('POST', '/api/v2/managers/41/deposit').single.containsKey('paid_via'), isFalse);
      await simDrain(t);
    });

    testWidgets('بلا الميزة (خادمٌ أقدم بلا المسار، أو مطفأ): النافذة كما كانت حرفاً — لا اختيار ولا سطر ولا طريقة', (t) async {
      for (final money in <Map<String, Object?>?>[null, {'success': true, 'data': {'manager_box': false, 'transfers': true}}]) {
        final s = await server(money: money);
        await open(t);
        expect(picker, findsNothing);
        expect(find.byKey(const ValueKey('mgr-box-note')), findsNothing);
        await amount(t, '100000');
        await submit(t);
        expect(s.bodies('POST', '/api/v2/managers/41/deposit').single.containsKey('paid_via'), isFalse);
        ManagerMoneyState.reset();
        await simDrain(t);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
      }
    });

    testWidgets('بأضيق هاتف وخطٍّ ×1.2 (فاتح وداكن): «استلمته» كاملةٌ بلا نصٍّ مقصوص', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      for (final dark in [false, true]) {
        await server(money: {'success': true, 'data': {'manager_box': true, 'transfers': true}});
        await open(t, v: SimVariant(320, dark: dark));
        await t.ensureVisible(find.byKey(const ValueKey('paid-via-other')));
        await t.tap(find.byKey(const ValueKey('paid-via-other')));
        await t.pumpAndSettle();
        expect(clipped(picker), isEmpty, reason: 'dark=$dark');
        expect(t.takeException(), isNull);
        ManagerMoneyState.reset();
        await simDrain(t);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
      }
    });
  });

  group('نافذة «تسديد دين» المدير', () {
    const m = Manager(id: 41, username: 'mgr.north', mobile: '07700000001', balance: 0, totalDebt: 300000, debtForMe: 300000);

    Future<SimServer> server({Map<String, Object?>? money}) async {
      final s = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@popq'});
      WhatsAppApi.clearCaches();
      PermissionsService.debugSet(isEmployee: false);
      if (money != null) s.reply('GET', '/api/v2/managers/money-settings', 200, money);
      s.reply('GET', '/api/v2/managers/41/debt', 200, {'success': true, 'data': {'total': 300000, 'debt_for_me': 300000, 'balance': 0}});
      s.reply('GET', '/api/admin/manager-debts/summary', 200, {'success': true, 'perDebtor': []});
      s.reply('POST', '/api/v2/managers/41/sas-pay-debt', 200, {'success': true});
      s.reply('GET', '/api/whatsapp/templates/2', 200, {'success': true, 'templates': []});
      s.reply('POST', '/api/whatsapp/send-message', 200, {'success': true});
      s.reply('POST', '/api/fcm/send-manager-balance-update', 200, {'success': true});
      return s;
    }

    testWidgets('دين الساس: «استلمته» وماستر تُرسل مع التسديد — وبلا الميزة لا شيء', (t) async {
      for (final on in [true, false]) {
        final s = await server(money: {'success': true, 'data': {'manager_box': on, 'transfers': on}});
        await pumpSim(t, const SimVariant(390, dark: false), home: (_) => simLauncher((ctx) => showPayDebtSheet(ctx, m)));
        await simOpen(t);
        await t.pumpAndSettle();
        final picker = find.byKey(const ValueKey('mgr-paid-via'));
        expect(picker, on ? findsOneWidget : findsNothing);
        // أسماء «أخرى» السريعة: تسأل «الحوالات» عند فتحها كشيتات d9
        expect(s.calls('GET', '/api/v2/transfer-pay'), isNotEmpty);
        if (on) {
          await t.ensureVisible(find.byKey(const ValueKey('paid-via-master')));
          await t.tap(find.byKey(const ValueKey('paid-via-master')));
          await t.pumpAndSettle();
        }
        await t.enterText(find.byType(TextField).first, '100000');
        await t.pumpAndSettle();
        await t.ensureVisible(find.byType(SheetFooterBar));
        await t.tap(find.byType(SheetFooterBar));
        await t.pumpAndSettle();
        final body = s.bodies('POST', '/api/v2/managers/41/sas-pay-debt').single;
        expect(body['amount'], 100000);
        expect(body['paid_via'], on ? 'master' : isNull);
        ManagerMoneyState.reset();
        await simDrain(t);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
      }
    });
  });
}
