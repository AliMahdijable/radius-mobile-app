import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_portal_api.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/national/national_labels.dart';
import 'package:rad_mysvcs/screens/national/national_wallet_screen.dart';
import 'package:rad_mysvcs/screens/national/national_widgets.dart';
import 'package:rad_mysvcs/screens/reports/widgets/date_range_chip.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «محفظتي» للمشروع الوطنيّ (١ نوفمبر — المالك: حركات التفعيل لا تظهر عندنا كما في البوّابة): قسمٌ بنفسه، آخر ٣٠ يوماً
/// افتراضاً (لا اليوم وحده)، والمحفظتان معاً، والمجموعات السريعة ⇒ group=، والصفّ v2 (العمولة، الاتّجاه، المنفّذ، التحويل)،
/// والرصيد/«حدّ المحفظة»/العمولة، و«التحويلات» حين يملكها الحساب، و«أيّ مشترك؟» حين يطابق الاسم أكثر من واحد.
const _v = SimVariant(390, dark: false);

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Map<String, Object?> _row(String type, num amount,
        {String wallet = 'Main', String? by, Map<String, Object?>? transfer, String owner = 'Partner'}) =>
    {
      'id': '9$amount',
      'at': '2026-10-31 11:15:00',
      'type': type,
      'amount': amount,
      'balance_after': 1250000,
      'method': 'Wallet',
      'pay_method': 'Wallet',
      'username': 'FBG885F15P1',
      'customer': {'id': '7', 'name': 'مريم عبد الله'},
      'subscription': {'id': '13293073', 'name': 'BASIC', 'starts': '2026-10-31 11:15:00', 'ends': '2026-11-30 11:15:00'},
      'wallet_type': wallet,
      'owner': owner,
      'change_type': 'Instant',
      'direction': amount < 0 ? 'out' : 'in',
      'by': by,
      if (transfer != null) 'transfer': transfer,
    };

Map<String, Object?> _walletReply({
  List<Map<String, Object?>>? rows,
  Map<String, Object?>? caps,
  Object? limit,
  List<Map<String, Object?>>? ambiguous,
  bool v2 = true,
}) {
  final data = rows ?? [_row('PLAN_RENEW', -35000, by: 'me'), _row('PURCHASE_COMMISSION', 2500, wallet: 'Commission')];
  return {
    'success': true,
    'data': data,
    'total': data.length,
    'page': 1,
    'size': 50,
    'page_count': 1,
    'from': '2026-10-03',
    'to': '2026-11-01',
    'balance': {'balance': 1250000, 'commission': 5000, 'currency': 'IQD', 'limit': limit},
    if (v2) ...{
      'range_default': false,
      'wallet': 'all',
      'caps': caps ?? {'commission': true, 'transfers': true, 'records': false, 'team': false},
      'ambiguous': ambiguous,
    },
  };
}

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    server.reply('GET', '/api/v2/ftth/lookups', 200, {
      'success': true,
      'data': {
        'transaction_types': [
          {'id': 'PLAN_RENEW', 'name': 'PLAN_RENEW'},
        ],
      },
    });
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  test('الصفّ v2: العمولة والاتّجاه والمنفّذ والتحويل — وما لا يرسله خادمٌ أقدم فارغ', () {
    final r = NationalMoneyRow.fromJson(_row('PLAN_RENEW', -35000, by: 'me'));
    expect(r.isOut, isTrue);
    expect(r.walletType, 'Main');
    expect(r.planName, 'BASIC');
    expect(r.ends, startsWith('2026-11-30'));
    expect(r.by, 'me');
    expect(r.changeType, 'Instant');
    final c = NationalMoneyRow.fromJson(_row('PURCHASE_COMMISSION', 2500, wallet: 'Commission'));
    expect(c.isCommission, isTrue);
    expect(c.isIn, isTrue);
    final t = NationalMoneyRow.fromJson(_row('WALLET_TRANSFER', -10000, transfer: {
      'from': {'id': '1', 'name': 'الوكيل أ'},
      'to': {'id': '2', 'name': 'الوكيل ب'},
    }));
    expect(t.transferFrom?.name, 'الوكيل أ');
    expect(t.transferTo?.name, 'الوكيل ب');
    // صفٌّ أقدم: بلا direction ⇒ من الإشارة؛ نوع المحفظة من id البوّابة
    final old = NationalMoneyRow.fromJson({
      'at': 'x',
      'type': 'WALLET_TOPUP',
      'amount': 500000,
      'wallet_type': {'id': '1'},
      'by': 'someone'
    });
    expect(old.direction, 'in');
    expect(old.walletType, 'Commission');
    expect(old.by, isNull, reason: 'لا اسم مستخدمٍ خامٌ أبداً');
    final none = NationalMoneyRow.fromJson({'type': 'PLAN_RENEW'});
    expect((none.amount, none.direction, none.walletType, none.owner), (null, '', '', ''));
  });

  test('المعاملات: الكلّ لا يُرسل، والتحويلات وحدها تحمل المالك وطريقة الدفع، و«أنا وحدي» ⇒ by=me', () {
    final w = NationalPortalApi.walletQuery(
        from: '2026-10-03',
        to: '2026-11-01',
        group: 'activations',
        wallet: 'all',
        owner: 'customer',
        method: 'card',
        change: 'instant',
        tx: ' 123 ',
        mine: true);
    expect(w['group'], 'activations');
    expect(w['wallet'], 'all', reason: '«محفظتي»: الخادم بلا wallet يردّ الرئيسيّة وحدها');
    expect(w['owner'], isNull, reason: '«محفظتي» بلا مالك');
    expect(w['method'], isNull);
    expect(w['change'], 'instant');
    expect(w['tx'], '123');
    expect(w['by'], 'me');
    expect(w.containsKey('changeTypes'), isFalse);
    final t = NationalPortalApi.walletQuery(
        transfers: true, owner: 'customer', method: 'card', wallet: 'commission', type: 'PLAN_RENEW');
    expect((t['owner'], t['method'], t['wallet'], t['types'], t['by']), ('customer', 'card', 'commission', 'PLAN_RENEW', null));
  });

  test('محفظة «محفظتي» صريحةً دائماً (الكلّ = all)، و«التحويلات» بلاها حين «الكلّ» (افتراض الخادم الكلّ)', () {
    for (final v in const [null, '', 'all']) {
      expect(NationalPortalApi.walletQuery(wallet: v)['wallet'], 'all', reason: '«محفظتي» wallet=$v');
      expect(NationalPortalApi.walletQuery(transfers: true, wallet: v)['wallet'], isNull, reason: '«التحويلات» wallet=$v');
    }
    expect(NationalPortalApi.walletQuery(wallet: 'main')['wallet'], 'main');
    expect(NationalPortalApi.walletQuery(wallet: 'commission')['wallet'], 'commission');
    expect(NationalPortalApi.walletQuery(transfers: true, wallet: 'main')['wallet'], 'main');
  });

  test('آخر ٣٠ يوماً: اليوم − ٢٩ ⇒ اليوم، وآخر ٧ أيّام', () {
    final r = DateRange.lastDays(30);
    final now = DateTime.now();
    expect(_day(r.to), _day(now));
    expect(_day(r.from), _day(DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29))));
    final w = DateRange.lastDays(7);
    expect(w.to.difference(w.from).inDays, 6);
  });

  test('الأسماء: المجموعات والأنواع الجديدة — لا «حركة أخرى» ولا «تمديد»', () {
    for (final c in [
      'SCHEDULE_CHANGE',
      'COMMIT_CHANGE',
      'HIERACHY_COMMISSION',
      'ONLINE_PAYMENT',
      'PAUSE',
      'RESUME',
      'TEAM_MEMBER_BALANCE'
    ]) {
      expect(nationalTxType(c), isNot('حركة أخرى'), reason: c);
    }
    expect(nationalTxGroups.map((g) => g.key), ['activations', 'topups', 'refunds', 'commissions']);
    expect(nationalTxTypes.values.any((v) => v.contains('تمديد')), isFalse);
    expect(nationalWalletType('Commission'), 'العمولة');
    expect(nationalChangeType('Scheduled'), 'مجدول');
  });

  test('القسم: للوطنيّ وحده بمفتاح reports.financial، والموظّف بلاه يراه مقفلاً بمكانه', () {
    var mods = {for (final m in buildAppModules()) m.id: m};
    expect(mods['national_wallet']?.title, 'محفظتي');
    expect(mods['national_wallet']?.isLocked, isFalse);
    expect(mods['national_money']?.title, 'الإيرادات');
    ProviderService.debugSet('nabd', label: 'نبض');
    expect(buildAppModules().any((m) => m.id == 'national_wallet'), isFalse);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true, 'reports.financial': false});
    mods = {for (final m in buildAppModules()) m.id: m};
    expect(mods['national_wallet']?.isLocked, isTrue, reason: 'مقفلٌ بمكانه لا مخفيّ');
  });

  testWidgets('الشاشة: آخر ٣٠ يوماً، الرصيد والعمولة، الصفّ بإشارته، والمجموعة ⇒ group=', (t) async {
    server.reply('GET', '/api/v2/ftth/wallet', 200, _walletReply());
    await pumpSim(t, _v, home: (_) => const NationalWalletScreen());
    final q = server.calls('GET', '/api/v2/ftth/wallet').first.queryParameters;
    final now = DateTime.now();
    expect(q['to'], _day(now));
    expect(q['from'], _day(DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29))));
    expect(q['wallet'], 'all', reason: 'المحفظتان معاً افتراضاً — صريحةً، فالخادم بلاها يردّ الرئيسيّة وحدها');
    expect(find.text('رصيد المحفظة'), findsOneWidget);
    expect(find.textContaining('1,250,000'), findsWidgets);
    expect(find.text('رصيد العمولة'), findsOneWidget);
    expect(find.textContaining('−35,000'), findsOneWidget);
    expect(find.textContaining('+2,500'), findsOneWidget);
    expect(find.textContaining('المنفّذ: أنت'), findsOneWidget);
    expect(find.textContaining('رصيد العمولة بعدها'), findsOneWidget);
    expect(find.text('آخر ٣٠ يوماً'), findsOneWidget);
    expect(find.text('التحويلات'), findsOneWidget, reason: 'caps.transfers');

    await t.tap(find.text('حركات التفعيل'));
    await t.pumpAndSettle();
    expect(server.calls('GET', '/api/v2/ftth/wallet').last.queryParameters['group'], 'activations');
    await simDrain(t);
  });

  testWidgets('شريحةٌ قبل وصول الردّ الأوّل ⇒ طلبٌ ثانٍ بمجموعتها وصفوفه تظهر — لا «جارٍ التحميل…» عالقة', (t) async {
    server.on(
        'GET',
        '/api/v2/ftth/wallet',
        (req) => SimReply(
            200,
            req.queryParameters['group'] == 'activations'
                ? _walletReply(rows: [_row('PLAN_RENEW', -42000)])
                : _walletReply()));
    server.hold('GET', '/api/v2/ftth/wallet');
    await pumpSim(t, _v, home: (_) => const NationalWalletScreen(), settle: false);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(server.calls('GET', '/api/v2/ftth/wallet'), hasLength(1));
    expect(find.text('جارٍ التحميل…'), findsOneWidget);
    await t.tap(find.text('حركات التفعيل'));
    await t.pump(const Duration(milliseconds: 100));
    final calls = server.calls('GET', '/api/v2/ftth/wallet');
    expect(calls, hasLength(2), reason: 'الشريحة تطلب بنفسها — لا ينتظر طلبها ردّاً سيُهمل');
    expect(calls.last.queryParameters['group'], 'activations');
    server.release('GET', '/api/v2/ftth/wallet');
    await t.pumpAndSettle();
    expect(find.textContaining('−42,000'), findsOneWidget);
    expect(find.textContaining('−35,000'), findsNothing, reason: 'ردّ ما قبل الشريحة يُهمل');
    expect(find.text('جارٍ التحميل…'), findsNothing);
    await simDrain(t);
  });

  testWidgets('التحويلات: مسارها، آخر ٧ أيّام، والمالك من الفلاتر', (t) async {
    server.reply('GET', '/api/v2/ftth/wallet', 200, _walletReply());
    server.reply('GET', '/api/v2/ftth/transfers', 200, {
      'success': true,
      'data': [_row('PLAN_RENEW', -35000, owner: 'Customer')],
      'total': 1,
      'page': 1,
      'page_count': 1,
    });
    await pumpSim(t, _v, home: (_) => const NationalWalletScreen());
    await t.tap(find.text('التحويلات'));
    await t.pumpAndSettle();
    final q = server.calls('GET', '/api/v2/ftth/transfers').last.queryParameters;
    final now = DateTime.now();
    expect(q['from'], _day(DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6))));
    expect(find.text('محفظة المشترك'), findsOneWidget);
    expect(find.textContaining('1,250,000'), findsWidgets, reason: 'الرصيد يبقى من «محفظتي»');
    await t.tap(find.text('الفلاتر'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('المشتركين'));
    await t.tap(find.text('المشتركين'));
    await t.pumpAndSettle();
    await t.tap(find.text('تطبيق'));
    await t.pumpAndSettle();
    expect(server.calls('GET', '/api/v2/ftth/transfers').last.queryParameters['owner'], 'customer');
    await simDrain(t);
  });

  testWidgets('الفلاتر: النوع والمنفّذ ورقم المعاملة (بأرقامٍ هنديّة) ⇒ معاملات الطلب', (t) async {
    server.reply('GET', '/api/v2/ftth/wallet', 200, _walletReply());
    await pumpSim(t, _v, home: (_) => const NationalWalletScreen());
    await t.tap(find.text('الفلاتر'));
    await t.pumpAndSettle();
    await t.tap(find.text('تجديد').last);
    await t.ensureVisible(find.text('أنا وحدي'));
    await t.tap(find.text('أنا وحدي'));
    await t.ensureVisible(find.text('رقم المعاملة'));
    final tx = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first;
    await t.enterText(tx, '١٢٣٤');
    await t.pumpAndSettle();
    await t.tap(find.text('تطبيق'));
    await t.pumpAndSettle();
    final q = server.calls('GET', '/api/v2/ftth/wallet').last.queryParameters;
    expect((q['types'], q['by'], q['tx']), ('PLAN_RENEW', 'me', '1234'));
    expect(find.text('3'), findsOneWidget, reason: 'عدّاد الفلاتر المفعّلة');
    await simDrain(t);
  });

  testWidgets('عضو فريقٍ بحدّ ⇒ «حدّ المحفظة»؛ وخادمٌ أقدم (بلا caps) ⇒ لا مجموعات ولا «التحويلات»', (t) async {
    server.reply('GET', '/api/v2/ftth/wallet', 200, _walletReply(limit: {'balance': 200000}));
    await pumpSim(t, _v, home: (_) => const NationalWalletScreen());
    expect(find.text('حدّ المحفظة'), findsOneWidget);
    expect(find.textContaining('200,000'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('خادمٌ أقدم (v1): لا شرائح فرزٍ لا يفهمها ولا بحث ولا «الفلاتر» ولا تبويب', (t) async {
    server.reply('GET', '/api/v2/ftth/wallet', 200, _walletReply(v2: false));
    await pumpSim(t, _v, home: (_) => const NationalWalletScreen());
    expect(find.text('حركات التفعيل'), findsNothing);
    expect(find.text('التحويلات'), findsNothing);
    expect(find.byType(NationalSearchField), findsNothing);
    expect(find.byType(NationalFilterButton), findsNothing);
    expect(find.text('الفلاتر'), findsNothing);
    expect(find.textContaining('−35,000'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('اسمٌ يطابق أكثر من مشترك ⇒ اختر واحداً، والاختيار يبحث برمز اشتراكه', (t) async {
    server.on('GET', '/api/v2/ftth/wallet', (req) {
      final q = req.queryParameters['q'];
      if (q == 'علي') {
        return SimReply(
            200,
            _walletReply(rows: const [], ambiguous: [
              {'customer_id': '7', 'name': 'علي حسين', 'username': 'FBG1A'},
              {'customer_id': '8', 'name': 'علي كاظم', 'username': 'FBG2B'},
            ]));
      }
      return SimReply(200, _walletReply());
    });
    await pumpSim(t, _v, home: (_) => const NationalWalletScreen());
    await t.enterText(find.byType(TextField).first, 'علي');
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.textContaining('أكثر من مشترك بهذا الاسم'), findsOneWidget);
    await t.tap(find.text('علي كاظم'));
    await t.pumpAndSettle();
    expect(server.calls('GET', '/api/v2/ftth/wallet').last.queryParameters['q'], 'FBG2B');
    await simDrain(t);
  });
}
