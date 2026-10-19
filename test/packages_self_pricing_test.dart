import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/screens/packages/packages_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «تسعيري الخاص» لمديرٍ معرّفه مؤهَّلٌ بساسه (٣.٠.٣+١٦٣).
///
/// 🐛 تدقيق المدير المقيَّد ١٨ أكتوبر (admin@hhnn، `next-gen:175`):
/// `int.tryParse('next-gen:175')` = null، فالشاشة بلا مدراء فرعيّين تقرأ
/// `/api/v2/packages` (قائمة الإضافة/التفعيل: بلا `user_price`) فيبدو «سعر البيع»
/// فارغاً، والحفظ يرجع بصمت لأنّه بلا معرّف. الآن: الرقم بعد آخر «:»، و«تسعيري
/// الخاص» لمعرّفٍ مؤهَّل من `/api/v2/price-list/<رقمه>` — والخادم يؤهّله بساس
/// التوكن (`next-gen:175`) قراءةً وحفظاً. الساس الأصل (معرّفٌ عارٍ) كما كان.
const _v = SimVariant(390, dark: false);
const _managers = '/api/v2/managers';
const _packages = '/api/v2/packages';
const _priceListPost = '/api/v2/price-list';

/// صفّ `/api/v2/price-list/:id` كما يردّه فرع الساس البعيد في الخادم.
Map<String, Object?> _row(int id, String name, int userPrice) => {
      'id': id,
      'profile_id': id,
      'name': name,
      'profile_name': name,
      'user_price': userPrice,
      'price': userPrice,
      'cost': 0,
    };

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  Future<void> session(String adminId, {String username = 'admin@hhnn'}) async {
    server = await simSetUp(secure: {
      'auth.admin_id': adminId,
      'auth.admin_username': username,
    });
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
    server.on('POST', _priceListPost,
        (_) => const SimReply(200, {'success': true, 'data': {'count': 2}}));
  }

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  void priceList(int managerId, List<Map<String, Object?>> rows) =>
      server.reply('GET', '/api/v2/price-list/$managerId', 200,
          {'success': true, 'data': rows});

  Future<void> open(WidgetTester t) async {
    await pumpSim(t, _v, home: (_) => const PackagesScreen());
    expect(t.takeException(), isNull);
  }

  Finder field(String text) =>
      find.descendant(of: find.byType(TextField), matching: find.text(text));

  Future<void> saveEconomyAs(WidgetTester t, String value) async {
    await t.enterText(find.byType(TextField).first, value);
    await t.pumpAndSettle();
    await t.tap(find.byIcon(LucideIcons.save));
    await t.pumpAndSettle();
  }

  testWidgets(
      '🚨 مدير ساسٍ بعيد (next-gen:175) بلا مدراء فرعيّين: سعر البيع من price-list/175 والحفظ يرسل 175',
      (t) async {
    await session('next-gen:175');
    // المدير المقيَّد بلا managers.view: الساس يرفض القائمة.
    server.reply('GET', _managers, 403, {'success': false});
    priceList(175, [_row(101, 'Economy', 25000), _row(102, 'Family', 0)]);
    await open(t);

    expect(server.calls('GET', '/api/v2/price-list/175'), hasLength(1));
    expect(server.calls('GET', _packages), isEmpty,
        reason: 'قائمة الإضافة بلا user_price — ليست «تسعيري الخاص»');
    expect(field('25,000'), findsOneWidget, reason: 'سعر البيع المحفوظ ظاهر');
    expect(find.text('admin@hhnn'), findsOneWidget, reason: 'المختار: هو نفسه');

    await saveEconomyAs(t, '30000');

    final posts = server.bodies('POST', _priceListPost);
    expect(posts, hasLength(1), reason: 'الحفظ لا يرجع بصمت');
    expect(posts.single['manager_id'], 175);
    final items = (posts.single['priceList'] as List).cast<Map>();
    expect(
      {for (final i in items) i['profile_id']: i['user_price']},
      {101: 30000, 102: 0},
      reason: 'المعدَّل بقيمته، وغير الملموس بما قُرئ لا صفرٌ مخترَع',
    );
    expect(find.text('تمّ حفظ الأسعار'), findsOneWidget);
    expect(server.calls('GET', '/api/v2/price-list/175'), hasLength(2),
        reason: 'يُعاد التحميل بعد الحفظ');
    expect(server.calls('GET', _packages), isEmpty);
    await simDrain(t);
  });

  testWidgets(
      'مدير ساسٍ بعيد بمدراء فرعيّين: يفتح على الأوّل، و«تسعيري الخاص» باسمه يقرأ 175',
      (t) async {
    await session('next-gen:175');
    server.reply('GET', _managers, 200, {
      'success': true,
      'data': [
        {'id': 300, 'username': 'sub1'},
      ],
    });
    priceList(300, [_row(101, 'Economy', 20000)]);
    priceList(175, [_row(101, 'Economy', 25000)]);
    await open(t);

    expect(server.calls('GET', '/api/v2/price-list/300'), hasLength(1));
    expect(server.calls('GET', '/api/v2/price-list/175'), isEmpty);
    expect(field('20,000'), findsOneWidget);

    await t.tap(find.text('sub1'));
    await t.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    // صفّ «تسعيري الخاص» باسم صاحب الحساب — كان يعرض اسم المختار (sub1 مرّتين).
    final self = find.ancestor(
        of: find.byIcon(LucideIcons.user), matching: find.byType(ListTile));
    expect(
        find.descendant(of: self, matching: find.text('admin@hhnn')),
        findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('sub1')),
        findsOneWidget);

    await t.tap(self);
    await t.pumpAndSettle();
    expect(server.calls('GET', '/api/v2/price-list/175'), hasLength(1));
    expect(field('25,000'), findsOneWidget);

    await saveEconomyAs(t, '26000');
    final posts = server.bodies('POST', _priceListPost);
    expect(posts.single['manager_id'], 175, reason: 'تسعيره هو لا الفرعيّ');
    expect(server.calls('GET', _packages), isEmpty);
    await simDrain(t);
  });

  testWidgets('سوبرنت (معرّفٌ عارٍ 42): «تسعيري الخاص» من /api/v2/packages كما كان',
      (t) async {
    await session('42', username: 'admin@supernet');
    server.reply('GET', _managers, 200, {'success': true, 'data': []});
    server.reply('GET', _packages, 200, {
      'success': true,
      'data': [
        {'id': 101, 'name': 'Economy', 'price': 25000, 'cost_price': 20000},
      ],
    });
    await open(t);

    expect(server.calls('GET', _packages), hasLength(1));
    expect(server.requests.where((r) => r.path.startsWith('/api/v2/price-list')),
        isEmpty);

    await saveEconomyAs(t, '30000');
    expect(server.bodies('POST', _priceListPost).single['manager_id'], 42);
    await simDrain(t);
  });

  testWidgets('ايرث لنك (earthlink:5): price-list/5 — الخادم يفرض المالك من الجلسة',
      (t) async {
    await session('earthlink:5', username: 'mahdi.el');
    ProviderService.debugSet('earthlink');
    // ردّ ايرث لنك الحقيقيّ: الموزّع صفّاً وحيداً بمعرّفه الكامل (لا رقم).
    server.reply('GET', _managers, 200, {
      'success': true,
      'data': [
        {'id': 'earthlink:5', 'username': 'mahdi.el'},
      ],
    });
    priceList(5, [_row(7, 'Fiber 35', 35000)]);
    await open(t);

    expect(server.calls('GET', '/api/v2/price-list/5'), hasLength(1));
    expect(server.calls('GET', _packages), isEmpty);
    expect(field('35,000'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('FTTH (ftth-iq:9): بلا price-list عنده — يبقى على /api/v2/packages',
      (t) async {
    await session('ftth-iq:9', username: 'partner');
    ProviderService.debugSet('ftth');
    server.reply('GET', _managers, 200, {'success': true, 'data': []});
    server.reply('GET', _packages, 200, {
      'success': true,
      'data': [
        {'id': 3, 'name': 'FTTH 50', 'price': 40000},
      ],
    });
    await open(t);

    expect(server.calls('GET', _packages), hasLength(1));
    expect(server.requests.where((r) => r.path.startsWith('/api/v2/price-list')),
        isEmpty);
    await simDrain(t);
  });
}
