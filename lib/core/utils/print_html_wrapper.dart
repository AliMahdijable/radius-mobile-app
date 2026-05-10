import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/print_template_model.dart';

/// يبني الـHTML النهائي الجاهز للتحويل إلى PDF — بشمول CSS التصميم +
/// تضمين الخط الأساسي base64 لضمان توافق العرض على الـmobile حتى بدون
/// إنترنت. مشترك بين Pipeline الطباعة الفعلية و LiveReceiptPreview.
class PrintHtmlWrapper {
  /// كاش لـCairo base64 — نقرأ الملف مرة واحدة من assets ونعيد استخدامه.
  static String? _cairoB64;
  static Future<String>? _cairoLoader;

  static Future<String> _loadCairoBase64() async {
    if (_cairoB64 != null) return _cairoB64!;
    _cairoLoader ??= () async {
      final bytes = await rootBundle.load('assets/fonts/Cairo-Variable.ttf');
      final b64 = base64Encode(bytes.buffer.asUint8List());
      _cairoB64 = b64;
      return b64;
    }();
    return _cairoLoader!;
  }

  /// يبني HTML كاملاً مع CSS مدمج + خط Cairo مضمَّن base64 + Google Fonts
  /// عبر `<link>` للخطوط الأخرى (يعمل لو فيه إنترنت، يـfallback لخط النظام
  /// لو لا). الـHTML الداخلي يُفترض أنه استبدلت متغيّراته مسبقاً.
  static Future<String> build({
    required String filledHtml,
    required ReceiptDesign d,
  }) async {
    final cairoB64 = await _loadCairoBase64();
    final pad = '${d.marginTopMm}mm ${d.marginRightMm}mm '
        '${d.marginBottomMm}mm ${d.marginLeftMm}mm';

    // قائمة الخطوط الإضافية المتاحة عبر Google Fonts — تُحمَّل عند توفر
    // الإنترنت، وإلا يستخدم النظام أي خط عربي افتراضي.
    const googleFontUrls = {
      'Tajawal':
          'https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700;800&display=swap',
      'Amiri':
          'https://fonts.googleapis.com/css2?family=Amiri:wght@400;700&display=swap',
      'Noto Naskh Arabic':
          'https://fonts.googleapis.com/css2?family=Noto+Naskh+Arabic:wght@400;500;700&display=swap',
      'IBM Plex Sans Arabic':
          'https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;500;600;700&display=swap',
    };
    final extraFontLink = googleFontUrls[d.fontFamily];

    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
${extraFontLink != null ? '<link href="$extraFontLink" rel="stylesheet">' : ''}
<style>
  @font-face {
    font-family: 'Cairo';
    src: url(data:font/ttf;base64,$cairoB64) format('truetype');
    font-weight: 100 900;
    font-style: normal;
    font-display: swap;
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  :root {
    --accent: ${d.accentColor};
    --text:   ${d.textColor};
  }
  body {
    font-family: '${d.fontFamily}', 'Cairo', 'Noto Sans Arabic', Tahoma, sans-serif;
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
