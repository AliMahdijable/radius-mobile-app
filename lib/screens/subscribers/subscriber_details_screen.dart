import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/subscriber_model.dart';
import '../../core/utils/helpers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/constants/api_constants.dart';
import 'package:dio/dio.dart';
import '../../core/network/dio_client.dart';
import '../../core/services/storage_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/whatsapp_provider.dart';
import '../../providers/subscribers_provider.dart';
import '../../providers/templates_provider.dart';
import '../../providers/print_templates_provider.dart';
import '../../core/utils/receipt_printer.dart';
import '../../widgets/app_snackbar.dart';

class SubscriberDetailsScreen extends ConsumerStatefulWidget {
  final SubscriberModel subscriber;

  const SubscriberDetailsScreen({super.key, required this.subscriber});

  @override
  ConsumerState<SubscriberDetailsScreen> createState() =>
      _SubscriberDetailsScreenState();
}

class _SubscriberDetailsScreenState
    extends ConsumerState<SubscriberDetailsScreen> {
  bool _isProcessing = false;

  int? get _subscriberId =>
      int.tryParse(widget.subscriber.idx ?? '');

  bool _matchesCurrentSubscriber(SubscriberModel candidate) {
    final originalIdx = widget.subscriber.idx;
    if (originalIdx != null && originalIdx.isNotEmpty) {
      return candidate.idx == originalIdx;
    }
    return candidate.username == widget.subscriber.username;
  }

  SubscriberModel _resolveCurrentSubscriber(
      Iterable<SubscriberModel> subscribers) {
    for (final candidate in subscribers) {
      if (_matchesCurrentSubscriber(candidate)) {
        return candidate;
      }
    }
    return widget.subscriber;
  }

  SubscriberModel _readCurrentSubscriber() {
    return _resolveCurrentSubscriber(ref.read(subscribersProvider).subscribers);
  }

  SubscriberModel _watchCurrentSubscriber() {
    return ref.watch(
      subscribersProvider.select(
        (state) => _resolveCurrentSubscriber(state.subscribers),
      ),
    );
  }

  void _showSnack(String msg, {bool success = true, String? detail}) {
    if (!mounted) return;
    if (success) {
      AppSnackBar.success(context, msg, detail: detail);
    } else {
      AppSnackBar.error(context, msg, detail: detail);
    }
  }

  Future<void> _launchPhoneCall() async {
    final sub = _readCurrentSubscriber();
    final rawPhone = sub.displayPhone.trim();
    if (rawPhone.isEmpty) {
      AppSnackBar.warning(context, 'لا يوجد رقم هاتف للمشترك');
      return;
    }

    final sanitized = rawPhone.replaceAll(RegExp(r'[^\d+]'), '');
    final dialPhone = sanitized.startsWith('+')
        ? sanitized
        : sanitized.startsWith('964')
            ? '+$sanitized'
            : sanitized;
    final uri = Uri(scheme: 'tel', path: dialPhone);
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      AppSnackBar.error(context, 'تعذر فتح تطبيق الاتصال');
    }
  }

  Future<void> _launchWhatsAppChat() async {
    final sub = _readCurrentSubscriber();
    final rawPhone = sub.displayPhone.trim();
    if (rawPhone.isEmpty) {
      AppSnackBar.warning(context, 'لا يوجد رقم هاتف للمشترك');
      return;
    }

    final phone = _formatPhone(rawPhone);
    if (phone.isEmpty) {
      AppSnackBar.warning(context, 'رقم الهاتف غير صالح لواتساب');
      return;
    }

    final uri = Uri.parse('https://wa.me/$phone');
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      AppSnackBar.error(context, 'تعذر فتح واتساب');
    }
  }

  Future<void> _offerPrintReceipt(ReceiptData data) async {
    if (!mounted) return;
    final shouldPrint = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('طباعة وصل', style: TextStyle(fontFamily: 'Cairo')),
        content: const Text('هل تريد طباعة وصل لهذه العملية؟',
            style: TextStyle(fontFamily: 'Cairo')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('لا'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.print_rounded, size: 18),
            label: const Text('طباعة'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
          ),
        ],
      ),
    );
    if (shouldPrint != true || !mounted) return;

    try {
      final ptState = ref.read(printTemplatesProvider);
      if (ptState.templates.isEmpty) {
        await ref.read(printTemplatesProvider.notifier).loadTemplates();
      }
      final activeTemplate = ref.read(printTemplatesProvider).activeTemplate;
      await ReceiptPrinter.printReceipt(
        data: data,
        htmlTemplate: activeTemplate?.content,
      );
    } catch (e) {
      if (mounted) AppSnackBar.error(context, 'فشل في طباعة الوصل');
    }
  }

  // ── Edit ───────────────────────────────────────────────────────────────
  void _showEditSheet() async {
    final canEditExpiration =
        ref.read(authProvider).user?.canAccessPackages ?? false;
    final id = _subscriberId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }

    setState(() => _isProcessing = true);
    final notifier = ref.read(subscribersProvider.notifier);

    final futures = <Future>[
      notifier.getSubscriberDetails(id),
      notifier.getUserOverview(id),
    ];
    if (ref.read(subscribersProvider).packages.isEmpty) {
      futures.add(notifier.loadPackages());
    }

    final results = await Future.wait(futures);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    final details = results[0] as Map<String, dynamic>?;
    final overview = results[1] as Map<String, dynamic>?;

    if (details == null) {
      _showSnack('فشل جلب بيانات المشترك', success: false);
      return;
    }

    if (overview != null) {
      for (final key in overview.keys) {
        if (details[key] == null ||
            (details[key] is String && (details[key] as String).isEmpty)) {
          details[key] = overview[key];
        }
      }
    }

    final sub = _readCurrentSubscriber();
    final originalUsername = details['username']?.toString() ?? sub.username;
    final originalProfileId = details['profile_id'] ??
        (details['profile_details'] is Map ? details['profile_details']['id'] : null) ??
        sub.profileId;

    final unCtrl = TextEditingController(text: originalUsername);
    final pwCtrl = TextEditingController(text: details['password']?.toString() ?? '');
    final fnCtrl = TextEditingController(text: details['firstname']?.toString() ?? sub.firstname);
    final lnCtrl = TextEditingController(text: details['lastname']?.toString() ?? sub.lastname);
    final phCtrl = TextEditingController(text: details['phone']?.toString() ?? sub.displayPhone);
    final expCtrl = TextEditingController(text: details['expiration']?.toString() ?? sub.expiration ?? '');
    int? selectedProfileId = originalProfileId is int
        ? originalProfileId
        : int.tryParse(originalProfileId?.toString() ?? '');
    bool saving = false;
    bool showAllPackages = false;

    if (!mounted) return;

    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom +
                MediaQuery.of(sheetCtx).padding.bottom,
          ),
          child: StatefulBuilder(builder: (ctx, setSheet) {
            final packages = ref.read(subscribersProvider).packages;
            final seen = <int>{};
            final uniquePkgs = packages.where((p) {
              if (p.idx <= 0 || seen.contains(p.idx)) return false;
              seen.add(p.idx);
              return true;
            }).toList();

            final currentPkgName = sub.profileName ??
                details['profile_name']?.toString() ??
                (details['profile_details'] is Map
                    ? details['profile_details']['name']?.toString()
                    : null);

            final currentPkg = selectedProfileId != null
                ? uniquePkgs.cast<PackageModel?>().firstWhere(
                    (p) => p!.idx == selectedProfileId, orElse: () => null)
                : null;

            final displayPkgs = showAllPackages
                ? uniquePkgs
                : uniquePkgs.take(5).toList();

            return Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, top: 16),
              child: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 40, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Row(children: [
                    Container(padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.edit, color: AppTheme.primary, size: 20)),
                    const SizedBox(width: 10),
                    Text('تعديل بيانات المشترك',
                        style: Theme.of(ctx).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 20),

                  Text('معلومات المشترك', style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: fnCtrl,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      decoration: const InputDecoration(
                        labelText: 'الاسم الأول',
                        prefixIcon: Icon(Icons.person_outline, size: 20)),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(
                      controller: lnCtrl,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.left,
                      decoration: const InputDecoration(labelText: 'الاسم الأخير'),
                    )),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phCtrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr, textAlign: TextAlign.left,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      prefixIcon: Icon(Icons.phone_outlined, size: 20)),
                  ),
                  const SizedBox(height: 20),

                  Text('بيانات الدخول', style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 10),
                  TextField(
                    controller: unCtrl,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    decoration: const InputDecoration(
                      labelText: 'اسم المستخدم',
                      prefixIcon: Icon(Icons.alternate_email, size: 20)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pwCtrl,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: Icon(Icons.lock_outline, size: 20)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: expCtrl,
                    readOnly: !canEditExpiration,
                    textDirection: TextDirection.ltr, textAlign: TextAlign.left,
                    decoration: InputDecoration(
                      labelText: 'تاريخ الانتهاء',
                      hintText: 'YYYY-MM-DD HH:MM:SS',
                      helperText: canEditExpiration
                          ? null
                          : 'لا تملك صلاحية تعديل تاريخ الانتهاء',
                      prefixIcon: const Icon(Icons.calendar_today, size: 20)),
                  ),
                  const SizedBox(height: 20),

                  if (uniquePkgs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.2))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                          const SizedBox(width: 8),
                          const Text('لا توجد باقات متاحة',
                              style: TextStyle(fontSize: 13, color: Colors.orange)),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              await notifier.loadPackages();
                              setSheet(() {});
                            },
                            child: const Icon(Icons.refresh, size: 16, color: Colors.orange),
                          ),
                        ],
                      ),
                    )
                  else ..._buildEditPackageGroups(
                    uniquePkgs, selectedProfileId, originalProfileId,
                    currentPkgName, showAllPackages,
                    (v) => setSheet(() => selectedProfileId = v),
                    () => setSheet(() => showAllPackages = !showAllPackages),
                    Theme.of(ctx),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(height: AppTheme.actionButtonHeight, child: ElevatedButton.icon(
                    onPressed: saving ? null : () async {
                      setSheet(() => saving = true);
                      try {
                        bool anySuccess = true;
                        final newUsername = unCtrl.text.trim();
                        if (newUsername != originalUsername && newUsername.isNotEmpty) {
                          final ok = await notifier.renameSubscriber(id, newUsername);
                          if (!ok) anySuccess = false;
                        }

                        final opId = originalProfileId is int
                            ? originalProfileId
                            : int.tryParse(originalProfileId?.toString() ?? '');
                        if (selectedProfileId != null && selectedProfileId != opId) {
                          final ok = await notifier.changeProfile(id, selectedProfileId!);
                          if (!ok) anySuccess = false;
                        }

                        details['firstname'] = fnCtrl.text.trim();
                        details['lastname'] = lnCtrl.text.trim();
                        details['phone'] = phCtrl.text.trim();
                        if (canEditExpiration) {
                          details['expiration'] = expCtrl.text.trim();
                        } else {
                          details.remove('expiration');
                        }
                        if (pwCtrl.text.isNotEmpty) {
                          details['password'] = pwCtrl.text;
                          details['confirm_password'] = pwCtrl.text;
                        }
                        details.remove('id');
                        details.remove('idx');
                        details.remove('profile_details');

                        final ok = await notifier.updateSubscriber(id, details);
                        if (!ok) anySuccess = false;

                        if (mounted) {
                          Navigator.pop(ctx);
                          _showSnack(anySuccess ? 'تم التعديل بنجاح' : 'فشل بعض التعديلات',
                              success: anySuccess);
                          if (id != null) await notifier.refreshSingleSubscriber(id);
                          if (mounted) context.pop();
                        }
                      } finally {
                        if (mounted) setSheet(() => saving = false);
                      }
                    },
                    icon: saving
                        ? const SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(saving ? 'جاري الحفظ...' : 'حفظ التعديلات'),
                  )),
                  const SizedBox(height: 20),
                ],
              )),
            );
          }),
        );
      },
    );
  }

  // ── Edit Package Groups ────────────────────────────────────────────────
  List<Widget> _buildEditPackageGroups(
    List<PackageModel> allPkgs,
    int? selectedProfileId,
    dynamic originalProfileId,
    String? currentPkgName,
    bool showAll,
    void Function(int) onSelect,
    VoidCallback onToggleShowAll,
    ThemeData theme,
  ) {
    final monthly = allPkgs.where((p) => p.isMonthly).toList();
    final others = allPkgs.where((p) => p.isExtension).toList();
    final opId = originalProfileId is int
        ? originalProfileId
        : int.tryParse(originalProfileId?.toString() ?? '');

    Widget buildCard(PackageModel pkg) {
      final isSelected = selectedProfileId == pkg.idx;
      final isCurrentPkg = pkg.idx == opId;
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: GestureDetector(
          onTap: () => onSelect(pkg.idx),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primary.withOpacity(0.08)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? AppTheme.primary.withOpacity(0.4) : Colors.transparent,
                width: 1.5),
            ),
            child: Row(children: [
              Icon(isSelected ? Icons.check_circle : Icons.circle_outlined,
                  size: 18, color: isSelected ? AppTheme.primary : Colors.grey),
              const SizedBox(width: 10),
              Expanded(child: Row(children: [
                Flexible(child: Text(pkg.name,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    color: isSelected ? AppTheme.primary : null),
                  overflow: TextOverflow.ellipsis)),
                if (isCurrentPkg) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4)),
                    child: const Text('الحالية',
                      style: TextStyle(fontSize: 9, color: Colors.blue,
                          fontWeight: FontWeight.w600)),
                  ),
                ],
              ])),
              Text(AppHelpers.formatMoney(pkg.displayPrice),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: isSelected ? AppTheme.primary : AppTheme.teal600)),
            ]),
          ),
        ),
      );
    }

    final widgets = <Widget>[];

    if (currentPkgName != null) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text('الباقة', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.5))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6)),
            child: Text('الحالية: $currentPkgName',
              style: const TextStyle(fontSize: 10, color: AppTheme.primary)),
          ),
        ]),
      ));
    } else {
      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text('الباقة', style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withOpacity(0.5))),
      ));
    }

    final displayPkgs = showAll ? allPkgs : allPkgs.take(6).toList();
    for (final pkg in displayPkgs) {
      widgets.add(buildCard(pkg));
    }

    if (allPkgs.length > 6) {
      widgets.add(TextButton(
        onPressed: onToggleShowAll,
        child: Text(showAll ? 'عرض أقل' : 'عرض الكل (${allPkgs.length} باقة)',
            style: const TextStyle(fontSize: 12)),
      ));
    }

    return widgets;
  }

  // ── Delete ─────────────────────────────────────────────────────────────
  Future<void> _deleteSubscriber() async {
    final id = _subscriberId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }

    final sub = _readCurrentSubscriber();
    if (sub.hasDebt) {
      _showSnack('لا يمكن حذف مشترك عليه دين: ${AppHelpers.formatMoney(sub.debtAmount.abs())}',
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
      final delId = _subscriberId;
      if (delId != null) ref.read(subscribersProvider.notifier).removeSubscriberFromList(delId);
      context.pop();
    } else {
      _showSnack('فشل حذف المشترك — قد يكون عليه دين', success: false);
    }
  }

  // ── Extend / Renew ─────────────────────────────────────────────────────
  Future<void> _extendSubscription() async {
    final id = _subscriberId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }
    final sub = _readCurrentSubscriber();

    setState(() => _isProcessing = true);
    final notifier = ref.read(subscribersProvider.notifier);
    final extData = await notifier.getExtensionData(id);
    if (!mounted) return;

    if (extData == null) {
      setState(() => _isProcessing = false);
      _showSnack('فشل جلب بيانات التمديد', success: false);
      return;
    }

    final pkgId = extData['profile_id'] ??
        (extData['profile_details'] is Map
            ? extData['profile_details']['id']
            : null) ??
        sub.profileId;

    List<Map<String, dynamic>> allowedPkgs = [];
    if (pkgId != null) {
      final pid = pkgId is int ? pkgId : int.tryParse(pkgId.toString()) ?? 0;
      allowedPkgs = await notifier.getAllowedExtensions(pid);
    }
    if (!mounted) return;
    setState(() => _isProcessing = false);

    final requiredPoints = extData['required_points']?.toString() ?? '0';
    final availablePoints = extData['reward_points_balance']?.toString() ?? '0';
    final notesSigned = _toDouble(
      extData['notes'] ?? extData['comments'] ?? sub.notes,
    );

    if (!mounted) return;

    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String method = 'credit';
        int selectedPkgId = pkgId is int
            ? pkgId
            : int.tryParse(pkgId?.toString() ?? '') ?? 0;
        String? pkgPrice;
        bool submitting = false;

        return StatefulBuilder(builder: (ctx, setSheet) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom,
              left: 20, right: 20, top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  Container(padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.teal600.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.autorenew, color: AppTheme.teal600, size: 20)),
                  const SizedBox(width: 10),
                  Text('تمديد المشترك', style: Theme.of(ctx).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 16),
                _InfoChip(label: 'المشترك', value: sub.fullName),
                _InfoChip(label: 'النقاط المطلوبة', value: '$requiredPoints نقطة'),
                _InfoChip(label: 'النقاط المتاحة', value: '$availablePoints نقطة'),
                if (notesSigned > 0)
                  _InfoChip(
                    label: 'الرصيد (من الملاحظات)',
                    value: AppHelpers.formatMoney(notesSigned),
                  )
                else if (notesSigned < 0)
                  _InfoChip(
                    label: 'الدين (من الملاحظات)',
                    value: AppHelpers.formatMoney(notesSigned.abs()),
                  )
                else
                  const _InfoChip(label: 'دين/رصيد الملاحظات', value: 'لا يوجد'),
                const SizedBox(height: 12),
                if (allowedPkgs.isNotEmpty) ...[
                  Text('الباقة', style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6))),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Theme.of(ctx).colorScheme.outline.withOpacity(0.3)),
                    ),
                    child: Builder(builder: (_) {
                      final seen = <int>{};
                      final filteredPkgs = allowedPkgs
                          .where((p) => !(p['name']?.toString().toLowerCase().contains('pool') ?? false))
                          .where((p) {
                            final pid = p['idx'] ?? p['id'] ?? 0;
                            final id = pid is int ? pid : int.tryParse(pid.toString()) ?? 0;
                            if (id <= 0 || seen.contains(id)) return false;
                            seen.add(id);
                            return true;
                          }).toList();
                      final hasMatch = selectedPkgId > 0 &&
                          filteredPkgs.any((p) {
                            final pid = p['idx'] ?? p['id'] ?? 0;
                            final id = pid is int ? pid : int.tryParse(pid.toString()) ?? 0;
                            return id == selectedPkgId;
                          });
                      return DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: hasMatch ? selectedPkgId : null,
                          isExpanded: true,
                          hint: const Text('اختر الباقة'),
                          items: filteredPkgs.map((p) {
                            final pid = p['idx'] ?? p['id'] ?? 0;
                            final id = pid is int ? pid : int.tryParse(pid.toString()) ?? 0;
                            return DropdownMenuItem<int>(
                              value: id,
                              child: Text(p['name']?.toString() ?? '—', style: const TextStyle(fontSize: 13)),
                            );
                          }).toList(),
                          onChanged: (v) async {
                            if (v == null) return;
                            setSheet(() => selectedPkgId = v);
                            final det = await notifier.getPackageDetails(v);
                            if (det != null) {
                              setSheet(() => pkgPrice = (det['price'] ?? det['monthly_fee'])?.toString());
                            }
                          },
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                Text('طريقة التمديد', style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6))),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: _MethodBtn(
                    icon: Icons.star_rounded, label: 'بالنقاط',
                    selected: method == 'reward_points',
                    onTap: () => setSheet(() => method = 'reward_points'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _MethodBtn(
                    icon: Icons.account_balance_wallet_rounded, label: 'برصيد المدير',
                    selected: method == 'credit',
                    onTap: () => setSheet(() => method = 'credit'),
                  )),
                ]),
                if (method == 'credit' && pkgPrice != null) ...[
                  const SizedBox(height: 8),
                  _InfoChip(label: 'تكلفة التمديد', value: AppHelpers.formatMoney(pkgPrice)),
                ],
                const SizedBox(height: 20),
                SizedBox(height: AppTheme.actionButtonHeight, child: ElevatedButton.icon(
                  onPressed: submitting ? null : () async {
                    setSheet(() => submitting = true);
                    final success = await notifier.extendSubscription(
                      userId: id, profileId: selectedPkgId, method: method);
                    if (mounted) {
                      Navigator.pop(ctx);
                      _showSnack(success ? 'تم التمديد بنجاح' : 'فشل التمديد',
                          success: success);
                      if (success) {
                        if (id != null) {
                          await notifier.refreshSubscriberAfterOperation(id);
                        }
                        final currentSub = _readCurrentSubscriber();
                        final fresh = await notifier.getSubscriberDetails(id);
                        final expDate = fresh?['expiration']?.toString() ?? '';
                        final newDebt = _toDouble(fresh?['notes'] ?? fresh?['comments']);
                        final remDays = fresh?['remaining_days']?.toString() ?? '';
                        // حساب المبلغ المسدد بناءً على طريقة التمديد
                        final paidAmountForMsg = method == 'credit'
                          ? _formatNumber(double.tryParse(pkgPrice ?? '0') ?? 0)
                          : '0'; // نقاط: لا يوجد مبلغ نقدي

                        await _sendWhatsAppFromTemplate('renewal',
                          extraVars: {
                            '{package_price}': _formatNumber(double.tryParse(pkgPrice ?? '0') ?? 0),
                            '{paid_amount}': paidAmountForMsg,
                            '{debt_amount}': newDebt < 0 ? _formatNumber(newDebt.abs()) : '0',
                            '{credit_amount}': newDebt > 0 ? _formatNumber(newDebt) : '0',
                            '{expiry_date}': expDate,
                            '{expiration_date}': expDate,
                            '{days_remaining}': remDays,
                            '{remaining_days}': remDays,
                          });
                        final extPrice = double.tryParse(pkgPrice ?? '0') ?? 0;
                        await _offerPrintReceipt(ReceiptData(
                          subscriberName: currentSub.fullName.isNotEmpty ? currentSub.fullName : currentSub.username,
                          phoneNumber: currentSub.displayPhone,
                          packageName: currentSub.profileName ?? '',
                          packagePrice: extPrice,
                          paidAmount: method == 'credit' ? extPrice : 0,
                          debtAmount: newDebt < 0 ? newDebt.abs() : 0,
                          remainingAmount: newDebt < 0 ? newDebt.abs() : 0,
                          expiryDate: expDate,
                          operationType: 'activation',
                        ));
                        if (mounted) context.pop();
                      }
                    }
                  },
                  icon: submitting
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.autorenew),
                  label: Text(submitting ? 'جاري التمديد...' : 'تمديد'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.teal600),
                )),
                const SizedBox(height: 20),
              ],
            ),
          );
        });
      },
    );
  }

  // ── Activate ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> _fetchSubscriberDiscount(String username) async {
    try {
      final dio = ref.read(backendDioProvider);
      final response = await dio.get('${ApiConstants.discounts}/$username');
      if (response.data is Map &&
          response.data['success'] == true &&
          response.data['data'] != null) {
        return Map<String, dynamic>.from(response.data['data']);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _activateSubscriber() async {
    final id = _subscriberId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }
    final sub = _readCurrentSubscriber();

    setState(() => _isProcessing = true);
    final notifier = ref.read(subscribersProvider.notifier);

    final results = await Future.wait([
      notifier.getActivationData(id),
      notifier.getSubscriberDetails(id),
      _fetchSubscriberDiscount(sub.username),
    ]);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    final activationData = results[0] as Map<String, dynamic>?;
    final userData = results[1] as Map<String, dynamic>?;
    final discountData = results[2] as Map<String, dynamic>?;

    if (activationData == null) {
      _showSnack('فشل جلب بيانات التفعيل', success: false);
      return;
    }

    final originalPrice = _toDouble(activationData['user_price']);
    final discountAmount = discountData != null
        ? _toDouble(discountData['discount_amount'])
        : 0.0;
    final hasDiscount = discountAmount > 0;
    final userPrice = hasDiscount
        ? (originalPrice - discountAmount).clamp(0.0, double.infinity)
        : originalPrice;
    final units = activationData['units'];
    final profileName = activationData['profile_name']?.toString() ?? '—';
    final profileDuration = activationData['profile_duration']?.toString() ?? '—';
    final requiredAmount = activationData['required_amount']?.toString() ?? '—';
    final managerBalance = activationData['manager_balance']?.toString() ?? '—';
    final rewardPoints = activationData['reward_points']?.toString() ?? '0';
    final currentBalance = _toDouble(userData?['notes'] ?? userData?['comments']);

    if (hasDiscount && mounted) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          AppSnackBar.info(context,
              'هذا المشترك لديه خصم ${AppHelpers.formatMoney(discountAmount)}');
        }
      });
    }

    final partialCtrl = TextEditingController();
    final partialFocus = FocusNode();
    bool isCash = false;
    bool isPartialCash = false;
    bool submitting = false;

    if (!mounted) return;

    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + MediaQuery.of(sheetCtx).padding.bottom,
            left: 20, right: 20, top: 16,
          ),
          child: StatefulBuilder(builder: (ctx, setSheet) {
            return SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),

                Row(children: [
                  Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF43A047), Color(0xFF2E7D32)]),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تفعيل المشترك', style: Theme.of(ctx).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(sub.fullName,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                    ],
                  )),
                ]),
                const SizedBox(height: 18),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.teal700.withOpacity(0.08), AppTheme.teal900.withOpacity(0.04)]),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.teal600.withOpacity(0.15)),
                  ),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: _ActivationInfoTile(
                        icon: Icons.wifi_rounded,
                        label: 'الباقة',
                        value: profileName,
                        color: AppTheme.teal600,
                      )),
                      Container(width: 1, height: 40, color: AppTheme.teal600.withOpacity(0.1)),
                      Expanded(child: _ActivationInfoTile(
                        icon: Icons.schedule_rounded,
                        label: 'المدة',
                        value: profileDuration,
                        color: AppTheme.infoColor,
                      )),
                    ]),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.successColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.sell_rounded, size: 18, color: AppTheme.successColor),
                          const SizedBox(width: 8),
                          Text('السعر: ', style: TextStyle(fontSize: 13,
                              color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6))),
                          if (hasDiscount) ...[
                            Text(AppHelpers.formatMoney(originalPrice),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: Colors.grey.shade500)),
                            const SizedBox(width: 8),
                          ],
                          Text(AppHelpers.formatMoney(userPrice),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                                color: AppTheme.successColor)),
                        ],
                      ),
                    ),
                    if (hasDiscount) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.secondary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.secondary.withOpacity(0.2)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.redeem_rounded, size: 18, color: AppTheme.secondary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            'خصم خاص: ${AppHelpers.formatMoney(discountAmount)}',
                            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13,
                                fontWeight: FontWeight.w700, color: AppTheme.secondary),
                          )),
                        ]),
                      ),
                    ],
                  ]),
                ),

                if (currentBalance != 0) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: (currentBalance < 0 ? Colors.red : Colors.green).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (currentBalance < 0 ? Colors.red : Colors.green).withOpacity(0.12)),
                    ),
                    child: Row(children: [
                      Icon(
                        currentBalance < 0 ? Icons.warning_amber_rounded : Icons.account_balance_wallet_rounded,
                        size: 18, color: currentBalance < 0 ? Colors.red : Colors.green),
                      const SizedBox(width: 8),
                      Text(currentBalance < 0 ? 'دين سابق: ' : 'رصيد سابق: ',
                          style: TextStyle(fontSize: 12,
                            color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6))),
                      Text(AppHelpers.formatMoney(currentBalance.abs()),
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                            color: currentBalance < 0 ? Colors.red : Colors.green)),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),

                Text('نوع الدفع', style: TextStyle(fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6))),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _MethodBtn(icon: Icons.money_rounded, label: 'نقدي',
                    selected: isCash && !isPartialCash,
                    onTap: () => setSheet(() { isCash = true; isPartialCash = false; partialCtrl.clear(); }),
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: _MethodBtn(icon: Icons.tune_rounded, label: 'جزئي',
                    selected: isCash && isPartialCash,
                    onTap: () => setSheet(() { isCash = true; isPartialCash = true; }),
                  )),
                  const SizedBox(width: 6),
                  Expanded(child: _MethodBtn(icon: Icons.schedule_rounded, label: 'آجل',
                    selected: !isCash,
                    onTap: () => setSheet(() { isCash = false; isPartialCash = false; partialCtrl.clear(); }),
                  )),
                ]),

                if (isCash && isPartialCash) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: partialCtrl,
                    focusNode: partialFocus,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [_ThousandsFormatter()],
                    decoration: InputDecoration(
                      labelText: 'المبلغ المدفوع نقداً',
                      suffixText: 'IQD',
                      prefixIcon: const Icon(Icons.monetization_on_outlined, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          partialCtrl.clear();
                          partialFocus.unfocus();
                          setSheet(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _QuickAmountChips(
                    amounts: _buildPartialQuickAmounts(userPrice),
                    selectedAmount: _parseMoney(partialCtrl.text),
                    enabled: true,
                    onSelected: (v) {
                      partialFocus.unfocus();
                      partialCtrl.text = _formatNumber(v);
                      setSheet(() {});
                    },
                  ),
                ],
                const SizedBox(height: 14),

                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: partialCtrl,
                  builder: (ctx3, partialVal, _) {
                    final livePartial = _parseMoney(partialVal.text);
                    final partialShortfall =
                        livePartial < userPrice ? userPrice - livePartial : 0.0;
                    final partialSurplus =
                        livePartial > userPrice ? livePartial - userPrice : 0.0;
                    final creditConsumed = currentBalance > 0 && partialShortfall > 0
                        ? (currentBalance < partialShortfall
                            ? currentBalance
                            : partialShortfall)
                        : 0.0;
                    final remainingDebtFromShortfall =
                        currentBalance > 0 && partialShortfall > creditConsumed
                            ? partialShortfall - creditConsumed
                            : currentBalance <= 0
                                ? partialShortfall
                                : 0.0;
                    final debtSettled =
                        currentBalance < 0 && partialSurplus > 0
                            ? (currentBalance.abs() < partialSurplus
                                ? currentBalance.abs()
                                : partialSurplus)
                            : 0.0;
                    final creditAddedFromPayment =
                        currentBalance < 0 && partialSurplus > debtSettled
                            ? partialSurplus - debtSettled
                            : currentBalance >= 0
                                ? partialSurplus
                                : 0.0;
                    double liveDebtPreview = currentBalance;
                    if (isCash && !isPartialCash) {
                      liveDebtPreview = currentBalance;
                    } else if (isCash && isPartialCash) {
                      liveDebtPreview = currentBalance - (userPrice - livePartial);
                    } else {
                      liveDebtPreview = currentBalance - userPrice;
                    }

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ملخص العملية', style: TextStyle(fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                          const SizedBox(height: 10),
                          _SummaryRow(label: 'سعر الباقة', value: AppHelpers.formatMoney(userPrice)),
                          if (hasDiscount)
                            _SummaryRow(
                              label: 'خصم',
                              value: '-${AppHelpers.formatMoney(discountAmount)}',
                              valueColor: AppTheme.secondary,
                            ),
                          if (currentBalance != 0)
                            _SummaryRow(
                              label: currentBalance < 0 ? 'دين سابق' : 'رصيد سابق',
                              value: currentBalance < 0
                                  ? '-${AppHelpers.formatMoney(currentBalance.abs())}'
                                  : '+${AppHelpers.formatMoney(currentBalance)}',
                              valueColor: currentBalance < 0 ? Colors.red : Colors.green,
                            ),
                          if (isCash && !isPartialCash)
                            _SummaryRow(label: 'الدفع', value: 'نقدي كامل',
                                valueColor: Colors.green),
                          if (isCash && isPartialCash) ...[
                            if (livePartial > 0)
                              _SummaryRow(label: 'المدفوع نقداً', value: AppHelpers.formatMoney(livePartial),
                                  valueColor: Colors.green),
                            if (creditConsumed > 0)
                              _SummaryRow(
                                label: 'يخصم من الرصيد',
                                value: AppHelpers.formatMoney(creditConsumed),
                                valueColor: Colors.orange,
                              ),
                            if (debtSettled > 0)
                              _SummaryRow(
                                label: 'تسديد من الدين السابق',
                                value: AppHelpers.formatMoney(debtSettled),
                                valueColor: Colors.green,
                              ),
                            if (creditAddedFromPayment > 0)
                              _SummaryRow(
                                label: 'يضاف إلى الرصيد',
                                value: AppHelpers.formatMoney(creditAddedFromPayment),
                                valueColor: Colors.green,
                              ),
                            if (remainingDebtFromShortfall > 0)
                              _SummaryRow(
                                label: currentBalance > 0
                                    ? 'المتبقي كدين'
                                    : currentBalance < 0
                                        ? 'يضاف إلى الدين'
                                        : 'يضاف كدين',
                                value: AppHelpers.formatMoney(remainingDebtFromShortfall),
                                valueColor: currentBalance < 0 ? Colors.red : Colors.orange,
                              ),
                          ],
                          if (!isCash)
                            _SummaryRow(label: 'الدفع', value: 'آجل (يضاف كدين)',
                                valueColor: Colors.orange),
                          const Divider(height: 16),
                          Row(children: [
                            Text('بعد التفعيل:', style: TextStyle(fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: (liveDebtPreview < 0 ? Colors.red : Colors.green).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                liveDebtPreview < 0
                                    ? 'دين ${AppHelpers.formatMoney(liveDebtPreview.abs())}'
                                    : liveDebtPreview > 0
                                        ? 'رصيد ${AppHelpers.formatMoney(liveDebtPreview)}'
                                        : 'بدون دين أو رصيد',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                    color: liveDebtPreview < 0 ? Colors.red
                                        : liveDebtPreview > 0 ? Colors.green
                                        : Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5)),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),

                SizedBox(height: AppTheme.actionButtonHeight, child: ElevatedButton.icon(
                  onPressed: submitting ? null : () async {
                    final cashAmount = _parseMoney(partialCtrl.text);
                    setSheet(() => submitting = true);
                    final notifier = ref.read(subscribersProvider.notifier);
                    final success = await notifier.activateSubscriber(
                      userId: id,
                      userPrice: userPrice,
                      activationUnits: units,
                      currentNotes: currentBalance.toString(),
                      isCash: isCash,
                      isPartialCash: isPartialCash,
                      partialCashAmount: cashAmount,
                      packageName: profileName,
                      originalPrice: originalPrice,
                      discountAmount: discountAmount > 0 ? discountAmount : 0,
                    );
                    if (mounted) {
                      Navigator.pop(ctx);
                      _showSnack(success ? 'تم التفعيل بنجاح' : 'فشل التفعيل', success: success);
                      if (success) {
                        if (id != null) {
                          final paymentLabel = isCash
                              ? (isPartialCash ? 'نقدي جزئي' : 'نقدي')
                              : 'غير نقدي';
                          if (isCash) {
                            final actualPaidAmount = isPartialCash ? cashAmount : userPrice;
                            await notifier.refreshSubscriberAfterOperation(
                              id,
                              refreshLastPayments: true,
                              paymentUsername: sub.username,
                              paymentDescription:
                                  'تفعيل المشترك ${sub.username} | الباقة: $profileName | السعر: ${_formatNumber(userPrice)} IQD | $paymentLabel',
                              paymentAmount: actualPaidAmount,
                              paymentActionType: 'SUBSCRIBER_ACTIVATE',
                              paymentMovementLabel: isPartialCash
                                  ? 'تفعيل نقدي جزئي'
                                  : 'تفعيل نقدي',
                              paymentType: paymentLabel,
                            );
                          } else {
                            await notifier.refreshSubscriberAfterOperation(id);
                          }
                        }
                        final currentSub = _readCurrentSubscriber();
                        final fresh = await notifier.getSubscriberDetails(id);
                        final newDebt = _toDouble(fresh?['notes'] ?? fresh?['comments']);
                        final freshExpDate = fresh?['expiration']?.toString() ?? '';
                        final freshRemDays = _calcRemainingDays(freshExpDate);
                        final actualPaidAmount = isCash
                          ? (isPartialCash ? cashAmount : userPrice)
                          : 0.0;
                        final paidAmountForMsg = _formatNumber(actualPaidAmount);
                        await _sendWhatsAppFromTemplate('activation_notice', extraVars: {
                          '{package_name}': profileName,
                          '{package_price}': _formatNumber(userPrice),
                          '{paid_amount}': paidAmountForMsg,
                          '{debt_amount}': newDebt < 0 ? _formatNumber(newDebt.abs()) : '0',
                          '{credit_amount}': newDebt > 0 ? _formatNumber(newDebt) : '0',
                          '{expiry_date}': freshExpDate,
                          '{expiration_date}': freshExpDate,
                          '{remaining_days}': freshRemDays,
                          '{days_remaining}': freshRemDays,
                        });
                        await _offerPrintReceipt(ReceiptData(
                          subscriberName: currentSub.fullName.isNotEmpty ? currentSub.fullName : currentSub.username,
                          phoneNumber: currentSub.displayPhone,
                          packageName: profileName,
                          packagePrice: userPrice,
                          paidAmount: actualPaidAmount,
                          debtAmount: newDebt < 0 ? newDebt.abs() : 0,
                          remainingAmount: newDebt < 0 ? newDebt.abs() : 0,
                          expiryDate: fresh?['expiration']?.toString() ?? '',
                          operationType: 'activation',
                        ));
                        if (mounted) context.pop();
                      }
                    }
                  },
                  icon: submitting
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.bolt_rounded),
                  label: Text(submitting ? 'جاري التفعيل...' : 'تفعيل الآن'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.successColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                )),
                const SizedBox(height: 20),
              ],
            ));
          }),
        );
      },
    );
  }

  List<double> _buildPartialQuickAmounts(double price) {
    final amounts = <double>[];
    final quarter = (price * 0.25).roundToDouble();
    final half = (price * 0.5).roundToDouble();
    final threeQ = (price * 0.75).roundToDouble();
    for (final v in [quarter, half, threeQ]) {
      if (v > 0 && v < price) amounts.add(v);
    }
    return amounts;
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll(',', '').trim()) ?? 0;
    return 0;
  }

  String _calcRemainingDays(String? expiration) {
    if (expiration == null || expiration.isEmpty) return '0';
    try {
      final s = expiration.trim();
      DateTime? exp;
      if (s.contains('T') || s.contains('+')) {
        exp = DateTime.tryParse(s);
      } else {
        exp = DateTime.tryParse('${s.replaceAll(' ', 'T')}+03:00');
      }
      if (exp == null) return '0';
      final diff = exp.difference(DateTime.now());
      if (diff.isNegative) return '0';
      return '${diff.inDays}';
    } catch (_) {
      return '0';
    }
  }

  Future<void> _sendWhatsAppFromTemplate(String templateType, {
    Map<String, String>? extraVars,
  }) async {
    final sub = _readCurrentSubscriber();
    final phone = sub.displayPhone;
    if (phone.isEmpty) {
      if (mounted) AppSnackBar.warning(context, 'لا يوجد رقم هاتف للمشترك');
      return;
    }

    try {
      var waState = ref.read(whatsappProvider);
      if (!waState.status.connected) {
        await ref.read(whatsappProvider.notifier).reconnect();
        await Future.delayed(const Duration(seconds: 3));
        await ref.read(whatsappProvider.notifier).fetchStatus();
        waState = ref.read(whatsappProvider);
        if (!waState.status.connected) {
          if (mounted) {
            AppSnackBar.whatsappError(context, 'واتساب غير متصل',
                detail: 'يرجى الاتصال بواتساب أولاً من الإعدادات');
          }
          return;
        }
      }

      final templates = ref.read(templatesProvider).templates;
      if (templates.isEmpty) {
        await ref.read(templatesProvider.notifier).loadTemplates();
      }
      final allTemplates = ref.read(templatesProvider).templates;
      final match = allTemplates.where(
        (t) => t.templateType == templateType && t.isActive,
      );
      if (match.isEmpty) {
        if (mounted) {
          AppSnackBar.warning(context, 'القالب غير متوفر أو معطل',
              detail: 'لا يوجد قالب "$templateType" مفعّل');
        }
        return;
      }

      final debtVal = sub.hasDebt ? _formatNumber(sub.debtAmount.abs()) : '0';
      final creditVal = sub.debtAmount > 0 ? _formatNumber(sub.debtAmount) : '0';
      final pkgPriceFormatted = _formatNumber(double.tryParse(sub.price ?? '0') ?? 0);
      final displayName = sub.fullName.isNotEmpty ? sub.fullName : sub.username;

      String msg = match.first.messageContent;
      final vars = {
        '{subscriber_name}': displayName,
        '{firstname}': sub.firstname.isNotEmpty ? sub.firstname : sub.username,
        '{lastname}': sub.lastname,
        '{phone}': sub.displayPhone,
        '{remaining_days}': '${sub.remainingDays ?? 0}',
        '{days_remaining}': '${sub.remainingDays ?? 0}',
        '{expiration_date}': sub.expiration ?? '',
        '{expiry_date}': sub.expiration ?? '',
        '{package_name}': sub.profileName ?? '',
        '{package_price}': pkgPriceFormatted,
        '{debt_amount}': debtVal,
        '{credit_amount}': creditVal,
        '{discount_amount}': '0',
        '{discounted_price}': pkgPriceFormatted,
        '{paid_amount}': '0',
        '{username}': sub.username,
        ...?extraVars,
      };
      vars.forEach((k, v) => msg = msg.replaceAll(k, v));

      final result =
          await ref.read(whatsappProvider.notifier).sendMessage(phone, msg);
      if (!mounted) return;
      if (result.success) {
        AppSnackBar.whatsapp(context, 'تم إرسال الرسالة بنجاح');
      } else {
        AppSnackBar.whatsappError(context, 'فشل إرسال الرسالة',
            detail: result.error);
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.whatsappError(context, 'فشل إرسال الرسالة',
            detail: 'خطأ غير متوقع');
      }
    }
  }

  // ── Pay Debt (تسديد دين) ──────────────────────────────────────────────
  Future<void> _showPayDebtSheet() async {
    final id = _subscriberId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }
    final sub = _readCurrentSubscriber();

    setState(() => _isProcessing = true);
    final notifier = ref.read(subscribersProvider.notifier);
    final details = await notifier.getSubscriberDetails(id);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    final currentNotes = _toDouble(details?['notes'] ?? details?['comments']);
    final currentDebt = currentNotes < 0 ? currentNotes.abs() : 0.0;

    if (currentDebt <= 0) {
      _showSnack('لا يوجد دين على هذا المشترك', success: false);
      return;
    }

    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final amountFocusPay = FocusNode();
    bool payAll = false;
    bool submitting = false;

    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + MediaQuery.of(sheetCtx).padding.bottom,
            left: 20, right: 20, top: 16,
          ),
          child: StatefulBuilder(builder: (ctx, setSheet) {
            return SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF43A047), Color(0xFF2E7D32)]),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.payments_rounded, color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('تسديد دين', style: Theme.of(ctx).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(sub.fullName,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                    ],
                  )),
                ]),
                const SizedBox(height: 16),

                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: amountCtrl,
                  builder: (ctx2, val, _) {
                    final effectiveAmount = payAll ? currentDebt : _parseMoney(val.text);
                    final payRatio = currentDebt > 0
                        ? (effectiveAmount / currentDebt).clamp(0.0, 1.0)
                        : 0.0;
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.red.withOpacity(0.12)),
                      ),
                      child: Column(
                        children: [
                          Text('الدين الحالي',
                              style: TextStyle(fontSize: 12,
                                color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                          const SizedBox(height: 4),
                          Text(AppHelpers.formatMoney(currentDebt),
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                                color: Colors.red)),
                          if (effectiveAmount > 0) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: payRatio,
                                minHeight: 6,
                                backgroundColor: Colors.red.withOpacity(0.15),
                                valueColor: const AlwaysStoppedAnimation(Colors.green),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${(payRatio * 100).toStringAsFixed(0)}% من الدين',
                              style: TextStyle(fontSize: 11,
                                color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5)),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: amountCtrl,
                  focusNode: amountFocusPay,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  enabled: !payAll,
                  inputFormatters: [_ThousandsFormatter()],
                  decoration: InputDecoration(
                    labelText: 'المبلغ المسدد',
                    suffixText: 'IQD',
                    prefixIcon: const Icon(Icons.monetization_on_outlined, size: 20),
                    suffixIcon: !payAll ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        amountCtrl.clear();
                        amountFocusPay.unfocus();
                        setSheet(() {});
                      },
                    ) : null,
                  ),
                ),
                const SizedBox(height: 10),

                _QuickAmountChips(
                  amounts: _buildPayDebtQuickAmounts(currentDebt),
                  selectedAmount: payAll ? currentDebt : _parseMoney(amountCtrl.text),
                  enabled: !payAll,
                  onSelected: (v) {
                    amountFocusPay.unfocus();
                    amountCtrl.text = _formatNumber(v);
                    setSheet(() {});
                  },
                ),
                const SizedBox(height: 6),

                GestureDetector(
                  onTap: () => setSheet(() {
                    payAll = !payAll;
                    if (payAll) {
                      amountCtrl.text = _formatNumber(currentDebt);
                    } else {
                      amountCtrl.clear();
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: payAll
                          ? Colors.green.withOpacity(0.08)
                          : Theme.of(ctx).colorScheme.surfaceContainerHighest.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: payAll ? Colors.green.withOpacity(0.3) : Colors.transparent),
                    ),
                    child: Row(children: [
                      Icon(payAll ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 20, color: payAll ? Colors.green : Colors.grey),
                      const SizedBox(width: 8),
                      const Text('تسديد كامل الدين', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      if (payAll)
                        Text(AppHelpers.formatMoney(currentDebt),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green)),
                    ]),
                  ),
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: notesCtrl,
                  maxLines: 2,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: Icon(Icons.note_outlined, size: 20)),
                  ),
                ),

                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: amountCtrl,
                  builder: (ctx2, val, _) {
                    final liveAmount = _parseMoney(val.text);
                    final liveEffective = payAll ? currentDebt : liveAmount;
                    final livePreview = currentNotes + liveEffective;
                    if (liveEffective <= 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: livePreview >= 0 ? Colors.green.withOpacity(0.06) : Colors.orange.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: livePreview >= 0 ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15)),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: (livePreview >= 0 ? Colors.green : Colors.orange).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                            child: Icon(livePreview >= 0 ? Icons.check_circle_rounded : Icons.timelapse_rounded,
                                size: 18, color: livePreview >= 0 ? Colors.green : Colors.orange),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(livePreview >= 0 ? 'بعد التسديد' : 'الدين المتبقي',
                                  style: TextStyle(fontSize: 11,
                                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                              const SizedBox(height: 2),
                              Text(
                                livePreview >= 0
                                    ? 'رصيد ${AppHelpers.formatMoney(livePreview)}'
                                    : AppHelpers.formatMoney(livePreview.abs()),
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                    color: livePreview >= 0 ? Colors.green : Colors.orange),
                              ),
                            ],
                          )),
                        ]),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: amountCtrl,
                  builder: (ctx2, val, _) {
                    final btnAmount = _parseMoney(val.text);
                    return SizedBox(height: AppTheme.actionButtonHeight, child: ElevatedButton.icon(
                      onPressed: submitting || (!payAll && btnAmount <= 0) ? null : () async {
                        final payAmount = payAll ? currentDebt : btnAmount;
                        setSheet(() => submitting = true);
                        final success = await notifier.payDebt(
                          userId: id,
                          username: sub.username,
                          amount: payAmount,
                          paymentNotes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                        );
                        if (mounted) {
                          Navigator.pop(ctx);
                          _showSnack(success ? 'تم التسديد بنجاح' : 'فشل التسديد', success: success);
                          if (success) {
                            if (id != null) {
                              await notifier.refreshSubscriberAfterOperation(
                                id,
                                refreshLastPayments: true,
                                paymentUsername: sub.username,
                                paymentDescription:
                                    'تسديد دين ${_formatNumber(payAmount)} IQD من المشترك ${sub.username}',
                                paymentAmount: payAmount,
                                paymentActionType: 'BALANCE_DEDUCT',
                                paymentMovementLabel: 'تسديد دين',
                              );
                            }
                            final currentSub = _readCurrentSubscriber();
                            final fresh = await notifier.getSubscriberDetails(id);
                            final newDebt = _toDouble(fresh?['notes'] ?? fresh?['comments']);
                            final freshExpDate2 = fresh?['expiration']?.toString() ?? '';
                            final freshRemDays2 = _calcRemainingDays(freshExpDate2);
                            await _sendWhatsAppFromTemplate('payment_confirmation',
                              extraVars: {
                                '{paid_amount}': _formatNumber(payAmount),
                                '{debt_amount}': newDebt < 0 ? _formatNumber(newDebt.abs()) : '0',
                                '{credit_amount}': newDebt > 0 ? _formatNumber(newDebt) : '0',
                                '{expiry_date}': freshExpDate2,
                                '{expiration_date}': freshExpDate2,
                                '{remaining_days}': freshRemDays2,
                                '{days_remaining}': freshRemDays2,
                              });
                            await _offerPrintReceipt(ReceiptData(
                              subscriberName: currentSub.fullName.isNotEmpty ? currentSub.fullName : currentSub.username,
                              phoneNumber: currentSub.displayPhone,
                              packageName: currentSub.profileName ?? '',
                              packagePrice: 0,
                              paidAmount: payAmount,
                              debtAmount: newDebt < 0 ? newDebt.abs() : 0,
                              remainingAmount: newDebt < 0 ? newDebt.abs() : 0,
                              expiryDate: fresh?['expiration']?.toString() ?? '',
                              operationType: 'debt_payment',
                            ));
                            if (mounted) context.pop();
                          }
                        }
                      },
                      icon: submitting
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.payments_rounded),
                      label: Text(submitting ? 'جاري التسديد...' : 'تسديد'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ));
                  },
                ),
                const SizedBox(height: 20),
              ],
            ));
          }),
        );
      },
    );
  }

  List<double> _buildPayDebtQuickAmounts(double debt) {
    final amounts = <double>[];
    for (final v in [5000, 10000, 15000, 25000, 50000]) {
      if (v < debt) amounts.add(v.toDouble());
    }
    return amounts;
  }

  // ── Add Debt (إضافة دين) ──────────────────────────────────────────────
  Future<void> _showAddDebtSheet() async {
    final id = _subscriberId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }
    final sub = _readCurrentSubscriber();

    setState(() => _isProcessing = true);
    final notifier = ref.read(subscribersProvider.notifier);
    final details = await notifier.getSubscriberDetails(id);
    if (!mounted) return;
    setState(() => _isProcessing = false);

    final currentNotes = _toDouble(details?['notes'] ?? details?['comments']);
    final currentDebt = currentNotes < 0 ? currentNotes.abs() : 0.0;
    final currentCredit = currentNotes > 0 ? currentNotes : 0.0;

    final amountCtrl = TextEditingController();
    final commentCtrl = TextEditingController();
    final amountFocusAdd = FocusNode();
    bool submitting = false;

    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + MediaQuery.of(sheetCtx).padding.bottom,
            left: 20, right: 20, top: 16,
          ),
          child: StatefulBuilder(builder: (ctx, setSheet) {
            return SingleChildScrollView(child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Row(children: [
                  Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF9A825), Color(0xFFF57F17)]),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.add_card_rounded, color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('إضافة دين', style: Theme.of(ctx).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                      Text(sub.fullName,
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                    ],
                  )),
                ]),
                const SizedBox(height: 16),

                Row(children: [
                  if (currentDebt > 0)
                    Expanded(child: _DebtInfoCard(
                      icon: Icons.trending_down_rounded,
                      label: 'الدين الحالي',
                      value: AppHelpers.formatMoney(currentDebt),
                      color: Colors.red,
                    )),
                  if (currentDebt > 0 && currentCredit > 0)
                    const SizedBox(width: 10),
                  if (currentCredit > 0)
                    Expanded(child: _DebtInfoCard(
                      icon: Icons.account_balance_wallet_rounded,
                      label: 'الرصيد الحالي',
                      value: AppHelpers.formatMoney(currentCredit),
                      color: Colors.green,
                    )),
                  if (currentDebt <= 0 && currentCredit <= 0)
                    Expanded(child: _DebtInfoCard(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'الرصيد',
                      value: 'لا يوجد دين أو رصيد',
                      color: Colors.grey,
                    )),
                ]),
                const SizedBox(height: 16),

                TextField(
                  controller: amountCtrl,
                  focusNode: amountFocusAdd,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [_ThousandsFormatter()],
                  decoration: InputDecoration(
                    labelText: 'قيمة الدين المضاف',
                    suffixText: 'IQD',
                    prefixIcon: const Icon(Icons.monetization_on_outlined, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        amountCtrl.clear();
                        amountFocusAdd.unfocus();
                        setSheet(() {});
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                _QuickAmountChips(
                  amounts: const [5000.0, 10000.0, 15000.0, 25000.0, 35000.0, 50000.0],
                  selectedAmount: _parseMoney(amountCtrl.text),
                  enabled: true,
                  onSelected: (v) {
                    amountFocusAdd.unfocus();
                    amountCtrl.text = _formatNumber(v);
                    setSheet(() {});
                  },
                ),
                const SizedBox(height: 10),

                TextField(
                  controller: commentCtrl,
                  maxLines: 2,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: Icon(Icons.note_outlined, size: 20)),
                  ),
                ),

                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: amountCtrl,
                  builder: (ctx2, val, _) {
                    final liveAmount = _parseMoney(val.text);
                    final livePreview = currentNotes - liveAmount;
                    if (liveAmount <= 0) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red.withOpacity(0.15)),
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.warning_amber_rounded,
                                size: 18, color: Colors.red),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('الدين بعد الإضافة',
                                  style: TextStyle(fontSize: 11,
                                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.5))),
                              const SizedBox(height: 2),
                              Row(children: [
                                Text(AppHelpers.formatMoney(currentDebt),
                                    style: TextStyle(fontSize: 12,
                                      color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.4),
                                      decoration: TextDecoration.lineThrough)),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Icon(Icons.arrow_forward, size: 14, color: Colors.red)),
                                Text(AppHelpers.formatMoney(livePreview.abs()),
                                    style: const TextStyle(fontSize: 14,
                                      fontWeight: FontWeight.w700, color: Colors.red)),
                              ]),
                            ],
                          )),
                        ]),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: amountCtrl,
                  builder: (ctx2, val, _) {
                    final btnAmount = _parseMoney(val.text);
                    return SizedBox(height: AppTheme.actionButtonHeight, child: ElevatedButton.icon(
                      onPressed: submitting || btnAmount <= 0 ? null : () async {
                        final addPreview = currentNotes - btnAmount;
                        final confirmed = await showDialog<bool>(
                          context: ctx,
                          builder: (dlgCtx) => AlertDialog(
                            title: const Text('تأكيد إضافة الدين',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            content: Text(
                              'سيتم إضافة ${AppHelpers.formatMoney(btnAmount)} كدين على "${sub.fullName}".\n'
                              'الدين الجديد: ${AppHelpers.formatMoney(addPreview.abs())}',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dlgCtx, false),
                                child: const Text('إلغاء'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(dlgCtx, true),
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.warningColor),
                                child: const Text('تأكيد'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true) return;

                        setSheet(() => submitting = true);
                        final success = await notifier.addDebt(
                          userId: id,
                          username: sub.username,
                          amount: btnAmount,
                          comment: commentCtrl.text.trim().isEmpty ? null : commentCtrl.text.trim(),
                        );
                        if (mounted) {
                          Navigator.pop(ctx);
                          _showSnack(success ? 'تم إضافة الدين بنجاح' : 'فشل إضافة الدين', success: success);
                          if (success) {
                            if (id != null) {
                              await notifier.refreshSubscriberAfterOperation(id);
                            }
                            final currentSub = _readCurrentSubscriber();
                            await _offerPrintReceipt(ReceiptData(
                              subscriberName: currentSub.fullName.isNotEmpty ? currentSub.fullName : currentSub.username,
                              phoneNumber: currentSub.displayPhone,
                              packageName: currentSub.profileName ?? '',
                              debtAmount: btnAmount,
                              remainingAmount: btnAmount,
                              operationType: 'debt_add',
                            ));
                            if (mounted) context.pop();
                          }
                        }
                      },
                      icon: submitting
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add_card_rounded),
                      label: Text(submitting ? 'جاري الإضافة...' : 'إضافة دين'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.warningColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ));
                  },
                ),
                const SizedBox(height: 20),
              ],
            ));
          }),
        );
      },
    );
  }

  // ── Toggle Enable/Disable ─────────────────────────────────────────────
  Future<void> _toggleSubscriber({required bool enable}) async {
    final id = _subscriberId;
    if (id == null) {
      _showSnack('معرف المشترك غير متوفر', success: false);
      return;
    }
    final sub = _readCurrentSubscriber();

    final action = enable ? 'تفعيل الحساب' : 'تعطيل الحساب';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تأكيد $action'),
        content: Text('هل تريد $action للمشترك "${sub.fullName}"؟'),
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
      final id = _subscriberId;
      if (id != null) await ref.read(subscribersProvider.notifier).refreshSingleSubscriber(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = _watchCurrentSubscriber();
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
                            label: sub.hasDebt
                                ? 'الدين'
                                : sub.hasCredit
                                    ? 'الرصيد'
                                    : 'الدين',
                            value: sub.hasDebt
                                ? AppHelpers.formatMoney(sub.debtAmount.abs())
                                : sub.hasCredit
                                    ? '+${AppHelpers.formatMoney(sub.debtAmount)}'
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
                    _PhoneDetailRow(
                      value: AppHelpers.formatPhone(sub.displayPhone),
                      enabled: sub.displayPhone.trim().isNotEmpty,
                      onCall: () {
                        _launchPhoneCall();
                      },
                      onWhatsApp: () {
                        _launchWhatsAppChat();
                      },
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
                      icon: Icons.credit_card,
                      label: 'الدين / الرصيد',
                      value: sub.hasDebt
                          ? '${AppHelpers.formatMoney(sub.debtAmount.abs())} (مديون)'
                          : sub.hasCredit
                              ? '+${AppHelpers.formatMoney(sub.debtAmount)} (رصيد)'
                              : 'لا يوجد',
                      valueColor: sub.hasDebt ? Colors.red : sub.hasCredit ? Colors.green : null,
                    ),
                    Builder(builder: (_) {
                      final lp = ref.watch(subscribersProvider).lastPayments[sub.username];
                      if (lp == null) return const SizedBox.shrink();
                      final createdAt = lp['created_at']?.toString();
                      if (createdAt == null) return const SizedBox.shrink();
                      final date = DateTime.tryParse(createdAt);
                      if (date == null) return const SizedBox.shrink();
                      final daysAgo = DateTime.now().difference(date).inDays;
                      if (daysAgo > 30) return const SizedBox.shrink();
                      final timeLabel = daysAgo == 0 ? 'اليوم' : 'منذ $daysAgo يوم';
                      final actionType = lp['action_type']?.toString();
                      final paymentType = lp['payment_type']?.toString() ?? '';
                      final movementLabel =
                          lp['movement_label']?.toString().trim().isNotEmpty == true
                              ? lp['movement_label'].toString().trim()
                              : actionType == 'SUBSCRIBER_ACTIVATE'
                                  ? (paymentType.contains('جزئي')
                                      ? 'تفعيل نقدي جزئي'
                                      : 'تفعيل نقدي')
                                  : 'تسديد دين';
                      final rawAmount = lp['amount'];
                      final amountValue = rawAmount is num
                          ? rawAmount.toDouble()
                          : double.tryParse(rawAmount?.toString() ?? '');
                      final desc = lp['action_description']?.toString() ?? '';
                      final amountText = amountValue != null && amountValue > 0
                          ? '${AppHelpers.formatMoney(amountValue)} IQD'
                          : (RegExp(r'([\d,.-]+)\s*IQD').firstMatch(desc)?.group(0) ?? '');
                      return _DetailRow(
                        icon: Icons.monetization_on_rounded,
                        label: 'آخر حركة مالية',
                        value:
                            '$movementLabel — $timeLabel${amountText.isNotEmpty ? ' — $amountText' : ''}',
                        valueColor: AppTheme.teal600,
                      );
                    }),
                  ],
                ),

                const SizedBox(height: 80),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isProcessing ? null : () => _showActionsSheet(isEnabled),
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.apps_rounded, color: Colors.white, size: 26),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  static String _formatPhone(String phone) {
    String cleaned = phone.replaceAll(RegExp(r'[\s\-\(\)\+]'), '');
    if (cleaned.startsWith('07')) return '964${cleaned.substring(1)}';
    if (cleaned.startsWith('7') && cleaned.length == 10) return '964$cleaned';
    return cleaned;
  }

  // ── Generate Info Link ───────────────────────────────────────────────
  Future<void> _generateInfoLink() async {
    final sub = _readCurrentSubscriber();
    final rawPhone = sub.phone;

    final waState = ref.read(whatsappProvider);
    if (!waState.status.connected) {
      _showSnack('واتساب غير متصل', success: false, detail: 'يرجى الاتصال بواتساب أولاً');
      return;
    }

    if (rawPhone == null || rawPhone.isEmpty) {
      _showSnack('لا يوجد رقم هاتف للمشترك', success: false);
      return;
    }

    final phone = _formatPhone(rawPhone);
    setState(() => _isProcessing = true);
    try {
      final dio = ref.read(backendDioProvider);
      final storage = ref.read(storageServiceProvider);
      final adminId = await storage.getAdminId();
      final adminToken = await storage.getToken();

      if (adminToken == null || adminToken.isEmpty) {
        if (mounted) AppSnackBar.error(context, 'فشل توليد الرابط', detail: 'توكن المدير غير متوفر - أعد تسجيل الدخول');
        return;
      }

      final userId = sub.idx ?? '';
      if (userId.isEmpty) {
        if (mounted) AppSnackBar.error(context, 'فشل توليد الرابط', detail: 'معرف المشترك غير متوفر');
        return;
      }

      final body = {
        'userId': userId,
        'username': sub.username,
        'adminId': adminId ?? 'unknown',
        'adminToken': adminToken,
        'price': sub.notes ?? sub.price ?? '0',
        'notes': sub.notes ?? '',
        'profileName': sub.profileName ?? '',
        'profileId': (sub.profileId ?? '').toString(),
      };

      late final dynamic linkResponse;
      try {
        debugPrint('[GEN-LINK] POST ${ApiConstants.generateUserLink}  body=$body');
        final res = await dio.post(ApiConstants.generateUserLink, data: body);
        linkResponse = res.data;
        debugPrint('[GEN-LINK] Response: $linkResponse');
      } on DioException catch (dioErr) {
        final errMsg = dioErr.response?.data?['message']?.toString()
            ?? dioErr.message ?? 'خطأ في الاتصال';
        debugPrint('[GEN-LINK] DioError: ${dioErr.response?.statusCode} $errMsg');
        if (mounted) AppSnackBar.error(context, 'فشل توليد الرابط', detail: errMsg);
        return;
      }

      if (linkResponse?['success'] != true || linkResponse?['token'] == null) {
        debugPrint('[GEN-LINK] API returned failure: $linkResponse');
        if (mounted) {
          AppSnackBar.error(context, 'فشل توليد الرابط',
              detail: linkResponse?['message']?.toString() ?? 'لم يتم الحصول على رابط');
        }
        return;
      }

      final token = linkResponse['token'];
      final linkUrl = '${ApiConstants.backendUrl}/user-info/$token';
      debugPrint('[GEN-LINK] Generated link: $linkUrl');

      final subscriberName = '${sub.firstname} ${sub.lastname}'.trim();
      final displayName = subscriberName.isNotEmpty ? subscriberName : sub.username;
      final message =
          'مرحباً $displayName 👋\n\n'
          'يمكنك الاطلاع على معلومات اشتراكك من خلال الرابط التالي:\n\n'
          '$linkUrl\n\n'
          '⚠️ ملاحظة: هذا الرابط صالح لمدة ساعة واحدة فقط.\n'
          'في حال تجديد الاشتراك أو تسديد الدين، يرجى طلب رابط جديد للبيانات المحدثة.\n\n'
          'شكراً لك 🙏';

      debugPrint('[GEN-LINK] Sending WA to: $phone');
      final sendResult = await ref.read(whatsappProvider.notifier).sendMessage(
        phone, message,
      );
      debugPrint('[GEN-LINK] WA result: success=${sendResult.success} error=${sendResult.error}');

      if (!mounted) return;
      if (sendResult.success) {
        AppSnackBar.whatsapp(context, 'تم إرسال رابط معلومات المشترك');
      } else {
        AppSnackBar.whatsappError(context, 'فشل إرسال الرابط عبر الواتساب',
            detail: sendResult.error);
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(context, 'خطأ غير متوقع', detail: e.toString());
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showActionsSheet(bool isEnabled) {
    final sub = _readCurrentSubscriber();
    final actions = [
      _FabAction(Icons.edit_outlined, 'تعديل', AppTheme.primary, _showEditSheet),
      _FabAction(Icons.bolt, 'تفعيل', AppTheme.successColor, _activateSubscriber),
      _FabAction(Icons.autorenew, 'تمديد', AppTheme.teal600, _extendSubscription),
      _FabAction(Icons.add_card_rounded, 'إضافة دين', AppTheme.warningColor, _showAddDebtSheet),
      if (sub.hasDebt)
        _FabAction(Icons.payments_rounded, 'تسديد دين', Colors.green, _showPayDebtSheet),
      if (sub.hasDebt)
        _FabAction(
          Icons.notifications_active_outlined,
          'تذكير دين',
          Colors.orange,
          () {
            _sendWhatsAppFromTemplate('debt_reminder');
          },
        ),
      _FabAction(Icons.link_rounded, 'توليد رابط', Colors.indigo, _generateInfoLink),
      _FabAction(Icons.delete_outline, 'حذف', AppTheme.dangerColor, _deleteSubscriber),
      _FabAction(
        isEnabled ? Icons.block : Icons.check_circle_outline,
        isEnabled ? 'تعطيل' : 'تفعيل حساب',
        isEnabled ? AppTheme.warningColor : AppTheme.successColor,
        () => _toggleSubscriber(enable: !isEnabled),
      ),
    ];

    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16,
                16 + MediaQuery.of(ctx).padding.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Text('العمليات', style: Theme.of(ctx).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.85,
                  children: actions.map((a) => _SpeedDialItem(
                    icon: a.icon,
                    label: a.label,
                    color: a.color,
                    onTap: () {
                      Navigator.pop(ctx);
                      a.onTap();
                    },
                  )).toList(),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Private helper widgets
// ═══════════════════════════════════════════════════════════════════════════

class _FabAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _FabAction(this.icon, this.label, this.color, this.onTap);
}

class _SpeedDialItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _SpeedDialItem({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          )),
        ],
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

class _MethodBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MethodBtn({
    required this.icon, required this.label,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withOpacity(0.12)
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withOpacity(0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withOpacity(0.7),
            )),
          ],
        ),
      ),
    );
  }
}

class _QuickAmountChips extends StatelessWidget {
  final List<double> amounts;
  final double selectedAmount;
  final bool enabled;
  final ValueChanged<double> onSelected;

  const _QuickAmountChips({
    required this.amounts,
    required this.selectedAmount,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (amounts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: amounts.map((v) {
        final isSelected = (selectedAmount - v).abs() < 0.5;
        return GestureDetector(
          onTap: enabled ? () => onSelected(v) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primary.withOpacity(0.15)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(enabled ? 0.5 : 0.25),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary.withOpacity(0.4)
                    : Colors.transparent,
              ),
            ),
            child: Text(
              AppHelpers.formatMoney(v),
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: !enabled
                    ? theme.colorScheme.onSurface.withOpacity(0.3)
                    : isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _DebtInfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _DebtInfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(fontSize: 11,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 14,
            fontWeight: FontWeight.w700, color: color),
            textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ActivationInfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _ActivationInfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 6),
        Text(label, style: TextStyle(fontSize: 10,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.45))),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 13,
          fontWeight: FontWeight.w700, color: color),
          textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600,
            color: valueColor ?? Theme.of(context).colorScheme.onSurface)),
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

class _PhoneDetailRow extends StatelessWidget {
  final String value;
  final bool enabled;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;

  const _PhoneDetailRow({
    required this.value,
    required this.enabled,
    required this.onCall,
    required this.onWhatsApp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(0.6);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.phone_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'رقم الهاتف',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.end,
                    textDirection: TextDirection.ltr,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (enabled) ...[
                  const SizedBox(width: 8),
                  _PhoneActionIcon(
                    icon: Icons.call_rounded,
                    color: AppTheme.teal600,
                    onTap: onCall,
                  ),
                  const SizedBox(width: 6),
                  _PhoneActionIcon(
                    icon: Icons.chat_rounded,
                    color: AppTheme.whatsappGreen,
                    onTap: onWhatsApp,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PhoneActionIcon({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withOpacity(0.18),
            ),
          ),
          child: Icon(
            icon,
            size: 15,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final digitsOnly = newValue.text.replaceAll(',', '');
    if (digitsOnly.isEmpty) return newValue.copyWith(text: '');
    if (int.tryParse(digitsOnly) == null) return oldValue;

    final formatted = _formatNumber(int.parse(digitsOnly).toDouble());
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

double _parseMoney(String text) =>
    double.tryParse(text.replaceAll(',', '')) ?? 0;

String _formatNumber(double value) {
  final intStr = value.toStringAsFixed(0);
  final buf = StringBuffer();
  final start = intStr.startsWith('-') ? 1 : 0;
  if (start == 1) buf.write('-');
  for (int i = start; i < intStr.length; i++) {
    if (i > start && (intStr.length - i) % 3 == 0) buf.write(',');
    buf.write(intStr[i]);
  }
  return buf.toString();
}
