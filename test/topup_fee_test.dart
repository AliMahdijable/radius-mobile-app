import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/el_managers_api.dart';
import 'package:rad_mysvcs/api/managers_api.dart';
import 'package:rad_mysvcs/api/topup_fee_api.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/managers/sheets/balance_op_sheet.dart';
import 'package:rad_mysvcs/screens/managers/sheets/el_topup_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'sim_el/sim_harness.dart';

/// «الفائدة» على شحن المدراء الآجل بالتطبيق (٢٠ نوفمبر ٢٠٢٦ — المالك: «ضيف بقسم المدراء بالشحن بايرث او غير ايرث نسبه الفائده او
/// مبلغ معين… من يشحن لوكيل اجل ام دين تنضاف ع الرصيد»).
///
/// ١) الحساب والنصوص على **وحدة الخادم الحيّة** نفسها: `topup_fee/server_fee_cases.json` ولّده `gen_server_fee_cases.js` من
///    server/managerTopupFees.js المنشور (بصمته = الحيّ) — لا أرقامٌ مكتوبةٌ باليد. الخادم يرفض (FEE_CHANGED) أيّ فائدةٍ تخالف حسابه.
/// ٢) نافذة شحن الساس ونافذة «المدراء» لايرث لنك: الحقل مع الآجل وحده وحين يفتحه الخادم، المقترح آخر فائدة، الجسم المُرسل، الملخّص،
///    ورسالة النجاح/التحذير — وبأضيق هاتف وخطٍّ ×1.2 لا نصّ مقصوص.
/// ٣) رسالة المدير: `{fee}` في القالب، وسطره يُحذف كلّه بلا فائدة؛ والإشعار يحملها مع الملاحظة.
void main() {
  final cases = jsonDecode(File('test/topup_fee/server_fee_cases.json').readAsStringSync()) as Map<String, dynamic>;
  TopupFeeKind kindOf(String k) => k == 'percent' ? TopupFeeKind.percent : TopupFeeKind.fixed;

  group('الحساب = الخادم', () {
    test('المبلغ والنصّ لكلّ حالة كما حسبتها وحدة الخادم الحيّة', () {
      final list = (cases['cases'] as List).cast<Map<String, dynamic>>();
      expect(list.length, greaterThan(10));
      for (final c in list) {
        final k = kindOf(c['kind'] as String);
        final v = c['value'] as num;
        final base = c['base'] as num;
        final a = TopupFee.amount(k, v, base);
        expect(a, c['amount'], reason: '${c['kind']} $v على $base');
        expect(TopupFee.label(k, v, a!), c['label'], reason: 'نصّ ${c['kind']} $v');
      }
    });

    test('قراءة ما يكتبه الوكيل كقراءة الخادم (valueOf): أرقامٌ عربيّة وفارسيّة، فواصل، منزلتان', () {
      for (final r in (cases['values'] as List).cast<Map<String, dynamic>>()) {
        final want = r['value'] as num?;
        final got = TopupFee.parseValue(r['raw'] as String);
        expect(got, want ?? isNull, reason: '«${r['raw']}»');
      }
    });

    test('ما يرفضه الخادم يُقال قبل الإرسال — وبلا مبلغٍ بعد لا خطأ (الزرّ معطّلٌ أصلاً)', () {
      expect(cases['meta']['max_percent'], 100);
      expect(TopupFee.problem(TopupFeeKind.percent, '101', 100000), 'النسبة أكبر من 100%');
      expect(TopupFee.problem(TopupFeeKind.percent, '0', 100000), 'اكتب الفائدة رقماً أكبر من صفر');
      expect(TopupFee.problem(TopupFeeKind.fixed, '-5', 100000), 'اكتب الفائدة رقماً أكبر من صفر');
      expect(TopupFee.problem(TopupFeeKind.percent, '', 100000), 'اكتب الفائدة رقماً أكبر من صفر');
      expect(TopupFee.problem(TopupFeeKind.fixed, '30,000', 25000), 'الفائدة أكبر من مبلغ الشحن');
      expect(TopupFee.problem(TopupFeeKind.percent, '0.01', 50), 'الفائدة أقلّ من دينار', reason: 'الخادم: FEE_TOO_SMALL (0 د.ع)');
      expect(TopupFee.problem(TopupFeeKind.percent, '2', 0), isNull);
      expect(TopupFee.problem(TopupFeeKind.none, 'أيّ شيء', 100000), isNull);
      expect(TopupFee.problem(TopupFeeKind.fixed, '25,000', 25000), isNull, reason: 'الفائدة = المبلغ تجوز (الخادم كذلك)');
      for (final b in (cases['bad'] as List).cast<Map<String, dynamic>>()) {
        expect(b['ok'], isFalse);
        if (b['kind'] == 'bonus') continue; // النوع يختاره الوكيل من ثلاثة — لا يُكتب
        expect(TopupFee.problem(kindOf(b['kind'] as String), '${b['value']}', 100000), isNotNull, reason: '$b');
      }
    });

    test('الجسم والمقترح والردّ', () {
      expect(TopupFee.body(TopupFeeKind.percent, '٢٫٥', 100000), {'kind': 'percent', 'value': 2.5, 'amount': 2500});
      expect(TopupFee.body(TopupFeeKind.fixed, '5,000', 100000), {'kind': 'fixed', 'value': 5000, 'amount': 5000});
      expect(TopupFee.body(TopupFeeKind.none, '2', 100000), isNull);
      expect(TopupFee.body(TopupFeeKind.percent, 'x', 100000), isNull);
      expect([TopupFee.valueText(TopupFeeKind.percent, 2.5), TopupFee.valueText(TopupFeeKind.fixed, 5000)], ['2.5', '5,000']);
      final on = TopupFeeConfig.fromBody({'success': true, 'enabled': true, 'last': {'kind': 'fixed', 'value': 750}, 'max_percent': 100});
      expect([on.enabled, on.lastKind, on.lastValue], [true, TopupFeeKind.fixed, 750]);
      final noLast = TopupFeeConfig.fromBody({'success': true, 'enabled': true, 'last': null});
      expect([noLast.enabled, noLast.lastKind], [true, null]);
      expect(TopupFeeConfig.fromBody({'success': false, 'enabled': true}).enabled, isFalse, reason: 'ردٌّ فاشل ⇒ مطفأة');
      expect(TopupFeeConfig.fromBody({'success': true, 'enabled': true, 'last': {'kind': 'bonus', 'value': 2}}).lastKind, isNull);
      final out = TopupFeeOutcome.fromJson({'amount': 2000, 'debt_id': 9, 'recorded': true, 'label': 'فائدة 2% (2,000 د.ع)'})!;
      expect([out.amount, out.recorded, out.label, out.cash], [2000, true, 'فائدة 2% (2,000 د.ع)', false]);
      // ٢١ نوفمبر: الخادم يقبلها مع النقديّ (collects) — خادمٌ أقدم بلا collects ⇒ الآجل وحده
      expect(TopupFeeConfig.fromBody({'success': true, 'enabled': true, 'collects': ['debt', 'cash']}).cash, isTrue);
      expect(TopupFeeConfig.fromBody({'success': true, 'enabled': true, 'collects': ['debt']}).cash, isFalse);
      expect(on.cash, isFalse);
      expect(TopupFeeOutcome.fromJson({'amount': 700, 'recorded': true, 'collect': 'cash'})!.cash, isTrue);
      expect(TopupFeeOutcome.fromJson(null), isNull);
      expect(TopupFeeOutcome.fromJson({'recorded': true}), isNull);
    });
  });

  // ═══════════════════════════ النافذتان ═══════════════════════════
  setUpAll(simSetUpAll);
  tearDown(PermissionsService.debugReset);

  /// نصوصٌ مقصوصة («…» أو أسطرٌ أكثر من حدّها) داخل [of].
  List<String> clipped(Finder of) => [
        for (final e in find.descendant(of: of, matching: find.byType(RichText)).evaluate())
          if ((e.renderObject! as RenderParagraph).didExceedMaxLines) (e.renderObject! as RenderParagraph).text.toPlainText(),
      ];

  group('شحن مدير الساس', () {
    const m = Manager(id: 41, username: 'mgr.north', mobile: '07700000001', balance: 10000);

    Future<SimServer> server({Map<String, Object?>? config, Map<String, Object?>? deposit, String template = ''}) async {
      final s = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@popq'});
      WhatsAppApi.clearCaches();
      PermissionsService.debugSet(isEmployee: false);
      s.reply('GET', '/api/v2/manager-topup-fees/config', 200, config ?? {'success': true, 'enabled': true, 'last': {'kind': 'percent', 'value': 2}, 'max_percent': 100});
      s.reply('POST', '/api/v2/managers/41/deposit', 200, deposit ?? {'success': true});
      s.reply('GET', '/api/admin/manager-debts/summary', 200, {
        'success': true,
        'perDebtor': [
          {'debtor_admin_id': 41, 'total_remaining': 2000, 'total_amount': 2000, 'debts_count': 1},
        ],
      });
      s.reply('GET', '/api/whatsapp/templates/2', 200, {
        'success': true,
        'templates': [
          if (template.isNotEmpty) {'template_type': 'manager_agent', 'is_active': 1, 'message_content': template},
        ],
      });
      s.reply('POST', '/api/whatsapp/send-message', 200, {'success': true});
      s.reply('POST', '/api/fcm/send-manager-balance-update', 200, {'success': true});
      return s;
    }

    Future<void> open(WidgetTester t, {SimVariant v = const SimVariant(390, dark: false)}) async {
      await pumpSim(t, v, home: (ctx) => simLauncher((c) => showBalanceOpSheet(c, m, preselected: BalanceOpKind.deposit)));
      await simOpen(t);
    }

    Future<void> loan(WidgetTester t) async {
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
    }

    Future<void> amount(WidgetTester t, String v) async {
      await t.enterText(find.byType(TextField).first, v);
      await t.pumpAndSettle();
    }

    Future<void> submit(WidgetTester t) async {
      await t.ensureVisible(find.byType(SheetFooterBar));
      await t.tap(find.byType(SheetFooterBar));
      await t.pumpAndSettle();
    }

    final fee = find.byKey(const ValueKey('topup-fee'));
    Finder inFee(String s) => find.descendant(of: fee, matching: find.text(s));

    testWidgets('الحقل مع «آجل» وحده، مقترحه آخر فائدة (2%)، والملخّص سطراً سطراً — والجسم يحمل ما رآه الوكيل', (t) async {
      final s = await server(deposit: {
        'success': true,
        'fee': {'amount': 2000, 'debt_id': 5, 'recorded': true, 'label': 'فائدة 2% (2,000 د.ع)'},
      });
      await open(t);
      expect(s.calls('GET', '/api/v2/manager-topup-fees/config').single.queryParameters, {'provider': 'sas4', 'manager': '41'});
      expect(fee, findsNothing, reason: 'الشحن النقديّ بلا فائدة');
      await loan(t);
      expect(fee, findsOneWidget);
      expect(find.descendant(of: fee, matching: find.byType(TextField)), findsOneWidget);
      expect(t.widget<TextField>(find.byKey(const ValueKey('topup-fee-value'))).controller!.text, '2', reason: 'آخر فائدة لهذا المدير');
      await amount(t, '100000');
      expect(inFee('100,000 د.ع'), findsOneWidget);
      expect(inFee('2,000 د.ع'), findsOneWidget);
      expect(inFee('102,000 د.ع'), findsOneWidget);
      expect(inFee('المجموع على المدير'), findsOneWidget);
      await submit(t);
      final body = s.bodies('POST', '/api/v2/managers/41/deposit').single;
      expect(body['isLoan'], isTrue);
      expect(body['amount'], 100000);
      expect(body['fee'], {'kind': 'percent', 'value': 2, 'amount': 2000});
      expect(find.textContaining('تمت العملية — فائدة 2% (2,000 د.ع)'), findsOneWidget);
      await simDrain(t);
      // الإشعار: الفائدة مع الملاحظة (الخادم يبني نصّه منها)، والرسالة الافتراضيّة بسطرها
      final push = s.bodies('POST', '/api/fcm/send-manager-balance-update').single;
      expect(push['notes'], 'فائدة 2% (2,000 د.ع)');
      final wa = s.bodies('POST', '/api/whatsapp/send-message').single['message'] as String;
      expect(wa, contains('➕ فائدة 2% (2,000 د.ع) — تُضاف على دينك'));
    });

    testWidgets('النقديّ بفائدة (٢١ نوفمبر — خادمٌ يقبلها): الحقل بلا «آجل» بعنوانه، «المجموع اللي تستلمه نقداً»، والجسم والرسالة', (t) async {
      final s = await server(
        config: {'success': true, 'enabled': true, 'last': {'kind': 'percent', 'value': 2}, 'max_percent': 100, 'collects': ['debt', 'cash']},
        deposit: {
          'success': true,
          'fee': {'amount': 2000, 'debt_id': null, 'recorded': true, 'label': 'فائدة 2% (2,000 د.ع)', 'collect': 'cash'},
        },
      );
      await open(t);
      expect(fee, findsOneWidget, reason: 'نقديٌّ والخادم يقبلها');
      expect(inFee('الفائدة على الشحن النقدي'), findsOneWidget);
      await amount(t, '100000');
      expect(inFee('المجموع اللي تستلمه نقداً'), findsOneWidget);
      expect(inFee('102,000 د.ع'), findsOneWidget);
      expect(find.descendant(of: fee, matching: find.textContaining('تستلمها نقداً مع الشحن')), findsOneWidget);
      // «آجل» ⇒ العنوان والمجموع يتبعان الطريقة، ثمّ رجوعٌ للنقديّ
      await loan(t);
      expect(inFee('الفائدة على الآجل'), findsOneWidget);
      expect(inFee('المجموع على المدير'), findsOneWidget);
      await loan(t);
      await submit(t);
      final body = s.bodies('POST', '/api/v2/managers/41/deposit').single;
      expect([body['isLoan'], body['fee']], [false, {'kind': 'percent', 'value': 2, 'amount': 2000}]);
      expect(find.textContaining('تمت العملية — فائدة 2% (2,000 د.ع)'), findsOneWidget);
      await simDrain(t);
      final wa = s.bodies('POST', '/api/whatsapp/send-message').single['message'] as String;
      expect(wa, contains('➕ فائدة 2% (2,000 د.ع) — مدفوعة نقداً مع الشحن'));
      expect(wa, isNot(contains('تُضاف على دينك')));
      expect(s.bodies('POST', '/api/fcm/send-manager-balance-update').single['notes'], 'فائدة 2% (2,000 د.ع)');
    });

    testWidgets('النقديّ بعد الآجل: لا فائدة في الجسم — و«بدون» كذلك', (t) async {
      final s = await server();
      await open(t);
      await loan(t);
      await loan(t); // رجع نقديّاً
      expect(fee, findsNothing);
      await amount(t, '50000');
      await submit(t);
      expect(s.bodies('POST', '/api/v2/managers/41/deposit').single.containsKey('fee'), isFalse);
      await simDrain(t);

      final s2 = await server();
      await open(t);
      await loan(t);
      await t.tap(inFee('بدون'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('topup-fee-value')), findsNothing);
      await amount(t, '50000');
      await submit(t);
      final b = s2.bodies('POST', '/api/v2/managers/41/deposit').single;
      expect([b['isLoan'], b.containsKey('fee')], [true, false]);
      await simDrain(t);
    });

    testWidgets('الخادم لم يفتحها للصفحة (أو تعذّر السؤال): لا حقل مع الآجل', (t) async {
      final s = await server(config: {'success': true, 'enabled': false, 'last': null});
      await open(t);
      await loan(t);
      expect(fee, findsNothing);
      await amount(t, '50000');
      await submit(t);
      expect(s.bodies('POST', '/api/v2/managers/41/deposit').single.containsKey('fee'), isFalse);
      await simDrain(t);

      final s2 = await server(config: {'success': false, 'message': 'تعذّر'});
      await open(t);
      await loan(t);
      expect(fee, findsNothing);
      expect(s2.calls('GET', '/api/v2/manager-topup-fees/config').length, 1);
      await simDrain(t);
    });

    testWidgets('خطأ الفائدة يُقال تحتها ويُعطّل الزرّ — ولا يُرسل شيء', (t) async {
      final s = await server(config: {'success': true, 'enabled': true, 'last': null});
      await open(t);
      await loan(t);
      await t.tap(inFee('مبلغ'));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('topup-fee-value')), '30,000');
      await amount(t, '25000');
      expect(find.byKey(const ValueKey('topup-fee-problem')), findsOneWidget);
      expect(inFee('الفائدة أكبر من مبلغ الشحن'), findsOneWidget);
      expect(t.widget<SheetFooterBar>(find.byType(SheetFooterBar)).enabled, isFalse);
      await submit(t);
      expect(s.calls('POST', '/api/v2/managers/41/deposit'), isEmpty);
      await t.enterText(find.byKey(const ValueKey('topup-fee-value')), '٥٠٠');
      await t.pumpAndSettle();
      expect(inFee('25,500 د.ع'), findsOneWidget);
      expect(t.widget<SheetFooterBar>(find.byType(SheetFooterBar)).enabled, isTrue);
      await simDrain(t);
    });

    testWidgets('تمّ الشحن ولم يُسجَّل دين الفائدة: تحذير الخادم صريحاً، ولا «فائدة» في رسالة النجاح ولا الإشعار', (t) async {
      final s = await server(deposit: {
        'success': true,
        'fee': {'amount': 2000, 'debt_id': null, 'recorded': false, 'label': 'فائدة 2% (2,000 د.ع)'},
        'warning': 'تمّ الشحن ولم تُسجَّل الفائدة — أضفها من «ديون أخرى»',
      });
      await open(t);
      await loan(t);
      await amount(t, '100000');
      await submit(t);
      expect(find.text('تمّ الشحن ولم تُسجَّل الفائدة — أضفها من «ديون أخرى»'), findsOneWidget);
      expect(find.textContaining('تمت العملية — فائدة'), findsNothing);
      await simDrain(t);
      expect(s.bodies('POST', '/api/fcm/send-manager-balance-update').single['notes'], '');
    });

    testWidgets('قالب المدير: {fee} بالفائدة، وسطره يُحذف كلّه بلا فائدة', (t) async {
      const tpl = 'شحن {amount}\nالفائدة: {fee}\nدينك {total_debts}';
      final s = await server(
        template: tpl,
        deposit: {
          'success': true,
          'fee': {'amount': 2000, 'debt_id': 5, 'recorded': true, 'label': 'فائدة 2% (2,000 د.ع)'},
        },
      );
      await open(t);
      await loan(t);
      await amount(t, '100000');
      await submit(t);
      await simDrain(t);
      expect(s.bodies('POST', '/api/whatsapp/send-message').single['message'], 'شحن 100,000\nالفائدة: فائدة 2% (2,000 د.ع)\nدينك 102,000');

      final s2 = await server(template: tpl, config: {'success': true, 'enabled': false});
      await open(t);
      await loan(t);
      await amount(t, '100000');
      await submit(t);
      await simDrain(t);
      expect(s2.bodies('POST', '/api/whatsapp/send-message').single['message'], 'شحن 100,000\nدينك 102,000');
    });

    testWidgets('بأضيق هاتف وخطٍّ ×1.2 (فاتح وداكن): الحقل كاملٌ بلا فيضٍ ولا نصٍّ مقصوص', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      for (final v in const [SimVariant(320, dark: false), SimVariant(320, dark: true), SimVariant(390, dark: false)]) {
        await server();
        await open(t, v: v);
        await loan(t);
        await amount(t, '1250000');
        await t.ensureVisible(fee);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '@${v.tag}');
        expect(inFee('1,275,000 د.ع'), findsOneWidget);
        expect(clipped(fee), isEmpty, reason: 'نصٌّ مقصوص @${v.tag}');
        await t.tap(inFee('مبلغ'));
        await t.pumpAndSettle();
        expect(clipped(fee), isEmpty, reason: 'نصٌّ مقصوص (مبلغ) @${v.tag}');
        await simDrain(t);
        await t.pumpWidget(const SizedBox.shrink()); // الورقة لا تبقى مفتوحةً للمقاس التالي
        await t.pump();
        // النقديّ (عنوانه ومجموعه أطول): «الفائدة على الشحن النقدي» و«المجموع اللي تستلمه نقداً»
        await server(config: {'success': true, 'enabled': true, 'last': {'kind': 'percent', 'value': 2}, 'collects': ['debt', 'cash']});
        await open(t, v: v);
        await amount(t, '1250000');
        await t.ensureVisible(fee);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'نقديّ @${v.tag}');
        expect(inFee('المجموع اللي تستلمه نقداً'), findsOneWidget);
        expect(clipped(fee), isEmpty, reason: 'نصٌّ مقصوص (نقديّ) @${v.tag}');
        await simDrain(t);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
      }
    });
  });

  group('«المدراء» لايرث لنك', () {
    const row = ElManagerRow(index: 153, name: 'najaf40', otherDebt: 10000, hasApp: true);

    Future<SimServer> server({Map<String, Object?>? config, Map<String, Object?>? topup}) async {
      final s = await simSetUp(secure: {'auth.admin_id': 'earthlink:153357', 'auth.admin_username': 'admin@el'});
      // الموظّف يشحن بكلمة الإيداع المحفوظة (الخادم) — لا حقل كلمةٍ في النافذة
      PermissionsService.debugSet(isEmployee: true);
      s.reply('GET', '/api/v2/manager-topup-fees/config', 200, config ?? {'success': true, 'enabled': true, 'last': {'kind': 'fixed', 'value': 700}});
      s.reply('POST', '/api/v2/el/managers/153/topup', 200, topup ?? {'success': true, 'message': 'تمّ شحن 50,000 د.ع لـ«najaf40»'});
      return s;
    }

    ElTopupResult? result;
    Future<void> open(WidgetTester t, {SimVariant v = const SimVariant(390, dark: false)}) async {
      result = null;
      await pumpSim(t, v, home: (ctx) => simLauncher((c) async => result = await showElTopupSheet(c, manager: row, balance: 1000000)));
      await simOpen(t);
    }

    Future<void> debt(WidgetTester t) async {
      await t.tap(find.text('شحن آجل'));
      await t.pumpAndSettle();
    }

    final fee = find.byKey(const ValueKey('topup-fee'));
    Finder inFee(String s) => find.descendant(of: fee, matching: find.text(s));

    testWidgets('آجلٌ بفائدةٍ ثابتة (المقترح 700): التأكيد يقول المجموع، «ديون أخرى عليه بعدها» بالفائدة، والجسم والنتيجة', (t) async {
      final s = await server(topup: {
        'success': true,
        'message': 'تمّ شحن 50,000 د.ع لـ«najaf40»',
        'fee': {'amount': 700, 'debt_id': 8, 'recorded': true, 'label': 'فائدة 700 د.ع'},
      });
      await open(t);
      expect(s.calls('GET', '/api/v2/manager-topup-fees/config').single.queryParameters, {'provider': 'earthlink', 'manager': '153'});
      expect(fee, findsNothing, reason: 'النقديّ بلا فائدة');
      await debt(t);
      expect(fee, findsOneWidget);
      await t.enterText(find.byType(TextField).first, '50000');
      await t.pumpAndSettle();
      expect(inFee('50,700 د.ع'), findsOneWidget);
      // الملخّص أسفل القائمة (تُبنى عند الحاجة) — نمرّر إليه
      await t.dragUntilVisible(find.text('60,700 د.ع'), find.byType(ListView).last, const Offset(0, -200));
      expect(find.text('60,700 د.ع'), findsOneWidget, reason: 'ديون أخرى عليه بعدها = 10,000 + 50,000 + 700');
      await t.ensureVisible(find.byType(SheetFooterBar));
      await t.tap(find.byType(SheetFooterBar));
      await t.pumpAndSettle();
      expect(find.textContaining('+ فائدة 700 د.ع في «ديون أخرى» — المجموع 50,700 د.ع.'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'شحن'));
      await t.pumpAndSettle();
      final body = s.bodies('POST', '/api/v2/el/managers/153/topup').single;
      expect([body['as_debt'], body['amount'], body['fee']], [true, 50000, {'kind': 'fixed', 'value': 700, 'amount': 700}]);
      expect(result?.ok, isTrue);
      expect(result?.feeLine, 'مع فائدة 700 د.ع في «ديون أخرى»');
      await simDrain(t);
    });

    testWidgets('نقديٌّ بفائدة (خادمٌ يقبلها): الحقل مع «شحن نقدي»، التأكيد «استلمتَ منه الآن 50,700»، والجسم والنتيجة', (t) async {
      final s = await server(
        config: {'success': true, 'enabled': true, 'last': {'kind': 'fixed', 'value': 700}, 'collects': ['debt', 'cash']},
        topup: {
          'success': true,
          'message': 'تمّ شحن 50,000 د.ع لـ«najaf40»',
          'fee': {'amount': 700, 'debt_id': null, 'recorded': true, 'label': 'فائدة 700 د.ع', 'collect': 'cash'},
        },
      );
      await open(t);
      expect(fee, findsOneWidget, reason: 'نقديٌّ افتراضاً والخادم يقبلها');
      expect(inFee('الفائدة على الشحن النقدي'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, '50000');
      await t.pumpAndSettle();
      expect(inFee('المجموع اللي تستلمه نقداً'), findsOneWidget);
      expect(inFee('50,700 د.ع'), findsOneWidget);
      await t.ensureVisible(find.byType(SheetFooterBar));
      await t.tap(find.byType(SheetFooterBar));
      await t.pumpAndSettle();
      expect(find.textContaining('نقداً: استلمتَ منه الآن 50,700 د.ع — الشحن 50,000 د.ع + فائدة 700 د.ع.'), findsOneWidget, reason: 'نصّ الموقع نفسه');
      await t.tap(find.widgetWithText(FilledButton, 'شحن'));
      await t.pumpAndSettle();
      final body = s.bodies('POST', '/api/v2/el/managers/153/topup').single;
      expect([body['as_debt'], body['fee']], [false, {'kind': 'fixed', 'value': 700, 'amount': 700}]);
      expect(result?.feeLine, 'مع فائدة 700 د.ع نقداً');
      await simDrain(t);
    });

    testWidgets('نقداً بعد الآجل: لا فائدة في الجسم ولا في التأكيد', (t) async {
      final s = await server();
      await open(t);
      await debt(t);
      await t.tap(find.text('شحن نقدي'));
      await t.pumpAndSettle();
      expect(fee, findsNothing);
      await t.enterText(find.byType(TextField).first, '50000');
      await t.pumpAndSettle();
      await t.ensureVisible(find.byType(SheetFooterBar));
      await t.tap(find.byType(SheetFooterBar));
      await t.pumpAndSettle();
      expect(find.textContaining('فائدة'), findsNothing);
      await t.tap(find.widgetWithText(FilledButton, 'شحن'));
      await t.pumpAndSettle();
      expect(s.bodies('POST', '/api/v2/el/managers/153/topup').single.containsKey('fee'), isFalse);
      await simDrain(t);
    });

    testWidgets('«غير مؤكَّد» ثمّ «تحقّق»: الفائدة مقفلةٌ وتُعاد كما هي بالمفتاح نفسه', (t) async {
      final s = await server(topup: {'success': false, 'code': 'OUTCOME_UNKNOWN', 'message': 'لم يتأكّد الشحن من ايرث لنك'});
      await open(t);
      await debt(t);
      await t.enterText(find.byType(TextField).first, '50000');
      await t.pumpAndSettle();
      await t.ensureVisible(find.byType(SheetFooterBar));
      await t.tap(find.byType(SheetFooterBar));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'شحن'));
      await t.pumpAndSettle();
      expect(t.widget<TextField>(find.byKey(const ValueKey('topup-fee-value'))).enabled, isFalse, reason: 'مقفلة');
      s.reply('POST', '/api/v2/el/managers/153/topup', 200, {
        'success': true,
        'message': 'تمّ شحن 50,000 د.ع لـ«najaf40» (ظهر بكشف الحساب)',
        'fee': {'amount': 700, 'debt_id': 8, 'recorded': true, 'label': 'فائدة 700 د.ع'},
      });
      await t.ensureVisible(find.byType(SheetFooterBar));
      await t.tap(find.byType(SheetFooterBar));
      await t.pumpAndSettle();
      final bodies = s.bodies('POST', '/api/v2/el/managers/153/topup');
      expect(bodies.length, 2);
      expect(bodies[1]['idempotencyKey'], bodies[0]['idempotencyKey']);
      expect(bodies[1]['fee'], bodies[0]['fee']);
      expect(result?.feeLine, 'مع فائدة 700 د.ع في «ديون أخرى»');
      await simDrain(t);
    });

    testWidgets('بأضيق هاتف وخطٍّ ×1.2: الحقل كاملٌ بلا فيضٍ ولا نصٍّ مقصوص', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      for (final v in const [SimVariant(320, dark: false), SimVariant(320, dark: true)]) {
        await server(config: {'success': true, 'enabled': true, 'last': {'kind': 'percent', 'value': 2.5}});
        await open(t, v: v);
        await debt(t);
        await t.enterText(find.byType(TextField).first, '1250000');
        await t.pumpAndSettle();
        await t.ensureVisible(fee);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: '@${v.tag}');
        expect(inFee('1,281,250 د.ع'), findsOneWidget);
        expect(clipped(fee), isEmpty, reason: 'نصٌّ مقصوص @${v.tag}');
        await simDrain(t);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
      }
    });
  });
}
