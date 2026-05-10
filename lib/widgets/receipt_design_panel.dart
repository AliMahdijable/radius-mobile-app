import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/app_theme.dart';
import '../models/print_template_model.dart';

/// لوحة تحرير ReceiptDesign — مرآة للويب client-v2/PrintTemplates.tsx.
/// مقسّمة لـ 5 أقسام قابلة للطي (ExpansionTile) لتوفير المساحة على الموبايل:
///   1. الإظهار/الإخفاء — switches للعناصر الظاهرة على الوصل
///   2. الورق — عرض ورق POS، الهوامش، اتجاه A4
///   3. الخطوط — نوع الخط، الأحجام، الوزن
///   4. الألوان — accent + text + border
///   5. التخطيط — تباعد الأقسام، ارتفاع السطر، محاذاة، حواف
class ReceiptDesignPanel extends StatefulWidget {
  final ReceiptDesign value;
  final ValueChanged<ReceiptDesign> onChanged;
  final String templateType; // 'pos' | 'a4' — يخفي/يظهر بعض الحقول

  const ReceiptDesignPanel({
    super.key,
    required this.value,
    required this.onChanged,
    required this.templateType,
  });

  @override
  State<ReceiptDesignPanel> createState() => _ReceiptDesignPanelState();
}

class _ReceiptDesignPanelState extends State<ReceiptDesignPanel> {
  late ReceiptDesign d;

  @override
  void initState() {
    super.initState();
    d = widget.value;
  }

  @override
  void didUpdateWidget(covariant ReceiptDesignPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      d = widget.value;
    }
  }

  void _emit() => widget.onChanged(d);

  @override
  Widget build(BuildContext context) {
    final isPos = widget.templateType == 'pos';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(
          icon: LucideIcons.eye,
          title: 'الإظهار / الإخفاء',
          initiallyExpanded: true,
          children: _showHideSection(),
        ),
        const SizedBox(height: 8),
        _section(
          icon: LucideIcons.fileText,
          title: 'الورق والهوامش',
          children: _paperSection(isPos),
        ),
        const SizedBox(height: 8),
        _section(
          icon: LucideIcons.type,
          title: 'الخطوط',
          children: _typographySection(),
        ),
        const SizedBox(height: 8),
        _section(
          icon: LucideIcons.palette,
          title: 'الألوان',
          children: _colorsSection(),
        ),
        const SizedBox(height: 8),
        _section(
          icon: LucideIcons.layoutDashboard,
          title: 'التخطيط',
          children: _layoutSection(),
        ),
      ],
    );
  }

  // ─── البناء ────────────────────────────────────────────────────

  Widget _section({
    required IconData icon,
    required String title,
    bool initiallyExpanded = false,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            leading: Icon(icon, size: 18, color: AppTheme.primary),
            title: Text(
              title,
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            initiallyExpanded: initiallyExpanded,
            children: children,
          ),
        ),
      ),
    );
  }

  // ─── 1. إظهار/إخفاء ────────────────────────────────────────────

  List<Widget> _showHideSection() {
    return [
      _switch('شعار المتجر', d.showLogo, (v) => setState(() {
            d.showLogo = v;
            _emit();
          })),
      _switch('بيانات المتجر (العنوان/الهاتف)', d.showShopInfo, (v) => setState(() {
            d.showShopInfo = v;
            _emit();
          })),
      _switch('رقم الوصل', d.showReceiptId, (v) => setState(() {
            d.showReceiptId = v;
            _emit();
          })),
      _switch('التاريخ والوقت', d.showDatetime, (v) => setState(() {
            d.showDatetime = v;
            _emit();
          })),
      _switch('بيانات المشترك', d.showSubscriberInfo, (v) => setState(() {
            d.showSubscriberInfo = v;
            _emit();
          })),
      _switch('بيانات الباقة', d.showPackageInfo, (v) => setState(() {
            d.showPackageInfo = v;
            _emit();
          })),
      _switch('سعر الباقة', d.showPackagePrice, (v) => setState(() {
            d.showPackagePrice = v;
            _emit();
          })),
      _switch('بيانات العملية', d.showTransactionInfo, (v) => setState(() {
            d.showTransactionInfo = v;
            _emit();
          })),
      _switch('توقيع المدير', d.showManagerSignature, (v) => setState(() {
            d.showManagerSignature = v;
            _emit();
          })),
      _switch('الذيل (رسالة الشكر)', d.showFooter, (v) => setState(() {
            d.showFooter = v;
            _emit();
          })),
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
          onChanged: (v) => setState(() {
            d.paperWidthMm = v;
            _emit();
          }),
        ),
      ] else ...[
        _dropdown<String>(
          label: 'اتجاه A4',
          value: d.a4Orientation,
          items: const {
            'portrait': 'عمودي (Portrait)',
            'landscape': 'أفقي (Landscape)',
          },
          onChanged: (v) => setState(() {
            d.a4Orientation = v ?? 'portrait';
            _emit();
          }),
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
        onChanged: (v) => setState(() {
          d.marginTopMm = v;
          _emit();
        }),
      ),
      _slider(
        label: 'الهامش السفلي',
        value: d.marginBottomMm,
        min: 0,
        max: 30,
        divisions: 30,
        suffix: ' مم',
        onChanged: (v) => setState(() {
          d.marginBottomMm = v;
          _emit();
        }),
      ),
      _slider(
        label: 'الهامش الأيمن',
        value: d.marginRightMm,
        min: 0,
        max: 30,
        divisions: 30,
        suffix: ' مم',
        onChanged: (v) => setState(() {
          d.marginRightMm = v;
          _emit();
        }),
      ),
      _slider(
        label: 'الهامش الأيسر',
        value: d.marginLeftMm,
        min: 0,
        max: 30,
        divisions: 30,
        suffix: ' مم',
        onChanged: (v) => setState(() {
          d.marginLeftMm = v;
          _emit();
        }),
      ),
    ];
  }

  // ─── 3. الخطوط ─────────────────────────────────────────────────

  List<Widget> _typographySection() {
    return [
      _dropdown<String>(
        label: 'نوع الخط',
        value: d.fontFamily,
        items: const {
          'Cairo': 'Cairo',
          'Tajawal': 'Tajawal',
          'Almarai': 'Almarai',
        },
        onChanged: (v) => setState(() {
          d.fontFamily = v ?? 'Cairo';
          _emit();
        }),
      ),
      const SizedBox(height: 6),
      _slider(
        label: 'حجم الخط الأساسي',
        value: d.fontSizeBase,
        min: 9,
        max: 22,
        divisions: 13,
        suffix: ' px',
        onChanged: (v) => setState(() {
          d.fontSizeBase = v;
          _emit();
        }),
      ),
      _slider(
        label: 'حجم خط العناوين',
        value: d.fontSizeTitle,
        min: 12,
        max: 36,
        divisions: 24,
        suffix: ' px',
        onChanged: (v) => setState(() {
          d.fontSizeTitle = v;
          _emit();
        }),
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
        onChanged: (v) => setState(() {
          d.fontWeight = v ?? '700';
          _emit();
        }),
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
        onChanged: (hex) => setState(() {
          d.accentColor = hex;
          _emit();
        }),
      ),
      const SizedBox(height: 8),
      _colorRow(
        label: 'لون النص',
        currentHex: d.textColor,
        presets: const [
          '#0f172a', '#1f2937', '#374151', '#4b5563', '#000000',
        ],
        onChanged: (hex) => setState(() {
          d.textColor = hex;
          _emit();
        }),
      ),
    ];
  }

  // ─── 5. التخطيط ────────────────────────────────────────────────

  List<Widget> _layoutSection() {
    return [
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
        onChanged: (v) => setState(() {
          d.borderStyle = v ?? 'dashed';
          _emit();
        }),
      ),
      const SizedBox(height: 6),
      _slider(
        label: 'انحناء زوايا الإطار',
        value: d.borderRadiusPx,
        min: 0,
        max: 20,
        divisions: 20,
        suffix: ' px',
        onChanged: (v) => setState(() {
          d.borderRadiusPx = v;
          _emit();
        }),
      ),
      _slider(
        label: 'المسافة بين الأقسام',
        value: d.sectionGapMm,
        min: 0,
        max: 20,
        divisions: 20,
        suffix: ' مم',
        onChanged: (v) => setState(() {
          d.sectionGapMm = v;
          _emit();
        }),
      ),
      _slider(
        label: 'ارتفاع السطر',
        value: d.lineHeight,
        min: 1.0,
        max: 2.2,
        divisions: 12,
        suffix: 'x',
        onChanged: (v) => setState(() {
          d.lineHeight = v;
          _emit();
        }),
      ),
      _slider(
        label: 'حجم الشعار',
        value: d.logoSizeMm,
        min: 8,
        max: 50,
        divisions: 42,
        suffix: ' مم',
        onChanged: (v) => setState(() {
          d.logoSizeMm = v;
          _emit();
        }),
      ),
      _slider(
        label: 'حجم الـQR',
        value: d.qrSizeMm,
        min: 15,
        max: 60,
        divisions: 45,
        suffix: ' مم',
        onChanged: (v) => setState(() {
          d.qrSizeMm = v;
          _emit();
        }),
      ),
      _dropdown<String>(
        label: 'محاذاة العنوان',
        value: d.headerAlign,
        items: const {
          'right': 'يمين',
          'center': 'وسط',
          'left': 'يسار',
        },
        onChanged: (v) => setState(() {
          d.headerAlign = v ?? 'center';
          _emit();
        }),
      ),
      _dropdown<String>(
        label: 'محاذاة الذيل',
        value: d.footerAlign,
        items: const {
          'right': 'يمين',
          'center': 'وسط',
          'left': 'يسار',
        },
        onChanged: (v) => setState(() {
          d.footerAlign = v ?? 'center';
          _emit();
        }),
      ),
      _switch('عناوين الأقسام بأحرف كبيرة', d.sectionTitleUppercase,
          (v) => setState(() {
                d.sectionTitleUppercase = v;
                _emit();
              })),
      _switch('تسطير عناوين الأقسام', d.sectionTitleUnderline,
          (v) => setState(() {
                d.sectionTitleUnderline = v;
                _emit();
              })),
    ];
  }

  // ─── أدوات مشتركة ──────────────────────────────────────────────

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        label,
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
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
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
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
          labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        items: items.entries
            .map((e) => DropdownMenuItem<T>(
                  value: e.key,
                  child: Text(
                    e.value,
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
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
    Color _parse(String hex) {
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
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _parse(currentHex),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              currentHex.toUpperCase(),
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                color: _parse(currentHex).computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: presets.map((p) {
            final selected = p.toLowerCase() == currentHex.toLowerCase();
            return InkWell(
              onTap: () => onChanged(p),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _parse(p),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? AppTheme.primary
                        : Colors.black.withValues(alpha: 0.10),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: selected
                    ? const Icon(LucideIcons.check,
                        size: 16, color: Colors.white)
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
