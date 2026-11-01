import 'dart:convert';

import 'package:flutter/foundation.dart';

/// «تصميم الوصل» v2/v3 — المالك ١ نوفمبر: «الطباعه اضافة ميزات اخفاء وتقليص الوصل والتحكم اكثر بالمتغيرات انطي صلاحيه
/// تصميم اكثر بوصل الطباعه والمعلومات يتحكم بيها اكثر من الاخفاء والاظهار»، ثمّ «مصمّم احترافي: متغيّرات وأحجام ومحاذاة».
///
/// التصميم في `receipt_settings.design_json` كما هو (مفاتيح v1 لا يتغيّر معناها — التطبيقات القديمة تطبع بها)، وكائنٌ واحد
/// فيه: `design.layout`. v2: الضغط، إظهار كلّ حقلٍ وتسميته وحجمه وعرضه، عناوين الأقسام، عنوانٌ لكلّ نوع وصل، نصوصٌ
/// بمتغيّرات، الرموز و«أسود فقط». v3 = v2 + مفاتيح اختياريّة لكلّ عنصر (حجمٌ ثابت بالنقطة، محاذاة، شكل السطر، مسافة
/// قبل/بعد، خطٌّ تحته، «يظهر في»)، والعملة، وترتيب الكتل والأقسام والحقول، وعشرة أماكن للنصوص. كلّ مفتاحٍ جديد بقيمته
/// الافتراضيّة لا يغيّر شيئاً — تصميم v2 يُطبع بايتاً ببايت كما كان (`test/fixtures/receipt_pdf.hashes.json`). تصميمٌ بلا
/// `layout` يُطبع بطريق v1 كما كان حرفاً بحرف ([ReceiptPdf]).
///
/// [ReceiptResolver.resolve] (التصميم الخامّ + بيانات الوصل ⇒ كتلٌ مرتّبة) نسخةٌ حرفيّة من `resolveReceipt` في الموقع
/// (`client-v2/src/lib/receipt-layout.ts`) — يربطهما ملفّ تثبيتٍ واحد: `test/fixtures/receipt_layout.fixtures.json`
/// (`receipt-layout-fixtures/2`) نسخةٌ بالبايت من ملفّ الموقع، وبصمته [receiptFixturesSha256] مثبّتةٌ في المكانين، والأوّل
/// مجمّداً (`receipt_layout.fixtures.v1.json`، بند العقد 29). غيّرتَ معنى شيءٍ هنا؟ غيّر الملفّ وبصمته في المستودعين معاً.
/// الرسم (PDF الكاشير/A4، `receipt_pdf_v2.dart`) يرسم الكتل وحدها.
///
/// نقيّ: لا ساعة ولا شبكة ولا واجهة — الوقت والرقم يصلان نصّاً جاهزاً، وما لا يُفهم من التصميم افتراضيّ (لا رمي أبداً).

/// بصمة sha256 لملفّ التثبيت المشترك — هي نفسها `RECEIPT_FIXTURES_SHA256` في الموقع.
const String receiptFixturesSha256 = '8e0aa26e3ab0a3773be82acdbd68ca2a4221ed81fad72bd5a9110792718821c5';

// ───────────────────────── الثوابت المشتركة (tokens في ملفّ التثبيت) ─────────────────────────

const List<String> receiptKinds = ['activation', 'extension', 'payment', 'info', 'sale'];
const List<String> receiptSizeSteps = ['xs', 'sm', 'md', 'lg', 'xl'];
const Map<String, num> receiptSizeScale = {'xs': 0.8, 'sm': 0.9, 'md': 1, 'lg': 1.2, 'xl': 1.4};

/// حجم الخطّ = round(font_size_base × النسبة × scale)؛ والعنوان الفرعيّ من font_size_title.
const Map<String, num> receiptRatios = {'value': 0.95, 'label': 0.85, 'caption': 0.78, 'subtitle': 0.8};

/// أماكن النصوص في v2 (الأربعة الأولى) — [receiptTextPos3] تضيف ستّة.
const List<String> receiptTextPositions = ['top', 'after_title', 'before_qr', 'bottom'];
const List<String> receiptDensities = ['normal', 'compact', 'tight'];
const List<String> receiptHAligns = ['right', 'center', 'left'];
const List<String> receiptLabelAligns = ['right', 'center', 'left', 'justify'];

/// رموز الضغط بكسلاً على الويب؛ التطبيق نقاط = بكسل × ٠٫٧٥. «عادي» = أرقام الوصل اليوم.
@immutable
class ReceiptDensityTokens {
  const ReceiptDensityTokens({
    required this.rowPad,
    required this.titlePadV,
    required this.titlePadH,
    required this.titleFill,
    required this.metaPad,
    required this.metaLine,
    required this.qrPad,
    required this.qrLine,
    required this.qrGap,
    required this.footerPad,
    required this.logoGap,
    required this.sectionTitleGap,
    required this.tableGap,
  });

  final double rowPad;
  final double titlePadV;
  final double titlePadH;
  final bool titleFill;
  final double metaPad;
  final bool metaLine;
  final double qrPad;
  final bool qrLine;
  final double qrGap;
  final double footerPad;
  final double logoGap;
  final double sectionTitleGap;
  final double tableGap;

  static ReceiptDensityTokens of(String density) => receiptDensityTokens[density] ?? receiptDensityTokens['normal']!;

  Map<String, Object> toJson() => {
        'row_pad': rowPad,
        'title_pad_v': titlePadV,
        'title_pad_h': titlePadH,
        'title_fill': titleFill,
        'meta_pad': metaPad,
        'meta_line': metaLine,
        'qr_pad': qrPad,
        'qr_line': qrLine,
        'qr_gap': qrGap,
        'footer_pad': footerPad,
        'logo_gap': logoGap,
        'section_title_gap': sectionTitleGap,
        'table_gap': tableGap,
      };
}

const Map<String, ReceiptDensityTokens> receiptDensityTokens = {
  'normal': ReceiptDensityTokens(
      rowPad: 5, titlePadV: 4, titlePadH: 8, titleFill: true, metaPad: 8, metaLine: true, //
      qrPad: 12, qrLine: true, qrGap: 4, footerPad: 8, logoGap: 8, sectionTitleGap: 4, tableGap: 8),
  'compact': ReceiptDensityTokens(
      rowPad: 2, titlePadV: 2, titlePadH: 6, titleFill: true, metaPad: 3, metaLine: true, //
      qrPad: 4, qrLine: true, qrGap: 2, footerPad: 4, logoGap: 3, sectionTitleGap: 1, tableGap: 2),
  'tight': ReceiptDensityTokens(
      rowPad: 1, titlePadV: 1, titlePadH: 4, titleFill: false, metaPad: 2, metaLine: false, //
      qrPad: 2, qrLine: false, qrGap: 1, footerPad: 2, logoGap: 2, sectionTitleGap: 0, tableGap: 0),
};

const List<String> _kAll = receiptKinds;
const List<String> _kSubs = ['activation', 'extension', 'payment', 'info'];
const List<String> _kActExt = ['activation', 'extension'];

/// تعريف الحقل: مجموعته في المصمّم، تسميته، عرضه، اتّجاهه، كيف تُطبع تسميته (row · inline · caption · none)، ومفتاح v1
/// الذي يحكم ظهوره (إن وُجد ⇒ `fields[id].show` يُهمل — مصدرٌ واحد للحقيقة)، والأنواع التي يمكن أن يظهر فيها.
@immutable
class ReceiptFieldDef {
  const ReceiptFieldDef(
    this.group,
    this.label, {
    required this.bold,
    required this.ltr,
    required this.mode,
    required this.kinds,
    this.v1,
  });

  final String group;
  final String label;
  final bool bold;
  final bool ltr;
  final String mode;
  final String? v1;

  /// أنواع الوصل التي يمكن أن يظهر فيها (المصمّم: «لا يظهر في وصل التسديد»).
  final List<String> kinds;

  Map<String, Object?> toJson() =>
      {'group': group, 'label': label, 'bold': bold, 'ltr': ltr, 'mode': mode, 'v1': v1, 'kinds': kinds};
}

/// الترتيب = ترتيب الوصل.
const List<String> receiptFieldIds = [
  'shop_name', 'shop_address', 'shop_phone', 'title', 'receipt_no', 'issued_at', //
  'subscriber_name', 'username', 'phone', //
  'package_name', 'package_price', 'expiry_date', 'days_remaining', //
  'payment_type', 'amount', 'cash_paid', 'balance_debt', 'balance_credit', //
  'qr_caption', 'issuer', 'footer_text',
];

/// محجوزة للمرحلة ٢ (يحفظها الخادم، ولا تُطبع بعد).
const List<String> receiptReservedFieldIds = ['old_debt', 'discount_amount', 'card_tail'];

/// كلّ معرّفات الحقول التي يقبلها الخادم (٢١ + ٣ محجوزة) — بترتيبه القانونيّ.
const List<String> receiptAllFieldIds = [...receiptFieldIds, ...receiptReservedFieldIds];

const Map<String, ReceiptFieldDef> receiptFieldDefs = {
  'shop_name': ReceiptFieldDef('header', '', bold: true, ltr: false, mode: 'none', kinds: _kAll),
  'shop_address': ReceiptFieldDef('header', '', bold: false, ltr: false, mode: 'inline', kinds: _kAll),
  'shop_phone': ReceiptFieldDef('header', '', bold: false, ltr: true, mode: 'inline', kinds: _kAll),
  'title': ReceiptFieldDef('header', '', bold: true, ltr: false, mode: 'none', kinds: _kAll),
  'receipt_no': ReceiptFieldDef('header', '#', bold: false, ltr: true, mode: 'inline', v1: 'show_receipt_id', kinds: _kSubs),
  'issued_at': ReceiptFieldDef('header', '', bold: false, ltr: true, mode: 'inline', v1: 'show_datetime', kinds: _kAll),
  'subscriber_name': ReceiptFieldDef('subscriber', 'الاسم', bold: true, ltr: false, mode: 'row', kinds: _kAll),
  'username': ReceiptFieldDef('subscriber', 'اسم المستخدم', bold: false, ltr: true, mode: 'row', kinds: _kAll),
  'phone': ReceiptFieldDef('subscriber', 'الهاتف', bold: false, ltr: true, mode: 'row', kinds: _kAll),
  'package_name': ReceiptFieldDef('package', 'الباقة', bold: true, ltr: false, mode: 'row', kinds: _kSubs),
  'package_price':
      ReceiptFieldDef('package', 'سعر الباقة', bold: true, ltr: false, mode: 'row', v1: 'show_package_price', kinds: _kSubs),
  'expiry_date': ReceiptFieldDef('package', 'تاريخ الانتهاء', bold: false, ltr: true, mode: 'row', kinds: _kSubs),
  'days_remaining': ReceiptFieldDef('package', 'الأيام المتبقّية',
      bold: true, ltr: false, mode: 'row', kinds: ['activation', 'extension', 'info']),
  'payment_type': ReceiptFieldDef('transaction', 'طريقة الدفع', bold: true, ltr: false, mode: 'row', kinds: _kActExt),
  'amount': ReceiptFieldDef('transaction', 'المبلغ',
      bold: true, ltr: false, mode: 'row', kinds: ['activation', 'extension', 'payment']),
  'cash_paid': ReceiptFieldDef('transaction', 'المُدفَع نقداً', bold: true, ltr: false, mode: 'row', kinds: _kActExt),
  'balance_debt': ReceiptFieldDef('transaction', 'الدين المتبقّي', bold: true, ltr: false, mode: 'row', kinds: _kSubs),
  'balance_credit': ReceiptFieldDef('transaction', 'الرصيد المتبقّي', bold: true, ltr: false, mode: 'row', kinds: _kSubs),
  'qr_caption':
      ReceiptFieldDef('qr', 'امسح للاطلاع على معلومات الاشتراك', bold: false, ltr: false, mode: 'caption', kinds: _kSubs),
  'issuer':
      ReceiptFieldDef('footer', 'أصدره', bold: false, ltr: false, mode: 'inline', v1: 'show_manager_signature', kinds: _kAll),
  'footer_text': ReceiptFieldDef('footer', '', bold: false, ltr: false, mode: 'none', kinds: _kAll),
};

/// تسمياتٌ افتراضيّة تتغيّر بالحال (ما لم يكتب الوكيل تسميته).
const Map<String, String> receiptLabelVariants = {'amount_payment': 'المبلغ المسدَّد', 'balance_zero': 'الرصيد'};

const List<String> receiptSectionIds = ['subscriber', 'package', 'transaction', 'sale_customer', 'sale_items', 'sale_totals'];

/// أقسام الجسم الثلاثة (ترتيبها `order.body`).
const List<String> receiptBodySections = ['subscriber', 'package', 'transaction'];

/// '' = بلا عنوانٍ افتراضيّ (مجموع الفاتورة كما على الويب) — يظهر إن كتب الوكيل عنواناً.
const Map<String, String> receiptSectionTitles = {
  'subscriber': 'المشترك',
  'package': 'الباقة',
  'transaction': 'المعاملة',
  'sale_customer': 'الزبون',
  'sale_items': 'المواد',
  'sale_totals': '',
};

const Map<String, String> receiptDefaultTitles = {
  'activation': 'وصل تفعيل',
  'extension': 'وصل تمديد',
  'payment': 'وصل تسديد دين',
  'info': 'بطاقة معلومات المشترك',
  'sale': 'فاتورة بيع رقم {receipt_no}',
};

/// {receipt_type} — اسم النوع بلا رقم.
const Map<String, String> receiptTypeLabels = {
  'activation': 'وصل تفعيل',
  'extension': 'وصل تمديد',
  'payment': 'وصل تسديد دين',
  'info': 'بطاقة معلومات المشترك',
  'sale': 'فاتورة بيع',
};

const Map<String, String> receiptPaymentLabels = {'cash': 'نقدي', 'partial-cash': 'نقدي جزئي', 'non-cash': 'غير نقدي'};

const Map<String, String> receiptSaleLabels = {
  'total': 'المجموع',
  'payment': 'طريقة الدفع',
  'cash': 'نقداً',
  'debt': 'على حساب المشترك (دين)',
  'void': 'مُلغاة',
  'note': 'ملاحظة',
  'customer': 'زبون',
};

const String receiptDefaultFooter = 'شكراً لاختياركم خدماتنا';
const String receiptDefaultShopName = 'MyServices';
const Map<String, Object> receiptTextDefaults = {'align': 'center', 'size': 'md', 'bold': false, 'boxed': false};
const Map<String, int> receiptLimits = {
  'label': 40,
  'sectionTitle': 40,
  'typeTitle': 60,
  'text': 300,
  'textLines': 4,
  'texts': 6,
  'fields': 40,
  'layoutBytes': 12000,
};

/// ما يقرؤه المحلِّل من مفاتيح v1 (والافتراضيّ إن غاب).
const Map<String, Object> receiptV1Defaults = {
  'show_logo': true,
  'show_shop_info': true,
  'show_subscriber_info': true,
  'show_package_info': true,
  'show_package_price': true,
  'show_transaction_info': true,
  'show_footer': true,
  'show_manager_signature': true,
  'show_receipt_id': true,
  'show_datetime': true,
  'default_align': 'right',
  'header_align': 'center',
  'footer_align': 'center',
  'logo_align': 'center',
  'qr_align': 'center',
};

@immutable
class ReceiptVarDef {
  const ReceiptVarDef(this.id, this.label, this.kinds, this.group);

  final String id;
  final String label;
  final List<String> kinds;

  /// مجموعته في «إدراج متغيّر» ([receiptVarGroups]).
  final String group;

  Map<String, Object> toJson() => {'id': id, 'label': label, 'kinds': kinds, 'group': group};
}

/// مجموعات «إدراج متغيّر» بأسمائها (بترتيب العرض).
const List<({String id, String label})> receiptVarGroups = [
  (id: 'shop', label: 'المحلّ'),
  (id: 'receipt', label: 'الوصل'),
  (id: 'subscriber', label: 'المشترك'),
  (id: 'package', label: 'الباقة'),
  (id: 'money', label: 'المال'),
  (id: 'sale', label: 'الفاتورة'),
];

/// المتغيّرات بأسماء قوالب واتساب. متغيّرٌ نوعُ الوصل خارج kinds قيمته فارغة دائماً.
const List<ReceiptVarDef> receiptVariables = [
  ReceiptVarDef('shop_name', 'اسم المحلّ', _kAll, 'shop'),
  ReceiptVarDef('shop_phone', 'هاتف المحلّ', _kAll, 'shop'),
  ReceiptVarDef('shop_address', 'عنوان المحلّ', _kAll, 'shop'),
  ReceiptVarDef('receipt_type', 'نوع الوصل', _kAll, 'receipt'),
  ReceiptVarDef('receipt_no', 'رقم الوصل', _kAll, 'receipt'),
  ReceiptVarDef('date', 'التاريخ', _kAll, 'receipt'),
  ReceiptVarDef('time', 'الوقت', _kAll, 'receipt'),
  ReceiptVarDef('issuer', 'أصدره', _kAll, 'receipt'),
  ReceiptVarDef('subscriber_name', 'اسم المشترك', _kAll, 'subscriber'),
  ReceiptVarDef('firstname', 'الاسم الأول', _kAll, 'subscriber'),
  ReceiptVarDef('username', 'اسم المستخدم', _kAll, 'subscriber'),
  ReceiptVarDef('phone', 'هاتف المشترك', _kAll, 'subscriber'),
  ReceiptVarDef('package_name', 'الباقة', _kSubs, 'package'),
  ReceiptVarDef('sas_package_name', 'الباقة في الساس', _kSubs, 'package'),
  ReceiptVarDef('package_price', 'سعر الباقة', _kSubs, 'package'),
  ReceiptVarDef('expiry_date', 'تاريخ الانتهاء', _kSubs, 'package'),
  ReceiptVarDef('days_remaining', 'الأيام المتبقّية (رقم)', ['activation', 'extension', 'info'], 'package'),
  ReceiptVarDef('remaining_days', 'الأيام المتبقّية', ['activation', 'extension', 'info'], 'package'),
  ReceiptVarDef('payment_type', 'طريقة الدفع', _kActExt, 'money'),
  ReceiptVarDef('amount', 'المبلغ', ['activation', 'extension', 'payment'], 'money'),
  ReceiptVarDef('paid_amount', 'المدفوع', ['activation', 'extension', 'payment'], 'money'),
  ReceiptVarDef('debt_amount', 'الدين', _kSubs, 'money'),
  ReceiptVarDef('credit_amount', 'الرصيد', _kSubs, 'money'),
  ReceiptVarDef('balance', 'الدين أو الرصيد', _kSubs, 'money'),
  ReceiptVarDef('sale_total', 'مجموع الفاتورة', ['sale'], 'sale'),
  ReceiptVarDef('sale_payment', 'دفع الفاتورة', ['sale'], 'sale'),
];

@immutable
class ReceiptPresetDef {
  const ReceiptPresetDef(this.label, this.v1, {required this.density, required this.emoji});

  final String label;

  /// مفاتيح v1 التي يكتبها القالب (فيقصر الوصل حتى في تطبيق 3.0.13).
  final Map<String, Object> v1;
  final String density;
  final bool emoji;

  Map<String, Object> toJson() => {'label': label, 'v1': v1, 'density': density, 'emoji': emoji};
}

/// «حجم الوصل».
const Map<String, ReceiptPresetDef> receiptPresets = {
  'normal': ReceiptPresetDef(
    'عادي',
    {
      'font_size_base': 13, 'font_size_title': 16, 'section_gap_mm': 6, 'line_height': 1.5, //
      'margin_top_mm': 4, 'margin_right_mm': 4, 'margin_bottom_mm': 4, 'margin_left_mm': 4, //
      'logo_size_mm': 18, 'qr_size_mm': 35, 'row_separator': 'dotted', 'section_title_underline': true,
    },
    density: 'normal',
    emoji: true,
  ),
  'compact': ReceiptPresetDef(
    'مضغوط',
    {
      'font_size_base': 11, 'font_size_title': 14, 'section_gap_mm': 2, 'line_height': 1.25, //
      'margin_top_mm': 2, 'margin_right_mm': 2, 'margin_bottom_mm': 2, 'margin_left_mm': 2, //
      'logo_size_mm': 12, 'qr_size_mm': 24, 'row_separator': 'dotted', 'section_title_underline': true,
    },
    density: 'compact',
    emoji: false,
  ),
  'tight': ReceiptPresetDef(
    'مضغوط جداً',
    {
      'font_size_base': 10, 'font_size_title': 13, 'section_gap_mm': 1, 'line_height': 1.1, //
      'margin_top_mm': 1, 'margin_right_mm': 1, 'margin_bottom_mm': 1, 'margin_left_mm': 1, //
      'logo_size_mm': 9, 'qr_size_mm': 20, 'row_separator': 'none', 'section_title_underline': false,
    },
    density: 'tight',
    emoji: false,
  ),
};

// ───────────────────────── ثوابت v3 (spec §1) ─────────────────────────

/// أحجامٌ مثبّتة بالنقطة (`pt`) — نقطة PDF = نقطة CSS، فالموقع والتطبيق يطبعان الحجم نفسه.
const List<num> receiptPtSteps = [6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20, 24];
const List<String> receiptSeps = ['none', 'dotted', 'dashed', 'solid'];
const List<String> receiptRowModes = ['line', 'stack', 'value'];
const List<String> receiptDigits = ['latin', 'arabic'];
const String receiptDefaultCurrency = 'د.ع';

/// ترتيب كتل الوصل الافتراضيّ (= ترتيب اليوم).
const List<String> receiptBlockIds = ['logo', 'shop_name', 'shop_lines', 'title', 'meta', 'body', 'qr', 'footer'];

/// الحاويات (`layout.blocks[id]`): مسافةٌ قبل/بعد، وخطٌّ تحت، و«يظهر في».
const List<String> receiptContainerIds = ['logo', 'shop_lines', 'meta', 'qr', 'footer'];

/// صفوف الأقسام الثلاثة (تنتقل بينها) + ثلاثةٌ محجوزة للمرحلة ٢ (لا تُرسم في المرحلة ١).
const List<String> receiptRowFieldIds = [
  'subscriber_name', 'username', 'phone', //
  'package_name', 'package_price', 'expiry_date', 'days_remaining', //
  'payment_type', 'amount', 'cash_paid', 'balance_debt', 'balance_credit', //
  'old_debt', 'discount_amount', 'card_tail',
];

/// قسم كلّ صفٍّ الافتراضيّ.
const Map<String, String> receiptRowFieldSection = {
  'subscriber_name': 'subscriber',
  'username': 'subscriber',
  'phone': 'subscriber',
  'package_name': 'package',
  'package_price': 'package',
  'expiry_date': 'package',
  'days_remaining': 'package',
  'payment_type': 'transaction',
  'amount': 'transaction',
  'cash_paid': 'transaction',
  'balance_debt': 'transaction',
  'balance_credit': 'transaction',
  'old_debt': 'transaction',
  'discount_amount': 'transaction',
  'card_tail': 'transaction',
};

/// أماكن النصوص العشرة بأسمائها، بترتيبها في الوصل الافتراضيّ (spec §1.4).
const List<({String id, String label})> receiptTextPos3 = [
  (id: 'top', label: 'أعلى الوصل'),
  (id: 'after_shop', label: 'بعد العنوان والهاتف'),
  (id: 'after_title', label: 'بعد عنوان الوصل'),
  (id: 'after_meta', label: 'بعد الرقم والتاريخ'),
  (id: 'after_subscriber', label: 'بعد قسم المشترك'),
  (id: 'after_package', label: 'بعد قسم الباقة'),
  (id: 'after_transaction', label: 'بعد قسم المعاملة'),
  (id: 'before_qr', label: 'قبل رمز QR'),
  (id: 'before_footer', label: 'قبل الذيل'),
  (id: 'bottom', label: 'أسفل الوصل'),
];
const List<String> receiptTextPos3Ids = [
  'top', 'after_shop', 'after_title', 'after_meta', 'after_subscriber', 'after_package', 'after_transaction', //
  'before_qr', 'before_footer', 'bottom',
];

const List<String> _rowCaps = [
  'show', 'label', 'size', 'bold', 'pt', 'align', 'row_mode', 'gap_before', 'gap_after', 'sep', 'only', //
];
const List<String> _rowCapsV1 = ['label', 'size', 'bold', 'pt', 'align', 'row_mode', 'gap_before', 'gap_after', 'sep', 'only'];
const List<String> _metaCaps = ['label', 'bold', 'pt', 'align', 'row_mode', 'gap_before', 'gap_after', 'only'];

/// ما يقبله كلّ حقلٍ من خصائص (spec §1.3) — المصمّم لا يعرض غيرها، والضغط لا يحفظ غيرها، والخادم في v3 يرفض غيرها.
/// `show` غائبٌ عن الحقول الأربعة المربوطة بمفاتيح v1 (إظهارها من مفاتيحها).
const Map<String, List<String>> receiptFieldCaps = {
  'shop_name': ['show', 'size', 'bold', 'pt', 'align', 'gap_before', 'gap_after', 'sep', 'only'],
  'shop_address': _rowCaps,
  'shop_phone': _rowCaps,
  'title': ['show', 'size', 'bold', 'pt', 'align', 'gap_before', 'gap_after', 'only'],
  'receipt_no': _metaCaps,
  'issued_at': _metaCaps,
  'subscriber_name': _rowCaps,
  'username': _rowCaps,
  'phone': _rowCaps,
  'package_name': _rowCaps,
  'package_price': _rowCapsV1,
  'expiry_date': _rowCaps,
  'days_remaining': _rowCaps,
  'payment_type': _rowCaps,
  'amount': _rowCaps,
  'cash_paid': _rowCaps,
  'balance_debt': _rowCaps,
  'balance_credit': _rowCaps,
  'qr_caption': ['show', 'label', 'bold', 'pt', 'align', 'only'],
  'issuer': _rowCapsV1,
  'footer_text': ['show', 'size', 'bold', 'pt', 'align', 'gap_before', 'gap_after', 'sep', 'only'],
  'old_debt': _rowCaps,
  'discount_amount': _rowCaps,
  'card_tail': _rowCaps,
};
const List<String> _bodySecCaps = ['title', 'show_title', 'pt', 'align', 'gap_before', 'gap_after', 'only'];
const List<String> _saleSecCaps = ['title', 'show_title', 'pt', 'align', 'gap_before', 'gap_after'];

/// خصائص الأقسام: «يظهر في» لأقسام الجسم الثلاثة وحدها (بنية الفاتورة ثابتة). pt/align لعنوان القسم.
const Map<String, List<String>> receiptSectionCaps = {
  'subscriber': _bodySecCaps,
  'package': _bodySecCaps,
  'transaction': _bodySecCaps,
  'sale_customer': _saleSecCaps,
  'sale_items': _saleSecCaps,
  'sale_totals': _saleSecCaps,
};
const List<String> _blockCapsAll = ['gap_before', 'gap_after', 'sep', 'only'];
const Map<String, List<String>> receiptContainerCaps = {
  'logo': _blockCapsAll,
  'shop_lines': _blockCapsAll,
  'meta': _blockCapsAll,
  'qr': _blockCapsAll,
  'footer': _blockCapsAll,
};
const List<String> receiptTextCaps = [
  'id', 'at', 'text', 'align', 'size', 'bold', 'boxed', 'only', 'pt', 'gap_before', 'gap_after', 'sep', //
];

/// حدود v3 (الخادم يرفض ما تجاوزها برسالةٍ ومسار — لا قصّ صامت).
const Map<String, num> receiptLimits3 = {
  'label': 40,
  'sectionTitle': 40,
  'typeTitle': 60,
  'text': 300,
  'textLines': 4,
  'texts': 6,
  'currency': 8,
  'gapMax': 10,
  'gapStep': 0.5,
  'layoutBytes': 16384,
};

/// مفاتيح v1 الستّة والثلاثون بافتراضيّاتها (= `sanitizeV1({})` في الخادم، بترتيبه) — الحفظ يرسلها كلّها (الخادم يعيد كلّ
/// مفتاحٍ غائب لافتراضه).
const Map<String, Object> receiptV1AllDefaults = {
  'paper_width_mm': 80,
  'margin_top_mm': 4,
  'margin_right_mm': 4,
  'margin_bottom_mm': 4,
  'margin_left_mm': 4,
  'a4_orientation': 'portrait',
  'font_family': 'Cairo',
  'font_size_base': 13,
  'font_size_title': 16,
  'font_weight': '700',
  'accent_color': '#0d9488',
  'text_color': '#0f172a',
  'border_style': 'dashed',
  'border_radius_px': 8,
  'section_gap_mm': 6,
  'line_height': 1.5,
  'default_align': 'right',
  'header_align': 'center',
  'footer_align': 'center',
  'logo_size_mm': 18,
  'logo_align': 'center',
  'qr_size_mm': 35,
  'qr_align': 'center',
  'row_separator': 'dotted',
  'section_title_uppercase': true,
  'section_title_underline': true,
  'show_logo': true,
  'show_shop_info': true,
  'show_subscriber_info': true,
  'show_package_info': true,
  'show_transaction_info': true,
  'show_footer': true,
  'show_manager_signature': true,
  'show_receipt_id': true,
  'show_datetime': true,
  'show_package_price': true,
};

/// «قوالب جاهزة»: إعداداتٌ عامّة وحدها — لا تمسّ الحقول ولا النصوص ولا العناوين ولا الرموز.
@immutable
class ReceiptTemplateDef {
  const ReceiptTemplateDef(this.label, {required this.paperSize, required this.v1, required this.density, required this.mono});

  final String label;
  final String paperSize;
  final Map<String, Object> v1;
  final String density;
  final bool mono;

  Map<String, Object> toJson() => {
        'label': label,
        'paper_size': paperSize,
        'v1': v1,
        'layout': {'density': density, 'mono': mono},
      };
}

const List<String> receiptTemplateIds = ['pos58_compact', 'pos80', 'a4_formal'];

final Map<String, ReceiptTemplateDef> receiptTemplates = {
  'pos58_compact': ReceiptTemplateDef(
    'كاشير ٥٨ مضغوط',
    paperSize: 'pos',
    v1: {'paper_width_mm': 58, ...receiptPresets['compact']!.v1},
    density: 'compact',
    mono: true,
  ),
  'pos80': ReceiptTemplateDef(
    'كاشير ٨٠',
    paperSize: 'pos',
    v1: {'paper_width_mm': 80, ...receiptPresets['normal']!.v1},
    density: 'normal',
    mono: true,
  ),
  'a4_formal': const ReceiptTemplateDef(
    'A4 رسمي',
    paperSize: 'a4',
    v1: {
      'a4_orientation': 'portrait',
      'font_size_base': 14,
      'font_size_title': 20,
      'section_gap_mm': 6,
      'line_height': 1.5,
      'margin_top_mm': 12,
      'margin_right_mm': 12,
      'margin_bottom_mm': 12,
      'margin_left_mm': 12,
      'logo_size_mm': 22,
      'qr_size_mm': 30,
      'row_separator': 'solid',
      'section_title_underline': true,
      'border_style': 'none',
    },
    density: 'normal',
    mono: false,
  ),
};

/// عيّنات المعاينة (الموقع والتطبيق): أرقامٌ متّسقة — باقة ٣٥٬٠٠٠، جزئيّ ٢٥٬٠٠٠، دين ١٠٬٠٠٠. `issuedText` null = «الآن».
const Map<String, Object?> _sampleSub = {
  'username': 'sample.user',
  'fullName': 'محمد علي',
  'phone': '07700000000',
  'profileName': 'Economy',
  'packagePrice': 35000,
};
const Map<String, Map<String, Object?>> receiptPreviewSamples = {
  'activation': {
    'receiptNo': 12,
    'issuedText': null,
    'subscriber': {..._sampleSub, 'expiration': '2026-12-01 10:00', 'remainingDays': 30},
    'amount': 35000,
    'paymentType': 'partial-cash',
    'partialAmount': 25000,
    'newBalance': -10000,
    'qr': true,
    'sale': null,
  },
  'extension': {
    'receiptNo': 13,
    'issuedText': null,
    'subscriber': {..._sampleSub, 'expiration': '2026-12-31 10:00', 'remainingDays': 60},
    'amount': 35000,
    'paymentType': 'cash',
    'partialAmount': null,
    'newBalance': 0,
    'qr': true,
    'sale': null,
  },
  'payment': {
    'receiptNo': 14,
    'issuedText': null,
    'subscriber': {..._sampleSub, 'expiration': '2026-12-01 10:00', 'remainingDays': null},
    'amount': 25000,
    'paymentType': null,
    'partialAmount': null,
    'newBalance': -10000,
    'qr': true,
    'sale': null,
  },
  'info': {
    'receiptNo': null,
    'issuedText': null,
    'subscriber': {..._sampleSub, 'expiration': '2026-12-01 10:00', 'remainingDays': 30},
    'amount': null,
    'paymentType': null,
    'partialAmount': null,
    'newBalance': -10000,
    'qr': true,
    'sale': null,
  },
  'sale': {
    'receiptNo': 128,
    'issuedText': null,
    'subscriber': {
      'username': 'sample.user',
      'fullName': 'محمد علي',
      'phone': '07700000000',
      'profileName': null,
      'packagePrice': null,
      'expiration': null,
      'remainingDays': null,
    },
    'amount': null,
    'paymentType': null,
    'partialAmount': null,
    'newBalance': null,
    'qr': false,
    'sale': {
      'id': 128,
      'dateText': '2026-10-29 14:30',
      'payment': 'cash',
      'total': 42500,
      'lines': [
        {'name': 'راوتر TP-Link', 'qtyText': '1 قطعة', 'unitPrice': 35000, 'total': 35000},
        {'name': 'كيبل شبكة', 'qtyText': '15 متر', 'unitPrice': 500, 'total': 7500},
      ],
    },
  },
};

/// الثوابت بشكل `tokens` في ملفّ التثبيت (الاختبار يقارنها حرفاً بحرف).
Map<String, Object?> receiptLayoutTokens() => {
      'KINDS': receiptKinds,
      'SIZE_STEPS': receiptSizeSteps,
      'SIZE_SCALE': receiptSizeScale,
      'RATIOS': receiptRatios,
      'TEXT_POS': receiptTextPositions,
      'DENSITIES': receiptDensities,
      'DENSITY': {for (final e in receiptDensityTokens.entries) e.key: e.value.toJson()},
      'FIELD_IDS': receiptFieldIds,
      'FIELD_DEFS': {for (final e in receiptFieldDefs.entries) e.key: e.value.toJson()},
      'LABEL_VARIANTS': receiptLabelVariants,
      'SECTION_IDS': receiptSectionIds,
      'SECTION_TITLES': receiptSectionTitles,
      'DEFAULT_TITLES': receiptDefaultTitles,
      'RECEIPT_TYPE_LABELS': receiptTypeLabels,
      'PAYMENT_TYPE_LABELS': receiptPaymentLabels,
      'SALE_LABELS': receiptSaleLabels,
      'DEFAULT_FOOTER': receiptDefaultFooter,
      'DEFAULT_SHOP_NAME': receiptDefaultShopName,
      'TEXT_DEFAULTS': receiptTextDefaults,
      'LIMITS': receiptLimits,
      'V1_DEFAULTS': receiptV1Defaults,
      'VARIABLES': [for (final v in receiptVariables) v.toJson()],
      'PRESETS': {for (final e in receiptPresets.entries) e.key: e.value.toJson()},
      'PT_STEPS': receiptPtSteps,
      'SEPS': receiptSeps,
      'ROW_MODES': receiptRowModes,
      'DIGITS': receiptDigits,
      'DEFAULT_CURRENCY': receiptDefaultCurrency,
      'BLOCK_IDS': receiptBlockIds,
      'CONTAINER_IDS': receiptContainerIds,
      'BODY_SECTION_IDS': receiptBodySections,
      'RESERVED_FIELD_IDS': receiptReservedFieldIds,
      'ALL_FIELD_IDS': receiptAllFieldIds,
      'ROW_FIELD_IDS': receiptRowFieldIds,
      'ROW_FIELD_SECTION': receiptRowFieldSection,
      'TEXT_POS3': [for (final p in receiptTextPos3) {'id': p.id, 'label': p.label}],
      'FIELD_CAPS': receiptFieldCaps,
      'SECTION_CAPS': receiptSectionCaps,
      'CONTAINER_CAPS': receiptContainerCaps,
      'TEXT_CAPS': receiptTextCaps,
      'VAR_IDS': [for (final v in receiptVariables) v.id],
      'VAR_GROUPS': [for (final g in receiptVarGroups) {'id': g.id, 'label': g.label}],
      'LIMITS3': receiptLimits3,
      'V1_ALL_DEFAULTS': receiptV1AllDefaults,
      'TEMPLATE_IDS': receiptTemplateIds,
      'TEMPLATES': {for (final e in receiptTemplates.entries) e.key: e.value.toJson()},
      'PREVIEW_SAMPLES': receiptPreviewSamples,
    };

// ───────────────────────── قراءة JSON بدلالات الموقع ─────────────────────────

/// `String(n)` في JS: العدد الصحيح بلا فاصلة عشريّة (30 ⇒ '30' لا '30.0').
String _jsNum(num n) {
  if (n is int) return '$n';
  if (n.isFinite && n == n.truncateToDouble() && n.abs() < 1e21) return n.toInt().toString();
  return '$n';
}

/// `str()` في الموقع: النصّ مشذَّباً، والعدد المحدود نصّاً، وغيرهما ''.
String _str(Object? s) => s is String ? s.trim() : (s is num && s.isFinite ? _jsNum(s) : '');

/// `num()` في الموقع: العدد المحدود وحده، وغيره null (النصّ «25000» ليس عدداً).
num? _num(Object? n) => n is num && n.isFinite ? n : null;

/// `Number(n) || 0` في الموقع (مبالغ الفاتورة).
num _number(Object? n) {
  if (n is num) return n.isFinite ? n : 0;
  if (n is bool) return n ? 1 : 0;
  if (n is String) {
    final t = n.trim();
    if (t.isEmpty) return 0;
    final v = num.tryParse(t);
    return v == null || !v.isFinite ? 0 : v;
  }
  return 0;
}

/// صدق JS (`!!x`).
bool _truthy(Object? v) =>
    v == true || (v is num && v != 0 && !v.isNaN) || (v is String && v.isNotEmpty) || v is Map || v is List;

String? _oneOf(Object? v, List<String> list) => v is String && list.contains(v) ? v : null;

/// العدد الصحيح بلا كسرٍ عشريّ صحيحاً (1.0 ⇒ 1) — JSON كالموقع.
num _tidy(num v) => v is double && v.isFinite && v == v.truncateToDouble() ? v.toInt() : v;

/// pt من [receiptPtSteps] وحدها.
num? _ptOf(Object? v) => v is num && receiptPtSteps.contains(v) ? _tidy(v) : null;

/// مسافةٌ بالملّيمتر: رقمٌ محصور ٠–١٠ مقرَّب لأقرب نصف؛ ٠ ⇒ null (غائب) — `gapOf` في الموقع.
num? receiptGapOf(Object? v) {
  if (v is! num || !v.isFinite) return null;
  final g = (v.clamp(0, 10) * 2).round() / 2;
  return g > 0 ? _tidy(g) : null;
}

/// «يظهر في»: الأنواع المعروفة بترتيبها (فارغ ⇒ null = كلّ الأنواع) — `onlyOf` في الموقع.
List<String>? _onlyOf(Object? v) {
  if (v is! List) return null;
  final out = [for (final k in receiptKinds) if (v.contains(k)) k];
  return out.isEmpty ? null : out;
}

/// العملة: سطرٌ واحد ≤ ٨ نقاط ترميز بعد التشذيب ('' = بلا وحدة)؛ غير ذلك «د.ع».
String _currencyOf(Object? v) {
  if (v is! String) return receiptDefaultCurrency;
  final s = v.trim();
  return s.contains(RegExp(r'[\r\n]')) || s.runes.length > receiptLimits3['currency']! ? receiptDefaultCurrency : s;
}

/// ‎`25,000 د.ع`‎: تقريب القيمة المطلقة وفواصل الآلاف الإنجليزيّة، ثمّ العملة ('' = بلا وحدة).
String receiptMoney(Object? n, [String currency = receiptDefaultCurrency]) {
  final v = _number(n).abs().round();
  final s = '$v';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return currency == '' ? '$b' : '$b $currency';
}

/// ترتيب الكتل المحلول: المعروف من القائمة بلا تكرار، ثمّ الناقص بترتيبه الافتراضيّ.
List<String> receiptResolveBlockOrder(Object? list) => _resolveList(list, receiptBlockIds);
List<String> receiptResolveBodyOrder(Object? list) => _resolveList(list, receiptBodySections);

List<String> _resolveList(Object? given, List<String> all) {
  final out = <String>[];
  if (given is List) {
    for (final x in given) {
      if (x is String && all.contains(x) && !out.contains(x)) out.add(x);
    }
  }
  for (final x in all) {
    if (!out.contains(x)) out.add(x);
  }
  return out;
}

/// حقول كلّ قسم (بند 20): `order[قسم]` ∩ الصفوف — أوّل ظهورٍ بترتيب الأقسام القانونيّ يفوز — ثمّ ما لم يُوضع في قسمه
/// الافتراضيّ بترتيبه.
Map<String, List<String>> receiptResolveSectionFields(Object? order) {
  final o = order is Map ? order : const {};
  final out = <String, List<String>>{'subscriber': [], 'package': [], 'transaction': []};
  final placed = <String>{};
  for (final sec in receiptBodySections) {
    final raw = o[sec];
    if (raw is! List) continue;
    for (final x in raw) {
      if (x is! String || !receiptRowFieldIds.contains(x) || placed.contains(x)) continue;
      out[sec]!.add(x);
      placed.add(x);
    }
  }
  for (final id in receiptRowFieldIds) {
    if (!placed.contains(id)) out[receiptRowFieldSection[id]]!.add(id);
  }
  return out;
}

// ───────────────────────── التصميم (layout) بتسامح ─────────────────────────

@immutable
class ReceiptFieldStyle {
  const ReceiptFieldStyle({
    this.show,
    this.label,
    this.size,
    this.bold,
    this.pt,
    this.align,
    this.rowMode,
    this.gapBefore,
    this.gapAfter,
    this.sep,
    this.only,
  });

  final bool? show;

  /// '' = بلا تسمية.
  final String? label;
  final String? size;
  final bool? bold;

  /// v3: حجمٌ ثابت بالنقطة — يتقدّم على [size].
  final num? pt;

  /// v3: محاذاةٌ فيزيائيّة.
  final String? align;

  /// v3: `stack` (التسمية فوق القيمة) أو `value` (القيمة وحدها)؛ null = بسطرٍ واحد.
  final String? rowMode;
  final num? gapBefore;
  final num? gapAfter;
  final String? sep;

  /// null = كلّ الأنواع.
  final List<String>? only;
}

@immutable
class ReceiptSectionStyle {
  const ReceiptSectionStyle({this.title, this.showTitle, this.pt, this.align, this.gapBefore, this.gapAfter, this.only});

  final String? title;
  final bool? showTitle;
  final num? pt;
  final String? align;
  final num? gapBefore;
  final num? gapAfter;
  final List<String>? only;
}

/// v3: الحاويات (الشعار، العنوان والهاتف، الرقم والتاريخ، رمز QR، الذيل).
@immutable
class ReceiptBlockStyle {
  const ReceiptBlockStyle({this.gapBefore, this.gapAfter, this.sep, this.only});

  final num? gapBefore;
  final num? gapAfter;
  final String? sep;
  final List<String>? only;
}

@immutable
class ReceiptCustomText {
  const ReceiptCustomText({
    required this.id,
    required this.at,
    required this.text,
    this.align = 'center',
    this.size = 'md',
    this.bold = false,
    this.boxed = false,
    this.only = const [],
    this.pt,
    this.gapBefore = 0,
    this.gapAfter = 0,
    this.sep,
  });

  final String id;
  final String at;
  final String text;
  final String align;
  final String size;
  final bool bold;
  final bool boxed;

  /// فارغ = كلّ أنواع الوصل.
  final List<String> only;
  final num? pt;
  final num gapBefore;
  final num gapAfter;
  final String? sep;
}

/// `design.layout` مقروءاً بتسامح (`normalizeLayout` في الموقع): ما لا يُفهم افتراضيّ، والمعرّفات المجهولة تُهمل.
@immutable
class ReceiptLayout {
  const ReceiptLayout({
    this.density = 'normal',
    this.emoji = true,
    this.mono = false,
    this.currency = receiptDefaultCurrency,
    this.digits = 'latin',
    this.fields = const {},
    this.sections = const {},
    this.blocks = const {},
    this.titles = const {},
    this.texts = const [],
    this.blockOrder = receiptBlockIds,
    this.bodyOrder = receiptBodySections,
    this.sectionFields = const {},
  });

  final String density;
  final bool emoji;
  final bool mono;

  /// v3: وحدة المال ('' = بلا وحدة).
  final String currency;

  /// v3 (المرحلة ٢): يُقرأ ويُحفظ، ولا يُرسم بعد.
  final String digits;
  final Map<String, ReceiptFieldStyle> fields;
  final Map<String, ReceiptSectionStyle> sections;
  final Map<String, ReceiptBlockStyle> blocks;
  final Map<String, String> titles;
  final List<ReceiptCustomText> texts;

  /// الترتيب المحلول كاملاً.
  final List<String> blockOrder;
  final List<String> bodyOrder;
  final Map<String, List<String>> sectionFields;

  /// `null` حين لا يكون كائناً (⇒ وصل v1).
  static ReceiptLayout? fromJson(Object? raw) => raw is Map ? normalize(raw) : null;

  /// لا يرمي أبداً: غير الكائن ⇒ الافتراضيّ.
  static ReceiptLayout normalize(Object? raw) {
    final l = raw is Map ? raw : const {};
    final fields = <String, ReceiptFieldStyle>{};
    final f = l['fields'];
    if (f is Map) {
      for (final id in receiptAllFieldIds) {
        final x = f[id];
        if (x is! Map) continue;
        final show = x['show'];
        final label = x['label'];
        final bold = x['bold'];
        final mode = x['row_mode'];
        fields[id] = ReceiptFieldStyle(
          show: show is bool ? show : null,
          label: label is String ? label : null,
          size: _oneOf(x['size'], receiptSizeSteps),
          bold: bold is bool ? bold : null,
          pt: _ptOf(x['pt']),
          align: _oneOf(x['align'], receiptHAligns),
          rowMode: mode == 'stack' || mode == 'value' ? mode as String : null,
          gapBefore: receiptGapOf(x['gap_before']),
          gapAfter: receiptGapOf(x['gap_after']),
          sep: _oneOf(x['sep'], receiptSeps),
          only: _onlyOf(x['only']),
        );
      }
    }
    final sections = <String, ReceiptSectionStyle>{};
    final s = l['sections'];
    if (s is Map) {
      for (final id in receiptSectionIds) {
        final x = s[id];
        if (x is! Map) continue;
        final title = x['title'];
        final showTitle = x['show_title'];
        sections[id] = ReceiptSectionStyle(
          title: title is String ? title : null,
          showTitle: showTitle is bool ? showTitle : null,
          pt: _ptOf(x['pt']),
          align: _oneOf(x['align'], receiptHAligns),
          gapBefore: receiptGapOf(x['gap_before']),
          gapAfter: receiptGapOf(x['gap_after']),
          only: receiptBodySections.contains(id) ? _onlyOf(x['only']) : null,
        );
      }
    }
    final blocks = <String, ReceiptBlockStyle>{};
    final b = l['blocks'];
    if (b is Map) {
      for (final id in receiptContainerIds) {
        final x = b[id];
        if (x is! Map) continue;
        blocks[id] = ReceiptBlockStyle(
          gapBefore: receiptGapOf(x['gap_before']),
          gapAfter: receiptGapOf(x['gap_after']),
          sep: _oneOf(x['sep'], receiptSeps),
          only: _onlyOf(x['only']),
        );
      }
    }
    final titles = <String, String>{};
    final t = l['titles'];
    if (t is Map) {
      for (final k in receiptKinds) {
        final v = t[k];
        if (v is String) titles[k] = v;
      }
    }
    final texts = <ReceiptCustomText>[];
    final xs = l['texts'];
    if (xs is List) {
      for (final x in xs) {
        if (texts.length >= receiptLimits['texts']!) break;
        if (x is! Map) continue;
        final at = _oneOf(x['at'], receiptTextPos3Ids);
        final text = x['text'];
        if (at == null || text is! String) continue;
        final only = x['only'];
        final id = x['id'];
        texts.add(ReceiptCustomText(
          id: id is String && id.isNotEmpty ? id : 't${texts.length + 1}',
          at: at,
          text: text,
          align: _oneOf(x['align'], receiptHAligns) ?? 'center',
          size: _oneOf(x['size'], receiptSizeSteps) ?? 'md',
          bold: x['bold'] == true,
          boxed: x['boxed'] == true,
          only: only is List ? [for (final k in receiptKinds) if (only.contains(k)) k] : const [],
          pt: _ptOf(x['pt']),
          gapBefore: receiptGapOf(x['gap_before']) ?? 0,
          gapAfter: receiptGapOf(x['gap_after']) ?? 0,
          sep: _oneOf(x['sep'], receiptSeps),
        ));
      }
    }
    final o = l['order'] is Map ? l['order'] as Map : const {};
    return ReceiptLayout(
      density: _oneOf(l['density'], receiptDensities) ?? 'normal',
      emoji: l['emoji'] != false,
      mono: l['mono'] == true,
      currency: _currencyOf(l['currency']),
      digits: _oneOf(l['digits'], receiptDigits) ?? 'latin',
      fields: fields,
      sections: sections,
      blocks: blocks,
      titles: titles,
      texts: texts,
      blockOrder: receiptResolveBlockOrder(o['blocks']),
      bodyOrder: receiptResolveBodyOrder(o['body']),
      sectionFields: receiptResolveSectionFields(o),
    );
  }

  /// الحقول المخفيّة بقرار المالك في v2 (بلا الأربعة التي ظهورها من مفاتيح v1 — تُعدّ هناك).
  int get hiddenFields =>
      fields.entries.where((e) => e.value.show == false && receiptFieldDefs[e.key] != null && receiptFieldDefs[e.key]!.v1 == null).length;
}

// ───────────────────────── بيانات الوصل ─────────────────────────

@immutable
class ReceiptInputSubscriber {
  const ReceiptInputSubscriber({
    this.name,
    this.username,
    this.phone,
    this.packageName,
    this.sasPackageName,
    this.packagePrice,
    this.expiration,
    this.remainingDays,
  });

  final String? name;
  final String? username;
  final String? phone;
  final String? packageName;
  final String? sasPackageName;
  final num? packagePrice;
  final String? expiration;
  final num? remainingDays;
}

@immutable
class ReceiptInputSaleLine {
  const ReceiptInputSaleLine({required this.name, required this.qtyText, required this.unitPrice, required this.total});

  final String name;
  final String qtyText;

  /// أعدادٌ بدلالة `Number(n) || 0` في الموقع.
  final Object? unitPrice;
  final Object? total;
}

@immutable
class ReceiptInputSale {
  const ReceiptInputSale({
    required this.lines,
    required this.total,
    required this.debt,
    this.note,
    this.voided = false,
    this.voidReason,
  });

  final List<ReceiptInputSaleLine> lines;
  final Object? total;

  /// على حساب المشترك (دين) لا نقداً.
  final bool debt;
  final String? note;
  final bool voided;
  final String? voidReason;
}

/// ما يحتاجه المحلِّل (`ReceiptInput` في الموقع) — الوقت والرقم نصّاً جاهزاً.
@immutable
class ReceiptInput {
  const ReceiptInput({
    required this.kind,
    required this.issuedText,
    required this.receiptId,
    required this.receiptNoText,
    this.shopName,
    this.shopAddress,
    this.shopPhone,
    this.footerText,
    this.issuer,
    this.hasLogo = false,
    this.hasQr = false,
    this.subscriber = const ReceiptInputSubscriber(),
    this.paymentType,
    this.amount,
    this.partialAmount,
    this.newBalance,
    this.sale,
  });

  final String kind;
  final String? shopName;
  final String? shopAddress;
  final String? shopPhone;
  final String? footerText;

  /// «yyyy-MM-dd HH:mm» بتوقيت بغداد (وقت البيع للفاتورة).
  final String issuedText;

  /// سطر الرقم: «No. 00012» (من الأرشيف) أو «R-…».
  final String receiptId;

  /// {receipt_no}: الرقم بخمس خانات، أو رقم الفاتورة، أو «R-…» إن لم يُؤرشف.
  final String receiptNoText;

  /// «أصدره»: الموظّف أو المدير.
  final String? issuer;
  final bool hasLogo;
  final bool hasQr;
  final ReceiptInputSubscriber subscriber;

  /// 'cash' | 'partial-cash' | 'non-cash'
  final String? paymentType;
  final num? amount;
  final num? partialAmount;

  /// بعد العمليّة: سالبٌ = دين.
  final num? newBalance;
  final ReceiptInputSale? sale;

  static String? _s(Object? v) => v is String ? v : (v is num && v.isFinite ? _jsNum(v) : null);

  /// شكل الموقع (حالات ملفّ التثبيت) بدلالات `str()`/`num()` نفسها.
  factory ReceiptInput.fromJson(Map<String, dynamic> j) {
    final sub = j['subscriber'] is Map ? j['subscriber'] as Map : const {};
    final sale = j['sale'];
    return ReceiptInput(
      kind: '${j['kind']}',
      shopName: _s(j['shopName']),
      shopAddress: _s(j['shopAddress']),
      shopPhone: _s(j['shopPhone']),
      footerText: _s(j['footerText']),
      issuedText: _s(j['issuedText']) ?? '',
      receiptId: _s(j['receiptId']) ?? '',
      receiptNoText: _s(j['receiptNoText']) ?? '',
      issuer: _s(j['issuer']),
      hasLogo: _truthy(j['hasLogo']),
      hasQr: _truthy(j['hasQr']),
      subscriber: ReceiptInputSubscriber(
        name: _s(sub['name']),
        username: _s(sub['username']),
        phone: _s(sub['phone']),
        packageName: _s(sub['packageName']),
        sasPackageName: _s(sub['sasPackageName']),
        packagePrice: _num(sub['packagePrice']),
        expiration: _s(sub['expiration']),
        remainingDays: _num(sub['remainingDays']),
      ),
      paymentType: j['paymentType'] is String ? j['paymentType'] as String : null,
      amount: _num(j['amount']),
      partialAmount: _num(j['partialAmount']),
      newBalance: _num(j['newBalance']),
      sale: sale is Map
          ? ReceiptInputSale(
              lines: [
                for (final l in (sale['lines'] is List ? sale['lines'] as List : const []))
                  if (l is Map)
                    ReceiptInputSaleLine(
                      name: _s(l['name']) ?? '',
                      qtyText: _s(l['qtyText']) ?? '',
                      unitPrice: l['unitPrice'],
                      total: l['total'],
                    ),
              ],
              total: sale['total'],
              debt: sale['payment'] == 'debt',
              note: _s(sale['note']),
              voided: _truthy(sale['voided']),
              voidReason: _s(sale['voidReason']),
            )
          : null,
    );
  }
}

// ───────────────────────── الناتج: كتلٌ مرتّبة ─────────────────────────

/// مسافتا الكتلة/الصفّ/السطر (ملّيمتراً) وخطّها (v3؛ ٠/٠/null = كما كان).
mixin _Gaps {
  num get gapBefore;
  num get gapAfter;
  String? get sep;
  Map<String, Object?> get _gapsJson => {'gap_before': gapBefore, 'gap_after': gapAfter, 'sep': sep};
}

@immutable
sealed class RBlock with _Gaps {
  const RBlock({this.gapBefore = 0, this.gapAfter = 0, this.sep});

  @override
  final num gapBefore;
  @override
  final num gapAfter;
  @override
  final String? sep;

  Map<String, Object?> toJson();
}

class RLogo extends RBlock {
  const RLogo(this.align, {super.gapBefore, super.gapAfter, super.sep});

  final String align;
  @override
  Map<String, Object?> toJson() => {'t': 'logo', 'align': align, ..._gapsJson};
}

class RShopName extends RBlock {
  const RShopName({
    required this.text,
    required this.scale,
    required this.bold,
    required this.align,
    this.pt,
    super.gapBefore,
    super.gapAfter,
    super.sep,
  });

  final String text;
  final num scale;
  final bool bold;
  final String align;
  final num? pt;
  @override
  Map<String, Object?> toJson() =>
      {'t': 'shop_name', 'text': text, 'scale': scale, 'bold': bold, 'align': align, 'pt': pt, ..._gapsJson};
}

@immutable
class RShopLine with _Gaps {
  const RShopLine({
    required this.id,
    required this.text,
    required this.ltr,
    required this.icon,
    required this.scale,
    required this.bold,
    required this.align,
    this.pt,
    this.stack = false,
    this.gapBefore = 0,
    this.gapAfter = 0,
    this.sep,
  });

  /// 'shop_address' | 'shop_phone'
  final String id;
  final String text;
  final bool ltr;

  /// 'pin' | 'phone' — الموقع يرسمه رمزاً تعبيريّاً حين الرموز مفعّلة، والتطبيق لا يرسم رموزاً.
  final String icon;
  final num scale;
  final bool bold;

  /// v3: محاذاة السطر (الافتراضيّ header_align).
  final String align;
  final num? pt;

  /// التسمية فوق القيمة (النصّ «التسمية\nالقيمة»).
  final bool stack;
  @override
  final num gapBefore;
  @override
  final num gapAfter;
  @override
  final String? sep;
  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'ltr': ltr,
        'icon': icon,
        'scale': scale,
        'bold': bold,
        'align': align,
        'pt': pt,
        'stack': stack,
        ..._gapsJson,
      };
}

class RShopLines extends RBlock {
  const RShopLines({required this.lines, required this.align, super.gapBefore, super.gapAfter, super.sep});

  final List<RShopLine> lines;
  final String align;
  @override
  Map<String, Object?> toJson() =>
      {'t': 'shop_lines', 'lines': [for (final l in lines) l.toJson()], 'align': align, ..._gapsJson};
}

class RTitle extends RBlock {
  const RTitle({
    required this.text,
    required this.scale,
    required this.bold,
    required this.align,
    this.pt,
    super.gapBefore,
    super.gapAfter,
  });

  final String text;
  final num scale;
  final bool bold;
  final String align;
  final num? pt;
  @override
  Map<String, Object?> toJson() =>
      {'t': 'title', 'text': text, 'scale': scale, 'bold': bold, 'align': align, 'pt': pt, ..._gapsJson};
}

class RMeta extends RBlock {
  const RMeta({
    required this.no,
    required this.at,
    this.split = false,
    this.noAlign,
    this.atAlign,
    this.noPt,
    this.atPt,
    this.noBold = false,
    this.atBold = false,
    this.noGapBefore = 0,
    this.noGapAfter = 0,
    this.atGapBefore = 0,
    this.atGapAfter = 0,
    super.gapBefore,
    super.gapAfter,
    super.sep,
  });

  /// «#No. 00012» (التسمية ملتصقة) أو null.
  final String? no;
  final String? at;

  /// سطران منفصلان بمحاذاة كلٍّ منهما (حين تُحدَّد محاذاة أحدهما).
  final bool split;
  final String? noAlign;
  final String? atAlign;
  final num? noPt;
  final num? atPt;
  final bool noBold;
  final bool atBold;

  /// مسافتا كلّ سطرٍ (تُرسمان حين [split] وحده).
  final num noGapBefore;
  final num noGapAfter;
  final num atGapBefore;
  final num atGapAfter;
  @override
  Map<String, Object?> toJson() => {
        't': 'meta',
        'no': no,
        'at': at,
        'split': split,
        'no_align': noAlign,
        'at_align': atAlign,
        'no_pt': noPt,
        'at_pt': atPt,
        'no_bold': noBold,
        'at_bold': atBold,
        'no_gap_before': noGapBefore,
        'no_gap_after': noGapAfter,
        'at_gap_before': atGapBefore,
        'at_gap_after': atGapAfter,
        ..._gapsJson,
      };
}

@immutable
class RRow with _Gaps {
  const RRow({
    required this.id,
    required this.label,
    required this.value,
    required this.ltr,
    required this.bold,
    required this.scale,
    this.tone,
    this.align,
    this.stack = false,
    this.pt,
    this.labelPt,
    this.gapBefore = 0,
    this.gapAfter = 0,
    this.sep,
  });

  final String id;

  /// null = القيمة وحدها (تسميةٌ فارغة أو «القيمة فقط»).
  final String? label;
  final String value;
  final bool ltr;
  final bool bold;
  final num scale;

  /// 'debt' أحمر · 'credit' أخضر · 'total' بحجم العنوان الفرعيّ (الألوان لـA4 وحده ما لم يكن «أسود فقط»).
  final String? tone;

  /// null = المحاذاة القديمة (التسميات default_align والقيم بعكسها).
  final String? align;

  /// التسمية فوق القيمة.
  final bool stack;
  final num? pt;

  /// = round(pt × 0.9 × 2) / 2 حين يُثبَّت الحجم.
  final num? labelPt;
  @override
  final num gapBefore;
  @override
  final num gapAfter;
  @override
  final String? sep;
  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'value': value,
        'ltr': ltr,
        'bold': bold,
        'scale': scale,
        'tone': tone,
        'align': align,
        'stack': stack,
        'pt': pt,
        'label_pt': labelPt,
        ..._gapsJson,
      };
}

class RSection extends RBlock {
  const RSection({
    required this.id,
    required this.title,
    required this.rows,
    this.titlePt,
    this.titleAlign,
    super.gapBefore,
    super.gapAfter,
  });

  final String id;
  final String? title;
  final List<RRow> rows;
  final num? titlePt;
  final String? titleAlign;
  @override
  Map<String, Object?> toJson() => {
        't': 'section',
        'id': id,
        'title': title,
        'rows': [for (final r in rows) r.toJson()],
        'title_pt': titlePt,
        'title_align': titleAlign,
        ..._gapsJson,
      };
}

class RSaleVoid extends RBlock {
  const RSaleVoid(this.text);

  final String text;
  @override
  Map<String, Object?> toJson() => {'t': 'sale_void', 'text': text, ..._gapsJson};
}

@immutable
class RSaleLine {
  const RSaleLine({required this.name, required this.detail, required this.total});

  final String name;

  /// «الكمّيّة × سعر الوحدة».
  final String detail;
  final String total;
  Map<String, Object?> toJson() => {'name': name, 'detail': detail, 'total': total};
}

class RSaleItems extends RBlock {
  const RSaleItems({
    required this.title,
    required this.lines,
    this.titlePt,
    this.titleAlign,
    super.gapBefore,
    super.gapAfter,
  });

  final String? title;
  final List<RSaleLine> lines;
  final num? titlePt;
  final String? titleAlign;
  @override
  Map<String, Object?> toJson() => {
        't': 'sale_items',
        'title': title,
        'lines': [for (final l in lines) l.toJson()],
        'title_pt': titlePt,
        'title_align': titleAlign,
        ..._gapsJson,
      };
}

class RSaleNote extends RBlock {
  const RSaleNote(this.text);

  final String text;
  @override
  Map<String, Object?> toJson() => {'t': 'sale_note', 'text': text, ..._gapsJson};
}

class RText extends RBlock {
  const RText({
    required this.id,
    required this.text,
    required this.align,
    required this.scale,
    required this.bold,
    required this.boxed,
    this.pt,
    super.gapBefore,
    super.gapAfter,
    super.sep,
  });

  final String id;
  final String text;
  final String align;
  final num scale;
  final bool bold;
  final bool boxed;
  final num? pt;
  @override
  Map<String, Object?> toJson() => {
        't': 'text',
        'id': id,
        'text': text,
        'align': align,
        'scale': scale,
        'bold': bold,
        'boxed': boxed,
        'pt': pt,
        ..._gapsJson,
      };
}

class RQr extends RBlock {
  const RQr({
    required this.caption,
    required this.align,
    String? captionAlign,
    this.captionPt,
    this.captionBold = false,
    super.gapBefore,
    super.gapAfter,
    super.sep,
  }) : captionAlign = captionAlign ?? align;

  final String? caption;
  final String align;
  final num? captionPt;
  final String captionAlign;
  final bool captionBold;
  @override
  Map<String, Object?> toJson() => {
        't': 'qr',
        'caption': caption,
        'align': align,
        'caption_pt': captionPt,
        'caption_align': captionAlign,
        'caption_bold': captionBold,
        ..._gapsJson,
      };
}

@immutable
class RFooterLine with _Gaps {
  const RFooterLine({
    required this.id,
    required this.text,
    required this.icon,
    required this.scale,
    required this.bold,
    required this.align,
    this.pt,
    this.stack = false,
    this.gapBefore = 0,
    this.gapAfter = 0,
    this.sep,
  });

  /// 'issuer' | 'footer_text'
  final String id;
  final String text;

  /// 'pray' (🙏 بالموقع بعد التذييل الافتراضيّ) أو null.
  final String? icon;
  final num scale;
  final bool bold;

  /// v3: محاذاة السطر (الافتراضيّ footer_align).
  final String align;
  final num? pt;
  final bool stack;
  @override
  final num gapBefore;
  @override
  final num gapAfter;
  @override
  final String? sep;
  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'icon': icon,
        'scale': scale,
        'bold': bold,
        'align': align,
        'pt': pt,
        'stack': stack,
        ..._gapsJson,
      };
}

class RFooter extends RBlock {
  const RFooter({required this.lines, required this.align, super.gapBefore, super.gapAfter, super.sep});

  final List<RFooterLine> lines;
  final String align;
  @override
  Map<String, Object?> toJson() =>
      {'t': 'footer', 'lines': [for (final l in lines) l.toJson()], 'align': align, ..._gapsJson};
}

@immutable
class ResolvedReceipt {
  const ResolvedReceipt({
    required this.density,
    required this.emoji,
    required this.mono,
    required this.labelAlign,
    required this.valueAlign,
    required this.blocks,
  });

  final String density;
  final bool emoji;
  final bool mono;

  /// محاذاة عمود التسميات (default_align)، والقيم بعكسها الفيزيائيّ: يمين/ضبط ⇒ يسار، يسار ⇒ يمين، وسط ⇒ وسط.
  final String labelAlign;
  final String valueAlign;
  final List<RBlock> blocks;

  Map<String, Object?> toJson() => {
        'density': density,
        'emoji': emoji,
        'mono': mono,
        'label_align': labelAlign,
        'value_align': valueAlign,
        'blocks': [for (final b in blocks) b.toJson()],
      };
}

// ───────────────────────── المتغيّرات ─────────────────────────

String _displayName(ReceiptInput i) {
  final n = _str(i.subscriber.name);
  return n.isNotEmpty ? n : _str(i.subscriber.username);
}

String _shopNameOf(ReceiptInput i) {
  final n = _str(i.shopName);
  return n.isNotEmpty ? n : receiptDefaultShopName;
}

String _expiryText(ReceiptInput i) {
  final e = _str(i.subscriber.expiration);
  return e.length > 16 ? e.substring(0, 16) : e;
}

/// قيم المتغيّرات لهذا الوصل — كلّ متغيّرٍ معروف حاضرٌ (فارغٌ إن لم ينطبق على النوع أو لا قيمة له).
Map<String, String> receiptVars(ReceiptInput input, [String currency = receiptDefaultCurrency]) {
  final s = input.subscriber;
  final kind = input.kind;
  String money(Object? n) => receiptMoney(n, currency);
  final issued = _str(input.issuedText);
  final sp = issued.indexOf(' ');
  final nb = _num(input.newBalance);
  final amount = _num(input.amount);
  final price = _num(s.packagePrice);
  final days = _num(s.remainingDays);
  final pay = receiptPaymentLabels.containsKey(input.paymentType) ? input.paymentType : null;
  num? paid;
  if (kind == 'payment') {
    paid = amount;
  } else if (pay == 'cash') {
    paid = amount;
  } else if (pay == 'partial-cash') {
    paid = _num(input.partialAmount);
  } else if (pay == 'non-cash') {
    paid = 0;
  }
  final sale = kind == 'sale' ? input.sale : null;
  final sas = _str(s.sasPackageName);
  final raw = <String, String>{
    'shop_name': _shopNameOf(input),
    'shop_phone': _str(input.shopPhone),
    'shop_address': _str(input.shopAddress),
    'receipt_type': receiptTypeLabels[kind] ?? '',
    'receipt_no': _str(input.receiptNoText),
    'date': sp > 0 ? issued.substring(0, sp) : issued,
    'time': sp > 0 ? issued.substring(sp + 1).trim() : '',
    'issuer': _str(input.issuer),
    'subscriber_name': _displayName(input),
    'firstname': _str(s.name).split(RegExp(r'\s+')).first,
    'username': _str(s.username),
    'phone': _str(s.phone),
    'package_name': _str(s.packageName),
    'sas_package_name': sas.isNotEmpty ? sas : _str(s.packageName),
    'package_price': price != null && price > 0 ? money(price) : '',
    'expiry_date': _expiryText(input),
    'days_remaining': days != null ? _jsNum(days) : '',
    'remaining_days': days != null ? '${_jsNum(days)} يوم' : '',
    'payment_type': pay != null ? receiptPaymentLabels[pay]! : '',
    'amount': amount != null ? money(amount) : '',
    'paid_amount': paid != null ? money(paid) : '',
    'debt_amount': nb != null && nb < 0 ? money(nb) : '',
    'credit_amount': nb != null && nb > 0 ? money(nb) : '',
    'balance': nb == null ? '' : (nb < 0 ? 'دين ${money(nb)}' : (nb > 0 ? 'رصيد ${money(nb)}' : money(0))),
    'sale_total': sale != null ? money(sale.total) : '',
    'sale_payment': sale != null ? (sale.debt ? receiptSaleLabels['debt']! : receiptSaleLabels['cash']!) : '',
  };
  for (final v in receiptVariables) {
    if (!v.kinds.contains(kind)) raw[v.id] = '';
  }
  return raw;
}

final RegExp _varRe = RegExp(r'\{([a-z_]+)\}');
final Set<String> _varIds = {for (final v in receiptVariables) v.id};

/// يملأ `{متغيّر}`: المجهول يبقى حرفيّاً (فيظهر الخطأ في المعاينة)، والمعروف الفارغ ''. ثمّ تُطوى المسافات وتُحذف الأسطر
/// الفارغة. hidden = النصّ فارغ، أو فيه متغيّرٌ معروف واحدٌ على الأقلّ وكلّها فارغة (فلا يُطبع نصٌّ نصفه فراغ).
({String text, bool hidden}) receiptFill(String text, Map<String, String> vars) {
  var known = 0;
  var filled = 0;
  final out = text.replaceAllMapped(_varRe, (m) {
    final name = m.group(1)!;
    if (!_varIds.contains(name)) return m.group(0)!;
    known++;
    final v = vars[name] ?? '';
    if (v != '') filled++;
    return v;
  });
  final lines = out
      .split(RegExp(r'\r?\n'))
      .map((l) => l.replaceAll(RegExp('[ \t ]+'), ' ').trim())
      .where((l) => l != '')
      .toList();
  final res = lines.join('\n');
  return (text: res, hidden: res == '' || (known > 0 && filled == 0));
}

/// في النصّ `{متغيّرٌ معروف}`؟ (التسميات بلا متغيّرٍ تبقى كما كتبها الوكيل حرفيّاً — بند 22.)
bool receiptHasKnownVar(String text) => _varRe.allMatches(text).any((m) => _varIds.contains(m.group(1)));

/// المتغيّرات المجهولة في نصّ (للمصمّم: «متغيّرٌ غير معروف»): `{…}` بلا فراغ، كلٌّ مرّةً واحدة — `unknownVars` في الموقع.
List<String> receiptUnknownVars(String text) {
  final out = <String>[];
  for (final m in RegExp(r'\{([^{}\s]{1,40})\}').allMatches(text)) {
    final name = m.group(1)!;
    if (!_varIds.contains(name) && !out.contains(name)) out.add(name);
  }
  return out;
}

/// ما يرفضه الخادم في v3 (`LAYOUT_UNKNOWN_VAR`): كلّ `{x}` من [a-z_] ليس متغيّراً معروفاً.
List<String> receiptStrictUnknownVars(String text) {
  final out = <String>[];
  for (final m in _varRe.allMatches(text)) {
    final name = m.group(1)!;
    if (!_varIds.contains(name) && !out.contains(name)) out.add(name);
  }
  return out;
}

/// كلّ مدخلٍ يقبل المتغيّرات في التصميم وما فيه من متغيّرٍ مجهول — للحفظ: لا يُرسل تصميمٌ سيرفضه الخادم. المسار بصيغة الخادم.
List<({String path, List<String> vars})> receiptLayoutUnknownVars(Object? raw) {
  final l = raw is Map ? raw : const {};
  final out = <({String path, List<String> vars})>[];
  void check(String path, Object? v) {
    if (v is! String) return;
    final u = receiptStrictUnknownVars(v);
    if (u.isNotEmpty) out.add((path: path, vars: u));
  }

  final f = l['fields'];
  if (f is Map) {
    for (final e in f.entries) {
      if (e.value is Map) check('fields.${e.key}.label', (e.value as Map)['label']);
    }
  }
  final s = l['sections'];
  if (s is Map) {
    for (final e in s.entries) {
      if (e.value is Map) check('sections.${e.key}.title', (e.value as Map)['title']);
    }
  }
  final t = l['titles'];
  if (t is Map) {
    for (final e in t.entries) {
      check('titles.${e.key}', e.value);
    }
  }
  final xs = l['texts'];
  if (xs is List) {
    for (var i = 0; i < xs.length; i++) {
      if (xs[i] is Map) check('texts[$i].text', (xs[i] as Map)['text']);
    }
  }
  return out;
}

/// «التسمية: القيمة» — بلا تسمية ⇒ القيمة وحدها؛ تسميةٌ تنتهي بـ# تلتصق (#No. 00012)؛ وبـ: يتبعها فراغ.
String receiptJoinLabel(String label, String value) {
  final l = label.trim();
  if (l.isEmpty) return value;
  if (l.endsWith('#')) return '$l$value';
  if (l.endsWith(':')) return '$l $value';
  return '$l: $value';
}

/// حجم التسمية حين يُثبَّت حجم الصفّ: ١٢ ⇒ ١١، ١٤ ⇒ ١٢٫٥، ٩ ⇒ ٨.
num receiptLabelPt(num pt) => _tidy((pt * 0.9 * 2).round() / 2);

// ───────────────────────── المحلِّل ─────────────────────────

/// التصميم الخامّ (`design_json`: مفاتيح v1 + `layout`) + بيانات الوصل ⇒ كتلٌ مرتّبة — `resolveReceipt` في الموقع.
class ReceiptResolver {
  ReceiptResolver._();

  static const Map<String, String> _sectionSwitch = {
    'subscriber': 'show_subscriber_info',
    'package': 'show_package_info',
    'transaction': 'show_transaction_info',
  };

  static ResolvedReceipt resolve(Object? design, ReceiptInput input) {
    final d = design is Map ? design : const {};
    final l = ReceiptLayout.normalize(d['layout']);
    final kind = receiptKinds.contains(input.kind) ? input.kind : 'activation';
    bool sw(String k) => d.containsKey(k) ? d[k] != false : receiptV1Defaults[k] == true;
    String hAlign(String k) => _oneOf(d[k], receiptHAligns) ?? receiptV1Defaults[k]! as String;
    final labelAlign = _oneOf(d['default_align'], receiptLabelAligns) ?? 'right';
    final valueAlign = labelAlign == 'center' ? 'center' : (labelAlign == 'left' ? 'right' : 'left');
    final currency = l.currency;
    String money(Object? n) => receiptMoney(n, currency);
    final vars = receiptVars(_withKind(input, kind), currency);

    bool kindOk(List<String>? only) => only == null || only.isEmpty || only.contains(kind);
    ReceiptFieldStyle st(String id) => l.fields[id] ?? const ReceiptFieldStyle();
    ReceiptBlockStyle blk(String id) => l.blocks[id] ?? const ReceiptBlockStyle();
    ReceiptSectionStyle sec(String id) => l.sections[id] ?? const ReceiptSectionStyle();
    bool visible(String id) {
      final v1 = receiptFieldDefs[id]!.v1;
      return (v1 != null ? sw(v1) : st(id).show != false) && kindOk(st(id).only);
    }

    /// الحجم النسبيّ — لا أثر له حين يُثبَّت pt.
    num scale(String id) => st(id).pt != null ? 1 : receiptSizeScale[st(id).size ?? 'md']!;
    bool bold(String id) => st(id).bold ?? receiptFieldDefs[id]!.bold;
    String mode(String id) => st(id).rowMode ?? 'line';

    /// التسمية: المخصّصة مشذّبة ('' = بلا تسمية)؛ وبمتغيّراتٍ تُملأ — وإن خفيت فالافتراضيّة (لا يُخفى صفٌّ بتسميته).
    String labelOf(String id, [String? fallback]) {
      final def = fallback ?? receiptFieldDefs[id]!.label;
      final c = st(id).label;
      if (c == null) return def;
      final t = c.trim();
      if (t.isEmpty || !receiptHasKnownVar(t)) return t;
      final f = receiptFill(t, vars);
      return f.hidden ? def : f.text;
    }

    /// حقلٌ في سطر: «التسمية: القيمة»، أو التسمية فوق القيمة، أو القيمة وحدها.
    String inlineText(String id, String value) {
      final m = mode(id);
      if (m == 'value') return value;
      final lb = labelOf(id).trim();
      if (m == 'stack') return lb.isNotEmpty ? '$lb\n$value' : value;
      return receiptJoinLabel(lb, value);
    }

    RRow row(String id, String value, [String? tone, String? fallbackLabel]) {
      final s = st(id);
      final label = mode(id) == 'value' ? '' : labelOf(id, fallbackLabel);
      final pt = s.pt;
      return RRow(
        id: id,
        label: label == '' ? null : label,
        value: value,
        ltr: receiptFieldDefs[id]!.ltr,
        bold: bold(id),
        scale: scale(id),
        tone: tone,
        align: s.align,
        stack: mode(id) == 'stack',
        pt: pt,
        labelPt: pt == null ? null : receiptLabelPt(pt),
        gapBefore: s.gapBefore ?? 0,
        gapAfter: s.gapAfter ?? 0,
        sep: s.sep,
      );
    }

    String? sectionTitle(String id) {
      final s = sec(id);
      if (s.showTitle == false) return null;
      var t = (s.title ?? '').trim();
      if (t.isNotEmpty && receiptHasKnownVar(t)) {
        final f = receiptFill(t, vars);
        t = f.hidden ? '' : f.text;
      }
      if (t.isEmpty) t = receiptSectionTitles[id]!;
      return t.isNotEmpty ? t : null;
    }

    RSection sectionBlock(String id, List<RRow> rows) => RSection(
          id: id,
          title: sectionTitle(id),
          rows: rows,
          titlePt: sec(id).pt,
          titleAlign: sec(id).align,
          gapBefore: sec(id).gapBefore ?? 0,
          gapAfter: sec(id).gapAfter ?? 0,
        );

    final blocks = <RBlock>[];
    void pushTexts(String at) {
      for (final t in l.texts) {
        if (t.at != at) continue;
        if (t.only.isNotEmpty && !t.only.contains(kind)) continue;
        final f = receiptFill(t.text, vars);
        if (f.hidden) continue;
        blocks.add(RText(
          id: t.id,
          text: f.text,
          align: t.align,
          scale: t.pt != null ? 1 : receiptSizeScale[t.size]!,
          bold: t.bold,
          boxed: t.boxed,
          pt: t.pt,
          gapBefore: t.gapBefore,
          gapAfter: t.gapAfter,
          sep: t.sep,
        ));
      }
    }

    final s = input.subscriber;
    final price = _num(s.packagePrice);
    final days = _num(s.remainingDays);
    final amount = _num(input.amount);
    final part = _num(input.partialAmount);
    final nb = _num(input.newBalance);
    final pay = receiptPaymentLabels.containsKey(input.paymentType) ? input.paymentType : null;
    final actExt = kind == 'activation' || kind == 'extension';

    /// صفّ الحقل في هذا الوصل (أهليّته بالنوع والقيمة كما كانت) أو null؛ المحجوزة null في المرحلة ١.
    RRow? rowFor(String id) {
      if (!receiptFieldIds.contains(id)) return null;
      if (!visible(id)) return null;
      switch (id) {
        case 'subscriber_name':
          final n = _displayName(input);
          return n.isNotEmpty ? row(id, n) : null;
        case 'username':
          return _str(s.username).isNotEmpty ? row(id, _str(s.username)) : null;
        case 'phone':
          return _str(s.phone).isNotEmpty ? row(id, _str(s.phone)) : null;
        case 'package_name':
          final p = _str(s.packageName);
          return row(id, p.isNotEmpty ? p : '—');
        case 'package_price':
          return price != null && price > 0 ? row(id, money(price)) : null;
        case 'expiry_date':
          return _expiryText(input).isNotEmpty ? row(id, _expiryText(input)) : null;
        case 'days_remaining':
          return days != null ? row(id, '${_jsNum(days)} يوم') : null;
        case 'payment_type':
          return actExt && pay != null ? row(id, receiptPaymentLabels[pay]!) : null;
        case 'amount':
          if (amount == null) return null;
          if (actExt) return row(id, money(amount));
          if (kind == 'payment') return row(id, money(amount), null, receiptLabelVariants['amount_payment']);
          return null;
        case 'cash_paid':
          return actExt && pay == 'partial-cash' && part != null ? row(id, money(part)) : null;
        case 'balance_debt':
          return nb != null && nb < 0 ? row(id, money(nb), 'debt') : null;
        case 'balance_credit':
          return nb != null && nb >= 0
              ? row(id, money(nb), nb > 0 ? 'credit' : null, nb > 0 ? null : receiptLabelVariants['balance_zero'])
              : null;
      }
      return null;
    }

    void body() {
      if (kind == 'sale') {
        // بنية الفاتورة ثابتة (order.body وقوائم الحقول لا تمسّها)؛ والنصوص بعد أقسامها المقابلة.
        final sale = input.sale;
        if (sale != null) {
          if (sale.voided) {
            final why = _str(sale.voidReason);
            blocks.add(RSaleVoid(why.isNotEmpty ? '${receiptSaleLabels['void']} — $why' : receiptSaleLabels['void']!));
          }
          if (sw('show_subscriber_info')) {
            final rows = <RRow>[];
            final name = _displayName(input);
            if (visible('subscriber_name')) {
              rows.add(row('subscriber_name', name.isNotEmpty ? name : receiptSaleLabels['customer']!));
            }
            if (visible('username') && _str(s.username).isNotEmpty) rows.add(row('username', _str(s.username)));
            if (visible('phone') && _str(s.phone).isNotEmpty) rows.add(row('phone', _str(s.phone)));
            if (rows.isNotEmpty) blocks.add(sectionBlock('sale_customer', rows));
          }
        }
        pushTexts('after_subscriber');
        if (sale != null) {
          blocks.add(RSaleItems(
            title: sectionTitle('sale_items'),
            lines: [
              for (final x in sale.lines)
                RSaleLine(
                  name: _str(x.name),
                  detail: '${_str(x.qtyText)} × ${money(x.unitPrice)}',
                  total: money(x.total),
                ),
            ],
            titlePt: sec('sale_items').pt,
            titleAlign: sec('sale_items').align,
            gapBefore: sec('sale_items').gapBefore ?? 0,
            gapAfter: sec('sale_items').gapAfter ?? 0,
          ));
        }
        pushTexts('after_package');
        if (sale != null) {
          blocks.add(sectionBlock('sale_totals', [
            RRow(
              id: 'sale_total',
              label: receiptSaleLabels['total'],
              value: money(sale.total),
              ltr: false,
              bold: true,
              scale: 1,
              tone: 'total',
            ),
            RRow(
              id: 'sale_payment',
              label: receiptSaleLabels['payment'],
              value: sale.debt ? receiptSaleLabels['debt']! : receiptSaleLabels['cash']!,
              ltr: false,
              bold: true,
              scale: 1,
            ),
          ]));
        }
        pushTexts('after_transaction');
        final note = sale != null ? _str(sale.note) : '';
        if (note.isNotEmpty) blocks.add(RSaleNote('${receiptSaleLabels['note']}: $note'));
        return;
      }
      for (final sid in l.bodyOrder) {
        if (sw(_sectionSwitch[sid]!) && kindOk(sec(sid).only)) {
          final rows = <RRow>[];
          for (final id in l.sectionFields[sid] ?? const <String>[]) {
            final r = rowFor(id);
            if (r != null) rows.add(r);
          }
          if (rows.isNotEmpty) blocks.add(sectionBlock(sid, rows));
        }
        pushTexts('after_$sid');
      }
    }

    pushTexts('top');
    for (final b in l.blockOrder) {
      switch (b) {
        case 'logo':
          if (sw('show_logo') && input.hasLogo && kindOk(blk('logo').only)) {
            blocks.add(RLogo(
              hAlign('logo_align'),
              gapBefore: blk('logo').gapBefore ?? 0,
              gapAfter: blk('logo').gapAfter ?? 0,
              sep: blk('logo').sep,
            ));
          }
        case 'shop_name':
          if (visible('shop_name')) {
            final x = st('shop_name');
            blocks.add(RShopName(
              text: _shopNameOf(input),
              scale: scale('shop_name'),
              bold: bold('shop_name'),
              align: x.align ?? hAlign('header_align'),
              pt: x.pt,
              gapBefore: x.gapBefore ?? 0,
              gapAfter: x.gapAfter ?? 0,
              sep: x.sep,
            ));
          }
        case 'shop_lines':
          if (sw('show_shop_info') && kindOk(blk('shop_lines').only)) {
            final lines = <RShopLine>[];
            RShopLine shopLine(String id, String value, bool ltr, String icon) {
              final x = st(id);
              return RShopLine(
                id: id,
                text: inlineText(id, value),
                ltr: ltr,
                icon: icon,
                scale: scale(id),
                bold: bold(id),
                align: x.align ?? hAlign('header_align'),
                pt: x.pt,
                stack: mode(id) == 'stack',
                gapBefore: x.gapBefore ?? 0,
                gapAfter: x.gapAfter ?? 0,
                sep: x.sep,
              );
            }

            final addr = _str(input.shopAddress);
            final tel = _str(input.shopPhone);
            if (addr.isNotEmpty && visible('shop_address')) lines.add(shopLine('shop_address', addr, false, 'pin'));
            if (tel.isNotEmpty && visible('shop_phone')) lines.add(shopLine('shop_phone', tel, true, 'phone'));
            if (lines.isNotEmpty) {
              blocks.add(RShopLines(
                lines: lines,
                align: hAlign('header_align'),
                gapBefore: blk('shop_lines').gapBefore ?? 0,
                gapAfter: blk('shop_lines').gapAfter ?? 0,
                sep: blk('shop_lines').sep,
              ));
            }
          }
          pushTexts('after_shop');
        case 'title':
          if (visible('title')) {
            final custom = (l.titles[kind] ?? '').trim();
            var text = custom.isNotEmpty ? receiptFill(custom, vars).text : '';
            if (text.isEmpty) text = receiptFill(receiptDefaultTitles[kind]!, vars).text;
            final x = st('title');
            blocks.add(RTitle(
              text: text,
              scale: scale('title'),
              bold: bold('title'),
              align: x.align ?? hAlign('header_align'),
              pt: x.pt,
              gapBefore: x.gapBefore ?? 0,
              gapAfter: x.gapAfter ?? 0,
            ));
          }
          pushTexts('after_title');
        case 'meta':
          // الفاتورة رقمها في عنوانها
          if (kindOk(blk('meta').only)) {
            final rid = _str(input.receiptId);
            final issued = _str(input.issuedText);
            final no = visible('receipt_no') && kind != 'sale' && rid.isNotEmpty ? inlineText('receipt_no', rid) : null;
            final at = visible('issued_at') && issued.isNotEmpty ? inlineText('issued_at', issued) : null;
            if (no != null || at != null) {
              final sNo = st('receipt_no');
              final sAt = st('issued_at');
              final split = sNo.align != null || sAt.align != null;
              blocks.add(RMeta(
                no: no,
                at: at,
                split: split,
                noAlign: split ? sNo.align ?? hAlign('header_align') : null,
                atAlign: split ? sAt.align ?? hAlign('header_align') : null,
                noPt: sNo.pt,
                atPt: sAt.pt,
                noBold: bold('receipt_no'),
                atBold: bold('issued_at'),
                noGapBefore: sNo.gapBefore ?? 0,
                noGapAfter: sNo.gapAfter ?? 0,
                atGapBefore: sAt.gapBefore ?? 0,
                atGapAfter: sAt.gapAfter ?? 0,
                gapBefore: blk('meta').gapBefore ?? 0,
                gapAfter: blk('meta').gapAfter ?? 0,
                sep: blk('meta').sep,
              ));
            }
          }
          pushTexts('after_meta');
        case 'body':
          body();
        case 'qr':
          pushTexts('before_qr');
          // لا QR للفاتورة
          if (input.hasQr && kind != 'sale' && kindOk(blk('qr').only)) {
            var cap = '';
            if (visible('qr_caption')) {
              final c = st('qr_caption').label;
              if (c == null) {
                cap = receiptFieldDefs['qr_caption']!.label;
              } else {
                cap = c.trim();
                if (cap.isNotEmpty && receiptHasKnownVar(cap)) {
                  final f = receiptFill(cap, vars);
                  cap = f.hidden ? '' : f.text;
                }
              }
            }
            final x = st('qr_caption');
            blocks.add(RQr(
              caption: cap.isNotEmpty ? cap : null,
              align: hAlign('qr_align'),
              captionPt: x.pt,
              captionAlign: x.align ?? hAlign('qr_align'),
              captionBold: bold('qr_caption'),
              gapBefore: blk('qr').gapBefore ?? 0,
              gapAfter: blk('qr').gapAfter ?? 0,
              sep: blk('qr').sep,
            ));
          }
        case 'footer':
          pushTexts('before_footer');
          if (sw('show_footer') && kindOk(blk('footer').only)) {
            final lines = <RFooterLine>[];
            final issuer = _str(input.issuer);
            if (visible('issuer') && issuer.isNotEmpty) {
              final x = st('issuer');
              lines.add(RFooterLine(
                id: 'issuer',
                text: inlineText('issuer', issuer),
                icon: null,
                scale: scale('issuer'),
                bold: bold('issuer'),
                align: x.align ?? hAlign('footer_align'),
                pt: x.pt,
                stack: mode('issuer') == 'stack',
                gapBefore: x.gapBefore ?? 0,
                gapAfter: x.gapAfter ?? 0,
                sep: x.sep,
              ));
            }
            if (visible('footer_text')) {
              final own = (input.footerText ?? '')
                  .split(RegExp(r'\r?\n'))
                  .map((x) => x.trim())
                  .where((x) => x != '')
                  .join('\n');
              final x = st('footer_text');
              lines.add(RFooterLine(
                id: 'footer_text',
                text: own.isNotEmpty ? own : receiptDefaultFooter,
                icon: own.isNotEmpty ? null : 'pray',
                scale: scale('footer_text'),
                bold: bold('footer_text'),
                align: x.align ?? hAlign('footer_align'),
                pt: x.pt,
                stack: false,
                gapBefore: x.gapBefore ?? 0,
                gapAfter: x.gapAfter ?? 0,
                sep: x.sep,
              ));
            }
            if (lines.isNotEmpty) {
              blocks.add(RFooter(
                lines: lines,
                align: hAlign('footer_align'),
                gapBefore: blk('footer').gapBefore ?? 0,
                gapAfter: blk('footer').gapAfter ?? 0,
                sep: blk('footer').sep,
              ));
            }
          }
      }
    }
    pushTexts('bottom');

    return ResolvedReceipt(
      density: l.density,
      emoji: l.emoji,
      mono: l.mono,
      labelAlign: labelAlign,
      valueAlign: valueAlign,
      blocks: blocks,
    );
  }

  static ReceiptInput _withKind(ReceiptInput i, String kind) => i.kind == kind
      ? i
      : ReceiptInput(
          kind: kind,
          issuedText: i.issuedText,
          receiptId: i.receiptId,
          receiptNoText: i.receiptNoText,
          shopName: i.shopName,
          shopAddress: i.shopAddress,
          shopPhone: i.shopPhone,
          footerText: i.footerText,
          issuer: i.issuer,
          hasLogo: i.hasLogo,
          hasQr: i.hasQr,
          subscriber: i.subscriber,
          paymentType: i.paymentType,
          amount: i.amount,
          partialAmount: i.partialAmount,
          newBalance: i.newBalance,
          sale: i.sale,
        );
}

// ───────────────────────── للمصمّم — على التصميم الخامّ ─────────────────────────

const Set<String> _knownTop = {
  'v', 'density', 'emoji', 'mono', 'currency', 'digits', 'fields', 'sections', 'blocks', 'titles', 'texts', 'order', //
  'types',
};

bool _sameJson(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

/// أقصر قائمةٍ تعطي الترتيب المحلول نفسه: تُحذف من آخرها المعرّفات التي يعيدها الحلّ إلى مكانها.
List<String> _minimalList(List<String> list, bool Function(List<String>) same) {
  var cur = List<String>.from(list);
  while (cur.isNotEmpty && same(cur.sublist(0, cur.length - 1))) {
    cur = cur.sublist(0, cur.length - 1);
  }
  return cur;
}

/// ما يُحفظ من `layout` (`compactLayout` في الموقع): يحذف كلّ ما يساوي الافتراضيّ، ولا يحفظ خاصيّةً خارج قدرات العنصر
/// (الخادم يرفضها)، ويحذف `size` حين يُثبَّت `pt`، ويُبقي **المفاتيح العليا التي لا يعرفها** كما هي، ولا يُنزل `v` تحت ٣.
/// null = تصميمٌ افتراضيّ (يُرسل `layout: null` فيبقى الوصل بطريق v1 حرفيّاً).
Map<String, dynamic>? receiptCompactLayout(Object? raw) {
  final r = raw is Map ? raw : const {};
  final l = ReceiptLayout.normalize(r);
  final rv = r['v'];
  final v = rv is int && rv > 3 ? rv : (rv is double && rv == rv.truncateToDouble() && rv > 3 ? rv.toInt() : 3);
  final out = <String, dynamic>{'v': v};
  if (l.density != 'normal') out['density'] = l.density;
  if (!l.emoji) out['emoji'] = false;
  if (l.mono) out['mono'] = true;
  if (l.currency != receiptDefaultCurrency) out['currency'] = l.currency;
  if (l.digits != 'latin') out['digits'] = l.digits;

  final fields = <String, dynamic>{};
  for (final id in receiptAllFieldIds) {
    final f = l.fields[id];
    if (f == null) continue;
    final caps = receiptFieldCaps[id]!;
    bool can(String p) => caps.contains(p);
    final def = receiptFieldDefs[id];
    final o = <String, dynamic>{};
    if (can('show') && f.show == false) o['show'] = false;
    if (can('label') && f.label != null && (def == null || f.label!.trim() != def.label)) o['label'] = f.label!.trim();
    if (can('size') && f.size != null && f.size != 'md' && f.pt == null) o['size'] = f.size;
    if (can('bold') && f.bold != null && (def == null || f.bold != def.bold)) o['bold'] = f.bold;
    if (can('pt') && f.pt != null) o['pt'] = f.pt;
    if (can('align') && f.align != null) o['align'] = f.align;
    if (can('row_mode') && f.rowMode != null) o['row_mode'] = f.rowMode;
    if (can('gap_before') && f.gapBefore != null) o['gap_before'] = f.gapBefore;
    if (can('gap_after') && f.gapAfter != null) o['gap_after'] = f.gapAfter;
    if (can('sep') && f.sep != null) o['sep'] = f.sep;
    if (can('only') && f.only != null && f.only!.length < receiptKinds.length) o['only'] = f.only;
    if (o.isNotEmpty) fields[id] = o;
  }
  if (fields.isNotEmpty) out['fields'] = fields;

  final sections = <String, dynamic>{};
  for (final id in receiptSectionIds) {
    final s = l.sections[id];
    if (s == null) continue;
    final caps = receiptSectionCaps[id]!;
    bool can(String p) => caps.contains(p);
    final o = <String, dynamic>{};
    final t = (s.title ?? '').trim();
    if (t.isNotEmpty && t != receiptSectionTitles[id]) o['title'] = t;
    if (s.showTitle == false) o['show_title'] = false;
    if (can('pt') && s.pt != null) o['pt'] = s.pt;
    if (can('align') && s.align != null) o['align'] = s.align;
    if (can('gap_before') && s.gapBefore != null) o['gap_before'] = s.gapBefore;
    if (can('gap_after') && s.gapAfter != null) o['gap_after'] = s.gapAfter;
    if (can('only') && s.only != null && s.only!.length < receiptKinds.length) o['only'] = s.only;
    if (o.isNotEmpty) sections[id] = o;
  }
  if (sections.isNotEmpty) out['sections'] = sections;

  final blocks = <String, dynamic>{};
  for (final id in receiptContainerIds) {
    final b = l.blocks[id];
    if (b == null) continue;
    final o = <String, dynamic>{};
    if (b.gapBefore != null) o['gap_before'] = b.gapBefore;
    if (b.gapAfter != null) o['gap_after'] = b.gapAfter;
    if (b.sep != null) o['sep'] = b.sep;
    if (b.only != null && b.only!.length < receiptKinds.length) o['only'] = b.only;
    if (o.isNotEmpty) blocks[id] = o;
  }
  if (blocks.isNotEmpty) out['blocks'] = blocks;

  final titles = <String, dynamic>{};
  for (final k in receiptKinds) {
    final t = (l.titles[k] ?? '').trim();
    if (t.isNotEmpty && t != receiptDefaultTitles[k]) titles[k] = t;
  }
  if (titles.isNotEmpty) out['titles'] = titles;

  final texts = <Map<String, dynamic>>[];
  for (final t in l.texts) {
    if (t.text.trim().isEmpty) continue;
    final o = <String, dynamic>{'id': 't${texts.length + 1}', 'at': t.at, 'text': t.text};
    if (t.align != 'center') o['align'] = t.align;
    if (t.size != 'md' && t.pt == null) o['size'] = t.size;
    if (t.bold) o['bold'] = true;
    if (t.boxed) o['boxed'] = true;
    if (t.only.isNotEmpty && t.only.length < receiptKinds.length) o['only'] = t.only;
    if (t.pt != null) o['pt'] = t.pt;
    if (t.gapBefore != 0) o['gap_before'] = t.gapBefore;
    if (t.gapAfter != 0) o['gap_after'] = t.gapAfter;
    if (t.sep != null) o['sep'] = t.sep;
    texts.add(o);
  }
  if (texts.isNotEmpty) out['texts'] = texts;

  // الترتيب: أقصر قوائم تعطي الحلّ نفسه؛ الافتراضيّ لا يُحفظ.
  final order = <String, dynamic>{};
  final blocksList = _minimalList(l.blockOrder, (x) => _sameJson(receiptResolveBlockOrder(x), l.blockOrder));
  if (blocksList.isNotEmpty) order['blocks'] = blocksList;
  final bodyList = _minimalList(l.bodyOrder, (x) => _sameJson(receiptResolveBodyOrder(x), l.bodyOrder));
  if (bodyList.isNotEmpty) order['body'] = bodyList;
  final lists = <String, List<String>>{for (final e in l.sectionFields.entries) e.key: e.value};
  for (final secId in receiptBodySections) {
    lists[secId] = _minimalList(
      lists[secId]!,
      (x) => _sameJson(receiptResolveSectionFields({...lists, secId: x}), l.sectionFields),
    );
  }
  for (final secId in receiptBodySections) {
    if (lists[secId]!.isNotEmpty) order[secId] = lists[secId];
  }
  if (order.isNotEmpty) out['order'] = order;

  // مفاتيح أعلى من نسخةٍ أحدث تبقى كما هي (types متقاعدٌ فيُسقط).
  for (final e in r.entries) {
    if (!_knownTop.contains(e.key)) out['${e.key}'] = e.value;
  }
  return out.length > 1 ? out : null;
}

/// التصميم افتراضيّ (لا شيء يُحفظ في `layout`).
bool receiptIsDefaultLayout(Object? raw) => receiptCompactLayout(raw) == null;

Object? _canon(Object? x) {
  if (x is Map) {
    final keys = [for (final k in x.keys) '$k']..sort();
    return {for (final k in keys) k: _canon(x[k])};
  }
  if (x is List) return [for (final v in x) _canon(v)];
  if (x is num) return _tidy(x);
  return x;
}

/// ما أُرسل وما رجع من الخادم: مسارات المفاتيح المختلفة («fields.username.pt»…) — [] = حُفظ كلّه (`layoutDiff`).
List<String> receiptLayoutDiff(Object? a, Object? b, [String path = '']) {
  if (jsonEncode(_canon(a)) == jsonEncode(_canon(b))) return const [];
  if (a is Map && b is Map) {
    final out = <String>[];
    for (final k in <String>{for (final x in a.keys) '$x', for (final x in b.keys) '$x'}) {
      out.addAll(receiptLayoutDiff(a[k], b[k], path.isEmpty ? k : '$path.$k'));
    }
    return out;
  }
  if (a is List && b is List && path == 'texts') {
    final out = <String>[];
    for (var i = 0; i < (a.length > b.length ? a.length : b.length); i++) {
      out.addAll(receiptLayoutDiff(i < a.length ? a[i] : null, i < b.length ? b[i] : null, 'texts[$i]'));
    }
    return out;
  }
  return [path.isEmpty ? 'layout' : path];
}

/// قدرات العنصر في المصمّم: حقلٌ أو قسمٌ أو حاوية (`capsOf`).
List<String> receiptCapsOf(String id) =>
    receiptFieldCaps[id] ?? receiptSectionCaps[id] ?? receiptContainerCaps[id] ?? const [];

/// الحجم الظاهر في المصمّم (`uiPt`): المثبَّت أو ما يطبعه الحجم النسبيّ اليوم مقرَّباً لنصف نقطة («تلقائي · 9»).
/// عنصرٌ واحد من [field] / [section] / [text] (فهرس النصّ).
({num pt, bool pinned}) receiptUiPt(Map design, Object? layout, {String? field, String? section, int? text}) {
  final l = ReceiptLayout.normalize(layout);
  final base = design['font_size_base'] is num ? design['font_size_base'] as num : 13;
  final title = design['font_size_title'] is num ? design['font_size_title'] as num : 16;
  num toPt(num px) => _tidy((px * 0.75 * 2).round() / 2);
  if (section != null) {
    final p = l.sections[section]?.pt;
    return p != null ? (pt: p, pinned: true) : (pt: toPt((base * receiptRatios['label']!).round()), pinned: false);
  }
  if (text != null) {
    if (text < 0 || text >= l.texts.length) return (pt: toPt((base * receiptRatios['value']!).round()), pinned: false);
    final t = l.texts[text];
    return t.pt != null
        ? (pt: t.pt!, pinned: true)
        : (pt: toPt((base * receiptRatios['value']! * receiptSizeScale[t.size]!).round()), pinned: false);
  }
  final id = field ?? '';
  final f = l.fields[id] ?? const ReceiptFieldStyle();
  if (f.pt != null) return (pt: f.pt!, pinned: true);
  final sc = receiptSizeScale[f.size ?? 'md']!;
  final px = switch (id) {
    'shop_name' => (title * sc).round(),
    'title' => (title * receiptRatios['subtitle']! * sc).round(),
    'receipt_no' || 'issued_at' => (base * receiptRatios['label']!).round(),
    'qr_caption' => (base * receiptRatios['caption']!).round(),
    'shop_address' || 'shop_phone' || 'issuer' || 'footer_text' => (base * receiptRatios['caption']! * sc).round(),
    _ => (base * receiptRatios['value']! * sc).round(),
  };
  return (pt: toPt(px), pinned: false);
}

/// كم عنصراً بحجمٍ مثبَّت (القوالب لا تمسّها — «N عناصر بحجمٍ مثبّت — إرجاعها للتلقائي»).
int receiptPinnedCount(Object? layout) {
  final l = ReceiptLayout.normalize(layout);
  var n = 0;
  for (final id in receiptAllFieldIds) {
    if (l.fields[id]?.pt != null) n++;
  }
  for (final id in receiptSectionIds) {
    if (l.sections[id]?.pt != null) n++;
  }
  for (final t in l.texts) {
    if (t.pt != null) n++;
  }
  return n;
}

/// يُرجع كلّ حجمٍ مثبَّت للتلقائي (`pt` يُحذف؛ `size` النسبيّ يبقى).
Map<String, dynamic> receiptUnpinAll(Map<String, dynamic> layout) {
  final out = <String, dynamic>{...layout};
  Object? strip(Object? m) {
    if (m is! Map) return m;
    return <String, dynamic>{
      for (final e in m.entries)
        '${e.key}': e.value is Map ? (Map<String, dynamic>.from(e.value as Map)..remove('pt')) : e.value,
    };
  }

  if (out['fields'] is Map) out['fields'] = strip(out['fields']);
  if (out['sections'] is Map) out['sections'] = strip(out['sections']);
  if (out['texts'] is List) {
    out['texts'] = [
      for (final t in out['texts'] as List) t is Map ? (Map<String, dynamic>.from(t)..remove('pt')) : t,
    ];
  }
  return out;
}

/// «قوالب جاهزة» (`applyTemplate`): الإعدادات العامّة وحدها (الورق ومفاتيح v1 والضغط و«أسود فقط») — الحقول والنصوص
/// والعناوين والرموز كما هي، والأحجام المثبَّتة تبقى مثبَّتة. `v` لا يَنزل.
({String paperSize, Map<String, dynamic> design, Map<String, dynamic> layout}) receiptApplyTemplate(
  ({String paperSize, Map<String, dynamic> design, Map<String, dynamic>? layout}) state,
  String id,
) {
  final t = receiptTemplates[id]!;
  final layout = state.layout ?? const <String, dynamic>{};
  final lv = layout['v'];
  final v = lv is int && lv > 3 ? lv : 3;
  return (
    paperSize: t.paperSize,
    design: {...state.design, ...t.v1},
    layout: {...layout, 'v': v, 'density': t.density, 'mono': t.mono},
  );
}

/// «يظهر في» للمصمّم: الأنواع المعروفة بترتيبها؛ فارغٌ أو كلّها ⇒ null (كلّ الأنواع).
List<String>? receiptOnly(Object? v) {
  final o = _onlyOf(v);
  return o == null || o.length == receiptKinds.length ? null : o;
}
