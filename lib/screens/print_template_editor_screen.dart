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

/// محرّر القالب — مرآة بصرية لـclient-v2/PrintTemplates.tsx:
///   • هيدر العنوان + الوصف
///   • معاينة لايف قابلة للطي (دائماً فوق)
///   • شريط تابات أفقي قابل للسحب (الورق / الخطوط / التخطيط / الألوان /
///     الأقسام / المحتوى)
///   • محتوى التاب الحالي
///   • شريط أكشن سفلي (حفظ + معاينة طباعة)
class PrintTemplateEditorScreen extends ConsumerStatefulWidget {
  final PrintTemplateModel initial;
  const PrintTemplateEditorScreen({super.key, required this.initial});

  @override
  ConsumerState<PrintTemplateEditorScreen> createState() =>
      _PrintTemplateEditorScreenState();
}

/// أقسام الشاشة بترتيب الـtabs — الخمسة الأولى من ReceiptDesign، السادسة
/// "المحتوى" مخصصة للاسم/الفعّالية/إعادة التعيين/نوع الورق.
enum _Tab { paper, fonts, layout, colors, sections, content }

const Map<_Tab, ({IconData icon, String label})> _kTabMeta = {
  _Tab.paper:    (icon: LucideIcons.fileText,       label: 'الورق'),
  _Tab.fonts:    (icon: LucideIcons.type,           label: 'الخطوط'),
  _Tab.layout:   (icon: LucideIcons.layoutDashboard, label: 'التخطيط'),
  _Tab.colors:   (icon: LucideIcons.palette,        label: 'الألوان'),
  _Tab.sections: (icon: LucideIcons.eye,            label: 'الأقسام'),
  _Tab.content:  (icon: LucideIcons.settings,       label: 'المحتوى'),
};

class _PrintTemplateEditorScreenState
    extends ConsumerState<PrintTemplateEditorScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _htmlCtrl;
  late String _type;
  late bool _isActive;
  late ReceiptDesign _design;
  String _previewHtml = '';
  bool _saving = false;
  _Tab _tab = _Tab.paper;

  bool get _isNew => widget.initial.id == null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initial.templateName);
    final initialContent = _correctMismatchedContent(
      widget.initial.templateType,
      widget.initial.content,
    );
    _htmlCtrl = TextEditingController(text: initialContent);
    _previewHtml = initialContent;
    _htmlCtrl.addListener(_onHtmlChanged);
    _type = widget.initial.templateType;
    _isActive = widget.initial.isActive;
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

  /// إصلاح القوالب القديمة: لو النوع 'a4' لكن المحتوى يطابق defaultPosTemplate
  /// بالضبط، بدّل تلقائياً (والعكس صحيح).
  static String _correctMismatchedContent(String type, String content) {
    final trimmed = content.trim();
    final posDefault = PrintTemplateModel.defaultPosTemplate().trim();
    final a4Default = PrintTemplateModel.defaultA4Template().trim();
    if (type == 'a4' && trimmed == posDefault) {
      return PrintTemplateModel.defaultA4Template();
    }
    if (type == 'pos' && trimmed == a4Default) {
      return PrintTemplateModel.defaultPosTemplate();
    }
    return content;
  }

  Future<void> _resetTemplateContent() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'إعادة تعيين القالب',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
        content: Text(
          'سيتم استبدال محتوى HTML بقالب ${_type == 'pos' ? 'POS 80mm' : 'A4'} '
          'الافتراضي. يُحفظ التصميم البصري (الألوان، الخطوط، الهوامش).\n\n'
          'هل تريد المتابعة؟',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'إعادة تعيين',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final newHtml = _type == 'pos'
        ? PrintTemplateModel.defaultPosTemplate()
        : PrintTemplateModel.defaultA4Template();
    setState(() {
      _htmlCtrl.text = newHtml;
      _previewHtml = newHtml;
    });
  }

  static const rp.ReceiptData _sampleData = rp.ReceiptData(
    subscriberName: 'sample.user@hst',
    firstName: 'محمد أحمد',
    phoneNumber: '07712345678',
    packageName: 'باقة أساسية',
    packagePrice: 25000,
    paidAmount: 25000,
    remainingAmount: 0,
    debtAmount: 0,
    expiryDate: '2026-12-31 18:30:00',
    operationType: 'activation',
    shopName: 'مكتب الإنترنت',
    shopAddress: 'بغداد',
    shopPhone: '07712345678',
    managerName: 'admin@hst',
  );

  Future<void> _printPreview() async {
    try {
      await rp.ReceiptPrinter.printReceipt(
        data: _sampleData,
        htmlTemplate: _htmlCtrl.text,
        design: _design,
        type: _type,
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

  void _onTypeChanged(String? v) {
    if (v == null || v == _type) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'تصميم الوصل',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── اختيار نوع الورقة — بارز بالأعلى مثل الويب ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: _PaperTypePicker(
              current: _type,
              onChanged: _onTypeChanged,
            ),
          ),

          // ── معاينة لايف (دائماً فوق، قابلة للطي) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LiveReceiptPreview(
              htmlTemplate: _htmlCtrl.text,
              design: _design,
              templateType: _type,
              sampleData: _sampleData,
            ),
          ),
          const SizedBox(height: 10),

          // ── شريط التابات ──
          _TabBar(
            current: _tab,
            onChanged: (t) => setState(() => _tab = t),
          ),
          const SizedBox(height: 8),

          // ── محتوى التاب الحالي ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              child: _buildTabContent(theme),
            ),
          ),

          // ── شريط أكشن سفلي ──
          _BottomActions(
            saving: _saving,
            onPreview: _printPreview,
            onSave: _save,
          ),
        ],
      ),
    );
  }

  // ─── محتوى التابات ─────────────────────────────────────────────

  Widget _buildTabContent(ThemeData theme) {
    if (_tab == _Tab.content) return _contentTab(theme);
    return ReceiptDesignSectionPanel(
      section: _toDesignSection(_tab),
      value: _design,
      templateType: _type,
      onChanged: (d) => setState(() => _design = d),
    );
  }

  DesignSection _toDesignSection(_Tab t) => switch (t) {
        _Tab.paper => DesignSection.paper,
        _Tab.fonts => DesignSection.fonts,
        _Tab.layout => DesignSection.layout,
        _Tab.colors => DesignSection.colors,
        _Tab.sections => DesignSection.sections,
        _Tab.content => DesignSection.paper, // غير مستخدم
      };

  Widget _contentTab(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // اسم القالب
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'اسم القالب',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),

        // نشط/معطّل — (نوع الورقة موجود بالأعلى دائماً، ما نكرّره هنا)
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'القالب النشط',
            style: TextStyle(
                fontFamily: 'Cairo', fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'يُستخدم عند طباعة الوصولات',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          value: _isActive,
          activeThumbColor: AppTheme.successColor,
          onChanged: (v) => setState(() => _isActive = v),
        ),
        const SizedBox(height: 14),

        // إعادة تعيين القالب
        OutlinedButton.icon(
          onPressed: _resetTemplateContent,
          icon: const Icon(LucideIcons.rotateCcw, size: 16),
          label: Text(
            'إعادة تعيين محتوى القالب لـ${_type == 'pos' ? 'POS' : 'A4'} الافتراضي',
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w700,
                fontSize: 12),
            textAlign: TextAlign.center,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            foregroundColor: AppTheme.primary,
            side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.35)),
          ),
        ),
      ],
    );
  }
}

/// اختيار نوع الورقة (A4 / POS) — كرتان بارزتان بالأعلى مثل الويب.
class _PaperTypePicker extends StatelessWidget {
  final String current; // 'pos' | 'a4'
  final ValueChanged<String?> onChanged;
  const _PaperTypePicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _card(
            theme,
            value: 'a4',
            icon: LucideIcons.fileText,
            title: 'A4',
            subtitle: 'ورق طباعة عادي',
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _card(
            theme,
            value: 'pos',
            icon: LucideIcons.receipt,
            title: 'POS',
            subtitle: 'حراري قابل للتخصيص',
          ),
        ),
      ],
    );
  }

  Widget _card(
    ThemeData theme, {
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final active = value == current;
    return Material(
      color: active
          ? AppTheme.primary.withValues(alpha: 0.10)
          : (theme.cardTheme.color ?? Colors.white),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onChanged(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? AppTheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.18),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 22,
                  color: active
                      ? AppTheme.primary
                      : theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        color: active
                            ? AppTheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 10.5,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Icon(LucideIcons.circleCheck,
                    size: 18, color: AppTheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط التابات الأفقي القابل للسحب — مماثل لتصميم client-v2.
class _TabBar extends StatelessWidget {
  final _Tab current;
  final ValueChanged<_Tab> onChanged;
  const _TabBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.15)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        itemCount: _Tab.values.length,
        itemBuilder: (_, i) {
          final t = _Tab.values[i];
          final meta = _kTabMeta[t]!;
          final active = t == current;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Material(
              color: active
                  ? AppTheme.primary
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(t),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        meta.icon,
                        size: 15,
                        color: active
                            ? Colors.white
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        meta.label,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: active
                              ? Colors.white
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// شريط الأكشن السفلي — معاينة طباعة + حفظ.
class _BottomActions extends StatelessWidget {
  final bool saving;
  final VoidCallback onPreview;
  final VoidCallback onSave;

  const _BottomActions({
    required this.saving,
    required this.onPreview,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? Colors.white,
        border: Border(
          top: BorderSide(
            color:
                Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPreview,
                icon: const Icon(LucideIcons.printer, size: 16),
                label: const Text(
                  'طباعة المعاينة',
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
                onPressed: saving ? null : onSave,
                icon: saving
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
          ],
        ),
      ),
    );
  }
}
