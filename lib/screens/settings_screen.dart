import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../services/app_version.dart';
import '../services/auth_storage.dart';
import '../services/locale_service.dart';
import '../services/permissions_service.dart';
import '../services/saved_profiles_store.dart';
import '../services/session_manager.dart';
import '../services/print_prefs.dart';
import '../services/theme_service.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'app_permissions_screen.dart';
import 'devices/device_defaults_screen.dart';
import 'login_screen.dart';
import 'notifications_settings_screen.dart';
import 'print_templates/print_templates_screen.dart';
import 'whatsapp/whatsapp_schedules_screen.dart';
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
        title: Text('settings.logout_title'.tr(),
            style:
                AppType.title(color: AppColors.textHi).copyWith(fontSize: 18)),
        content: Text(
          'settings.logout_body'.tr(),
          style:
              AppType.subtitle(color: AppColors.textMid).copyWith(height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr(),
                style: AppType.button(color: AppColors.textMid)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.logout'.tr(),
                style: AppType.button(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    // 2026-07-14: كل التنظيف عبر SessionManager الموحّد — يضمن أن
    // كل مسار للخروج (logout يدوي، 401 kick، login جديد) يستعمل نفس
    // الروتين ولا ينسى caches جديدة تُضاف لاحقاً.
    await SessionManager.clearAllSessionData();
    // 2026-08-26: امسح مرجع الأصلي — Logout يدوي = "أنا أعرف شنو أعمل"،
    // فلا مبرّر يبقى مرجع للـswitcher الأصلي مخزَّن (سيرتبك أول تبديل
    // بعد login جديد). الحسابات المحفوظة العامّة تبقى كما هي.
    await SavedProfilesStore.clearOriginal();
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
                'settings.title'.tr(),
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'common.back'.tr(),
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
                child: Text('settings.title'.tr(),
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
              _SectionLabel('settings.whatsapp'.tr()),
              if (Perms.has('whatsapp.connect'))
                _Row(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'settings.whatsapp_status'.tr(),
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
                  label: 'settings.whatsapp_templates'.tr(),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WhatsAppTemplatesScreen(),
                    ),
                  ),
                ),
              // مطلب 2026-XX: قائمة الجدولة (أوقات + أيام تبليغات)
              // منقولة من v1 — الآن متاحة تحت whatsapp.templates.
              if (Perms.has('whatsapp.templates'))
                const SizedBox(height: Sp.xs),
              if (Perms.has('whatsapp.templates'))
                _Row(
                  icon: Icons.schedule_outlined,
                  label: 'settings.whatsapp_schedules'.tr(),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const WhatsAppSchedulesScreen(),
                    ),
                  ),
                ),
              const SizedBox(height: Sp.md),
            ],
            // اعتمادات الأجهزة = إعدادات حسّاسة، نقفلها بـsettings.edit.
            if (Perms.has('settings.edit')) ...[
              _SectionLabel('settings.devices'.tr()),
              _Row(
                icon: Icons.router_outlined,
                label: 'settings.device_creds'.tr(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DeviceDefaultsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: Sp.md),
            ],
            _SectionLabel('settings.printing'.tr()),
            // 2026-07-13: بدل الـstub، صار يفتح picker لنوع الطابعة
            // (A4 / POS 80mm). الاختيار محفوظ ويُستعمل لأزرار "طباعة
            // الوصل" بعد التفعيل/التسديد.
            ValueListenableBuilder<PrintFormatChoice>(
              valueListenable: PrintPrefs.notifier,
              builder: (_, choice, __) => _Row(
                icon: Icons.print_outlined,
                label: 'settings.default_printer'.tr(),
                trailing: choice == PrintFormatChoice.a4 ? 'A4' : 'POS 80mm',
                onTap: () => _openPrinterFormatPicker(context),
              ),
            ),
            const SizedBox(height: Sp.xs),
            _Row(
              icon: Icons.receipt_long_outlined,
              label: 'settings.print_templates'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PrintTemplatesScreen(),
                ),
              ),
            ),
            const SizedBox(height: Sp.md),
            _SectionLabel('settings.app'.tr()),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: ThemeService.notifier,
              builder: (_, mode, __) => _Row(
                icon: mode == ThemeMode.dark
                    ? Icons.dark_mode_rounded
                    : mode == ThemeMode.light
                        ? Icons.light_mode_rounded
                        : Icons.brightness_auto_rounded,
                label: 'settings.theme'.tr(),
                trailing: _themeLabel(mode),
                onTap: () => _openThemePicker(context),
              ),
            ),
            const SizedBox(height: Sp.xs),
            // مطلب 2026-07-12: صف اللغة يفتح picker (عربي / English).
            _Row(
              icon: Icons.language_rounded,
              label: 'settings.language'.tr(),
              trailing: LocaleService.labelFor(context.locale),
              onTap: () => _openLanguagePicker(context),
            ),
            const SizedBox(height: Sp.xs),
            _Row(
              icon: Icons.lock_outline_rounded,
              label: 'settings.permissions'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AppPermissionsScreen(),
                ),
              ),
            ),
            const SizedBox(height: Sp.xs),
            _Row(
              icon: Icons.notifications_none_rounded,
              label: 'settings.notifications'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NotificationsSettingsScreen(),
                ),
              ),
            ),
            const SizedBox(height: Sp.md),
            _SectionLabel('settings.about'.tr()),
            _Row(
              icon: Icons.info_outline_rounded,
              label: 'settings.version'.tr(),
              // بلا buildNumber (نُخفيه — طلب المستخدم). الـshortVersion = 'v2.0.1'
              trailing: AppVersion.shortVersion,
            ),
            const SizedBox(height: Sp.md),
            // 2026-08-26: مسح الحسابات المحفوظة على شاشة الدخول (chips).
            // منفصل عن Logout — Logout ينظّف الجلسة ويُبقي الحسابات المحفوظة.
            SizedBox(
              width: double.infinity,
              height: 44,
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(R.md),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.surface,
                        title: const Text('مسح الحسابات المحفوظة'),
                        content: const Text(
                            'سيتمّ حذف كل الحسابات (يوزر+باسورد) المحفوظة على شاشة الدخول. متأكّد؟'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('إلغاء'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.error),
                            child: const Text('حذف'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await SavedProfilesStore.clearAll();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('تمّ مسح الحسابات المحفوظة'),
                          backgroundColor: AppColors.brand,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: Center(
                    child: Text(
                      'مسح الحسابات المحفوظة',
                      style: AppType.button(color: AppColors.textMid),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Sp.lg),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: Material(
                color: AppColors.dangerSoftBg,
                borderRadius: BorderRadius.circular(R.md),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _logout,
                  child: Center(
                    child: Text(
                      'common.logout'.tr(),
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
              style:
                  AppType.title(color: AppColors.brand).copyWith(fontSize: 22),
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

void _openPrinterFormatPicker(BuildContext ctx) {
  showModalBottomSheet<void>(
    context: ctx,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    builder: (_) => const _PrinterFormatPickerSheet(),
  );
}

/// النص المعروض على السطر الرئيسي بجانب "المظهر" — يترجم حسب اللغة
/// الحالية بدل ThemeService.labelFor الثابت العربي.
String _themeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'settings.theme_light'.tr();
    case ThemeMode.dark:
      return 'settings.theme_dark'.tr();
    case ThemeMode.system:
      return 'settings.theme_system'.tr();
  }
}

void _openLanguagePicker(BuildContext ctx) {
  showModalBottomSheet<void>(
    context: ctx,
    backgroundColor: Colors.transparent,
    isScrollControlled: false,
    builder: (_) => const _LanguagePickerSheet(),
  );
}

class _LanguagePickerSheet extends StatelessWidget {
  const _LanguagePickerSheet();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final current = context.locale;
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                'settings.language'.tr(),
                textAlign: TextAlign.center,
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'settings.language_hint'.tr(),
                textAlign: TextAlign.center,
                style: AppType.subtitle(color: AppColors.textMid)
                    .copyWith(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: Sp.lg),
              _ThemeOptionTile(
                icon: Icons.language_rounded,
                label: 'settings.language_arabic'.tr(),
                subtitle: 'العربية · RTL',
                selected: current.languageCode == 'ar',
                onTap: () async {
                  await LocaleService.setLocale(context, LocaleService.arabic);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
              const SizedBox(height: Sp.xs),
              _ThemeOptionTile(
                icon: Icons.language_rounded,
                label: 'settings.language_english'.tr(),
                subtitle: 'English · LTR',
                selected: current.languageCode == 'en',
                onTap: () async {
                  await LocaleService.setLocale(context, LocaleService.english);
                  if (context.mounted) Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemePickerSheet extends StatelessWidget {
  const _ThemePickerSheet();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                'settings.theme'.tr(),
                textAlign: TextAlign.center,
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'settings.theme_desc'.tr(),
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
                      label: 'settings.theme_system'.tr(),
                      subtitle: 'settings.theme_system_desc'.tr(),
                      selected: current == ThemeMode.system,
                      onTap: () async {
                        await ThemeService.setMode(ThemeMode.system);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(height: Sp.xs),
                    _ThemeOptionTile(
                      icon: Icons.light_mode_rounded,
                      label: 'settings.theme_light'.tr(),
                      subtitle: 'settings.theme_light_desc'.tr(),
                      selected: current == ThemeMode.light,
                      onTap: () async {
                        await ThemeService.setMode(ThemeMode.light);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(height: Sp.xs),
                    _ThemeOptionTile(
                      icon: Icons.dark_mode_rounded,
                      label: 'settings.theme_dark'.tr(),
                      subtitle: 'settings.theme_dark_desc'.tr(),
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

class _PrinterFormatPickerSheet extends StatelessWidget {
  const _PrinterFormatPickerSheet();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                'settings.default_printer'.tr(),
                textAlign: TextAlign.center,
                style: AppType.title(color: AppColors.textHi)
                    .copyWith(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'settings.default_printer_desc'.tr(),
                textAlign: TextAlign.center,
                style: AppType.subtitle(color: AppColors.textMid)
                    .copyWith(fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: Sp.lg),
              ValueListenableBuilder<PrintFormatChoice>(
                valueListenable: PrintPrefs.notifier,
                builder: (_, current, __) => Column(
                  children: [
                    _ThemeOptionTile(
                      icon: Icons.receipt_outlined,
                      label: 'settings.printer_pos'.tr(),
                      subtitle: 'settings.printer_pos_desc'.tr(),
                      selected: current == PrintFormatChoice.pos,
                      onTap: () async {
                        await PrintPrefs.setFormat(PrintFormatChoice.pos);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(height: Sp.xs),
                    _ThemeOptionTile(
                      icon: Icons.description_outlined,
                      label: 'settings.printer_a4'.tr(),
                      subtitle: 'settings.printer_a4_desc'.tr(),
                      selected: current == PrintFormatChoice.a4,
                      onTap: () async {
                        await PrintPrefs.setFormat(PrintFormatChoice.a4);
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
      color: selected ? AppColors.brandSoftBg : AppColors.surfaceInput,
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
            child: Text(label, style: AppType.label(color: AppColors.textHi)),
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
