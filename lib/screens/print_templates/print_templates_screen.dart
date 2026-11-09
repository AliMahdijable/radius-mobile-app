import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/platform/desktop_layout.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/permission_locked.dart';
import '../../core/widgets/print_feedback.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/active_company.dart';
import '../../services/merged_mode.dart';
import '../../services/permissions_service.dart';
import '../../services/print_output.dart';
import '../../services/print_prefs.dart';
import '../../services/provider_service.dart';
import '../../services/receipt_layout.dart';
import '../../services/receipt_pdf.dart';
import '../../services/receipt_pdf_v2.dart';
import '../../services/receipt_preview.dart';
import '../../services/receipt_samples.dart';
import '../../services/receipt_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'designer/controls.dart';
import 'designer/designer_controller.dart';
import 'designer/designer_elements.dart';
import 'designer/element_inspector_sheet.dart';
import 'designer/elements_tab.dart';
import 'designer/paper_tab.dart';
import 'designer/preview_pane.dart';
import 'designer/texts_tab.dart';
import 'issuer_names_sheet.dart';

/// «تصميم الوصل» في التطبيق — مصمّمٌ كامل (spec §4.4)، كان عرضاً للقراءة. المالك يجرّب على الهاتف:
/// المعاينة فوق (صورة الطباعة نفسها، ٤٢٪ من الشاشة)، وتحتها «العناصر» (كلّ ما في الوصل بترتيبه — النقر يفتح خصائصه في
/// ورقةٍ لا تغطّي المعاينة)، و«الورق والخطّ»، و«النصوص». «حفظ» يظهر حين يتغيّر شيء، و«تراجع» خطوةً خطوة.
///
/// القفل (لا إخفاء): موظّفٌ بلا `print_templates.edit` يرى التصميم والمعاينة وأنواعها، والتعديل مقفل («ليس لديك صلاحيّة»)؛
/// وموظّف شركةٍ لا تُمنح فيها الصلاحيّة (ايرث لنك، فايبر اكس، المُضافة) يرى «يغيّره صاحب الحساب».
/// في «كل الشركات» يعدّل الشركة المفتوحة وحدها (الحفظ لا يُوجَّه) — واسمها تحت العنوان.
class PrintTemplatesScreen extends StatefulWidget {
  const PrintTemplatesScreen({super.key, this.controller, this.preview, this.canRaster});

  /// للاختبار.
  final ReceiptDesignController? controller;
  final ReceiptPreviewController? preview;
  final bool? canRaster;

  @override
  State<PrintTemplatesScreen> createState() => _PrintTemplatesScreenState();
}

/// أعمدة الحاسبة: المعاينة وبجانبها القائمة (والخصائص بجانبها إن اتّسع العرض، وإلّا مكانها).
enum _DeskColumns { none, two, three }

class _PrintTemplatesScreenState extends State<PrintTemplatesScreen> {
  late final ReceiptDesignController _c = widget.controller ?? ReceiptDesignController();
  late final ReceiptPreviewController _p = widget.preview ?? ReceiptPreviewController();
  ReceiptKind _kind = ReceiptKind.activation;
  int _tab = 0;
  bool? _canRaster;
  ({String shop, String? issuer}) _id = (shop: receiptDefaultShopName, issuer: null);
  String? _selected;

  /// عمود القائمة (العناصر/الورق/النصوص) وعمود الخصائص على الحاسبة، وأضيق معاينةٍ تُقرأ بجانبهما.
  static const double _listWidth = 420;
  static const double _inspectorWidth = 380;
  static const double _minPreview = 280;

  /// آخر تخطيطٍ رُسم — النقر على عنصرٍ يفتح خصائصه عموداً فيه، أو ورقةً حين لا أعمدة.
  _DeskColumns _columns = _DeskColumns.none;

  /// التخطيط من عرض الشاشة نفسها لا النافذة: داخل غلاف الحاسبة تأخذ منطقة المحتوى (النافذة − القائمة الجانبيّة ٢٧٢ − ١٦)،
  /// فنافذة ١٠٢٤ تعطي ٧٣٦ — كان القرار بعرض النافذة فتُرسم الأعمدة الثابتة (٤٢٠ + ٣٨٠) وتختفي المعاينة وتفيض.
  /// ثلاثة أعمدة حين تبقى للمعاينة [_minPreview]، وإلّا تحلّ الخصائص محلّ القائمة؛ وأضيق من عمودين = تخطيط الهاتف.
  _DeskColumns _columnsFor(BuildContext context, double width) {
    if (!DesktopLayout.wide(context) || width < _listWidth + 1 + _minPreview) return _DeskColumns.none;
    return width >= _listWidth + _inspectorWidth + 2 + _minPreview ? _DeskColumns.three : _DeskColumns.two;
  }

  @override
  void initState() {
    super.initState();
    _canRaster = widget.canRaster;
    _c.addListener(_changed);
    _c.load();
    ReceiptService.identityFor(null).then((id) {
      if (mounted) setState(() => _id = id);
    }).catchError((Object _) {});
    if (_canRaster == null) {
      receiptCanRaster().then((v) {
        if (mounted) setState(() => _canRaster = v);
      });
    }
  }

  @override
  void dispose() {
    _c.removeListener(_changed);
    if (widget.controller == null) _c.dispose();
    if (widget.preview == null) _p.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// موظّف شركةٍ لا تُمنح فيها صلاحيّة التصميم أصلاً.
  bool get _ownerOnly => !permShown(const ['print_templates.edit']);
  bool get _locked => _ownerOnly || !Perms.has('print_templates.edit');
  String? get _lockMessage => _ownerOnly ? 'تصميم الوصل يغيّره صاحب الحساب' : null;

  /// رسالة القفل (سياق الشاشة فوق [DesignerLockScope]).
  void _deny() => showNoPermission(context, action: true, message: _lockMessage);

  /// QR على وصل الساس وحده — ايرث لنك وفايبر اكس والشركات المُضافة بلا رابطٍ على الوصل.
  bool get _qrAvailable =>
      !(ProviderService.isEarthlink ||
          ActiveCompany.current?.sasCode == 'earthlink' ||
          ProviderService.isFiberx ||
          ProviderService.isKit);

  Map<String, String> _sampleVars() {
    final look = _c.draft;
    final doc = receiptSampleDoc(_kind, look: look, shopName: look.shopName ?? _id.shop, issuer: _id.issuer, qr: false);
    final currency = ReceiptLayout.normalize(look.design?['layout']).currency;
    return receiptVars(receiptInputOf(doc, hasLogo: false), currency);
  }

  // ───────────────────────── الإجراءات ─────────────────────────

  Future<void> _save() async {
    if (_locked) return _deny();
    // وصل الشبكة (٢ نوفمبر): الرجوع للمعتاد وحده يُسأل عنه — الورق والأحجام ومعلومات المحلّ تُحفظ مع الشبكة كما هي
    if (_c.willDropGrid) {
      final go = await showConfirmSheet(
        context,
        title: 'الرجوع للتصميم المعتاد',
        message: 'غيّرت خيارات التصميم المعتاد — الحفظ يرجع وصلك من مصمّم السحب والتحريك (الموقع) للتصميم المعتاد. متابعة؟',
        confirmLabel: 'احفظ بالتصميم المعتاد',
        icon: LucideIcons.layoutGrid,
        tone: AppTone.warning,
      );
      if (go != true || !mounted) return;
    }
    final unknown = receiptLayoutUnknownVars(_c.compactLayout);
    if (unknown.isNotEmpty) {
      final u = unknown.first;
      return showSheetSnack(
        context,
        'متغيّرٌ غير معروف ${u.vars.map((v) => '{$v}').join('، ')} في ${u.path} — اختره من «إدراج متغيّر»',
        isError: true,
      );
    }
    final r = await _c.save();
    if (!mounted) return;
    if (r.ok) {
      HapticFeedback.mediumImpact();
      return showSheetSnack(context, r.message, isError: r.notSaved.isNotEmpty);
    }
    if (r.conflict) {
      final reload = await showConfirmSheet(
        context,
        title: 'تغيّر التصميم',
        message: r.message,
        confirmLabel: 'تحديث (تضيع تعديلاتك)',
        icon: LucideIcons.refreshCw,
        tone: AppTone.warning,
      );
      if (reload == true && mounted) await _c.load();
      return;
    }
    return showSheetSnack(context, r.message, isError: true);
  }

  Future<void> _reset() async {
    if (_locked) return _deny();
    final ok = await showConfirmSheet(
      context,
      title: 'إعادة للافتراضي',
      message: 'يرجع الوصل لشكله الافتراضيّ — الأحجام والمحاذاة والترتيب والنصوص. اسم المحلّ وعنوانه وهاتفه والذيل كما هي، '
          'ولا يُحفظ شيءٌ قبل «حفظ».',
      confirmLabel: 'إعادة',
      icon: LucideIcons.rotateCcw,
      tone: AppTone.warning,
    );
    if (ok == true) _c.resetToDefault();
  }

  /// «اطبع تجربة»: المسوّدة الحاليّة لنوع المعاينة على طابعة الجهاز.
  Future<void> _printSample() async {
    final look = _c.draft;
    final doc = receiptSampleDoc(
      _kind,
      look: look,
      shopName: look.shopName ?? _id.shop,
      issuer: _id.issuer,
      qr: _qrAvailable && look.showQr,
    );
    PrintResult r;
    try {
      final pdf = await ReceiptPdf.build(doc, a4: PrintPrefs.currentTemplateType == 'a4');
      // نافذة الطباعة كما كانت ولو اختيرت «طابعة الوصولات» — المصمّم يجرّب القالب (A4 أو الكاشير) لا الطابعة.
      r = await PrintOutput.send(pdf, receiptPrinter: false);
    } catch (e) {
      r = PrintResult.failed('$e');
    }
    if (mounted) showPrintResult(context, r);
  }

  Future<void> _templates() async {
    if (_locked) return _deny();
    final id = await showAppSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => DesignSheet(
        header: SheetHeaderBar(
          icon: LucideIcons.layoutTemplate,
          title: 'قوالب جاهزة',
          subtitle: 'الورق والحجم والكثافة — الحقول والنصوص كما هي',
          onClose: () => Navigator.of(ctx).pop(),
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final id in receiptTemplateIds)
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.sm),
                child: DesignerChip(label: receiptTemplates[id]!.label, selected: false, onTap: () => Navigator.of(ctx).pop(id)),
              ),
          ],
        ),
      ),
    );
    if (id != null) _c.applyTemplate(id);
  }

  void _open(String id) {
    if (_columns != _DeskColumns.none) {
      setState(() => _selected = id);
      return;
    }
    showElementInspector(
      context,
      controller: _c,
      id: id,
      kind: _kind.name,
      sampleVars: _sampleVars(),
      locked: _locked,
      lockMessage: _lockMessage,
    );
  }

  Future<bool> _confirmLeave() async {
    if (!_c.dirty) return true;
    final ok = await showConfirmSheet(
      context,
      title: 'تعديلاتٌ لم تُحفظ',
      message: 'الخروج الآن يترك تعديلاتك بلا حفظ.',
      confirmLabel: 'خروج بلا حفظ',
      icon: LucideIcons.logOut,
      tone: AppTone.warning,
    );
    return ok == true;
  }

  // ───────────────────────── البناء ─────────────────────────

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return PopScope(
      canPop: !_c.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.of(context).pop();
      },
      child: DesignerLockScope(
        locked: _locked,
        message: _lockMessage,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          appBar: deskPageBar(context, mobile: _appBar()),
          body: _body(),
        ),
      ),
    );
  }

  AppBar _appBar() {
    final merged = MergedMode.active.value ? ActiveCompany.current?.label : null;
    // القفل سطرٌ تحت العنوان (لا شريطٌ زائد): «عرضٌ فقط» أو «يغيّره صاحب الحساب».
    final lockLine = _locked && !_c.loading ? (_lockMessage ?? 'عرضٌ فقط — لا صلاحيّة لتعديل التصميم') : null;
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('تصميم الوصل', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          if (lockLine != null)
            GestureDetector(
              onTap: _deny,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PermLockIcon(size: 11),
                  const SizedBox(width: Sp.xs),
                  Flexible(
                    child: Text(lockLine, style: AppType.muted(), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            )
          else if (!_c.loading && _c.isGrid)
            Text('مصمَّمٌ بالسحب والتحريك من الموقع — يُطبع كما هو هناك',
                style: AppType.muted(), maxLines: 1, overflow: TextOverflow.ellipsis)
          else if (merged != null && merged.isNotEmpty)
            Text('لشركة $merged', style: AppType.muted(), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
      iconTheme: IconThemeData(color: AppColors.textHi),
      actions: [
        if (!_c.loading && _c.loadError == null) ...[
          IconButton(
            tooltip: 'تراجع',
            icon: Icon(LucideIcons.undo2, size: 18, color: _c.canUndo && !_locked ? AppColors.textHi : AppColors.textHint),
            onPressed: _c.canUndo && !_locked ? _c.undo : null,
          ),
          if (_locked)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
              child: InkWell(
                onTap: _deny,
                child: PermLockBadge(child: Icon(LucideIcons.save, size: 18, color: AppColors.textLow)),
              ),
            )
          else if (_c.dirty || _c.saving)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: Sp.xs),
              child: TextButton(
                onPressed: _c.saving ? null : _save,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.onBrand,
                  minimumSize: const Size(0, H.chipSm),
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.sm)),
                ),
                child: _c.saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand),
                      )
                    : Text('حفظ', style: AppType.bodyStrong(color: AppColors.onBrand)),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'المزيد',
            icon: Icon(LucideIcons.ellipsisVertical, size: 18, color: AppColors.textHi),
            color: AppColors.surface,
            onSelected: (v) => switch (v) {
              'reset' => _reset(),
              'print' => _printSample(),
              'templates' => _templates(),
              'issuer' => _locked ? _deny() : showIssuerNamesSheet(context),
              _ => null,
            },
            itemBuilder: (_) => [
              _menuItem('templates', LucideIcons.layoutTemplate, 'قوالب جاهزة'),
              _menuItem('print', LucideIcons.printer, 'اطبع تجربة'),
              // «أصدره» باسمٍ عربيّ للمدير وموظّفيه (٢ نوفمبر — طلب المالك)
              _menuItem('issuer', LucideIcons.signature, 'اسم «أصدره» على الوصل'),
              _menuItem('reset', LucideIcons.rotateCcw, 'إعادة للافتراضي'),
            ],
          ),
        ],
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String v, IconData icon, String label) => PopupMenuItem(
        value: v,
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textMid),
            const SizedBox(width: Sp.sm),
            Text(label, style: AppType.body(color: AppColors.textHi)),
          ],
        ),
      );

  Widget _body() {
    if (_c.loading) return const Center(child: CircularProgressIndicator());
    if (_c.loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.cloudOff, size: 28, color: AppColors.textLow),
              const SizedBox(height: Sp.sm),
              Text(_c.loadError!, textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
              const SizedBox(height: Sp.md),
              TextButton.icon(
                onPressed: _c.load,
                icon: Icon(LucideIcons.refreshCw, size: 16, color: AppColors.brand),
                label: Text('إعادة المحاولة', style: AppType.bodyStrong(color: AppColors.brand)),
              ),
            ],
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final columns = _columns = _columnsFor(context, box.maxWidth);
        final preview = PreviewPane(
          controller: _c,
          preview: _p,
          kind: _kind,
          onKind: (k) => setState(() => _kind = k),
          shopName: _id.shop,
          issuer: _id.issuer,
          qrAvailable: _qrAvailable,
          canRaster: _canRaster ?? true,
          onPrintSample: _printSample,
        );
        final tabs = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.xs),
              child: SheetSegmented(
                labels: const ['العناصر', 'الورق والخطّ', 'النصوص'],
                selectedIndex: _tab,
                onSelect: (i) => setState(() => _tab = i),
              ),
            ),
            Expanded(child: _tabBody(inline: columns != _DeskColumns.none)),
          ],
        );
        if (columns == _DeskColumns.none) {
          return Column(
            children: [
              SizedBox(height: (box.maxHeight * 0.42).clamp(200.0, 520.0), child: preview),
              Divider(height: 1, color: AppColors.border),
              Expanded(child: tabs),
            ],
          );
        }
        // الحاسبة: المعاينة والقائمة جنباً إلى جنب، والخصائص عمودٌ ثالث بدل الورقة — أو مكان القائمة حين لا يتّسع العرض
        // (القائمة باقيةٌ خلفها بموضع تمريرها، والمعاينة لا تضيق).
        final sel = _tab == 0 ? _selected : null;
        final three = columns == _DeskColumns.three;
        return Row(
          children: [
            Expanded(child: preview),
            VerticalDivider(width: 1, color: AppColors.border),
            SizedBox(
              width: _listWidth,
              child: IndexedStack(
                index: !three && sel != null ? 1 : 0,
                sizing: StackFit.expand,
                children: [
                  tabs,
                  if (!three && sel != null) _inspectorColumn(sel, replacesList: true) else const SizedBox.shrink(),
                ],
              ),
            ),
            if (three && sel != null) ...[
              VerticalDivider(width: 1, color: AppColors.border),
              SizedBox(width: _inspectorWidth, child: _inspectorColumn(sel)),
            ],
          ],
        );
      },
    );
  }

  /// خصائص العنصر عموداً على الحاسبة (بدل الورقة): اسمه وزرّ إغلاقه — وحين تحلّ محلّ القائمة يعيدها الزرّ.
  Widget _inspectorColumn(String id, {bool replacesList = false}) => Column(
        children: [
          ListTile(
            title: Text(
              designerElementNames[id] ?? id,
              style: AppType.bodyStrong(color: AppColors.textHi),
            ),
            trailing: IconButton(
              tooltip: replacesList ? 'رجوع للعناصر' : 'إغلاق',
              icon: Icon(LucideIcons.x, size: 18, color: AppColors.textMid),
              onPressed: () => setState(() => _selected = null),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Sp.lg),
              child: ElementInspector(controller: _c, id: id, kind: _kind.name, sampleVars: _sampleVars()),
            ),
          ),
        ],
      );

  Widget _tabBody({required bool inline}) => switch (_tab) {
        1 => PaperTab(controller: _c, qrAvailable: _qrAvailable),
        2 => TextsTab(controller: _c, kind: _kind.name, sampleVars: _sampleVars()),
        _ => ElementsTab(
            controller: _c,
            kind: _kind.name,
            qrAvailable: _qrAvailable,
            onOpen: _open,
            selected: inline ? _selected : null,
          ),
      };
}
