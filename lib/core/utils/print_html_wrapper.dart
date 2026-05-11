import '../../models/print_template_model.dart';

/// يبني الـHTML النهائي الجاهز للتحويل إلى PDF.
///
/// ملاحظة مهمة: لا نُضمّن أي `<link>` لخطوط خارجية (Google Fonts) — لأن
/// الـwebview الداخلي الذي يستعمله Printing.convertHtml يحاول جلب المورد
/// قبل الرسم، فإن لم يكن هناك إنترنت سريع → يتوقف rendering ويُرمى
/// TimeoutException. بدلاً من ذلك نعتمد على خطوط النظام: على أندرويد
/// "Noto Sans Arabic" يعرض العربية بجودة جيدة، وعلى iOS خط النظام.
/// font-family المختار من المستخدم يبقى أول في السلسلة، فإذا توفر الخط
/// على الجهاز يُستخدم.
class PrintHtmlWrapper {
  static String build({
    required String filledHtml,
    required ReceiptDesign d,
  }) {
    final pad = '${d.marginTopMm}mm ${d.marginRightMm}mm '
        '${d.marginBottomMm}mm ${d.marginLeftMm}mm';

    return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
<meta charset="UTF-8">
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  :root {
    --accent: ${d.accentColor};
    --text:   ${d.textColor};
  }
  body {
    font-family: '${d.fontFamily}', 'Noto Sans Arabic', 'Noto Naskh Arabic', Tahoma, Arial, sans-serif;
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
