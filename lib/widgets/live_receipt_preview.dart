import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/receipt_printer.dart' as rp;
import '../models/print_template_model.dart';

/// لوحة معاينة لايف للوصل — تعرض الـHTML الفعلي للقالب (مع CSS مشتقّ من
/// التصميم) داخل WebView. هذا يطابق تماماً ما يخرج للطباعة عبر
/// `Printing.convertHtml` على نفس الـHTML — فما تشوفه هو ما يطبع.
///
/// لماذا WebView وليس PDF→raster؟ لأن convertHtml→raster على بعض أجهزة
/// أندرويد يتعثّر مع صفحات A4؛ والـnative renderer لا يطابق الـHTML
/// المخصّص من الباك ايند. WebView يرسم الـHTML+CSS مباشرةً، بسرعة وموثوقية.
class LiveReceiptPreview extends StatefulWidget {
  /// محتوى قالب الـHTML (من template.content). فارغ → نعرض رسالة.
  final String htmlTemplate;
  final ReceiptDesign design;
  final String templateType; // 'pos' | 'a4'
  final rp.ReceiptData sampleData;

  const LiveReceiptPreview({
    super.key,
    required this.htmlTemplate,
    required this.design,
    required this.templateType,
    required this.sampleData,
  });

  @override
  State<LiveReceiptPreview> createState() => _LiveReceiptPreviewState();
}

class _LiveReceiptPreviewState extends State<LiveReceiptPreview> {
  bool _expanded = true;
  bool _loading = true;
  Timer? _debounce;
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setBackgroundColor(const Color(0xFFF4F4F6))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
        onWebResourceError: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ));
    _scheduleReload(delay: 80);
  }

  @override
  void didUpdateWidget(covariant LiveReceiptPreview old) {
    super.didUpdateWidget(old);
    final changed = old.htmlTemplate != widget.htmlTemplate ||
        old.templateType != widget.templateType ||
        !_designEquals(old.design, widget.design);
    if (changed) _scheduleReload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  bool _designEquals(ReceiptDesign a, ReceiptDesign b) =>
      a.toJson().toString() == b.toJson().toString();

  // قصير بما يكفي ليبدو "لحظياً" عند تحريك المؤشّرات، ودون إعادة رسم
  // على كل إطار.
  void _scheduleReload({int delay = 250}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: delay), _reloadNow);
  }

  void _reloadNow() {
    if (!mounted) return;
    setState(() => _loading = true);
    final html = rp.ReceiptPrinter.buildPreviewHtml(
      htmlTemplate: widget.htmlTemplate,
      data: widget.sampleData,
      design: widget.design,
      type: widget.templateType,
      receiptNo: 12345,
    );
    _controller.loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
              child: Row(children: [
                Icon(LucideIcons.eye, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'معاينة مباشرة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  IconButton(
                    icon: const Icon(LucideIcons.refreshCw, size: 16),
                    tooltip: 'تحديث',
                    visualDensity: VisualDensity.compact,
                    onPressed: _reloadNow,
                  ),
                IconButton(
                  icon: Icon(
                    _expanded
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 18,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ]),
            ),
          ),

          // Body — WebView داخل ارتفاع ثابت، scroll داخلي يتكفّل بطول الوصل.
          if (_expanded) ...[
            Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.10),
            ),
            SizedBox(
              height: 360,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(12)),
                child: Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (_loading)
                      const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
