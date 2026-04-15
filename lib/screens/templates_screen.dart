import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/templates_provider.dart';
import '../providers/auth_provider.dart';
import '../models/template_model.dart';
import '../core/theme/app_theme.dart';

class TemplatesScreen extends ConsumerStatefulWidget {
  const TemplatesScreen({super.key});

  @override
  ConsumerState<TemplatesScreen> createState() => _TemplatesScreenState();
}

class _TemplatesScreenState extends ConsumerState<TemplatesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(templatesProvider.notifier).loadTemplates();
    });
  }

  void _showEditSheet(TemplateModel? template) {
    final nameController =
        TextEditingController(text: template?.templateName ?? '');
    final contentController =
        TextEditingController(text: template?.messageContent ?? '');
    String selectedType = template?.templateType ?? 'debt_reminder';
    final adminId = ref.read(authProvider).user?.id ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  template == null ? 'إنشاء قالب' : 'تعديل القالب',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 20),

                if (template == null) ...[
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(labelText: 'نوع القالب'),
                    items: [
                      'debt_reminder',
                      'expiry_warning',
                      'service_end',
                      'activation_notice',
                      'payment_confirmation',
                      'welcome_message',
                    ]
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(TemplateModel.getArabicType(t)),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setSheetState(() => selectedType = v ?? selectedType),
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم القالب',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: contentController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'محتوى الرسالة',
                    hintText: 'مرحبا {firstname}...',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Variables chips
                Text('المتغيرات المتاحة:',
                    style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: TemplateModel.availableVariables.map((v) {
                    return ActionChip(
                      label: Text(
                        TemplateModel.variableLabels[v] ?? v,
                        style: const TextStyle(fontSize: 11),
                      ),
                      avatar: const Icon(Icons.add, size: 14),
                      onPressed: () {
                        final text = contentController.text;
                        final selection = contentController.selection;
                        final newText = text.replaceRange(
                          selection.start,
                          selection.end,
                          v,
                        );
                        contentController.text = newText;
                        contentController.selection = TextSelection.collapsed(
                          offset: selection.start + v.length,
                        );
                      },
                    );
                  }).toList(),
                ),

                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        contentController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('يرجى ملء جميع الحقول')),
                      );
                      return;
                    }
                    final newTemplate = TemplateModel(
                      id: template?.id,
                      adminId: adminId,
                      templateType: template?.templateType ?? selectedType,
                      templateName: nameController.text,
                      messageContent: contentController.text,
                      isActive: template?.isActive ?? true,
                    );
                    final ok = await ref
                        .read(templatesProvider.notifier)
                        .saveTemplate(newTemplate);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content:
                            Text(ok ? 'تم حفظ القالب' : 'فشل حفظ القالب'),
                      ));
                    }
                  },
                  child: const Text('حفظ القالب'),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(templatesProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('قوالب الرسائل')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditSheet(null),
        child: const Icon(Icons.add),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.templates.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.description_outlined,
                          size: 64,
                          color:
                              theme.colorScheme.onSurface.withOpacity(0.2)),
                      const SizedBox(height: 16),
                      const Text('لا توجد قوالب'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: () => _showEditSheet(null),
                        icon: const Icon(Icons.add),
                        label: const Text('إنشاء قالب'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(templatesProvider.notifier).loadTemplates(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.templates.length,
                    itemBuilder: (context, index) {
                      final tmpl = state.templates[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color:
                              theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.description,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          title: Text(
                            tmpl.templateName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  TemplateModel.getArabicType(
                                      tmpl.templateType),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                tmpl.messageContent,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          trailing: Switch.adaptive(
                            value: tmpl.isActive,
                            activeColor: AppTheme.successColor,
                            onChanged: (v) {
                              ref
                                  .read(templatesProvider.notifier)
                                  .toggleTemplate(tmpl.templateType, v);
                            },
                          ),
                          onTap: () => _showEditSheet(tmpl),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
