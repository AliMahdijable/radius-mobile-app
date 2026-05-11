import '../../models/print_template_model.dart';

/// يبني الـHTML النهائي (محتوى القالب بعد ملء المتغيّرات + CSS مشتقّ من
/// ReceiptDesign). يُستخدم في موضعين:
///   • LiveReceiptPreview → يحمّله في WebView (عرض دقيق لما يطبع)
///   • ReceiptPrinter.printReceipt → يمرّره لـPrinting.convertHtml
///
/// نُحمّل خطّ Google المختار عبر `<link>` كي تنعكس "نوع الخط" فعلياً في
/// المعاينة (تطابق الويب). لو لا يوجد إنترنت يسقط المتصفّح تلقائياً إلى
/// خطوط النظام (Noto Sans Arabic / Tahoma) — والطباعة لها fallback أصلي.
class PrintHtmlWrapper {
  /// خرائط اسم العائلة → شريحة رابط Google Fonts (بأوزان مناسبة).
  static const Map<String, String> _gfSlugs = {
    'Cairo': 'Cairo:wght@400;500;600;700;800;900',
    'Tajawal': 'Tajawal:wght@400;500;700;800',
    'Amiri': 'Amiri:wght@400;700',
    'Noto Naskh Arabic': 'Noto+Naskh+Arabic:wght@400;500;600;700',
    'IBM Plex Sans Arabic': 'IBM+Plex+Sans+Arabic:wght@400;500;600;700',
  };

  static String _fontLink(String family) {
    final slug = _gfSlugs[family] ?? _gfSlugs['Cairo']!;
    return '<link rel="preconnect" href="https://fonts.googleapis.com">'
        '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
        '<link href="https://fonts.googleapis.com/css2?family=$slug&display=swap" rel="stylesheet">';
  }

  static String build({
    required String filledHtml,
    required ReceiptDesign d,
    required String type, // 'pos' | 'a4'
  }) {
    final pad = '${d.marginTopMm}mm ${d.marginRightMm}mm '
        '${d.marginBottomMm}mm ${d.marginLeftMm}mm';
    // عرض الصفحة: POS = عرض الورق المختار، A4 = 210mm (أو 297 إذا أفقي).
    final pageWidth = type == 'a4'
        ? (d.a4Orientation == 'landscape' ? '297mm' : '210mm')
        : '${d.paperWidthMm}mm';
    final borderCss = switch (d.borderStyle) {
      'none' => 'none',
      'double' => '3px double',
      _ => '1px ${d.borderStyle}',
    };

    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, minimum-scale=0.5, maximum-scale=5.0, user-scalable=yes">
${_fontLink(d.fontFamily)}
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body {
    background: #f4f4f6;
    -webkit-text-size-adjust: 100%;
    overflow-x: hidden;
  }
  :root { --accent: ${d.accentColor}; --text: ${d.textColor}; }
  .page {
    background: #fff;
    width: $pageWidth;
    max-width: calc(100% - 16px);
    margin: 8px auto;
    padding: $pad;
    overflow: hidden;            /* امنع المحتوى من تجاوز الحدود */
    box-shadow: 0 2px 12px rgba(0,0,0,0.10);
    font-family: '${d.fontFamily}', 'Noto Sans Arabic', 'Noto Naskh Arabic', Tahoma, Arial, sans-serif;
    direction: rtl;
    font-size: ${d.fontSizeBase}px;
    font-weight: ${d.fontWeight};
    color: ${d.textColor};
    line-height: ${d.lineHeight};
    ${borderCss == 'none' ? '' : 'border: $borderCss ${d.accentColor}; border-radius: ${d.borderRadiusPx}px;'}
  }
  /* أي عنصر داخل الوصل لا يتجاوز عرض الصفحة، والنصوص الطويلة تلتفّ */
  .page * {
    max-width: 100%;
    overflow-wrap: break-word;
    word-wrap: break-word;
  }
  .page table { width: 100%; table-layout: fixed; }
  .page td { overflow-wrap: break-word; }
  h1, h2, h3 { color: var(--accent); font-size: ${d.fontSizeTitle}px; font-weight: 800; }
  @media print {
    html, body { background: #fff; }
    .page { box-shadow: none; margin: 0; width: 100%; max-width: 100%; }
  }
</style>
</head>
<body>
<div class="page">$filledHtml</div>
</body>
</html>
''';
  }
}
