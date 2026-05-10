import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/theme/app_theme.dart';
import '../models/print_template_model.dart';
import '../providers/auth_provider.dart';
import '../providers/print_templates_provider.dart';

/// قوالب الطباعة — قالب واحد لكل مدير (بناءً على طلب المستخدم).
/// السلوك:
///   • أول مرة: ينشئ قالب POS افتراضي ثم يفتح المحرّر مباشرة.
///   • لاحقاً: يفتح القالب النشط أو الأول مباشرة.
///   • أكثر من قالب موجود (من نسخة سابقة): يعرضها كقائمة بسيطة.
class PrintTemplatesScreen extends ConsumerStatefulWidget {
  const PrintTemplatesScreen({super.key});

  @override
  ConsumerState<PrintTemplatesScreen> createState() =>
      _PrintTemplatesScreenState();
}

class _PrintTemplatesScreenState extends ConsumerState<PrintTemplatesScreen> {
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadAndMaybeOpen);
  }

  Future<void> _loadAndMaybeOpen() async {
    await ref.read(printTemplatesProvider.notifier).loadTemplates();
    if (!mounted || _autoOpened) return;
    final state = ref.read(printTemplatesProvider);

    // مدير ليس عنده قوالب → ننشئ POS افتراضي ونفتحه مباشرة.
    if (state.templates.isEmpty) {
      _autoOpened = true;
      final adminId = ref.read(authProvider).user?.id ?? '';
      final draft = PrintTemplateModel(
        adminId: adminId,
        templateType: 'pos',
        templateName: 'قالب الطباعة',
        content: PrintTemplateModel.defaultPosTemplate(),
        isActive: true,
      );
      if (!mounted) return;
      context.push('/print-template-editor', extra: draft);
      return;
    }

    // قالب واحد فقط → افتحه مباشرة بدون list intermediate.
    if (state.templates.length == 1) {
      _autoOpened = true;
      if (!mounted) return;
      context.push('/print-template-editor', extra: state.templates.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(printTemplatesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'قوالب الطباعة',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : state.templates.length <= 1
              // 0 أو 1 قالب → نعرض شاشة انتظار، الـauto-open يأخذ المستخدم
              ? _loadingTransition(theme)
              : _multipleTemplates(state.templates),
    );
  }

  Widget _loadingTransition(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.fileText,
              size: 36,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          const Text(
            'جارٍ فتح القالب...',
            style: TextStyle(
                fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }

  /// لو فيه أكثر من قالب (متبقّي من نسخة سابقة)، نعرضها لتسهيل الاختيار/الحذف.
  Widget _multipleTemplates(List<PrintTemplateModel> templates) {
    final theme = Theme.of(context);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
      itemCount: templates.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final t = templates[i];
        final isPos = t.templateType == 'pos';
        return Material(
          color: theme.cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/print-template-editor', extra: t),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isPos ? LucideIcons.receipt : LucideIcons.fileText,
                      color: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.templateName,
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isPos ? 'POS 80mm' : 'A4',
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (t.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.successColor
                                    .withValues(alpha: 0.12),
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
                  IconButton(
                    icon: const Icon(LucideIcons.trash2, size: 18),
                    color: Colors.red.shade700,
                    onPressed: () => _confirmDelete(t),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
            child:
                const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'حذف',
              style:
                  TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(printTemplatesProvider.notifier).deleteTemplate(t.id!);
  }
}
