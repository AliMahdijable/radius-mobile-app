import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/print_template_model.dart';
import '../providers/auth_provider.dart';
import '../providers/print_templates_provider.dart';

/// قوالب الطباعة — قالب واحد لكل مدير (بناءً على طلب المستخدم).
/// لا تعرض هذه الشاشة قائمة؛ بمجرد التحميل تفتح القالب النشط مباشرة
/// (أو تنشئ POS افتراضي لو لا يوجد قالب).
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
    Future.microtask(_loadAndOpen);
  }

  Future<void> _loadAndOpen() async {
    await ref.read(printTemplatesProvider.notifier).loadTemplates();
    if (!mounted || _autoOpened) return;
    final state = ref.read(printTemplatesProvider);
    _autoOpened = true;

    PrintTemplateModel target;
    if (state.templates.isEmpty) {
      final adminId = ref.read(authProvider).user?.id ?? '';
      target = PrintTemplateModel(
        adminId: adminId,
        templateType: 'pos',
        templateName: 'قالب الطباعة',
        content: PrintTemplateModel.defaultPosTemplate(),
        isActive: true,
      );
    } else {
      target = state.templates.firstWhere(
        (t) => t.isActive,
        orElse: () => state.templates.first,
      );
    }
    if (!mounted) return;
    // pushReplacement حتى لا يرجع المستخدم لشاشة الانتظار.
    context.pushReplacement('/print-template-editor', extra: target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'قوالب الطباعة',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'جارٍ فتح القالب...',
              style: TextStyle(
                  fontFamily: 'Cairo', fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
