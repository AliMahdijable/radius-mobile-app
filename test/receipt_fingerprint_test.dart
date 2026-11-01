import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/services/receipt_layout.dart';
import 'package:rad_mysvcs/services/receipt_pdf.dart';

/// 🔒 قفل الرسم — «مصمّم الوصل» v3 (spec §4.0): تصاميم v1 (بلا `layout`) وتصاميم v2 الموجودة تُطبع **بايتاً ببايت** كما
/// كانت قبل المصمّم الجديد. البصمات سُجّلت قبل أيّ تعديلٍ على المحلِّل أو الرسم (على f0495c9e/28ff1a3c)، وكلّ تغييرٍ
/// بعدها يجب أن يُبقيها كما هي — مفتاحٌ جديد بقيمته الافتراضيّة لا يضيف شيئاً إلى الوصل.
///
///   RECORD_RECEIPT_HASHES=1 flutter test test/receipt_fingerprint_test.dart   ⇒ يسجّل (قبل التعديل وحده)
///   flutter test test/receipt_fingerprint_test.dart                           ⇒ يقارن
///
/// تصاميم v1 الستّة وبياناتها هي `V1_DESIGNS`/`V1_DATA` في `client-v2/scripts/check-receipt-layout.mjs`، وتصاميم v2:
/// «مضغوط» و«مضغوط جداً» وحالات c02 c03 c05 c10 c17 من ملفّ التثبيت الأوّل المجمَّد، و«أسود فقط». خمسة أنواع على
/// الكاشير، وA4 لتصميمين من كلٍّ. PDF بلا ضغط، والمعرّف (/ID) والتاريخ يُطبَّعان قبل البصمة.
const _hashesPath = 'test/fixtures/receipt_pdf.hashes.json';
const _frozenFixtures = 'test/fixtures/receipt_layout.fixtures.v1.json';

/// صورة PNG بنقطةٍ واحدة — شعار الوصولات (كـ`QR` في فحص الموقع).
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

const Map<String, Map<String, Object>> _v1Designs = {
  'default': {},
  'sizes': {
    'font_size_base': 15,
    'font_size_title': 19,
    'logo_size_mm': 25,
    'section_gap_mm': 4,
    'margin_top_mm': 1,
    'line_height': 1.3,
  },
  'hidden': {
    'show_logo': false,
    'show_shop_info': false,
    'show_package_info': false,
    'show_manager_signature': false,
    'show_receipt_id': false,
    'show_datetime': false,
    'show_package_price': false,
  },
  'aligns': {
    'default_align': 'left',
    'header_align': 'right',
    'footer_align': 'left',
    'logo_align': 'left',
    'qr_align': 'right',
    'border_style': 'none',
    'row_separator': 'none',
    'section_title_uppercase': false,
    'section_title_underline': false,
  },
  'fonts': {
    'font_family': 'Tajawal',
    'font_weight': '600',
    'accent_color': '#7c3aed',
    'text_color': '#111111',
    'paper_width_mm': 58,
  },
  'compactv1': {
    'font_size_base': 11,
    'font_size_title': 14,
    'section_gap_mm': 2,
    'line_height': 1.25,
    'margin_top_mm': 2,
    'margin_right_mm': 2,
    'margin_bottom_mm': 2,
    'margin_left_mm': 2,
    'logo_size_mm': 12,
    'qr_size_mm': 24,
  },
};

/// تصاميم v2 الموجودة اليوم: القالبان، وخمس حالات من ملفّ التثبيت المجمَّد، و«أسود فقط».
Map<String, Map<String, dynamic>> _v2Designs() {
  final f = jsonDecode(File(_frozenFixtures).readAsStringSync()) as Map<String, dynamic>;
  Map<String, dynamic> caseDesign(String prefix) => Map<String, dynamic>.from(
      (f['cases'] as List).cast<Map<String, dynamic>>().firstWhere((c) => (c['name'] as String).startsWith(prefix))['design']
          as Map);
  Map<String, dynamic> preset(String id) {
    final p = receiptPresets[id]!;
    return {
      ...p.v1,
      'layout': {'v': 2, 'density': p.density, 'emoji': p.emoji},
    };
  }

  return {
    'v2compact': preset('compact'),
    'v2tight': preset('tight'),
    'c02': caseDesign('c02_'),
    'c03': caseDesign('c03_'),
    'c05': caseDesign('c05_'),
    'c10': caseDesign('c10_'),
    'c17': caseDesign('c17_'),
    'v2mono': {
      'layout': {'v': 2, 'mono': true},
    },
  };
}

/// تصاميم تُبنى على A4 أيضاً.
const _a4Designs = {'default', 'sizes', 'v2compact', 'v2mono'};

const _kinds = ['activation', 'extension', 'payment', 'info', 'sale'];

ReceiptSettings _look(Map<String, dynamic> design) => ReceiptSettings.fromJson({
      'shop_name': 'مكتب النجف',
      'shop_address': 'النجف',
      'shop_phone': '0780 111 2222',
      'footer_text': 'سطر\nثاني',
      'logo_data': _png,
      'show_qr': 1,
      'design': design,
    });

/// بيانات الأنواع الخمسة كـ`V1_DATA` في فحص الموقع.
ReceiptDoc _doc(String kind, ReceiptSettings look) {
  const qr = 'https://pro.mysvcs.net/user-info/abc';
  final at = DateTime.utc(2026, 11, 1, 7, 5);
  ReceiptDoc sub({
    required ReceiptKind k,
    int? no,
    int? days = 31,
    ReceiptPay? pay,
    num? amount,
    num? partial,
    num? balance,
    String? qrUrl,
  }) =>
      ReceiptDoc(
        kind: k,
        issuedAt: at,
        look: look,
        receiptNo: no,
        shopName: 'مكتب النجف',
        subscriberName: 'علي حسن',
        username: 'user7',
        phone: '07701234567',
        packageName: '10M-Unlimited',
        packagePrice: 25000,
        expiration: '2026-11-24 15:30:00',
        remainingDays: days,
        pay: pay,
        amount: amount,
        partialAmount: partial,
        newBalance: balance,
        qrUrl: qrUrl,
        issuer: 'حسن (emp1)',
      );
  return switch (kind) {
    'activation' => sub(
        k: ReceiptKind.activation,
        no: 12,
        pay: ReceiptPay.partial,
        amount: 25000,
        partial: 10000,
        balance: -15000,
        qrUrl: qr,
      ),
    'extension' => sub(k: ReceiptKind.extension, no: 13, pay: ReceiptPay.credit, amount: 25000, balance: 5000, qrUrl: qr),
    'payment' => sub(k: ReceiptKind.payment, no: 14, days: null, amount: 10000, balance: 0),
    'info' => sub(k: ReceiptKind.info, balance: -7000, qrUrl: qr),
    _ => ReceiptDoc(
        kind: ReceiptKind.sale,
        issuedAt: DateTime.utc(2026, 10, 29, 15, 40),
        look: look,
        shopName: 'مكتب النجف',
        subscriberName: 'علي حسن',
        username: 'user7',
        phone: '07701234567',
        issuer: 'حسن (emp1)',
        sale: const SaleInvoiceDoc(
          id: 15,
          lines: [(name: 'راوتر', qty: '1', unitPrice: 45000, total: 45000)],
          total: 45000,
          debt: true,
          note: 'ملاحظة <b>',
          voided: true,
          voidReason: 'سبب',
        ),
      ),
  };
}

/// بايتات PDF بلا ما يتغيّر بين بناءين: المعرّف وتاريخ الإنشاء والتعديل (طولها ثابت، فالإزاحات لا تتغيّر).
String _fingerprint(Uint8List bytes) {
  final s = latin1
      .decode(bytes)
      .replaceAll(RegExp(r'/ID\s*\[[^\]]*\]'), '/ID[]')
      .replaceAll(RegExp(r'/CreationDate\s*\([^)]*\)'), '/CreationDate()')
      .replaceAll(RegExp(r'/ModDate\s*\([^)]*\)'), '/ModDate()');
  return sha256.convert(latin1.encode(s)).toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late pw.ThemeData theme;
  setUpAll(() {
    ByteData font(String w) => ByteData.sublistView(File('assets/fonts/IBMPlexSansArabic-$w.ttf').readAsBytesSync());
    theme = pw.ThemeData.withFont(base: pw.Font.ttf(font('400')), bold: pw.Font.ttf(font('700')));
    ReceiptPdf.debugCompress = false;
  });
  tearDownAll(() => ReceiptPdf.debugCompress = true);

  Future<Map<String, String>> buildAll() async {
    final designs = <String, Map<String, dynamic>>{
      for (final e in _v1Designs.entries) e.key: Map<String, dynamic>.from(e.value),
      ..._v2Designs(),
    };
    final out = <String, String>{};
    for (final d in designs.entries) {
      final look = _look(d.value);
      for (final kind in _kinds) {
        for (final a4 in [false, true]) {
          if (a4 && !_a4Designs.contains(d.key)) continue;
          final pdf = await ReceiptPdf.build(_doc(kind, look), a4: a4, theme: theme);
          out['${d.key}/$kind/${a4 ? 'a4' : 'pos'}'] = _fingerprint(pdf.bytes);
        }
      }
    }
    return out;
  }

  test('🔒 وصولات v1 وv2 بايتاً ببايت كما سُجّلت قبل مصمّم v3', () async {
    final got = await buildAll();
    expect(got.length, 90, reason: 'v1: ٦×٥ + ٢×٥ A4 · v2: ٨×٥ + ٢×٥ A4');
    if (Platform.environment['RECORD_RECEIPT_HASHES'] == '1') {
      File(_hashesPath).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(got)}\n');
      return;
    }
    final want = (jsonDecode(File(_hashesPath).readAsStringSync()) as Map).cast<String, String>();
    expect(got.keys.toSet(), want.keys.toSet(), reason: 'مجموعة البصمات تغيّرت');
    final changed = [for (final k in want.keys) if (got[k] != want[k]) k];
    expect(changed, isEmpty, reason: 'وصولٌ تغيّر رسمها: ${changed.join(', ')}');
  });

  test('البناء حتميّ: بناءان متتاليان ببصمةٍ واحدة', () async {
    final look = _look(_v2Designs()['c05']!);
    final a = await ReceiptPdf.build(_doc('activation', look), a4: false, theme: theme);
    final b = await ReceiptPdf.build(_doc('activation', look), a4: false, theme: theme);
    expect(_fingerprint(a.bytes), _fingerprint(b.bytes));
    expect(latin1.decode(a.bytes).contains('/FlateDecode'), isFalse, reason: 'بلا ضغطٍ في البصمة');
  });
}
