import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/subscriber_model.dart';
import '../../core/utils/helpers.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/whatsapp_provider.dart';
import '../../providers/subscribers_provider.dart';

class SubscriberDetailsScreen extends ConsumerStatefulWidget {
  final SubscriberModel subscriber;

  const SubscriberDetailsScreen({super.key, required this.subscriber});

  @override
  ConsumerState<SubscriberDetailsScreen> createState() =>
      _SubscriberDetailsScreenState();
}

class _SubscriberDetailsScreenState
    extends ConsumerState<SubscriberDetailsScreen> {
  final _messageController = TextEditingController();
  bool _isProcessing = false;

  int? get _subscriberId =>
      int.tryParse(widget.subscriber.idx ?? '');

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── WhatsApp ──────────────────────────────────────────────────────────
  void _showSendMessageSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 20, right: 20, top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.chat, color: AppTheme.whatsappGreen),
                const SizedBox(width: 8),
                Text('إرسال رسالة واتساب',
                    style: Theme.of(ctx).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'إلى: ${widget.subscriber.fullName} (${widget.subscriber.displayPhone})',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'اكتب رسالتك هنا...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                if (_messageController.text.trim().isEmpty) return;
                final success =
                    await ref.read(whatsappProvider.notifier).sendMessage(
                          widget.subscriber.displayPhone,
                          _messageController.text.trim(),
                        );
                if (mounted) {
                  Navigator.pop(ctx);
                  _showSnack(
                    success ? 'تم الإرسال بنجاح' : 'فشل الإرسال',
                    success: success,
                  );
                  _messageController.clear();
                }
              },
              icon: const Icon(Icons.send),
              label: const Text('إرسال'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.whatsappGreen,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── Edit ───────────────────────────────────────────────────────────────
  void _showEditSheet() {
    final sub = widget.subscriber;
    final fnCtrl = TextEditingController(text: sub.firstname);
    final lnCtrl = TextEditingController(text: sub.lastname);
    final phCtrl = TextEditingController(text: sub.displayPhone);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20, right: 20, top: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit, color: AppTheme.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text('تعديل بيانات المشترك',
                      style: Theme.of(ctx).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: fnCtrl,
                      decoration: const InputDecoration(
                        labelText: 'الاسم الأول',
                        prefixIcon: Icon(Icons.person_outline, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: lnCtrl,
                      decoration: const InputDecoration(labelText: 'الاسم الأخير'),
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: phCtrl,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            final id = _subscriberId;
                            if (id == null) {
                              _showSnack('معرف المشترك غير متوفر', success: false);
                              return;
                            }
                            setSheetState(() => saving = true);
                            try {
                              final notifier = ref.read(subscribersProvider.notifier);
                              final details = await notifier.getSubscriberDetails(id);
                              if (details == null) {
                                if (mounted) {
                                  _showSnack('فشل جلب بيانات المشترك', success: false);
                                }
                                return;
                              }
                              details['firstname'] = fnCtrl.text.trim();
                              details['lastname'] = lnCtrl.text.trim();
                              details['phone'] = phCtrl.text.trim();
                              details.remove('id');
                              details.remove('idx');
                              details.remove('profile_details');

                              final ok = await notifier.updateSubscriber(id, details);

                              if (mounted) {
                                Navigator.pop(ctx);
                                _showSnack(
                                  ok ? 'تم التعديل بنجاح' : 'فشل التعديل',
                                  success: ok,
                                );
                                if (ok) notifier.loadSubscribers();
                              }
                            } finally {
                              if (mounted) setSheetState(() => saving = false);
                            }
                          },
                    icon: saving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(saving ? 'جاري الحفظ...' : 'حفظ التعديلات'),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        });
      },
    );
  }

  // ── Delete ─────────────────────────────────────────────────────────────
  Future<void> _deleteSubscriber() async {
    final id = _subscriberId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }

    final sub = widget.subscriber;
    if (sub.hasDebt && sub.debtAmount < 0) {
      _showSnack('لا يمكن حذف مشترك عليه دين: ${AppHelpers.formatMoney(sub.debtAmount)}',
          success: false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المشترك "${sub.fullName}"؟\nلا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.dangerColor),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    final success = await ref.read(subscribersProvider.notifier)
        .deleteSubscriber(id, forceSkipDebtCheck: true);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    if (success) {
      _showSnack('تم حذف المشترك بنجاح');
      ref.read(subscribersProvider.notifier).loadSubscribers();
      context.pop();
    } else {
      _showSnack('فشل حذف المشترك — قد يكون عليه دين', success: false);
    }
  }

  // ── Extend / Renew ─────────────────────────────────────────────────────
  Future<void> _extendSubscription() async {
    final id = _subscriberId;
    final profileId = widget.subscriber.profileId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }
    if (profileId == null) {
      _showSnack('معرف الباقة غير متوفر', success: false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد التجديد'),
        content: Text(
          'تجديد اشتراك "${widget.subscriber.fullName}"\n'
          'الباقة: ${widget.subscriber.profileName ?? "—"}\n'
          'السعر: ${widget.subscriber.price != null ? AppHelpers.formatMoney(widget.subscriber.price) : "—"}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تجديد'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    final success = await ref.read(subscribersProvider.notifier)
        .extendSubscription(userId: id, profileId: profileId);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    _showSnack(
      success ? 'تم التجديد بنجاح' : 'فشل التجديد',
      success: success,
    );
    if (success) {
      ref.read(subscribersProvider.notifier).loadSubscribers();
    }
  }

  // ── Activate ───────────────────────────────────────────────────────────
  Future<void> _activateSubscriber() async {
    final id = _subscriberId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }

    setState(() => _isProcessing = true);

    final notifier = ref.read(subscribersProvider.notifier);
    final activationData = await notifier.getActivationData(id);

    if (!mounted) return;

    if (activationData == null) {
      setState(() => _isProcessing = false);
      _showSnack('فشل جلب بيانات التفعيل', success: false);
      return;
    }

    setState(() => _isProcessing = false);

    final userPrice = (activationData['user_price'] is num)
        ? (activationData['user_price'] as num).toDouble()
        : double.tryParse(activationData['user_price']?.toString() ?? '') ?? 0;
    final units = (activationData['units'] is int)
        ? activationData['units'] as int
        : int.tryParse(activationData['units']?.toString() ?? '') ?? 30;
    final profileName = activationData['profile_name']?.toString() ?? '—';
    final profileDuration = activationData['profile_duration']?.toString() ?? '—';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد التفعيل'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المشترك: ${widget.subscriber.fullName}'),
            const SizedBox(height: 8),
            _InfoChip(label: 'الباقة', value: profileName),
            _InfoChip(label: 'المدة', value: profileDuration),
            _InfoChip(label: 'السعر', value: AppHelpers.formatMoney(userPrice)),
            _InfoChip(label: 'الوحدات', value: '$units يوم'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.successColor),
            child: const Text('تفعيل'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    final success = await notifier.activateSubscriber(
      userId: id,
      userPrice: userPrice,
      activationUnits: units,
      currentNotes: widget.subscriber.notes ?? '0',
    );
    if (!mounted) return;
    setState(() => _isProcessing = false);

    _showSnack(
      success ? 'تم التفعيل بنجاح' : 'فشل التفعيل',
      success: success,
    );
    if (success) {
      ref.read(subscribersProvider.notifier).loadSubscribers();
    }
  }

  // ── Toggle Enable/Disable ─────────────────────────────────────────────
  Future<void> _toggleSubscriber({required bool enable}) async {
    final id = _subscriberId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }

    final action = enable ? 'تفعيل الحساب' : 'تعطيل الحساب';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تأكيد $action'),
        content: Text('هل تريد $action للمشترك "${widget.subscriber.fullName}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  enable ? AppTheme.successColor : AppTheme.warningColor,
            ),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isProcessing = true);
    final success = await ref
        .read(subscribersProvider.notifier)
        .toggleSubscriber(id, enable: enable);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    _showSnack(
      success ? 'تم $action بنجاح' : 'فشل $action',
      success: success,
    );
    if (success) {
      ref.read(subscribersProvider.notifier).loadSubscribers();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = widget.subscriber;
    final theme = Theme.of(context);
    final daysColor = AppHelpers.getRemainingDaysColor(sub.remainingDays);
    final isEnabled = sub.enabled == null || sub.enabled == 1;

    return Scaffold(
      appBar: AppBar(title: Text(sub.fullName)),
      body: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Header Card ──
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: sub.isExpired
                          ? [Colors.red.shade700, Colors.red.shade900]
                          : [AppTheme.teal700, AppTheme.teal900],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Center(
                          child: Text(
                            sub.firstname.isNotEmpty ? sub.firstname[0] : '?',
                            style: const TextStyle(
                              color: Colors.white, fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(sub.fullName,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 20,
                            fontWeight: FontWeight.w800,
                          )),
                      const SizedBox(height: 4),
                      Text(sub.username,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7), fontSize: 14,
                          )),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _HeaderStat(
                            label: 'الأيام المتبقية',
                            value: sub.isExpired
                                ? 'منتهي'
                                : '${sub.remainingDays ?? 0}',
                          ),
                          Container(width: 1, height: 30,
                              color: Colors.white.withOpacity(0.2)),
                          _HeaderStat(
                            label: 'الباقة',
                            value: sub.profileName ?? '—',
                          ),
                          Container(width: 1, height: 30,
                              color: Colors.white.withOpacity(0.2)),
                          _HeaderStat(
                            label: 'الدين',
                            value: sub.hasDebt
                                ? AppHelpers.formatMoney(sub.debtAmount)
                                : 'لا يوجد',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Account Info ──
                _DetailSection(
                  title: 'معلومات الحساب',
                  children: [
                    _DetailRow(
                      icon: Icons.person_outline,
                      label: 'اسم المستخدم',
                      value: sub.username,
                    ),
                    _DetailRow(
                      icon: Icons.phone_outlined,
                      label: 'رقم الهاتف',
                      value: AppHelpers.formatPhone(sub.displayPhone),
                    ),
                    _DetailRow(
                      icon: Icons.wifi,
                      label: 'الباقة',
                      value: sub.profileName ?? '—',
                    ),
                    _DetailRow(
                      icon: Icons.attach_money,
                      label: 'سعر الباقة',
                      value: sub.price != null
                          ? AppHelpers.formatMoney(sub.price)
                          : '—',
                    ),
                    _DetailRow(
                      icon: Icons.toggle_on_outlined,
                      label: 'الحالة',
                      value: isEnabled ? 'مفعّل' : 'معطّل',
                      valueColor: isEnabled
                          ? AppTheme.successColor
                          : AppTheme.dangerColor,
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Subscription Status ──
                _DetailSection(
                  title: 'حالة الاشتراك',
                  children: [
                    _DetailRow(
                      icon: Icons.calendar_today,
                      label: 'تاريخ الانتهاء',
                      value: sub.expiration ?? '—',
                    ),
                    _DetailRow(
                      icon: Icons.timelapse,
                      label: 'الأيام المتبقية',
                      value: sub.isExpired
                          ? 'منتهي (${sub.remainingDays} يوم)'
                          : '${sub.remainingDays ?? 0} يوم',
                      valueColor: daysColor,
                    ),
                    _DetailRow(
                      icon: Icons.credit_card,
                      label: 'الدين / الرصيد',
                      value: sub.hasDebt
                          ? '${AppHelpers.formatMoney(sub.debtAmount)} (مديون)'
                          : sub.notes != null &&
                                  (double.tryParse(sub.notes!) ?? 0) > 0
                              ? '${AppHelpers.formatMoney(sub.notes)} (رصيد)'
                              : 'لا يوجد',
                      valueColor: sub.hasDebt ? Colors.red : Colors.green,
                    ),
                  ],
                ),

                const SizedBox(height: 80),
              ],
            ),

      // ── Bottom Action Bar ──────────────────────────────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? theme.colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ActionChip(
                    icon: Icons.edit_outlined,
                    label: 'تعديل',
                    color: AppTheme.primary,
                    onTap: _isProcessing ? null : _showEditSheet,
                  ),
                  const SizedBox(width: 8),
                  _ActionChip(
                    icon: Icons.delete_outline,
                    label: 'حذف',
                    color: AppTheme.dangerColor,
                    onTap: _isProcessing ? null : _deleteSubscriber,
                  ),
                  const SizedBox(width: 8),
                  _ActionChip(
                    icon: Icons.chat_outlined,
                    label: 'واتساب',
                    color: AppTheme.whatsappGreen,
                    onTap: _isProcessing ? null : _showSendMessageSheet,
                  ),
                  const SizedBox(width: 8),
                  _ActionChip(
                    icon: Icons.autorenew,
                    label: 'تجديد',
                    color: AppTheme.teal600,
                    onTap: _isProcessing ? null : _extendSubscription,
                  ),
                  const SizedBox(width: 8),
                  _ActionChip(
                    icon: Icons.bolt,
                    label: 'تفعيل',
                    color: AppTheme.successColor,
                    onTap: _isProcessing ? null : _activateSubscriber,
                  ),
                  const SizedBox(width: 8),
                  _ActionChip(
                    icon: isEnabled
                        ? Icons.block
                        : Icons.check_circle_outline,
                    label: isEnabled ? 'تعطيل' : 'تفعيل حساب',
                    color: isEnabled
                        ? AppTheme.warningColor
                        : AppTheme.successColor,
                    onTap: _isProcessing
                        ? null
                        : () => _toggleSubscriber(enable: !isEnabled),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Private helper widgets
// ═══════════════════════════════════════════════════════════════════════════

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: disabled
                ? Colors.grey.withOpacity(0.08)
                : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: disabled
                  ? Colors.grey.withOpacity(0.15)
                  : color.withOpacity(0.3),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20,
                  color: disabled ? Colors.grey : color),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: disabled ? Colors.grey : color,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text('$label: ',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
              )),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  final String label;
  final String value;
  const _HeaderStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6), fontSize: 11,
            )),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.6),
              )),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor,
                ),
                textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}
