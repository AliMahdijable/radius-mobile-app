import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/app_theme.dart';
import '../models/print_template_model.dart';
import '../providers/auth_provider.dart';
import '../providers/print_templates_provider.dart';
import '../widgets/app_snackbar.dart';

/// Print templates list — simple Card-per-template view with toggle-active
/// switches and an FAB to create a new template. Tapping a card opens the
/// editor screen at /print-template-editor.
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
    Future.microtask(() {
      ref.read(printTemplatesProvider.notifier).loadTemplates();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(printTemplatesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'قوالب الطباعة',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(LucideIcons.refreshCw, size: 20),
            onPressed: () =>
                ref.read(printTemplatesProvider.notifier).loadTemplates(),
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.templates.isEmpty
              ? _empty(context)
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(printTemplatesProvider.notifier).loadTemplates(),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                    itemCount: state.templates.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final t = state.templates[i];
                      return _TemplateCard(
                        template: t,
                        onToggle: () => _toggleActive(t),
                        onEdit: () => _openEditor(t),
                        onDelete: () => _confirmDelete(t),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createNew,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(LucideIcons.plus, size: 18),
        label: const Text(
          'قالب جديد',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.fileText,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.3)),
            const SizedBox(height: 14),
            const Text(
              'لا توجد قوالب طباعة بعد',
              style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w800,
                  fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'اضغط "قالب جديد" لإنشاء قالب POS أو A4',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(PrintTemplateModel t) async {
    if (t.id == null) return;
    final ok =
        await ref.read(printTemplatesProvider.notifier).toggleActive(t.id!);
    if (!mounted) return;
    if (!ok) AppSnackBar.error(context, 'فشل تبديل الحالة');
  }

  Future<void> _confirmDelete(PrintTemplateModel t) async {
    if (t.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'حذف القالب',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
        content: Text(
          'هل تريد حذف "${t.templateName}" نهائياً؟',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف',
                style:
                    TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final done =
        await ref.read(printTemplatesProvider.notifier).deleteTemplate(t.id!);
    if (!mounted) return;
    if (done) {
      AppSnackBar.success(context, 'تم الحذف');
    } else {
      AppSnackBar.error(context, 'فشل الحذف');
    }
  }

  void _openEditor(PrintTemplateModel t) {
    context.push('/print-template-editor', extra: t);
  }

  void _createNew() {
    final adminId = ref.read(authProvider).user?.id ?? '';
    final draft = PrintTemplateModel(
      adminId: adminId,
      templateType: 'pos',
      templateName: 'قالب جديد',
      content: PrintTemplateModel.defaultPosTemplate(),
      isActive: false,
    );
    context.push('/print-template-editor', extra: draft);
  }
}

class _TemplateCard extends StatelessWidget {
  final PrintTemplateModel template;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TemplateCard({
    required this.template,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPos = template.templateType == 'pos';
    final accent = isPos ? AppTheme.primary : Colors.indigo;

    return Material(
      color: theme.cardTheme.color ?? Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPos ? LucideIcons.receipt : LucideIcons.fileText,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.templateName,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: accent.withValues(alpha: 0.28)),
                        ),
                        child: Text(
                          isPos ? 'POS 80mm' : 'A4',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (template.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.successColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'نشط',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.successColor,
                            ),
                          ),
                        ),
                    ]),
                  ],
                ),
              ),
              Switch(
                value: template.isActive,
                onChanged: (_) => onToggle(),
                activeThumbColor: AppTheme.successColor,
              ),
              IconButton(
                icon: const Icon(LucideIcons.trash2, size: 18),
                color: Colors.red.shade700,
                tooltip: 'حذف',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
