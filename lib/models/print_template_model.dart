/// التصميم البصري للوصل — مرآة للـReceiptDesign بـclient-v2/lib/print-receipt.ts.
/// يُخزَّن كـJSON في عمود `template_data` بـDB، ويُقرأ هنا للسماح بالتحرير
/// من الموبايل بنفس درجة التحكم التي يوفّرها الويب.
class ReceiptDesign {
  // ── ورق ──
  double paperWidthMm;       // 50-120 (POS فقط)
  double marginTopMm;        // 0-30
  double marginRightMm;
  double marginBottomMm;
  double marginLeftMm;
  String a4Orientation;      // portrait | landscape

  // ── خطوط ──
  String fontFamily;         // Cairo | Tajawal | Almarai
  double fontSizeBase;       // 9-22
  double fontSizeTitle;      // 12-36
  String fontWeight;         // 400 | 500 | 600 | 700 | 800

  // ── ألوان ──
  String accentColor;        // #RRGGBB
  String textColor;

  // ── إطار + تخطيط ──
  String borderStyle;        // none | solid | dashed | dotted | double
  double borderRadiusPx;     // 0-20
  double sectionGapMm;       // 0-20
  double lineHeight;         // 1.0-2.2
  String defaultAlign;       // right | center | left | justify
  String headerAlign;        // right | center | left
  String footerAlign;
  double logoSizeMm;         // 8-50
  String logoAlign;
  double qrSizeMm;           // 15-60
  String qrAlign;
  String rowSeparator;       // none | solid | dashed | dotted
  bool sectionTitleUppercase;
  bool sectionTitleUnderline;

  // ── إظهار/إخفاء ──
  bool showLogo;
  bool showShopInfo;
  bool showSubscriberInfo;
  bool showPackageInfo;
  bool showPackagePrice;
  bool showTransactionInfo;
  bool showFooter;
  bool showManagerSignature;
  bool showReceiptId;
  bool showDatetime;

  ReceiptDesign({
    this.paperWidthMm = 80,
    this.marginTopMm = 4,
    this.marginRightMm = 4,
    this.marginBottomMm = 4,
    this.marginLeftMm = 4,
    this.a4Orientation = 'portrait',
    this.fontFamily = 'Cairo',
    this.fontSizeBase = 13,
    this.fontSizeTitle = 16,
    this.fontWeight = '700',
    this.accentColor = '#0d9488',
    this.textColor = '#0f172a',
    this.borderStyle = 'dashed',
    this.borderRadiusPx = 8,
    this.sectionGapMm = 6,
    this.lineHeight = 1.5,
    this.defaultAlign = 'right',
    this.headerAlign = 'center',
    this.footerAlign = 'center',
    this.logoSizeMm = 18,
    this.logoAlign = 'center',
    this.qrSizeMm = 35,
    this.qrAlign = 'center',
    this.rowSeparator = 'dotted',
    this.sectionTitleUppercase = true,
    this.sectionTitleUnderline = true,
    this.showLogo = true,
    this.showShopInfo = true,
    this.showSubscriberInfo = true,
    this.showPackageInfo = true,
    this.showPackagePrice = true,
    this.showTransactionInfo = true,
    this.showFooter = true,
    this.showManagerSignature = true,
    this.showReceiptId = true,
    this.showDatetime = true,
  });

  /// نسخة مستقلّة — تُستعمل قبل أي تعديل حتى لا نُلوّث المرجع المشترَك
  /// (وإلا لن تكتشف معاينة الـWebView التغيير لأنه يحدث على نفس الكائن).
  ReceiptDesign clone() => ReceiptDesign.fromJson(toJson());

  factory ReceiptDesign.fromJson(Map<String, dynamic> j) {
    double _d(dynamic v, double fallback) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? fallback;
    bool _b(dynamic v, bool fallback) =>
        v is bool ? v : (v == 1 || v == '1' || v == 'true') ? true : (v == null ? fallback : false);
    String _s(dynamic v, String fallback) =>
        v == null ? fallback : v.toString();

    return ReceiptDesign(
      paperWidthMm: _d(j['paper_width_mm'], 80),
      marginTopMm: _d(j['margin_top_mm'], 4),
      marginRightMm: _d(j['margin_right_mm'], 4),
      marginBottomMm: _d(j['margin_bottom_mm'], 4),
      marginLeftMm: _d(j['margin_left_mm'], 4),
      a4Orientation: _s(j['a4_orientation'], 'portrait'),
      fontFamily: _s(j['font_family'], 'Cairo'),
      fontSizeBase: _d(j['font_size_base'], 13),
      fontSizeTitle: _d(j['font_size_title'], 16),
      fontWeight: _s(j['font_weight'], '700'),
      accentColor: _s(j['accent_color'], '#0d9488'),
      textColor: _s(j['text_color'], '#0f172a'),
      borderStyle: _s(j['border_style'], 'dashed'),
      borderRadiusPx: _d(j['border_radius_px'], 8),
      sectionGapMm: _d(j['section_gap_mm'], 6),
      lineHeight: _d(j['line_height'], 1.5),
      defaultAlign: _s(j['default_align'], 'right'),
      headerAlign: _s(j['header_align'], 'center'),
      footerAlign: _s(j['footer_align'], 'center'),
      logoSizeMm: _d(j['logo_size_mm'], 18),
      logoAlign: _s(j['logo_align'], 'center'),
      qrSizeMm: _d(j['qr_size_mm'], 35),
      qrAlign: _s(j['qr_align'], 'center'),
      rowSeparator: _s(j['row_separator'], 'dotted'),
      sectionTitleUppercase: _b(j['section_title_uppercase'], true),
      sectionTitleUnderline: _b(j['section_title_underline'], true),
      showLogo: _b(j['show_logo'], true),
      showShopInfo: _b(j['show_shop_info'], true),
      showSubscriberInfo: _b(j['show_subscriber_info'], true),
      showPackageInfo: _b(j['show_package_info'], true),
      showPackagePrice: _b(j['show_package_price'], true),
      showTransactionInfo: _b(j['show_transaction_info'], true),
      showFooter: _b(j['show_footer'], true),
      showManagerSignature: _b(j['show_manager_signature'], true),
      showReceiptId: _b(j['show_receipt_id'], true),
      showDatetime: _b(j['show_datetime'], true),
    );
  }

  Map<String, dynamic> toJson() => {
        'paper_width_mm': paperWidthMm,
        'margin_top_mm': marginTopMm,
        'margin_right_mm': marginRightMm,
        'margin_bottom_mm': marginBottomMm,
        'margin_left_mm': marginLeftMm,
        'a4_orientation': a4Orientation,
        'font_family': fontFamily,
        'font_size_base': fontSizeBase,
        'font_size_title': fontSizeTitle,
        'font_weight': fontWeight,
        'accent_color': accentColor,
        'text_color': textColor,
        'border_style': borderStyle,
        'border_radius_px': borderRadiusPx,
        'section_gap_mm': sectionGapMm,
        'line_height': lineHeight,
        'default_align': defaultAlign,
        'header_align': headerAlign,
        'footer_align': footerAlign,
        'logo_size_mm': logoSizeMm,
        'logo_align': logoAlign,
        'qr_size_mm': qrSizeMm,
        'qr_align': qrAlign,
        'row_separator': rowSeparator,
        'section_title_uppercase': sectionTitleUppercase,
        'section_title_underline': sectionTitleUnderline,
        'show_logo': showLogo,
        'show_shop_info': showShopInfo,
        'show_subscriber_info': showSubscriberInfo,
        'show_package_info': showPackageInfo,
        'show_package_price': showPackagePrice,
        'show_transaction_info': showTransactionInfo,
        'show_footer': showFooter,
        'show_manager_signature': showManagerSignature,
        'show_receipt_id': showReceiptId,
        'show_datetime': showDatetime,
      };
}

class PrintTemplateModel {
  final int? id;
  final String adminId;
  final String templateType; // 'a4' or 'pos'
  final String templateName;
  final String content; // HTML with placeholders
  final String? templateData; // JSON builder state
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  const PrintTemplateModel({
    this.id,
    required this.adminId,
    required this.templateType,
    required this.templateName,
    required this.content,
    this.templateData,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory PrintTemplateModel.fromJson(Map<String, dynamic> json) {
    return PrintTemplateModel(
      id: json['id'] as int?,
      adminId: json['admin_id']?.toString() ?? '',
      templateType: json['template_type']?.toString() ?? 'pos',
      templateName: json['template_name']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      templateData: json['template_data']?.toString(),
      isActive: json['is_active'] == 1 || json['is_active'] == true,
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'adminId': adminId,
        'templateType': templateType,
        'templateName': templateName,
        'content': content,
        if (templateData != null) 'templateData': templateData,
        'isActive': isActive,
      };

  PrintTemplateModel copyWith({
    int? id,
    String? adminId,
    String? templateType,
    String? templateName,
    String? content,
    String? templateData,
    bool? isActive,
  }) {
    return PrintTemplateModel(
      id: id ?? this.id,
      adminId: adminId ?? this.adminId,
      templateType: templateType ?? this.templateType,
      templateName: templateName ?? this.templateName,
      content: content ?? this.content,
      templateData: templateData ?? this.templateData,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static const List<String> availableVariables = [
    '{receipt_no}',
    '{invoice_number}',
    '{date}',
    '{subscriber_name}',
    '{phone_number}',
    '{package_name}',
    '{package_price}',
    '{paid_amount}',
    '{remaining_amount}',
    '{expiry_date}',
    '{debt_amount}',
  ];

  static const Map<String, String> variableLabels = {
    '{receipt_no}': 'رقم الوصل (No. 00000)',
    '{invoice_number}': 'رقم الفاتورة (legacy)',
    '{date}': 'التاريخ',
    '{subscriber_name}': 'اسم المشترك',
    '{phone_number}': 'رقم الهاتف',
    '{package_name}': 'اسم الباقة',
    '{package_price}': 'سعر الباقة',
    '{paid_amount}': 'المبلغ المدفوع',
    '{remaining_amount}': 'المبلغ المتبقي',
    '{expiry_date}': 'تاريخ الانتهاء',
    '{debt_amount}': 'مبلغ الدين',
  };

  /// قوالب افتراضية — تستخدم CSS variables (var(--accent) / var(--text))
  /// والـfont-size بالـem حتى تستجيب لإعدادات التصميم (الخط، الحجم، الألوان،
  /// الهوامش) المُطبَّقة على الـ.page wrapper. لا ألوان/مقاسات صلبة.
  static String defaultPosTemplate() => '''
<div style="text-align:center; border-bottom: 1.5px dashed var(--accent); padding-bottom: 8px; margin-bottom: 10px;">
  <h2 style="margin:0;">{shop_name}</h2>
  <div style="font-size:0.85em; opacity:0.7;">{receipt_no}</div>
  <div style="font-size:0.8em; opacity:0.6;">{date}</div>
</div>
<div style="font-size:1em;">
  <div style="display:flex; justify-content:space-between; padding:2px 0;"><span style="opacity:0.7;">الاسم</span><b>{firstname}</b></div>
  <div style="display:flex; justify-content:space-between; padding:2px 0;"><span style="opacity:0.7;">اسم المستخدم</span><b>{subscriber_name}</b></div>
  <div style="display:flex; justify-content:space-between; padding:2px 0;"><span style="opacity:0.7;">الهاتف</span><b>{phone_number}</b></div>
  <hr style="border:none; border-top:1px dotted var(--accent); margin:6px 0; opacity:0.5;">
  <div style="display:flex; justify-content:space-between; padding:2px 0;"><span style="opacity:0.7;">الباقة</span><b>{package_name}</b></div>
  <div style="display:flex; justify-content:space-between; padding:2px 0;"><span style="opacity:0.7;">السعر</span><b>{package_price}</b></div>
  <div style="display:flex; justify-content:space-between; padding:2px 0;"><span style="opacity:0.7;">المدفوع</span><b>{paid_amount}</b></div>
  <div style="display:flex; justify-content:space-between; padding:2px 0;"><span style="opacity:0.7;">المتبقي</span><b>{remaining_amount}</b></div>
  <div style="display:flex; justify-content:space-between; padding:2px 0;"><span style="opacity:0.7;">الانتهاء</span><b>{expiry_date}</b></div>
</div>
<div style="text-align:center; border-top:1.5px dashed var(--accent); margin-top:10px; padding-top:8px; font-size:0.8em; opacity:0.7;">
  شكراً لاختياركم خدماتنا
</div>''';

  static String defaultA4Template() => '''
<div style="display:flex; justify-content:space-between; align-items:flex-start; border-bottom:2px solid var(--accent); padding-bottom:14px; margin-bottom:20px;">
  <div>
    <h1 style="margin:0;">{shop_name}</h1>
    <div style="font-size:0.9em; opacity:0.7;">{receipt_no}</div>
  </div>
  <div style="text-align:left; font-size:0.9em; opacity:0.7;">{date}</div>
</div>
<h3 style="margin:0 0 8px;">معلومات المشترك</h3>
<table style="width:100%; border-collapse:collapse; font-size:0.95em; margin-bottom:18px;">
  <tr><td style="padding:6px; border:1px solid rgba(0,0,0,0.12); opacity:0.7;">الاسم</td><td style="padding:6px; border:1px solid rgba(0,0,0,0.12);"><b>{firstname}</b></td></tr>
  <tr><td style="padding:6px; border:1px solid rgba(0,0,0,0.12); opacity:0.7;">اسم المستخدم</td><td style="padding:6px; border:1px solid rgba(0,0,0,0.12);"><b>{subscriber_name}</b></td></tr>
  <tr><td style="padding:6px; border:1px solid rgba(0,0,0,0.12); opacity:0.7;">الهاتف</td><td style="padding:6px; border:1px solid rgba(0,0,0,0.12);">{phone_number}</td></tr>
  <tr><td style="padding:6px; border:1px solid rgba(0,0,0,0.12); opacity:0.7;">الباقة</td><td style="padding:6px; border:1px solid rgba(0,0,0,0.12);">{package_name}</td></tr>
  <tr><td style="padding:6px; border:1px solid rgba(0,0,0,0.12); opacity:0.7;">سعر الباقة</td><td style="padding:6px; border:1px solid rgba(0,0,0,0.12);">{package_price}</td></tr>
  <tr><td style="padding:6px; border:1px solid rgba(0,0,0,0.12); opacity:0.7;">المدفوع</td><td style="padding:6px; border:1px solid rgba(0,0,0,0.12);">{paid_amount}</td></tr>
  <tr><td style="padding:6px; border:1px solid rgba(0,0,0,0.12); opacity:0.7;">المتبقي</td><td style="padding:6px; border:1px solid rgba(0,0,0,0.12);">{remaining_amount}</td></tr>
  <tr><td style="padding:6px; border:1px solid rgba(0,0,0,0.12); opacity:0.7;">تاريخ الانتهاء</td><td style="padding:6px; border:1px solid rgba(0,0,0,0.12);">{expiry_date}</td></tr>
</table>
<div style="text-align:center; margin-top:30px; padding-top:14px; border-top:1px solid rgba(0,0,0,0.12); font-size:0.85em; opacity:0.7;">
  شكراً لاختياركم خدماتنا
</div>''';
}
