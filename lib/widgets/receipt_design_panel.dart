import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/app_theme.dart';
import '../models/print_template_model.dart';

/// أقسام التصميم — يستعملها الـeditor كـtabs على غرار الويب.
enum DesignSection { paper, fonts, layout, colors, sections }

const Map<DesignSection, ({IconData icon, String label})> kDesignSectionMeta = {
  DesignSection.paper:    (icon: LucideIcons.fileText,       label: 'الورق'),
  DesignSection.fonts:    (icon: LucideIcons.type,           label: 'الخطوط'),
  DesignSection.layout:   (icon: LucideIcons.layoutDashboard, label: 'التخطيط'),
  DesignSection.colors:   (icon: LucideIcons.palette,        label: 'الألوان'),
  DesignSection.sections: (icon: LucideIcons.eye,            label: 'الأقسام'),
};

/// لوحة تحرير قسم واحد من ReceiptDesign — تُستخدم داخل tabs الـeditor.
/// السلوك مرآة لـclient-v2/PrintTemplates.tsx مع الفصل بين الأقسام.
///
/// مهم: كل تعديل يُنتج كائن ReceiptDesign **جديد** (عبر [_update]) ولا يُعدِّل
/// المرجع الوارد — هذا ضروري كي يكتشف `LiveReceiptPreview.didUpdateWidget`
/// التغيير ويعيد رسم المعاينة لحظياً.
class ReceiptDesignSectionPanel extends StatefulWidget {
  final DesignSection section;
  final ReceiptDesign value;
  final ValueChanged<ReceiptDesign> onChanged;
  final String templateType; // 'pos' | 'a4'

  const ReceiptDesignSectionPanel({
    super.key,
    required this.section,
    required this.value,
    required this.onChanged,
    required this.templateType,
  });

  @override
  State<ReceiptDesignSectionPanel> createState() =>
      _ReceiptDesignSectionPanelState();
}

class _ReceiptDesignSectionPanelState extends State<ReceiptDesignSectionPanel> {
  late ReceiptDesign d;

  @override
  void initState() {
    super.initState();
    d = widget.value;
  }

  @override
  void didUpdateWidget(covariant ReceiptDesignSectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value)) d = widget.value;
  }

  /// ينسخ التصميم الحالي، يطبّق التعديل على النسخة، يحدّث الحالة المحلية،
  /// ويُبلّغ الأب — بدون أي تعديل في المكان على الكائن المشترَك.
  void _update(void Function(ReceiptDesign d) mut) {
    final next = d.clone();
    mut(next);
    setState(() => d = next);
    widget.onChanged(next);
  }

  String _normalizeFamily(String f) {
    const allowed = {
      'Cairo', 'Tajawal', 'Amiri',
      'Noto Naskh Arabic', 'IBM Plex Sans Arabic',
    };
    return allowed.contains(f) ? f : 'Cairo';
  }

  @override
  Widget build(BuildContext context) {
    final children = switch (widget.section) {
      DesignSection.paper    => _paperSection(widget.templateType == 'pos'),
      DesignSection.fonts    => _typographySection(),
      DesignSection.layout   => _layoutSection(),
      DesignSection.colors   => _colorsSection(),
      DesignSection.sections => _showHideSection(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  // ─── 1. إظهار/إخفاء ────────────────────────────────────────────

  List<Widget> _showHideSection() {
    return [
      _switch('شعار المتجر', d.showLogo, (v) => _update((d) => d.showLogo = v)),
      _switch('بيانات المتجر (العنوان/الهاتف)', d.showShopInfo,
          (v) => _update((d) => d.showShopInfo = v)),
      _switch('رقم الوصل', d.showReceiptId,
          (v) => _update((d) => d.showReceiptId = v)),
      _switch('التاريخ والوقت', d.showDatetime,
          (v) => _update((d) => d.showDatetime = v)),
      _switch('بيانات المشترك', d.showSubscriberInfo,
          (v) => _update((d) => d.showSubscriberInfo = v)),
      _switch('بيانات الباقة', d.showPackageInfo,
          (v) => _update((d) => d.showPackageInfo = v)),
      _switch('سعر الباقة', d.showPackagePrice,
          (v) => _update((d) => d.showPackagePrice = v)),
      _switch('بيانات العملية', d.showTransactionInfo,
          (v) => _update((d) => d.showTransactionInfo = v)),
      _switch('توقيع المدير', d.showManagerSignature,
          (v) => _update((d) => d.showManagerSignature = v)),
      _switch('الذيل (رسالة الشكر)', d.showFooter,
          (v) => _update((d) => d.showFooter = v)),
    ];
  }

  // ─── 2. الورق ──────────────────────────────────────────────────

  List<Widget> _paperSection(bool isPos) {
    return [
      if (isPos) ...[
        _slider(
          label: 'عرض الورق',
          value: d.paperWidthMm,
          min: 50,
          max: 120,
          divisions: 70,
          suffix: ' مم',
          onChanged: (v) => _update((d) => d.paperWidthMm = v),
        ),
      ] else ...[
        _dropdown<String>(
          label: 'اتجاه A4',
          value: d.a4Orientation,
          items: const {
            'portrait': 'عمودي (Portrait)',
            'landscape': 'أفقي (Landscape)',
          },
          onChanged: (v) => _update((d) => d.a4Orientation = v ?? 'portrait'),
        ),
      ],
      const SizedBox(height: 6),
      _slider(
        label: 'الهامش العلوي',
        value: d.marginTopMm,
        min: 0,
        max: 30,
        divisions: 30,
        suffix: ' مم',
        onChanged: (v) => _update((d) => d.marginTopMm = v),
      ),
      _slider(
        label: 'الهامش السفلي',
        value: d.marginBottomMm,
        min: 0,
        max: 30,
        divisions: 30,
        suffix: ' مم',
        onChanged: (v) => _update((d) => d.marginBottomMm = v),
      ),
      _slider(
        label: 'الهامش الأيمن',
        value: d.marginRightMm,
        min: 0,
        max: 30,
        divisions: 30,
        suffix: ' مم',
        onChanged: (v) => _update((d) => d.marginRightMm = v),
      ),
      _slider(
        label: 'الهامش الأيسر',
        value: d.marginLeftMm,
        min: 0,
        max: 30,
        divisions: 30,
        suffix: ' مم',
        onChanged: (v) => _update((d) => d.marginLeftMm = v),
      ),
      const SizedBox(height: 12),
      _dropdown<String>(
        label: 'نمط الإطار',
        value: d.borderStyle,
        items: const {
          'none': 'بدون',
          'solid': 'متصل',
          'dashed': 'متقطّع',
          'dotted': 'منقّط',
          'double': 'مزدوج',
        },
        onChanged: (v) => _update((d) => d.borderStyle = v ?? 'dashed'),
      ),
      _slider(
        label: 'انحناء زوايا الإطار',
        value: d.borderRadiusPx,
        min: 0,
        max: 20,
        divisions: 20,
        suffix: ' px',
        onChanged: (v) => _update((d) => d.borderRadiusPx = v),
      ),
    ];
  }

  // ─── 3. الخطوط ─────────────────────────────────────────────────

  List<Widget> _typographySection() {
    return [
      _dropdown<String>(
        label: 'نوع الخط',
        value: _normalizeFamily(d.fontFamily),
        items: const {
          'Cairo': 'Cairo (افتراضي)',
          'Tajawal': 'Tajawal',
          'Amiri': 'Amiri (خط مزخرف)',
          'Noto Naskh Arabic': 'Noto Naskh Arabic',
          'IBM Plex Sans Arabic': 'IBM Plex Sans Arabic',
        },
        onChanged: (v) => _update((d) => d.fontFamily = v ?? 'Cairo'),
      ),
      const SizedBox(height: 6),
      _slider(
        label: 'حجم الخط الأساسي',
        value: d.fontSizeBase,
        min: 9,
        max: 22,
        divisions: 13,
        suffix: ' px',
        onChanged: (v) => _update((d) => d.fontSizeBase = v),
      ),
      _slider(
        label: 'حجم خط العناوين',
        value: d.fontSizeTitle,
        min: 12,
        max: 36,
        divisions: 24,
        suffix: ' px',
        onChanged: (v) => _update((d) => d.fontSizeTitle = v),
      ),
      _dropdown<String>(
        label: 'سُمك الخط',
        value: d.fontWeight,
        items: const {
          '400': 'عادي (400)',
          '500': 'متوسط (500)',
          '600': 'شبه عريض (600)',
          '700': 'عريض (700)',
          '800': 'عريض جداً (800)',
        },
        onChanged: (v) => _update((d) => d.fontWeight = v ?? '700'),
      ),
    ];
  }

  // ─── 4. الألوان ────────────────────────────────────────────────

  List<Widget> _colorsSection() {
    return [
      _colorRow(
        label: 'لون التمييز (Accent)',
        currentHex: d.accentColor,
        presets: const [
          '#0d9488', '#10b981', '#3b82f6', '#8b5cf6', '#ef4444',
          '#f59e0b', '#1f2937', '#000000',
        ],
        onChanged: (hex) => _update((d) => d.accentColor = hex),
      ),
      const SizedBox(height: 14),
      _colorRow(
        label: 'لون النص',
        currentHex: d.textColor,
        presets: const [
          '#0f172a', '#1f2937', '#374151', '#4b5563', '#000000',
        ],
        onChanged: (hex) => _update((d) => d.textColor = hex),
      ),
    ];
  }

  // ─── 5. التخطيط ────────────────────────────────────────────────

  List<Widget> _layoutSection() {
    return [
      _slider(
        label: 'المسافة بين الأقسام',
        value: d.sectionGapMm,
        min: 0,
        max: 20,
        divisions: 20,
        suffix: ' مم',
        onChanged: (v) => _update((d) => d.sectionGapMm = v),
      ),
      _slider(
        label: 'ارتفاع السطر',
        value: d.lineHeight,
        min: 1.0,
        max: 2.2,
        divisions: 12,
        suffix: 'x',
        onChanged: (v) => _update((d) => d.lineHeight = v),
      ),
      _slider(
        label: 'حجم الشعار',
        value: d.logoSizeMm,
        min: 8,
        max: 50,
        divisions: 42,
        suffix: ' مم',
        onChanged: (v) => _update((d) => d.logoSizeMm = v),
      ),
      _slider(
        label: 'حجم الـQR',
        value: d.qrSizeMm,
        min: 15,
        max: 60,
        divisions: 45,
        suffix: ' مم',
        onChanged: (v) => _update((d) => d.qrSizeMm = v),
      ),
      _dropdown<String>(
        label: 'محاذاة العنوان',
        value: d.headerAlign,
        items: const {
          'right': 'يمين',
          'center': 'وسط',
          'left': 'يسار',
        },
        onChanged: (v) => _update((d) => d.headerAlign = v ?? 'center'),
      ),
      _dropdown<String>(
        label: 'محاذاة الذيل',
        value: d.footerAlign,
        items: const {
          'right': 'يمين',
          'center': 'وسط',
          'left': 'يسار',
        },
        onChanged: (v) => _update((d) => d.footerAlign = v ?? 'center'),
      ),
      const SizedBox(height: 8),
      _switch('عناوين الأقسام بأحرف كبيرة', d.sectionTitleUppercase,
          (v) => _update((d) => d.sectionTitleUppercase = v)),
      _switch('تسطير عناوين الأقسام', d.sectionTitleUnderline,
          (v) => _update((d) => d.sectionTitleUnderline = v)),
    ];
  }

  // ─── أدوات مشتركة ──────────────────────────────────────────────

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        label,
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
      ),
      value: value,
      activeThumbColor: AppTheme.successColor,
      onChanged: onChanged,
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    final disp = value % 1 == 0
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$disp$suffix',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        items: items.entries
            .map((e) => DropdownMenuItem<T>(
                  value: e.key,
                  child: Text(
                    e.value,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  ),
                ))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _colorRow({
    required String label,
    required String currentHex,
    required List<String> presets,
    required ValueChanged<String> onChanged,
  }) {
    Color parse(String hex) {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: parse(currentHex),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              currentHex.toUpperCase(),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: parse(currentHex).computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((p) {
            final selected = p.toLowerCase() == currentHex.toLowerCase();
            return InkWell(
              onTap: () => onChanged(p),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: parse(p),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppTheme.primary
                        : Colors.black.withValues(alpha: 0.10),
                    width: selected ? 2.5 : 1,
                  ),
                ),
                child: selected
                    ? const Icon(LucideIcons.check,
                        size: 18, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
