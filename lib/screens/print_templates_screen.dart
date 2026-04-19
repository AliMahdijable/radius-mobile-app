import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/receipt_printer.dart';
import '../models/print_template_model.dart';
import '../providers/print_templates_provider.dart';
import '../widgets/app_snackbar.dart';

class PrintTemplatesScreen extends ConsumerStatefulWidget {
  const PrintTemplatesScreen({super.key});

  @override
  ConsumerState<PrintTemplatesScreen> createState() =>
      _PrintTemplatesScreenState();
}

class _PrintTemplatesScreenState extends ConsumerState<PrintTemplatesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(printTemplatesProvider.notifier).loadTemplates());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(printTemplatesProvider);
    final theme = Theme.of(context);

    final hasA4 = state.templates.any((t) => t.templateType == 'a4');
    final hasPOS = state.templates.any((t) => t.templateType == 'pos');

    return Scaffold(
      appBar: AppBar(
        title: const Text('قوالب الطباعة',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ref.read(printTemplatesProvider.notifier).loadTemplates(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline, size: 20,
                          color: AppTheme.primary.withOpacity(0.7)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'القالب النشط سيُستخدم في طباعة الوصولات عند التفعيل وتسديد الديون',
                          style: TextStyle(
                            fontFamily: 'Cairo', fontSize: 12,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  if (!hasA4 || !hasPOS) ...[
                    Row(children: [
                      if (!hasA4)
                        Expanded(
                          child: _AddTemplateCard(
                            label: 'A4', icon: Icons.description_rounded,
                            onTap: () => _openBuilder(null, 'a4'),
                          ),
                        ),
                      if (!hasA4 && !hasPOS) const SizedBox(width: 10),
                      if (!hasPOS)
                        Expanded(
                          child: _AddTemplateCard(
                            label: 'POS', icon: Icons.receipt_long_rounded,
                            onTap: () => _openBuilder(null, 'pos'),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  ...state.templates.map((t) => _TemplateCard(
                        template: t,
                        onEdit: () => _openBuilder(t, t.templateType),
                        onToggle: () => _toggleTemplate(t),
                        onDelete: () => _deleteTemplate(t),
                        onPreview: () => _previewTemplate(t),
                      )),

                  if (state.templates.isEmpty && hasA4 && hasPOS)
                    _emptyState(theme),
                ],
              ),
            ),
    );
  }

  Widget _emptyState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(children: [
        Icon(Icons.print_disabled_rounded, size: 56,
            color: theme.colorScheme.onSurface.withOpacity(0.2)),
        const SizedBox(height: 12),
        Text('لا توجد قوالب طباعة',
            style: TextStyle(fontFamily: 'Cairo',
                color: theme.colorScheme.onSurface.withOpacity(0.4))),
      ]),
    );
  }

  void _openBuilder(PrintTemplateModel? existing, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _InvoiceBuilderPage(template: existing, templateType: type),
      ),
    ).then((saved) {
      if (saved == true) {
        ref.read(printTemplatesProvider.notifier).loadTemplates();
      }
    });
  }

  Future<void> _toggleTemplate(PrintTemplateModel t) async {
    final ok = await ref.read(printTemplatesProvider.notifier).toggleActive(t.id!);
    if (mounted) {
      if (ok) {
        AppSnackBar.success(context, t.isActive ? 'تم تعطيل القالب' : 'تم تفعيل القالب');
      } else {
        AppSnackBar.error(context, 'فشل تغيير حالة القالب');
      }
    }
  }

  Future<void> _deleteTemplate(PrintTemplateModel t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف القالب'),
        content: Text('هل تريد حذف "${t.templateName}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ref.read(printTemplatesProvider.notifier).deleteTemplate(t.id!);
    if (mounted) {
      if (ok) {
        AppSnackBar.success(context, 'تم حذف القالب');
      } else {
        AppSnackBar.error(context, 'فشل حذف القالب');
      }
    }
  }

  Future<void> _previewTemplate(PrintTemplateModel t) async {
    final sampleData = ReceiptData(
      subscriberName: 'أحمد محمد',
      phoneNumber: '07801234567',
      packageName: 'باقة 10 ميغا',
      packagePrice: 15000, paidAmount: 15000,
      remainingAmount: 0, debtAmount: 0,
      expiryDate: '2026-05-15', operationType: 'activation',
    );
    try {
      await ReceiptPrinter.printReceipt(data: sampleData, htmlTemplate: t.content);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'فشل معاينة القالب');
    }
  }
}

// ─────────────────────────────────────────────────────────
// Shared Widgets
// ─────────────────────────────────────────────────────────

class _AddTemplateCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _AddTemplateCard({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: theme.cardTheme.color, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
        ),
        child: Column(children: [
          Icon(icon, size: 32, color: AppTheme.primary.withOpacity(0.5)),
          const SizedBox(height: 8),
          Text('إضافة قالب $label',
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                  fontWeight: FontWeight.w600, color: AppTheme.primary)),
        ]),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final PrintTemplateModel template;
  final VoidCallback onEdit, onToggle, onDelete, onPreview;
  const _TemplateCard({required this.template, required this.onEdit,
      required this.onToggle, required this.onDelete, required this.onPreview});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isA4 = template.templateType == 'a4';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color, borderRadius: BorderRadius.circular(14),
        border: template.isActive
            ? Border.all(color: AppTheme.successColor.withOpacity(0.4), width: 1.5) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (template.isActive ? AppTheme.successColor : Colors.grey).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(isA4 ? Icons.description_rounded : Icons.receipt_long_rounded,
                  size: 22, color: template.isActive ? AppTheme.successColor : Colors.grey),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(template.templateName, style: const TextStyle(
                    fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w700)),
                Row(children: [
                  _Badge(label: isA4 ? 'A4' : 'POS', color: AppTheme.primary),
                  if (template.isActive) ...[
                    const SizedBox(width: 6),
                    _Badge(label: 'نشط', color: AppTheme.successColor),
                  ],
                ]),
              ]),
            ),
            Switch.adaptive(value: template.isActive, onChanged: (_) => onToggle(),
                activeColor: AppTheme.successColor),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _ActionChip(icon: Icons.edit_rounded, label: 'تعديل', onTap: onEdit),
            const SizedBox(width: 8),
            _ActionChip(icon: Icons.visibility_rounded, label: 'معاينة', onTap: onPreview),
            const SizedBox(width: 8),
            _ActionChip(icon: Icons.delete_outline_rounded, label: 'حذف',
                onTap: onDelete, color: Colors.red),
          ]),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge({required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 10,
          fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ActionChip({required this.icon, required this.label,
      required this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c.withOpacity(0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withOpacity(0.15))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
              fontWeight: FontWeight.w600, color: c)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Invoice Builder Page (visual designer)
// ─────────────────────────────────────────────────────────

class _InvoiceElement {
  String id;
  String type; // header, field, divider, footer, text
  String label;
  String content;
  String variable;
  String fontSize;
  String color;
  String align;
  int order;
  bool visible;
  String dividerStyle;

  _InvoiceElement({
    required this.id, required this.type, required this.label,
    this.content = '', this.variable = '', this.fontSize = '14px',
    this.color = '#1f2937', this.align = 'right', this.order = 0,
    this.visible = true, this.dividerStyle = 'solid',
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type, 'label': label, 'content': content,
    'variable': variable, 'fontSize': fontSize, 'color': color,
    'align': align, 'order': order, 'visible': visible,
    'style': dividerStyle,
  };

  factory _InvoiceElement.fromJson(Map<String, dynamic> json) {
    return _InvoiceElement(
      id: json['id'] ?? 'el_${DateTime.now().millisecondsSinceEpoch}',
      type: json['type'] ?? 'field',
      label: json['label'] ?? '',
      content: json['content'] ?? '',
      variable: json['variable'] ?? '',
      fontSize: json['fontSize'] ?? '14px',
      color: json['color'] ?? '#1f2937',
      align: json['align'] ?? 'right',
      order: json['order'] ?? 0,
      visible: json['visible'] ?? true,
      dividerStyle: json['style'] ?? 'solid',
    );
  }
}

class _InvoiceBuilderPage extends ConsumerStatefulWidget {
  final PrintTemplateModel? template;
  final String templateType;
  const _InvoiceBuilderPage({this.template, required this.templateType});

  @override
  ConsumerState<_InvoiceBuilderPage> createState() => _InvoiceBuilderPageState();
}

class _InvoiceBuilderPageState extends ConsumerState<_InvoiceBuilderPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late TextEditingController _nameCtrl;
  late List<_InvoiceElement> _elements;
  late String _layoutType;
  bool _saving = false;

  String _bgColor = '#ffffff';
  String _padding = '20px';
  String _fontFamily = 'Cairo';

  static const _variableOptions = <String, String>{
    '{invoice_number}': 'رقم الفاتورة',
    '{date}': 'التاريخ',
    '{subscriber_name}': 'اسم المشترك',
    '{phone_number}': 'رقم الهاتف',
    '{package_name}': 'اسم الباقة',
    '{package_price}': 'سعر الباقة',
    '{paid_amount}': 'المبلغ المدفوع',
    '{remaining_amount}': 'المبلغ المتبقي',
    '{expiry_date}': 'تاريخ الانتهاء',
    '{debt_amount}': 'مبلغ الدين',
  };

  static const _fontSizes = ['12px', '14px', '16px', '18px', '20px', '24px', '28px', '32px'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _layoutType = widget.templateType;
    _nameCtrl = TextEditingController(
      text: widget.template?.templateName ??
          (widget.templateType == 'a4' ? 'قالب A4' : 'قالب POS'),
    );
    _loadElements();
  }

  void _loadElements() {
    if (widget.template?.templateData != null) {
      try {
        final data = jsonDecode(widget.template!.templateData!);
        if (data is Map && data['elements'] is List) {
          _elements = (data['elements'] as List)
              .map((e) => _InvoiceElement.fromJson(e as Map<String, dynamic>))
              .toList();
          if (data['globalSettings'] is Map) {
            final gs = data['globalSettings'] as Map;
            _bgColor = gs['backgroundColor'] ?? '#ffffff';
            _padding = gs['padding'] ?? '20px';
            _fontFamily = gs['fontFamily'] ?? 'Cairo';
          }
          if (data['layoutType'] is String) {
            _layoutType = data['layoutType'];
          }
          return;
        }
      } catch (_) {}
    }
    _elements = _defaultElements();
  }

  // القوالب الجاهزة للاختيار من زر "✨" أعلى الشاشة
  static const _presetLayouts = <({String id, String title, String subtitle, IconData icon})>[
    (
      id: 'full_invoice',
      title: 'فاتورة كاملة',
      subtitle: 'رأس + بيانات المشترك + المبالغ + التذييل',
      icon: Icons.description_rounded,
    ),
    (
      id: 'pos_receipt',
      title: 'وصل حراري (POS)',
      subtitle: 'مختصر ومضغوط — مناسب للطابعة الحرارية 80mm',
      icon: Icons.receipt_long_rounded,
    ),
    (
      id: 'payment_receipt',
      title: 'وصل تسديد',
      subtitle: 'يركّز على المدفوع والمتبقّي والدين',
      icon: Icons.payments_rounded,
    ),
    (
      id: 'activation_simple',
      title: 'تفعيل مبسَّط',
      subtitle: 'الاسم + الباقة + السعر + تاريخ الانتهاء',
      icon: Icons.check_circle_rounded,
    ),
  ];

  void _showPresetPicker() {
    final bool hasExisting = _elements.isNotEmpty;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: AppTheme.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('توليد قالب جاهز',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'اختر قالباً مُصمَّماً جاهزاً — سيستبدل العناصر الحالية.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.55),
                  ),
                ),
                const SizedBox(height: 12),
                ..._presetLayouts.map((p) => _PresetTile(
                      icon: p.icon,
                      title: p.title,
                      subtitle: p.subtitle,
                      onTap: () async {
                        Navigator.pop(ctx);
                        if (hasExisting) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (dCtx) => AlertDialog(
                              title: const Text('استبدال التصميم؟'),
                              content: const Text(
                                  'التصميم الحالي سيُستبدَل بالقالب الجاهز.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dCtx, false),
                                  child: const Text('إلغاء'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(dCtx, true),
                                  child: const Text('استبدال'),
                                ),
                              ],
                            ),
                          );
                          if (confirm != true) return;
                        }
                        setState(() {
                          _elements = _presetElements(p.id);
                          if (p.id == 'pos_receipt') _layoutType = 'pos';
                        });
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_InvoiceElement> _presetElements(String id) {
    switch (id) {
      case 'pos_receipt':
        return [
          _InvoiceElement(id: 'header', type: 'header', label: 'العنوان',
              content: 'وصل استلام', fontSize: '22px', color: '#10b981', align: 'center', order: 0),
          _InvoiceElement(id: 'invoice_number', type: 'field', label: 'رقم',
              variable: '{invoice_number}', fontSize: '12px', color: '#6b7280', align: 'center', order: 1),
          _InvoiceElement(id: 'date', type: 'field', label: 'التاريخ',
              variable: '{date}', fontSize: '12px', color: '#6b7280', align: 'center', order: 2),
          _InvoiceElement(id: 'divider1', type: 'divider', label: 'خط',
              dividerStyle: 'dashed', color: '#9ca3af', order: 3),
          _InvoiceElement(id: 'subscriber_name', type: 'field', label: 'المشترك',
              variable: '{subscriber_name}', fontSize: '14px', color: '#1f2937', align: 'right', order: 4),
          _InvoiceElement(id: 'package_name', type: 'field', label: 'الباقة',
              variable: '{package_name}', fontSize: '12px', color: '#374151', align: 'right', order: 5),
          _InvoiceElement(id: 'divider2', type: 'divider', label: 'خط',
              dividerStyle: 'dashed', color: '#9ca3af', order: 6),
          _InvoiceElement(id: 'package_price', type: 'field', label: 'السعر',
              variable: '{package_price} IQD', fontSize: '14px', color: '#1f2937', align: 'right', order: 7),
          _InvoiceElement(id: 'paid_amount', type: 'field', label: 'المدفوع',
              variable: '{paid_amount} IQD', fontSize: '14px', color: '#047857', align: 'right', order: 8),
          _InvoiceElement(id: 'remaining_amount', type: 'field', label: 'المتبقي',
              variable: '{remaining_amount} IQD', fontSize: '14px', color: '#dc2626', align: 'right', order: 9),
          _InvoiceElement(id: 'divider3', type: 'divider', label: 'خط',
              dividerStyle: 'dashed', color: '#9ca3af', order: 10),
          _InvoiceElement(id: 'footer', type: 'footer', label: 'الذيل',
              content: 'شكراً لتعاملكم معنا', fontSize: '11px', color: '#6b7280', align: 'center', order: 11),
        ];
      case 'payment_receipt':
        return [
          _InvoiceElement(id: 'header', type: 'header', label: 'العنوان',
              content: 'وصل تسديد', fontSize: '28px', color: '#10b981', align: 'center', order: 0),
          _InvoiceElement(id: 'invoice_number', type: 'field', label: 'رقم الوصل',
              variable: '{invoice_number}', fontSize: '14px', color: '#6b7280', align: 'center', order: 1),
          _InvoiceElement(id: 'date', type: 'field', label: 'التاريخ',
              variable: '{date}', fontSize: '14px', color: '#6b7280', align: 'center', order: 2),
          _InvoiceElement(id: 'divider1', type: 'divider', label: 'خط فاصل',
              dividerStyle: 'solid', color: '#e5e7eb', order: 3),
          _InvoiceElement(id: 'subscriber_name', type: 'field', label: 'اسم المشترك',
              variable: '{subscriber_name}', fontSize: '16px', color: '#1f2937', align: 'right', order: 4),
          _InvoiceElement(id: 'phone_number', type: 'field', label: 'رقم الهاتف',
              variable: '{phone_number}', fontSize: '14px', color: '#374151', align: 'right', order: 5),
          _InvoiceElement(id: 'divider2', type: 'divider', label: 'خط فاصل',
              dividerStyle: 'solid', color: '#e5e7eb', order: 6),
          _InvoiceElement(id: 'paid_amount', type: 'field', label: 'المبلغ المدفوع',
              variable: '{paid_amount} IQD', fontSize: '16px', color: '#047857', align: 'right', order: 7),
          _InvoiceElement(id: 'debt_amount', type: 'field', label: 'الدين المتبقي',
              variable: '{debt_amount} IQD', fontSize: '15px', color: '#dc2626', align: 'right', order: 8),
          _InvoiceElement(id: 'remaining_amount', type: 'field', label: 'الإجمالي المتبقي',
              variable: '{remaining_amount} IQD', fontSize: '15px', color: '#374151', align: 'right', order: 9),
          _InvoiceElement(id: 'divider3', type: 'divider', label: 'خط فاصل',
              dividerStyle: 'solid', color: '#10b981', order: 10),
          _InvoiceElement(id: 'footer', type: 'footer', label: 'الذيل',
              content: 'شكراً لكم على التسديد 🙏', fontSize: '14px', color: '#6b7280', align: 'center', order: 11),
        ];
      case 'activation_simple':
        return [
          _InvoiceElement(id: 'header', type: 'header', label: 'العنوان',
              content: 'تم التفعيل ✅', fontSize: '28px', color: '#10b981', align: 'center', order: 0),
          _InvoiceElement(id: 'date', type: 'field', label: 'التاريخ',
              variable: '{date}', fontSize: '13px', color: '#6b7280', align: 'center', order: 1),
          _InvoiceElement(id: 'divider1', type: 'divider', label: 'خط فاصل',
              dividerStyle: 'solid', color: '#e5e7eb', order: 2),
          _InvoiceElement(id: 'subscriber_name', type: 'field', label: 'المشترك',
              variable: '{subscriber_name}', fontSize: '17px', color: '#1f2937', align: 'right', order: 3),
          _InvoiceElement(id: 'package_name', type: 'field', label: 'الباقة',
              variable: '{package_name}', fontSize: '15px', color: '#374151', align: 'right', order: 4),
          _InvoiceElement(id: 'package_price', type: 'field', label: 'السعر',
              variable: '{package_price} IQD', fontSize: '15px', color: '#1f2937', align: 'right', order: 5),
          _InvoiceElement(id: 'expiry_date', type: 'field', label: 'تاريخ الانتهاء',
              variable: '{expiry_date}', fontSize: '14px', color: '#374151', align: 'right', order: 6),
          _InvoiceElement(id: 'divider2', type: 'divider', label: 'خط فاصل',
              dividerStyle: 'solid', color: '#10b981', order: 7),
          _InvoiceElement(id: 'footer', type: 'footer', label: 'الذيل',
              content: 'نتمنى لك تجربة ممتازة 🌐', fontSize: '13px', color: '#6b7280', align: 'center', order: 8),
        ];
      case 'full_invoice':
      default:
        return _defaultElements();
    }
  }

  List<_InvoiceElement> _defaultElements() {
    return [
      _InvoiceElement(id: 'header', type: 'header', label: 'العنوان',
          content: 'فاتورة', fontSize: '28px', color: '#10b981', align: 'center', order: 0),
      _InvoiceElement(id: 'invoice_number', type: 'field', label: 'رقم الفاتورة',
          variable: '{invoice_number}', fontSize: '14px', color: '#6b7280', align: 'center', order: 1),
      _InvoiceElement(id: 'date', type: 'field', label: 'التاريخ',
          variable: '{date}', fontSize: '14px', color: '#6b7280', align: 'center', order: 2),
      _InvoiceElement(id: 'divider1', type: 'divider', label: 'خط فاصل',
          dividerStyle: 'solid', color: '#e5e7eb', order: 3),
      _InvoiceElement(id: 'subscriber_name', type: 'field', label: 'اسم المشترك',
          variable: '{subscriber_name}', fontSize: '16px', color: '#1f2937', align: 'right', order: 4),
      _InvoiceElement(id: 'phone_number', type: 'field', label: 'رقم الهاتف',
          variable: '{phone_number}', fontSize: '14px', color: '#374151', align: 'right', order: 5),
      _InvoiceElement(id: 'package_name', type: 'field', label: 'اسم الباقة',
          variable: '{package_name}', fontSize: '14px', color: '#374151', align: 'right', order: 6),
      _InvoiceElement(id: 'divider2', type: 'divider', label: 'خط فاصل',
          dividerStyle: 'solid', color: '#e5e7eb', order: 7),
      _InvoiceElement(id: 'package_price', type: 'field', label: 'سعر الباقة',
          variable: '{package_price} IQD', fontSize: '15px', color: '#1f2937', align: 'right', order: 8),
      _InvoiceElement(id: 'paid_amount', type: 'field', label: 'المبلغ المدفوع',
          variable: '{paid_amount} IQD', fontSize: '15px', color: '#047857', align: 'right', order: 9),
      _InvoiceElement(id: 'remaining_amount', type: 'field', label: 'المبلغ المتبقي',
          variable: '{remaining_amount} IQD', fontSize: '15px', color: '#dc2626', align: 'right', order: 10),
      _InvoiceElement(id: 'expiry_date', type: 'field', label: 'تاريخ الانتهاء',
          variable: '{expiry_date}', fontSize: '14px', color: '#374151', align: 'right', order: 11),
      _InvoiceElement(id: 'divider3', type: 'divider', label: 'خط فاصل',
          dividerStyle: 'solid', color: '#10b981', order: 12),
      _InvoiceElement(id: 'footer', type: 'footer', label: 'الذيل',
          content: 'شكراً لتعاملكم معنا', fontSize: '14px', color: '#6b7280', align: 'center', order: 13),
    ];
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  String _generateHTML() {
    final sorted = List<_InvoiceElement>.from(_elements)
      ..sort((a, b) => a.order.compareTo(b.order));
    final width = _layoutType == 'pos' ? '80mm' : '100%';
    final maxW = _layoutType == 'pos' ? '80mm' : '21cm';

    final buf = StringBuffer();
    buf.write('<div style="width:$width;max-width:$maxW;padding:$_padding;'
        'font-family:$_fontFamily,sans-serif;direction:rtl;background:$_bgColor;">');

    for (final el in sorted) {
      if (!el.visible) continue;
      switch (el.type) {
        case 'header':
          buf.write('<div style="text-align:${el.align};margin:15px 0;">'
              '<h1 style="margin:0;color:${el.color};font-size:${el.fontSize};font-weight:700;">'
              '${el.content}</h1></div>');
          break;
        case 'field':
          buf.write('<div style="text-align:${el.align};margin:8px 0;font-size:${el.fontSize};'
              'color:${el.color};"><strong>${el.label}:</strong> ${el.variable}</div>');
          break;
        case 'divider':
          buf.write('<hr style="border:none;border-top:2px ${el.dividerStyle} ${el.color};margin:15px 0;" />');
          break;
        case 'footer':
          buf.write('<div style="text-align:${el.align};margin-top:30px;padding-top:15px;'
              'border-top:2px solid ${el.color};color:${el.color};font-size:${el.fontSize};">'
              '${el.content}</div>');
          break;
        case 'text':
          buf.write('<div style="text-align:${el.align};margin:8px 0;font-size:${el.fontSize};'
              'color:${el.color};">${el.content}</div>');
          break;
      }
    }
    buf.write('</div>');
    return buf.toString();
  }

  String _previewHTML() {
    return _generateHTML()
        .replaceAll('{invoice_number}', '12345')
        .replaceAll('{date}', DateTime.now().toString().substring(0, 10))
        .replaceAll('{subscriber_name}', 'محمد أحمد علي')
        .replaceAll('{phone_number}', '07901234567')
        .replaceAll('{package_name}', 'الباقة الذهبية')
        .replaceAll('{package_price}', '50,000')
        .replaceAll('{paid_amount}', '50,000')
        .replaceAll('{remaining_amount}', '0')
        .replaceAll('{expiry_date}', '2026-12-31')
        .replaceAll('{debt_amount}', '0');
  }

  void _addElement(String type) {
    final newEl = _InvoiceElement(
      id: 'el_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      label: type == 'header' ? 'عنوان جديد' : type == 'field' ? 'حقل جديد'
          : type == 'divider' ? 'خط فاصل' : type == 'text' ? 'نص حر' : 'ذيل',
      content: type == 'text' ? 'نص مخصص' : type == 'header' ? 'عنوان' : type == 'footer' ? 'تذييل' : '',
      variable: type == 'field' ? '{subscriber_name}' : '',
      fontSize: type == 'header' ? '24px' : '14px',
      color: type == 'header' ? '#10b981' : '#1f2937',
      align: type == 'header' || type == 'footer' ? 'center' : 'right',
      order: _elements.length,
      dividerStyle: 'solid',
    );
    setState(() => _elements.add(newEl));
  }

  void _deleteElement(int index) {
    setState(() {
      _elements.removeAt(index);
      for (int i = 0; i < _elements.length; i++) _elements[i].order = i;
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      AppSnackBar.warning(context, 'يرجى إدخال اسم القالب');
      return;
    }

    setState(() => _saving = true);

    final html = _generateHTML();
    final templateData = jsonEncode({
      'html': html,
      'elements': _elements.map((e) => e.toJson()).toList(),
      'globalSettings': {
        'backgroundColor': _bgColor,
        'padding': _padding,
        'fontFamily': _fontFamily,
      },
      'layoutType': _layoutType,
      'templateName': name,
    });

    final notifier = ref.read(printTemplatesProvider.notifier);
    bool ok;

    if (widget.template?.id != null) {
      ok = await notifier.updateTemplate(
        widget.template!.id!,
        widget.template!.copyWith(templateName: name, content: html, templateData: templateData),
      );
    } else {
      ok = await notifier.createTemplate(PrintTemplateModel(
        adminId: '', templateType: _layoutType,
        templateName: name, content: html,
        templateData: templateData, isActive: true,
      ));
    }

    setState(() => _saving = false);
    if (mounted) {
      if (ok) {
        AppSnackBar.success(context, 'تم حفظ القالب بنجاح');
        Navigator.pop(context, true);
      } else {
        AppSnackBar.error(context, 'فشل في حفظ القالب');
      }
    }
  }

  void _showElementProperties(int index) {
    final el = _elements[index];
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ElementPropertiesSheet(
        element: el,
        variableOptions: _variableOptions,
        fontSizes: _fontSizes,
        onUpdate: (updated) {
          setState(() => _elements[index] = updated);
        },
        onDelete: () {
          Navigator.pop(ctx);
          _deleteElement(index);
        },
      ),
    );
  }

  void _showGlobalSettings() {
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        var bg = _bgColor;
        var pad = _padding;
        var font = _fontFamily;
        return StatefulBuilder(builder: (ctx2, setSheet) {
          return _BottomSheet(
            title: 'إعدادات عامة',
            icon: Icons.settings_rounded,
            children: [
              _PropRow(label: 'لون الخلفية', child: Row(children: [
                _ColorDot(color: bg, onTap: () async {
                  final c = await _pickColor(ctx2, bg);
                  if (c != null) setSheet(() => bg = c);
                }),
                const SizedBox(width: 8),
                Text(bg, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
              ])),
              _PropRow(label: 'المسافة الداخلية', child: DropdownButton<String>(
                value: pad, isExpanded: true, isDense: true,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                    color: Theme.of(ctx2).colorScheme.onSurface),
                items: const [
                  DropdownMenuItem(value: '10px', child: Text('صغيرة')),
                  DropdownMenuItem(value: '20px', child: Text('متوسطة')),
                  DropdownMenuItem(value: '30px', child: Text('كبيرة')),
                  DropdownMenuItem(value: '40px', child: Text('كبيرة جداً')),
                ],
                onChanged: (v) => setSheet(() => pad = v!),
              )),
              _PropRow(label: 'الخط', child: DropdownButton<String>(
                value: font, isExpanded: true, isDense: true,
                style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                    color: Theme.of(ctx2).colorScheme.onSurface),
                items: const [
                  DropdownMenuItem(value: 'Cairo', child: Text('Cairo')),
                  DropdownMenuItem(value: 'Arial', child: Text('Arial')),
                  DropdownMenuItem(value: 'Tahoma', child: Text('Tahoma')),
                ],
                onChanged: (v) => setSheet(() => font = v!),
              )),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, height: AppTheme.actionButtonHeight, child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _bgColor = bg;
                    _padding = pad;
                    _fontFamily = font;
                  });
                  Navigator.pop(ctx2);
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('تطبيق', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
              )),
            ],
          );
        });
      },
    );
  }

  Future<String?> _pickColor(BuildContext ctx, String current) async {
    final colors = [
      '#ffffff', '#f9fafb', '#f3f4f6', '#1f2937', '#111827', '#000000',
      '#10b981', '#047857', '#059669', '#14b8a6', '#0d9488',
      '#3b82f6', '#2563eb', '#6366f1', '#8b5cf6',
      '#ef4444', '#dc2626', '#f59e0b', '#f97316',
      '#e5e7eb', '#d1d5db', '#9ca3af', '#6b7280', '#374151',
    ];
    return showDialog<String>(
      context: ctx,
      builder: (dlg) => AlertDialog(
        title: const Text('اختر لون', style: TextStyle(fontFamily: 'Cairo')),
        content: Wrap(
          spacing: 8, runSpacing: 8,
          children: colors.map((c) {
            final parsed = Color(int.parse('FF${c.replaceAll('#', '')}', radix: 16));
            return GestureDetector(
              onTap: () => Navigator.pop(dlg, c),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: parsed, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c == current ? AppTheme.primary : Colors.grey.shade300, width: c == current ? 2 : 1),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'header': return Icons.title_rounded;
      case 'field': return Icons.text_fields_rounded;
      case 'divider': return Icons.horizontal_rule_rounded;
      case 'footer': return Icons.vertical_align_bottom_rounded;
      case 'text': return Icons.notes_rounded;
      default: return Icons.widgets_rounded;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'header': return 'عنوان';
      case 'field': return 'حقل';
      case 'divider': return 'خط فاصل';
      case 'footer': return 'ذيل';
      case 'text': return 'نص حر';
      default: return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.template?.id != null;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          isEditing ? 'تعديل التصميم' : 'تصميم فاتورة جديدة',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _showPresetPicker,
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: 'توليد قالب جاهز',
          ),
          IconButton(
            onPressed: _showGlobalSettings,
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'إعدادات عامة',
          ),
          if (_saving)
            const Padding(padding: EdgeInsets.all(12),
                child: SizedBox(width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(onPressed: _save, icon: const Icon(Icons.save_rounded), tooltip: 'حفظ'),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(86),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _LayoutToggle(label: 'A4', icon: Icons.description_rounded,
                  active: _layoutType == 'a4', onTap: () => setState(() => _layoutType = 'a4')),
              const SizedBox(width: 8),
              _LayoutToggle(label: 'POS', icon: Icons.receipt_long_rounded,
                  active: _layoutType == 'pos', onTap: () => setState(() => _layoutType = 'pos')),
            ]),
            const SizedBox(height: 4),
            TabBar(controller: _tabCtrl, tabs: const [
              Tab(text: 'العناصر'),
              Tab(text: 'المعاينة'),
            ]),
          ]),
        ),
      ),
      bottomNavigationBar: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: AppTheme.actionButtonHeight,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 20),
                label: Text(
                  _saving ? 'جاري الحفظ...' : 'حفظ التصميم',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(children: [
        // Template name
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'اسم القالب', prefixIcon: Icon(Icons.label_outline, size: 20), isDense: true,
            ),
          ),
        ),
        Expanded(
          child: TabBarView(controller: _tabCtrl, children: [
            _buildElementsTab(theme),
            _buildPreviewTab(theme),
          ]),
        ),
      ]),
    );
  }

  Widget _buildElementsTab(ThemeData theme) {
    return Column(children: [
      // Add buttons
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          _AddBtn(icon: Icons.title_rounded, label: 'عنوان',
              onTap: () => _addElement('header')),
          const SizedBox(width: 6),
          _AddBtn(icon: Icons.text_fields_rounded, label: 'حقل',
              onTap: () => _addElement('field')),
          const SizedBox(width: 6),
          _AddBtn(icon: Icons.horizontal_rule_rounded, label: 'فاصل',
              onTap: () => _addElement('divider')),
          const SizedBox(width: 6),
          _AddBtn(icon: Icons.notes_rounded, label: 'نص',
              onTap: () => _addElement('text')),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onSurface.withOpacity(0.3)),
          const SizedBox(width: 6),
          Text('اسحب لإعادة الترتيب • اضغط لتعديل الخصائص',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 10,
                  color: theme.colorScheme.onSurface.withOpacity(0.4))),
        ]),
      ),
      const SizedBox(height: 4),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          itemCount: _elements.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = _elements.removeAt(oldIndex);
              _elements.insert(newIndex, item);
              for (int i = 0; i < _elements.length; i++) _elements[i].order = i;
            });
          },
          itemBuilder: (ctx, i) {
            final el = _elements[i];
            final typeColor = el.type == 'header' ? Colors.green
                : el.type == 'field' ? Colors.blue
                : el.type == 'divider' ? Colors.grey
                : el.type == 'footer' ? Colors.orange
                : Colors.purple;

            return Container(
              key: ValueKey(el.id),
              margin: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showElementProperties(i),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: el.visible
                          ? theme.cardTheme.color
                          : theme.colorScheme.onSurface.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: theme.colorScheme.onSurface.withOpacity(0.08)),
                    ),
                    child: Row(children: [
                      Icon(Icons.drag_indicator_rounded, size: 18,
                          color: theme.colorScheme.onSurface.withOpacity(0.2)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: typeColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(_typeIcon(el.type), size: 16, color: typeColor),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(el.label, style: TextStyle(
                              fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600,
                              color: el.visible ? null : theme.colorScheme.onSurface.withOpacity(0.3))),
                          Text(_typeLabel(el.type), style: TextStyle(
                              fontFamily: 'Cairo', fontSize: 10,
                              color: theme.colorScheme.onSurface.withOpacity(0.4))),
                        ]),
                      ),
                      IconButton(
                        icon: Icon(el.visible ? Icons.visibility : Icons.visibility_off,
                            size: 18, color: el.visible ? AppTheme.primary : Colors.grey),
                        onPressed: () => setState(() => el.visible = !el.visible),
                        visualDensity: VisualDensity.compact,
                      ),
                      Icon(Icons.chevron_left, size: 16,
                          color: theme.colorScheme.onSurface.withOpacity(0.2)),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _buildPreviewTab(ThemeData theme) {
    final html = _previewHTML();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
          ),
          child: _HtmlPreviewWidget(html: html),
        ),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 46, child: OutlinedButton.icon(
          onPressed: () async {
            final sampleData = ReceiptData(
              subscriberName: 'محمد أحمد علي', phoneNumber: '07901234567',
              packageName: 'الباقة الذهبية', packagePrice: 50000,
              paidAmount: 50000, remainingAmount: 0, debtAmount: 0,
              expiryDate: '2026-12-31', operationType: 'activation',
            );
            try {
              await ReceiptPrinter.printReceipt(data: sampleData, htmlTemplate: _generateHTML());
            } catch (e) {
              if (mounted) AppSnackBar.error(context, 'فشل في الطباعة التجريبية');
            }
          },
          icon: const Icon(Icons.print_rounded, size: 18),
          label: const Text('تجربة الطباعة',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Element Properties Bottom Sheet
// ─────────────────────────────────────────────────────────

class _ElementPropertiesSheet extends StatefulWidget {
  final _InvoiceElement element;
  final Map<String, String> variableOptions;
  final List<String> fontSizes;
  final ValueChanged<_InvoiceElement> onUpdate;
  final VoidCallback onDelete;

  const _ElementPropertiesSheet({
    required this.element, required this.variableOptions,
    required this.fontSizes, required this.onUpdate, required this.onDelete,
  });

  @override
  State<_ElementPropertiesSheet> createState() => _ElementPropertiesSheetState();
}

class _ElementPropertiesSheetState extends State<_ElementPropertiesSheet> {
  late _InvoiceElement _el;
  late TextEditingController _labelCtrl;
  late TextEditingController _contentCtrl;

  @override
  void initState() {
    super.initState();
    _el = widget.element;
    _labelCtrl = TextEditingController(text: _el.label);
    _contentCtrl = TextEditingController(text: _el.content);
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _update() {
    _el.label = _labelCtrl.text;
    _el.content = _contentCtrl.text;
    widget.onUpdate(_el);
  }

  Future<String?> _pickColor(String current) async {
    final colors = [
      '#ffffff', '#f9fafb', '#1f2937', '#111827', '#000000',
      '#10b981', '#047857', '#059669', '#14b8a6', '#0d9488',
      '#3b82f6', '#2563eb', '#6366f1', '#8b5cf6',
      '#ef4444', '#dc2626', '#f59e0b', '#f97316',
      '#e5e7eb', '#d1d5db', '#9ca3af', '#6b7280', '#374151',
    ];
    return showDialog<String>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('اختر لون', style: TextStyle(fontFamily: 'Cairo')),
        content: Wrap(
          spacing: 8, runSpacing: 8,
          children: colors.map((c) {
            final parsed = Color(int.parse('FF${c.replaceAll('#', '')}', radix: 16));
            return GestureDetector(
              onTap: () => Navigator.pop(dlg, c),
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: parsed, borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: c == current ? AppTheme.primary : Colors.grey.shade300,
                    width: c == current ? 2 : 1),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isField = _el.type == 'field';
    final isDivider = _el.type == 'divider';
    final hasContent = _el.type == 'header' || _el.type == 'footer' || _el.type == 'text';

    return _BottomSheet(
      title: 'خصائص العنصر',
      icon: Icons.tune_rounded,
      children: [
        _PropRow(label: 'العنوان', child: TextField(
          controller: _labelCtrl,
          onChanged: (_) => _update(),
          decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
        )),

        if (hasContent)
          _PropRow(label: 'المحتوى', child: TextField(
            controller: _contentCtrl,
            onChanged: (_) => _update(),
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
          )),

        if (isField)
          _PropRow(label: 'المتغير', child: DropdownButton<String>(
            value: widget.variableOptions.keys.contains(_el.variable) ? _el.variable : null,
            hint: Text(_el.variable, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
            isExpanded: true, isDense: true,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: theme.colorScheme.onSurface),
            items: widget.variableOptions.entries.map((e) =>
                DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
            onChanged: (v) {
              if (v != null) setState(() { _el.variable = v; _update(); });
            },
          )),

        if (!isDivider) ...[
          _PropRow(label: 'حجم الخط', child: DropdownButton<String>(
            value: widget.fontSizes.contains(_el.fontSize) ? _el.fontSize : '14px',
            isExpanded: true, isDense: true,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: theme.colorScheme.onSurface),
            items: widget.fontSizes.map((s) =>
                DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) {
              if (v != null) setState(() { _el.fontSize = v; _update(); });
            },
          )),

          _PropRow(label: 'اللون', child: Row(children: [
            _ColorDot(color: _el.color, onTap: () async {
              final c = await _pickColor(_el.color);
              if (c != null) setState(() { _el.color = c; _update(); });
            }),
            const SizedBox(width: 8),
            Text(_el.color, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          ])),

          _PropRow(label: 'المحاذاة', child: Row(children: [
            _AlignBtn(icon: Icons.format_align_right, active: _el.align == 'right',
                onTap: () => setState(() { _el.align = 'right'; _update(); })),
            const SizedBox(width: 4),
            _AlignBtn(icon: Icons.format_align_center, active: _el.align == 'center',
                onTap: () => setState(() { _el.align = 'center'; _update(); })),
            const SizedBox(width: 4),
            _AlignBtn(icon: Icons.format_align_left, active: _el.align == 'left',
                onTap: () => setState(() { _el.align = 'left'; _update(); })),
          ])),
        ],

        if (isDivider)
          _PropRow(label: 'نمط الخط', child: DropdownButton<String>(
            value: _el.dividerStyle, isExpanded: true, isDense: true,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13, color: theme.colorScheme.onSurface),
            items: const [
              DropdownMenuItem(value: 'solid', child: Text('متصل')),
              DropdownMenuItem(value: 'dashed', child: Text('متقطع')),
              DropdownMenuItem(value: 'dotted', child: Text('منقط')),
              DropdownMenuItem(value: 'double', child: Text('مزدوج')),
            ],
            onChanged: (v) {
              if (v != null) setState(() { _el.dividerStyle = v; _update(); });
            },
          )),

        if (isDivider)
          _PropRow(label: 'اللون', child: Row(children: [
            _ColorDot(color: _el.color, onTap: () async {
              final c = await _pickColor(_el.color);
              if (c != null) setState(() { _el.color = c; _update(); });
            }),
            const SizedBox(width: 8),
            Text(_el.color, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
          ])),

        const SizedBox(height: 12),
        SizedBox(width: double.infinity, height: 44, child: ElevatedButton.icon(
          onPressed: widget.onDelete,
          icon: const Icon(Icons.delete_rounded, size: 18),
          label: const Text('حذف العنصر', style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
        )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────

class _BottomSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _BottomSheet({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4, margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontFamily: 'Cairo', fontSize: 16,
                fontWeight: FontWeight.w700)),
          ]),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ]),
    );
  }
}

class _PropRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _PropRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
        const SizedBox(height: 4),
        child,
      ]),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final String color;
  final VoidCallback onTap;
  const _ColorDot({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final parsed = Color(int.parse('FF${color.replaceAll('#', '')}', radix: 16));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: parsed, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
      ),
    );
  }
}

class _AlignBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _AlignBtn({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppTheme.primary.withOpacity(0.3)
              : Colors.grey.shade300),
        ),
        child: Icon(icon, size: 18, color: active ? AppTheme.primary : Colors.grey),
      ),
    );
  }
}

class _LayoutToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _LayoutToggle({required this.label, required this.icon,
      required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? AppTheme.primary : Colors.grey.shade400),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: active ? AppTheme.primary : Colors.grey),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 12,
              fontWeight: FontWeight.w700,
              color: active ? AppTheme.primary : Colors.grey)),
        ]),
      ),
    );
  }
}

class _AddBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _AddBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.primary.withOpacity(0.15)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: AppTheme.primary),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10,
                fontWeight: FontWeight.w600, color: AppTheme.primary)),
          ]),
        ),
      ),
    );
  }
}

class _HtmlPreviewWidget extends StatelessWidget {
  final String html;
  const _HtmlPreviewWidget({required this.html});

  @override
  Widget build(BuildContext context) {
    final elements = _parseSimpleHTML(html);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: elements,
      ),
    );
  }

  List<Widget> _parseSimpleHTML(String html) {
    final widgets = <Widget>[];
    final divRegex = RegExp(r'<div[^>]*style="([^"]*)"[^>]*>(.*?)</div>', dotAll: true);
    final hrRegex = RegExp(r'<hr[^>]*style="([^"]*)"[^>]*/?>');
    final h1Regex = RegExp(r'<h1[^>]*style="([^"]*)"[^>]*>(.*?)</h1>', dotAll: true);

    final allTags = RegExp(r'(<div[^>]*>.*?</div>|<hr[^>]*/>)', dotAll: true);

    for (final match in allTags.allMatches(html)) {
      final tag = match.group(0) ?? '';

      final hr = hrRegex.firstMatch(tag);
      if (hr != null) {
        final style = hr.group(1) ?? '';
        final colorMatch = RegExp(r'border-top:[^;]*\s(#[0-9a-fA-F]{3,6})').firstMatch(style);
        final color = _parseColor(colorMatch?.group(1) ?? '#e5e7eb');
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(color: color, thickness: 2),
        ));
        continue;
      }

      final div = divRegex.firstMatch(tag);
      if (div != null) {
        final style = div.group(1) ?? '';
        final content = div.group(2) ?? '';

        final align = _extractAlign(style);
        final color = _extractColor(style);
        final fontSize = _extractFontSize(style);
        final isBorderTop = style.contains('border-top');

        final h1 = h1Regex.firstMatch(content);
        if (h1 != null) {
          final h1Style = h1.group(1) ?? '';
          final h1Text = h1.group(2) ?? '';
          final h1Color = _extractColor(h1Style);
          final h1Size = _extractFontSize(h1Style);
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(h1Text,
              textAlign: align, textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: h1Size, fontWeight: FontWeight.w700,
                  color: h1Color, fontFamily: 'Cairo')),
          ));
          continue;
        }

        final cleanContent = content
            .replaceAll(RegExp(r'<strong>(.*?)</strong>'), r'$1')
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .trim();

        if (cleanContent.isNotEmpty) {
          if (isBorderTop) {
            widgets.add(Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Divider(color: color, thickness: 2),
            ));
          }
          final hasBold = content.contains('<strong>');
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(cleanContent,
              textAlign: align, textDirection: TextDirection.rtl,
              style: TextStyle(fontSize: fontSize, color: color,
                  fontWeight: hasBold ? FontWeight.w600 : FontWeight.normal,
                  fontFamily: 'Cairo')),
          ));
        }
      }
    }

    if (widgets.isEmpty) {
      widgets.add(const Padding(
        padding: EdgeInsets.all(20),
        child: Text('أضف عناصر لبدء تصميم الفاتورة',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
      ));
    }

    return widgets;
  }

  TextAlign _extractAlign(String style) {
    if (style.contains('text-align:center') || style.contains('text-align: center')) return TextAlign.center;
    if (style.contains('text-align:left') || style.contains('text-align: left')) return TextAlign.left;
    return TextAlign.right;
  }

  Color _extractColor(String style) {
    final m = RegExp(r'color:\s*(#[0-9a-fA-F]{3,6})').firstMatch(style);
    return _parseColor(m?.group(1) ?? '#1f2937');
  }

  double _extractFontSize(String style) {
    final m = RegExp(r'font-size:\s*(\d+)px').firstMatch(style);
    return double.tryParse(m?.group(1) ?? '14') ?? 14;
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return const Color(0xFF1f2937);
    }
  }
}

class _PresetTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PresetTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: accent.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withOpacity(0.16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 11.5,
                              color: theme.colorScheme.onSurface.withOpacity(0.55))),
                    ],
                  ),
                ),
                Icon(Icons.chevron_left_rounded,
                    color: accent, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
