import '../../models/print_template_model.dart';

/// يبني الـHTML النهائي (محتوى القالب بعد ملء المتغيّرات + CSS مشتقّ من
/// ReceiptDesign). يُستخدم في موضعين:
///   • LiveReceiptPreview → يحمّله في WebView (عرض دقيق لما يطبع)
///   • ReceiptPrinter.printReceipt → يمرّره لـPrinting.convertHtml
///
/// لا نُضمّن أي مورد خارجي (`<link>` لخطوط) — يُهنّ webview الطباعة بلا
/// إنترنت. نعتمد على خطوط النظام (Noto Sans Arabic / Tahoma).
class PrintHtmlWrapper {
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
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body {
    background: #f4f4f6;
    -webkit-text-size-adjust: 100%;
  }
  :root { --accent: ${d.accentColor}; --text: ${d.textColor}; }
  .page {
    background: #fff;
    width: $pageWidth;
    max-width: 100%;
    margin: 8px auto;
    padding: $pad;
    box-shadow: 0 2px 12px rgba(0,0,0,0.10);
    font-family: '${d.fontFamily}', 'Noto Sans Arabic', 'Noto Naskh Arabic', Tahoma, Arial, sans-serif;
    direction: rtl;
    font-size: ${d.fontSizeBase}px;
    font-weight: ${d.fontWeight};
    color: ${d.textColor};
    line-height: ${d.lineHeight};
    ${borderCss == 'none' ? '' : 'border: $borderCss ${d.accentColor}; border-radius: ${d.borderRadiusPx}px;'}
  }
  h1, h2, h3 { color: var(--accent); font-size: ${d.fontSizeTitle}px; font-weight: 800; }
  @media print {
    html, body { background: #fff; }
    .page { box-shadow: none; margin: 0; width: 100%; }
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
