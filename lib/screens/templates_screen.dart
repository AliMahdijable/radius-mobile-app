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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final screenH = MediaQuery.of(ctx).size.height;
        return StatefulBuilder(
          builder: (ctx, setSheetState) => Container(
            height: screenH * 0.85,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom,
              left: 20, right: 20, top: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 12),
                Text(
                  template == null ? 'إنشاء قالب' : 'تعديل القالب',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),

                if (template == null) ...[
                  DropdownButtonFormField<String>(
                    value: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'نوع القالب',
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    items: [
                      'debt_reminder', 'expiry_warning', 'service_end',
                      'activation_notice', 'renewal', 'payment_confirmation',
                      'welcome_message',
                    ].map((t) => DropdownMenuItem(
                      value: t,
                      child: Text(TemplateModel.getArabicType(t)),
                    )).toList(),
                    onChanged: (v) =>
                        setSheetState(() => selectedType = v ?? selectedType),
                  ),
                  const SizedBox(height: 12),
                ],

                TextField(
                  controller: nameController,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'اسم القالب',
                    prefixIcon: Icon(Icons.label_outline, size: 20),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                Expanded(
                  child: TextField(
                    controller: contentController,
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(fontSize: 14, height: 1.6),
                    decoration: const InputDecoration(
                      labelText: 'محتوى الرسالة',
                      hintText: 'مرحبا {firstname}...',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                Text('المتغيرات:', style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4, runSpacing: 4,
                  children: TemplateModel.availableVariables.map((v) {
                    return GestureDetector(
                      onTap: () {
                        final text = contentController.text;
                        final sel = contentController.selection;
                        final start = sel.isValid ? sel.start : text.length;
                        final end = sel.isValid ? sel.end : text.length;
                        contentController.text = text.replaceRange(start, end, v);
                        contentController.selection = TextSelection.collapsed(
                            offset: start + v.length);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          TemplateModel.variableLabels[v] ?? v,
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                              color: Theme.of(ctx).colorScheme.primary),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 12),
                SizedBox(height: 46, child: ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty || contentController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('يرجى ملء جميع الحقول')));
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
                    final ok = await ref.read(templatesProvider.notifier)
                        .saveTemplate(newTemplate);
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(ok ? 'تم حفظ القالب' : 'فشل حفظ القالب')));
                    }
                  },
                  child: const Text('حفظ القالب'),
                )),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
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
                      return GestureDetector(
                        onTap: () => _showEditSheet(tmpl),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: theme.cardTheme.color,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36, height: 36,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10)),
                                child: Icon(Icons.description, size: 18,
                                    color: theme.colorScheme.primary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text(tmpl.templateName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700, fontSize: 13)),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.primary.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(4)),
                                        child: Text(
                                          TemplateModel.getArabicType(tmpl.templateType),
                                          style: TextStyle(fontSize: 9,
                                              color: theme.colorScheme.primary)),
                                      ),
                                    ]),
                                    const SizedBox(height: 2),
                                    Text(tmpl.messageContent,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 11,
                                            color: theme.colorScheme.onSurface.withOpacity(0.5))),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: tmpl.isActive,
                                activeColor: AppTheme.successColor,
                                onChanged: (v) {
                                  ref.read(templatesProvider.notifier)
                                      .toggleTemplate(tmpl.templateType, v);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
