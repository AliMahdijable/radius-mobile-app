import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
      if (!mounted) return;
      setState(() => _appVersion = versionLabel);
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
                      child: const Icon(LucideIcons.messageCircle,
                          color: AppTheme.whatsappGreen, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Text('ميزات واتساب',
                        style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 16),
                // Master switch — يلتحق بكل الـtoggles أدناه. لمّا مغلق
                // الباكند يتجاوز كل feature flag ويوقف كل الإشعارات
                // (فورية + scheduled).
                _MasterNotificationsToggle(
                  enabled: settings.features.notificationsEnabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('notificationsEnabled', v),
                ),
                const SizedBox(height: 12),
                _FeatureToggle(
                  icon: LucideIcons.circlePlus,
                  title: 'إرسال عند التفعيل',
                  subtitle: 'إرسال رسالة ترحيب عند تفعيل مشترك جديد',
                  value: settings.features.sendOnActivation,
                  enabled: settings.features.notificationsEnabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('sendOnActivation', v),
                ),
                _FeatureToggle(
                  icon: LucideIcons.repeat,
                  title: 'إرسال عند التمديد',
                  subtitle: 'إرسال قالب "إشعار التمديد" عند تمديد/تجديد اشتراك',
                  value: settings.features.sendOnExtension,
                  enabled: settings.features.notificationsEnabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('sendOnExtension', v),
                ),
                _FeatureToggle(
                  icon: LucideIcons.triangleAlert,
                  title: 'تذكير انتهاء',
                  subtitle: 'إرسال تحذير قبل انتهاء الاشتراك',
                  value: settings.features.expiryReminder,
                  enabled: settings.features.notificationsEnabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('expiryReminder', v),
                ),
                _FeatureToggle(
                  icon: LucideIcons.creditCard,
                  title: 'تذكير ديون',
                  subtitle: 'إرسال تذكير تلقائي للمديونين',
                  value: settings.features.debtReminder,
                  enabled: settings.features.notificationsEnabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('debtReminder', v),
                ),
                _FeatureToggle(
                  icon: LucideIcons.calendarOff,
                  title: 'إشعار انتهاء الخدمة',
                  subtitle: 'إرسال إشعار عند انتهاء الخدمة',
                  value: settings.features.serviceEndNotification,
                  enabled: settings.features.notificationsEnabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .updateFeature('serviceEndNotification', v),
                ),
                _FeatureToggle(
                  icon: LucideIcons.handHeart,
                  title: 'رسالة ترحيب',
                  subtitle: 'إرسال رسالة ترحيب للمشتركين الجدد',
                  value: settings.features.welcomeMessage,
                  enabled: settings.features.notificationsEnabled,
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

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final authState = ref.watch(authProvider);
    final user = authState.user;
    bool empCan(String key) => user?.hasEmployeePermission(key) ?? true;
    final theme = Theme.of(context);
    final canAccessManagers = authState.user?.canAccessManagers ?? false;
    final isEmployee = user?.isEmployee == true;

    // ── حساب visibility الأقسام مسبقاً عشان نخفي القسم الفارغ ─────────
    final hasAdministration =
        empCan('discounts.view') ||
        (canAccessManagers && empCan('managers.view')) ||
        (!isEmployee || empCan('employees.view')) ||
        (canAccessManagers && empCan('packages.view'));

    final hasWhatsapp = !isEmployee ||
        (user?.hasAnyEmployeePermission(const [
              'whatsapp.connect',
              'whatsapp.send',
              'whatsapp.broadcast',
              'whatsapp.templates',
              'whatsapp.schedules',
            ]) ??
            false);

    final hasArchives = empCan('reports.expenses') || true; // archive always

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
      children: [
        // 1) المظهر والإشعارات (مفتوحة بشكل افتراضي — الأكثر استعمالاً)
        _SettingsSection(
          title: 'المظهر والإشعارات',
          icon: LucideIcons.palette,
          initiallyExpanded: true,
          children: [
            _SettingTile(
              icon: LucideIcons.moon,
              title: 'الوضع الداكن',
              trailing: Switch.adaptive(
                value: themeMode == ThemeMode.dark,
                onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
                activeColor: theme.colorScheme.primary,
              ),
            ),
            _SettingTile(
              icon: LucideIcons.bellRing,
              title: 'إشعارات الجهاز',
              subtitle:
                  'استقبال تنبيهات الجهاز للاشتراكات + الإشعارات الفورية داخل التطبيق.',
              trailing: !_fcmLoaded
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Switch.adaptive(
                      value: _fcmEnabled,
                      onChanged: ref.watch(authProvider).status ==
                              AuthStatus.authenticated
                          ? _onFcmChanged
                          : null,
                      activeColor: theme.colorScheme.primary,
                    ),
            ),
            _SettingTile(
              icon: LucideIcons.bellRing,
              title: 'إعدادات الإشعارات',
              subtitle: 'تفعيل/إيقاف Push + ساعات صمت',
              iconColor: Colors.indigo,
              onTap: () => context.push('/notification-settings'),
            ),
            _SettingTile(
              icon: LucideIcons.router,
              title: 'الإعدادات الافتراضية لأجهزتك',
              subtitle: 'بيانات دخول Ubiquiti و ONT',
              onTap: () => context.push('/device-defaults'),
            ),
          ],
        ),

        // 2) الإدارة — موظفون / مدراء فرعيون / باقات / خصومات
        if (hasAdministration)
          _SettingsSection(
            title: 'الإدارة',
            icon: LucideIcons.slidersHorizontal,
            children: [
              if (!isEmployee || empCan('employees.view'))
                _SettingTile(
                  icon: LucideIcons.badgeCheck,
                  title: 'الموظفون',
                  subtitle: 'إنشاء/تعديل حسابات الموظفين وصلاحياتهم',
                  onTap: () => context.push('/employees'),
                ),
              if (canAccessManagers && empCan('managers.view'))
                _SettingTile(
                  icon: LucideIcons.shield,
                  title: 'المدراء الفرعيون',
                  subtitle: 'إظهار وإدارة قسم الأدمنية الفرعية',
                  onTap: () => context.push('/managers'),
                ),
              if (canAccessManagers && empCan('packages.view'))
                _SettingTile(
                  icon: LucideIcons.tag,
                  title: 'تسعير الباقات',
                  subtitle: 'إدارة أسعار الباقات للمدراء',
                  onTap: () => context.push('/packages'),
                ),
              if (empCan('discounts.view'))
                _SettingTile(
                  icon: LucideIcons.percent,
                  title: 'قائمة الخصومات',
                  subtitle: 'إدارة خصومات المشتركين',
                  onTap: () => context.push('/discounts'),
                ),
            ],
          ),

        // 3) التواصل — كل ما يخص واتساب
        if (hasWhatsapp)
          _SettingsSection(
            title: 'التواصل (واتساب)',
            icon: LucideIcons.messageCircle,
            iconColor: AppTheme.whatsappGreen,
            children: [
              if (empCan('whatsapp.connect'))
                _SettingTile(
                  icon: LucideIcons.link,
                  title: 'اتصال واتساب',
                  subtitle: 'ربط/فصل الجلسة',
                  onTap: () => context.push('/whatsapp-connection'),
                ),
              if (empCan('whatsapp.templates'))
                _SettingTile(
                  icon: LucideIcons.slidersHorizontal,
                  title: 'ميزات واتساب',
                  subtitle: 'التحكم بالإرسال التلقائي',
                  iconColor: AppTheme.whatsappGreen,
                  onTap: _showFeaturesModal,
                ),
              if (canAccessManagers && !isEmployee)
                _SettingTile(
                  icon: LucideIcons.mapPin,
                  title: 'نطاق الإرسال',
                  subtitle: 'حدد أي مدراء فرعيين يغطيهم هذا الواتساب',
                  iconColor: AppTheme.whatsappGreen,
                  onTap: () => context.push('/whatsapp-send-scope'),
                ),
              if (empCan('whatsapp.templates'))
                _SettingTile(
                  icon: LucideIcons.fileText,
                  title: 'قوالب الرسائل',
                  onTap: () => context.push('/templates'),
                ),
              if (empCan('whatsapp.schedules'))
                _SettingTile(
                  icon: LucideIcons.clock,
                  title: 'الجدولة',
                  onTap: () => context.push('/schedules'),
                ),
              if (empCan('whatsapp.broadcast'))
                _SettingTile(
                  icon: LucideIcons.megaphone,
                  title: 'بث الرسائل',
                  onTap: () => context.push('/broadcast'),
                ),
              if (empCan('whatsapp.send'))
                _SettingTile(
                  icon: LucideIcons.history,
                  title: 'سجل الرسائل',
                  onTap: () => context.push('/message-logs'),
                ),
            ],
          ),

        // 4) الأرشيف والسجلات — وصولات + صرفيات
        if (hasArchives)
          _SettingsSection(
            title: 'الأرشيف والسجلات',
            icon: LucideIcons.folderOpen,
            children: [
              _SettingTile(
                icon: LucideIcons.receipt,
                title: 'أرشيف الوصولات',
                subtitle: 'كل ما طُبع من تفعيل/تمديد/تسديد دين',
                iconColor: AppTheme.primary,
                onTap: () => context.push('/receipts-archive'),
              ),
              if (empCan('reports.expenses'))
                _SettingTile(
                  icon: LucideIcons.wallet,
                  title: 'الصرفيات',
                  subtitle: 'تسجيل حركات الصرف — تُخصم من الإيرادات',
                  onTap: () => context.push('/expenses'),
                ),
            ],
          ),

        // 5) إدارة الديون — أدمن فقط
        if (!isEmployee)
          _SettingsSection(
            title: 'إدارة الديون',
            icon: LucideIcons.receipt,
            children: [
              if (empCan('debts.import'))
                _SettingTile(
                  icon: LucideIcons.download,
                  title: 'تصدير ديون المشتركين',
                  subtitle: 'تصدير ملف CSV بالمشتركين المديونين',
                  onTap: () => context.push('/debt-export'),
                ),
              if (empCan('debts.import'))
                _SettingTile(
                  icon: LucideIcons.upload,
                  title: 'استيراد ديون المشتركين',
                  subtitle: 'استيراد ديون من ملف CSV',
                  onTap: () => context.push('/debt-import'),
                ),
              _SettingTile(
                icon: LucideIcons.banknote,
                title: 'ديون عليّ',
                subtitle: 'ديون مسجلة عليك من قبل المدير الرئيسي',
                onTap: () => context.push('/my-debts'),
              ),
            ],
          ),

        // 6) حول
        _SettingsSection(
          title: 'حول',
          icon: LucideIcons.info,
          children: [
            _SettingTile(
              icon: LucideIcons.info,
              title: 'عن التطبيق',
              subtitle: _appVersion == null
                  ? 'MyServices Radius'
                  : 'MyServices Radius v$_appVersion',
            ),
          ],
        ),

        const SizedBox(height: 16),

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
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
            icon: const Icon(LucideIcons.logOut, color: Colors.red),
            label: const Text('تسجيل الخروج',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ),
      ],
    );
  }
}

/// قسم قابل للطي. الـheader يحمل أيقونة + عنوان، والـchildren tiles عادية.
/// تطبيق ExpansionTile يخفي القائمة الطويلة ويسرّع التصفح.
class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? iconColor;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
    this.iconColor,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = iconColor ?? theme.colorScheme.primary;
    final visibleChildren = children.whereType<Widget>().toList();
    if (visibleChildren.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.onSurface.withValues(alpha: .06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // إخفاء divider الافتراضي للـExpansionTile حتى يكون الكارت نظيف.
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          title: Text(title,
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
          children: visibleChildren,
        ),
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
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        dense: true,
        leading: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: themeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: themeColor, size: 18),
        ),
        title: Text(title,
            style: const TextStyle(
                fontFamily: 'Cairo',
                fontWeight: FontWeight.w600,
                fontSize: 13.5)),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style:
                    const TextStyle(fontFamily: 'Cairo', fontSize: 11))
            : null,
        trailing: trailing ??
            (onTap != null
                ? Icon(LucideIcons.chevronLeft,
                    size: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.3))
                : null),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Master switch — يستخدم لون مميّز (أخضر/أحمر) لتمييزه عن الـfeature
/// flags الفرعية. لمّا مغلق نُعرَض الـtoggles الفرعية معطّلة بصرياً.
class _MasterNotificationsToggle extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _MasterNotificationsToggle({
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppTheme.whatsappGreen : Colors.redAccent;
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.45), width: 1),
      ),
      child: SwitchListTile.adaptive(
        secondary: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            enabled ? LucideIcons.bell : LucideIcons.bellOff,
            color: color,
            size: 22,
          ),
        ),
        title: const Text(
          'تنبيهات الواتساب',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          enabled
              ? 'مفعّلة — يمكن التحكم بكل ميزة أدناه'
              : 'موقوفة بالكامل — لن يُرسل النظام أي إشعار',
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 11),
        ),
        value: enabled,
        activeColor: AppTheme.whatsappGreen,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
  /// لمّا master switch مغلق، نعرض الـtoggles الفرعية معطّلة بصرياً
  /// لإيضاح أن قيمها لا تؤثّر حالياً.
  final bool enabled;

  const _FeatureToggle({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Container(
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
              style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
          subtitle: Text(subtitle,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
          value: value,
          activeColor: AppTheme.whatsappGreen,
          onChanged: enabled ? onChanged : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
