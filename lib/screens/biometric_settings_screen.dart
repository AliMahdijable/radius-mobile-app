import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/biometric_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// شاشة البصمة / Face ID. تفعيل واحد يحوّل الـsplash لإجبار
/// مصادقة قبل الدخول للداش بورد.
class BiometricSettingsScreen extends StatefulWidget {
  const BiometricSettingsScreen({super.key});

  @override
  State<BiometricSettingsScreen> createState() =>
      _BiometricSettingsScreenState();
}

class _BiometricSettingsScreenState extends State<BiometricSettingsScreen> {
  bool _loading = true;
  bool _enabled = false;
  bool _canAuth = false;
  List<BiometricType> _available = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      BiometricService.isEnabled(),
      BiometricService.canAuthenticate(),
      BiometricService.available(),
    ]);
    if (!mounted) return;
    setState(() {
      _enabled = results[0] as bool;
      _canAuth = results[1] as bool;
      _available = results[2] as List<BiometricType>;
      _loading = false;
    });
  }

  Future<void> _toggle(bool v) async {
    if (_busy) return;
    setState(() => _busy = true);
    if (v) {
      final r = await BiometricService.enable();
      if (!mounted) return;
      setState(() {
        _enabled = r.ok;
        _busy = false;
      });
      if (!r.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(r.reason ?? 'تعذّر التفعيل'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('تم تفعيل القفل بالبصمة'),
            backgroundColor: AppColors.brand,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      await BiometricService.disable();
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _busy = false;
      });
    }
  }

  String get _bioLabel {
    if (!_canAuth) return 'البصمة غير متاحة على هذا الجهاز';
    if (_available.contains(BiometricType.face)) {
      return 'Face ID متاح';
    }
    if (_available.contains(BiometricType.fingerprint) ||
        _available.contains(BiometricType.strong)) {
      return 'بصمة الإصبع متاحة';
    }
    if (_available.contains(BiometricType.iris)) {
      return 'قزحية متاحة';
    }
    return 'وحدة بيومترية متاحة';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('البصمة / Face ID',
            style: AppType.title(color: AppColors.textHi)
                .copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Sp.lg, Sp.lg, Sp.lg, Sp.huge),
              children: [
                Container(
                  padding: const EdgeInsets.all(Sp.lg),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.brand.withValues(alpha: 0.15),
                        AppColors.brand.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    borderRadius: BorderRadius.circular(R.lg),
                    border: Border.all(
                        color: AppColors.brand.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.brand.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          _available.contains(BiometricType.face)
                              ? LucideIcons.scanFace
                              : LucideIcons.fingerprint,
                          color: AppColors.brand,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _enabled ? 'القفل مفعّل' : 'القفل معطّل',
                        style: AppType.title(color: AppColors.textHi)
                            .copyWith(fontSize: 17),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _bioLabel,
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Sp.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: Sp.md, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(R.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _enabled
                              ? AppColors.brand.withValues(alpha: 0.14)
                              : AppColors.surfaceInput,
                          borderRadius: BorderRadius.circular(R.sm),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          LucideIcons.lock,
                          size: 16,
                          color: _enabled
                              ? AppColors.brand
                              : AppColors.textLow,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'قفل التطبيق بالبصمة',
                              style: AppType.label(color: AppColors.textHi)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'يطلب البصمة عند فتح التطبيق',
                              style: AppType.muted(color: AppColors.textMid)
                                  .copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: _enabled,
                        onChanged: (_canAuth && !_busy) ? _toggle : null,
                      ),
                    ],
                  ),
                ),
                if (!_canAuth) ...[
                  const SizedBox(height: Sp.md),
                  Container(
                    padding: const EdgeInsets.all(Sp.md),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(R.md),
                      border: Border.all(
                          color: AppColors.error.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.triangleAlert,
                            size: 14, color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'لم نجد بصمة مسجّلة على الجهاز. سجّل بصمة من '
                            'إعدادات النظام ثم عد لتفعيلها هنا.',
                            style:
                                AppType.muted(color: AppColors.textHi)
                                    .copyWith(
                                        fontSize: 11, height: 1.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
