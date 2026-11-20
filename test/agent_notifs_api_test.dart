import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/agent_notifs_api.dart';
import 'package:rad_mysvcs/screens/my_alerts/money_alerts_section.dart';

/// «إشعاراتي — تنبيهات المال»: ردّ الخادم (server/agentNotifs.js view) كما يقرؤه التطبيق — القيم، «جارٍ»، والأسباب.
void main() {
  Map<String, Object?> reply({Map<String, Object?>? balance, Map<String, Object?>? cap, Map<String, Object?>? debtors}) => {
        'balance': {
          'enabled': true,
          'threshold': 250000,
          'repeat': {'mode': 'every_hours', 'hours': 6},
          'now': 184500,
          'days_left': 2,
          'reason': null,
          'pending': false,
          ...?balance,
        },
        'debt_cap': {
          'enabled': true,
          'cap': 5000000,
          'repeat': {'mode': 'daily', 'at': '09:00'},
          'now': 4150000,
          'percent': 83,
          'reason': null,
          'pending': false,
          ...?cap,
        },
        'debtors': {
          'enabled': true,
          'min_days': 30,
          'min_amount': null,
          'max_amount': null,
          'schedule': {'mode': 'every_days', 'days': 3, 'at': '10:00', 'anchor': '2026-11-20'},
          'matching': {'count': 14, 'total': 1265000},
          'reason': null,
          'pending': false,
          ...?debtors,
        },
        'recent': [
          {'kind': 'balance', 'title': 'رصيدك 184,500 د.ع — تحت حدّك 250,000', 'at': '2026-11-20T06:00:00.000Z', 'push': 'sent'},
        ],
        'currency': 'IQD',
        'dry_run': false,
      };

  test('الردّ الكامل: القيم والتكرار والموعد ونسبة الخادم', () {
    final n = AgentNotifs.fromJson(reply())!;
    expect(n.balance.threshold, 250000);
    expect(n.balance.repeat.mode, AlertRepeatMode.everyHours);
    expect(n.balance.now, 184500);
    expect(n.balance.daysLeft, 2);
    expect(n.debtCap.percent, 83);
    expect(n.debtors.schedule.mode, DigestMode.everyDays);
    expect(n.debtors.schedule.days, 3);
    expect(n.debtors.matchCount, 14);
    expect(n.recent.single.title, startsWith('رصيدك'));
    expect(n.anyPending, isFalse);
  });

  test('«جارٍ»: قراءةٌ لم تصل ⇒ لا رقم والشاشة تسأل ثانيةً', () {
    final n = AgentNotifs.fromJson(reply(balance: {'now': null, 'pending': true, 'reason': 'pending'}))!;
    expect(n.balance.now, isNull);
    expect(n.balance.pending, isTrue);
    expect(n.anyPending, isTrue);
    expect(balanceWhy(n.balance), 'جارٍ قراءة رصيدك…');
  });

  test('الأسباب بكلماتٍ يفهمها الوكيل — لا «تعذّر» واحدة لكلّ شيء', () {
    BalanceAlert b(String r) => AgentNotifs.fromJson(reply(balance: {'now': null, 'reason': r}))!.balance;
    expect(balanceWhy(b('no_wallet')), contains('ما تعطي رصيد صفحة'));
    expect(balanceWhy(b('no_session')), contains('ادخل شركتك من جديد'));
    expect(balanceWhy(b('unreadable')), 'تعذّرت قراءة رصيدك الآن');
    expect(debtsWhy(false, 'no_token'), contains('لا جلسة محفوظة'));
    expect(debtsWhy(false, 'no_age'), contains('بالمبلغ'));
    expect(debtsWhy(false, 'list'), 'تعذّر حساب ديون مشتركيك الآن');
    expect(debtsWhy(true, null), 'جارٍ حساب ديون مشتركيك…');
  });

  test('خادمٌ أقدم بلا percent ⇒ النسبة تُحسب بالتقريب للأسفل كإشعاره', () {
    final c = DebtCapAlert.fromJson({'enabled': true, 'cap': 3000000, 'now': 2999999});
    expect(c.percent, 99);
  });

  testWidgets('تشغيل «سقف الديون» بلا سقف ⇒ نافذة المبلغ أوّلاً ويُحفظان معاً؛ الإلغاء يبقيه مطفأً', (t) async {
    // شاشة هاتف (الافتراضيّ 800×600 يُخرج شريط «حفظ» عن الشاشة)
    t.view.physicalSize = const Size(1290, 2796);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final patches = <Map<String, Object?>>[];
    final data = AgentNotifs.fromJson(reply(cap: {'enabled': false, 'cap': null, 'now': 4150000, 'percent': null}))!;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MoneyAlertsSection(data: data, onPatch: (p) async { patches.add(p); return true; }),
        ),
      ),
    ));
    final toggle = find.descendant(of: find.byKey(const ValueKey('ma-debtcap')), matching: find.byType(Switch));
    await t.ensureVisible(toggle);
    await t.tap(toggle);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ma-amount-field')), findsOneWidget, reason: 'نافذة المبلغ');
    expect(patches, isEmpty, reason: 'لا حفظ قبل المبلغ');
    await t.enterText(find.byKey(const ValueKey('ma-amount-field')), '5000000');
    await t.pump();
    await t.tap(find.text('حفظ').last);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('ma-amount-field')), findsNothing, reason: 'أُغلقت النافذة');
    expect(patches, [
      {'debt_cap': {'enabled': true, 'cap': 5000000}}
    ]);
  });
}
