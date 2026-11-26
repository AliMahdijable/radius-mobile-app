import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:rad_mysvcs/api/settlements_api.dart';
import 'package:rad_mysvcs/services/pdf_kit.dart';
import 'package:rad_mysvcs/services/settlement_print.dart';

/// تصميم PDF المشترك (٢٦ نوفمبر — المالك: «تصميم التقارير بملف pdf … كلش مخزي بجميع التقارير والتسويه … حسّن التصميم اكثر
/// ومعلومات اوضح»): عيوب النصّ التي ظهرت في صور «قبل» لا تعود.
void main() {
  bool anyIn(String s, int from, int to) => s.runes.any((r) => r >= from && r <= to);

  test('١ الشدّة مع الحركة لا تصير رمزاً لا يملكه الخطّ (مربّع فارغ)', () {
    for (final w in ['يُحصَّل لاحقاً', 'رصيد مدوَّر', 'المُرحَّل للفترة التالية', 'المستلَم فعلاً']) {
      final v = PdfKit.visual(w);
      expect(anyIn(v, 0xFC5E, 0xFC63), isFalse, reason: w);
      expect(anyIn(v, 0x064B, 0x0650) || anyIn(v, 0x0652, 0x065F), isFalse, reason: 'لا حركة ولا تنوين: $w');
      expect(anyIn(v, 0xFE70, 0xFE75), isFalse, reason: 'التنوين لا يُرسم علامةً منفصلة: $w');
    }
    // الشدّة وحدها تبقى — لها شكلٌ في الخطّ
    expect(PdfKit.visual('الكلّ').runes.contains(0x0651) || anyIn(PdfKit.visual('الكلّ'), 0xFE7C, 0xFE7D), isTrue);
  });

  test('٢ التاريخ والوقت والمبلغ داخل جملةٍ عربيّة لا تنقلب أجزاؤها', () {
    final p = PdfKit.visual('من 2026-11-01 إلى 2026-11-26');
    expect(p, contains('2026-11-01'));
    expect(p, contains('2026-11-26'));
    expect(p.indexOf('2026-11-26'), lessThan(p.indexOf('2026-11-01')), reason: 'يُقرأ من اليمين: الأوّل يميناً');
    final t = PdfKit.visual('طبع 2026-11-26 04:58');
    expect(t, contains('04:58'));
    expect(t, contains('2026-11-26'));
    final m = PdfKit.visual('2,031,000 د.ع');
    expect(m, contains('2,031,000'));
    expect(m.endsWith('2,031,000'), isTrue, reason: 'المبلغ يميناً والعملة بعده يساراً');
    expect(PdfKit.visual('الرصيد -35,000'), contains('-35,000'));
    expect(PdfKit.visual('هذا الشهر · 2026-11-01 ← 2026-11-26'), contains('2026-11-26 ← 2026-11-01'));
  });

  test('٢ب محارف العزل حول الرقم السالب (rpNum في التطبيق) لا تصل للخطّ — لا شكل لها', () {
    final fsi = String.fromCharCode(0x2068), pdi = String.fromCharCode(0x2069), rlm = String.fromCharCode(0x200F);
    final v = PdfKit.visual('$fsi${String.fromCharCode(0x2212)}35,000$pdi د.ع');
    expect(v.contains(fsi) || v.contains(pdi) || v.contains(rlm), isFalse);
    expect(v, contains('${String.fromCharCode(0x2212)}35,000'));
    expect(PdfKit.plain('${fsi}12$pdi'), '12', reason: 'النصّ اللاتينيّ يُرسم بلا عزلٍ كذلك');
  });

  test('٢ج المبلغ: التقريب قبل الإشارة', () {
    expect(PdfKit.amount(-0.4), '0');
    expect(PdfKit.amount(-125000), '-125,000');
    expect(PdfKit.amount(2031000.6), '2,031,001');
  });

  test('٣ الجملة عربيّة ولو بدأت بكلمةٍ لاتينيّة', () {
    final v = PdfKit.visual('TP-Link راوتر');
    expect(v.endsWith('TP-Link'), isTrue, reason: 'أوّل الجملة يميناً');
  });

  test('٤ «عدد الصفوف: 3» كما ثبّته اختبار التقرير', () {
    final v = PdfKit.visual('عدد الصفوف: 3');
    expect(v.split(' '), hasLength(3));
    expect(v.startsWith('3 '), isTrue);
  });

  group('٥ السند: الداخل والخارج', () {
    SettlementRecord rec(Map<String, dynamic> over) => SettlementRecord.fromJson({
          'id': 1, 'kind': 'settlement', 'number': 3, 'status': 'active',
          'period_start_at': '2026-11-19 21:00:00', 'cut_at': '2026-11-26 00:30:00',
          'opening_balance': 150000,
          'cash_activations': {'sum': 2350000, 'count': 57}, 'debt_payments': {'sum': 450000, 'count': 9},
          'sales_cash': {'sum': 120000, 'count': 3}, 'cash_in': 2920000,
          'expenses': {'sum': 789000, 'count': 4}, 'goods_purchases': {'sum': 0, 'count': 0},
          'employee_moves': {'sum': -250000, 'count': 5}, 'new_debts': {'sum': 0, 'count': 0},
          'expected_amount': 2031000, 'received_amount': 2000000, 'carried_amount': 31000,
          ...over,
        })!;

    test('المدوَّر + الداخل − الخارج = المتوقّع (معادلة الخادم)', () {
      final s = rec({});
      final f = SettlementPrint.flows(s);
      final inSum = f.ins.fold<num>(0, (a, l) => a + l.amount);
      final outSum = f.outs.fold<num>(0, (a, l) => a + l.amount);
      expect(inSum, 2920000);
      expect(outSum, 1039000);
      expect(s.openingBalance + inSum - outSum, s.expected);
      expect(f.outs.map((l) => l.label), contains('سلف وقروض الموظفين'));
    });

    test('الإشارة تحدّد الجهة: سحب حوالات وإلغاؤه، نقد المدراء، استرجاع من المورّد', () {
      final s = rec({
        'transfer_withdrawals': {'sum': -40000, 'count': 1},
        'manager_moves': {'sum': 300000, 'count': 2},
        'goods_purchases': {'sum': -15000, 'count': 1},
        'employee_moves': {'sum': 60000, 'count': 1},
      });
      final f = SettlementPrint.flows(s);
      expect(f.outs.map((l) => l.label), contains('إلغاء سحب من الحوالات'));
      expect(f.ins.map((l) => l.label), containsAll(['من المدراء الفرعيّين', 'استرجاع من المورّد', 'رجع من سلف الموظفين']));
      expect([...f.ins, ...f.outs].every((l) => l.amount >= 0 || l.label == 'بيع مواد'), isTrue, reason: 'المبالغ موجبة في جهتها');
    });

    test('المعادلة لا تُطبع إن لم تطابق رقم الخادم (سجلٌّ بحقلٍ ناقص)', () {
      expect(SettlementPrint.balancedOf(rec({})), isTrue);
      // تسوية الإنتاج #176: تفعيلات 450,000 + تسديد 385,000 + رجع سلف 20,000 = 855,000
      expect(
          SettlementPrint.balancedOf(rec({
            'opening_balance': 0, 'cash_activations': {'sum': 450000, 'count': 10}, 'debt_payments': {'sum': 385000, 'count': 8},
            'sales_cash': {'sum': 0, 'count': 0}, 'expenses': {'sum': 0, 'count': 0}, 'employee_moves': {'sum': 20000, 'count': 4},
            'expected_amount': 855000,
          })),
          isTrue);
      expect(SettlementPrint.balancedOf(rec({'expected_amount': 2081000})), isFalse, reason: 'فرق 50,000 ⇒ لا معادلة');
      expect(SettlementPrint.balancedOf(rec({'employee_moves': {'sum': -250000, 'count': 0}})), isFalse,
          reason: 'مجموعٌ بلا عدد (حقلٌ شاذّ) لا يدخل السطور ⇒ المعادلة لا تطابق ⇒ لا تُطبع');
    });

    testWidgets('A4 والكاشير يُبنيان — ملغاة وبداية حساب', (t) async {
      await t.runAsync(() async {
        for (final s in [
          rec({}),
          rec({'status': 'voided', 'void_reason': 'خطأ بالمبلغ', 'voided_by': 'admin'}),
          rec({'kind': 'opening', 'number': null}),
        ]) {
          for (final f in [PdfPageFormat.a4, PdfPageFormat.roll80]) {
            final bytes = await (await SettlementPrint.buildForTest(s, f, company: 'سوبرنت', manager: 'admin@x')).save();
            expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
          }
        }
      });
    });
  });
}
