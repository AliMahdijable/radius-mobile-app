import 'package:flutter/material.dart';

import '../services/auth_storage.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'login_screen.dart';

/// Temporary landing page after login + permissions. The real dashboard
/// will replace this in the next iteration once visual direction is approved.
class HomePlaceholder extends StatefulWidget {
  const HomePlaceholder({super.key});

  @override
  State<HomePlaceholder> createState() => _HomePlaceholderState();
}

class _HomePlaceholderState extends State<HomePlaceholder> {
  String _name = '';

  @override
  void initState() {
    super.initState();
    AuthStorage.readDisplayName().then((n) {
      if (mounted) setState(() => _name = n ?? '');
    });
  }

  Future<void> _logout() async {
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Sp.xxl),
          child: Column(
            children: [
              const SizedBox(height: Sp.huge),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.lg),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.check_rounded,
                    color: AppColors.brand, size: 36),
              ),
              const SizedBox(height: Sp.xl),
              Text('تم تسجيل الدخول بنجاح',
                  style: AppType.title(color: AppColors.textHi)),
              const SizedBox(height: Sp.sm),
              if (_name.isNotEmpty)
                Text('مرحباً $_name 👋',
                    style: AppType.subtitle(color: AppColors.textMid)),
              const SizedBox(height: Sp.lg),
              Text(
                'تصميم الشاشة الرئيسية سيتم بناؤه في الجلسة القادمة.',
                textAlign: TextAlign.center,
                style: AppType.subtitle(color: AppColors.textMid)
                    .copyWith(height: 1.6),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: Material(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(R.md),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _logout,
                    child: Center(
                      child: Text('تسجيل الخروج',
                          style: AppType.button(color: AppColors.error)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
