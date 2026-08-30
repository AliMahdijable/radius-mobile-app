import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/whatsapp_api.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// Label عربي لكل متغير قالب — يظهر بـtooltip + كـsubtitle داخل
/// الـchip في الـEditTemplateSheet. مطابق v1
/// mobile-app/lib/models/template_model.dart:90-117.
const Map<String, String> _kVariableLabels = {
  // Subscriber
  '{firstname}': 'الاسم الأول',
  '{subscriber_name}': 'اسم المشترك',
  '{username}': 'اسم المستخدم',
  '{phone}': 'رقم الهاتف',
  '{package_name}': 'اسم الباقة',
  '{package_price}': 'سعر الباقة',
  '{days_remaining}': 'الأيام المتبقية',
  '{expiry_date}': 'تاريخ الانتهاء',
  '{debt_amount}': 'مبلغ الدين',
  '{credit_amount}': 'الرصيد',
  '{paid_amount}': 'المبلغ المدفوع',
  '{payment_date}': 'تاريخ التسديد',
  '{discount_amount}': 'قيمة الخصم',
  '{discounted_price}': 'السعر بعد الخصم',
  // Manager
  '{manager_name}': 'اسم المدير',
  '{manager_username}': 'معرّف المدير',
  '{amount}': 'المبلغ',
  '{action_type}': 'نوع الحركة',
  '{previous_credit}': 'الرصيد السابق',
  '{current_credit}': 'الرصيد الحالي',
  '{sas_debts}': 'ديون الساس',
  '{other_debts}': 'ديون أخرى',
  '{total_debts}': 'مجموع الديون',
  '{movement_description}': 'وصف الحركة',
};

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
  /// مطلب 2026-06-12 (مطابق v1 mobile-app/lib/models/template_model.dart:73-117):
  /// متغيرات المشترك المعتمدة من template helper الـbackend. كل
  /// متغير له label عربي يظهر بـtooltip عند الضغط.
  static const _subscriberVariables = <String>[
    '{firstname}',
    '{subscriber_name}',
    '{username}',
    '{phone}',
    '{package_name}',
    '{package_price}',
    '{days_remaining}',
    '{expiry_date}',
    '{debt_amount}',
    '{credit_amount}',
    '{paid_amount}',
    '{payment_date}',
    '{discount_amount}',
    '{discounted_price}',
  ];

  /// متغيرات قالب المدير الفرعي (manager_agent).
  static const _managerVariables = <String>[
    '{manager_name}',
    '{manager_username}',
    '{amount}',
    '{action_type}',
    '{previous_credit}',
    '{current_credit}',
    '{sas_debts}',
    '{other_debts}',
    '{total_debts}',
    '{movement_description}',
  ];

  static const _knownTypes = <_TemplateDef>[
    _TemplateDef(
      type: 'welcome_message',
      label: 'رسالة الترحيب',
      icon: LucideIcons.handshake,
      placeholders: _subscriberVariables,
    ),
    _TemplateDef(
      type: 'activation_notice',
      label: 'إشعار التفعيل',
      icon: LucideIcons.zap,
      placeholders: _subscriberVariables,
    ),
    _TemplateDef(
      type: 'renewal',
      label: 'إشعار التمديد',
      icon: LucideIcons.calendarPlus,
      placeholders: _subscriberVariables,
    ),
    _TemplateDef(
      type: 'payment_confirmation',
      label: 'تأكيد التسديد',
      icon: LucideIcons.banknote,
      placeholders: _subscriberVariables,
    ),
    _TemplateDef(
      type: 'debt_reminder',
      label: 'تذكير الدين',
      icon: LucideIcons.alertCircle,
      placeholders: _subscriberVariables,
    ),
    _TemplateDef(
      type: 'expiry_warning',
      label: 'تذكير قرب الانتهاء',
      icon: LucideIcons.clock,
      placeholders: _subscriberVariables,
    ),
    _TemplateDef(
      type: 'service_end',
      label: 'إشعار الانتهاء',
      icon: LucideIcons.timerOff,
      placeholders: _subscriberVariables,
    ),
    _TemplateDef(
      type: 'subscriber_info',
      label: 'معلومات المشترك',
      icon: LucideIcons.info,
      placeholders: _subscriberVariables,
    ),
    _TemplateDef(
      type: 'manager_agent',
      label: 'إشعار مدير فرعي',
      icon: LucideIcons.shield,
      placeholders: _managerVariables,
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
      barrierColor: AppColors.scrim,
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
    Theme.of(context); // theme-dep (dark-mode)
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
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: accent,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
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
    Theme.of(context); // theme-dep (dark-mode)
    final isActive = existing?.isActive == true;
    final hasBody = (existing?.messageContent ?? '').trim().isNotEmpty;
    final accent = isActive
        ? const Color(0xFF25D366)
        : (hasBody ? AppColors.warning : AppColors.textLow);
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
              Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
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
      color = AppColors.warning;
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
          fontWeight: FontWeight.w700,
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

  /// 2026-08-26: قناة افتراضيّة للقالب — auto/whatsapp/telegram.
  late String _defaultChannel;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bodyCtrl =
        TextEditingController(text: widget.existing?.messageContent ?? '');
    _isActive = widget.existing?.isActive ?? true;
    _defaultChannel = widget.existing?.defaultChannel ?? 'auto';
  }

  @override
  void dispose() {
    _bodyCtrl.dispose();
    super.dispose();
  }

  /// 2026-08-26: مبدّل القناة الافتراضيّة للقالب — 3 chips.
  /// auto = يحترم binding المشترك (الافتراضي).
  /// whatsapp = يجبر WA حتى لو المشترك مربوط بـTG.
  /// telegram = يجبر TG (يفشل الإرسال لو المشترك مو مربوط).
  Widget _defaultChannelPicker() {
    final options = [
      (
        value: 'auto',
        label: 'تلقائي',
        icon: LucideIcons.split,
        color: AppColors.brand,
        hint: 'يحترم ربط المشترك (تلغرام لو مربوط، وإلا واتساب)',
      ),
      (
        value: 'whatsapp',
        label: 'واتساب فقط',
        icon: LucideIcons.messageCircle,
        color: const Color(0xFF25D366),
        hint: 'يجبر الواتساب حتى للمربوطين بتلغرام',
      ),
      (
        value: 'telegram',
        label: 'تلغرام فقط',
        icon: LucideIcons.send,
        color: const Color(0xFF229ED9),
        hint: 'يجبر تلغرام — يفشل للمشترك غير المربوط',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('قناة الإرسال',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textHi,
              )),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _channelChip(
                    label: options[i].label,
                    icon: options[i].icon,
                    color: options[i].color,
                    selected: _defaultChannel == options[i].value,
                    onTap: () =>
                        setState(() => _defaultChannel = options[i].value),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            options.firstWhere((o) => o.value == _defaultChannel).hint,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppColors.textMid,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color:
              selected ? color.withValues(alpha: 0.14) : AppColors.surfaceInput,
          borderRadius: BorderRadius.circular(R.sm),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 1 : 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: selected ? color : AppColors.textMid),
            const SizedBox(width: 4),
            Flexible(
              child: Text(label,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? color : AppColors.textMid,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }

  void _insertPlaceholder(String ph) {
    final sel = _bodyCtrl.selection;
    final text = _bodyCtrl.text;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final next = text.substring(0, start) + ph + text.substring(end);
    _bodyCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + ph.length),
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final r = await WhatsAppApi.saveTemplate(
      templateType: widget.def.type,
      templateName: widget.def.label,
      messageContent: _bodyCtrl.text,
      isActive: _isActive,
      defaultChannel: _defaultChannel,
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
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorFill),
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
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFF25D366);
    // مطلب 2026-06-12 (iPhone): على iOS ما يوجد زر "خلف" يخفي
    // الكيبورد فيستحيل على المدير يطلع من حقل التعديل. GestureDetector
    // بـHitTestBehavior.translucent يلتقط أي نقر فاضي ويخفي الكيبورد
    // (FocusScope.unfocus). الـTextField الداخلية تتلقى نقراتها أولاً
    // فما يتأثر تعديلها.
    return DesignSheet(
      header: SheetHeaderBar(
        icon: widget.def.icon,
        title: widget.def.label,
        subtitle: 'قالب رسالة واتساب',
        tint: AppColors.channelWhatsApp,
        tintBg: AppColors.channelWhatsAppSoftBg,
        onClose: _saving ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _saving ? 'جارٍ الحفظ...' : 'حفظ',
        icon: LucideIcons.save,
        busy: _saving,
        onPressed: _save,
      ),
      maxHeightFactor: 0.95,
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.xxl),
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            activeColor: accent,
            title: const Text(
              'القالب مفعّل',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
          const SizedBox(height: Sp.sm),
          // 2026-08-26: قناة افتراضيّة للقالب — auto / whatsapp / telegram.
          _defaultChannelPicker(),
          const SizedBox(height: Sp.md),
          if (widget.def.placeholders.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 2),
              child: Row(
                children: [
                  Text(
                    'إضافة متغير',
                    style: AppType.muted(color: AppColors.textMid)
                        .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.arrowLeftRight,
                      size: 11, color: AppColors.textLow),
                ],
              ),
            ),
            // مطلب 2026-06-12: scroll أفقي قابل للسحب يمين/يسار،
            // الـchips تظهر مرتّبة في صف واحد بدون انتشار عمودي.
            SizedBox(
              // 52dp يضمن استيعاب 2 سطر نص + padding بلا
              // overflow على iPhone (الـtext rendering يأخذ
              // ~1dp إضافي بسبب الـArabic glyphs).
              height: 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.def.placeholders.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => _phChip(widget.def.placeholders[i]),
              ),
            ),
            const SizedBox(height: Sp.md),
          ],
          Text(
            'نص الرسالة',
            style: AppType.muted(color: AppColors.textMid)
                .copyWith(fontSize: 11, fontWeight: FontWeight.w700),
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
                borderSide: BorderSide(color: AppColors.borderSoft),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm),
                borderSide: BorderSide(color: AppColors.borderSoft),
              ),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  /// مطلب 2026-06-12 (تحديث): chip أفقي مدمج — Arabic label فوق
  /// + {variable_name} تحت. النقر يدرج بالـcursor مباشرة.
  Widget _phChip(String ph) {
    final arabicLabel = _kVariableLabels[ph];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _insertPlaceholder(ph),
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF25D366).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
                color: const Color(0xFF25D366).withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (arabicLabel != null) ...[
                Text(
                  arabicLabel,
                  style: TextStyle(
                    color: AppColors.successFill,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
              ],
              Text(
                ph,
                style: const TextStyle(
                  color: Color(0xFF25D366),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
