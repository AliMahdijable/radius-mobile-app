import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../core/theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(settingsProvider.notifier).loadFeatures();
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(authProvider).user;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        // Profile card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.username ?? '—',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${user?.id ?? '—'} • ${user?.role ?? ''}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Theme
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

        const SizedBox(height: 20),

        // WhatsApp Features
        _SectionTitle(title: 'ميزات واتساب'),
        const SizedBox(height: 8),

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

        const SizedBox(height: 20),

        // Navigation items
        _SectionTitle(title: 'إدارة'),
        const SizedBox(height: 8),
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

        // App info
        _SectionTitle(title: 'حول'),
        const SizedBox(height: 8),
        _SettingTile(
          icon: Icons.info_outline,
          title: 'عن التطبيق',
          subtitle: 'MyServices Radius v1.0.0',
        ),

        const SizedBox(height: 20),

        // Logout
        SizedBox(
          height: 52,
          child: OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('تسجيل الخروج'),
                  content:
                      const Text('هل أنت متأكد من تسجيل الخروج؟'),
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
                if (mounted) context.go('/login');
              }
            },
            icon: const Icon(Icons.logout, color: Colors.red),
            label: const Text(
              'تسجيل الخروج',
              style: TextStyle(color: Colors.red),
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

  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            color:
                Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              color: Theme.of(context).colorScheme.primary, size: 20),
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: subtitle != null ? Text(subtitle!, style: const TextStyle(fontSize: 12)) : null,
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
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
        value: value,
        activeColor: AppTheme.whatsappGreen,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
