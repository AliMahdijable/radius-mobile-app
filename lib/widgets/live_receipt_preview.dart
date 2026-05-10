import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/print_html_wrapper.dart';
import '../core/utils/receipt_printer.dart' as rp;
import '../models/print_template_model.dart';

/// لوحة معاينة لايف للوصل — تحوّل HTML+design إلى PDF داخل الذاكرة وتعرض
/// أول صفحة كصورة. الـUI:
///   • شريط علوي: عنوان + زر تحديث + زر طيّ/فتح
///   • منطقة العرض: 220px ارتفاع، scroll أفقي لتغطية الورق العريض
///   • إعادة الرسم تحدث بعد 1 ثانية من توقف التعديل (debounce)
///   • ✅ يستعمل ReceiptPrinter._fillTemplate الموجود (نفس الـrenderer
///     المستخدم وقت الطباعة الفعلية) — مطابقة 1:1 لما يخرج للطابعة
class LiveReceiptPreview extends StatefulWidget {
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
  bool _rendering = false;
  Uint8List? _imageBytes;
  String? _error;
  Timer? _debounce;
  int _generation = 0; // يحمي من سباق التحديثات

  // Zoom — Controller للـInteractiveViewer + قيمة عرض حالية
  final TransformationController _zoomCtrl = TransformationController();
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
    _scheduleRender(delay: 100);
  }

  @override
  void didUpdateWidget(covariant LiveReceiptPreview old) {
    super.didUpdateWidget(old);
    final changed = old.htmlTemplate != widget.htmlTemplate ||
        old.templateType != widget.templateType ||
        !_designEquals(old.design, widget.design);
    if (changed) _scheduleRender();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _zoomCtrl.dispose();
    super.dispose();
  }

  void _zoomIn() {
    final next = (_currentScale * 1.4).clamp(0.5, 5.0);
    _setZoom(next);
  }

  void _zoomOut() {
    final next = (_currentScale / 1.4).clamp(0.5, 5.0);
    _setZoom(next);
  }

  void _zoomReset() => _setZoom(1.0);

  void _setZoom(double scale) {
    setState(() {
      _currentScale = scale;
      _zoomCtrl.value = Matrix4.identity()..scale(scale);
    });
  }

  bool _designEquals(ReceiptDesign a, ReceiptDesign b) {
    // مقارنة سريعة عبر JSON. الحقول كلها primitive فالتسلسل ثابت.
    return a.toJson().toString() == b.toJson().toString();
  }

  void _scheduleRender({int delay = 900}) {
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: delay), _renderNow);
  }

  Future<void> _renderNow() async {
    if (!mounted) return;
    if (widget.htmlTemplate.trim().isEmpty) {
      setState(() {
        _imageBytes = null;
        _error = 'لا يوجد محتوى HTML';
      });
      return;
    }
    final myGen = ++_generation;
    setState(() {
      _rendering = true;
      _error = null;
    });
    try {
      final pdfBytes = await _buildPdf();
      if (myGen != _generation || !mounted) return;
      // الـraster stream قد يكون فارغاً لو الـPDF ما فيه صفحات
      // (HTML malformed). نستعمل firstOrNull سلوكاً فبدلاً من throw نعرض رسالة.
      PdfRaster? raster;
      await for (final r in Printing.raster(pdfBytes, dpi: 110)) {
        raster = r;
        break;
      }
      if (myGen != _generation || !mounted) return;
      if (raster == null) {
        setState(() {
          _rendering = false;
          _error = 'لم يتم توليد أي صفحة من القالب';
        });
        return;
      }
      final png = await raster.toPng();
      if (myGen != _generation || !mounted) return;
      setState(() {
        _imageBytes = png;
        _rendering = false;
      });
    } catch (e) {
      if (myGen != _generation || !mounted) return;
      setState(() {
        _rendering = false;
        _error = 'تعذّر إنشاء المعاينة: $e';
      });
    }
  }

  Future<Uint8List> _buildPdf() async {
    // POS roll height — convertHtml لا يقبل double.infinity فاستخدم
    // ارتفاع كبير معقول (297mm = A4 height) كحدّ أعلى. الـHTML نفسه
    // سيقصّ في الواقع لما المحتوى ينتهي.
    final format = widget.templateType == 'a4'
        ? (widget.design.a4Orientation == 'landscape'
            ? PdfPageFormat.a4.landscape
            : PdfPageFormat.a4)
        : PdfPageFormat(
            widget.design.paperWidthMm * PdfPageFormat.mm,
            297 * PdfPageFormat.mm,
          );
    // نستخدم نفس الـwrapper اللي يستخدمه الطباعة الفعلية — فالمعاينة
    // والطباعة تتشاركان نفس CSS، نفس @font-face لـCairo، نفس قيم
    // التصميم. الـreceiptNo رقم تجريبي للمعاينة فقط.
    final filled = rp.ReceiptPrinter.testFillTemplate(
      widget.htmlTemplate,
      widget.sampleData,
      receiptNo: 12345,
    );
    final wrapper =
        await PrintHtmlWrapper.build(filledHtml: filled, d: widget.design);
    return await Printing.convertHtml(html: wrapper, format: format);
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
                if (_rendering)
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
                    onPressed: _renderNow,
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

          // Body
          if (_expanded) ...[
            Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.10),
            ),
            Container(
              height: 480,
              width: double.infinity,
              color: const Color(0xFFF4F4F6),
              child: _buildPreviewBody(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPreviewBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.circleAlert,
                  size: 28, color: Colors.red.shade400),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }
    if (_imageBytes == null) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _zoomCtrl,
          maxScale: 5,
          minScale: 0.3,
          // Allow free pan; content larger than viewport is normal for A4
          constrained: false,
          boundaryMargin: const EdgeInsets.all(200),
          onInteractionEnd: (_) {
            final s = _zoomCtrl.value.getMaxScaleOnAxis();
            if ((s - _currentScale).abs() > 0.01) {
              setState(() => _currentScale = s);
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              // ارسم بالأبعاد الطبيعية للصورة. هذا مهم خصوصاً لـA4
              // (910x1286px @110dpi) حتى المحتوى يطلع واضحاً والمستخدم
              // يسحب/يكبّر بدل ما يشاهد نقطة بالمنتصف.
              child: Image.memory(_imageBytes!),
            ),
          ),
        ),
        // أزرار الـzoom — overlay بأسفل اليسار
        Positioned(
          bottom: 10,
          left: 10,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(LucideIcons.zoomOut, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _currentScale > 0.6 ? _zoomOut : null,
                ),
                InkWell(
                  onTap: _zoomReset,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '${(_currentScale * 100).round()}%',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(LucideIcons.zoomIn, size: 18),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: _currentScale < 4.5 ? _zoomIn : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
