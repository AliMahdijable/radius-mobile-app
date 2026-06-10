import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/whatsapp_api.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// قائمة قوالب الواتساب القابلة للتحرير. كل قالب له:
///   • templateType (مفتاح ثابت — welcome_message, activation_notice, …)
///   • isActive — لو معطّل، الـbackend ما يستخدم القالب حتى لو
///     الـfeature toggle مفعّل.
///   • messageContent — نص فيه placeholders ({name}, {amount}, ...)
class WhatsAppTemplatesScreen extends StatefulWidget {
  const WhatsAppTemplatesScreen({super.key});

  @override
  State<WhatsAppTemplatesScreen> createState() =>
      _WhatsAppTemplatesScreenState();
}

class _WhatsAppTemplatesScreenState extends State<WhatsAppTemplatesScreen> {
  List<WhatsTemplate> _templates = const [];
  bool _loading = true;

  /// الـ7 أنواع المعروفة + الـlabel العربي + الـplaceholders. لو
  /// الـbackend رجّع قالب بنوع غير معروف، نضيفه ديناميكياً للقائمة.
  static const _knownTypes = <_TemplateDef>[
    _TemplateDef(
      type: 'welcome_message',
      label: 'رسالة الترحيب',
      icon: LucideIcons.handshake,
      placeholders: ['{name}', '{username}', '{password}', '{package}'],
    ),
    _TemplateDef(
      type: 'activation_notice',
      label: 'إشعار التفعيل',
      icon: LucideIcons.zap,
      placeholders: [
        '{name}',
        '{username}',
        '{package}',
        '{price}',
        '{expiration}',
        '{paid}'
      ],
    ),
    _TemplateDef(
      type: 'extension_notice',
      label: 'إشعار التمديد',
      icon: LucideIcons.calendarPlus,
      placeholders: [
        '{name}',
        '{username}',
        '{package}',
        '{price}',
        '{expiration}'
      ],
    ),
    _TemplateDef(
      type: 'payment_confirmation',
      label: 'تأكيد التسديد',
      icon: LucideIcons.banknote,
      placeholders: [
        '{name}',
        '{username}',
        '{paid_amount}',
        '{package_price}',
        '{package_name}'
      ],
    ),
    _TemplateDef(
      type: 'debt_reminder',
      label: 'تذكير الدين',
      icon: LucideIcons.alertCircle,
      placeholders: [
        '{name}',
        '{username}',
        '{debt_amount}',
        '{package}'
      ],
    ),
    _TemplateDef(
      type: 'expiry_warning',
      label: 'تذكير قرب الانتهاء',
      icon: LucideIcons.clock,
      placeholders: [
        '{name}',
        '{username}',
        '{days_left}',
        '{expiration}'
      ],
    ),
    _TemplateDef(
      type: 'service_end',
      label: 'إشعار الانتهاء',
      icon: LucideIcons.timerOff,
      placeholders: ['{name}', '{username}', '{expiration}'],
    ),
    _TemplateDef(
      type: 'subscriber_info',
      label: 'معلومات المشترك',
      icon: LucideIcons.info,
      placeholders: [
        '{name}',
        '{username}',
        '{package}',
        '{expiration}',
        '{balance}'
      ],
    ),
    _TemplateDef(
      type: 'manager_agent',
      label: 'إشعار مدير فرعي',
      icon: LucideIcons.shield,
      placeholders: [
        '{manager_name}',
        '{manager_username}',
        '{amount}',
        '{previous_credit}',
        '{current_credit}',
        '{current_debt}',
        '{action_label}',
        '{notes}'
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await WhatsAppApi.loadTemplates(refresh: true);
    if (!mounted) return;
    setState(() {
      _templates = list ?? const [];
      _loading = false;
    });
  }

  WhatsTemplate? _templateOf(String type) {
    for (final t in _templates) {
      if (t.templateType == type) return t;
    }
    return null;
  }

  Future<void> _openEdit(_TemplateDef def) async {
    final existing = _templateOf(def.type);
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditTemplateSheet(def: def, existing: existing),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF25D366);
    // نضيف ديناميكياً أي type رجّعه الـbackend غير معروف.
    final extras = _templates
        .where((t) => !_knownTypes.any((d) => d.type == t.templateType))
        .map((t) => _TemplateDef(
              type: t.templateType,
              label: t.templateType,
              icon: LucideIcons.messageSquare,
              placeholders: const [],
            ))
        .toList();
    final all = [..._knownTypes, ...extras];
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'قوالب الواتساب',
          style: AppType.title(color: AppColors.textHi)
              .copyWith(fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Column(
                  children: [
                    for (final def in all) ...[
                      _TemplateTile(
                        def: def,
                        existing: _templateOf(def.type),
                        onTap: () => _openEdit(def),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateDef {
  const _TemplateDef({
    required this.type,
    required this.label,
    required this.icon,
    required this.placeholders,
  });
  final String type;
  final String label;
  final IconData icon;
  final List<String> placeholders;
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.def,
    required this.existing,
    required this.onTap,
  });
  final _TemplateDef def;
  final WhatsTemplate? existing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isActive = existing?.isActive == true;
    final hasBody = (existing?.messageContent ?? '').trim().isNotEmpty;
    final accent = isActive
        ? const Color(0xFF25D366)
        : (hasBody ? const Color(0xFFE08F2D) : AppColors.textLow);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.md),
                ),
                alignment: Alignment.center,
                child: Icon(def.icon, size: 16, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          def.label,
                          style: AppType.title(color: AppColors.textHi)
                              .copyWith(fontSize: 13),
                        ),
                        const SizedBox(width: 6),
                        _statePill(isActive, hasBody),
                      ],
                    ),
                    if (hasBody) ...[
                      const SizedBox(height: 4),
                      Text(
                        existing!.messageContent.trim(),
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 11, height: 1.4),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(
                        'لم يُضبط بعد — اضغط للتحرير',
                        style: AppType.muted().copyWith(fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(LucideIcons.chevronLeft,
                  size: 16, color: AppColors.textLow),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statePill(bool isActive, bool hasBody) {
    String label;
    Color color;
    if (isActive) {
      label = 'مفعّل';
      color = const Color(0xFF25D366);
    } else if (hasBody) {
      label = 'معطّل';
      color = const Color(0xFFE08F2D);
    } else {
      label = 'فاضي';
      color = AppColors.textLow;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EditTemplateSheet extends StatefulWidget {
  const _EditTemplateSheet({required this.def, required this.existing});
  final _TemplateDef def;
  final WhatsTemplate? existing;

  @override
  State<_EditTemplateSheet> createState() => _EditTemplateSheetState();
}

class _EditTemplateSheetState extends State<_EditTemplateSheet> {
  late final TextEditingController _bodyCtrl;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bodyCtrl = TextEditingController(
        text: widget.existing?.messageContent ?? '');
    _isActive = widget.existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _insertPlaceholder(String ph) {
    final sel = _bodyCtrl.selection;
    final text = _bodyCtrl.text;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final next = text.substring(0, start) + ph + text.substring(end);
    _bodyCtrl.value = TextEditingValue(
      text: next,
      selection:
          TextSelection.collapsed(offset: start + ph.length),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final r = await WhatsAppApi.saveTemplate(
      templateType: widget.def.type,
      messageContent: _bodyCtrl.text,
      isActive: _isActive,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'تم الحفظ' : (r.message ?? 'تعذّر الحفظ')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف القالب'),
        content: Text('حذف قالب "${widget.def.label}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final r = await WhatsAppApi.deleteTemplate(widget.def.type);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(r.ok ? 'تم الحذف' : (r.message ?? 'تعذّر الحذف')),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF25D366);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.xl)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child:
                          Icon(widget.def.icon, size: 16, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.def.label,
                            style: AppType.title(color: AppColors.textHi)
                                .copyWith(fontSize: 15),
                          ),
                          Text(
                            widget.def.type,
                            style:
                                AppType.muted().copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.x, size: 16),
                      color: AppColors.textMid,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(
                      Sp.lg, Sp.md, Sp.lg, Sp.huge),
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      activeColor: accent,
                      title: const Text(
                        'القالب مفعّل',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _isActive
                            ? 'الـbackend سيستعمل هذا القالب لإرسال الإشعارات'
                            : 'الـbackend سيتجاهل القالب حتى لو الـtoggle مفعّل',
                        style: AppType.muted().copyWith(fontSize: 11),
                      ),
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                    ),
                    const SizedBox(height: Sp.md),
                    if (widget.def.placeholders.isNotEmpty) ...[
                      Text(
                        'متغيرات متاحة (اضغط للإدراج):',
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final ph in widget.def.placeholders)
                            _phChip(ph),
                        ],
                      ),
                      const SizedBox(height: Sp.md),
                    ],
                    Text(
                      'نص الرسالة',
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(
                              fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _bodyCtrl,
                      maxLines: 14,
                      minLines: 8,
                      style: AppType.input(color: AppColors.textHi),
                      decoration: InputDecoration(
                        hintText: 'مثلاً: مرحباً {name}، باقتك {package}…',
                        hintStyle: AppType.input(color: AppColors.textLow),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.sm),
                          borderSide: BorderSide(
                              color: AppColors.border
                                  .withValues(alpha: 0.5)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.sm),
                          borderSide: BorderSide(
                              color: AppColors.border
                                  .withValues(alpha: 0.5)),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.md),
                  child: SizedBox(
                    height: 50,
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(LucideIcons.save, size: 16),
                            label: const Text(
                              'حفظ',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(R.md),
                              ),
                            ),
                          ),
                        ),
                        if (widget.existing != null) ...[
                          const SizedBox(width: 8),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _saving ? null : _delete,
                              borderRadius: BorderRadius.circular(R.md),
                              child: Container(
                                width: 50,
                                height: 50,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: AppColors.error
                                      .withValues(alpha: 0.08),
                                  borderRadius:
                                      BorderRadius.circular(R.md),
                                  border: Border.all(
                                    color: AppColors.error
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: const Icon(
                                  LucideIcons.trash2,
                                  size: 18,
                                  color: AppColors.error,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _phChip(String ph) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _insertPlaceholder(ph),
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
                color: const Color(0xFF25D366).withValues(alpha: 0.3)),
          ),
          child: Text(
            ph,
            style: const TextStyle(
              color: Color(0xFF25D366),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
