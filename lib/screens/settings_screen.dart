import 'package:flutter/material.dart';

import '../api/device_probe_api.dart';
import '../api/subscribers_api.dart';
import '../services/auth_storage.dart';
import '../services/fcm_service.dart';
import '../services/inbox_service.dart';
import '../services/permissions_service.dart';
import '../services/theme_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'app_permissions_screen.dart';
import 'devices/device_defaults_screen.dart';
import 'login_screen.dart';
import 'notifications_settings_screen.dart';
import 'whatsapp/whatsapp_status_screen.dart';
import 'whatsapp/whatsapp_templates_screen.dart';

/// Basic settings — version, identity, logout. Will grow next iteration.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _name = '';
  String _id = '';

  @override
  void initState() {
    super.initState();
    AuthStorage.readDisplayName().then((n) {
      if (mounted) setState(() => _name = n ?? '');
    });
    AuthStorage.readAdminId().then((i) {
      if (mounted) setState(() => _id = i ?? '');
    });
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.lg),
        ),
        title: Text('تأكيد تسجيل الخروج',
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 18)),
        content: Text(
          'سيتم مسح الجلسة المحفوظة وستحتاج لتسجيل الدخول من جديد.',
          style: AppType.subtitle(color: AppColors.textMid)
              .copyWith(height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('إلغاء', style: AppType.button(color: AppColors.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('خروج', style: AppType.button(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // مطلب 2026-06-11: امسح كل in-memory caches قبل الـauth wipe
    // عشان أوّل dashboard للـadmin الجديد ما يلصق على بقايا
    // admin السابق (45s TTL على الـsubscribers list كان كافياً
    // لتسريب الأرقام بين الجلستين).
    SubscribersApi.clearAllCaches();
    DeviceProbeApi.clearAllCaches();
    // نُلغي تسجيل الـFCM token قبل مسح الجلسة — عشان الحساب الجديد
    // (لو أحد سجّل بعدك على نفس الجهاز) ما يستلم إشعارات الحساب السابق.
    // آمنة الفشل — لا تعطّل الـlogout.
    await FcmService.unregister();
    // إفراغ inbox للحساب الحالي (الإشعارات لحساب سابق).
    await InboxService.clear();
    await PermissionsService.clear();
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // Render with our own AppBar that shows a back arrow when this
    // screen was pushed (i.e. not used as a bottom-tab anymore —
    // since 2026-06-10 the gear opens this as a route, not a tab).
    // Navigator.canPop returns true in that pushed context; we use
    // it to switch between the in-page title (when there's no
    // ancestor route) and a back-arrow AppBar (when there is).
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: canPop
          ? AppBar(
              backgroundColor: AppColors.bg,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              foregroundColor: AppColors.textHi,
              title: Text(
                'الإعدادات',
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'رجوع',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            Sp.lg,
            canPop ? Sp.sm : Sp.lg,
            Sp.lg,
            Sp.huge * 2,
          ),
          children: [
            if (!canPop)
              Padding(
                padding: const EdgeInsets.only(bottom: Sp.lg),
                child: Text('الإعدادات',
                    style: AppType.title(color: AppColors.textHi)
                        .copyWith(fontSize: 22)),
              ),
            _IdentityCard(name: _name),
            const SizedBox(height: Sp.lg),
            // مطلب 2026-06-10: شاشة الإعدادات تضم أقسام: واتساب +
            // قوالبه، طباعة + قوالبها، المظهر، البصمة، الصلاحيات،
            // الإشعارات، السكون. حالياً كل واحد stub يفتح snack
            // 'قيد التطوير' حتى نبني كل قسم على حدة.
            // مطلب 2026-06-12: قسم الواتساب يختفي كلياً لو الموظف ما
            // عنده ولا واحدة من whatsapp.connect/templates. كل بند
            // محمي بمفتاحه.
            if (Perms.hasAny(
                const ['whatsapp.connect', 'whatsapp.templates'])) ...[
              _SectionLabel('الواتساب'),
              if (Perms.has('whatsapp.connect'))
                _Row(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'حالة الواتساب',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WhatsAppStatusScreen(),
                    ),
                  ),
                ),
              if (Perms.hasAll(
                  const ['whatsapp.connect', 'whatsapp.templates']))
                const SizedBox(height: Sp.xs),
              if (Perms.has('whatsapp.templates'))
                _Row(
                  icon: Icons.message_outlined,
                  label: 'قوالب الواتساب',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WhatsAppTemplatesScreen(),
                    ),
                  ),
                ),
              const SizedBox(height: Sp.md),
            ],
            // اعتمادات الأجهزة = إعدادات حسّاسة، نقفلها بـsettings.edit.
            if (Perms.has('settings.edit')) ...[
              _SectionLabel('الأجهزة'),
              _Row(
                icon: Icons.router_outlined,
                label: 'اعتمادات ONU / Ubiquiti',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DeviceDefaultsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: Sp.md),
            ],
            _SectionLabel('الطباعة'),
            _Row(
              icon: Icons.print_outlined,
              label: 'طابعة الوصولات',
              onTap: () => _todo(context, 'الطباعة — قيد التطوير'),
            ),
            const SizedBox(height: Sp.xs),
            _Row(
              icon: Icons.receipt_long_outlined,
              label: 'قوالب الطباعة',
              onTap: () => _todo(context, 'قوالب الطباعة — قيد التطوير'),
            ),
            const SizedBox(height: Sp.md),
            _SectionLabel('التطبيق'),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeService.notifier,
              builder: (_, mode, __) => _Row(
                icon: mode == ThemeMode.dark
                    ? Icons.dark_mode_rounded
                    : mode == ThemeMode.light
                        ? Icons.light_mode_rounded
                        : Icons.brightness_auto_rounded,
                label: 'المظهر',
                trailing: ThemeService.labelFor(mode),
                onTap: () => _openThemePicker(context),
              ),
            ),
            const SizedBox(height: Sp.xs),
            _Row(
              icon: Icons.lock_outline_rounded,
              label: 'صلاحيات التطبيق',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AppPermissionsScreen(),
                ),
              ),
            ),
            const SizedBox(height: Sp.xs),
            _Row(
              icon: Icons.notifications_none_rounded,
              label: 'الإشعارات وأوقات السكون',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationsSettingsScreen(),
                ),
              ),
            ),
            const SizedBox(height: Sp.md),
            _SectionLabel('عن التطبيق'),
            _Row(
              icon: Icons.info_outline_rounded,
              label: 'الإصدار',
              trailing: 'V2.0.0',
            ),
            const SizedBox(height: Sp.huge),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: Material(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(R.md),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _logout,
                  child: Center(
                    child: Text(
                      'تسجيل الخروج',
                      style: AppType.button(color: AppColors.error),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(Sp.lg),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(R.md),
            ),
            alignment: Alignment.center,
            child: Text(
              name.isEmpty ? '?' : name.characters.first,
              style: AppType.title(color: AppColors.brand)
                  .copyWith(fontSize: 22),
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'مستخدم' : name,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, Sp.sm, 4, 6),
      child: Text(
        label,
        style: AppType.muted(color: AppColors.textMid).copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

void _todo(BuildContext ctx, String msg) {
  ScaffoldMessenger.of(ctx).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.textHi,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

void _openThemePicker(BuildContext ctx) {
  showModalBottomSheet<void>(
    context: ctx,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    builder: (_) => const _ThemePickerSheet(),
  );
}

class _ThemePickerSheet extends StatelessWidget {
  const _ThemePickerSheet();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius:
          const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: Sp.md),
              Text(
                'المظهر',
                textAlign: TextAlign.center,
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'يحدد ألوان التطبيق — التلقائي يتبع إعدادات النظام.',
                textAlign: TextAlign.center,
                style: AppType.subtitle(color: AppColors.textMid)
                    .copyWith(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: Sp.lg),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: ThemeService.notifier,
                builder: (_, current, __) => Column(
                  children: [
                    _ThemeOptionTile(
                      icon: Icons.brightness_auto_rounded,
                      label: 'تلقائي',
                      subtitle: 'يتبع إعدادات النظام',
                      selected: current == ThemeMode.system,
                      onTap: () async {
                        await ThemeService.setMode(ThemeMode.system);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(height: Sp.xs),
                    _ThemeOptionTile(
                      icon: Icons.light_mode_rounded,
                      label: 'فاتح',
                      subtitle: 'خلفية بيضاء + ألوان نهارية',
                      selected: current == ThemeMode.light,
                      onTap: () async {
                        await ThemeService.setMode(ThemeMode.light);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(height: Sp.xs),
                    _ThemeOptionTile(
                      icon: Icons.dark_mode_rounded,
                      label: 'داكن',
                      subtitle: 'خلفية داكنة — مريح للعين ليلاً',
                      selected: current == ThemeMode.dark,
                      onTap: () async {
                        await ThemeService.setMode(ThemeMode.dark);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: selected
          ? AppColors.brand.withValues(alpha: 0.10)
          : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.lg,
            vertical: Sp.md,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.brand : Colors.transparent,
              width: 1.4,
            ),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (selected ? AppColors.brand : AppColors.textMid)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 18,
                  color: selected ? AppColors.brand : AppColors.textMid,
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppType.label(color: AppColors.textHi)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppType.muted(color: AppColors.textMid)
                          .copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.brand : AppColors.textLow,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String? trailing;
  /// When non-null the row becomes an InkWell — section entries
  /// (واتساب / طباعة / مظهر / إلخ) use this; the about-version row
  /// leaves it null so it reads as a static info card.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final card = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: Sp.lg,
        vertical: Sp.md,
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMid, size: 20),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Text(label,
                style: AppType.label(color: AppColors.textHi)),
          ),
          if (trailing != null) ...[
            Text(trailing!,
                style: AppType.muted(color: AppColors.textLow)
                    .copyWith(fontSize: 12)),
            const SizedBox(width: 6),
          ],
          if (onTap != null)
            Icon(Icons.chevron_left_rounded,
                color: AppColors.textLow, size: 20),
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: card,
      ),
    );
  }
}
