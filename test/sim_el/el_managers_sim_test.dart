import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/el_managers_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/screens/managers/el_managers_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// «المدراء» لموزّع ايرث لنك (٢٠ نوفمبر — `managers/el_managers_screen.dart` + `sheets/el_topup_sheet.dart`؛ الخادم
/// server/earthlink/elManagers.js). ما يُحرس (المال — مهارة money-change-review):
///   • الشحن بتأكيدٍ قبل الإرسال وجسمٍ صحيح (المبلغ، الآجل، الإشعار، مفتاح التكرار).
///   • «غير مؤكَّد» (409 OUTCOME_UNKNOWN، أو لا ردّ) ⇒ النافذة تبقى، والزرّ «تحقّق من الشحن» يعيد **المفتاح نفسه** بلا تأكيد —
///     لا شحنٌ ثانٍ بمفتاحٍ جديد.
///   • «المبلغ نفسه خلال ٥ دقائق» (RECENT_DUPLICATE) ⇒ سؤالٌ ثمّ confirmRepeat بالمفتاح نفسه.
///   • فشلٌ يقيناً ⇒ مفتاحٌ جديد للمحاولة التالية.
///   • الموظّف: «شحن رصيد» مقفلٌ بلا el_managers.topup، ولا حقل كلمة إيداعٍ له؛ والميزة المطفأة تقول ذلك (ولصاحب الحساب التحويل القديم).
const _list = '/api/v2/el/managers';
const _topup = '/api/v2/el/managers/1025/topup';

Map<String, dynamic> _listBody({bool enabled = true}) => enabled
    ? {
        'success': true,
        'enabled': true,
        'data': {
          'balance': 1250000,
          'min_topup': 5000,
          'deposit_saved': true,
          'managers': [
            {
              'index': 1025,
              'name': 'najaf40',
              'other_debt': 75000,
              'last_topup': {'amount': 50000, 'at': '2026-11-18T09:30:00Z', 'as_debt': true},
              'wa_phone': '07701234567',
              'wa_source': 'session',
              'has_app': true,
            },
            {
              'index': 2048,
              'name': 'kufa7',
              'other_debt': 0,
              'last_topup': null,
              'wa_phone': null,
              'wa_source': null,
              'has_app': false,
            },
          ],
        },
      }
    : {'success': true, 'enabled': false, 'data': {'balance': null, 'managers': []}};

void main() {
  late SimServer server;
  const v = SimVariant(390, dark: false);

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    PermissionsService.debugSet(isEmployee: false);
    server.reply('GET', _list, 200, _listBody());
    server.reply('GET', '/api/v2/el/deposit-password', 200, {
      'success': true,
      'data': {'saved': true, 'can_manage': true, 'updated_at': '2026-11-18T10:00:00Z'},
    });
  });

  Future<void> open(WidgetTester t, {SimVariant variant = v}) async {
    await pumpSim(t, variant, home: (_) => const ElManagersScreen());
  }

  Finder amountField() =>
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'مثلاً 50,000');

  Future<void> openSheetFor(WidgetTester t, String name) async {
    final card = find.ancestor(of: find.text(name), matching: find.byType(Container)).first;
    final btn = find.descendant(of: card, matching: find.text('شحن رصيد'));
    await t.ensureVisible(btn.first);
    await t.tap(btn.first);
    await t.pumpAndSettle();
  }

  Future<void> fillAndConfirm(WidgetTester t, {String amount = '25000', bool debt = false}) async {
    if (debt) {
      await t.tap(find.text('شحن آجل'));
      await t.pumpAndSettle();
    }
    await t.enterText(amountField(), amount);
    await t.pumpAndSettle();
    final footer = find.textContaining('شحن 25,000');
    await t.ensureVisible(footer.first);
    await t.tap(footer.first);
    await t.pumpAndSettle();
    expect(find.text('تأكيد الشحن'), findsOneWidget, reason: 'تأكيدٌ قبل الإرسال');
    await t.tap(find.text('شحن'));
    await t.pumpAndSettle();
  }

  testWidgets('القائمة: الحسابات التابعة ورصيد الإيداع وديون أخرى، والعمليّتان لكلّ مدير', (t) async {
    await open(t);
    expect(find.text('najaf40'), findsOneWidget);
    expect(find.text('kufa7'), findsOneWidget);
    expect(find.text('شحن رصيد'), findsNWidgets(2));
    expect(find.text('ديون أخرى'), findsWidgets);
    expect(find.text('أضف رقم واتساب'), findsOneWidget, reason: 'kufa7 بلا رقم');
    expect(find.byIcon(LucideIcons.lock), findsNothing, reason: 'صاحب الحساب لا قفل له');
    expect(server.unhandled, isEmpty);
  });

  testWidgets('شحنٌ نقديّ: تأكيدٌ ثمّ جسمٌ صحيح بمفتاح تكرار، والنافذة تُغلق بالرسالة وسطر الإشعار', (t) async {
    server.reply('POST', _topup, 200, {
      'success': true,
      'message': 'تمّ شحن 25,000 د.ع لـ«najaf40»',
      'balance_after': 1225000,
      'notice': {'app': true, 'app_message': null, 'whatsapp': false, 'whatsapp_message': 'الجلسة غير متّصلة'},
    });
    await open(t);
    await openSheetFor(t, 'najaf40');
    expect(find.text('كلمة مرور الإيداع'), findsOneWidget, reason: 'لصاحب الحساب');
    await fillAndConfirm(t);
    final bodies = server.bodies('POST', _topup);
    expect(bodies, hasLength(1));
    final b = bodies.single;
    expect(b['amount'], 25000);
    expect(b['as_debt'], false);
    expect(b['notify_app'], true);
    expect(b['notify_whatsapp'], true);
    expect('${b['idempotencyKey']}', startsWith('eltop-'));
    expect(b.containsKey('depositPassword'), isFalse, reason: 'المحفوظة يضيفها الخادم');
    expect(find.text('تأكيد الشحن'), findsNothing);
    expect(find.textContaining('وصله إشعارٌ بتطبيقه'), findsOneWidget);
    expect(find.textContaining('لم تُرسل رسالة الواتساب: الجلسة غير متّصلة'), findsOneWidget);
  });

  testWidgets('«غير مؤكَّد» ⇒ النافذة تبقى و«تحقّق من الشحن» يعيد المفتاح نفسه بلا تأكيد — لا شحنٌ بمفتاحٍ جديد', (t) async {
    var n = 0;
    server.on('POST', _topup, (_) {
      n++;
      return n == 1
          ? const SimReply(409, {'success': false, 'code': 'OUTCOME_UNKNOWN', 'message': 'لم يتأكّد الشحن من ايرث لنك'})
          : const SimReply(200, {'success': true, 'message': 'تمّ شحن 25,000 د.ع لـ«najaf40» (ظهر بكشف الحساب)'});
    });
    await open(t);
    await openSheetFor(t, 'najaf40');
    await fillAndConfirm(t, debt: true);
    expect(find.textContaining('لم يتأكّد الشحن من ايرث لنك'), findsOneWidget);
    expect(find.text('تحقّق من الشحن'), findsOneWidget);
    final amountTf = t.widget<TextField>(amountField());
    expect(amountTf.enabled, isFalse, reason: 'المدخلات مقفلة: المفتاح نفسه لا يقبل عمليّةً أخرى');
    await t.tap(find.text('تحقّق من الشحن'));
    await t.pumpAndSettle();
    expect(find.text('تأكيد الشحن'), findsNothing, reason: 'التحقّق بلا تأكيد');
    final bodies = server.bodies('POST', _topup);
    expect(bodies, hasLength(2));
    expect(bodies[1]['idempotencyKey'], bodies[0]['idempotencyKey']);
    expect(bodies[1]['as_debt'], true);
    expect(bodies[1]['amount'], 25000);
    expect(find.textContaining('ظهر بكشف الحساب'), findsOneWidget);
  });

  testWidgets('لا ردّ من الخادم (مهلة) ⇒ «غير مؤكَّد» أيضاً بالمفتاح نفسه', (t) async {
    var n = 0;
    server.on('POST', _topup, (o) {
      n++;
      if (n == 1) simTimeout(o);
      return const SimReply(200, {'success': true, 'deduped': true, 'message': 'تمّ شحن 25,000 د.ع لـ«najaf40»'});
    });
    await open(t);
    await openSheetFor(t, 'najaf40');
    await fillAndConfirm(t);
    expect(find.text('تحقّق من الشحن'), findsOneWidget);
    await t.tap(find.text('تحقّق من الشحن'));
    await t.pumpAndSettle();
    final bodies = server.bodies('POST', _topup);
    expect(bodies, hasLength(2));
    expect(bodies[1]['idempotencyKey'], bodies[0]['idempotencyKey']);
  });

  testWidgets('RECENT_DUPLICATE ⇒ سؤال، ثمّ confirmRepeat بالمفتاح نفسه بلا تأكيدٍ ثانٍ؛ و«لا» لا يرسل شيئاً', (t) async {
    var n = 0;
    server.on('POST', _topup, (_) {
      n++;
      return n == 1
          ? const SimReply(409, {'success': false, 'code': 'RECENT_DUPLICATE', 'message': 'شحنت 25,000 د.ع لـ«najaf40» قبل دقيقة — تشحنه مرّةً ثانية؟'})
          : const SimReply(200, {'success': true, 'message': 'تمّ شحن 25,000 د.ع لـ«najaf40»'});
    });
    await open(t);
    await openSheetFor(t, 'najaf40');
    await fillAndConfirm(t);
    expect(find.text('شحنٌ مكرَّر؟'), findsOneWidget);
    await t.tap(find.text('نعم، اشحن ثانيةً'));
    await t.pumpAndSettle();
    expect(find.text('تأكيد الشحن'), findsNothing, reason: 'أكّد للتوّ — لا تأكيدٌ مزدوج');
    final bodies = server.bodies('POST', _topup);
    expect(bodies, hasLength(2));
    expect(bodies[0].containsKey('confirmRepeat'), isFalse);
    expect(bodies[1]['confirmRepeat'], true);
    expect(bodies[1]['idempotencyKey'], bodies[0]['idempotencyKey']);
  });

  testWidgets('RECENT_DUPLICATE ثمّ «لا» ⇒ لا طلب ثانٍ والنافذة تبقى للتعديل', (t) async {
    server.reply('POST', _topup, 409, {'success': false, 'code': 'RECENT_DUPLICATE', 'message': 'شحنت 25,000 د.ع لـ«najaf40» قبل دقيقة — تشحنه مرّةً ثانية؟'});
    await open(t);
    await openSheetFor(t, 'najaf40');
    await fillAndConfirm(t);
    await t.tap(find.text('لا'));
    await t.pumpAndSettle();
    expect(server.bodies('POST', _topup), hasLength(1));
    expect(amountField(), findsOneWidget);
  });

  testWidgets('فشلٌ يقيناً ⇒ مفتاحٌ جديد للمحاولة التالية، والنافذة تبقى', (t) async {
    var n = 0;
    server.on('POST', _topup, (_) {
      n++;
      return n == 1
          ? const SimReply(400, {'success': false, 'code': 'NOT_APPLIED', 'message': 'رفضت ايرث لنك الشحن: Insufficient balance'})
          : const SimReply(200, {'success': true, 'message': 'تمّ'});
    });
    await open(t);
    await openSheetFor(t, 'najaf40');
    await fillAndConfirm(t);
    expect(find.textContaining('Insufficient balance'), findsOneWidget);
    expect(find.text('تحقّق من الشحن'), findsNothing);
    final footer = find.textContaining('شحن 25,000');
    await t.tap(footer.first);
    await t.pumpAndSettle();
    await t.tap(find.text('شحن'));
    await t.pumpAndSettle();
    final bodies = server.bodies('POST', _topup);
    expect(bodies, hasLength(2));
    expect(bodies[1]['idempotencyKey'], isNot(bodies[0]['idempotencyKey']));
  });

  testWidgets('المبلغ أكبر من الرصيد: تنبيهٌ لا منع (ايرث لنك تحكم)', (t) async {
    server.reply('POST', _topup, 200, {'success': true, 'message': 'تمّ'});
    await open(t);
    await openSheetFor(t, 'najaf40');
    await t.enterText(amountField(), '2000000');
    await t.pumpAndSettle();
    expect(find.textContaining('أكبر من رصيد إيداعك'), findsOneWidget);
    final footer = find.textContaining('شحن 2,000,000');
    await t.ensureVisible(footer.first);
    await t.tap(footer.first);
    await t.pumpAndSettle();
    expect(find.text('تأكيد الشحن'), findsOneWidget, reason: 'الزرّ غير معطَّل بالرصيد');
  });

  testWidgets('موظّفٌ بالعرض وحده: «شحن رصيد» و«ديون أخرى» مقفلان بمكانهما، والنقر لا يفتح شيئاً', (t) async {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'el_managers.view': true});
    await open(t);
    expect(find.byIcon(LucideIcons.lock), findsWidgets);
    await t.tap(find.text('شحن رصيد').first);
    await t.pumpAndSettle();
    expect(amountField(), findsNothing);
    expect(find.text('أضف رقم واتساب'), findsNothing, reason: 'الرقم بمفتاح الشحن');
    // شريط «لا صلاحيّة» يختفي بمؤقّته — يُترك ينتهي قبل نهاية الاختبار
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
  });

  testWidgets('موظّفٌ بالشحن: لا حقل كلمة إيداع (المحفوظة بالخادم) والجسم بلاها', (t) async {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'el_managers.topup': true});
    server.reply('POST', _topup, 200, {'success': true, 'message': 'تمّ'});
    await open(t);
    await openSheetFor(t, 'najaf40');
    expect(find.text('كلمة مرور الإيداع'), findsNothing);
    await fillAndConfirm(t);
    final b = server.bodies('POST', _topup).single;
    expect(b.containsKey('depositPassword'), isFalse);
    expect(b.containsKey('rememberDepositPassword'), isFalse);
  });

  testWidgets('الميزة مطفأة للحساب: رسالةٌ واضحة، ولصاحب الحساب «تحويل الرصيد» القديم', (t) async {
    server.reply('GET', _list, 200, _listBody(enabled: false));
    await open(t);
    expect(find.text('قسم «المدراء» لم يُفتح لحسابك بعد'), findsOneWidget);
    expect(find.text('تحويل الرصيد'), findsOneWidget);
    expect(find.text('شحن رصيد'), findsNothing);
  });

  testWidgets('٣٢٠ بخطٍّ مكبَّر: لا نصّ يفيض في البطاقة ولا في النافذة', (t) async {
    t.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await open(t, variant: const SimVariant(320, dark: true));
    expect(t.takeException(), isNull);
    await openSheetFor(t, 'najaf40');
    await t.enterText(amountField(), '250000');
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  test('ElTopupResult: النتيجة والرموز وسطر الإشعار', () {
    final ok = ElTopupResult.fromBody({
      'success': true,
      'message': 'تمّ',
      'notice': {'app': false, 'app_message': 'لا جهاز مسجّل لتطبيقه', 'whatsapp': true},
    });
    expect(ok.ok, isTrue);
    expect(ok.noticeLine, 'لا إشعار بالتطبيق: لا جهاز مسجّل لتطبيقه · أُرسلت رسالة الواتساب');
    expect(ElTopupResult.fromBody({'success': false, 'code': 'OUTCOME_UNKNOWN'}).uncertain, isTrue);
    expect(ElTopupResult.fromBody({'success': false, 'code': 'IN_PROGRESS'}).uncertain, isTrue);
    expect(ElTopupResult.fromBody({'success': false, 'code': 'RECENT_DUPLICATE'}).repeatPrompt, isTrue);
    expect(ElTopupResult.fromBody({'success': false, 'code': 'NOT_APPLIED'}).uncertain, isFalse);
    expect(const ElTopupResult(ok: false, noResponse: true).uncertain, isTrue);
  });

  test('محرّر موظّف ايرث لنك: مفاتيح «المدراء» تُمنح فرادى، و«ديون أخرى» لا تُعرض قبل فتح الميزة', () {
    ProviderService.debugSet('earthlink');
    expect(ElEmployeePerms.keys, containsAll(<String>['el_managers.view', 'el_managers.topup', 'reports.manager_debts']));
    final closed = ElEmployeePerms.offered(['subscribers.view', 'reports.manager_debts']);
    expect(closed.contains('reports.manager_debts'), isFalse);
    final open = ElEmployeePerms.offered(['subscribers.view', 'reports.manager_debts', 'el_managers.view', 'el_managers.topup']);
    expect(open, containsAll(<String>['reports.manager_debts', 'el_managers.view', 'el_managers.topup']));
    // لا دور جاهز يمنحها (تُمنح فرادى؛ والدور يعيد ضبطها — أحوط للمال)
    for (final p in ElEmployeePerms.presets) {
      expect(p.keys.intersection(ElEmployeePerms.elManagerKeys), isEmpty, reason: p.id);
    }
  });

  testWidgets('لا ردّ مفهوم من الخادم ⇒ noResponse (DioException بلا جسم)', (t) async {
    final s = server;
    s.on('POST', _topup, (o) => throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
    final r = (await t.runAsync(() => ElManagersApi.topup(index: 1025, amount: 25000, asDebt: false, idempotencyKey: 'eltop-test-1')))!;
    expect(r.noResponse, isTrue);
    expect(r.uncertain, isTrue);
  });
}
