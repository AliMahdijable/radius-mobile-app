import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/free_users_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/free_users/free_users_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';

import 'sim_el/sim_harness.dart';

/// «اليوزرات الفري» بالتطبيق (٢٦ نوفمبر — المالك: «تمام كلشي يعني تطبيق وويب»): الشاشة بعقد الموقع /v2/free-users حرفاً —
/// القائمة باسم الحامل، البيع (نقدي/جزئي/دين) وتأكيد التكرار، الترك والدين قائم، «تسديد» بنافذة صفحة المشتركين باسم الحامل ودينه
/// من /debt، الأقفال للموظّف، والقسم بالقائمة حين يقول الخادم إنّه مفعّل.

Map<String, dynamic> _item(
  int id, {
  String state = 'active',
  String? name = 'محمد علي',
  String user = 'review@poox',
  String idx = '259672',
  int price = 35000,
  String? phone = '077023920320',
  int fails = 0,
  int? debt,
  String? debtSource,
}) =>
    {
      'id': id,
      'idx': idx,
      'username': user,
      'sub_name': name,
      'sub_phone': phone,
      'price': price,
      'state': state,
      'paid_until': state == 'pending' ? null : '2026-12-26 12:33',
      'minutes_left': state == 'pending' ? null : (state == 'expired' ? -120 : 43000),
      'sas_enabled': state == 'active' ? 1 : 0,
      'last_error': null,
      'fail_count': fails,
      'holder_from': '2026-11-26 12:30',
      // دين الحامل مع القائمة (٢٦ نوفمبر) — بلا [debt] ولا [debtSource] = خادمٌ أقدم (لا يُعرف)
      if (debt != null || debtSource != null) 'debt': debt,
      if (debt != null || debtSource != null) 'debt_source': debtSource ?? 'ledger',
    };

Map<String, dynamic> _list(List<Map<String, dynamic>> items, {bool enabled = true, bool test = true}) => {
      'success': true,
      'enabled': enabled,
      'family': 'sas4',
      'test': test,
      if (!enabled) 'reason': 'بيع الفري غير مفعّل لحسابك بعد',
      'items': items,
      'summary': enabled
          ? {
              'active': items.where((x) => x['state'] == 'active').length,
              'expired': items.where((x) => x['state'] == 'expired').length,
              'pending': items.where((x) => x['state'] == 'pending').length,
              'ending_soon': 0,
              'last30': {'sales': 3, 'total': 105000, 'paid': 70000, 'debt': 35000},
            }
          : null,
    };

final _two = [
  _item(1),
  _item(3, name: 'عبد الرحمن عبد الكريم الموسوي', user: 'admin@laith7-long-username', idx: '86091', price: 25000, state: 'expired'),
];

void main() {
  test('النموذج: الحقول بأسماء الخادم، والحالات، و«باقي/انتهى منذ»، وبداية الحامل', () {
    final l = FreeList.fromJson(_list(_two))!;
    expect([l.enabled, l.test, l.where, l.items.length], [true, true, 'بالساس', 2]);
    final a = l.items.first;
    expect([a.id, a.idx, a.username, a.subName, a.price, a.state, a.holderFrom], [1, '259672', 'review@poox', 'محمد علي', 35000, FreeState.active, '2026-11-26 12:30']);
    expect(l.items.last.state, FreeState.expired);
    expect(l.summary!.debt30, 35000);
    expect(freeLeftText(43000), 'باقي 30 يوم');
    expect(freeLeftText(-120), 'انتهى منذ 2 ساعة');
    expect(freeLeftText(null), '—');
    expect(freeDay('2026-11-26 12:30'), DateTime(2026, 11, 26));
    expect(FreeList.fromJson({'success': false}), isNull);
    expect(FreeItem.fromJson({'id': 1}), isNull, reason: 'بلا idx/يوزر ⇒ لا سطر');
  });

  group('الشاشة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      FreeUsersState.reset();
      PermissionsService.debugSet(isEmployee: false);
      server = await simSetUp(secure: {'auth.admin_id': '2251', 'auth.admin_username': 'admin@poox'});
    });
    tearDown(PermissionsService.debugReset);

    Future<void> open(WidgetTester t, {SimVariant v = const SimVariant(390, dark: false)}) async {
      await pumpSim(t, v, home: (_) => const FreeUsersScreen());
      await t.pumpAndSettle();
    }

    testWidgets('القائمة: الاسم المسجَّل عنواناً واليوزر بعده، الإحصاءات، والأزرار؛ الفلتر بالحالة', (t) async {
      server.reply('GET', '/api/v2/free-users', 200, _list(_two));
      await open(t);
      expect(find.text('محمد علي'), findsOneWidget);
      expect(find.textContaining('review@poox'), findsOneWidget);
      expect(find.textContaining('35,000'), findsWidgets);
      expect(find.text('شغّال'), findsWidgets);
      // «العمليات» (المالك ٢٦ نوفمبر: «حاكي العمليات»): أربع بلاطات على البطاقة، والباقي في «المزيد»
      for (final b in ['sell-1', 'hist-1', 'stmt-1', 'more-1']) {
        expect(find.byKey(ValueKey('free-btn-$b')), findsOneWidget, reason: b);
      }
      for (final b in ['edit-1', 'debt-1', 'test-1', 'release-1', 'pay-1']) {
        expect(find.byKey(ValueKey('free-btn-$b')), findsNothing, reason: '$b في «المزيد» لا على البطاقة');
      }
      await t.tap(find.byKey(const ValueKey('free-btn-more-1')));
      await t.pumpAndSettle();
      expect(find.text('إجراءات أخرى'), findsOneWidget);
      for (final b in ['pay-1', 'debt-1', 'edit-1', 'test-1', 'release-1']) {
        expect(find.byKey(ValueKey('free-btn-$b')), findsOneWidget, reason: '$b في «المزيد» (دينٌ لا يُعرف من خادمٍ أقدم ⇒ «تسديد» هنا)');
      }
      Navigator.of(t.element(find.text('إجراءات أخرى'))).pop();
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const ValueKey('free-btn-more-3')), 250, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
      await t.ensureVisible(find.byKey(const ValueKey('free-btn-more-3')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('free-btn-more-3')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('free-btn-test-3')), findsNothing, reason: '«مدّة فحص» للشغّال وحده');
      Navigator.of(t.element(find.text('إجراءات أخرى'))).pop();
      await t.pumpAndSettle();
      await t.drag(find.byType(ListView), const Offset(0, 4000));
      await t.pumpAndSettle();
      expect(FreeUsersState.on, true, reason: 'ما رأته الشاشة يكتب حال القائمة');
      await t.tap(find.byKey(const ValueKey('free-view-expired')));
      await t.pumpAndSettle();
      expect(find.text('محمد علي'), findsNothing);
      expect(find.text('عبد الرحمن عبد الكريم الموسوي'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('«تسديد» حين عليه دين وحده: بلوك الدين بالمبلغ على بطاقته؛ لا دين ⇒ لا «تسديد» أبداً؛ دين الساس ⇒ في «المزيد»', (t) async {
      server.reply('GET', '/api/v2/free-users', 200, _list([
        _item(1, debt: 35000),
        _item(3, name: 'علاء رمح', user: 'free77@x', idx: '86091', state: 'expired', debt: 0),
        _item(4, name: 'ابو بشير', user: 'free78@x', idx: '86092', debtSource: 'sas'),
      ]));
      await open(t);
      expect(find.byKey(const ValueKey('free-debt-1')), findsOneWidget);
      expect(find.text('35,000 د.ع'), findsWidgets);
      expect(find.byKey(const ValueKey('free-btn-pay-1')), findsOneWidget, reason: 'زرّ «تسديد» ببلوك الدين');
      await t.tap(find.byKey(const ValueKey('free-btn-more-1')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('free-btn-pay-1')), findsOneWidget, reason: 'مرّةً واحدة — ليس في «المزيد» أيضاً');
      Navigator.of(t.element(find.text('إجراءات أخرى'))).pop();
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const ValueKey('free-btn-more-3')), 250, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
      await t.ensureVisible(find.byKey(const ValueKey('free-btn-more-3')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('free-debt-3')), findsNothing, reason: 'دينه صفر');
      await t.tap(find.byKey(const ValueKey('free-btn-more-3')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('free-btn-pay-3')), findsNothing, reason: 'لا دين ⇒ لا «تسديد» في أيّ مكان');
      expect(find.byKey(const ValueKey('free-btn-debt-3')), findsOneWidget, reason: '«إضافة دين» باقٍ');
      Navigator.of(t.element(find.text('إجراءات أخرى'))).pop();
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.byKey(const ValueKey('free-btn-more-4')), 250, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
      await t.ensureVisible(find.byKey(const ValueKey('free-btn-more-4')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('free-debt-4')), findsNothing);
      await t.tap(find.byKey(const ValueKey('free-btn-more-4')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('free-btn-pay-4')), findsOneWidget, reason: 'دين الساس لا يُعرف هنا ⇒ «تسديد» في «المزيد»');
      await simDrain(t);
    });

    testWidgets('غير مفعّلة ⇒ سبب الخادم؛ وتعذّر القراءة ⇒ «اسحب للأسفل»', (t) async {
      server.reply('GET', '/api/v2/free-users', 200, _list(const [], enabled: false));
      await open(t);
      expect(find.text('«اليوزرات الفري» غير مفعّلة لحسابك بعد'), findsOneWidget);
      expect(find.text('بيع الفري غير مفعّل لحسابك بعد'), findsOneWidget);
      expect(FreeUsersState.on, false);
      server.reply('GET', '/api/v2/free-users', 500, {'success': false});
      await t.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await t.pumpAndSettle();
      expect(find.text('تعذّرت قراءة اليوزرات الفري'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('البيع: ٣ أشهر بالدين ⇒ جسم الخادم حرفاً؛ «بيعٌ قريب» ⇒ تأكيدٌ يرسل confirmRepeat؛ النجاح يعيد القائمة', (t) async {
      server.reply('GET', '/api/v2/free-users', 200, _list(_two));
      server.reply('POST', '/api/v2/free-users/1/sell', 409,
          {'success': false, 'code': 'RECENT_DUPLICATE', 'message': 'بيعٌ لهذا اليوزر قبل دقيقتين — أكّد إن كان بيعاً ثانياً'});
      await open(t);
      await t.tap(find.byKey(const ValueKey('free-btn-sell-1')));
      await t.pumpAndSettle();
      await t.tap(find.text('3 أشهر'));
      await t.tap(find.text('دين'));
      await t.pumpAndSettle();
      expect(find.text('بيع 105,000 د.ع'), findsOneWidget, reason: 'المجموع = السعر × الأشهر');
      await t.tap(find.text('بيع 105,000 د.ع'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/free-users/1/sell').single,
          {'months': 3, 'paymentType': 'non-cash', 'confirmRepeat': false});
      expect(find.byKey(const ValueKey('free-repeat')), findsOneWidget);
      server.reply('POST', '/api/v2/free-users/1/sell', 200, {'success': true, 'paid_until': '2027-03-26 12:33:00'});
      final lists = server.calls('GET', '/api/v2/free-users').length;
      await t.tap(find.text('أكّد البيع مرّةً أخرى'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/free-users/1/sell').last['confirmRepeat'], true);
      expect(find.textContaining('تمّ البيع — مدفوع لحدّ 2027-03-26 12:33'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/free-users').length, lists + 1, reason: 'القائمة من جديد');
      await simDrain(t);
    });

    testWidgets('البيع بلا ردّ (مهلة/انقطاع أو ٥xx) ⇒ «لم يتأكّد» والزرّ مقفل — لا «تعذّر» ولا ضغطةٌ ثانية', (t) async {
      for (final drop in [true, false]) {
        server.reply('GET', '/api/v2/free-users', 200, _list(_two));
        if (drop) {
          server.on('POST', '/api/v2/free-users/1/sell', simTimeout);
        } else {
          server.reply('POST', '/api/v2/free-users/1/sell', 502, 'Bad Gateway');
        }
        await open(t);
        await t.tap(find.byKey(const ValueKey('free-btn-sell-1')));
        await t.pumpAndSettle();
        final sends = server.calls('POST', '/api/v2/free-users/1/sell').length;
        await t.tap(find.text('بيع 35,000 د.ع'));
        await t.pumpAndSettle();
        expect(server.calls('POST', '/api/v2/free-users/1/sell').length, sends + 1);
        expect(find.byKey(const ValueKey('free-unknown')), findsOneWidget, reason: drop ? 'مهلة' : '502');
        expect(find.textContaining('لم يتأكّد البيع'), findsOneWidget);
        expect(find.text('تعذّر البيع'), findsNothing);
        await t.tap(find.text('بيع 35,000 د.ع'), warnIfMissed: false);
        await t.pumpAndSettle();
        expect(server.calls('POST', '/api/v2/free-users/1/sell').length, sends + 1, reason: 'الزرّ مقفل — لا بيع ثانٍ');
        await t.pumpWidget(const SizedBox());
        await simDrain(t);
      }
    });

    testWidgets('الترك والدين قائم ⇒ رسالة الخادم باسم الحامل ومبلغه، ولا تحديث', (t) async {
      server.reply('GET', '/api/v2/free-users', 200, _list(_two));
      server.reply('POST', '/api/v2/free-users/1/release', 409, {
        'success': false,
        'code': 'FREE_RELEASE_HAS_DEBT',
        'debt': 35000,
        'message': 'على «محمد علي» دين 35,000 د.ع — سدّده أوّلاً (زرّ «تسديد»)؛ لم يُترك شيء',
      });
      await open(t);
      final lists = server.calls('GET', '/api/v2/free-users').length;
      await t.tap(find.byKey(const ValueKey('free-btn-more-1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('free-btn-release-1')));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'ترك'));
      await t.pumpAndSettle();
      expect(server.bodies('POST', '/api/v2/free-users/1/release').single, {'enable': false});
      expect(find.textContaining('على «محمد علي» دين 35,000 د.ع'), findsOneWidget);
      expect(server.calls('GET', '/api/v2/free-users').length, lists);
      await simDrain(t);
    });

    testWidgets('«تسديد» ⇒ دين اليوزر من /debt ثمّ نافذة التسديد نفسها باسم الحامل ودينه', (t) async {
      server.reply('GET', '/api/v2/free-users', 200, _list([_item(1, debt: 35000), _two[1]]));
      server.reply('GET', '/api/v2/free-users/1/debt', 200, {'success': true, 'balance': -35000, 'source': 'ledger'});
      await open(t);
      await t.scrollUntilVisible(find.byKey(const ValueKey('free-btn-pay-1')), 250, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
      await t.ensureVisible(find.byKey(const ValueKey('free-btn-pay-1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('free-btn-pay-1')));
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/free-users/1/debt'), hasLength(1));
      // نافذة صفحة المشتركين نفسها («تسديد دين») — رأسها باسم الحامل لا يوزر الشركة
      final sheet = find.ancestor(of: find.text('تسديد دين'), matching: find.byType(Column)).first;
      expect(find.text('تسديد دين'), findsOneWidget);
      expect(find.descendant(of: find.ancestor(of: find.text('تسديد دين'), matching: find.byType(Row)).first, matching: find.text('محمد علي')),
          findsOneWidget, reason: 'الرأس باسم الحامل');
      expect(find.descendant(of: sheet, matching: find.textContaining('review@poox')), findsNothing, reason: 'لا يوزر الشركة عنواناً');
      expect(find.textContaining('35,000'), findsWidgets, reason: 'دينه من الدفتر');
      await simDrain(t);
    });

    testWidgets('تعذّر قراءة الدين ⇒ رسالة الخادم ولا نافذة', (t) async {
      server.reply('GET', '/api/v2/free-users', 200, _list(_two));
      server.reply('GET', '/api/v2/free-users/1/debt', 409,
          {'success': false, 'code': 'FREE_DEBT_UNAVAILABLE', 'message': 'تعذّرت قراءة دين «محمد علي» الآن — أعد المحاولة'});
      await open(t);
      await t.tap(find.byKey(const ValueKey('free-btn-more-1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('free-btn-debt-1')));
      await t.pumpAndSettle();
      expect(find.text('تعذّرت قراءة دين «محمد علي» الآن — أعد المحاولة'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('موظّفٌ بلا مفاتيحها ⇒ الأزرار بمكانها مقفلةً (لا مخفيّة)؛ والعرض وحده يعمل', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: const {'free.view': true});
      server.reply('GET', '/api/v2/free-users', 200, _list([_item(1, debt: 35000), _two[1]]));
      await open(t);
      Finder lockIn(String b) => find.descendant(of: find.byKey(ValueKey('free-btn-$b')), matching: find.byType(PermLockBadge));
      expect(lockIn('sell-1'), findsOneWidget, reason: 'البيع مقفلٌ بمكانه');
      expect(lockIn('stmt-1'), findsOneWidget, reason: 'كشف الحساب مقفل');
      expect(lockIn('hist-1'), findsNothing, reason: 'السجلّ عرضٌ');
      expect(find.descendant(of: find.byKey(const ValueKey('free-btn-pay-1')), matching: find.byIcon(LucideIcons.lock)), findsOneWidget,
          reason: '«تسديد» ببلوك الدين بقفل');
      final before = server.requests.length;
      await t.tap(find.byKey(const ValueKey('free-btn-sell-1')));
      await t.pumpAndSettle();
      expect(find.text('المدّة'), findsNothing, reason: 'لا نافذة بيع');
      await t.pump(const Duration(seconds: 6)); // رسالة القفل تطفو ثمّ تزول — لا تحجب الزرّ التالي
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('free-btn-pay-1')));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 6));
      await t.pumpAndSettle();
      expect(server.requests.length, before, reason: 'نقرة المقفل رسالةٌ وحدها — لا طلب');
      await t.tap(find.byKey(const ValueKey('free-btn-more-1')));
      await t.pumpAndSettle();
      for (final b in ['edit-1', 'debt-1', 'release-1']) {
        expect(find.descendant(of: find.byKey(ValueKey('free-btn-$b')), matching: find.byType(PermLockIcon)), findsOneWidget, reason: '$b مقفل');
      }
      await t.tap(find.byKey(const ValueKey('free-btn-release-1')));
      await t.pumpAndSettle();
      expect(find.text('إجراءات أخرى'), findsOneWidget, reason: 'المقفل لا يغلق الشيت');
      expect(server.requests.length, before);
      Navigator.of(t.element(find.text('إجراءات أخرى'))).pop();
      await t.pumpAndSettle();
      expect(t.widget<ButtonStyleButton>(find.byKey(const ValueKey('free-assign'))).onPressed, isNull);
      await simDrain(t);
    });

    for (final v in simVariants) {
      testWidgets('العرض @${v.tag}: يوزران (اسمٌ طويل) بلا فيضٍ ولا استثناء', (t) async {
        server.reply('GET', '/api/v2/free-users', 200, _list(_two));
        await open(t, v: v);
        expect(t.takeException(), isNull);
        await t.tap(find.byKey(const ValueKey('free-btn-sell-1')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'نافذة البيع');
        await simDrain(t);
      });
    }
  });

  group('«قوائم أخرى»', () {
    setUpAll(simSetUpAll);
    tearDown(() {
      PermissionsService.debugReset();
      FreeUsersState.reset();
    });

    testWidgets('القسم حين يقول الخادم إنّه مفعّل وحده؛ والموظّف بلا «العرض» لا يسأل ولا يرى', (t) async {
      await simSetUp(secure: {'auth.admin_id': '2251', 'auth.admin_username': 'admin@poox'});
      PermissionsService.debugSet(isEmployee: false);
      FreeUsersState.seen(FreeList.fromJson(_list(const [], enabled: false))!);
      expect(buildAppModules().where((m) => m.id == 'free_users'), isEmpty);
      FreeUsersState.seen(FreeList.fromJson(_list(_two))!);
      final m = buildAppModules().singleWhere((m) => m.id == 'free_users');
      expect([m.title, m.locked], ['اليوزرات الفري', false]);
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
      FreeUsersState.reset();
      await FreeUsersState.ensureFresh(force: true);
      expect(FreeUsersState.gate.value, isNull, reason: 'لا سؤال بلا «عرض اليوزرات الفري»');
    });
  });
}
