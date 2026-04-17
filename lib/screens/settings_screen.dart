import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/services/storage_service.dart';
import '../core/services/fcm_service.dart';
import '../widgets/app_snackbar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _fcmEnabled = false;
  bool _fcmLoaded = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      ref.read(settingsProvider.notifier).loadFeatures();
      final storage = ref.read(storageServiceProvider);
      final fcm = await storage.getFcmEnabled();
      if (mounted) {
        setState(() {
          _fcmEnabled = fcm;
          _fcmLoaded = true;
        });
      }
    });
  }

  Future<void> _onFcmChanged(bool value) async {
    final storage = ref.read(storageServiceProvider);
    if (value) {
      final ok = await FcmService.enable(storage);
      if (!ok && mounted) {
        AppSnackBar.error(context,
            'لم يُمنح إذن الإشعارات أو فشل التسجيل. تحقق من إعدادات الجهاز.');
        return;
      }
    } else {
      await FcmService.disable(storage);
    }
    if (mounted) {
      setState(() => _fcmEnabled = value);
      AppSnackBar.success(
        context,
        value
            ? 'تم تفعيل إشعارات الجهاز'
            : 'تم إيقاف إشعارات الجهاز',
      );
    }
  }

  void _showFeaturesModal() {
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final settings = ref.watch(settingsProvider);
          final theme = Theme.of(ctx);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.whatsappGreen.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.message_rounded,
                          color: AppTheme.whatsappGreen, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'ميزات واتساب',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _FeatureToggle(
                  icon: Icons.add_circle_outline,
                  title: 'إرسال عند التفعيل',
                  subtitle: 'إرسال رسالة ترحيب عند تفعيل مشترك جديد',
                  value: settings.features.sendOnActivation,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('sendOnActivation', v),
                ),
                _FeatureToggle(
                  icon: Icons.autorenew,
                  title: 'إرسال عند التمديد',
                  subtitle: 'إرسال إشعار عند تمديد اشتراك',
                  value: settings.features.sendOnExtension,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('sendOnExtension', v),
                ),
                _FeatureToggle(
                  icon: Icons.warning_amber_outlined,
                  title: 'تذكير انتهاء',
                  subtitle: 'إرسال تحذير قبل انتهاء الاشتراك',
                  value: settings.features.expiryReminder,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('expiryReminder', v),
                ),
                _FeatureToggle(
                  icon: Icons.credit_card,
                  title: 'تذكير ديون',
                  subtitle: 'إرسال تذكير تلقائي للمديونين',
                  value: settings.features.debtReminder,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('debtReminder', v),
                ),
                _FeatureToggle(
                  icon: Icons.event_busy,
                  title: 'إشعار انتهاء الخدمة',
                  subtitle: 'إرسال إشعار عند انتهاء الخدمة',
                  value: settings.features.serviceEndNotification,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('serviceEndNotification', v),
                ),
                _FeatureToggle(
                  icon: Icons.waving_hand,
                  title: 'رسالة ترحيب',
                  subtitle: 'إرسال رسالة ترحيب للمشتركين الجدد',
                  value: settings.features.welcomeMessage,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('welcomeMessage', v),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDebtExportDialog() {
    context.push('/debt-export');
  }

  void _showDebtImportDialog() {
    context.push('/debt-import');
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        _SectionTitle(title: 'المظهر'),
        const SizedBox(height: 8),
        _SettingTile(
          icon: Icons.dark_mode_outlined,
          title: 'الوضع الداكن',
          trailing: Switch.adaptive(
            value: themeMode == ThemeMode.dark,
            onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
            activeColor: theme.colorScheme.primary,
          ),
        ),
        _SettingTile(
          icon: Icons.notifications_active_outlined,
          title: 'إشعارات الجهاز',
          subtitle:
              'استقبال تنبيهات فورية عند انتهاء أو قرب انتهاء اشتراكات المشتركين، حتى عند إغلاق التطبيق.',
          trailing: !_fcmLoaded
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Switch.adaptive(
                  value: _fcmEnabled,
                  onChanged: ref.watch(authProvider).status ==
                          AuthStatus.authenticated
                      ? _onFcmChanged
                      : null,
                  activeColor: theme.colorScheme.primary,
                ),
        ),

        const SizedBox(height: 8),
        _SettingTile(
          icon: Icons.discount_rounded,
          title: 'قائمة الخصومات',
          subtitle: 'إدارة خصومات المشتركين',
          onTap: () => context.push('/discounts'),
        ),
        _SettingTile(
          icon: Icons.price_change_rounded,
          title: 'تسعير الباقات',
          subtitle: 'إدارة أسعار الباقات للمدراء',
          onTap: () => context.push('/packages'),
        ),
        _SettingTile(
          icon: Icons.print_rounded,
          title: 'قوالب الطباعة',
          subtitle: 'إدارة قوالب وصولات الطباعة',
          onTap: () => context.push('/print-templates'),
        ),

        const SizedBox(height: 20),

        _SectionTitle(title: 'إدارة واتساب'),
        const SizedBox(height: 8),
        _SettingTile(
          icon: Icons.tune_rounded,
          title: 'ميزات واتساب',
          subtitle: 'التحكم بالإرسال التلقائي',
          iconColor: AppTheme.whatsappGreen,
          onTap: _showFeaturesModal,
        ),
        _SettingTile(
          icon: Icons.link,
          title: 'اتصال واتساب',
          onTap: () => context.push('/whatsapp-connection'),
        ),
        _SettingTile(
          icon: Icons.schedule,
          title: 'الجدولة',
          onTap: () => context.push('/schedules'),
        ),
        _SettingTile(
          icon: Icons.description_outlined,
          title: 'قوالب الرسائل',
          onTap: () => context.push('/templates'),
        ),
        _SettingTile(
          icon: Icons.campaign,
          title: 'بث الرسائل',
          onTap: () => context.push('/broadcast'),
        ),
        _SettingTile(
          icon: Icons.history,
          title: 'سجل الرسائل',
          onTap: () => context.push('/message-logs'),
        ),

        const SizedBox(height: 20),

        _SectionTitle(title: 'إدارة الديون'),
        const SizedBox(height: 8),
        _SettingTile(
          icon: Icons.file_download_outlined,
          title: 'تصدير ديون المشتركين',
          subtitle: 'تصدير ملف CSV بالمشتركين المديونين',
          onTap: _showDebtExportDialog,
        ),
        _SettingTile(
          icon: Icons.file_upload_outlined,
          title: 'استيراد ديون المشتركين',
          subtitle: 'استيراد ديون من ملف CSV',
          onTap: _showDebtImportDialog,
        ),

        const SizedBox(height: 20),

        _SectionTitle(title: 'حول'),
        const SizedBox(height: 8),
        _SettingTile(
          icon: Icons.info_outline,
          title: 'عن التطبيق',
          subtitle: 'MyServices Radius v1.0.0',
        ),

        const SizedBox(height: 20),

        SizedBox(
          height: AppTheme.actionButtonHeight,
          child: OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('تسجيل الخروج'),
                  content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('إلغاء'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text('خروج'),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                await ref.read(authProvider.notifier).logout();
                if (!mounted) return;
                context.go('/login');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final ctx = appNavigatorKey.currentContext;
                  if (ctx != null) {
                    AppSnackBar.info(ctx, 'تم تسجيل الخروج');
                  }
                });
              }
            },
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text(
              'تسجيل الخروج',
              style: TextStyle(fontFamily: 'Cairo', color: Colors.red),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;

  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = iconColor ?? Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: themeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: themeColor, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: subtitle != null
            ? Text(subtitle!, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12))
            : null,
        trailing: trailing ??
            (onTap != null
                ? Icon(Icons.arrow_forward_ios,
                    size: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.3))
                : null),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

class _FeatureToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _FeatureToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SwitchListTile.adaptive(
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.whatsappGreen.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.whatsappGreen, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
        value: value,
        activeColor: AppTheme.whatsappGreen,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
