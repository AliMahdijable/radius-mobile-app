import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:rad_mysvcs/services/receipt_pdf.dart';

/// «مصمّم الوصل» v3 — الرسم (spec §4.2/§4.6): المسافات تُضاف بالضبط (Σ × ملم) ولا تبتلعها المسافة الطبيعيّة، والخطّ
/// تحت الكتلة ١ ملم + ٠٫٧٥ نقطة، و«تحت بعض» أطول من السطر الواحد، وورق ٥٨ يتّسع، والحجم المثبّت يُطبع بنقطته حرفاً.
const _mm = PdfPageFormat.mm;

ReceiptDoc _doc(Map<String, dynamic> design, {ReceiptKind kind = ReceiptKind.activation}) => ReceiptDoc(
      kind: kind,
      issuedAt: DateTime.utc(2026, 11, 1, 7, 5),
      look: ReceiptSettings.fromJson({
        'shop_name': 'مكتب النجف',
        'shop_address': 'النجف',
        'shop_phone': '0780 111 2222',
        'design': design,
      }),
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

Map<String, dynamic> _v3([Map<String, dynamic> layout = const {}]) => {
      'layout': {'v': 3, ...layout},
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late pw.ThemeData theme;
  setUpAll(() {
    ByteData font(String w) => ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-$w.ttf').readAsBytesSync());
    theme = pw.ThemeData.withFont(base: pw.Font.ttf(font('400')), bold: pw.Font.ttf(font('700')));
  });

  Future<PrintDoc> build(Map<String, dynamic> design, {bool a4 = false, PdfPageFormat? paper}) =>
      ReceiptPdf.build(_doc(design), a4: a4, theme: theme, paper: paper, compress: false);
  Future<double> height(Map<String, dynamic> design) async => (await build(design)).format.height;

  test('{v:3} بلا مفتاح = تصميم v2 الفارغ بايتاً ببايت (الرسم لا يقرأ v)', () async {
    final v2 = await build({'layout': {'v': 2}});
    final v3 = await build(_v3());
    String norm(Uint8List b) => latin1
        .decode(b)
        .replaceAll(RegExp(r'/ID\s*\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'/CreationDate\s*\([^)]*\)'), '');
    expect(norm(v3.bytes), norm(v2.bytes));
  });

  test('المسافات تُضاف بالضبط: Σ(قبل + بعد) × ملم — على الكتل والصفوف والسطور والأولى والأخيرة', () async {
    final base = await height(_v3());
    final cases = <Map<String, dynamic>, double>{
      {'blocks': {'qr': {'gap_before': 2}}}: 2,
      {'blocks': {'meta': {'gap_after': 1.5}, 'qr': {'gap_before': 1}}}: 2.5,
      {'fields': {'shop_name': {'gap_before': 3}}}: 3, // ثاني كتلة (بعد الشعار؟ لا شعار هنا ⇒ الأولى: حشوةٌ فوق)
      {'blocks': {'footer': {'gap_after': 4}}}: 4, // الأخيرة: مسافةٌ تحت
      {'fields': {'balance_debt': {'gap_before': 1, 'gap_after': 0.5}}}: 1.5, // صفّ
      {'fields': {'shop_phone': {'gap_after': 2}}}: 2, // سطرٌ في العنوان والهاتف
      {'fields': {'issuer': {'gap_before': 1}}}: 1, // سطرٌ في الذيل
    };
    for (final e in cases.entries) {
      final h = await height(_v3(e.key));
      expect(h - base, moreOrLessEquals(e.value * _mm, epsilon: 0.01), reason: '${e.key}');
    }
  });

  test('«خطّ تحته» على كتلة: ١ ملم + ٠٫٧٥ نقطة، و«بلا» لا يضيف شيئاً', () async {
    final base = await height(_v3());
    final solid = await height(_v3({
      'blocks': {
        'qr': {'sep': 'solid'},
      },
    }));
    expect(solid - base, moreOrLessEquals(1 * _mm + 0.75, epsilon: 0.01));
    final none = await height(_v3({
      'blocks': {
        'qr': {'sep': 'none'},
      },
    }));
    expect(none, moreOrLessEquals(base, epsilon: 0.01));
    // الرقم والتاريخ: «بلا» يزيل خطّهما (يُرسم داخل حشوتهما — الطول كما هو والرسم بلا خطّ).
    final plain = await build(_v3());
    final metaNone = await build(_v3({
      'blocks': {
        'meta': {'sep': 'none'},
      },
    }));
    expect(metaNone.format.height, moreOrLessEquals(base, epsilon: 0.01));
    expect(metaNone.bytes.length, lessThan(plain.bytes.length), reason: 'خطٌّ أقلّ في المحتوى');
  });

  test('«تحت بعض» أطول من السطر الواحد، و«القيمة فقط» لا تطول', () async {
    final line = await height(_v3());
    final stack = await height(_v3({
      'fields': {
        'subscriber_name': {'row_mode': 'stack'},
        'balance_debt': {'row_mode': 'stack'},
      },
    }));
    final value = await height(_v3({
      'fields': {
        'subscriber_name': {'row_mode': 'value'},
      },
    }));
    expect(stack, greaterThan(line));
    expect(value, lessThanOrEqualTo(line + 0.01));
  });

  test('ورق ٥٨: يتّسع بالأحجام المثبّتة الكبيرة والتسميات تحت بعض', () async {
    final pdf = await build(
      _v3({
        'fields': {
          'shop_name': {'pt': 24, 'align': 'right'},
          'subscriber_name': {'pt': 18, 'bold': true, 'row_mode': 'stack', 'align': 'center'},
          'balance_debt': {'pt': 24, 'sep': 'solid', 'gap_before': 2},
          'username': {'row_mode': 'value', 'align': 'center', 'pt': 9},
        },
      })
        ..['paper_width_mm'] = 58,
    );
    expect(pdf.format.width, moreOrLessEquals(58 * _mm, epsilon: 0.01));
    expect(pdf.format.height.isFinite, isTrue);
    final a4 = await build(_v3({'fields': {'amount': {'pt': 14}}}), a4: true);
    expect([a4.format.width, a4.format.height], [PdfPageFormat.a4.width, PdfPageFormat.a4.height]);
  });

  test('الحجم المثبّت يُطبع بنقطته: «14 Tf» للقيمة و«12.5 Tf» لتسميتها (labelPt)', () async {
    String content(PrintDoc d) => latin1.decode(d.bytes);
    final plain = content(await build(_v3()));
    expect(plain.contains(' 14 Tf'), isFalse);
    final pinned = content(await build(_v3({
      'fields': {
        'balance_debt': {'pt': 14},
      },
    })));
    expect(pinned.contains(' 14 Tf'), isTrue);
    expect(pinned.contains(' 12.5 Tf'), isTrue, reason: 'التسمية ٩٠٪ مقرَّبة لنصف نقطة');
  });

  test('المحاذاة والعنوان المنفصل والعملة وQR بخصائص التعليق تُبنى بلا استثناء', () async {
    for (final kind in ReceiptKind.values) {
      final d = _doc(
        _v3({
          'currency': 'IQD',
          'fields': {
            'receipt_no': {'align': 'right', 'pt': 8},
            'issued_at': {'align': 'left', 'pt': 8, 'gap_before': 1},
            'qr_caption': {'label': 'امسح يا {firstname}', 'pt': 7, 'bold': true, 'align': 'right'},
            'amount': {'label': 'المبلغ ({payment_type})', 'align': 'center'},
          },
          'sections': {
            'transaction': {'title': 'الحساب', 'align': 'center', 'pt': 9},
          },
          'order': {
            'blocks': ['logo', 'shop_name', 'shop_lines', 'title', 'body', 'meta', 'qr', 'footer'],
          },
          'texts': [
            {'id': 't1', 'at': 'after_transaction', 'text': 'سدّد قبل {expiry_date}', 'pt': 9, 'sep': 'dotted'},
          ],
        }),
        kind: kind,
      );
      final pdf = await ReceiptPdf.build(d, a4: false, theme: theme, compress: false);
      expect(pdf.bytes, isNotEmpty, reason: kind.name);
    }
  });
}
