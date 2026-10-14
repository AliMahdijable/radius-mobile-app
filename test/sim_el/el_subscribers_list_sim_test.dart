import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// محاكاة قائمة المشتركين بجلسة ايرث لنك وشريحة «مهمَل» (حساباتٌ لم تُفعَّل
/// قطّ — `abandoned: true` من الخادم): القائمة الافتراضيّة والعدّادات
/// تستثنيها، و«مهمَل» وحده يعرضها.
const _screen = 'el_subscribers';

Map<String, Object?> _row(
  int idx,
  String user, {
  String first = '',
  String last = '',
  String? profile,
  String? expiration,
  int? remaining,
  bool online = false,
  String? notes,
  bool abandoned = false,
}) =>
    {
      'idx': '$idx',
      'username': user,
      'firstname': first,
      'lastname': last,
      'phone': '0770${1000000 + idx}',
      if (profile != null) 'profile_name': profile,
      if (profile != null) 'profile_id': 7,
      if (expiration != null) 'expiration': expiration,
      if (remaining != null) 'remaining_days': remaining,
      'online_status': online ? 1 : 0,
      'enabled': 1,
      if (notes != null) 'notes': notes,
      if (abandoned) 'abandoned': true,
    };

final _subscribers = [
  _row(1, 'ali1@alnoor-net',
      first: 'علي',
      last: 'حسن الموسوي',
      profile: 'Economy',
      expiration: '2026-11-02 10:00:00',
      remaining: 20,
      online: true),
  _row(2, 'zainab.k@alnoor-net',
      first: 'زينب',
      last: 'كاظم',
      profile: 'Standard',
      expiration: '2026-10-14 08:00:00',
      remaining: 1),
  _row(3, 'hussein77@alnoor-net',
      first: 'حسين',
      last: 'عبد الأمير',
      profile: 'Plus',
      expiration: '2026-10-01 08:00:00',
      remaining: -12,
      notes: '-35000'),
  _row(4, 'mustafa.office@alnoor-net',
      first: 'مكتب',
      last: 'مصطفى للمحاماة',
      profile: 'Business Pro 100M',
      expiration: '2026-12-20 08:00:00',
      remaining: 68),
  _row(5, 'test1@alnoor-net', first: 'تجربة', abandoned: true),
  _row(6, 'new.sub.0912@alnoor-net', abandoned: true),
  _row(7, 'karrada-shop@alnoor-net', first: 'محلّ', last: 'الكرادة', abandoned: true),
];

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    SubscribersApi.clearAllCaches();
    await ActiveCompany.saveFromLogin(
      sasUrl: '',
      adminId: 'earthlink:5',
      loginUsername: 'mahdi.el',
      adminUsername: 'mahdi.el',
      isEmployee: false,
      label: 'ايرث لنك (Earthlink)',
      sasCode: 'earthlink',
    );
    server.reply('GET', '/api/v2/subscribers', 200,
        {'success': true, 'data': _subscribers});
  });

  tearDown(ActiveCompany.clear);

  Future<void> open(WidgetTester t, SimVariant v) async {
    await pumpSim(t, v,
        home: (_) => SubscribersScreen(isActive: ValueNotifier<bool>(true)));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
  }

  /// يفكّ الشاشة (مؤقّت الاستطلاع كلّ ٥ث) قبل نهاية الاختبار.
  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 2));
  }

  Finder chip(String label) => find.descendant(
      of: find.byType(FilterChipsBar), matching: find.text(label));

  /// الشريحة الأخيرة لا تُبنى قبل التمرير (قائمةٌ أفقيّة كسولة). تُحرَّك
  /// القائمة الأفقيّة وحدها: `ensureVisible` يحرّك القائمة الرأسيّة أيضاً
  /// فينطوي الرأس ويحلّ شريط البحث المضغوط محلّ الشرائح.
  Future<void> revealChip(WidgetTester t, String label) async {
    final bar = find.descendant(
        of: find.byType(FilterChipsBar), matching: find.byType(Scrollable));
    final pos = t.state<ScrollableState>(bar).position;
    pos.jumpTo(pos.maxScrollExtent);
    await t.pumpAndSettle();
    expect(chip(label), findsOneWidget);
  }

  /// عدّاد الشريحة بجانب تسميتها.
  String chipCount(WidgetTester t, String label) {
    final row = find.ancestor(of: chip(label), matching: find.byType(Row)).first;
    final texts = find.descendant(of: row, matching: find.byType(Text));
    return t.widget<Text>(texts.last).data ?? '';
  }

  simCase(_screen, 'default_hides_abandoned', (t, v) async {
    await open(t, v);
    expect(find.text('المشتركون'), findsOneWidget);
    expect(chipCount(t, 'الكل'), '4', reason: 'المهمَل خارج العدّ');
    expect(find.text('4 نتيجة'), findsOneWidget);
    expect(simText('علي حسن الموسوي'), findsWidgets);
    expect(find.textContaining('test1@alnoor-net'), findsNothing);
    expect(find.textContaining('karrada-shop'), findsNothing);
    await simCheck(t, v, _screen, 'default_hides_abandoned');
    await revealChip(t, 'مهمَل');
    expect(chipCount(t, 'مهمَل'), '3');
    await simCheck(t, v, _screen, 'default_chip_counts');
    await close(t);
  });

  simCase(_screen, 'neglected_filter', (t, v) async {
    await open(t, v);
    await revealChip(t, 'مهمَل');
    await t.tap(chip('مهمَل'));
    await t.pumpAndSettle();
    expect(find.text('3 نتيجة'), findsOneWidget);
    expect(find.textContaining('karrada-shop'), findsWidgets);
    expect(find.textContaining('new.sub.0912'), findsWidgets);
    expect(find.textContaining('test1@alnoor-net'), findsWidgets);
    expect(simText('علي حسن الموسوي'), findsNothing, reason: 'المهمَل وحده');
    expect(chipCount(t, 'مهمَل'), '3');
    await simCheck(t, v, _screen, 'neglected_filter');
    await close(t);
  });

  simCase(_screen, 'neglected_empty', (t, v) async {
    server.reply('GET', '/api/v2/subscribers', 200, {
      'success': true,
      'data': _subscribers.where((r) => r['abandoned'] != true).toList(),
    });
    await open(t, v);
    await revealChip(t, 'مهمَل');
    expect(chipCount(t, 'مهمَل'), '0');
    await t.tap(chip('مهمَل'));
    await t.pumpAndSettle();
    expect(simText('علي حسن الموسوي'), findsNothing);
    await simCheck(t, v, _screen, 'neglected_empty');
    await close(t);
  });
}
