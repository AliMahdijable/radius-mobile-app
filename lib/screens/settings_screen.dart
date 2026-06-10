import 'package:flutter/material.dart';

import '../services/auth_storage.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'devices/device_defaults_screen.dart';
import 'login_screen.dart';
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
    await AuthStorage.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
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
            _IdentityCard(name: _name, id: _id),
            const SizedBox(height: Sp.lg),
            // مطلب 2026-06-10: شاشة الإعدادات تضم أقسام: واتساب +
            // قوالبه، طباعة + قوالبها، المظهر، البصمة، الصلاحيات،
            // الإشعارات، السكون. حالياً كل واحد stub يفتح snack
            // 'قيد التطوير' حتى نبني كل قسم على حدة.
            _SectionLabel('الواتساب'),
            _Row(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'حالة الواتساب',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WhatsAppStatusScreen(),
                ),
              ),
            ),
            const SizedBox(height: Sp.xs),
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
            _Row(
              icon: Icons.dark_mode_outlined,
              label: 'المظهر',
              trailing: 'نهاري',
              onTap: () => _todo(context, 'تبديل المظهر — قيد التطوير'),
            ),
            const SizedBox(height: Sp.xs),
            _Row(
              icon: Icons.fingerprint_rounded,
              label: 'البصمة / Face ID',
              onTap: () => _todo(context, 'البصمة — قيد التطوير'),
            ),
            const SizedBox(height: Sp.xs),
            _Row(
              icon: Icons.shield_outlined,
              label: 'الصلاحيات',
              onTap: () => _todo(context, 'الصلاحيات — قيد التطوير'),
            ),
            const SizedBox(height: Sp.xs),
            _Row(
              icon: Icons.notifications_none_rounded,
              label: 'الإشعارات',
              onTap: () => _todo(context, 'الإشعارات — قيد التطوير'),
            ),
            const SizedBox(height: Sp.xs),
            _Row(
              icon: Icons.bedtime_outlined,
              label: 'أوقات السكون',
              onTap: () => _todo(context, 'أوقات السكون — قيد التطوير'),
            ),
            const SizedBox(height: Sp.md),
            _SectionLabel('عن التطبيق'),
            _Row(
              icon: Icons.info_outline_rounded,
              label: 'الإصدار',
              trailing: 'v2.0.0 (87)',
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
  const _IdentityCard({required this.name, required this.id});
  final String name;
  final String id;

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 2),
                Text(
                  id.isEmpty ? '—' : 'ID: $id',
                  style: AppType.subtitle(color: AppColors.textMid)
                      .copyWith(fontSize: 12),
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
            const Icon(Icons.chevron_left_rounded,
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
