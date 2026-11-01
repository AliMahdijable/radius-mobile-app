import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../services/receipt_layout.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'controls.dart';
import 'designer_controller.dart';
import 'var_picker_sheet.dart';

/// «النصوص»: حتى ستّة نصوص بمتغيّرات في عشرة أماكن — المكان والمحاذاة والحجم والعرض والإطار و«يظهر في» والمسافات والخطّ.
class TextsTab extends StatelessWidget {
  const TextsTab({super.key, required this.controller, required this.kind, required this.sampleVars});

  final ReceiptDesignController controller;
  final String kind;
  final Map<String, String> sampleVars;

  ReceiptDesignController get c => controller;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final texts = c.texts;
    final max = receiptLimits3['texts']!.toInt();
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge),
      children: [
        for (var i = 0; i < texts.length; i++)
          _TextCard(controller: c, index: i, text: texts[i], kind: kind, sampleVars: sampleVars),
        if (texts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.lg),
            child: Text(
              'نصٌّ ثابت أو بمتغيّرات يُطبع في مكانٍ تختاره — مثل «سدّد قبل {expiry_date}» في وصل التسديد وحده.',
              textAlign: TextAlign.center,
              style: AppType.body(color: AppColors.textMid),
            ),
          ),
        DesignerGate(
          child: OutlinedButton.icon(
            onPressed: texts.length >= max ? null : c.addText,
            icon: Icon(LucideIcons.plus, size: 16, color: texts.length >= max ? AppColors.textHint : AppColors.brand),
            label: Text(
              texts.length >= max ? 'الحدّ ستّة نصوص' : 'إضافة نصّ',
              style: AppType.bodyStrong(color: texts.length >= max ? AppColors.textHint : AppColors.brand),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(H.chip),
              side: BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
            ),
          ),
        ),
      ],
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({
    required this.controller,
    required this.index,
    required this.text,
    required this.kind,
    required this.sampleVars,
  });

  final ReceiptDesignController controller;
  final int index;
  final Map<String, dynamic> text;
  final String kind;
  final Map<String, String> sampleVars;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = controller;
    final i = index;
    final t = text;
    final at = receiptTextPos3Ids.contains(t['at']) ? t['at'] as String : 'bottom';
    final pinned = t['pt'] is num ? t['pt'] as num : null;
    final auto = receiptUiPt(c.design, c.layout, text: i).pt;
    num gap(String k) => t[k] is num ? t[k] as num : 0;
    return DesignerCard(
      title: 'نصّ ${i + 1}',
      icon: LucideIcons.textCursor,
      children: [
        DesignerField(
          label: 'النصّ',
          trailing: InkWell(
            onTap: () => c.removeText(i),
            child: Padding(
              padding: const EdgeInsets.all(Sp.xxs),
              child: Icon(LucideIcons.trash2, size: 16, color: AppColors.error),
            ),
          ),
          child: TemplatedInput(
            value: t['text'] is String ? t['text'] as String : '',
            hint: 'مثل: سدّد قبل {expiry_date}',
            maxLength: receiptLimits3['text']!.toInt(),
            maxLines: 4,
            kind: kind,
            sampleVars: sampleVars,
            onChanged: (v) => c.setText(i, {'text': v}, typing: true),
          ),
        ),
        DesignerField(
          label: 'المكان',
          child: _PositionSelect(value: at, onChanged: (v) => c.setText(i, {'at': v})),
        ),
        DesignerField(
          label: 'المحاذاة',
          child: DesignerChoice<String>(
            values: receiptHAligns,
            labels: designerAlignLabels,
            value: receiptHAligns.contains(t['align']) ? t['align'] as String : 'center',
            onChanged: (v) => c.setText(i, {'align': v == null || v == 'center' ? null : v}),
          ),
        ),
        DesignerField(
          label: 'الحجم (نقطة)',
          child: PtStepper(
            pinned: pinned,
            autoPt: auto,
            onChanged: (v) => c.setText(i, v == null ? {'pt': null} : {'pt': v, 'size': null}),
          ),
        ),
        DesignerField(
          label: 'الشكل',
          child: Wrap(
            spacing: Sp.x6,
            children: [
              DesignerChip(
                label: 'عريض',
                selected: t['bold'] == true,
                onTap: () => c.setText(i, {'bold': t['bold'] == true ? null : true}),
              ),
              DesignerChip(
                label: 'داخل إطار',
                selected: t['boxed'] == true,
                onTap: () => c.setText(i, {'boxed': t['boxed'] == true ? null : true}),
              ),
            ],
          ),
        ),
        DesignerField(
          label: 'يظهر في',
          child: KindChips(only: receiptOnly(t['only']), onChanged: (v) => c.setText(i, {'only': v})),
        ),
        Row(
          children: [
            Expanded(
              child: DesignerField(
                label: 'مسافة قبل',
                child: MmStepper(value: gap('gap_before'), onChanged: (v) => c.setText(i, {'gap_before': v == 0 ? null : v})),
              ),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: DesignerField(
                label: 'مسافة بعد',
                child: MmStepper(value: gap('gap_after'), onChanged: (v) => c.setText(i, {'gap_after': v == 0 ? null : v})),
              ),
            ),
          ],
        ),
        DesignerField(
          label: 'خطّ تحته',
          child: DesignerChoice<String>(
            values: receiptSeps,
            labels: designerSepLabels,
            value: receiptSeps.contains(t['sep']) ? t['sep'] as String : null,
            autoLabel: 'بلا تحديد',
            onChanged: (v) => c.setText(i, {'sep': v}),
          ),
        ),
      ],
    );
  }
}

/// المكان من عشرة (اسمه بالعربيّ) — قائمةٌ منسدلة.
class _PositionSelect extends StatelessWidget {
  const _PositionSelect({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: AppColors.surface,
          style: AppType.input(),
          items: [
            for (final p in receiptTextPos3) DropdownMenuItem(value: p.id, child: Text(p.label, style: AppType.input())),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
