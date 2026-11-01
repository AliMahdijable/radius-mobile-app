import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../services/receipt_layout.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'controls.dart';
import 'designer_controller.dart';
import 'var_picker_sheet.dart';

/// «الورق والخطّ» (spec §4.4): القوالب، و«حجم الوصل»، والورق (٥٨ / ٨٠ / مخصّص / A4)، والهوامش، وحجم الخطّ العامّ، والشعار
/// ورمز QR، والعملة، و«أسود فقط»، وفاصل الصفوف، وخطّ عناوين الأقسام، والطباعة التلقائيّة. نوع الخطّ وارتفاع السطر
/// والألوان والرموز لا يرسمها التطبيق في المرحلة ١ — فلا تُعرض هنا (الموقع يعدّلها).
class PaperTab extends StatelessWidget {
  const PaperTab({super.key, required this.controller, required this.qrAvailable});

  final ReceiptDesignController controller;
  final bool qrAvailable;

  ReceiptDesignController get c => controller;

  num _v1(String k) {
    final v = c.design[k];
    return v is num ? v : receiptV1AllDefaults[k]! as num;
  }

  String _s1(String k) {
    final v = c.design[k];
    return v is String ? v : receiptV1AllDefaults[k]! as String;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final draft = c.draft;
    final a4 = c.paperSize == 'a4';
    final width = _v1('paper_width_mm');
    final paper = a4 ? 'a4' : (width == 58 ? '58' : (width == 80 ? '80' : 'custom'));
    final pinned = c.pinnedCount;
    final l = c.layout ?? const <String, dynamic>{};
    final margins = ['margin_top_mm', 'margin_right_mm', 'margin_bottom_mm', 'margin_left_mm'].map(_v1).toSet();
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.huge),
      children: [
        DesignerCard(
          title: 'قوالب جاهزة',
          icon: LucideIcons.layoutTemplate,
          children: [
            DesignerField(
              label: 'تغيّر الورق والحجم والكثافة وحدها — الحقول والنصوص كما هي',
              child: Wrap(
                spacing: Sp.x6,
                runSpacing: Sp.x6,
                children: [
                  for (final id in receiptTemplateIds)
                    DesignerChip(
                      label: receiptTemplates[id]!.label,
                      selected: false,
                      onTap: () => c.applyTemplate(id),
                    ),
                ],
              ),
            ),
            if (pinned > 0)
              DesignerField(
                label: '${_pinnedPhrase(pinned)} — لا تتغيّر بالقوالب ولا بحجم الخطّ',
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DesignerChip(label: 'إرجاعها للتلقائي', selected: false, onTap: c.unpinAll),
                ),
              ),
          ],
        ),
        DesignerCard(
          title: 'الورق والحجم',
          icon: LucideIcons.scroll,
          children: [
            DesignerField(
              label: 'حجم الوصل',
              hint: draft.preset == null ? 'مخصّص — لا يطابق واحداً من الثلاثة' : null,
              child: DesignerChoice<String>(
                values: receiptDensities,
                labels: {for (final e in receiptPresets.entries) e.key: e.value.label},
                value: draft.preset,
                onChanged: (v) {
                  if (v != null) c.applyPreset(v);
                },
              ),
            ),
            DesignerField(
              label: 'الورق',
              hint: 'الطابعة تطبع بإعداد «الطابعة الافتراضية» في الجهاز',
              child: DesignerChoice<String>(
                values: const ['58', '80', 'custom', 'a4'],
                labels: const {'58': '58 ملم', '80': '80 ملم', 'custom': 'مخصّص', 'a4': 'A4'},
                value: paper,
                onChanged: (v) => switch (v) {
                  '58' => c.setPaper('pos', widthMm: 58),
                  '80' => c.setPaper('pos', widthMm: 80),
                  'a4' => c.setPaper('a4'),
                  _ => c.setPaper('pos', widthMm: width == 58 || width == 80 ? 72 : width),
                },
              ),
            ),
            if (paper == 'custom')
              DesignerField(
                label: 'عرض الورق',
                child: MmStepper(
                  value: width,
                  min: 50,
                  max: 120,
                  step: 1,
                  onChanged: (v) => c.setPaper('pos', widthMm: v),
                ),
              ),
            if (!a4)
              DesignerField(
                label: 'الهوامش',
                hint: margins.length > 1 ? 'الهوامش الأربع غير متساوية — التعديل يوحّدها' : null,
                child: MmStepper(
                  value: _v1('margin_top_mm'),
                  min: 0,
                  max: 30,
                  step: 1,
                  onChanged: c.setMargins,
                ),
              ),
            DesignerField(
              label: 'حجم الخطّ العامّ',
              hint: 'العناصر المثبّتة بالنقطة لا تتغيّر',
              child: DesignerStepper(
                text: '${c.fontPct}٪',
                onMinus: c.fontPct <= 80 ? null : () => c.setFontPct(c.fontPct - 5),
                onPlus: c.fontPct >= 130 ? null : () => c.setFontPct(c.fontPct + 5),
              ),
            ),
          ],
        ),
        DesignerCard(
          title: qrAvailable ? 'الشعار ورمز QR' : 'الشعار',
          icon: LucideIcons.image,
          children: [
            Row(
              children: [
                Expanded(
                  child: DesignerField(
                    label: 'ارتفاع الشعار',
                    child: MmStepper(
                      value: _v1('logo_size_mm'),
                      min: 8,
                      max: 50,
                      step: 1,
                      onChanged: (v) => c.setV1('logo_size_mm', v),
                    ),
                  ),
                ),
              ],
            ),
            DesignerField(
              label: 'محاذاة الشعار',
              child: DesignerChoice<String>(
                values: receiptHAligns,
                labels: designerAlignLabels,
                value: _s1('logo_align'),
                onChanged: (v) => c.setV1('logo_align', v ?? 'center'),
              ),
            ),
            if (qrAvailable) ...[
              DesignerField(
                label: 'حجم رمز QR',
                child: MmStepper(
                  value: _v1('qr_size_mm'),
                  min: 15,
                  max: 60,
                  step: 1,
                  onChanged: (v) => c.setV1('qr_size_mm', v),
                ),
              ),
              DesignerField(
                label: 'محاذاة رمز QR',
                child: DesignerChoice<String>(
                  values: receiptHAligns,
                  labels: designerAlignLabels,
                  value: _s1('qr_align'),
                  onChanged: (v) => c.setV1('qr_align', v ?? 'center'),
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.md),
                child: Text('رمز QR غير متاح لهذه الشركة — لا يُطبع على وصلها', style: AppType.muted()),
              ),
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.md),
              child: Text('الشعار يُرفع من الموقع («قوالب الطباعة»).', style: AppType.muted()),
            ),
          ],
        ),
        DesignerCard(
          title: 'الشكل',
          icon: LucideIcons.paintbrush,
          children: [
            DesignerField(label: 'العملة', child: _CurrencyPicker(controller: c)),
            DesignerSwitchRow(
              label: 'أسود فقط (توفير الحبر)',
              hint: 'لوصل A4 — الكاشير يُطبع بالأسود دائماً',
              value: l['mono'] == true,
              onChanged: (v) => c.setLayoutKey('mono', v ? true : null),
            ),
            const SizedBox(height: Sp.sm),
            DesignerField(
              label: 'فاصل الصفوف',
              child: DesignerChoice<String>(
                values: receiptSeps,
                labels: designerSepLabels,
                value: _s1('row_separator'),
                onChanged: (v) => c.setV1('row_separator', v ?? 'dotted'),
              ),
            ),
            DesignerSwitchRow(
              label: 'خطّ تحت عناوين الأقسام',
              value: c.design['section_title_underline'] != false,
              onChanged: (v) => c.setV1('section_title_underline', v),
            ),
            const SizedBox(height: Sp.sm),
          ],
        ),
        DesignerCard(
          title: 'الطباعة',
          icon: LucideIcons.printer,
          children: [
            DesignerSwitchRow(
              label: 'طباعة الوصل تلقائياً',
              hint: 'خانة «طباعة وصل» تأتي معلَّمة بعد التفعيل والتمديد والتسديد',
              value: c.autoPrint,
              onChanged: (v) => c.setColumn('auto_print', v),
            ),
            const SizedBox(height: Sp.sm),
          ],
        ),
        Text(
          'الخطّ والطول قد يختلفان قليلاً عن الموقع. نوع الخطّ وارتفاع السطر والألوان من الموقع.',
          style: AppType.muted(color: AppColors.textLow),
        ),
      ],
    );
  }
}

/// «العملة»: د.ع / دينار / IQD / بلا / مخصّص (≤ ٨ أحرف) — `layout.currency` ('' = بلا وحدة، «د.ع» = الافتراضيّ فلا يُحفظ).
class _CurrencyPicker extends StatefulWidget {
  const _CurrencyPicker({required this.controller});
  final ReceiptDesignController controller;

  @override
  State<_CurrencyPicker> createState() => _CurrencyPickerState();
}

class _CurrencyPickerState extends State<_CurrencyPicker> {
  static const _presets = {'د.ع': 'د.ع', 'دينار': 'دينار', 'IQD': 'IQD', '': 'بلا'};
  bool _custom = false;

  String get _currency {
    final cur = widget.controller.layout?['currency'];
    return cur is String ? cur.trim() : receiptDefaultCurrency;
  }

  @override
  void initState() {
    super.initState();
    _custom = !_presets.containsKey(_currency);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final cur = _currency;
    final custom = _custom || !_presets.containsKey(cur);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesignerChoice<String>(
          values: const ['د.ع', 'دينار', 'IQD', '', 'custom'],
          labels: const {..._presets, 'custom': 'مخصّص'},
          value: custom ? 'custom' : cur,
          onChanged: (v) {
            if (v == null) return;
            if (v == 'custom') {
              setState(() => _custom = true);
              return;
            }
            setState(() => _custom = false);
            c.setLayoutKey('currency', v == receiptDefaultCurrency ? null : v);
          },
        ),
        if (custom) ...[
          const SizedBox(height: Sp.x6),
          TemplatedInput(
            value: _presets.containsKey(cur) ? '' : cur,
            hint: 'مثل: \$ أو ألف',
            maxLength: receiptLimits3['currency']!.toInt(),
            vars: false,
            kind: 'activation',
            sampleVars: const {},
            onChanged: (v) => c.setLayoutKey('currency', v.trim(), typing: true),
          ),
        ],
      ],
    );
  }
}

/// «عنصرٌ واحد / عنصران / 3 عناصر / 11 عنصراً بحجمٍ مثبّت».
String _pinnedPhrase(int n) => switch (n) {
      1 => 'عنصرٌ واحد بحجمٍ مثبّت',
      2 => 'عنصران بحجمٍ مثبّت',
      <= 10 => '$n عناصر بحجمٍ مثبّت',
      _ => '$n عنصراً بحجمٍ مثبّت',
    };
