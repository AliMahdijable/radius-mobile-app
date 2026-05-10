import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/receipt_printer.dart' as rp;
import '../models/print_template_model.dart';
import '../providers/print_templates_provider.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/live_receipt_preview.dart';
import '../widgets/receipt_design_panel.dart';

/// Editor for a single print template (POS or A4).
///
/// Three sections in one form:
///   1. Settings — name, paper type, active flag
///   2. HTML — multiline TextField + variable chip picker (insert at cursor)
///   3. Preview — uses ReceiptPrinter with sample data to render the
///      current draft so the user can verify before saving
class PrintTemplateEditorScreen extends ConsumerStatefulWidget {
  final PrintTemplateModel initial;
  const PrintTemplateEditorScreen({super.key, required this.initial});

  @override
  ConsumerState<PrintTemplateEditorScreen> createState() =>
      _PrintTemplateEditorScreenState();
}

class _PrintTemplateEditorScreenState
    extends ConsumerState<PrintTemplateEditorScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _htmlCtrl;
  late String _type;
  late bool _isActive;
  late ReceiptDesign _design;
  bool _saving = false;
  String _previewHtml = '';

  bool get _isNew => widget.initial.id == null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial.templateName);
    _htmlCtrl = TextEditingController(text: widget.initial.content);
    _previewHtml = widget.initial.content;
    _htmlCtrl.addListener(_onHtmlChanged);
    _type = widget.initial.templateType;
    _isActive = widget.initial.isActive;
    // قراءة التصميم من template_data (JSON). لو ما موجود/معطوب → افتراضيات.
    _design = _parseDesign(widget.initial.templateData);
  }

  @override
  void dispose() {
    _htmlCtrl.removeListener(_onHtmlChanged);
    _nameCtrl.dispose();
    _htmlCtrl.dispose();
    super.dispose();
  }

  void _onHtmlChanged() {
    // الـTextEditingController يطلق notify كل ضربة مفتاح. نسحب القيمة
    // ونضعها في state عشان المعاينة تعرف تعيد البناء (debounce داخلها).
    if (_previewHtml != _htmlCtrl.text) {
      setState(() => _previewHtml = _htmlCtrl.text);
    }
  }

  static ReceiptDesign _parseDesign(String? raw) {
    if (raw == null || raw.trim().isEmpty) return ReceiptDesign();
    try {
      final m = jsonDecode(raw);
      if (m is Map<String, dynamic>) return ReceiptDesign.fromJson(m);
    } catch (_) {}
    return ReceiptDesign();
  }

  Future<void> _preview() async {
    if (_htmlCtrl.text.trim().isEmpty) {
      AppSnackBar.error(context, 'أضف محتوى HTML أولاً');
      return;
    }
    final sample = const rp.ReceiptData(
      subscriberName: 'محمد أحمد',
      phoneNumber: '07712345678',
      packageName: 'باقة أساسية',
      packagePrice: 25000,
      paidAmount: 25000,
      remainingAmount: 0,
      debtAmount: 0,
      expiryDate: '2026-12-31',
      operationType: 'activation',
    );
    try {
      await rp.ReceiptPrinter.printWithTemplate(
        htmlTemplate: _htmlCtrl.text,
        data: sample,
        design: _design,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, 'فشل المعاينة: $e');
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      AppSnackBar.error(context, 'اسم القالب مطلوب');
      return;
    }
    if (_htmlCtrl.text.trim().isEmpty) {
      AppSnackBar.error(context, 'محتوى الـHTML مطلوب');
      return;
    }
    setState(() => _saving = true);
    final updated = widget.initial.copyWith(
      templateType: _type,
      templateName: _nameCtrl.text.trim(),
      content: _htmlCtrl.text,
      templateData: jsonEncode(_design.toJson()),
      isActive: _isActive,
    );
    final notifier = ref.read(printTemplatesProvider.notifier);
    final ok = _isNew
        ? await notifier.createTemplate(updated)
        : await notifier.updateTemplate(widget.initial.id!, updated);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      AppSnackBar.success(context, _isNew ? 'تم إنشاء القالب' : 'تم الحفظ');
      Navigator.pop(context);
    } else {
      AppSnackBar.error(context, 'فشل الحفظ');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isNew ? 'قالب جديد' : 'تحرير القالب',
          style: const TextStyle(
              fontFamily: 'Cairo', fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'معاينة',
            icon: const Icon(LucideIcons.eye, size: 20),
            onPressed: _preview,
          ),
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.check, size: 18),
            label: const Text(
              'حفظ',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── معاينة مباشرة (في الأعلى — قابلة للطي) ──
          LiveReceiptPreview(
            htmlTemplate: _previewHtml,
            design: _design,
            templateType: _type,
            sampleData: const rp.ReceiptData(
              subscriberName: 'محمد أحمد',
              phoneNumber: '07712345678',
              packageName: 'باقة أساسية',
              packagePrice: 25000,
              paidAmount: 25000,
              remainingAmount: 0,
              debtAmount: 0,
              expiryDate: '2026-12-31',
              operationType: 'activation',
            ),
          ),
          const SizedBox(height: 14),

          // ── إعدادات أساسية ──
          _section(
            title: 'الإعدادات',
            icon: LucideIcons.settings,
            child: Column(
              children: [
                TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم القالب',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _type,
                      decoration: const InputDecoration(
                        labelText: 'مقاس الورق',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'pos',
                            child: Text('POS 80mm (وصل حراري)')),
                        DropdownMenuItem(
                            value: 'a4', child: Text('A4 (ورق عادي)')),
                      ],
                      onChanged: (v) {
                        if (v == null || v == _type) return;
                        // لو الـHTML الحالي لا يزال هو القالب الافتراضي للنوع
                        // القديم، نُبدّله بافتراضي النوع الجديد تلقائياً. لو
                        // المستخدم حرّر شيئاً (لا يطابق الافتراضي بالضبط)، نحترم
                        // اختياره ونتركه كما هو.
                        final currentTrimmed = _htmlCtrl.text.trim();
                        final oldDefault = _type == 'pos'
                            ? PrintTemplateModel.defaultPosTemplate().trim()
                            : PrintTemplateModel.defaultA4Template().trim();
                        setState(() {
                          _type = v;
                          if (currentTrimmed == oldDefault) {
                            final newDefault = v == 'pos'
                                ? PrintTemplateModel.defaultPosTemplate()
                                : PrintTemplateModel.defaultA4Template();
                            _htmlCtrl.text = newDefault;
                            _previewHtml = newDefault;
                          }
                        });
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'القالب النشط',
                    style: TextStyle(
                        fontFamily: 'Cairo', fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'استخدم هذا القالب عند طباعة الوصولات',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11.5,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  value: _isActive,
                  activeThumbColor: AppTheme.successColor,
                  onChanged: (v) => setState(() => _isActive = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── التصميم البصري (5 أقسام قابلة للطي) ──
          _section(
            title: 'التصميم البصري',
            icon: LucideIcons.brush,
            subtitle: 'عناصر مرئية، ألوان، خطوط، هوامش — نفس ما هو على الويب',
            child: ReceiptDesignPanel(
              value: _design,
              templateType: _type,
              onChanged: (d) => setState(() => _design = d),
            ),
          ),
          const SizedBox(height: 14),

          // ─── HTML editor + variables — مخفي بناءً على طلب المستخدم.
          //     التصميم البصري + المعاينة كافيين. لو احتجت تعود لتحرير
          //     الـHTML الخام، ارجع لـcommit 9353ca6.

          // ── أزرار المعاينة + الحفظ ──
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _preview,
                icon: const Icon(LucideIcons.eye, size: 16),
                label: const Text(
                  'معاينة',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(LucideIcons.save, size: 16),
                label: const Text(
                  'حفظ',
                  style: TextStyle(
                      fontFamily: 'Cairo', fontWeight: FontWeight.w800),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    String? subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900),
            ),
            const Spacer(),
            if (trailing != null) trailing,
          ]),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
