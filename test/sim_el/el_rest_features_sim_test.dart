import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/api/el_card_order_gate.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/cards/cards_screen.dart';
import 'package:rad_mysvcs/screens/el/required_cards_screen.dart';
import 'package:rad_mysvcs/screens/reports/sessions_report_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/last_seen_card.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';
import 'package:rad_mysvcs/theme/spacing.dart';

import 'sim_harness.dart';

/// محاكاة «باقي ميزات ايرث لنك» في قائمة المشتركين وشاشة المشترك:
///   • آخر جهاز (MAC) على كرت **غير المتّصل** — من صفّ القائمة (`last_mac`،
///     callerID عند ايرث لنك) — ولا يُعرض للمتّصل.
///   • الحذف: ايرث لنك لا تسمح به ⇒ زرّ الحذف الجماعيّ وصفّ «حذف» بمكانهما
///     **مقفلَين بالسبب** (لا مخفيَّين، ولا «اطلبها من مديرك») — ولا طلب حذف.
///   • «آخر اتصال» في كارت المشترك غير المتّصل: الوقت وآخر جهاز (MAC).
///   • الموقع: «إضافة موقع» مفتوحٌ لمالك ايرث لنك (مخزنٌ محلّيّ على خادمنا).
///   • الجلسات: ملاحظة مصدر المنتهية (`ended` من الخادم) ومدّة كلّ جلسةٍ منتهية،
///     و«سجلّ الجلسات» لمشتركٍ بعينه (البحث باسمه كاملاً).
///   • الكارتات: مخزون ايرث لنك بالباقة (السلسلة = الباقة) — بأسمائها لا برموزها.
///   • «الكارتات المطلوبة»: الرصيد المطلوب بسعر الكارت (ما يحسب به «طلب
///     الكارتات»)، وكلفة التفعيل من الرصيد بجانبه حين تختلف.
const _screen = 'el_rest';
const _reason = 'ايرث لنك لا تسمح بحذف المشترك';

Map<String, Object?> _row(
  int idx,
  String user, {
  required String first,
  required String last,
  required String expiration,
  required int remaining,
  bool online = false,
  String? mac,
  String? lastOnline,
}) =>
    {
      'idx': '$idx',
      'username': user,
      'firstname': first,
      'lastname': last,
      'phone': '0770${1000000 + idx}',
      'profile_name': 'Economy',
      'profile_id': 7,
      'expiration': expiration,
      'remaining_days': remaining,
      'online_status': online ? 1 : 0,
      'is_online': online ? 1 : 0,
      'enabled': 1,
      if (mac != null) 'last_mac': mac,
      if (lastOnline != null) 'last_online': lastOnline,
      'latitude': null,
      'longitude': null,
    };

String _ago(Duration d) {
  final t = DateTime.now().subtract(d);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:00';
}

List<Map<String, Object?>> _rows() => [
      _row(1, 'ali1@alnoor-net',
          first: 'علي',
          last: 'حسن الموسوي',
          expiration: '2026-11-20 10:00:00',
          remaining: 33,
          online: true,
          mac: '68:FF:7B:8A:CD:11'),
      _row(2, 'zainab.k@alnoor-net',
          first: 'زينب',
          last: 'كاظم',
          expiration: '2026-11-14 08:00:00',
          remaining: 27,
          mac: '44:D1:FA:12:9B:07',
          lastOnline: _ago(const Duration(hours: 3))),
      _row(3, 'hussein77@alnoor-net',
          first: 'حسين',
          last: 'عبد الأمير',
          expiration: '2026-12-01 08:00:00',
          remaining: 44,
          mac: 'C4:AD:34:01:22:9F'),
      _row(4, 'mustafa.office@alnoor-net',
          first: 'مكتب',
          last: 'مصطفى للمحاماة',
          expiration: '2026-12-20 08:00:00',
          remaining: 63),
    ];

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    PermissionsService.debugSet(isEmployee: false);
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
    server.reply(
        'GET', '/api/v2/subscribers', 200, {'success': true, 'data': _rows()});
  });

  tearDown(() async {
    await ActiveCompany.clear();
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Future<void> openList(WidgetTester t, SimVariant v) async {
    await pumpSim(t, v,
        home: (_) => SubscribersScreen(isActive: ValueNotifier<bool>(true)));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  }

  List<String> deletes() => [
        for (final r in server.requests)
          if (r.method == 'DELETE') r.path,
      ];

  simCase(_screen, 'list_last_mac', (t, v) async {
    await openList(t, v);
    // غير المتّصل يحمل آخر جهاز؛ المتّصل لا (جلسته تقول جهازه).
    expect(simText('44:D1:FA:12:9B:07'), findsOneWidget);
    expect(simText('68:FF:7B:8A:CD:11'), findsNothing);
    expect(find.text('آخر جهاز'), findsNWidgets(2));
    expect(find.textContaining('آخر اتصال'), findsWidgets);
    await simCheck(t, v, _screen, 'list_last_mac');
    await close(t);
  });

  simCase(_screen, 'bulk_delete_locked', (t, v) async {
    await openList(t, v);
    await t.longPress(simText('زينب كاظم').first);
    await t.pumpAndSettle();
    final del = find.text('حذف');
    expect(del, findsOneWidget, reason: 'بمكانه — لا مخفيّ');
    await simCheck(t, v, _screen, 'bulk_delete_locked');
    await t.tap(del);
    await t.pump();
    expect(find.text(_reason), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(deletes(), isEmpty);
    await close(t);
  });

  simCase(_screen, 'detail_delete_locked_location_open', (t, v) async {
    final sub = Subscriber.fromJson(Map<String, dynamic>.from(_rows()[1]));
    await pumpSim(t, v,
        home: (_) => SubscriberDetailScreen(sub: sub), settle: false);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('المزيد'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    // «إضافة موقع» مفتوحٌ لمالك ايرث لنك.
    final sheetList = find
        .descendant(
            of: find.byType(BottomSheet), matching: find.byType(Scrollable))
        .first;
    await t.drag(sheetList, const Offset(0, -2000));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('إضافة موقع'), findsOneWidget);
    final del = find.descendant(
        of: find.byType(BottomSheet), matching: find.text('حذف'));
    expect(del, findsOneWidget);
    await simCheck(t, v, _screen, 'detail_more_sheet');
    await t.tap(del, warnIfMissed: false);
    await t.pump();
    expect(find.text(_reason), findsOneWidget);
    expect(find.text('إجراءات أخرى'), findsOneWidget, reason: 'الشيت باقٍ');
    await t.pump(const Duration(seconds: 3));
    expect(deletes(), isEmpty);
    await close(t);
  });

  // ───────────────────── «آخر اتصال» في كارت المشترك ─────────────────────

  // الكرت وحده بـ«الآن» ثابت — اللقطة لا تتغيّر بمرور الأيّام: الوقت + آخر
  // جهاز (ايرث لنك)، وآخر جهازٍ بلا وقت (ايرث لنك بلا جلسةٍ معروفة)، والوقت
  // وحده (SAS4 — لا MAC في قائمته).
  simCase(_screen, 'last_seen_card', (t, v) async {
    final now = DateTime(2026, 10, 18, 12, 20);
    Subscriber sub(Map<String, Object?> extra) => Subscriber.fromJson(
        Map<String, dynamic>.from({..._rows()[1], ...extra}));
    await pumpSim(t, v,
        home: (_) => Scaffold(
              backgroundColor: AppColors.bg,
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(Sp.lg),
                  children: [
                    LastSeenCard(
                        sub: sub({'last_online': '2026-10-18 09:12:00'}),
                        now: now),
                    LastSeenCard(sub: sub({'last_online': null}), now: now),
                    LastSeenCard(
                        sub: sub({
                          'last_online': '2026-10-15 07:40:00',
                          'last_mac': null,
                        }),
                        now: now),
                  ],
                ),
              ),
            ));
    expect(find.text('آخر اتصال'), findsNWidgets(3));
    expect(find.text('قبل 3 س'), findsOneWidget);
    expect(find.text('قبل 3 أيام'), findsOneWidget);
    expect(simText('44:D1:FA:12:9B:07'), findsNWidgets(2));
    await simCheck(t, v, _screen, 'last_seen_card');
  });

  // في كارت المشترك نفسه (بلا لقطة: وقته نسبيٌّ للآن الحقيقيّ): غير المتّصل
  // يحمل الكرت بلا فيضٍ ولا نصٍّ خامّ على كلّ عرض، والمتّصل لا.
  simCase(_screen, 'detail_last_seen', (t, v) async {
    Future<void> open(Map<String, Object?> row) async {
      final sub = Subscriber.fromJson(Map<String, dynamic>.from(row));
      await pumpSim(t, v,
          home: (_) => SubscriberDetailScreen(sub: sub), settle: false);
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(seconds: 1));
    }

    await open(_rows()[1]);
    final card = find.byType(LastSeenCard);
    await t.ensureVisible(card);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.descendant(of: card, matching: find.text('آخر اتصال')),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('قبل 3 س')),
        findsOneWidget);
    expect(
        find.descendant(of: card, matching: simText('44:D1:FA:12:9B:07')),
        findsOneWidget);
    expect(t.takeException(), isNull);
    expect(simRawTextViolations(), isEmpty);
    await close(t);

    // المتّصل: «معلومات الاتصال» تقول جلسته — لا كرت «آخر اتصال».
    await open(_rows()[0]);
    expect(find.text('آخر اتصال'), findsNothing);
    await close(t);
  });

  // ─────────────────────────── الجلسات ───────────────────────────

  Map<String, Object?> ended(String user, String start, String end,
          {required int id}) =>
      {
        'id': id,
        'username': user,
        'framedipaddress': '100.78.74.27',
        'callingstationid': '44:D1:FA:12:9B:07',
        'acctstarttime': start,
        'acctstoptime': end,
        'acctsessiontime': 3600,
        'acctinputoctets': 150 * 1024 * 1024,
        'acctoutputoctets': 2300 * 1024 * 1024,
        'acctterminatecause': '',
      };

  simCase(_screen, 'sessions_completed_unavailable', (t, v) async {
    server.reply('GET', '/api/v2/online-users', 200, {'success': true, 'data': []});
    server.reply('GET', '/api/v2/sessions', 200, {
      'success': true,
      'data': [
        {
          'id': 1,
          'username': 'ali1@alnoor-net',
          'framedipaddress': '100.78.74.20',
          'callingstationid': '68:FF:7B:8A:CD:11',
          'acctstarttime': '2026-10-18 09:12:00',
          'acctstoptime': '',
          'acctsessiontime': 3000,
        },
      ],
      'total': 1,
      'ended': {
        'supported': false,
        'source': 'completed',
        'window': 500,
        'partial': false,
        'range': null,
      },
    });
    await pumpSim(t, v, home: (_) => const SessionsReportScreen());
    await t.tap(find.text('الكل'));
    await t.pumpAndSettle();
    expect(find.textContaining('لا تعطي سجلّ الجلسات المنتهية'), findsOneWidget);
    await simCheck(t, v, _screen, 'sessions_completed_unavailable');
    // «متصلون الآن» بلا ملاحظة.
    await t.tap(find.text('متصلون الآن'));
    await t.pumpAndSettle();
    expect(find.textContaining('لا تعطي سجلّ الجلسات المنتهية'), findsNothing);
  });

  simCase(_screen, 'sessions_subscriber_history', (t, v) async {
    server.reply('GET', '/api/v2/sessions', 200, {
      'success': true,
      'data': [
        ended('zainab.k@alnoor-net', '2026-10-17 21:05:00', '2026-10-18 02:40:11',
            id: 1000000000001),
        ended('zainab.k@alnoor-net', '2026-10-16 08:00:00', '2026-10-16 13:30:00',
            id: 1000000000002),
      ],
      'total': 2,
      'ended': {
        'supported': true,
        'source': 'subscriber',
        'window': null,
        'partial': false,
        'range': {'startDate': '2026-09-19', 'endDate': '2026-10-18'},
      },
    });
    await pumpSim(t, v,
        home: (_) =>
            const SessionsReportScreen(initialUsername: 'zainab.k@alnoor-net'));
    final req = server.calls('GET', '/api/v2/sessions').single;
    expect(req.queryParameters['username'], 'zainab.k@alnoor-net');
    expect(server.calls('GET', '/api/v2/online-users'), isEmpty,
        reason: 'يفتح على «الكلّ»');
    expect(simText('سجلّ هذا المشترك من 2026/09/19 إلى 2026/10/18.'),
        findsOneWidget);
    expect(simText('2026/10/17 21:05 → 10/18 02:40'), findsOneWidget);
    expect(simText('2026/10/16 08:00 → 13:30'), findsOneWidget);
    await simCheck(t, v, _screen, 'sessions_subscriber_history');
  });

  simCase(_screen, 'detail_sessions_entry', (t, v) async {
    final sub = Subscriber.fromJson(Map<String, dynamic>.from(_rows()[1]));
    server.reply('GET', '/api/v2/sessions', 200,
        {'success': true, 'data': const [], 'total': 0});
    await pumpSim(t, v,
        home: (_) => SubscriberDetailScreen(sub: sub), settle: false);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    await t.tap(find.text('المزيد'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    final entry = find.descendant(
        of: find.byType(BottomSheet), matching: find.text('سجلّ الجلسات'));
    await t.ensureVisible(entry);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(entry);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    final req = server.calls('GET', '/api/v2/sessions').single;
    expect(req.queryParameters['username'], 'zainab.k@alnoor-net');
    await close(t);
  });

  // ─────────────────────────── الكارتات ───────────────────────────

  simCase(_screen, 'cards_el_packages', (t, v) async {
    CardsState.reset();
    server.reply('GET', '/api/v2/cards/summary', 200, {
      'success': true,
      'enabled': true,
      'source': 'earthlink',
      'totals': {'remaining': 17, 'used': 40, 'qty': 60, 'series': 2},
      'profiles': [
        {'profile_id': 7, 'profile_name': 'Economy', 'value': 22000, 'remaining': 12, 'qty': 40, 'used': 28, 'series': 1},
        {'profile_id': 12, 'profile_name': 'Ta3leem 50,000 Plus 3 Months', 'value': 95000, 'remaining': 5, 'qty': 20, 'used': 12, 'series': 1},
      ],
      'series': [
        {'series': 'el-7', 'type': 0, 'profile_id': 7, 'profile_name': 'Economy', 'value': 22000, 'qty': 40, 'used': 28, 'remaining': 12, 'expiration': null, 'expired': false, 'suspended': false, 'created_at': null},
        {'series': 'el-12', 'type': 0, 'profile_id': 12, 'profile_name': 'Ta3leem 50,000 Plus 3 Months', 'value': 95000, 'qty': 20, 'used': 12, 'remaining': 5, 'expiration': null, 'expired': false, 'suspended': false, 'created_at': null},
      ],
      // قراءةٌ لم تكتمل (سقف الكروت/المهلة عند الخادم) ⇒ تُقال تحت المجموع.
      'partial': true,
      'updated_at': '2026-10-18T11:00:00.000Z',
    });
    server.reply('GET', '/api/v2/cards/series/el-7', 200, {
      'success': true,
      'series': {'series': 'el-7', 'type': 0, 'profile_id': 7, 'profile_name': 'Economy', 'value': 22000, 'qty': 40, 'used': 28, 'remaining': 12},
      'cards': [
        {'id': 123456789, 'serial_tail': '4821', 'used': false, 'available': true, 'status': 'Active', 'used_at': null, 'subscriber': null},
        {'id': 223456789, 'serial_tail': '1177', 'used': true, 'available': false, 'status': 'Used', 'used_at': '2026-10-17 18:20:00', 'subscriber': {'id': null, 'username': 'ali1@alnoor-net'}},
      ],
      'total': 40,
      'page': 1,
      'count': 50,
    });
    await pumpSim(t, v, home: (_) => const CardsScreen());
    // السلاسل = الباقات: قسمٌ واحد «حسب الباقة» بأسمائها — لا «el-7».
    expect(find.text('حسب الباقة'), findsOneWidget);
    expect(find.text('السلاسل'), findsNothing);
    expect(find.textContaining('el-'), findsNothing);
    expect(find.text('Economy'), findsOneWidget);
    expect(simText('المخزون أكبر ممّا قُرئ — الأرقام لأوّل 60 كارت.'),
        findsOneWidget);
    await simCheck(t, v, _screen, 'cards_el_packages');
    await t.tap(find.text('Economy'));
    await t.pumpAndSettle();
    expect(find.text('كارتات Economy'), findsOneWidget);
    expect(find.textContaining('el-'), findsNothing);
    expect(find.text('••4821'), findsOneWidget);
    await simCheck(t, v, _screen, 'cards_el_series_sheet');
    CardsState.reset();
  });

  simCase(_screen, 'required_cards_card_price', (t, v) async {
    // سعر الكارت (card_price — prices/forreseller) للرصيد المطلوب، بالسعر نفسه الذي
    // يحسب به «طلب الكارتات»؛ وكلفة التفعيل (cost) سطرٌ ثانٍ حين تختلف. باقةٌ بلا
    // سعر (null) ⇒ كلفتها وحدها كما كان.
    server.on('GET', '/api/v2/el/prepaid-needed', (o) => const SimReply(200, {
          'success': true,
          'days': 1,
          'data': [
            {'profile_id': 7, 'name': 'Economy', 'cost': 20000, 'card_price': 22000, 'available': 12, 'used': 30, 'needed': 18, 'image': null},
            {'profile_id': 9, 'name': 'Plus', 'cost': 34000, 'card_price': null, 'available': 1, 'used': 9, 'needed': 8, 'image': null},
          ],
        }));
    // «طلب الكارتات» مفتوحٌ بالخادم ⇒ زرّ «اطلب هذه الكارتات» في اللقطة.
    ElCardOrderGate.reset();
    server.reply('POST', '/api/v2/el/card-order/quote', 400,
        {'success': false, 'message': 'حدّد الباقة والعدد'});
    await pumpSim(t, v, home: (_) => const ElRequiredCardsScreen());
    expect(find.text('الرصيد المطلوب (بسعر الكارت)'), findsOneWidget);
    // ١٨ × ٢٢٬٠٠٠ + ٨ × ٣٤٬٠٠٠ = ٦٦٨٬٠٠٠
    expect(find.text('668,000'), findsOneWidget);
    expect(find.text('سعر الكارت 22,000 د.ع'), findsOneWidget);
    expect(find.text('التفعيل من الرصيد 20,000 د.ع'), findsOneWidget);
    expect(find.text('كلفة الكارت 34,000 د.ع'), findsOneWidget);
    expect(find.text('396,000 د.ع'), findsOneWidget, reason: 'رصيد Economy بسعر الكارت');
    await simCheck(t, v, _screen, 'required_cards_card_price');
  });
}
