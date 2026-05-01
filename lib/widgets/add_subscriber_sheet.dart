import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../providers/auth_provider.dart';
import '../providers/managers_provider.dart';
import '../providers/subscribers_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/helpers.dart';
import '../models/manager_model.dart';
import '../models/subscriber_model.dart';
import 'app_snackbar.dart';
import 'contact_picker.dart';

/// Add-subscriber sheet — styled exactly like the edit-subscriber modal:
/// same icon header, same "معلومات المشترك" / "بيانات الدخول" section labels,
/// same input decorations, same expiration date-time picker gated by the
/// canAccessManagers || canAccessPackages permission, and the same package
/// DropdownButtonFormField used in the edit sheet.
class AddSubscriberSheet extends ConsumerStatefulWidget {
  const AddSubscriberSheet({super.key});

  @override
  ConsumerState<AddSubscriberSheet> createState() => _AddSubscriberSheetState();
}

class _AddSubscriberSheetState extends ConsumerState<AddSubscriberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _firstnameCtrl = TextEditingController();
  final _lastnameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _expCtrl = TextEditingController();
  int? _selectedPackageId;
  int? _selectedParentId;
  List<ManagerModel> _parentManagers = const [];
  bool _isLoading = false;
  bool _loadingPackages = false;
  bool _loadingParents = false;

  @override
  void initState() {
    super.initState();
    _ensurePackagesLoaded();
    _loadParents();
  }

  Future<void> _ensurePackagesLoaded() async {
    if (!mounted) return;
    final pkgs = ref.read(subscribersProvider).packages;
    if (pkgs.isEmpty) {
      if (mounted) setState(() => _loadingPackages = true);
      await ref.read(subscribersProvider.notifier).loadPackages();
      if (mounted) setState(() => _loadingPackages = false);
    }
  }

  Future<void> _loadParents() async {
    if (!mounted) return;
    final authUser = ref.read(authProvider).user;
    // Skip the manager-tree fetch for admins who can't pick a parent
    // anyway — sub-managers without canAccessManagers won't see the field.
    if (!(authUser?.canAccessManagers ?? false)) return;
    setState(() => _loadingParents = true);
    final list = await ref.read(managersProvider.notifier).fetchParentManagers();
    if (!mounted) return;
    final currentAdminId = int.tryParse(authUser?.id?.toString() ?? '');
    setState(() {
      _parentManagers = list;
      // Default the new subscriber's parent to the currently logged-in admin,
      // matching the prior behavior of createSubscriber when no parent_id was
      // selected. Only set if the current admin actually appears in the list.
      if (_selectedParentId == null &&
          currentAdminId != null &&
          list.any((m) => m.id == currentAdminId)) {
        _selectedParentId = currentAdminId;
      }
      _loadingParents = false;
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _firstnameCtrl.dispose();
    _lastnameCtrl.dispose();
    _phoneCtrl.dispose();
    _expCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickExpiration() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_expCtrl.text.trim()) ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
      locale: const Locale('ar'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted) return;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time?.hour ?? current.hour,
      time?.minute ?? current.minute,
    );
    setState(() {
      _expCtrl.text =
          intl.DateFormat('yyyy-MM-dd HH:mm:ss').format(combined);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPackageId == null) {
      AppSnackBar.warning(context, 'اختر الباقة');
      return;
    }

    setState(() => _isLoading = true);

    DateTime expirationToSend;
    final raw = _expCtrl.text.trim();
    final parsed = DateTime.tryParse(raw);
    expirationToSend = parsed ?? DateTime.now();
    final expStr =
        intl.DateFormat('yyyy-MM-dd HH:mm:ss').format(expirationToSend);

    final success = await ref.read(subscribersProvider.notifier).createSubscriber(
          username: _usernameCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
          profileId: _selectedPackageId!,
          firstname: _firstnameCtrl.text.trim(),
          lastname: _lastnameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          expiration: expStr,
          parentId: _selectedParentId,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      _usernameCtrl.clear();
      _passwordCtrl.clear();
      _firstnameCtrl.clear();
      _lastnameCtrl.clear();
      _phoneCtrl.clear();
      _expCtrl.clear();
      setState(() => _selectedPackageId = null);

      if (!mounted) return;
      AppSnackBar.success(context, 'تم إنشاء المشترك بنجاح');
      await ref.read(subscribersProvider.notifier).loadSubscribers();
      if (mounted) Navigator.of(context).maybePop();
    } else {
      AppSnackBar.error(context, 'فشل إنشاء المشترك');
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(subscribersProvider).packages;
    final theme = Theme.of(context);
    final authUser = ref.watch(authProvider).user;
    // أي مدير يملك صلاحية إدارة المدراء أو الباقات يستطيع تحديد تاريخ الانتهاء.
    // المدير الفرعي العادي فقط يُحرم من هذا الحقل.
    final canEditExpiration =
        (authUser?.canAccessManagers ?? false) ||
            (authUser?.canAccessPackages ?? false);
    // "تابع إلى" يظهر فقط للمدراء الذين يملكون صلاحية إدارة المدراء (أي
    // الذين يستطيعون إنشاء مدراء فرعيين تحتهم).
    final canPickParent = authUser?.canAccessManagers ?? false;

    final seen = <int>{};
    final uniquePkgs = packages.where((p) {
      if (p.idx <= 0 || seen.contains(p.idx)) return false;
      seen.add(p.idx);
      return true;
    }).toList();

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle — نفس مقبض مودل التعديل
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header بأيقونة وعنوان — مثل "تعديل بيانات المشترك"
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_add_alt_1,
                    color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Text('إضافة بيانات مشترك',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 20),

          // قسم: معلومات المشترك
          Text('معلومات المشترك',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              )),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _firstnameCtrl,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                decoration: const InputDecoration(
                  labelText: 'الاسم الأول',
                  prefixIcon: Icon(Icons.person_outline, size: 20),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'مطلوب' : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _lastnameCtrl,
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                decoration:
                    const InputDecoration(labelText: 'الاسم الأخير'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: InputDecoration(
              labelText: 'رقم الهاتف',
              prefixIcon: const Icon(Icons.phone_outlined, size: 20),
              suffixIcon: IconButton(
                tooltip: 'اختر من جهات الاتصال',
                icon: const Icon(Icons.contacts_rounded, size: 20),
                onPressed: () async {
                  final phone = await pickContactPhone(context);
                  if (phone != null && phone.isNotEmpty) {
                    _phoneCtrl.text = phone;
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          // قسم: بيانات الدخول
          Text('بيانات الدخول',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              )),
          const SizedBox(height: 10),
          TextFormField(
            controller: _usernameCtrl,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: const InputDecoration(
              labelText: 'اسم المستخدم',
              prefixIcon: Icon(Icons.alternate_email, size: 20),
              hintText: 'user@domain',
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _passwordCtrl,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: const InputDecoration(
              labelText: 'كلمة المرور',
              prefixIcon: Icon(Icons.lock_outline, size: 20),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
          ),
          const SizedBox(height: 12),

          // تابع إلى (parent manager) — same dropdown style as the manager
          // form's "تابع إلى" field. Defaults to the currently logged-in admin
          // so behavior matches the prior auto-assignment in createSubscriber.
          // Only shown to admins who can manage sub-admins; sub-managers
          // (without canAccessManagers) never see or change the parent.
          if (canPickParent) ...[
            if (_loadingParents)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 10),
                    Text('جاري تحميل المدراء...',
                        style: TextStyle(fontSize: 12)),
                  ],
                ),
              )
            else
              DropdownButtonFormField<int?>(
                value: _selectedParentId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'تابع إلى',
                  prefixIcon: Icon(Icons.account_tree_outlined, size: 20),
                ),
                items: _parentManagers
                    .map(
                      (m) => DropdownMenuItem<int?>(
                        value: m.id,
                        child: Text(
                          m.fullName.isNotEmpty
                              ? '${m.username} - ${m.fullName}'
                              : m.username,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedParentId = v),
              ),
            const SizedBox(height: 12),
          ],

          // تاريخ الانتهاء (date-picker تفاعلي) — مُحكم بنفس صلاحيات التعديل
          TextField(
            controller: _expCtrl,
            readOnly: true,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            onTap: !canEditExpiration ? null : _pickExpiration,
            decoration: InputDecoration(
              labelText: 'تاريخ الانتهاء',
              hintText: canEditExpiration
                  ? 'اضغط لاختيار التاريخ والوقت'
                  : 'يبدأ الآن تلقائياً',
              helperText: canEditExpiration
                  ? 'اختياري — إن لم يُحدَّد يبدأ من الآن'
                  : 'لا تملك صلاحية تعديل تاريخ الانتهاء',
              prefixIcon: const Icon(Icons.calendar_today, size: 20),
              suffixIcon: canEditExpiration
                  ? const Icon(Icons.edit_calendar_rounded, size: 18)
                  : null,
            ),
          ),
          const SizedBox(height: 20),

          // قسم: الباقة — نفس Dropdown مودل التعديل
          if (_loadingPackages)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('جاري تحميل الباقات...',
                      style: TextStyle(fontSize: 13)),
                ],
              ),
            )
          else if (uniquePkgs.isEmpty)
            GestureDetector(
              onTap: _ensurePackagesLoaded,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.2)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh, size: 18, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('لا توجد باقات — اضغط لإعادة التحميل',
                        style: TextStyle(fontSize: 13, color: Colors.orange)),
                  ],
                ),
              ),
            )
          else ...[
            Text('الباقة',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                )),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              value: _selectedPackageId != null &&
                      uniquePkgs.any((p) => p.idx == _selectedPackageId)
                  ? _selectedPackageId
                  : null,
              isExpanded: true,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'Cairo',
                color: theme.colorScheme.onSurface,
              ),
              dropdownColor:
                  theme.cardTheme.color ?? theme.colorScheme.surface,
              iconEnabledColor: theme.colorScheme.onSurface.withOpacity(0.7),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.wifi_rounded, size: 18),
                hintText: 'اختر الباقة',
              ),
              items: uniquePkgs
                  .map((pkg) => DropdownMenuItem<int>(
                        value: pkg.idx,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                pkg.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              AppHelpers.formatMoney(pkg.displayPrice),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.teal600,
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedPackageId = v),
              validator: (v) => v == null ? 'مطلوب' : null,
            ),
          ],
          const SizedBox(height: 24),

          // زر الحفظ — نفس تصميم زر مودل التعديل (لون الثيم الافتراضي)
          SizedBox(
            height: AppTheme.actionButtonHeight,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submit,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(_isLoading ? 'جاري الحفظ...' : 'حفظ المشترك'),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
