import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/copyable.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../theme/colors.dart';

/// عنوان الجهاز (IP) رابطاً: النقر يفتح واجهة إدارته بالمتصفح (`http://IP`) على كلّ المنصّات — أندرويد وآيفون وويندوز
/// والماك — والضغط المطوّل (أو الزرّ الأيمن) ينسخه كما كان ([Copyable]).
///
/// المالك ٣٠ أكتوبر: «بقسم الاجهزه ضيفلنا ميزه النقر على الايبي الجهاز يفتح كوكل يعني يفتح الرابط بالمتصفح في جميع المنصات».
/// `http` لا `https`: واجهات الأجهزة (مايكروتك، يوبيكويتي، الأولتات…) تجيب على 80 أو تحوّل بنفسها إلى https.
/// داخل بطاقةٍ تفتح الجهاز بالنقر: النقر على العنوان نفسه يفتح المتصفح، وخارجه يفتح الجهاز كما كان.
class DeviceIpLink extends StatelessWidget {
  const DeviceIpLink(
    this.ip, {
    super.key,
    this.text,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String ip;

  /// النصّ المعروض بدل العنوان وحده («العنوان · الطراز» في بطاقة النظرة العامّة).
  final String? text;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;

  /// رابط الجهاز: `http://IP`؛ IPv6 بين قوسين؛ «host:port» كما هو؛ رابطٌ بمخطّطه (http/https) يُترك؛ فارغٌ أو بمسافات ⇒ null.
  static Uri? urlFor(String raw) {
    final v = raw.trim();
    if (v.isEmpty || v == '—' || v == '-' || RegExp(r'\s').hasMatch(v)) return null;
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(v)) {
      final u = Uri.tryParse(v);
      return u != null && u.host.isNotEmpty ? u : null;
    }
    // IPv6 بلا قوسين (أكثر من نقطتين رأسيّتين) ⇒ [..]؛ وإلّا host أو host:port.
    final host = ':'.allMatches(v).length > 1 && !v.startsWith('[') ? '[$v]' : v;
    final u = Uri.tryParse('http://$host');
    return u != null && u.host.isNotEmpty ? u : null;
  }

  /// يفتح الرابط بالمتصفح الخارجيّ — يُستبدل في الاختبار.
  @visibleForTesting
  static Future<bool> Function(Uri url) launcher = (url) => launchUrl(url, mode: LaunchMode.externalApplication);

  /// يفتح واجهة الجهاز؛ تعذّر الفتح ⇒ رسالةٌ قصيرة (لا صمت).
  static Future<void> open(BuildContext context, String ip) async {
    final url = urlFor(ip);
    if (url == null) return;
    var ok = false;
    try {
      ok = await launcher(url);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) showSheetSnack(context, 'تعذّر فتح المتصفح على $ip', isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final url = urlFor(ip);
    final base = style ?? DefaultTextStyle.of(context).style;
    final label = Text(
      text ?? ip,
      maxLines: maxLines,
      overflow: overflow,
      textDirection: text == null ? TextDirection.ltr : null,
      style: url == null
          ? base
          : base.copyWith(
              color: AppColors.brandAccent,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.brandAccent.withValues(alpha: 0.45),
            ),
    );
    if (url == null) return label;
    return Copyable(
      label: 'IP',
      value: ip,
      child: Semantics(
        link: true,
        label: 'افتح $ip بالمتصفح',
        child: Tooltip(
          message: 'فتح بالمتصفح',
          waitDuration: const Duration(milliseconds: 600),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => open(context, ip),
              child: label,
            ),
          ),
        ),
      ),
    );
  }
}
