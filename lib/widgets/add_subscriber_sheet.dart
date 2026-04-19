import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../providers/auth_provider.dart';
import '../providers/subscribers_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/helpers.dart';
import '../models/subscriber_model.dart';
import 'app_snackbar.dart';
import 'contact_picker.dart';

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
  DateTime? _expiration; // null = الافتراضي (الآن)
  bool _isLoading = false;
  bool _loadingPackages = false;
  bool _showPassword = false;

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

  Future<void> _pickExpiration() async {
    final now = DateTime.now();
    final current = _expiration ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      locale: const Locale('ar'),
    );
    if (picked == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted) return;
    setState(() {
      _expiration = DateTime(
        picked.year,
        picked.month,
        picked.day,
        time?.hour ?? current.hour,
        time?.minute ?? current.minute,
      );
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPackageId == null) {
      AppSnackBar.warning(context, 'اختر الباقة');
      return;
    }

    setState(() => _isLoading = true);

    final expirationToSend = _expiration ?? DateTime.now();
    final expStr = intl.DateFormat('yyyy-MM-dd HH:mm:ss').format(expirationToSend);

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
      setState(() {
        _selectedPackageId = null;
        _expiration = null;
      });

      if (!mounted) return;
      AppSnackBar.success(context, 'تم إنشاء المشترك بنجاح');
      await ref.read(subscribersProvider.notifier).loadSubscribers();
    } else {
      AppSnackBar.error(context, 'فشل إنشاء المشترك');
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(subscribersProvider).packages;
    final theme = Theme.of(context);
    final canPickExpiration =
        ref.watch(authProvider).user?.canAccessPackages ?? false;

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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppTheme.teal600, AppTheme.teal900]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.person_add_alt_1,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text('إضافة مشترك جديد',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 14),

          // الاسم الأول + الاسم الأخير
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _firstnameCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: _dense('الاسم الأول', Icons.person_outline),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'مطلوب' : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _lastnameCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: _dense('الاسم الأخير', null),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // رقم الهاتف — زر جهات الاتصال في الـ suffix
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.left,
            style: const TextStyle(fontSize: 13),
            decoration: _dense('رقم الهاتف', Icons.phone_outlined).copyWith(
              hintText: '07xxxxxxxxx',
              suffixIcon: IconButton(
                tooltip: 'اختر من جهات الاتصال',
                icon: const Icon(Icons.contacts_rounded, size: 18),
                onPressed: () async {
                  final phone = await pickContactPhone(context);
                  if (phone != null && phone.isNotEmpty) {
                    _phoneCtrl.text = phone;
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 14),

          _sectionLabel(theme, 'بيانات الدخول'),
          const SizedBox(height: 6),

          // اسم المستخدم + كلمة المرور في صف واحد
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _usernameCtrl,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  style: const TextStyle(fontSize: 13),
                  decoration: _dense('اسم المستخدم', Icons.alternate_email)
                      .copyWith(hintText: 'user@domain'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'مطلوب' : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _passwordCtrl,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  obscureText: !_showPassword,
                  style: const TextStyle(fontSize: 13),
                  decoration: _dense('كلمة المرور', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'مطلوب' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          _sectionLabel(theme, 'الباقة'),
          const SizedBox(height: 6),

          if (_loadingPackages)
            const SizedBox(
              height: 50,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (uniquePkgs.isEmpty)
            GestureDetector(
              onTap: _ensurePackagesLoaded,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withOpacity(0.2)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh, size: 16, color: Colors.orange),
                    SizedBox(width: 6),
                    Text('لا توجد باقات — اضغط لإعادة التحميل',
                        style: TextStyle(fontSize: 12, color: Colors.orange)),
                  ],
                ),
              ),
            )
          else
            DropdownButtonFormField<int>(
              value: _selectedPackageId,
              isExpanded: true,
              style: const TextStyle(fontSize: 13, fontFamily: 'Cairo'),
              decoration: _dense('اختر الباقة', Icons.wifi_rounded),
              items: uniquePkgs
                  .map((pkg) => DropdownMenuItem<int>(
                        value: pkg.idx,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                pkg.name,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              AppHelpers.formatMoney(pkg.displayPrice),
                              style: TextStyle(
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
          const SizedBox(height: 14),

          // تاريخ الانتهاء — يظهر فقط لمن يملك صلاحية canAccessPackages
          if (canPickExpiration) ...[
            _sectionLabel(theme, 'تاريخ الانتهاء (اختياري)'),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickExpiration,
              borderRadius: BorderRadius.circular(8),
              child: InputDecorator(
                decoration: _dense(
                  _expiration == null ? 'الافتراضي: الآن' : 'تاريخ الانتهاء',
                  Icons.event_rounded,
                ).copyWith(
                  suffixIcon: _expiration == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 16),
                          onPressed: () =>
                              setState(() => _expiration = null),
                        ),
                ),
                child: Text(
                  _expiration == null
                      ? ''
                      : intl.DateFormat('yyyy-MM-dd HH:mm')
                          .format(_expiration!),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  textDirection: TextDirection.ltr,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _submit,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add, size: 18),
              label: Text(_isLoading ? 'جاري الإنشاء...' : 'إنشاء المشترك',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.successColor,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  InputDecoration _dense(String label, IconData? icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, size: 18),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      labelStyle: const TextStyle(fontSize: 12),
    );
  }

  Widget _sectionLabel(ThemeData theme, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface.withOpacity(0.55),
      ),
    );
  }
}
