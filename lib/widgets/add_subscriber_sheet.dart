import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import '../providers/subscribers_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/helpers.dart';
import '../models/subscriber_model.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر الباقة'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    final expDate = DateTime.now().add(const Duration(days: 30));
    final expStr = intl.DateFormat('yyyy-MM-dd').format(expDate);

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
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء المشترك بنجاح'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فشل إنشاء المشترك'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final packages = ref.watch(subscribersProvider).packages;
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom,
        left: 20, right: 20, top: 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.person_add_alt_1, color: AppTheme.primary, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Text('إضافة مشترك جديد',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 20),

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
                  const SizedBox(width: 12),
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
              const SizedBox(height: 12),

              Builder(builder: (_) {
                final seen = <int>{};
                final uniquePkgs = packages.where((p) {
                  if (p.idx <= 0 || seen.contains(p.idx)) return false;
                  seen.add(p.idx);
                  return true;
                }).toList();
                final hasMatch = _selectedPackageId != null &&
                    _selectedPackageId! > 0 &&
                    uniquePkgs.any((p) => p.idx == _selectedPackageId);
                return DropdownButtonFormField<int>(
                  value: hasMatch ? _selectedPackageId : null,
                  decoration: const InputDecoration(
                    labelText: 'الباقة',
                    prefixIcon: Icon(Icons.sell_rounded, size: 20),
                  ),
                  items: uniquePkgs.map((pkg) {
                    return DropdownMenuItem(
                      value: pkg.idx,
                      child: Text(
                        '${pkg.name} — ${AppHelpers.formatMoney(pkg.price)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedPackageId = v),
                  validator: (v) => v == null ? 'اختر الباقة' : null,
                );
              }),
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
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
