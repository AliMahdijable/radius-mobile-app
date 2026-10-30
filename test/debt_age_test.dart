import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/debt_age.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_card_v3.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'support/app_fonts.dart';

/// «أيّام الدين» (٣٠ أكتوبر) — المالك: «ايام الدين يعني المشترك صارله شكد من عليه اخر عمليه دين وبين قوسين شنو جانت
/// تفعيل او شراء»، ثمّ: «تكدر ترتبه اكثر لان هسه ياخذ من الوجدت مساحه».
///
/// يثبت: النموذج يقرأ `debt_since`/`debt_kind` وتحملهما النسخ · العمر للمدين وحده · الأيّام بتقويم الجهاز والدرجات
/// (٧/٨ · ٣٠/٣١) والنصوص · و**الكرت لا يكبر**: الشريط يطول بضع نقاطٍ على الهاتف، ولا شيء على العريض (الشارة بجانب المبلغ).

/// ظهر اليوم ناقص [days] — منتصف النهار فلا يقلب فارق التوقيت التاريخ.
String _ago(int days) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, 12).subtract(Duration(days: days)).toUtc().toIso8601String();
}

Subscriber _sub({String notes = '-45000', String? since, String? kind}) => Subscriber.fromJson({
      'idx': '3',
      'username': 'hussein77@najaf',
      'firstname': 'حسين',
      'lastname': 'عبد الأمير',
      'profile_name': 'Plus',
      'package_price': 25000,
      'expiration': '2026-11-28 10:00:00',
      'remaining_days': 29,
      'notes': notes,
      if (since != null) 'debt_since': since,
      if (kind != null) 'debt_kind': kind,
    });

Future<double> _cardHeight(WidgetTester t, Subscriber s, double width) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = Size(width, 1200);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            child: SubscriberCardV3(
              sub: s,
              selected: false,
              onTap: () {},
              onLongPress: () {},
              onSendDebtReminder: () {},
              onPayDebt: () {},
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
  return t.getSize(find.byType(SubscriberCardV3)).height;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => AppColors.setDarkMode(false));

  group('النموذج', () {
    test('يقرأ debt_since/debt_kind، وتحملهما نسخ الصفّ', () {
      final s = _sub(since: '2026-10-25T10:00:00.000Z', kind: 'activate');
      expect(s.debtSince, DateTime.utc(2026, 10, 25, 10).toLocal());
      expect(s.debtKind, 'activate');
      final c = s.withCompany('co-1');
      expect(c.debtSince, s.debtSince);
      expect(c.debtKind, 'activate');
      final e = s.enrichWithPackages(const {});
      expect(e.debtKind, 'activate');
      final bad = _sub(since: 'not a date', kind: '');
      expect(bad.debtSince, isNull);
      expect(bad.debtKind, isNull);
    });

    test('العمر للمدين بتاريخٍ من الخادم وحده', () {
      expect(DebtAge.of(_sub(notes: '', since: _ago(5), kind: 'activate')), isNull, reason: 'ليس مديناً');
      expect(DebtAge.of(_sub(notes: '5000', since: _ago(5), kind: 'activate')), isNull, reason: 'رصيدٌ له لا عليه');
      expect(DebtAge.of(_sub()), isNull, reason: 'مدينٌ بلا حركةٍ من الخادم (أو خادمٌ أقدم)');
      expect(DebtAge.of(_sub(since: _ago(5), kind: 'sale'))!.kind, 'sale');
    });
  });

  group('الأيّام والدرجات والنصوص', () {
    test('بتقويم الجهاز: أمس قبل منتصف الليل = يوم، ولا سالب', () {
      final a = DebtAge(since: DateTime(2026, 10, 30, 23, 50), kind: 'activate');
      expect(a.days(DateTime(2026, 10, 31, 0, 10)), 1);
      expect(a.days(DateTime(2026, 10, 30, 23, 59)), 0);
      expect(a.days(DateTime(2026, 10, 29)), 0, reason: 'ساعة جهازٍ خاطئة لا تُظهر سالباً');
    });

    test('الحدود: ≤7 هادئة · 8–30 كهرمانيّة · >30 حمراء · الرصيد السابق رماديّ', () {
      final now = DateTime(2026, 10, 30, 12);
      DebtAgeTier tier(int d, [String k = 'activate']) =>
          DebtAge(since: now.subtract(Duration(days: d)), kind: k).tierAt(now);
      expect(tier(0), DebtAgeTier.fresh);
      expect(tier(7), DebtAgeTier.fresh);
      expect(tier(8), DebtAgeTier.aging);
      expect(tier(30), DebtAgeTier.aging);
      expect(tier(31), DebtAgeTier.old);
      for (final k in ['opening', 'import', '', 'adjust']) {
        expect(tier(90, k), DebtAgeTier.legacy, reason: k);
      }
    });

    test('النصوص: الأيّام بالعربيّة والنوع بين قوسين؛ الرصيد السابق بلا أيّام', () {
      final now = DateTime(2026, 10, 30, 12);
      String pill(int d, String k) => DebtAge(since: now.subtract(Duration(days: d)), kind: k).pillText(now);
      expect(pill(47, 'activate'), '47 يوماً (تفعيل)');
      expect(pill(12, 'sale'), '12 يوماً (شراء)');
      expect(pill(2, 'manual'), 'يومين (إضافة دين)');
      expect(pill(1, 'extend'), 'يوم (تمديد)');
      expect(pill(5, 'activate'), '5 أيام (تفعيل)');
      expect(pill(0, 'sale'), 'اليوم (شراء)');
      expect(pill(40, 'opening'), 'رصيد سابق');
      final a = DebtAge(since: DateTime(2026, 9, 13, 9), kind: 'activate');
      expect(a.dateLine, 'آخر دين \u20662026/09/13\u2069');
      expect(DebtAge(since: DateTime(2026, 10, 19), kind: 'opening').dateLine, 'قبل \u20662026/10/19\u2069');
    });
  });

  group('الكرت لا يكبر (المالك: «ياخذ من الوجدت مساحه»)', () {
    for (final w in <double>[320, 360, 390]) {
      testWidgets('الهاتف ${w.toInt()}: سطرٌ رفيع داخل شريط الدين — الكرت يطول ≤ 8 نقاط، والشارة كاملة', (t) async {
        final without = await _cardHeight(t, _sub(), w);
        final withAge = await _cardHeight(t, _sub(since: _ago(47), kind: 'activate'), w);
        expect(find.text('47 يوماً (تفعيل)'), findsOneWidget);
        expect(withAge - without, inInclusiveRange(0, 8));
        final p = t.renderObject<RenderParagraph>(find.text('47 يوماً (تفعيل)'));
        expect(p.didExceedMaxLines, isFalse, reason: 'الشارة لا تُقصّ');
      });
    }

    testWidgets('العريض (اللوحيّ): الشارة بجانب المبلغ — بلا أيّ زيادة', (t) async {
      final without = await _cardHeight(t, _sub(), 640);
      final withAge = await _cardHeight(t, _sub(since: _ago(12), kind: 'sale'), 640);
      expect(find.text('12 يوماً (شراء)'), findsOneWidget);
      expect((withAge - without).abs(), lessThanOrEqualTo(1));
    });

    // الهواتف الشائعة ٤١١–٤١٢ وما فوقها: الزرّان بنصّيهما — القرار بالقياس لا بعتبة عرضٍ ثابتة (عتبة ٤٠٠ كانت تقصّ
    // «1,250,000 د.ع» بجانب «47 يوماً (إضافة دين)»).
    for (final w in <double>[411, 440, 460, 500])
    for (final c in [('-1250000', 'manual', 47), ('-30000', 'activate', 1), ('-30000', 'manual', 0)]) {
      testWidgets('${w.toInt()} بمبلغ ${c.$1} وشارة ${c.$2}/${c.$3}: لا يُقصّ المبلغ ولا الشارة، والكرت لا يكبر > 8', (t) async {
        final without = await _cardHeight(t, _sub(notes: c.$1), w);
        final withAge = await _cardHeight(t, _sub(notes: c.$1, since: _ago(c.$3), kind: c.$2), w);
        expect(withAge - without, inInclusiveRange(0, 8));
        var checked = 0;
        for (final f in [find.textContaining('د.ع'), find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('('))]) {
          for (final e in f.evaluate()) {
            checked++;
            final p = e.renderObject;
            if (p is RenderParagraph) expect(p.didExceedMaxLines, isFalse, reason: (e.widget as Text).data);
          }
        }
        expect(checked, greaterThanOrEqualTo(2), reason: 'المبلغ والشارة فُحصا فعلاً');
      });
    }

    testWidgets('غير المدين وبلا تاريخ: لا شارة', (t) async {
      await _cardHeight(t, _sub(notes: '', since: _ago(3), kind: 'activate'), 390);
      expect(find.byType(DebtAgePill), findsNothing);
      await _cardHeight(t, _sub(), 390);
      expect(find.byType(DebtAgePill), findsNothing);
    });
  });
}
