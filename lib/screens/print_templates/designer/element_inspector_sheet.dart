import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/app_sheet.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../services/receipt_layout.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'controls.dart';
import 'designer_controller.dart';
import 'designer_elements.dart';
import 'var_picker_sheet.dart';

/// يفتح «خصائص العنصر» ورقةً لا تتجاوز ٥٥٪ من الشاشة، بحاجزٍ خفيف — المعاينة فوقها تبقى ظاهرة وتتحدّث.
Future<void> showElementInspector(
  BuildContext context, {
  required ReceiptDesignController controller,
  required String id,
  required String kind,
  required Map<String, String> sampleVars,
  required bool locked,
  String? lockMessage,
}) =>
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim.withValues(alpha: 0.12),
      builder: (ctx) => DesignerLockScope(
        locked: locked,
        message: lockMessage,
        child: ListenableBuilder(
          listenable: controller,
          builder: (ctx, _) => DesignSheet(
            maxHeightFactor: 0.55,
            header: SheetHeaderBar(
              icon: _iconOf(id),
              title: designerElementNames[id] ?? id,
              subtitle: controller.dimReason(id, kind) ?? controller.summary(id),
              onClose: () => Navigator.of(ctx).pop(),
            ),
            body: ElementInspector(controller: controller, id: id, kind: kind, sampleVars: sampleVars),
          ),
        ),
      ),
    );

IconData _iconOf(String id) => switch (id) {
      'logo' => LucideIcons.image,
      'qr' || 'qr_caption' => LucideIcons.qrCode,
      'shop_name' || 'title' => LucideIcons.heading,
      'meta' || 'receipt_no' || 'issued_at' => LucideIcons.hash,
      'footer' || 'footer_text' || 'issuer' => LucideIcons.alignJustify,
      _ when receiptSectionCaps.containsKey(id) => LucideIcons.rows3,
      _ => LucideIcons.type,
    };

/// أعمدة الصفّ التي تحمل نصّ العنصر (تُطبع كما كُتبت — بلا متغيّرات).
const Map<String, ({String col, int max, String hint, int lines})> _textColumns = {
  'shop_name': (col: 'shop_name', max: 255, hint: 'اسم المحلّ كما يُطبع', lines: 1),
  'shop_address': (col: 'shop_address', max: 500, hint: 'العنوان', lines: 2),
  'shop_phone': (col: 'shop_phone', max: 50, hint: '0780 000 0000', lines: 1),
  'footer_text': (col: 'footer_text', max: 1000, hint: 'شكراً لاختياركم خدماتنا', lines: 3),
};

/// خصائص العنصر (spec §3.4/§4.4): لا يُعرض إلّا ما يملكه العنصر ([receiptCapsOf]) — في الورقة على الهاتف، وفي عمودٍ على
/// الحاسبة.
class ElementInspector extends StatelessWidget {
  const ElementInspector({
    super.key,
    required this.controller,
    required this.id,
    required this.kind,
    required this.sampleVars,
  });

  final ReceiptDesignController controller;
  final String id;
  final String kind;
  final Map<String, String> sampleVars;

  ReceiptDesignController get c => controller;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final caps = receiptCapsOf(id);
    final st = c.styleOf(id);
    final def = receiptFieldDefs[id];
    final isSection = receiptSectionCaps.containsKey(id);
    final shown = c.shown(id);
    final children = <Widget>[];

    // ── الظهور
    if (shown != null) {
      children.add(DesignerSwitchRow(
        label: isSection ? 'يظهر القسم' : 'يظهر في الوصل',
        value: shown,
        onChanged: (v) => c.setShown(id, v),
      ));
      if (!shown && id == 'balance_debt') {
        children.add(const _Warning(text: 'الوصل لن يذكر دين المشترك'));
      }
      children.add(const SizedBox(height: Sp.sm));
    }

    // ── نصّ العنصر
    final col = _textColumns[id];
    if (col != null) {
      children.add(DesignerField(
        label: id == 'footer_text' ? 'نصّ الذيل' : 'النصّ',
        hint: 'يُطبع كما هو — بلا متغيّرات',
        child: TemplatedInput(
          value: (c.column(col.col) as String?) ?? '',
          hint: col.hint,
          maxLength: col.max,
          maxLines: col.lines,
          vars: false,
          ltr: id == 'shop_phone',
          kind: kind,
          sampleVars: sampleVars,
          onChanged: (v) => c.setColumn(col.col, v, typing: true),
        ),
      ));
    }
    if (id == 'title') {
      final t = c.layout?['titles'];
      final cur = t is Map && t[kind] is String ? t[kind] as String : '';
      children.add(DesignerField(
        label: 'عنوان ${designerKindPhrase[kind]}',
        hint: 'فارغ = «${receiptDefaultTitles[kind]}»',
        child: TemplatedInput(
          value: cur,
          hint: receiptDefaultTitles[kind],
          maxLength: receiptLimits3['typeTitle']!.toInt(),
          kind: kind,
          sampleVars: sampleVars,
          onChanged: (v) => c.setTitle(kind, v, typing: true),
        ),
      ));
    }

    // ── التسمية / تعليق الرمز («القيمة فقط» تُطبع بلا تسمية — فلا حقل لها)
    if (caps.contains('label') && def != null && st['row_mode'] != 'value') {
      final label = st['label'];
      final none = label is String && label.trim().isEmpty;
      final caption = id == 'qr_caption';
      children.add(DesignerField(
        label: caption ? 'نصّ التعليق' : 'التسمية',
        trailing: caption
            ? null
            : DesignerChip(
                label: 'بلا تسمية',
                selected: none,
                onTap: () => c.setField(id, {'label': none ? null : ''}),
              ),
        child: none
            ? Text('تُطبع القيمة وحدها', style: AppType.muted(color: AppColors.textMid))
            : TemplatedInput(
                value: label is String ? label : '',
                hint: def.label.isEmpty ? 'بلا تسمية' : def.label,
                maxLength: receiptLimits3['label']!.toInt(),
                kind: kind,
                sampleVars: sampleVars,
                onChanged: (v) => c.setField(id, {'label': v.isEmpty ? null : v}, typing: true),
              ),
      ));
    }

    // ── عنوان القسم
    if (isSection) {
      final title = st['title'];
      children.add(DesignerField(
        label: 'عنوان القسم',
        trailing: DesignerChip(
          label: 'بلا عنوان',
          selected: st['show_title'] == false,
          onTap: () => c.setSection(id, {'show_title': st['show_title'] == false ? null : false}),
        ),
        child: st['show_title'] == false
            ? Text('القسم يُطبع بلا عنوان', style: AppType.muted(color: AppColors.textMid))
            : TemplatedInput(
                value: title is String ? title : '',
                hint: (receiptSectionTitles[id] ?? '').isEmpty ? 'بلا عنوان' : receiptSectionTitles[id],
                maxLength: receiptLimits3['sectionTitle']!.toInt(),
                kind: kind,
                sampleVars: sampleVars,
                onChanged: (v) => c.setSection(id, {'title': v.isEmpty ? null : v}, typing: true),
              ),
      ));
    }

    // ── الحجم
    if (caps.contains('pt')) {
      final pinned = st['pt'] is num ? st['pt'] as num : null;
      final auto = (isSection ? receiptUiPt(c.design, c.layout, section: id) : receiptUiPt(c.design, c.layout, field: id)).pt;
      children.add(DesignerField(
        label: isSection ? 'حجم عنوان القسم' : 'الحجم (نقطة)',
        hint: pinned != null ? 'مثبّت: لا يتغيّر بحجم الخطّ العامّ ولا بالقوالب' : null,
        // التثبيت يُسقط الحجم النسبيّ (لا أثر له مع pt)، و«تلقائي» يُبقيه.
        child: PtStepper(
          pinned: pinned,
          autoPt: auto,
          onChanged: (v) => c.setStyle(id, v == null ? {'pt': null} : {'pt': v, 'size': null}),
        ),
      ));
    }
    if (caps.contains('bold') && def != null) {
      final bold = st['bold'] is bool ? st['bold'] as bool : def.bold;
      children.add(DesignerSwitchRow(
        label: 'عريض',
        value: bold,
        onChanged: (v) => c.setField(id, {'bold': v == def.bold ? null : v}),
      ));
      children.add(const SizedBox(height: Sp.sm));
    }

    // ── المحاذاة وشكل السطر
    if (caps.contains('align')) {
      children.add(DesignerField(
        label: isSection ? 'محاذاة العنوان' : 'المحاذاة',
        child: DesignerChoice<String>(
          values: receiptHAligns,
          labels: designerAlignLabels,
          value: st['align'] is String ? st['align'] as String : null,
          autoLabel: 'تلقائي',
          onChanged: (v) => c.setStyle(id, {'align': v}),
        ),
      ));
    }
    if (caps.contains('row_mode')) {
      final m = st['row_mode'];
      children.add(DesignerField(
        label: 'شكل السطر',
        child: DesignerChoice<String>(
          values: receiptRowModes,
          labels: designerRowModeLabels,
          value: m is String && receiptRowModes.contains(m) ? m : 'line',
          onChanged: (v) => c.setStyle(id, {'row_mode': v == null || v == 'line' ? null : v}),
        ),
      ));
    }

    // ── الشعار ورمز QR: الحجم والمحاذاة من مفاتيح v1
    if (id == 'logo' || id == 'qr') {
      final sizeKey = id == 'logo' ? 'logo_size_mm' : 'qr_size_mm';
      final alignKey = id == 'logo' ? 'logo_align' : 'qr_align';
      final lo = id == 'logo' ? 8 : 15;
      final hi = id == 'logo' ? 50 : 60;
      final v = c.design[sizeKey];
      final size = v is num ? v : receiptV1AllDefaults[sizeKey]! as num;
      children.add(DesignerField(
        label: id == 'logo' ? 'ارتفاع الشعار' : 'حجم الرمز',
        child: MmStepper(value: size, min: lo, max: hi, step: 1, onChanged: (n) => c.setV1(sizeKey, n)),
      ));
      final a = c.design[alignKey];
      children.add(DesignerField(
        label: 'المحاذاة',
        child: DesignerChoice<String>(
          values: receiptHAligns,
          labels: designerAlignLabels,
          value: a is String && receiptHAligns.contains(a) ? a : 'center',
          onChanged: (x) => c.setV1(alignKey, x ?? 'center'),
        ),
      ));
    }

    // ── المسافات والخطّ
    if (caps.contains('gap_before') || caps.contains('gap_after')) {
      num gap(String k) => st[k] is num ? st[k] as num : 0;
      children.add(Row(
        children: [
          if (caps.contains('gap_before'))
            Expanded(
              child: DesignerField(
                label: 'مسافة قبل',
                child: MmStepper(value: gap('gap_before'), onChanged: (v) => c.setStyle(id, {'gap_before': v == 0 ? null : v})),
              ),
            ),
          if (caps.contains('gap_before') && caps.contains('gap_after')) const SizedBox(width: Sp.md),
          if (caps.contains('gap_after'))
            Expanded(
              child: DesignerField(
                label: 'مسافة بعد',
                child: MmStepper(value: gap('gap_after'), onChanged: (v) => c.setStyle(id, {'gap_after': v == 0 ? null : v})),
              ),
            ),
        ],
      ));
    }
    if (caps.contains('sep')) {
      children.add(DesignerField(
        label: id == 'meta' ? 'الخطّ تحت الرقم والتاريخ' : 'خطّ تحته',
        child: DesignerChoice<String>(
          values: receiptSeps,
          labels: designerSepLabels,
          value: st['sep'] is String ? st['sep'] as String : null,
          autoLabel: 'تلقائي',
          onChanged: (v) => c.setStyle(id, {'sep': v}),
        ),
      ));
    }

    // ── يظهر في
    if (caps.contains('only')) {
      final kinds = receiptFieldDefs[id]?.kinds ??
          (id == 'qr' || receiptBodySections.contains(id) ? const ['activation', 'extension', 'payment', 'info'] : receiptKinds);
      if (kinds.length > 1) {
        children.add(DesignerField(
          label: 'يظهر في',
          hint: 'إخفاؤه من نوعٍ لا يغيّر غيره',
          child: KindChips(
            only: receiptOnly(st['only']),
            kinds: kinds,
            onChanged: (v) => c.setStyle(id, {'only': v}),
          ),
        ));
      }
    }

    // ── الترتيب
    final movable = receiptRowFieldIds.contains(id) || receiptBodySections.contains(id) || receiptBlockIds.contains(id);
    if (movable) {
      children.add(DesignerField(
        label: 'الترتيب',
        child: Row(
          children: [
            Expanded(
              child: _MoveButton(icon: LucideIcons.arrowUp, label: 'للأعلى', onTap: () => c.move(id, -1)),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: _MoveButton(icon: LucideIcons.arrowDown, label: 'للأسفل', onTap: () => c.move(id, 1)),
            ),
          ],
        ),
      ));
    }
    if (children.isEmpty) {
      children.add(Text('لا خيارات لهذا العنصر', style: AppType.muted()));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _MoveButton extends StatelessWidget {
  const _MoveButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: SizedBox(
          height: H.chipSm,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: AppColors.textHi),
              const SizedBox(width: Sp.xs),
              Text(label, style: AppType.bodyStrong(color: AppColors.textHi)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      margin: const EdgeInsets.only(top: Sp.xs),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.warningSoftBg,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.warningSoftBorder),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.triangleAlert, size: 14, color: AppColors.warningOnSoft),
          const SizedBox(width: Sp.x6),
          Expanded(
            child: Text(text, style: AppType.bodyStrong(color: AppColors.warningOnSoft), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}
