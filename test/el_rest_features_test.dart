import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/api/earthlink_api.dart';
import 'package:rad_mysvcs/api/employees_api.dart';
import 'package:rad_mysvcs/api/reports_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/dashboard/widgets/stats_grid.dart';
import 'package:rad_mysvcs/screens/el/required_cards_screen.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/screens/reports/sessions_report_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/location_sheets.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/last_seen_card.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_limits.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'sim_el/sim_harness.dart';

/// «باقي ميزات ايرث لنك» (البند ٦، ١٨ أكتوبر) — ما لا يحتاج رسماً كاملاً:
/// المحلّلات المتسامحة، وما يمنعه المزوّد لا الصلاحيّة. و(١٩ أكتوبر) «طلب
/// الكارتات» أُلغي نهائيّاً والحذف مخفيٌّ لايرث لنك: لا بطاقة ولا زرّ لهما.
void main() {
  tearDown(() {
    ProviderService.debugSet(null);
    PermissionsService.debugReset();
  });

  // ═══════════════════════ آخر جهاز ═══════════════════════
  group('آخر MAC من صفّ القائمة', () {
    Subscriber sub(Map<String, Object?> extra) => Subscriber.fromJson({
          'idx': '9',
          'username': 'u9@el',
          'firstname': 'علي',
          'lastname': '',
          ...extra,
        });

    test('last_mac أوّلاً ثمّ البدائل، والفراغ «لا شيء»', () {
      expect(sub({'last_mac': '44:D1:FA:12:9B:07'}).lastMac, '44:D1:FA:12:9B:07');
      expect(sub({'mac': 'AA:BB:CC:DD:EE:FF'}).lastMac, 'AA:BB:CC:DD:EE:FF');
      expect(sub({'callingstationid': '11:22:33:44:55:66'}).lastMac,
          '11:22:33:44:55:66');
      expect(sub({'last_mac': '  ', 'mac': 'AA:BB:CC:DD:EE:FF'}).lastMac,
          'AA:BB:CC:DD:EE:FF');
      expect(sub({'last_mac': null}).lastMac, isNull);
      expect(sub({}).lastMac, isNull, reason: 'صفّ SAS4 كما كان');
    });

    test('يبقى عبر نسخ الإثراء (الباقات/الجلسة/الموقع)', () {
      final s = sub({'last_mac': '44:D1:FA:12:9B:07', 'profile_id': 7});
      expect(s.enrichWithPackages(const {}).lastMac, '44:D1:FA:12:9B:07');
      expect(s.copyWithOnline(online: false).lastMac, '44:D1:FA:12:9B:07');
      expect(s.copyWithLocation(latitude: 1, longitude: 2).lastMac,
          '44:D1:FA:12:9B:07');
    });
  });

  // ═══════════════════ «آخر اتصال» في كارت المشترك ═══════════════════
  group('«آخر اتصال» في كارت المشترك', () {
    Subscriber sub(Map<String, Object?> extra) => Subscriber.fromJson({
          'idx': '9',
          'username': 'u9@el',
          'firstname': 'علي',
          'lastname': '',
          ...extra,
        });

    test('غير المتّصل: الوقت وآخر جهاز؛ والمتّصل والفارغ بلا كرت', () {
      final f = LastSeenCard.factsOf(sub({
        'last_online': '2026-10-18 09:12:00',
        'last_mac': '44:D1:FA:12:9B:07',
      }))!;
      expect(f.at, DateTime(2026, 10, 18, 9, 12),
          reason: 'توقيت الساس/ايرث لنك بغداديٌّ عارٍ — يُقرأ محلّيّاً');
      expect(f.mac, '44:D1:FA:12:9B:07');
      // المتّصل: «معلومات الاتصال» تقول جلسته — لا كرت.
      expect(
          LastSeenCard.factsOf(sub({
            'last_online': '2026-10-18 09:12:00',
            'last_mac': '44:D1:FA:12:9B:07',
            'online_status': 1,
          })),
          isNull);
      expect(LastSeenCard.factsOf(sub({})), isNull, reason: 'لا شيء يُعرض');
      expect(LastSeenCard.factsOf(sub({'last_online': '0000-00-00 00:00:00'})),
          isNull,
          reason: 'صفر الساس غيابٌ لا تاريخ');
      // SAS4 بلا MAC في القائمة: الوقت وحده.
      final sas = LastSeenCard.factsOf(sub({'last_online': '2026-10-01 07:00:00'}))!;
      expect(sas.mac, isNull);
      // ايرث لنك بلا وقتٍ معروف: آخر جهاز وحده.
      final macOnly =
          LastSeenCard.factsOf(sub({'last_mac': ' AA:BB:CC:DD:EE:FF '}))!;
      expect(macOnly.at, isNull);
      expect(macOnly.mac, 'AA:BB:CC:DD:EE:FF');
      expect(LastSeenCard.dateTimeText(DateTime(2026, 10, 7, 21, 5)),
          '2026/10/07 · 21:05');
    });

    testWidgets('الكرت: «قبل…» والتاريخ، و«آخر جهاز» يُنسخ بنقرة', (t) async {
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      final s = sub({
        'last_online': '2026-10-18 09:12:00',
        'last_mac': '44:D1:FA:12:9B:07',
      });
      await t.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: LastSeenCard(sub: s, now: DateTime(2026, 10, 18, 12, 20)),
          ),
        ),
      ));
      expect(find.text('آخر اتصال'), findsOneWidget);
      expect(find.text('قبل 3 س'), findsOneWidget);
      expect(find.text('2026/10/18 · 09:12'), findsOneWidget);
      expect(find.text('44:D1:FA:12:9B:07'), findsOneWidget);
      await t.tap(find.text('44:D1:FA:12:9B:07'));
      await t.pump();
      expect(copied, '44:D1:FA:12:9B:07');
      await t.pump(const Duration(seconds: 3));

      // متّصل ⇒ لا شيء.
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LastSeenCard(
              sub: sub({'last_mac': '44:D1:FA:12:9B:07', 'online_status': 1})),
        ),
      ));
      expect(find.text('آخر اتصال'), findsNothing);
    });
  });

  // ═══════════════ «الكارتات N» تحت الرصيد المقفل ═══════════════
  group('«الكارتات N» تحت الرصيد المقفل — لكلّ المزوّدين', () {
    const v = SimVariant(360, dark: false);
    setUpAll(simSetUpAll);
    tearDown(CardsState.reset);

    testWidgets('موظّف ايرث لنك بلا reports.financial: السطر بشارةٍ مفعّلة',
        (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(
          isEmployee: true,
          permissions: const {'subscribers.view': true, 'subscribers.activate': true});
      CardsState.set(const CardsBadge(enabled: true, remaining: 17));
      await pumpSim(t, v,
          home: (_) => const Scaffold(
                body: StatsGrid(
                    wallet: null,
                    debtors: null,
                    balanceLocked: true,
                    debtLocked: true),
              ));
      expect(find.byType(LockedCard), findsNWidgets(2));
      expect(find.textContaining('17'), findsOneWidget);
      AppColors.setDarkMode(false);
    });

    testWidgets('حسابٌ بلا مخزون (الشارة مطفأة): لا سطر', (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'subscribers.activate': true});
      CardsState.set(const CardsBadge(enabled: false, remaining: null));
      await pumpSim(t, v,
          home: (_) => const Scaffold(
                body: StatsGrid(
                    wallet: null,
                    debtors: null,
                    balanceLocked: true,
                    debtLocked: true),
              ));
      expect(find.byType(LockedCard), findsNWidgets(2));
      expect(find.textContaining('الكارتات'), findsNothing);
      AppColors.setDarkMode(false);
    });
  });

  // ═══════════════════════ مخزون الكارتات ═══════════════════════
  test('ملخّص الكارتات: ايرث لنك بالباقة، و«غير متاح» بسببه، والجزئيّ يُعلَّم', () {
    final el = CardsSummary.fromJson({
      'success': true,
      'enabled': true,
      'source': 'earthlink',
      'totals': {'remaining': 17, 'used': 40, 'qty': 60, 'series': 2},
      'profiles': const [],
      'series': const [],
      'partial': true,
    });
    expect(el.seriesArePackages, isTrue);
    expect(el.partial, isTrue);
    expect(el.unsupportedMessage, isNull);
    final off = CardsSummary.fromJson({
      'success': true,
      'enabled': false,
      'source': 'earthlink',
      'unsupported': true,
      'message': 'ايرث لنك لا تعرض مخزون الكروت لهذا الحساب',
      'totals': {'remaining': 0, 'used': 0, 'qty': 0, 'series': 0},
      'profiles': const [],
      'series': const [],
    });
    expect(off.enabled, isFalse);
    expect(off.unsupportedMessage, 'ايرث لنك لا تعرض مخزون الكروت لهذا الحساب');
    // SAS4 كما كان: بلا مصدر ولا «جزئيّ».
    final sas = CardsSummary.fromJson({
      'success': true,
      'enabled': true,
      'totals': {'remaining': 3},
      'profiles': const [],
      'series': const [],
    });
    expect(sas.seriesArePackages, isFalse);
    expect(sas.partial, isFalse);
  });

  // ═══════════════════════ الجلسات ═══════════════════════
  group('سجلّ الجلسات المنتهية', () {
    test('ملاحظة المصدر من `ended` (ايرث لنك)، ولا شيء لـSAS4', () {
      Map<String, dynamic> body(Map<String, Object?> ended) =>
          {'success': true, 'data': const [], 'ended': ended};
      // SAS4 لا يرسل ended ⇒ كما كان.
      expect(ReportsApi.sessionsHistoryNote({'success': true, 'data': []}),
          isNull);
      // علم القدرة وحده (بلا `ended`): نصّ الخادم، وإلّا «الحيّة فقط».
      expect(
          ReportsApi.sessionsHistoryNote({
            'success': true,
            'history_available': false,
            'history_note': 'ايرث لنك: الحيّة فقط',
          }),
          'ايرث لنك: الحيّة فقط');
      expect(
          ReportsApi.sessionsHistoryNote(
              {'success': true, 'history_available': false}),
          contains('الجلسات الحيّة فقط'));
      expect(
          ReportsApi.sessionsHistoryNote(
              {'success': true, 'history_available': true}),
          isNull);
      expect(
          ReportsApi.sessionsHistoryNote(body({'supported': false})),
          contains('لا تعطي سجلّ الجلسات المنتهية'));
      expect(ReportsApi.sessionsHistoryNote(body({'supported': null})),
          contains('تعذّر جلب الجلسات المنتهية'));
      expect(
          ReportsApi.sessionsHistoryNote(body({
            'supported': true,
            'source': 'subscriber',
            'range': {'startDate': '2026-09-19', 'endDate': '2026-10-18'},
          })),
          'سجلّ هذا المشترك من \u20682026/09/19\u2069 إلى \u20682026/10/18\u2069.');
      expect(
          ReportsApi.sessionsHistoryNote(body({
            'supported': true,
            'source': 'completed',
            'window': 500,
            'partial': true,
          })),
          startsWith('آخر 500 جلسة منتهية'));
      // كاملةٌ بلا قصّ ⇒ لا ملاحظة.
      expect(
          ReportsApi.sessionsHistoryNote(body({
            'supported': true,
            'source': 'completed',
            'window': 500,
            'partial': false,
          })),
          isNull);
    });

    test('مدّة الجلسة المنتهية بتوقيت الساس، والحيّة والصفريّة بلا سطر', () {
      SessionRow row(Map<String, Object?> j) =>
          SessionRow.fromJson(Map<String, dynamic>.from(j))!;
      expect(
        sessionSpanText(row({
          'radacctid': 1,
          'username': 'a',
          'acctstarttime': '2026-10-18 09:12:00',
          'acctstoptime': '2026-10-18 14:40:30',
        })),
        '2026/10/18 09:12 → 14:40',
        reason: 'نهايةٌ في اليوم نفسه بساعتها وحدها',
      );
      expect(
        sessionSpanText(row({
          'radacctid': 4,
          'username': 'a',
          'acctstarttime': '2026-10-17 21:05:00',
          'acctstoptime': '2026-10-18 02:40:11',
        })),
        '2026/10/17 21:05 → 10/18 02:40',
      );
      // حيّة (لا انتهاء) ⇒ لا سطر.
      expect(
          sessionSpanText(row({
            'radacctid': 2,
            'username': 'a',
            'acctstarttime': '2026-10-18 09:12:00',
            'acctstoptime': '',
          })),
          isNull);
      // «0000-…» غيابٌ لا تاريخ.
      expect(
          sessionSpanText(row({
            'radacctid': 3,
            'username': 'a',
            'acctstarttime': '0000-00-00 00:00:00',
            'acctstoptime': '2026-10-18 14:40:30',
          })),
          '2026/10/18 14:40');
    });
  });

  // ═══════════════════════ الكارتات المطلوبة ═══════════════════════
  group('«الكارتات المطلوبة» — النموذج', () {
    test('«الكارتات المطلوبة»: سعر الكارت (ما تُشترى به) للرصيد المطلوب، والكلفة احتياطاً', () {
      final withPrice = ElNeededCard.fromJson(const {
        'profile_id': 7,
        'name': 'Economy',
        'cost': 20000,
        'card_price': 22000,
        'available': 2,
        'used': 10,
        'needed': 8,
      })!;
      expect(withPrice.cardPrice, 22000);
      expect(withPrice.unitPrice, 22000);
      expect(withPrice.balanceNeeded, 176000, reason: '8 × سعر الكارت لا الكلفة');
      final older = ElNeededCard.fromJson(const {
        'profile_id': 7,
        'name': 'Economy',
        'cost': 20000,
        'needed': 8,
      })!;
      expect(older.cardPrice, isNull, reason: 'خادمٌ أقدم بلا السعر');
      expect(older.balanceNeeded, 160000);
      expect(
          ElNeededCard.fromJson(const {'profile_id': 7, 'cost': 20000, 'card_price': 0})!
              .cardPrice,
          isNull);
    });
  });

  // ═══════════════════════ شارة الكارتات ═══════════════════════
  test('شارة admin-widgets بلا enabled (حالةٌ لم تُعرف) لا تُقرأ «غير متاح»', () {
    expect(CardsBadge.fromJson(const {'remaining': null}), isNull);
    expect(CardsBadge.fromJson(const {'enabled': null, 'remaining': 3}), isNull);
    expect(CardsBadge.fromJson(const {'enabled': false, 'remaining': null}),
        const CardsBadge(enabled: false));
    expect(CardsBadge.fromJson(const {'enabled': true, 'remaining': 4}),
        const CardsBadge(enabled: true, remaining: 4));
    CardsState.reset();
    CardsState.set(const CardsBadge(enabled: true, remaining: 9));
    CardsState.applyAdminWidgets(const {'remaining': null});
    expect(CardsState.badge.value, const CardsBadge(enabled: true, remaining: 9),
        reason: 'ما نعرفه يبقى');
    expect(CardsState.isLive, isFalse, reason: 'فيُسأل الملخّص (ensureKnown)');
    CardsState.reset();
  });

  // ═══════════════════════ ما يمنعه المزوّد ═══════════════════════
  group('الحذف والموقع', () {
    test('الحذف: مخفيٌّ لجلسة ايرث لنك (قرار المالك ١٩ أكتوبر)، وكما كان لـSAS4 وFTTH', () {
      ProviderService.debugSet('earthlink');
      expect(subscriberDeleteHidden(), isTrue);
      ProviderService.debugSet(null);
      expect(subscriberDeleteHidden(), isFalse);
      ProviderService.debugSet('ftth');
      expect(subscriberDeleteHidden(), isFalse);
    });

    test('الموقع لايرث لنك كالساس: بالصلاحيّة وحدها', () {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(isEmployee: false);
      expect(canEditLocation(), isTrue, reason: 'المالك');
      PermissionsService.debugSet(
          isEmployee: true,
          permissions: const {'subscribers.edit_location': true});
      expect(canEditLocation(), isTrue);
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'subscribers.view': true});
      expect(canEditLocation(), isFalse);
      // ويُمنح لموظّف ايرث لنك (فيظهر مقفلاً بمكانه لمن لا يملكه).
      expect(ElEmployeePerms.keys, contains('subscribers.edit_location'));
      expect(permShown(const ['subscribers.edit_location']), isTrue);
    });
  });

  // ═══════════════════════ «طلب الكارتات» أُلغي ═══════════════════════
  // قرار المالك ١٩ أكتوبر: لا بطاقة في «قوائم أخرى» ولا زرّ في «الكارتات
  // المطلوبة» — لأحدٍ (مالكاً أو موظّفاً) — ولا نداء لمسارات الطلب أصلاً.
  group('«طلب الكارتات» أُلغي — لا مدخل له', () {
    Finder byTypeName(String name) =>
        find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

    Future<void> showMore(WidgetTester t) async {
      t.view.physicalSize = const Size(800, 3200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(
        home: Directionality(
            textDirection: TextDirection.rtl, child: MoreModulesScreen()),
      ));
      await t.pump();
    }

    Finder orderCard() => find.ancestor(
        of: find.byIcon(LucideIcons.shoppingCart),
        matching: byTypeName('_ModuleCard'));

    testWidgets('مالك ايرث لنك: لا بطاقة «طلب الكارتات» — والتحويل باقٍ', (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(isEmployee: false);
      await showMore(t);
      expect(orderCard(), findsNothing);
      expect(find.text('طلب الكارتات'), findsNothing);
      expect(find.text('تحويل الرصيد'), findsOneWidget);
      expect(find.text('الكارتات المطلوبة'), findsOneWidget);
    });

    testWidgets('موظّف ايرث لنك وشركات SAS4: لا بطاقة', (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'reports.financial': true});
      await showMore(t);
      expect(orderCard(), findsNothing);
      ProviderService.debugSet(null);
      PermissionsService.debugSet(isEmployee: false);
      await showMore(t);
      expect(orderCard(), findsNothing);
    });
  });

  group('«الكارتات المطلوبة» توقّعٌ للعرض فقط', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp();
      ProviderService.debugSet('earthlink');
      server.reply('GET', '/api/v2/el/prepaid-needed', 200, {
        'success': true,
        'data': [
          {'profile_id': 7, 'name': 'Economy', 'cost': 20000, 'available': 1, 'used': 9, 'needed': 8},
          {'profile_id': 13, 'name': 'Business Pro 100M', 'cost': 180000, 'available': 3, 'used': 0, 'needed': 0},
        ],
      });
    });

    const v = SimVariant(390, dark: false);

    testWidgets('المالك: لا زرّ «اطلب هذه الكارتات» ولا نداء لمسارات الطلب', (t) async {
      PermissionsService.debugSet(isEmployee: false);
      await pumpSim(t, v, home: (_) => const ElRequiredCardsScreen());
      expect(find.text('Economy'), findsOneWidget);
      expect(find.text('اطلب هذه الكارتات من ايرث لنك'), findsNothing);
      expect(find.byIcon(LucideIcons.shoppingCart), findsNothing);
      expect(server.requests.where((r) => r.path.contains('/el/card-order')),
          isEmpty);
      AppColors.setDarkMode(false);
    });

    testWidgets('الموظّف: كذلك', (t) async {
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'reports.financial': true});
      await pumpSim(t, v, home: (_) => const ElRequiredCardsScreen());
      expect(find.text('Economy'), findsOneWidget);
      expect(find.text('اطلب هذه الكارتات من ايرث لنك'), findsNothing);
    });
  });
}
