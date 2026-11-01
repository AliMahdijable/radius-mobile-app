import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../services/receipt_pdf.dart';
import '../../../services/receipt_preview.dart';
import '../../../services/receipt_samples.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'controls.dart';
import 'designer_controller.dart';

/// أنواع الوصل بترتيب الشرائح.
const List<ReceiptKind> designerKinds = [
  ReceiptKind.activation,
  ReceiptKind.extension,
  ReceiptKind.payment,
  ReceiptKind.info,
  ReceiptKind.sale,
];

/// المعاينة (spec §4.5): شرائح النوع، و«الطول ≈ N ملم»، وصورة الوصل كما يُطبع — بايتات الطباعة نفسها (عيّنة الموقع)،
/// تُبنى في خيطٍ آخر بعد ٢٠٠ ملّي ثانية من آخر تعديل. نظامٌ لا يرسم PDF صورةً ⇒ زرّ «اطبع تجربة».
class PreviewPane extends StatefulWidget {
  const PreviewPane({
    super.key,
    required this.controller,
    required this.preview,
    required this.kind,
    required this.onKind,
    required this.shopName,
    required this.issuer,
    required this.qrAvailable,
    required this.canRaster,
    required this.onPrintSample,
  });

  final ReceiptDesignController controller;
  final ReceiptPreviewController preview;
  final ReceiptKind kind;
  final ValueChanged<ReceiptKind> onKind;

  /// اسم المحلّ الاحتياطيّ (اسم الحساب) و«أصدره» — كما في الطباعة.
  final String shopName;
  final String? issuer;

  /// الشركة تطبع QR (الساس) — ايرث لنك وفايبر اكس والمُضافة لا.
  final bool qrAvailable;
  final bool canRaster;
  final VoidCallback onPrintSample;

  @override
  State<PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<PreviewPane> {
  double _paneWidth = 0;

  /// كثافة الشاشة كما قُرئت في البناء (لا قراءة سياقٍ خارج البناء).
  double _dpr = 2;
  ({int rev, ReceiptKind kind, double w})? _asked;
  bool _showTiming = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onDesign);
  }

  @override
  void didUpdateWidget(PreviewPane old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onDesign);
      widget.controller.addListener(_onDesign);
    }
    if (old.kind != widget.kind || old.shopName != widget.shopName) _request();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onDesign);
    super.dispose();
  }

  void _onDesign() => _request();

  bool get _a4 => widget.controller.paperSize == 'a4';

  double get _paperMm => _a4 ? 210 : widget.controller.draft.paperWidthMm;

  /// عرض الورق على الشاشة: ٥٨ أضيق من ٨٠ كما في الحقيقة، وA4 بعرض اللوحة.
  double _displayWidth(double pane) {
    final usable = pane - 2 * Sp.md;
    final f = _a4 ? 1.0 : (_paperMm / 82).clamp(0.5, 1.0);
    return usable * f;
  }

  void _request() {
    final c = widget.controller;
    if (!widget.canRaster || c.loading || c.loadError != null || _paneWidth <= 0) return;
    final key = (rev: c.revision, kind: widget.kind, w: _paneWidth);
    if (_asked == key) return;
    _asked = key;
    final look = c.draft;
    final doc = receiptSampleDoc(
      widget.kind,
      look: look,
      shopName: look.shopName ?? widget.shopName,
      issuer: widget.issuer,
      qr: widget.qrAvailable && look.showQr,
    );
    final dpr = _dpr;
    widget.preview.request(
      doc,
      a4: _a4,
      dpi: ReceiptPreviewController.dpiFor(
        paneWidthDp: _displayWidth(_paneWidth),
        devicePixelRatio: dpr,
        paperMm: _paperMm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    _dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2;
    return Container(
      color: AppColors.surfaceSunken,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.xs),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final k in designerKinds) ...[
                          DesignerChip(
                            label: designerKindChips[k.name]!,
                            selected: widget.kind == k,
                            dense: true,
                            onTap: () => widget.onKind(k),
                          ),
                          const SizedBox(width: Sp.x6),
                        ],
                      ],
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: widget.preview,
                  builder: (_, __) => _LengthLabel(
                    a4: _a4,
                    heightMm: widget.preview.heightMm,
                    timing: _showTiming ? widget.preview.lastRender : null,
                    onLongPress: () => setState(() => _showTiming = !_showTiming),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth != _paneWidth) {
                  _paneWidth = box.maxWidth;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _request();
                  });
                }
                if (!widget.canRaster) return _NoRaster(onPrint: widget.onPrintSample);
                return ListenableBuilder(
                  listenable: widget.preview,
                  builder: (_, __) => _Paper(
                    preview: widget.preview,
                    width: _displayWidth(box.maxWidth),
                    onPrint: widget.onPrintSample,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LengthLabel extends StatelessWidget {
  const _LengthLabel({required this.a4, required this.heightMm, required this.timing, required this.onLongPress});

  final bool a4;
  final double? heightMm;
  final Duration? timing;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final h = heightMm;
    final text = a4 ? 'A4' : (h == null ? '… ملم' : '≈ ${h.round()} ملم');
    return GestureDetector(
      // ضغطةٌ طويلة: زمن آخر معاينة (قياس سرعتها على الهاتف).
      onLongPress: () {
        HapticFeedback.selectionClick();
        onLongPress();
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: Sp.sm),
        child: Text(
          timing == null ? text : '$text · ${timing!.inMilliseconds} ms',
          style: AppType.muted(color: AppColors.textMid),
        ),
      ),
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({required this.preview, required this.width, required this.onPrint});

  final ReceiptPreviewController preview;
  final double width;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final img = preview.image;
    if (img == null) {
      if (preview.error != null) return _NoRaster(onPrint: onPrint, message: preview.error);
      return const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    final h = width * img.height / img.width;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.xs, Sp.md, Sp.lg),
      child: Center(
        child: Stack(
          children: [
            Container(
              width: width,
              height: h,
              decoration: BoxDecoration(
                color: AppColors.paper,
                border: Border.all(color: AppColors.border),
                boxShadow: Sh.menu,
              ),
              child: RawImage(image: img, width: width, height: h, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
            ),
            if (preview.busy)
              PositionedDirectional(
                top: Sp.xs,
                end: Sp.xs,
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.textLow),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoRaster extends StatelessWidget {
  const _NoRaster({required this.onPrint, this.message});
  final VoidCallback onPrint;
  final String? message;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.receipt, size: 28, color: AppColors.textLow),
            const SizedBox(height: Sp.sm),
            Text(
              message ?? 'المعاينة غير متاحة على هذا الجهاز',
              textAlign: TextAlign.center,
              style: AppType.body(color: AppColors.textMid),
            ),
            const SizedBox(height: Sp.sm),
            TextButton.icon(
              onPressed: onPrint,
              icon: Icon(LucideIcons.printer, size: 16, color: AppColors.brand),
              label: Text('اطبع تجربة', style: AppType.bodyStrong(color: AppColors.brand)),
            ),
          ],
        ),
      ),
    );
  }
}
