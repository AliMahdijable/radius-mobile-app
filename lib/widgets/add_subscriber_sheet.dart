import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../providers/subscribers_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/helpers.dart';
import '../models/subscriber_model.dart';
import 'app_snackbar.dart';

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
  int? _selectedPackageId;
  bool _isLoading = false;
  bool _loadingPackages = false;

  @override
  void initState() {
    super.initState();
    _ensurePackagesLoaded();
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

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _firstnameCtrl.dispose();
    _lastnameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPackageId == null) {
      AppSnackBar.warning(context, 'اختر الباقة');
      return;
    }

    setState(() => _isLoading = true);

    final expStr = intl.DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    final success = await ref.read(subscribersProvider.notifier).createSubscriber(
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
      profileId: _selectedPackageId!,
      firstname: _firstnameCtrl.text.trim(),
      lastname: _lastnameCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      expiration: expStr,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      _usernameCtrl.clear();
      _passwordCtrl.clear();
      _firstnameCtrl.clear();
      _lastnameCtrl.clear();
      _phoneCtrl.clear();
      setState(() => _selectedPackageId = null);

      if (!mounted) return;
      AppSnackBar.success(context, 'تم إنشاء المشترك بنجاح');
      await ref.read(subscribersProvider.notifier).loadSubscribers();
    } else {
      AppSnackBar.error(context, 'فشل إنشاء المشترك');
    }
  }

  Widget _buildPackageCard(PackageModel pkg, ThemeData theme) {
    final isSelected = _selectedPackageId == pkg.idx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => setState(() => _selectedPackageId = pkg.idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.successColor.withOpacity(0.08)
                : theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppTheme.successColor.withOpacity(0.4)
                  : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: isSelected ? AppTheme.successColor : Colors.grey,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(pkg.name, style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: isSelected ? AppTheme.successColor : null,
                )),
              ),
              Text(AppHelpers.formatMoney(pkg.displayPrice),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                    color: isSelected ? AppTheme.successColor : AppTheme.teal600)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(subscribersProvider).packages;
    final theme = Theme.of(context);

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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.teal600, AppTheme.teal900]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.person_add_alt_1, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Text('إضافة مشترك جديد',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 24),

          Text('معلومات المشترك', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.5))),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _firstnameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الأول',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'مطلوب' : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  controller: _lastnameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الأخير',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              prefixIcon: Icon(Icons.phone_outlined, size: 20),
              hintText: '07xxxxxxxxx',
            ),
          ),
          const SizedBox(height: 20),

          Text('بيانات الدخول', style: TextStyle(fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withOpacity(0.5))),
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
          const SizedBox(height: 20),

          if (_loadingPackages)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('جاري تحميل الباقات...', style: TextStyle(fontSize: 13)),
                ],
              ),
            )
          else if (uniquePkgs.isEmpty)
            GestureDetector(
              onTap: _ensurePackagesLoaded,
              child: Container(
                padding: const EdgeInsets.all(16),
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
            Text('الباقة', style: TextStyle(fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withOpacity(0.5))),
            const SizedBox(height: 8),
            ...uniquePkgs.map((pkg) => _buildPackageCard(pkg, theme)),
          ],
          const SizedBox(height: 24),

          SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submit,
              icon: _isLoading
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add),
              label: Text(_isLoading ? 'جاري الإنشاء...' : 'إنشاء المشترك'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.successColor,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
