import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/manager_debts_api.dart';
import '../../../api/managers_api.dart';
import '../../../api/whatsapp_api.dart';
import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/widgets/sheet_scaffold.dart';

/// إرسال رسالة معلومات للمدير (وضعه المالي الحالي) بدون أي عملية.
/// مطابق v1 _sendManagerInfoMessage (managers_screen.dart:1109).
/// يُولّد قالب جاهز يحتوي على الرصيد + الدين، ويسمح للأدمن بتعديله
/// قبل الإرسال.
Future<bool?> showSendInfoSheet(BuildContext context, Manager m) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SendInfoSheet(manager: m),
  );
}

class _SendInfoSheet extends StatefulWidget {
  const _SendInfoSheet({required this.manager});
  final Manager manager;

  @override
  State<_SendInfoSheet> createState() => _SendInfoSheetState();
}

class _SendInfoSheetState extends State<_SendInfoSheet> {
  late final TextEditingController _msgCtrl;
  bool _submitting = false;
  // مطلب 2026-06-11: الديون الخارجية (manager-debts) تُجلب عند فتح
  // الـsheet بالتوازي مع رسم القالب الافتراضي. v1 يمرّر extraDebt من
  // الأب (managers_screen) لأنه يحتفظ بـsummary cached؛ v2 لا يحتفظ
  // فيها فنجلبها هنا. عند الوصول، نُعيد بناء النص بالقيم الصحيحة.
  double _extraDebt = 0;
  bool _extraLoaded = false;

  @override
  void initState() {
    super.initState();
    _msgCtrl = TextEditingController(text: _composeMessage(0));
    _loadExtraDebt();
  }

  Future<void> _loadExtraDebt() async {
    final summary = await ManagerDebtsApi.summary();
    if (!mounted) return;
    final extra = summary?.remainingForDebtor(widget.manager.id) ?? 0;
    setState(() {
      _extraDebt = extra;
      _extraLoaded = true;
      _msgCtrl.text = _composeMessage(extra);
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  /// مطابق v1 _sendManagerInfoMessage (managers_screen.dart:1109).
  /// الشكل ثابت — تحية + الرصيد الحالي + بريك-داون الديون الثلاث.
  /// الفاصلة العربية بعد الاسم مهمّة: السيرفر يستعملها لاستخراج
  /// `recipient_name` في سجلّ الواتساب (لو حُذفت الفاصلة، الـRegEx
  /// يأخذ بقية الرسالة كلها كاسم → سجلّ مشوّش).
  String _composeMessage(double extraDebt) {
    final m = widget.manager;
    final managerName = m.fullName.isNotEmpty ? m.fullName : m.username;
    final sas = m.debt;
    final total = sas + extraDebt;
    return [
      'عزيزي المدير $managerName، 👋',
      '',
      '💳 رصيدك الحالي: ${formatIQD(m.credit)} د.ع',
      '',
      '— الديون عليك —',
      '🧾 ديون الساس: ${formatIQD(sas)} د.ع',
      '📑 ديون أخرى: ${formatIQD(extraDebt)} د.ع',
      '📊 المجموع: ${formatIQD(total)} د.ع',
    ].join('\n');
  }

  Future<void> _send() async {
    if (_submitting) return;
    final phone = (widget.manager.mobile ?? '').trim();
    if (phone.isEmpty) {
      showSheetSnack(context, 'لا يوجد رقم هاتف للمدير', isError: true);
      return;
    }
    final message = _msgCtrl.text.trim();
    if (message.isEmpty) return;
    setState(() => _submitting = true);
    final r = await WhatsAppApi.sendMessage(
      to: phone,
      message: message,
      intent: 'manager_info',
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    showSheetSnack(context, r.ok
            ? 'تم إرسال المعلومات'
            : (r.message ?? 'تعذّر الإرسال'), isError: (r.ok) ? false : true);
    if (r.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFF25D366);
    final hasPhone = (widget.manager.mobile ?? '').trim().isNotEmpty;
    // iOS keyboard-avoidance: push the sheet up so the editable message
    // text field + send button stay visible when the keyboard opens.
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.xl)),
          ),
          padding: EdgeInsets.only(bottom: bottomInset),
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
                      child: const Icon(LucideIcons.smartphone,
                          size: 16, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إرسال معلومات',
                            style: AppType.title(color: AppColors.textHi)
                                .copyWith(fontSize: 15),
                          ),
                          Text(
                            widget.manager.username,
                            style: AppType.muted().copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
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
                    if (!hasPhone) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(R.md),
                          border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: const [
                            Icon(LucideIcons.triangleAlert,
                                size: 14, color: AppColors.error),
                            SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'لا يوجد رقم هاتف محفوظ — لن يُرسل واتساب',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Sp.md),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, right: 2),
                      child: Text('الرسالة (قابلة للتعديل)',
                          style: AppType.muted(color: AppColors.textMid)
                              .copyWith(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                    ),
                    TextField(
                      controller: _msgCtrl,
                      maxLines: 12,
                      minLines: 8,
                      style: AppType.input(color: AppColors.textHi),
                      decoration: InputDecoration(
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
                    child: ElevatedButton.icon(
                      onPressed:
                          (hasPhone && !_submitting) ? _send : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.send, size: 16),
                      label: Text(
                        _submitting ? 'جاري الإرسال...' : 'إرسال واتساب',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
