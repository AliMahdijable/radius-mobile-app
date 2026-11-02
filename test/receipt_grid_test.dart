import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:rad_mysvcs/services/receipt_grid.dart';
import 'package:rad_mysvcs/services/receipt_layout.dart';
import 'package:rad_mysvcs/services/receipt_pdf.dart';

/// «تصميم الوصل» v4 «الشبكة» في التطبيق (٢ نوفمبر — نسخة `client-v2/src/lib/receipt-grid.ts`): التفقيط، ملء النصوص بالمتغيّرات
/// (الفارغ يُخفي النصّ)، «من أصل» و«المتبقّي» و«المبلغ كتابةً»، وقراءة {v:4} وحده، والرسم PDF لكلّ أنواع الوصل والحجم بالنقطة
/// حرفاً، والصفّ الذي لا قيمة فيه لا يُطبع.
ReceiptDoc _doc(Map<String, dynamic> design, {ReceiptKind kind = ReceiptKind.activation}) => ReceiptDoc(
      kind: kind,
      issuedAt: DateTime.utc(2026, 11, 2, 7, 5),
      look: ReceiptSettings.fromJson({'shop_name': 'مكتب النجف', 'shop_address': 'النجف', 'shop_phone': '0780 111 2222', 'design': design}),
      receiptNo: 12,
      shopName: 'مكتب النجف',
      subscriberName: 'علي حسن',
      username: 'user7',
      phone: '07701234567',
      packageName: '10M-Unlimited',
      packagePrice: 25000,
      expiration: '2026-11-24 15:30:00',
      remainingDays: 31,
      pay: ReceiptPay.partial,
      amount: 25000,
      partialAmount: 10000,
      newBalance: -15000,
      qrUrl: 'https://pro.mysvcs.net/user-info/abc',
      issuer: 'حسن (emp1)',
    );

Map<String, dynamic> _grid(List<Map<String, dynamic>> rows, {String? currency}) => {
      'layout': {
        'v': 4,
        'grid': {'rows': rows},
        if (currency != null) 'currency': currency,
      },
    };

Map<String, dynamic> _row(List<Map<String, dynamic>> cells, {num? gap, List<String>? only}) =>
    {'id': 'r${cells.hashCode}', 'cells': cells, if (gap != null) 'gap': gap, if (only != null) 'only': only};

ReceiptInput _input({String kind = 'activation', String? pay = 'partial-cash', num? amount = 25000, num? partial = 10000, num? nb = -15000}) =>
    ReceiptInput(kind: kind, issuedText: '2026-11-02 10:05', receiptId: 'No. 00012', receiptNoText: '00012', paymentType: pay, amount: amount, partialAmount: partial, newBalance: nb);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late pw.ThemeData theme;
  setUpAll(() {
    ByteData font(String w) => ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-$w.ttf').readAsBytesSync());
    theme = pw.ThemeData.withFont(base: pw.Font.ttf(font('400')), bold: pw.Font.ttf(font('700')));
  });

  test('التفقيط كالموقع: ألوفٌ وملايين ومثنّى، و«فقط … دينار عراقي لا غير»', () {
    expect(numberWords(0), 'صفر');
    expect(numberWords(10000), 'عشرة آلاف');
    expect(numberWords(35000), 'خمسة وثلاثون ألف');
    expect(numberWords(1500), 'ألف وخمسمئة');
    expect(numberWords(25250), 'خمسة وعشرون ألف ومئتان وخمسون');
    expect(numberWords(2000000), 'مليونان');
    expect(amountWords(35000), 'فقط خمسة وثلاثون ألف دينار عراقي لا غير');
    expect(amountWords(35000, 'IQD'), 'فقط خمسة وثلاثون ألف دينار عراقي لا غير');
    expect(amountWords(35000, r'$'), r'فقط خمسة وثلاثون ألف $ لا غير');
  });

  test('ملء النصّ: المجهول يبقى، والمعروف الفارغ يُخفي النصّ إن فرغت متغيّراته كلّها، والأسطر الفارغة تُحذف', () {
    final v = {'firstname': 'علي', 'phone': ''};
    expect(gridFill('مرحباً {firstname}', v), (text: 'مرحباً علي', hidden: false));
    expect(gridFill('هاتف: {phone}', v).hidden, isTrue);
    expect(gridFill('{phone} {firstname}', v), (text: 'علي', hidden: false));
    expect(gridFill('ثابت {unknown_x}', v), (text: 'ثابت {unknown_x}', hidden: false));
    expect(gridFill('سطر\n\n  {phone}  \nآخر', v).text, 'سطر\nآخر');
    expect(gridFill('   ', v).hidden, isTrue);
  });

  test('من أصل والمتبقّي والمبلغ كتابةً: التفعيل الجزئيّ والدفع، وغير الماليّ فارغ', () {
    final a = gridVars(_input());
    expect((a['total_amount'], a['remaining_amount'], a['amount_words']), ('25,000 د.ع', '15,000 د.ع', 'فقط عشرة آلاف دينار عراقي لا غير'));
    expect(a['datetime'], '2026-11-02 10:05');
    // الدفع: الدين قبله = |بعده − المدفوع| والمتبقّي = الدين بعده
    final p = gridVars(_input(kind: 'payment', pay: null, amount: 10000, partial: null, nb: -5000));
    expect((p['total_amount'], p['remaining_amount'], p['amount_words']), ('15,000 د.ع', '5,000 د.ع', 'فقط عشرة آلاف دينار عراقي لا غير'));
    // الآجل: لا مبلغ كتابةً (المدفوع صفر)، والمتبقّي كلّه
    final c = gridVars(_input(pay: 'non-cash', partial: null));
    expect((c['amount_words'], c['remaining_amount']), ('', '25,000 د.ع'));
    // وصل المعلومات: لا متغيّرات مال
    final i = gridVars(_input(kind: 'info', pay: null));
    expect((i['total_amount'], i['remaining_amount'], i['amount_words']), ('', '', ''));
  });

  test('{v:4} وحده شبكة — v3 أو شبكةٌ بلا صفوف ليست كذلك؛ والخانة المجهولة تُسقط والعرض يُحدّ', () {
    expect(GridLayout.from({'v': 3, 'fields': {}}), isNull);
    expect(GridLayout.from({'v': 4}), isNull);
    expect(GridLayout.from({'v': 4, 'grid': {}}), isNull);
    final g = GridLayout.from({
      'v': 4,
      'currency': 'IQD',
      'grid': {
        'rows': [
          {
            'cells': [
              {'type': 'field', 'var': 'firstname', 'w': 40},
              {'type': 'weird'},
              {'type': 'text', 'text': 'x', 'w': 0},
            ],
          },
        ],
      },
    })!;
    expect(g.currency, 'IQD');
    expect(g.rows.single.cells.map((c) => (c.type, c.w)).toList(), [('field', 12), ('text', 1)]);
  });

  Future<PrintDoc> build(Map<String, dynamic> design, {ReceiptKind kind = ReceiptKind.activation, bool a4 = false}) =>
      ReceiptPdf.build(_doc(design, kind: kind), a4: a4, theme: theme, compress: false);

  final full = _grid([
    _row([
      {'type': 'logo', 'size_mm': 14},
      {'type': 'text', 'text': '{shop_name}', 'w': 2, 'style': {'pt': 16, 'weight': '800'}},
    ]),
    _row([
      {'type': 'field', 'var': 'firstname', 'label_pos': 'top', 'style': {'box': 'dashed', 'radius': 1}},
      {'type': 'field', 'var': 'package_name', 'label': 'الباقة', 'label_style': {'color': '#0d9488'}},
    ]),
    _row([
      {'type': 'line', 'line': 'dotted', 'thick': 1},
    ]),
    _row([
      {'type': 'field', 'var': 'paid_amount', 'style': {'bg': '#d1d5db'}},
      {'type': 'field', 'var': 'remaining_amount'},
    ], only: ['activation', 'extension', 'payment']),
    _row([
      {'type': 'text', 'text': '{amount_words}', 'style': {'pt': 9, 'align': 'right'}},
    ]),
    _row([
      {'type': 'space', 'h': 3},
    ]),
    _row([
      {'type': 'qr', 'size_mm': 20, 'style': {'align': 'left'}},
      {'type': 'field', 'var': 'datetime', 'label_pos': 'none'},
    ], gap: 2),
  ], currency: 'د.ع');

  test('الرسم: كلّ أنواع الوصل تُبنى، كاشيراً وA4، والحجم بالنقطة يُطبع حرفاً', () async {
    for (final kind in ReceiptKind.values) {
      for (final a4 in [false, true]) {
        final pdf = await build(full, kind: kind, a4: a4);
        expect(pdf.bytes, isNotEmpty, reason: '${kind.name} a4=$a4');
      }
    }
    final s = latin1.decode((await build(full)).bytes);
    expect(s.contains(' 16 Tf'), isTrue, reason: 'اسم المحلّ بـ١٦ نقطة');
    expect(s.contains(' 9 Tf'), isTrue, reason: 'المبلغ كتابةً بـ٩ نقاط');
  });

  test('الصفّ الذي لا قيمة في خاناته لا يُطبع (لا يطيل الوصل)، والصفّ المقصور على أنواعٍ يغيب عن غيرها', () async {
    // حشوٌ يتجاوز أقصر ورقٍ للكاشير — فيظهر فرق الطول
    final filler = [
      for (var i = 0; i < 14; i++)
        _row([
          {'type': 'text', 'text': 'سطر $i', 'style': {'pt': 20}},
        ]),
    ];
    final base = _grid([
      ...filler,
      _row([
        {'type': 'field', 'var': 'firstname'},
      ]),
    ]);
    final withEmpty = _grid([
      ...filler,
      _row([
        {'type': 'field', 'var': 'firstname'},
      ]),
      _row([
        {'type': 'field', 'var': 'sale_total'},
        {'type': 'text', 'text': 'الدفع: {sale_payment}'},
      ]),
    ]);
    final h0 = (await build(base)).format.height;
    final h1 = (await build(withEmpty)).format.height;
    expect(h1, h0);
    final onlyPay = _grid([
      ...filler,
      _row([
        {'type': 'field', 'var': 'firstname'},
      ]),
      _row([
        {'type': 'text', 'text': 'للدفع وحده', 'style': {'pt': 20}},
      ], only: ['payment']),
    ]);
    expect((await build(onlyPay)).format.height, h0);
    expect((await build(onlyPay, kind: ReceiptKind.payment)).format.height, greaterThan(h0));
  });
}
