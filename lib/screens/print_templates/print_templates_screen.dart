import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/print_templates_api.dart';
import '../../services/print_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'print_template_editor_screen.dart';

/// شاشة "قوالب الطباعة" — يعرض القالبين (A4 + POS) للأدمن الحالي.
/// backend يضمن أن كل type له سطر واحد فقط (UNIQUE KEY على admin_id+type).
/// لو مو موجود يظهر placeholder + زر إنشاء بمحتوى افتراضي.
class PrintTemplatesScreen extends StatefulWidget {
  const PrintTemplatesScreen({super.key});

  @override
  State<PrintTemplatesScreen> createState() => _PrintTemplatesScreenState();
}

class _PrintTemplatesScreenState extends State<PrintTemplatesScreen> {
  List<PrintTemplate> _list = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await PrintTemplatesApi.list();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  PrintTemplate? _byType(String type) {
    for (final t in _list) {
      if (t.templateType == type) return t;
    }
    return null;
  }

  Future<void> _editOrCreate(String type, {PrintTemplate? existing}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PrintTemplateEditorScreen(
          templateType: type,
          existing: existing,
        ),
      ),
    );
    if (result == true) await _load();
  }

  Future<void> _testPrint(PrintTemplate t) async {
    final filled = PrintService.fillTemplate(t.content, PrintService.sampleData);
    final ok = await PrintService.printHtml(
      html: filled,
      format: PrintService.formatForType(t.templateType),
      documentName: t.templateName,
    );
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('print_templates.print_cancelled'.tr()),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final a4 = _byType('a4');
    final pos = _byType('pos');

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'print_templates.title'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.huge),
                children: [
                  _sectionLabel(
                    'print_templates.a4_section'.tr(),
                    LucideIcons.fileText,
                  ),
                  const SizedBox(height: Sp.sm),
                  _TemplateCard(
                    type: 'a4',
                    template: a4,
                    onTap: () => _editOrCreate('a4', existing: a4),
                    onTestPrint: a4 == null ? null : () => _testPrint(a4),
                  ),
                  const SizedBox(height: Sp.lg),
                  _sectionLabel(
                    'print_templates.pos_section'.tr(),
                    LucideIcons.receipt,
                  ),
                  const SizedBox(height: Sp.sm),
                  _TemplateCard(
                    type: 'pos',
                    template: pos,
                    onTap: () => _editOrCreate('pos', existing: pos),
                    onTestPrint: pos == null ? null : () => _testPrint(pos),
                  ),
                  const SizedBox(height: Sp.lg),
                  Container(
                    padding: const EdgeInsets.all(Sp.md),
                    decoration: BoxDecoration(
                      color: AppColors.brand.withOpacity(0.05),
                      border: Border.all(
                          color: AppColors.brand.withOpacity(0.15)),
                      borderRadius: BorderRadius.circular(R.md),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.info,
                            size: 14, color: AppColors.brand),
                        const SizedBox(width: Sp.sm),
                        Expanded(
                          child: Text(
                            'print_templates.info_body'.tr(),
                            style: AppType.subtitle(color: AppColors.textMid)
                                .copyWith(fontSize: 11.5, height: 1.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

Widget _sectionLabel(String text, IconData icon) => Row(
      children: [
        Icon(icon, size: 14, color: AppColors.brand),
        const SizedBox(width: Sp.xs),
        Text(text,
            style: AppType.title(color: AppColors.textHi)
                .copyWith(fontSize: 12)),
      ],
    );

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.type,
    required this.template,
    required this.onTap,
    this.onTestPrint,
  });
  final String type;
  final PrintTemplate? template;
  final VoidCallback onTap;
  final VoidCallback? onTestPrint;

  @override
  Widget build(BuildContext context) {
    final exists = template != null;
    final IconData typeIcon =
        type == 'a4' ? LucideIcons.fileText : LucideIcons.receipt;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brand.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(typeIcon, color: AppColors.brand, size: 22),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      exists
                          ? template!.templateName
                          : (type == 'a4'
                              ? 'print_templates.a4_default_name'.tr()
                              : 'print_templates.pos_default_name'.tr()),
                      style: AppType.title(color: AppColors.textHi)
                          .copyWith(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: Sp.sm, vertical: 2),
                          decoration: BoxDecoration(
                            color: (exists && template!.isActive)
                                ? AppColors.brand.withOpacity(0.1)
                                : AppColors.textMid.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(R.pill),
                          ),
                          child: Text(
                            exists
                                ? (template!.isActive
                                    ? 'print_templates.active'.tr()
                                    : 'print_templates.inactive'.tr())
                                : 'print_templates.not_created'.tr(),
                            style: AppType.button(
                              color: (exists && template!.isActive)
                                  ? AppColors.brand
                                  : AppColors.textMid,
                            ).copyWith(fontSize: 10),
                          ),
                        ),
                        const SizedBox(width: Sp.sm),
                        if (exists && template!.updatedAt != null)
                          Expanded(
                            child: Text(
                              _formatDate(template!.updatedAt!),
                              style:
                                  AppType.subtitle(color: AppColors.textMid)
                                      .copyWith(fontSize: 10),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (exists && onTestPrint != null)
                IconButton(
                  tooltip: 'print_templates.test_print'.tr(),
                  icon: Icon(LucideIcons.printer,
                      color: AppColors.brand, size: 18),
                  onPressed: onTestPrint,
                ),
              Icon(
                exists ? LucideIcons.pencil : LucideIcons.plus,
                color: AppColors.textLow,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final d = DateTime.tryParse(iso);
      if (d == null) return iso;
      final l = d.toLocal();
      final y = l.year.toString().padLeft(4, '0');
      final m = l.month.toString().padLeft(2, '0');
      final dd = l.day.toString().padLeft(2, '0');
      return '$y-$m-$dd';
    } catch (_) {
      return iso;
    }
  }
}
