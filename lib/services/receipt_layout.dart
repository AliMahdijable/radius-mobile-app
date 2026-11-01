import 'package:flutter/foundation.dart';

/// «تصميم الوصل» v2 — المالك ١ نوفمبر: «الطباعه اضافة ميزات اخفاء وتقليص الوصل والتحكم اكثر بالمتغيرات انطي صلاحيه
/// تصميم اكثر بوصل الطباعه والمعلومات يتحكم بيها اكثر من الاخفاء والاظهار».
///
/// التصميم في `receipt_settings.design_json` كما هو (مفاتيح v1 لا يتغيّر معناها — التطبيقات القديمة تطبع بها)، وv2 كائنٌ
/// واحد فيه: `design.layout` (الضغط، إظهار كلّ حقلٍ وتسميته وحجمه وعرضه، عناوين الأقسام، عنوانٌ لكلّ نوع وصل، نصوصٌ
/// بمتغيّرات، الرموز و«أسود فقط»). تصميمٌ بلا `layout` يُطبع بطريق v1 كما كان حرفاً بحرف ([ReceiptPdf]).
///
/// [ReceiptResolver.resolve] (التصميم الخامّ + بيانات الوصل ⇒ كتلٌ مرتّبة) نسخةٌ حرفيّة من `resolveReceipt` في الموقع
/// (`client-v2/src/lib/receipt-layout.ts`) — يربطهما ملفّ تثبيتٍ واحد: `test/fixtures/receipt_layout.fixtures.json` نسخةٌ
/// بالبايت من ملفّ الموقع، وبصمته [receiptFixturesSha256] مثبّتةٌ في المكانين. غيّرتَ معنى شيءٍ هنا؟ غيّر الملفّ وبصمته
/// في المستودعين معاً. الرسم (PDF الكاشير/A4، `receipt_pdf_v2.dart`) يرسم الكتل وحدها.
///
/// نقيّ: لا ساعة ولا شبكة ولا واجهة — الوقت والرقم يصلان نصّاً جاهزاً، وما لا يُفهم من التصميم افتراضيّ (لا رمي أبداً).

/// بصمة sha256 لملفّ التثبيت المشترك — هي نفسها `RECEIPT_FIXTURES_SHA256` في الموقع.
const String receiptFixturesSha256 = 'd18f3130a40e532cdaed7301fb32f6adfdd699cae87dde0a399a5e54f07614f1';

// ───────────────────────── الثوابت المشتركة (tokens في ملفّ التثبيت) ─────────────────────────

const List<String> receiptKinds = ['activation', 'extension', 'payment', 'info', 'sale'];
const List<String> receiptSizeSteps = ['xs', 'sm', 'md', 'lg', 'xl'];
const Map<String, num> receiptSizeScale = {'xs': 0.8, 'sm': 0.9, 'md': 1, 'lg': 1.2, 'xl': 1.4};

/// حجم الخطّ = round(font_size_base × النسبة × scale)؛ والعنوان الفرعيّ من font_size_title.
const Map<String, num> receiptRatios = {'value': 0.95, 'label': 0.85, 'caption': 0.78, 'subtitle': 0.8};
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

/// تعريف الحقل: مجموعته في المصمّم، تسميته، عرضه، اتّجاهه، كيف تُطبع تسميته (row · inline · caption · none)، ومفتاح v1
/// الذي يحكم ظهوره (إن وُجد ⇒ `fields[id].show` يُهمل — مصدرٌ واحد للحقيقة).
@immutable
class ReceiptFieldDef {
  const ReceiptFieldDef(this.group, this.label, {required this.bold, required this.ltr, required this.mode, this.v1});

  final String group;
  final String label;
  final bool bold;
  final bool ltr;
  final String mode;
  final String? v1;

  Map<String, Object?> toJson() => {'group': group, 'label': label, 'bold': bold, 'ltr': ltr, 'mode': mode, 'v1': v1};
}

/// الترتيب = ترتيب الوصل.
const List<String> receiptFieldIds = [
  'shop_name', 'shop_address', 'shop_phone', 'title', 'receipt_no', 'issued_at', //
  'subscriber_name', 'username', 'phone', //
  'package_name', 'package_price', 'expiry_date', 'days_remaining', //
  'payment_type', 'amount', 'cash_paid', 'balance_debt', 'balance_credit', //
  'qr_caption', 'issuer', 'footer_text',
];

const Map<String, ReceiptFieldDef> receiptFieldDefs = {
  'shop_name': ReceiptFieldDef('header', '', bold: true, ltr: false, mode: 'none'),
  'shop_address': ReceiptFieldDef('header', '', bold: false, ltr: false, mode: 'inline'),
  'shop_phone': ReceiptFieldDef('header', '', bold: false, ltr: true, mode: 'inline'),
  'title': ReceiptFieldDef('header', '', bold: true, ltr: false, mode: 'none'),
  'receipt_no': ReceiptFieldDef('header', '#', bold: false, ltr: true, mode: 'inline', v1: 'show_receipt_id'),
  'issued_at': ReceiptFieldDef('header', '', bold: false, ltr: true, mode: 'inline', v1: 'show_datetime'),
  'subscriber_name': ReceiptFieldDef('subscriber', 'الاسم', bold: true, ltr: false, mode: 'row'),
  'username': ReceiptFieldDef('subscriber', 'اسم المستخدم', bold: false, ltr: true, mode: 'row'),
  'phone': ReceiptFieldDef('subscriber', 'الهاتف', bold: false, ltr: true, mode: 'row'),
  'package_name': ReceiptFieldDef('package', 'الباقة', bold: true, ltr: false, mode: 'row'),
  'package_price': ReceiptFieldDef('package', 'سعر الباقة', bold: true, ltr: false, mode: 'row', v1: 'show_package_price'),
  'expiry_date': ReceiptFieldDef('package', 'تاريخ الانتهاء', bold: false, ltr: true, mode: 'row'),
  'days_remaining': ReceiptFieldDef('package', 'الأيام المتبقّية', bold: true, ltr: false, mode: 'row'),
  'payment_type': ReceiptFieldDef('transaction', 'طريقة الدفع', bold: true, ltr: false, mode: 'row'),
  'amount': ReceiptFieldDef('transaction', 'المبلغ', bold: true, ltr: false, mode: 'row'),
  'cash_paid': ReceiptFieldDef('transaction', 'المُدفَع نقداً', bold: true, ltr: false, mode: 'row'),
  'balance_debt': ReceiptFieldDef('transaction', 'الدين المتبقّي', bold: true, ltr: false, mode: 'row'),
  'balance_credit': ReceiptFieldDef('transaction', 'الرصيد المتبقّي', bold: true, ltr: false, mode: 'row'),
  'qr_caption': ReceiptFieldDef('qr', 'امسح للاطلاع على معلومات الاشتراك', bold: false, ltr: false, mode: 'caption'),
  'issuer': ReceiptFieldDef('footer', 'أصدره', bold: false, ltr: false, mode: 'inline', v1: 'show_manager_signature'),
  'footer_text': ReceiptFieldDef('footer', '', bold: false, ltr: false, mode: 'none'),
};

/// تسمياتٌ افتراضيّة تتغيّر بالحال (ما لم يكتب الوكيل تسميته).
const Map<String, String> receiptLabelVariants = {'amount_payment': 'المبلغ المسدَّد', 'balance_zero': 'الرصيد'};

const List<String> receiptSectionIds = ['subscriber', 'package', 'transaction', 'sale_customer', 'sale_items', 'sale_totals'];

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
  const ReceiptVarDef(this.id, this.label, this.kinds);

  final String id;
  final String label;
  final List<String> kinds;

  Map<String, Object> toJson() => {'id': id, 'label': label, 'kinds': kinds};
}

const List<String> _subs = ['activation', 'extension', 'payment', 'info'];

/// المتغيّرات بأسماء قوالب واتساب. متغيّرٌ نوعُ الوصل خارج kinds قيمته فارغة دائماً.
const List<ReceiptVarDef> receiptVariables = [
  ReceiptVarDef('shop_name', 'اسم المحلّ', receiptKinds),
  ReceiptVarDef('shop_phone', 'هاتف المحلّ', receiptKinds),
  ReceiptVarDef('shop_address', 'عنوان المحلّ', receiptKinds),
  ReceiptVarDef('receipt_type', 'نوع الوصل', receiptKinds),
  ReceiptVarDef('receipt_no', 'رقم الوصل', receiptKinds),
  ReceiptVarDef('date', 'التاريخ', receiptKinds),
  ReceiptVarDef('time', 'الوقت', receiptKinds),
  ReceiptVarDef('issuer', 'أصدره', receiptKinds),
  ReceiptVarDef('subscriber_name', 'اسم المشترك', receiptKinds),
  ReceiptVarDef('firstname', 'الاسم الأول', receiptKinds),
  ReceiptVarDef('username', 'اسم المستخدم', receiptKinds),
  ReceiptVarDef('phone', 'هاتف المشترك', receiptKinds),
  ReceiptVarDef('package_name', 'الباقة', _subs),
  ReceiptVarDef('sas_package_name', 'الباقة في الساس', _subs),
  ReceiptVarDef('package_price', 'سعر الباقة', _subs),
  ReceiptVarDef('expiry_date', 'تاريخ الانتهاء', _subs),
  ReceiptVarDef('days_remaining', 'الأيام المتبقّية (رقم)', ['activation', 'extension', 'info']),
  ReceiptVarDef('remaining_days', 'الأيام المتبقّية', ['activation', 'extension', 'info']),
  ReceiptVarDef('payment_type', 'طريقة الدفع', ['activation', 'extension']),
  ReceiptVarDef('amount', 'المبلغ', ['activation', 'extension', 'payment']),
  ReceiptVarDef('paid_amount', 'المدفوع', ['activation', 'extension', 'payment']),
  ReceiptVarDef('debt_amount', 'الدين', _subs),
  ReceiptVarDef('credit_amount', 'الرصيد', _subs),
  ReceiptVarDef('balance', 'الدين أو الرصيد', _subs),
  ReceiptVarDef('sale_total', 'مجموع الفاتورة', ['sale']),
  ReceiptVarDef('sale_payment', 'دفع الفاتورة', ['sale']),
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

/// `25,000 د.ع`: تقريب القيمة المطلقة وفواصل الآلاف الإنجليزيّة.
String receiptMoney(Object? n) {
  final v = _number(n).abs().round();
  final s = '$v';
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '$b د.ع';
}

// ───────────────────────── التصميم (layout) بتسامح ─────────────────────────

@immutable
class ReceiptFieldStyle {
  const ReceiptFieldStyle({this.show, this.label, this.size, this.bold});

  final bool? show;

  /// '' = بلا تسمية.
  final String? label;
  final String? size;
  final bool? bold;
}

@immutable
class ReceiptSectionStyle {
  const ReceiptSectionStyle({this.title, this.showTitle});

  final String? title;
  final bool? showTitle;
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
}

/// `design.layout` مقروءاً بتسامح (`normalizeLayout` في الموقع): ما لا يُفهم افتراضيّ، والمعرّفات المجهولة تُهمل.
@immutable
class ReceiptLayout {
  const ReceiptLayout({
    this.density = 'normal',
    this.emoji = true,
    this.mono = false,
    this.fields = const {},
    this.sections = const {},
    this.titles = const {},
    this.texts = const [],
  });

  final String density;
  final bool emoji;
  final bool mono;
  final Map<String, ReceiptFieldStyle> fields;
  final Map<String, ReceiptSectionStyle> sections;
  final Map<String, String> titles;
  final List<ReceiptCustomText> texts;

  /// `null` حين لا يكون كائناً (⇒ وصل v1).
  static ReceiptLayout? fromJson(Object? raw) => raw is Map ? normalize(raw) : null;

  /// لا يرمي أبداً: غير الكائن ⇒ الافتراضيّ.
  static ReceiptLayout normalize(Object? raw) {
    final l = raw is Map ? raw : const {};
    final fields = <String, ReceiptFieldStyle>{};
    final f = l['fields'];
    if (f is Map) {
      for (final id in receiptFieldIds) {
        final x = f[id];
        if (x is! Map) continue;
        final show = x['show'];
        final label = x['label'];
        final bold = x['bold'];
        fields[id] = ReceiptFieldStyle(
          show: show is bool ? show : null,
          label: label is String ? label : null,
          size: _oneOf(x['size'], receiptSizeSteps),
          bold: bold is bool ? bold : null,
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
        final at = _oneOf(x['at'], receiptTextPositions);
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
        ));
      }
    }
    return ReceiptLayout(
      density: _oneOf(l['density'], receiptDensities) ?? 'normal',
      emoji: l['emoji'] != false,
      mono: l['mono'] == true,
      fields: fields,
      sections: sections,
      titles: titles,
      texts: texts,
    );
  }

  /// الحقول المخفيّة بقرار المالك في v2 (بلا الأربعة التي ظهورها من مفاتيح v1 — تُعدّ هناك).
  int get hiddenFields =>
      fields.entries.where((e) => e.value.show == false && receiptFieldDefs[e.key]?.v1 == null).length;
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

@immutable
sealed class RBlock {
  const RBlock();

  Map<String, Object?> toJson();
}

class RLogo extends RBlock {
  const RLogo(this.align);

  final String align;
  @override
  Map<String, Object?> toJson() => {'t': 'logo', 'align': align};
}

class RShopName extends RBlock {
  const RShopName({required this.text, required this.scale, required this.bold, required this.align});

  final String text;
  final num scale;
  final bool bold;
  final String align;
  @override
  Map<String, Object?> toJson() => {'t': 'shop_name', 'text': text, 'scale': scale, 'bold': bold, 'align': align};
}

@immutable
class RShopLine {
  const RShopLine({
    required this.id,
    required this.text,
    required this.ltr,
    required this.icon,
    required this.scale,
    required this.bold,
  });

  /// 'shop_address' | 'shop_phone'
  final String id;
  final String text;
  final bool ltr;

  /// 'pin' | 'phone' — الموقع يرسمه رمزاً تعبيريّاً حين الرموز مفعّلة، والتطبيق لا يرسم رموزاً.
  final String icon;
  final num scale;
  final bool bold;
  Map<String, Object?> toJson() => {'id': id, 'text': text, 'ltr': ltr, 'icon': icon, 'scale': scale, 'bold': bold};
}

class RShopLines extends RBlock {
  const RShopLines({required this.lines, required this.align});

  final List<RShopLine> lines;
  final String align;
  @override
  Map<String, Object?> toJson() => {'t': 'shop_lines', 'lines': [for (final l in lines) l.toJson()], 'align': align};
}

class RTitle extends RBlock {
  const RTitle({required this.text, required this.scale, required this.bold, required this.align});

  final String text;
  final num scale;
  final bool bold;
  final String align;
  @override
  Map<String, Object?> toJson() => {'t': 'title', 'text': text, 'scale': scale, 'bold': bold, 'align': align};
}

class RMeta extends RBlock {
  const RMeta({required this.no, required this.at});

  /// «#No. 00012» (التسمية ملتصقة) أو null.
  final String? no;
  final String? at;
  @override
  Map<String, Object?> toJson() => {'t': 'meta', 'no': no, 'at': at};
}

@immutable
class RRow {
  const RRow({
    required this.id,
    required this.label,
    required this.value,
    required this.ltr,
    required this.bold,
    required this.scale,
    this.tone,
  });

  final String id;

  /// null = القيمة وحدها (تسميةٌ فارغة).
  final String? label;
  final String value;
  final bool ltr;
  final bool bold;
  final num scale;

  /// 'debt' أحمر · 'credit' أخضر · 'total' بحجم العنوان الفرعيّ (الألوان لـA4 وحده ما لم يكن «أسود فقط»).
  final String? tone;
  Map<String, Object?> toJson() =>
      {'id': id, 'label': label, 'value': value, 'ltr': ltr, 'bold': bold, 'scale': scale, 'tone': tone};
}

class RSection extends RBlock {
  const RSection({required this.id, required this.title, required this.rows});

  final String id;
  final String? title;
  final List<RRow> rows;
  @override
  Map<String, Object?> toJson() =>
      {'t': 'section', 'id': id, 'title': title, 'rows': [for (final r in rows) r.toJson()]};
}

class RSaleVoid extends RBlock {
  const RSaleVoid(this.text);

  final String text;
  @override
  Map<String, Object?> toJson() => {'t': 'sale_void', 'text': text};
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
  const RSaleItems({required this.title, required this.lines});

  final String? title;
  final List<RSaleLine> lines;
  @override
  Map<String, Object?> toJson() => {'t': 'sale_items', 'title': title, 'lines': [for (final l in lines) l.toJson()]};
}

class RSaleNote extends RBlock {
  const RSaleNote(this.text);

  final String text;
  @override
  Map<String, Object?> toJson() => {'t': 'sale_note', 'text': text};
}

class RText extends RBlock {
  const RText({
    required this.id,
    required this.text,
    required this.align,
    required this.scale,
    required this.bold,
    required this.boxed,
  });

  final String id;
  final String text;
  final String align;
  final num scale;
  final bool bold;
  final bool boxed;
  @override
  Map<String, Object?> toJson() =>
      {'t': 'text', 'id': id, 'text': text, 'align': align, 'scale': scale, 'bold': bold, 'boxed': boxed};
}

class RQr extends RBlock {
  const RQr({required this.caption, required this.align});

  final String? caption;
  final String align;
  @override
  Map<String, Object?> toJson() => {'t': 'qr', 'caption': caption, 'align': align};
}

@immutable
class RFooterLine {
  const RFooterLine({required this.id, required this.text, required this.icon, required this.scale, required this.bold});

  /// 'issuer' | 'footer_text'
  final String id;
  final String text;

  /// 'pray' (🙏 بالموقع بعد التذييل الافتراضيّ) أو null.
  final String? icon;
  final num scale;
  final bool bold;
  Map<String, Object?> toJson() => {'id': id, 'text': text, 'icon': icon, 'scale': scale, 'bold': bold};
}

class RFooter extends RBlock {
  const RFooter({required this.lines, required this.align});

  final List<RFooterLine> lines;
  final String align;
  @override
  Map<String, Object?> toJson() => {'t': 'footer', 'lines': [for (final l in lines) l.toJson()], 'align': align};
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
Map<String, String> receiptVars(ReceiptInput input) {
  final s = input.subscriber;
  final kind = input.kind;
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
    'package_price': price != null && price > 0 ? receiptMoney(price) : '',
    'expiry_date': _expiryText(input),
    'days_remaining': days != null ? _jsNum(days) : '',
    'remaining_days': days != null ? '${_jsNum(days)} يوم' : '',
    'payment_type': pay != null ? receiptPaymentLabels[pay]! : '',
    'amount': amount != null ? receiptMoney(amount) : '',
    'paid_amount': paid != null ? receiptMoney(paid) : '',
    'debt_amount': nb != null && nb < 0 ? receiptMoney(nb) : '',
    'credit_amount': nb != null && nb > 0 ? receiptMoney(nb) : '',
    'balance': nb == null ? '' : (nb < 0 ? 'دين ${receiptMoney(nb)}' : (nb > 0 ? 'رصيد ${receiptMoney(nb)}' : receiptMoney(0))),
    'sale_total': sale != null ? receiptMoney(sale.total) : '',
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
      .map((l) => l.replaceAll(RegExp('[ \t ]+'), ' ').trim())
      .where((l) => l != '')
      .toList();
  final res = lines.join('\n');
  return (text: res, hidden: res == '' || (known > 0 && filled == 0));
}

/// «التسمية: القيمة» — بلا تسمية ⇒ القيمة وحدها؛ تسميةٌ تنتهي بـ# تلتصق (#No. 00012)؛ وبـ: يتبعها فراغ.
String receiptJoinLabel(String label, String value) {
  final l = label.trim();
  if (l.isEmpty) return value;
  if (l.endsWith('#')) return '$l$value';
  if (l.endsWith(':')) return '$l $value';
  return '$l: $value';
}

// ───────────────────────── المحلِّل ─────────────────────────

/// التصميم الخامّ (`design_json`: مفاتيح v1 + `layout`) + بيانات الوصل ⇒ كتلٌ مرتّبة — `resolveReceipt` في الموقع.
class ReceiptResolver {
  ReceiptResolver._();

  static ResolvedReceipt resolve(Object? design, ReceiptInput input) {
    final d = design is Map ? design : const {};
    final l = ReceiptLayout.normalize(d['layout']);
    final kind = receiptKinds.contains(input.kind) ? input.kind : 'activation';
    bool sw(String k) => d.containsKey(k) ? d[k] != false : receiptV1Defaults[k] == true;
    String hAlign(String k) => _oneOf(d[k], receiptHAligns) ?? receiptV1Defaults[k]! as String;
    final labelAlign = _oneOf(d['default_align'], receiptLabelAligns) ?? 'right';
    final valueAlign = labelAlign == 'center' ? 'center' : (labelAlign == 'left' ? 'right' : 'left');
    final vars = receiptVars(_withKind(input, kind));

    ReceiptFieldStyle st(String id) => l.fields[id] ?? const ReceiptFieldStyle();
    bool visible(String id) {
      final v1 = receiptFieldDefs[id]!.v1;
      return v1 != null ? sw(v1) : st(id).show != false;
    }

    num scale(String id) => receiptSizeScale[st(id).size ?? 'md']!;
    bool bold(String id) => st(id).bold ?? receiptFieldDefs[id]!.bold;
    String labelOf(String id, [String? fallback]) {
      final c = st(id).label;
      if (c != null) return c.trim();
      return fallback ?? receiptFieldDefs[id]!.label;
    }

    RRow row(String id, String value, [String? tone, String? fallbackLabel]) {
      final label = labelOf(id, fallbackLabel);
      return RRow(
        id: id,
        label: label == '' ? null : label,
        value: value,
        ltr: receiptFieldDefs[id]!.ltr,
        bold: bold(id),
        scale: scale(id),
        tone: tone,
      );
    }

    String? sectionTitle(String id) {
      final s = l.sections[id] ?? const ReceiptSectionStyle();
      if (s.showTitle == false) return null;
      final custom = (s.title ?? '').trim();
      final t = custom.isNotEmpty ? custom : receiptSectionTitles[id]!;
      return t.isNotEmpty ? t : null;
    }

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
          scale: receiptSizeScale[t.size]!,
          bold: t.bold,
          boxed: t.boxed,
        ));
      }
    }

    // ١–٢. نصوص أعلى الوصل، الشعار
    pushTexts('top');
    if (sw('show_logo') && input.hasLogo) blocks.add(RLogo(hAlign('logo_align')));
    // ٣. اسم المحلّ
    if (visible('shop_name')) {
      blocks.add(RShopName(
        text: _shopNameOf(input),
        scale: scale('shop_name'),
        bold: bold('shop_name'),
        align: hAlign('header_align'),
      ));
    }
    // ٤. العنوان والهاتف
    if (sw('show_shop_info')) {
      final lines = <RShopLine>[];
      final addr = _str(input.shopAddress);
      final tel = _str(input.shopPhone);
      if (addr.isNotEmpty && visible('shop_address')) {
        lines.add(RShopLine(
          id: 'shop_address',
          text: receiptJoinLabel(labelOf('shop_address'), addr),
          ltr: false,
          icon: 'pin',
          scale: scale('shop_address'),
          bold: bold('shop_address'),
        ));
      }
      if (tel.isNotEmpty && visible('shop_phone')) {
        lines.add(RShopLine(
          id: 'shop_phone',
          text: receiptJoinLabel(labelOf('shop_phone'), tel),
          ltr: true,
          icon: 'phone',
          scale: scale('shop_phone'),
          bold: bold('shop_phone'),
        ));
      }
      if (lines.isNotEmpty) blocks.add(RShopLines(lines: lines, align: hAlign('header_align')));
    }
    // ٥–٦. عنوان الوصل (لا يختفي) ثمّ نصوص بعده
    if (visible('title')) {
      final custom = (l.titles[kind] ?? '').trim();
      var text = custom.isNotEmpty ? receiptFill(custom, vars).text : '';
      if (text.isEmpty) text = receiptFill(receiptDefaultTitles[kind]!, vars).text;
      blocks.add(RTitle(text: text, scale: scale('title'), bold: bold('title'), align: hAlign('header_align')));
    }
    pushTexts('after_title');
    // ٧. الرقم والتاريخ (الفاتورة رقمها في عنوانها)
    final rid = _str(input.receiptId);
    final issued = _str(input.issuedText);
    final no =
        sw('show_receipt_id') && kind != 'sale' && rid.isNotEmpty ? receiptJoinLabel(labelOf('receipt_no'), rid) : null;
    final at = sw('show_datetime') && issued.isNotEmpty ? receiptJoinLabel(labelOf('issued_at'), issued) : null;
    if (no != null || at != null) blocks.add(RMeta(no: no, at: at));

    // ٨. الجسم
    final s = input.subscriber;
    if (kind == 'sale') {
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
          if (rows.isNotEmpty) blocks.add(RSection(id: 'sale_customer', title: sectionTitle('sale_customer'), rows: rows));
        }
        blocks.add(RSaleItems(
          title: sectionTitle('sale_items'),
          lines: [
            for (final x in sale.lines)
              RSaleLine(
                name: _str(x.name),
                detail: '${_str(x.qtyText)} × ${receiptMoney(x.unitPrice)}',
                total: receiptMoney(x.total),
              ),
          ],
        ));
        blocks.add(RSection(id: 'sale_totals', title: sectionTitle('sale_totals'), rows: [
          RRow(
            id: 'sale_total',
            label: receiptSaleLabels['total'],
            value: receiptMoney(sale.total),
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
        final note = _str(sale.note);
        if (note.isNotEmpty) blocks.add(RSaleNote('${receiptSaleLabels['note']}: $note'));
      }
    } else {
      if (sw('show_subscriber_info')) {
        final rows = <RRow>[];
        final name = _displayName(input);
        if (visible('subscriber_name') && name.isNotEmpty) rows.add(row('subscriber_name', name));
        if (visible('username') && _str(s.username).isNotEmpty) rows.add(row('username', _str(s.username)));
        if (visible('phone') && _str(s.phone).isNotEmpty) rows.add(row('phone', _str(s.phone)));
        if (rows.isNotEmpty) blocks.add(RSection(id: 'subscriber', title: sectionTitle('subscriber'), rows: rows));
      }
      if (sw('show_package_info')) {
        final rows = <RRow>[];
        final price = _num(s.packagePrice);
        final days = _num(s.remainingDays);
        final pkg = _str(s.packageName);
        if (visible('package_name')) rows.add(row('package_name', pkg.isNotEmpty ? pkg : '—'));
        if (visible('package_price') && price != null && price > 0) rows.add(row('package_price', receiptMoney(price)));
        if (visible('expiry_date') && _expiryText(input).isNotEmpty) rows.add(row('expiry_date', _expiryText(input)));
        if (visible('days_remaining') && days != null) rows.add(row('days_remaining', '${_jsNum(days)} يوم'));
        if (rows.isNotEmpty) blocks.add(RSection(id: 'package', title: sectionTitle('package'), rows: rows));
      }
      if (sw('show_transaction_info')) {
        final rows = <RRow>[];
        final amount = _num(input.amount);
        final pay = receiptPaymentLabels.containsKey(input.paymentType) ? input.paymentType : null;
        if (kind == 'activation' || kind == 'extension') {
          if (visible('payment_type') && pay != null) rows.add(row('payment_type', receiptPaymentLabels[pay]!));
          if (visible('amount') && amount != null) rows.add(row('amount', receiptMoney(amount)));
          final part = _num(input.partialAmount);
          if (visible('cash_paid') && pay == 'partial-cash' && part != null) {
            rows.add(row('cash_paid', receiptMoney(part)));
          }
        } else if (kind == 'payment') {
          if (visible('amount') && amount != null) {
            rows.add(row('amount', receiptMoney(amount), null, receiptLabelVariants['amount_payment']));
          }
        }
        final nb = _num(input.newBalance);
        if (nb != null) {
          if (nb < 0) {
            if (visible('balance_debt')) rows.add(row('balance_debt', receiptMoney(nb), 'debt'));
          } else if (visible('balance_credit')) {
            rows.add(row('balance_credit', receiptMoney(nb), nb > 0 ? 'credit' : null,
                nb > 0 ? null : receiptLabelVariants['balance_zero']));
          }
        }
        if (rows.isNotEmpty) blocks.add(RSection(id: 'transaction', title: sectionTitle('transaction'), rows: rows));
      }
    }

    // ٩–١٠. نصوص قبل QR، ثمّ QR (لا QR للفاتورة)
    pushTexts('before_qr');
    if (input.hasQr && kind != 'sale') {
      final cap = visible('qr_caption') ? labelOf('qr_caption') : '';
      blocks.add(RQr(caption: cap.isNotEmpty ? cap : null, align: hAlign('qr_align')));
    }
    // ١١. الذيل
    if (sw('show_footer')) {
      final lines = <RFooterLine>[];
      final issuer = _str(input.issuer);
      if (visible('issuer') && issuer.isNotEmpty) {
        lines.add(RFooterLine(
          id: 'issuer',
          text: receiptJoinLabel(labelOf('issuer'), issuer),
          icon: null,
          scale: scale('issuer'),
          bold: bold('issuer'),
        ));
      }
      if (visible('footer_text')) {
        final own = (input.footerText ?? '')
            .split(RegExp(r'\r?\n'))
            .map((x) => x.trim())
            .where((x) => x != '')
            .join('\n');
        lines.add(RFooterLine(
          id: 'footer_text',
          text: own.isNotEmpty ? own : receiptDefaultFooter,
          icon: own.isNotEmpty ? null : 'pray',
          scale: scale('footer_text'),
          bold: bold('footer_text'),
        ));
      }
      if (lines.isNotEmpty) blocks.add(RFooter(lines: lines, align: hAlign('footer_align')));
    }
    // ١٢. نصوص أسفل الوصل
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
