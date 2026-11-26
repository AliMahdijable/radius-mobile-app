import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/reports/balance_reports_screen.dart';
import 'package:rad_mysvcs/screens/reports/reports_hub_screen.dart';
import 'package:rad_mysvcs/services/balance_sub_names.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'balance_reports/balance_fixture.dart';
import 'balance_reports/contract_server.dart';
import 'visual_perm/visual_perm_harness.dart';

/// «تقارير الأرصدة» — لقطاتٌ للمراجعة (١٦ نوفمبر): الصفحة بمثال المالك، ورقة التسوية، بعد التسوية، ثلاث فترات، تفاصيل فترةٍ مغلقة
/// وفلتر «كان دين وتسدّد»، أوّل شحنة، وكرت التقارير — بعرض شاشة المالك (٤٨٠) فاتحاً، وأضيق هاتف (٣٢٠) داكناً.
/// كلّ لقطةٍ بطول محتواها ([_fit]) وبظلالها الحقيقيّة. بياناتٌ تجريبيّة وحدها.
/// ١٦ نوفمبر: لقطات المدراء الفرعيّين داخل الحساب من **ردّ الخادم الحقيقيّ** (server_contract_managers.json) بأوقاتٍ مزاحة.
/// ١٦ نوفمبر مساءً: «الفترة التالية تُفتح عند الإغلاق» — 20 تأكيد الإغلاق · 21 الفترة بلا مبلغ · 22 ورقة المبلغ · 23 تفاصيلها · 24 المغلقة المقفلة.
/// ٢٠ نوفمبر: 25 الموظّف بمفتاح «العرض» وحده (سطر «للعرض» بلا أزرار كتابة) · 26 الاسم العربيّ بجانب اليوزر في حركات الفترة.
/// المخرجات: VISUAL_OUT (أو build/visual_perm المُتجاهَل بgit).
const _wide = VisualDevice('480', Size(480, 1040), 3);
const _narrowDark = VisualDevice('320_dark', Size(320, 693), 3, dark: true);

Future<void> _shot(WidgetTester t, String name, VisualDevice d) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
  final png = await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: d.dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  final f = File('${visualOutDir()}/balance_${name}_${d.tag}.png');
  f.parent.createSync(recursive: true);
  f.writeAsBytesSync(png!, flush: true);
  final ex = t.takeException();
  expect(ex, isNull, reason: 'استثناء في $name ${d.tag}:\n$ex');
}

/// طول الشاشة = طول محتوى الصفحة المفتوحة (ولا أقصر من الهاتف): نطوّلها أوّلاً فتُبنى كلّ عناصر القائمة ويصير امتدادها
/// دقيقاً لا تقديراً، ثمّ نقصّها عليه — صورةٌ واحدة بكلّ الصفحة بلا فراغٍ تحتها. لا يُستعمل وورقةٌ مفتوحة.
Future<void> _fit(WidgetTester t, VisualDevice d) async {
  Future<void> resize(double h) async {
    t.view.physicalSize = Size(d.size.width, h) * d.dpr;
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
  }

  final lists = find.byType(Viewport);
  if (lists.evaluate().isEmpty) return resize(d.size.height);
  await resize(6000);
  final viewport = t.renderObject<RenderViewport>(lists.last);
  var content = 0.0;
  for (var s = viewport.firstChild; s != null; s = viewport.childAfter(s)) {
    content += s.geometry?.scrollExtent ?? 0;
  }
  // ما فوق القائمة (الترويسة) وما تحتها (حافّة الشاشة الآمنة) يُضافان لطولها
  final top = viewport.localToGlobal(Offset.zero).dy;
  final below = 6000 - (top + viewport.size.height);
  await resize(math.max(d.size.height, (top + content + below).ceilToDouble()));
}

void main() {
  setUpAll(visualSetUpAll);

  Future<void> up(HttpClientAdapter server) async {
    await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = server;
    PermissionsService.debugSet(isEmployee: false);
  }

  Future<void> down(WidgetTester t) async {
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump(const Duration(seconds: 4));
    await visualTearDown();
  }

  Finder k(String key) => find.byKey(ValueKey(key));
  Future<void> tap(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pump();
    await t.tap(f);
    await settle(t, seconds: 2);
  }

  /// الجسم بظلاله الحقيقيّة (الاختبار يرسمها حلقةً سوداء)، وتُعاد قبل فحص ثوابت الإطار.
  void shots(String name, Future<void> Function(WidgetTester t) body) {
    testWidgets(name, (t) async {
      debugDisableShadows = false;
      try {
        await body(t);
        await down(t);
      } finally {
        debugDisableShadows = true;
      }
    });
  }

  for (final d in [_wide, _narrowDark]) {
    shots('الموظّف للعرض والاسم العربيّ بجانب اليوزر ${d.tag}', (t) async {
      Subscriber sub(String u, String first, String last) => Subscriber.fromJson({'username': u, 'firstname': first, 'lastname': last});
      BalanceSubNames.probe = () async => 0;
      BalanceSubNames.loadAll = () async => [
            sub('user0@net', 'علي', 'حسين'),
            sub('user1@net', 'user1@net', ''),
            sub('user2@net', 'محمد جاسم', ''),
            sub('user3@net', 'عبد الرحمن عبد الكريم عبد الأمير', 'الحسيني الموسوي البغدادي'),
            sub('user4@net', 'Ahmed', 'Kareem'),
            sub('user5@net', 'زينب', 'كاظم'),
            sub('user6@net', 'حيدر', 'عباس'),
            sub('user8@net', 'سجاد', 'فلاح'),
            sub('user9@net', 'مصطفى', 'رعد'),
          ];
      try {
        await up(BalanceServer.ownerExample()
          ..employee = true
          ..empView = true);
        PermissionsService.debugSet(isEmployee: true, permissions: const {'balance_reports.view': true, 'subscribers.view': true});
        await pumpVisual(t, d, home: (_) => const BalanceReportsScreen());
        await settle(t, seconds: 2);
        await _fit(t, d);
        await _shot(t, '25_employee_view', d);
        await tap(t, k('bal-detail-1'));
        await _fit(t, d);
        await _shot(t, '26_names', d);
      } finally {
        BalanceSubNames.debugReset();
      }
    });

    shots('مثال المالك ثمّ التسوية ${d.tag}', (t) async {
      await up(BalanceServer.ownerExample()..balance = 3000);
      await pumpVisual(t, d, home: (_) => const BalanceReportsScreen());
      await settle(t, seconds: 2);
      await _fit(t, d);
      await _shot(t, '01_example', d);
      await tap(t, k('bal-adjust-1'));
      await _shot(t, '02_adjust_sheet', d);
      await t.tap(find.descendant(of: k('bal-adjust-source'), matching: find.text('من مالي الخاصّ')));
      await t.pump();
      await t.tap(k('bal-adjust-save'));
      await settle(t, seconds: 5);
      await _fit(t, d);
      await _shot(t, '03_after_adjust_can_close', d);
    });

    shots('ثلاث فترات وتفاصيل المغلقة ${d.tag}', (t) async {
      final server = BalanceServer.three()
        ..balance = 420000
        ..totals = {'old_paid': 1365000, 'manual_paid': 40000, 'other_paid': 0, 'advance': 0};
      await up(server);
      await pumpVisual(t, d, home: (_) => const BalanceReportsScreen());
      await settle(t, seconds: 2);
      await _fit(t, d);
      await _shot(t, '04_three_periods', d);
      await tap(t, find.descendant(of: k('bal-period-3'), matching: find.byType(InkWell)).first);
      await _fit(t, d);
      await _shot(t, '05_detail_closed', d);
      await tap(t, k('bal-filter-paid'));
      await _fit(t, d);
      await _shot(t, '06_detail_was_debt_paid', d);
    });
  }

  /// عقد الخادم ومفتاح المدراء مفتوح، وكلّ أوقاته مزاحةٌ أيّاماً للوراء حتى لا تقع في المستقبل يوم التصوير.
  Map<String, dynamic> managersContract({int daysBack = 70}) {
    Object? shift(Object? v, [String key = '']) => switch (v) {
          final Map m => {for (final e in m.entries) '${e.key}': shift(e.value, '${e.key}')},
          final List l => [for (final x in l) shift(x)],
          final int n when key.endsWith('_ms') => n - daysBack * 86400000,
          _ => v,
        };
    return shift(jsonDecode(File('test/balance_reports/server_contract_managers.json').readAsStringSync()))! as Map<String, dynamic>;
  }

  for (final d in [_wide, _narrowDark]) {
    shots('المدراء الفرعيّون داخل الحساب ${d.tag}', (t) async {
      await up(BalanceContractServer(managersContract()));
      await pumpVisual(t, d, home: (_) => const BalanceReportsScreen());
      await settle(t, seconds: 2);
      await _fit(t, d);
      await _shot(t, '10_managers_page', d);
      await tap(t, find.descendant(of: k('bal-period-1'), matching: find.byType(InkWell)).first);
      await _fit(t, d);
      await _shot(t, '11_managers_detail', d);
      await tap(t, k('bal-filter-managers'));
      await _fit(t, d);
      await _shot(t, '12_managers_filter', d);
    });
  }

  // «بالحوالات — لم تُسحب» (٢٦ نوفمبر) من ردّ الخادم الحقيقيّ (server_contract_tw.json — أوقاته ٢٣–٢٥ نوفمبر، ماضيةٌ أصلاً):
  // الصفحة بسطرها تحت «المحصَّل» وفي تفصيله، ثمّ تفاصيل الفترة بخلاصتها لكلّ طريقة وحركاتها بحالها.
  for (final d in [_wide, _narrowDark]) {
    shots('الحوالات — لم تُسحب ${d.tag}', (t) async {
      final base = jsonDecode(File('test/balance_reports/server_contract.json').readAsStringSync()) as Map<String, dynamic>;
      final tw = jsonDecode(File('test/balance_reports/server_contract_tw.json').readAsStringSync()) as Map<String, dynamic>;
      await up(BalanceContractServer({...base, 'overview': tw['overview'], 'details': tw['details']}));
      await pumpVisual(t, d, home: (_) => const BalanceReportsScreen());
      await settle(t, seconds: 2);
      await _fit(t, d);
      await _shot(t, '30_tw_page', d);
      await tap(t, find.descendant(of: k('bal-period-1'), matching: find.byType(InkWell)).first);
      await _fit(t, d);
      await _shot(t, '31_tw_detail', d);
    });
  }

  // «الفترة التالية تُفتح عند الإغلاق» (١٦ نوفمبر مساءً): تأكيد الإغلاق بجملته، الفترة بلا مبلغ بتنبيهها، ورقة «كتابة مبلغ الشحن»،
  // تفاصيلها، وتفاصيل المغلقة بسطر قفلها.
  for (final d in [_wide, _narrowDark]) {
    shots('الفترة التالية — تأكيد الإغلاق ${d.tag}', (t) async {
      final server = BalanceServer.ownerExample()..autoNext = true;
      server.periods.first['amount'] = 1750000;
      await up(server);
      await pumpVisual(t, d, home: (_) => const BalanceReportsScreen());
      await settle(t, seconds: 2);
      await tap(t, k('bal-close-1'));
      await _shot(t, '20_next_close_confirm', d);
    });

    shots('الفترة التالية — بلا مبلغ ومبلغها وتفاصيلها والقفل ${d.tag}', (t) async {
      await up(BalanceServer.closedWithPending()..balance = 640000);
      await pumpVisual(t, d, home: (_) => const BalanceReportsScreen());
      await settle(t, seconds: 2);
      await _fit(t, d);
      await _shot(t, '21_next_pending_page', d);
      await tap(t, k('bal-amount-btn'));
      await t.enterText(find.descendant(of: k('bal-topup-amount'), matching: find.byType(TextField)), '2000000');
      await settle(t, seconds: 1);
      await _shot(t, '22_next_amount_sheet', d);
      await t.tapAt(const Offset(8, 8));
      await settle(t, seconds: 2);
      await tap(t, k('bal-detail-2'));
      await _fit(t, d);
      await _shot(t, '23_next_pending_detail', d);
      Navigator.of(t.element(find.byKey(const ValueKey('bal-detail-list')))).pop();
      await settle(t, seconds: 2);
      await tap(t, find.descendant(of: k('bal-period-1'), matching: find.byType(InkWell)).first);
      await _fit(t, d);
      await _shot(t, '24_next_locked_detail', d);
    });
  }

  shots('أوّل شحنة ${_wide.tag}', (t) async {
    const d = VisualDevice('480', Size(480, 940), 3);
    await up(BalanceServer());
    await pumpVisual(t, d, home: (_) => const BalanceReportsScreen());
    await settle(t, seconds: 2);
    await _shot(t, '07_empty', d);
    await tap(t, k('bal-first'));
    await t.enterText(find.descendant(of: k('bal-topup-amount'), matching: find.byType(TextField)), '2000000');
    await settle(t, seconds: 1);
    await _shot(t, '08_new_topup', d);
  });

  shots('كرت التقارير ${_wide.tag}', (t) async {
    await up(BalanceServer.ownerExample());
    await pumpVisual(t, _wide, home: (_) => const ReportsHubScreen());
    await settle(t, seconds: 2);
    await _fit(t, _wide);
    await _shot(t, '09_reports_tile', _wide);
  });
}
