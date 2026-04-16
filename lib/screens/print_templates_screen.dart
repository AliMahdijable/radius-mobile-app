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
    final isDark = theme.brightness == Brightness.dark;

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
                  // Info banner
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
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),

                  // Add buttons for missing types
                  if (!hasA4 || !hasPOS) ...[
                    Row(children: [
                      if (!hasA4)
                        Expanded(
                          child: _AddTemplateCard(
                            type: 'a4',
                            label: 'A4',
                            icon: Icons.description_rounded,
                            onTap: () => _openEditor(null, 'a4'),
                          ),
                        ),
                      if (!hasA4 && !hasPOS) const SizedBox(width: 10),
                      if (!hasPOS)
                        Expanded(
                          child: _AddTemplateCard(
                            type: 'pos',
                            label: 'POS',
                            icon: Icons.receipt_long_rounded,
                            onTap: () => _openEditor(null, 'pos'),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  // Existing templates
                  ...state.templates.map((t) => _TemplateCard(
                        template: t,
                        onEdit: () => _openEditor(t, t.templateType),
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
            style: TextStyle(
                fontFamily: 'Cairo',
                color: theme.colorScheme.onSurface.withOpacity(0.4))),
      ]),
    );
  }

  void _openEditor(PrintTemplateModel? existing, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _TemplateEditorPage(
          template: existing,
          templateType: type,
        ),
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
      packagePrice: 15000,
      paidAmount: 15000,
      remainingAmount: 0,
      debtAmount: 0,
      expiryDate: '2026-05-15',
      operationType: 'activation',
    );
    try {
      await ReceiptPrinter.printReceipt(data: sampleData, htmlTemplate: t.content);
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'فشل معاينة القالب');
    }
  }
}

class _AddTemplateCard extends StatelessWidget {
  final String type;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _AddTemplateCard({
    required this.type,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.primary.withOpacity(0.2),
            style: BorderStyle.solid,
          ),
        ),
        child: Column(children: [
          Icon(icon, size: 32, color: AppTheme.primary.withOpacity(0.5)),
          const SizedBox(height: 8),
          Text('إضافة قالب $label',
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppTheme.primary)),
        ]),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final PrintTemplateModel template;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onPreview;

  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isA4 = template.templateType == 'a4';
    final typeLabel = isA4 ? 'A4' : 'POS';
    final typeIcon = isA4 ? Icons.description_rounded : Icons.receipt_long_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(14),
        border: template.isActive
            ? Border.all(color: AppTheme.successColor.withOpacity(0.4), width: 1.5)
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (template.isActive ? AppTheme.successColor : Colors.grey)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(typeIcon, size: 22,
                    color: template.isActive ? AppTheme.successColor : Colors.grey),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(template.templateName,
                      style: const TextStyle(
                          fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w700)),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(typeLabel,
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 10,
                              fontWeight: FontWeight.w700, color: AppTheme.primary)),
                    ),
                    const SizedBox(width: 6),
                    if (template.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.successColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('نشط',
                            style: TextStyle(
                                fontFamily: 'Cairo', fontSize: 10,
                                fontWeight: FontWeight.w700, color: AppTheme.successColor)),
                      ),
                  ]),
                ]),
              ),
              Switch.adaptive(
                value: template.isActive,
                onChanged: (_) => onToggle(),
                activeColor: AppTheme.successColor,
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _ActionChip(icon: Icons.edit_rounded, label: 'تعديل', onTap: onEdit),
              const SizedBox(width: 8),
              _ActionChip(icon: Icons.visibility_rounded, label: 'معاينة', onTap: onPreview),
              const SizedBox(width: 8),
              _ActionChip(
                  icon: Icons.delete_outline_rounded,
                  label: 'حذف',
                  onTap: onDelete,
                  color: Colors.red),
            ]),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withOpacity(0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.w600, color: c)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Template Editor Page
// ─────────────────────────────────────────────────────────

class _TemplateEditorPage extends ConsumerStatefulWidget {
  final PrintTemplateModel? template;
  final String templateType;

  const _TemplateEditorPage({this.template, required this.templateType});

  @override
  ConsumerState<_TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends ConsumerState<_TemplateEditorPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _contentCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: widget.template?.templateName ??
            (widget.templateType == 'a4' ? 'قالب A4' : 'قالب POS'));
    _contentCtrl = TextEditingController(
        text: widget.template?.content ?? _defaultTemplate(widget.templateType));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  String _defaultTemplate(String type) {
    return '''<div style="text-align: center; padding: 20px; font-family: sans-serif; direction: rtl;">
  <h2 style="color: #1a7f64; margin-bottom: 10px;">وصل</h2>
  <hr style="border: 1px solid #1a7f64; margin-bottom: 15px;">
  <table style="width: 100%; border-collapse: collapse; text-align: right;">
    <tr><td style="padding: 6px; font-weight: bold;">رقم الفاتورة:</td><td style="padding: 6px;">{invoice_number}</td></tr>
    <tr><td style="padding: 6px; font-weight: bold;">التاريخ:</td><td style="padding: 6px;">{date}</td></tr>
    <tr><td colspan="2"><hr style="border: 0.5px solid #ddd;"></td></tr>
    <tr><td style="padding: 6px; font-weight: bold;">اسم المشترك:</td><td style="padding: 6px;">{subscriber_name}</td></tr>
    <tr><td style="padding: 6px; font-weight: bold;">رقم الهاتف:</td><td style="padding: 6px;">{phone_number}</td></tr>
    <tr><td style="padding: 6px; font-weight: bold;">الباقة:</td><td style="padding: 6px;">{package_name}</td></tr>
    <tr><td style="padding: 6px; font-weight: bold;">سعر الباقة:</td><td style="padding: 6px;">{package_price}</td></tr>
    <tr><td style="padding: 6px; font-weight: bold;">تاريخ الانتهاء:</td><td style="padding: 6px;">{expiry_date}</td></tr>
    <tr><td colspan="2"><hr style="border: 0.5px solid #ddd;"></td></tr>
    <tr><td style="padding: 6px; font-weight: bold;">المبلغ المدفوع:</td><td style="padding: 6px;">{paid_amount}</td></tr>
    <tr><td style="padding: 6px; font-weight: bold;">مبلغ الدين:</td><td style="padding: 6px;">{debt_amount}</td></tr>
    <tr><td style="padding: 6px; font-weight: bold;">المتبقي:</td><td style="padding: 6px;">{remaining_amount}</td></tr>
  </table>
  <hr style="border: 1px solid #1a7f64; margin-top: 15px;">
  <p style="color: #888; font-size: 11px; margin-top: 8px;">شكراً لكم</p>
</div>''';
  }

  void _insertVariable(String variable) {
    final text = _contentCtrl.text;
    final sel = _contentCtrl.selection;
    final pos = sel.isValid ? sel.baseOffset : text.length;
    final newText = text.substring(0, pos) + variable + text.substring(pos);
    _contentCtrl.text = newText;
    _contentCtrl.selection = TextSelection.collapsed(offset: pos + variable.length);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final content = _contentCtrl.text.trim();

    if (name.isEmpty || content.isEmpty) {
      AppSnackBar.warning(context, 'يرجى إدخال اسم القالب والمحتوى');
      return;
    }

    setState(() => _saving = true);

    final notifier = ref.read(printTemplatesProvider.notifier);
    bool ok;

    if (widget.template?.id != null) {
      ok = await notifier.updateTemplate(
        widget.template!.id!,
        widget.template!.copyWith(templateName: name, content: content),
      );
    } else {
      ok = await notifier.createTemplate(PrintTemplateModel(
        adminId: '',
        templateType: widget.templateType,
        templateName: name,
        content: content,
        isActive: true,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.template?.id != null;
    final typeLabel = widget.templateType == 'a4' ? 'A4' : 'POS';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing ? 'تعديل قالب $typeLabel' : 'إنشاء قالب $typeLabel',
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              tooltip: 'حفظ',
            ),
        ],
      ),
      body: Column(
        children: [
          // Template name
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _nameCtrl,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.left,
              decoration: const InputDecoration(
                labelText: 'اسم القالب',
                prefixIcon: Icon(Icons.label_outline, size: 20),
                isDense: true,
              ),
            ),
          ),

          // Variable chips
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: PrintTemplateModel.availableVariables.map((v) {
                final label = PrintTemplateModel.variableLabels[v] ?? v;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ActionChip(
                    avatar: const Icon(Icons.add, size: 14),
                    label: Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                    onPressed: () => _insertVariable(v),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),

          // HTML content editor
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                controller: _contentCtrl,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                  color: theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  hintText: 'محتوى القالب (HTML)...',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),

          // Save button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 20),
                label: Text(
                  _saving ? 'جاري الحفظ...' : 'حفظ القالب',
                  style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
