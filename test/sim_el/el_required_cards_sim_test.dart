import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/el_card_order_gate.dart';
import 'package:rad_mysvcs/screens/el/required_cards_screen.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// محاكاة «الكارتات المطلوبة» لايرث لنك (`el/required_cards_screen.dart`):
/// الهيكل أثناء الجلب، يوم/٣ أيام/أسبوع/شهر (كلٌّ بطلبه `days=`)، الصفوف
/// بأسماء باقاتٍ حقيقيّة طويلة وأرقامٍ كبيرة، الفراغ، الخطأ وإعادة المحاولة،
/// وفشل التحديث فوق بياناتٍ معروضة.
const _screen = 'el_required_cards';
const _path = '/api/v2/el/prepaid-needed';

/// صفوفٌ بشكل الخادم (earthlinkAdapter.getPrepaidNeeded).
List<Map<String, Object?>> _rows(int scale) => [
      {
        'profile_id': 7,
        'name': 'Economy',
        'cost': 20000,
        'available': 12,
        'used': 30 * scale,
        'needed': 18 * scale,
        'image': null,
      },
      {
        'profile_id': 12,
        'name': 'Ta3leem 50,000 Plus 3 Months (طلاب الجامعات)',
        'cost': 93000,
        'available': 0,
        'used': 4 * scale,
        'needed': 4 * scale,
        'image': null,
      },
      {
        'profile_id': 13,
        'name': 'Business Pro 100M',
        'cost': 180000,
        'available': 3,
        'used': 0,
        'needed': 0,
        'image': null,
      },
      {
        'profile_id': 9,
        'name': 'Plus',
        'cost': 34000,
        'available': 1,
        'used': 9 * scale,
        'needed': 8 * scale,
        'image': null,
      },
    ];

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    // «طلب الكارتات» مفتوحٌ بالخادم (السلّة الفارغة تُرفض بعد فحص المفتاح) —
    // فزرّ «اطلب هذه الكارتات» في اللقطات؛ وحاله موقوفاً في
    // test/el_card_order_gate_test.dart.
    ElCardOrderGate.reset();
    server.reply('POST', '/api/v2/el/card-order/quote', 400,
        {'success': false, 'message': 'حدّد الباقة والعدد'});
    server.on('GET', _path, (o) {
      final days = int.parse('${o.queryParameters['days']}');
      final scale = switch (days) { 1 => 1, 3 => 3, 7 => 7, _ => 137 };
      return SimReply(200, {'success': true, 'data': _rows(scale), 'days': days});
    });
  });

  Future<void> open(WidgetTester t, SimVariant v, {bool settle = true}) async {
    await pumpSim(t, v,
        home: (_) => const ElRequiredCardsScreen(), settle: settle);
  }

  Future<void> reveal(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
  }

  List<int> requestedDays() => [
        for (final r in server.calls('GET', _path))
          int.parse('${r.queryParameters['days']}'),
      ];

  simCase(_screen, 'loading', (t, v) async {
    server.hold('GET', _path);
    await open(t, v, settle: false);
    // الهيكل يومض — لا استقرار قبل الردّ.
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('الكارتات المطلوبة'), findsOneWidget);
    await simCheck(t, v, _screen, 'loading');
    server.release('GET', _path);
    await t.pumpAndSettle();
    expect(find.text('Economy'), findsOneWidget);
  });

  simCase(_screen, 'day', (t, v) async {
    await open(t, v);
    expect(requestedDays(), [1]);
    expect(find.text('Economy'), findsOneWidget);
    expect(find.text('4 باقات'), findsOneWidget);
    // المطلوب ٣٠ = ١٨+٤+٨، والرصيد = ١٨×٢٠٬٠٠٠ + ٤×٩٣٬٠٠٠ + ٨×٣٤٬٠٠٠.
    expect(find.text('30'), findsWidgets, reason: 'الملخّص (+ مستهلَك Economy)');
    expect(find.text('1,004,000'), findsOneWidget);
    await simCheck(t, v, _screen, 'day');
    await reveal(t, find.text('Business Pro 100M'));
    await simCheck(t, v, _screen, 'day_rows');
  });

  simCase(_screen, 'month_large_numbers', (t, v) async {
    await open(t, v);
    await t.tap(find.text('شهر'));
    await t.pumpAndSettle();
    expect(requestedDays(), [1, 30]);
    expect(find.textContaining('لشهر'), findsOneWidget);
    await simCheck(t, v, _screen, 'month_large_numbers');
    await reveal(t, find.text('Plus'));
    await simCheck(t, v, _screen, 'month_rows');
  });

  simCase(_screen, 'periods_cycle', (t, v) async {
    await open(t, v);
    for (final label in ['٣ أيام', 'أسبوع', 'شهر', 'يوم']) {
      await t.tap(find.text(label));
      await t.pumpAndSettle();
    }
    // اليوم محفوظ: يُعرض فوراً ويُحدَّث بالخلفيّة.
    expect(requestedDays(), [1, 3, 7, 30, 1]);
    await simCheck(t, v, _screen, 'periods_cycle');
  });

  simCase(_screen, 'empty', (t, v) async {
    server.reply('GET', _path, 200,
        {'success': true, 'data': <Object>[], 'days': 1});
    await open(t, v);
    expect(find.text('لا توجد كارتات مطلوبة لهذه المدّة'), findsOneWidget);
    await simCheck(t, v, _screen, 'empty');
  });

  simCase(_screen, 'error_then_retry', (t, v) async {
    server.reply('GET', _path, 503,
        {'success': false, 'message': 'تعذّر جلب الكروت المطلوبة'});
    await open(t, v);
    expect(find.text('تعذّر جلب الكروت المطلوبة'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    await simCheck(t, v, _screen, 'error_then_retry');
    server.on('GET', _path,
        (_) => SimReply(200, {'success': true, 'data': _rows(1), 'days': 1}));
    await t.tap(find.text('إعادة المحاولة'));
    await t.pumpAndSettle();
    expect(find.text('Economy'), findsOneWidget);
  });

  simCase(_screen, 'refresh_failed_keeps_data', (t, v) async {
    await open(t, v);
    server.reply('GET', _path, 503,
        {'success': false, 'message': 'تعذّر جلب الكروت المطلوبة'});
    await t.tap(find.byTooltip('تحديث'));
    await t.pumpAndSettle();
    expect(find.text('Economy'), findsOneWidget, reason: 'البيانات باقية');
    expect(find.text('تعذّر جلب الكروت المطلوبة'), findsOneWidget,
        reason: 'تنبيهٌ عائم لا استبدال للشاشة');
    await simCheck(t, v, _screen, 'refresh_failed_keeps_data');
    await simDrain(t);
  });
}
