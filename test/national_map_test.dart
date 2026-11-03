import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_map_api.dart';
import 'package:rad_mysvcs/screens/national/national_map_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «خريطة المشتركين» للوطني في التطبيق (٢ نوفمبر — نسخة الموقع WataniMap/watani-map/watani-geo): الشجرة زونات ← فاتات ← مشتركين
/// بحالاتهم ومنافذهم، و«بلا FAT»/«لم يُعرف بعد» آخراً، ومرجع موقع الفات «FAT7-FBG2251»، والبحث يجد المشترك والزون والفات.
const _v = SimVariant(390, dark: false);

Map<String, dynamic> _sub(String idx, String name, {String zone = 'FBG2251-2', String status = 'Active', bool suspended = false, int days = 10, bool online = false}) => {
      'idx': idx,
      'username': 'u$idx',
      'firstname': name,
      'remaining_days': days,
      'is_online': online ? 1 : 0,
      'parent_username': zone,
      'watani': {'zone': zone, 'zoneId': zone, 'status': status, 'suspended': suspended},
    };

void main() {
  test('الشجرة: الزون الأكبر أوّلاً، والفاتات المعروفة بالأكثر ثمّ «بلا FAT» ثمّ «لم يُعرف بعد»، والمشتركون بالمنفذ', () {
    final rows = [
      for (final s in [
        _sub('1', 'علي', days: 5, online: true),
        _sub('2', 'حسن', status: 'Expired', days: -2),
        _sub('3', 'زينب', suspended: true),
        _sub('4', 'سارة'),
        _sub('5', 'مريم', zone: 'FBG2260-5'),
      ])
        MapRow(raw: s),
    ];
    final items = {
      '1': const MapFatInfo(fatId: 'f7', fatName: 'FAT7', fdtName: 'FBG2251-2', port: 3),
      '2': const MapFatInfo(fatId: 'f7', fatName: 'FAT7', fdtName: 'FBG2251-2', port: 1),
      '3': const MapFatInfo(), // بلا FAT في البوّابة
      '5': const MapFatInfo(fatId: 'f2', fatName: 'FAT2', fdtName: 'FBG2260-5', port: 8),
    };
    final t = buildNationalMap(rows, items);
    expect(t.zones.map((z) => (z.name, z.total)).toList(), [('FBG2251-2', 4), ('FBG2260-5', 1)]);
    expect((t.totals.total, t.totals.active, t.totals.suspended, t.totals.expired, t.totals.online), (5, 3, 1, 1, 1));
    final z = t.zones.first;
    expect(z.fats.map((f) => (f.name, f.kind, f.total)).toList(), [
      ('FAT7', MapFatKind.fat, 2),
      (mapNoFat, MapFatKind.nofat, 1),
      (mapPendingFat, MapFatKind.pending, 1),
    ]);
    expect(z.fats.first.ports, [1, 3]);
    expect(z.fats.first.rows.map((r) => r.name).toList(), ['حسن', 'علي'], reason: 'بالمنفذ');
    expect((z.fatCount, z.pending, t.fatCount), (1, 1, 2));
  });

  test('مراجع المواقع: كود الزون ورقم الفات ومرجعه الموحّد كالموقع', () {
    expect(geoZoneCode('FBG2251-2'), 'FBG2251');
    expect(geoZoneCode('FAT7-FBG2251'), 'FBG2251');
    expect(geoFatNumber('FAT-07'), 7);
    expect(geoFatRef('FAT7', 'FBG2251-2'), 'FAT7-FBG2251');
    expect(geoFatRef('fat 12', null), isNull);
    final g = GeoPlace.from({'ref': 'FBG2251', 'name': 'زون', 'point': null, 'polygon': [[33.1, 44.2], [33.2, 44.3], [33.3, 44.1]]})!;
    expect((g.hasPoint, g.polygon.length), (false, 3));
  });

  group('الشاشة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      NationalMapScreen.debugNoTiles = true;
    });
    tearDown(() {
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });

    void routes() {
      server.reply('GET', '/api/v2/subscribers', 200, {
        'success': true,
        'data': [_sub('1', 'علي حسن', online: true), _sub('2', 'زينب كاظم', status: 'Expired', days: -3), _sub('5', 'مريم', zone: 'FBG2260-5')],
      });
      server.reply('GET', '/api/v2/ftth/fat-map', 200, {
        'success': true,
        'data': {
          'items': {
            '1': {'fat': {'id': 'f7', 'name': 'FAT7'}, 'fdt': {'id': 'd1', 'name': 'FBG2251-2'}, 'port': 3},
            '2': {'fat': {'id': 'f7', 'name': 'FAT7'}, 'fdt': {'id': 'd1', 'name': 'FBG2251-2'}, 'port': 1},
            '5': {'fat': {'id': 'f2', 'name': 'FAT2'}, 'fdt': {'id': 'd2', 'name': 'FBG2260-5'}, 'port': 8},
          },
          'known': 3,
          'total': 3,
          'warming': false,
        },
      });
      server.reply('GET', '/api/v2/ftth/geo', 200, {
        'success': true,
        'data': {
          'zones': [
            {'ref': 'FBG2251', 'name': 'FBG2251', 'point': {'lat': 33.22, 'lng': 44.53}, 'polygon': null},
          ],
          'fats': [
            {'ref': 'FAT7-FBG2251', 'name': 'FAT7-FBG2251', 'point': {'lat': 33.229, 'lng': 44.532}, 'polygon': null},
          ],
        },
      });
    }

    testWidgets('المخطّط: المجاميع والزونات، والزون يُفتح بفاتاته، والفات بمشتركيه وموقعه', (t) async {
      routes();
      await pumpSim(t, _v, home: (_) => const NationalMapScreen());
      await t.pumpAndSettle();
      expect(find.text('خريطة المشتركين'), findsOneWidget);
      expect(find.text('FBG2251-2'), findsOneWidget);
      expect(find.text('2 مشترك'), findsOneWidget);
      await t.tap(find.text('FBG2251-2'));
      await t.pumpAndSettle();
      expect(find.text('FAT7'), findsOneWidget);
      expect(find.textContaining('المنافذ: 1، 3'), findsOneWidget);
      await t.tap(find.text('FAT7'));
      await t.pumpAndSettle();
      expect(find.text('زينب كاظم'), findsOneWidget);
      expect(find.text('علي حسن'), findsOneWidget);
      expect(find.text('نسخ الإحداثيّات'), findsOneWidget, reason: 'للفات موقعٌ من KML');
      await simDrain(t);
    });

    testWidgets('البحث: الاسم والزون والفات من مكانٍ واحد', (t) async {
      routes();
      await pumpSim(t, _v, home: (_) => const NationalMapScreen());
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'زينب');
      await t.pumpAndSettle();
      expect(find.text('زينب كاظم'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'fat2');
      await t.pumpAndSettle();
      expect(find.text('FAT2'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, '2260');
      await t.pumpAndSettle();
      expect(find.text('FBG2260-5'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('الخريطة (ويندوز): البحث يبقى عليها بنتائجه، والمشترك ⇒ بطاقته بموقع فاته لا انتقالٌ لتبويبٍ آخر', (t) async {
      routes();
      await pumpSim(t, _v, home: (_) => const NationalMapScreen());
      await t.pumpAndSettle();
      await t.tap(find.text('الخريطة'));
      await t.pumpAndSettle();
      expect(find.text('FBG2251 · 2'), findsOneWidget, reason: 'علامة الزون بعدد مشتركيه');
      expect(find.text('FAT7 · 2'), findsOneWidget, reason: 'علامة الفات بعدد مشتركيه');
      expect(find.byTooltip('تكبير'), findsOneWidget);
      expect(find.byTooltip('عرض الكلّ'), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'زينب');
      await t.pumpAndSettle();
      expect(find.text('زينب كاظم'), findsOneWidget);
      expect(find.text('FBG2251 · 2'), findsOneWidget, reason: 'ما زلنا على الخريطة (لم ننتقل للمخطّط)');
      await t.tap(find.text('زينب كاظم'));
      await t.pumpAndSettle();
      expect(find.text('تفاصيل المشترك'), findsOneWidget);
      expect(find.text('منتهٍ'), findsWidgets);
      expect(find.text('نسخ الإحداثيّات'), findsOneWidget, reason: 'موقع فاته FAT7 من KML');
      await simDrain(t);
    });

    testWidgets('الخريطة: مشتركٌ فاته بلا موقع ⇒ بطاقته تقول ذلك ومعها «تفاصيل المشترك»', (t) async {
      routes();
      await pumpSim(t, _v, home: (_) => const NationalMapScreen());
      await t.pumpAndSettle();
      await t.tap(find.text('الخريطة'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'مريم');
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byType(InkWell), matching: find.text('مريم')).first);
      await t.pumpAndSettle();
      expect(find.textContaining('لا موقع لفاته'), findsOneWidget);
      expect(find.text('تفاصيل المشترك'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('المفتاح مطفأ: رسالة الخادم بمكانها بلا «إعادة المحاولة»', (t) async {
      server.reply('GET', '/api/v2/subscribers', 200, {'success': true, 'data': []});
      server.reply('GET', '/api/v2/ftth/fat-map', 409, {'success': false, 'code': 'MAP_OFF', 'message': 'خريطة المشتركين غير مفعّلة لحسابك بعد'});
      server.reply('GET', '/api/v2/ftth/geo', 409, {'success': false, 'code': 'GEO_OFF', 'message': 'x'});
      await pumpSim(t, _v, home: (_) => const NationalMapScreen());
      await t.pumpAndSettle();
      expect(find.text('خريطة المشتركين غير مفعّلة لحسابك بعد'), findsOneWidget);
      expect(find.text('إعادة المحاولة'), findsNothing);
      await simDrain(t);
    });
  });
}
