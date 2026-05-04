import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../core/router/app_router.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/services/storage_service.dart';
import '../core/services/fcm_service.dart';
import '../core/services/expiry_push_service.dart';
import '../core/utils/bottom_sheet_utils.dart';
import '../widgets/app_snackbar.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const MethodChannel _appInfoChannel =
      MethodChannel('com.mysvcs.rad_mysvcs/app_info');

  bool _fcmEnabled = false;
  bool _fcmLoaded = false;
  String? _appVersion;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      ref.read(settingsProvider.notifier).loadFeatures();
      await _loadNotificationState();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAppVersion();
    });
  }

  Future<void> _loadNotificationState() async {
    final storage = ref.read(storageServiceProvider);
    final enabled = await FcmService.isEnabled(storage);
    if (!mounted) return;
    setState(() {
      _fcmEnabled = enabled;
      _fcmLoaded = true;
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info =
          await _appInfoChannel.invokeMapMethod<String, dynamic>('getAppVersion');
      final version = (info?['version'] as String? ?? '').trim();
      final buildNumber = '${info?['buildNumber'] ?? ''}'.trim();
      final versionLabel = _buildVersionLabel(version, buildNumber);
      debugPrint(
        'Loaded app version: version="$version", build="$buildNumber", label="$versionLabel"',
      );
      if (!mounted) return;
      setState(() {
        _appVersion = versionLabel;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load app version: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _appVersion = null);
    }
  }

  String? _buildVersionLabel(String version, String buildNumber) {
    final cleanVersion = version.split('+').first.trim();
    if (cleanVersion.isNotEmpty) return cleanVersion;
    if (buildNumber.isNotEmpty) return buildNumber;
    return null;
  }

  Future<void> _onFcmChanged(bool value) async {
    final storage = ref.read(storageServiceProvider);
    if (value) {
      final result = await FcmService.enable(storage);
      if (!result.enabled && mounted) {
        AppSnackBar.error(
          context,
          result.message ?? 'لم يُمنح إذن الإشعارات. تحقق من إعدادات الجهاز.',
        );
        return;
      }
      await ExpiryPushService.setEnabled(storage, true);
      if (!mounted) return;
      setState(() => _fcmEnabled = true);
      AppSnackBar.success(context, 'تم تفعيل إشعارات الجهاز');
    } else {
      await FcmService.disable(storage);
      await ExpiryPushService.setEnabled(storage, false);
      if (!mounted) return;
      setState(() => _fcmEnabled = false);
      AppSnackBar.success(context, 'تم إيقاف إشعارات الجهاز');
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
            padding: bottomSheetContentPadding(
              ctx,
              horizontal: 20,
              top: 16,
              extraBottom: 12,
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
                  subtitle: 'إرسال قالب "إشعار التمديد" عند تمديد/تجديد اشتراك',
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
    final authState = ref.watch(authProvider);
    final user = authState.user;
    // الموظف لازم يحمل managers.view (للقسمين: إدارة المدراء + تسعير
    // الباقات). الأدمن العادي يكتفي بـcanAccessManagers من SAS4 perms.
    bool empCan(String key) => user?.hasEmployeePermission(key) ?? true;
    final theme = Theme.of(context);
    final canAccessManagers = authState.user?.canAccessManagers ?? false;

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
              'استقبال تنبيهات الجهاز للاشتراكات، مع ربط التنبيهات الفورية داخل التطبيق عندما يدعم الجهاز ذلك.',
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
        if (empCan('discounts.view'))
          _SettingTile(
            icon: Icons.discount_rounded,
            title: 'قائمة الخصومات',
            subtitle: 'إدارة خصومات المشتركين',
            onTap: () => context.push('/discounts'),
          ),
        if (canAccessManagers && empCan('managers.view'))
          _SettingTile(
            icon: Icons.admin_panel_settings_outlined,
            title: 'المدراء الفرعيون',
            subtitle: 'إظهار وإدارة قسم الأدمنية الفرعية',
            onTap: () => context.push('/managers'),
          ),
        if (canAccessManagers && empCan('packages.view'))
          _SettingTile(
            icon: Icons.price_change_rounded,
            title: 'تسعير الباقات',
            subtitle: 'إدارة أسعار الباقات للمدراء',
            onTap: () => context.push('/packages'),
          ),
        if (empCan('reports.expenses'))
          _SettingTile(
            icon: Icons.account_balance_wallet_rounded,
            title: 'الصرفيات',
            subtitle: 'تسجيل حركات الصرف — تُخصم من الإيرادات',
            onTap: () => context.push('/expenses'),
          ),
        // الإعدادات الافتراضية للأجهزة + إعدادات الإشعارات تفضيلات شخصية
        // للمستخدم؛ ما تحتاج صلاحية. الموظف عنده Ubiquiti/ONT/push
        // الخاصة فيه (مو الأب).
        _SettingTile(
          icon: Icons.router_rounded,
          title: 'الإعدادات الافتراضية لأجهزتك',
          subtitle: 'بيانات دخول Ubiquiti و ONT لكل مشتركيك',
          onTap: () => context.push('/device-defaults'),
        ),
        if (empCan('print_templates.edit'))
          _SettingTile(
            icon: Icons.print_rounded,
            title: 'قوالب الطباعة',
            subtitle: 'إدارة قوالب وصولات الطباعة',
            onTap: () => context.push('/print-templates'),
          ),
        _SettingTile(
          icon: Icons.notifications_active_rounded,
          title: 'إعدادات الإشعارات',
          subtitle: 'تفعيل/إيقاف Push + ساعات صمت',
          iconColor: Colors.indigo,
          onTap: () => context.push('/notification-settings'),
        ),

        // قسم WhatsApp يظهر فقط لو الفاعل يملك أي whatsapp.* perm.
        if (user == null ||
            !user.isEmployee ||
            user.hasAnyEmployeePermission(const [
              'whatsapp.connect',
              'whatsapp.send',
              'whatsapp.templates',
              'whatsapp.schedules',
            ])) ...[
          const SizedBox(height: 20),
          _SectionTitle(title: 'إدارة واتساب'),
          const SizedBox(height: 8),
          if (empCan('whatsapp.templates'))
            _SettingTile(
              icon: Icons.tune_rounded,
              title: 'ميزات واتساب',
              subtitle: 'التحكم بالإرسال التلقائي',
              iconColor: AppTheme.whatsappGreen,
              onTap: _showFeaturesModal,
            ),
          if (empCan('whatsapp.connect'))
            _SettingTile(
              icon: Icons.link,
              title: 'اتصال واتساب',
              onTap: () => context.push('/whatsapp-connection'),
            ),
          // نطاق الإرسال يخص أصحاب المدراء الفرعيين فقط. الأدمن الفرعي
          // ما عنده مدراء تحته فلا معنى للخيار عنده.
          if (canAccessManagers && empCan('whatsapp.send'))
            _SettingTile(
              icon: Icons.share_location_rounded,
              title: 'نطاق الإرسال',
              subtitle: 'حدد أي مدراء فرعيين يغطيهم هذا الواتساب',
              iconColor: AppTheme.whatsappGreen,
              onTap: () => context.push('/whatsapp-send-scope'),
            ),
          if (empCan('whatsapp.schedules'))
            _SettingTile(
              icon: Icons.schedule,
              title: 'الجدولة',
              onTap: () => context.push('/schedules'),
            ),
          if (empCan('whatsapp.templates'))
            _SettingTile(
              icon: Icons.description_outlined,
              title: 'قوالب الرسائل',
              onTap: () => context.push('/templates'),
            ),
          if (empCan('whatsapp.send'))
            _SettingTile(
              icon: Icons.campaign,
              title: 'بث الرسائل',
              onTap: () => context.push('/broadcast'),
            ),
          if (empCan('whatsapp.send'))
            _SettingTile(
              icon: Icons.history,
              title: 'سجل الرسائل',
              onTap: () => context.push('/message-logs'),
            ),
        ],

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
        // Personal ledger — any admin can see debts the parent recorded
        // against them. No gate: unlike manager debts it's always safe to
        // hit /my-debts; the endpoint just returns an empty list when
        // nothing is owed. Intentionally placed at the bottom of the
        // section so it feels like a "my account" view, not a main action.
        _SettingTile(
          icon: Icons.receipt_long_outlined,
          title: 'ديون عليّ',
          subtitle: 'ديون مسجلة عليك من قبل المدير الرئيسي',
          onTap: () => context.push('/my-debts'),
        ),

        const SizedBox(height: 20),

        _SectionTitle(title: 'حول'),
        const SizedBox(height: 8),
        _SettingTile(
          icon: Icons.info_outline,
          title: 'عن التطبيق',
          subtitle: _appVersion == null
              ? 'MyServices Radius'
              : 'MyServices Radius v$_appVersion',
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
