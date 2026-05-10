import '../../models/print_template_model.dart';

/// يبني الـHTML النهائي الجاهز للتحويل إلى PDF — بشمول CSS التصميم +
/// تحميل الخط عبر Google Fonts (نفس ما تستخدمه الويب) بدون base64
/// (لأن الخطوط الكبيرة المضمَّنة كانت تُهنّك convertHtml خاصة على A4).
class PrintHtmlWrapper {
  /// كل عائلة تجلب أوزانها الأساسية من Google Fonts. لو ما توفر إنترنت،
  /// يفـallback إلى أي خط عربي موجود بالنظام (Noto Sans Arabic عادةً).
  static const Map<String, String> _googleFontUrls = {
    'Cairo':
        'https://fonts.googleapis.com/css2?family=Cairo:wght@400;600;700;800&display=swap',
    'Tajawal':
        'https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700;800&display=swap',
    'Amiri':
        'https://fonts.googleapis.com/css2?family=Amiri:wght@400;700&display=swap',
    'Noto Naskh Arabic':
        'https://fonts.googleapis.com/css2?family=Noto+Naskh+Arabic:wght@400;500;700&display=swap',
    'IBM Plex Sans Arabic':
        'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&display=swap',
  };

  static String build({
    required String filledHtml,
    required ReceiptDesign d,
  }) {
    final pad = '${d.marginTopMm}mm ${d.marginRightMm}mm '
        '${d.marginBottomMm}mm ${d.marginLeftMm}mm';
    final fontUrl = _googleFontUrls[d.fontFamily];
    final fontLink = fontUrl != null
        ? '<link href="$fontUrl" rel="stylesheet">'
        : '';

    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
$fontLink
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  :root {
    --accent: ${d.accentColor};
    --text:   ${d.textColor};
  }
  body {
    font-family: '${d.fontFamily}', 'Noto Sans Arabic', Tahoma, sans-serif;
    direction: rtl;
    padding: $pad;
    font-size: ${d.fontSizeBase}px;
    font-weight: ${d.fontWeight};
    color: ${d.textColor};
    line-height: ${d.lineHeight};
  }
  h1, h2, h3 {
    color: var(--accent);
    font-size: ${d.fontSizeTitle}px;
    font-weight: 800;
  }
  @media print { body { padding: 0; } }
</style>
</head>
<body>$filledHtml</body>
</html>
''';
  }
}
