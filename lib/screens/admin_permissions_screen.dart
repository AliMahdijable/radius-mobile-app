import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/auth_storage.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// عرض الصلاحيات الحالية للمدير. صفحة read-only — لا تعديل من
/// الموبايل (الـsuper-admin يعدلها من لوحة الويب). تعرض:
///   • هل المستخدم super-admin
///   • صلاحية إدارة المدراء الفرعيين (canAccessManagers)
///   • صلاحية إدارة الباقات (canAccessPackages)
///   • معرف الادمن واسم العرض من التخزين
class AdminPermissionsScreen extends StatefulWidget {
  const AdminPermissionsScreen({super.key});

  @override
  State<AdminPermissionsScreen> createState() =>
      _AdminPermissionsScreenState();
}

class _AdminPermissionsScreenState extends State<AdminPermissionsScreen> {
  bool _loading = true;
  bool _isSuperAdmin = false;
  bool _canManagers = false;
  bool _canPackages = false;
  String _adminId = '';
  String _username = '';
  String _displayName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // كل قيمة من خانتها في الـsecure storage. الـauth flow يحفظها
    // عند تسجيل الدخول.
    final results = await Future.wait([
      AuthStorage.readIsSuperAdmin(),
      AuthStorage.readCanAccessManagers(),
      AuthStorage.readCanAccessPackages(),
      AuthStorage.readAdminId(),
      AuthStorage.readAdminUsername(),
      AuthStorage.readDisplayName(),
    ]);
    if (!mounted) return;
    setState(() {
      _isSuperAdmin = results[0] as bool;
      _canManagers = results[1] as bool;
      _canPackages = results[2] as bool;
      _adminId = (results[3] as String?) ?? '';
      _username = (results[4] as String?) ?? '';
      _displayName = (results[5] as String?) ?? '';
      _loading = false;
    });
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
        title: Text(
          'الصلاحيات',
          style: AppType.title(color: AppColors.textHi)
              .copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                _identityCard(),
                const SizedBox(height: Sp.md),
                _SectionLabel('الدور'),
                _PermRow(
                  icon: LucideIcons.crown,
                  label: 'مدير عام (Super Admin)',
                  sub: _isSuperAdmin
                      ? 'وصول كامل لجميع المديولات'
                      : 'دور عادي — صلاحياتك محددة في القائمة أدناه',
                  granted: _isSuperAdmin,
                ),
                const SizedBox(height: Sp.md),
                _SectionLabel('الصلاحيات الفرعية'),
                _PermRow(
                  icon: LucideIcons.userCog,
                  label: 'إدارة المدراء الفرعيين',
                  sub: 'إنشاء، تعديل، حذف، شحن أرصدة المدراء',
                  granted: _canManagers || _isSuperAdmin,
                  permissionKey: 'managers.*',
                ),
                _PermRow(
                  icon: LucideIcons.package,
                  label: 'إدارة الباقات',
                  sub: 'إضافة وتعديل أسعار الباقات للمدير',
                  granted: _canPackages || _isSuperAdmin,
                  permissionKey: 'profiles.*',
                ),
                const SizedBox(height: Sp.lg),
                _noteCard(),
              ],
            ),
    );
  }

  Widget _identityCard() {
    return Container(
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
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(R.md),
            ),
            alignment: Alignment.center,
            child: Text(
              (_displayName.isNotEmpty ? _displayName : _username)
                      .characters
                      .isEmpty
                  ? '?'
                  : (_displayName.isNotEmpty ? _displayName : _username)
                      .characters
                      .first,
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
                  _displayName.isNotEmpty ? _displayName : _username,
                  style: AppType.title(color: AppColors.textHi)
                      .copyWith(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _username.isNotEmpty
                      ? '$_username · ID $_adminId'
                      : 'ID $_adminId',
                  style: AppType.muted(color: AppColors.textMid)
                      .copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteCard() {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.info, size: 14, color: AppColors.textMid),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'التعديل على الصلاحيات يتم من لوحة الويب فقط. هذه الشاشة '
              'للعرض فقط — اتصل بالمدير العام إن احتجت ترقية صلاحية.',
              style: AppType.muted(color: AppColors.textMid)
                  .copyWith(fontSize: 11, height: 1.5),
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

class _PermRow extends StatelessWidget {
  const _PermRow({
    required this.icon,
    required this.label,
    required this.sub,
    required this.granted,
    this.permissionKey,
  });

  final IconData icon;
  final String label;
  final String sub;
  final bool granted;
  final String? permissionKey;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(
          horizontal: Sp.md, vertical: Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: granted
                  ? AppColors.brand.withValues(alpha: 0.14)
                  : AppColors.surfaceInput,
              borderRadius: BorderRadius.circular(R.md),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18,
              color: granted ? AppColors.brand : AppColors.textLow,
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
                  sub,
                  style: AppType.muted(color: AppColors.textMid)
                      .copyWith(fontSize: 11, height: 1.4),
                ),
                if (permissionKey != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceInput,
                      borderRadius: BorderRadius.circular(R.sm),
                    ),
                    child: Text(
                      permissionKey!,
                      style: TextStyle(
                        color: AppColors.textMid,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: granted
                  ? const Color(0xFF14B8A6).withValues(alpha: 0.14)
                  : AppColors.error.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  granted ? LucideIcons.check : LucideIcons.x,
                  size: 12,
                  color: granted
                      ? const Color(0xFF14B8A6)
                      : AppColors.error,
                ),
                const SizedBox(width: 3),
                Text(
                  granted ? 'مفعّل' : 'محظور',
                  style: TextStyle(
                    color: granted
                        ? const Color(0xFF14B8A6)
                        : AppColors.error,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
