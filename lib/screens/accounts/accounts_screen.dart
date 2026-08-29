import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/auth_api.dart';
import '../../api/managers_api.dart';
import '../../services/auth_storage.dart';
import '../../services/fcm_service.dart';
import '../../services/permissions_service.dart';
import '../../services/saved_profiles_store.dart';
import '../../services/session_manager.dart';
import '../../theme/colors.dart';
import '../main_shell.dart';

/// شاشة "الصفحات" — التبديل السريع بين حسابات المدراء الفرعيّين
/// (2026-08-26). طلب المستخدم:
///
/// > "قسم الصفحات — يجلب المدراء وباسورداتهم، هم موجودين أصلاً. يُضاف
///   فوق بصف الإعدادات بحيث المدير يقدر ينتقل بين الصفحات بدون تسجيل
///   دخول."
///
/// **كيف تعمل**:
/// 1. تعرض قائمة المدراء الفرعيّين تحت الأدمن الحاليّ (ManagersApi.listFull)
/// 2. لكل واحد: card فيه اسم + username + زر "دخول"
/// 3. الضغط على دخول → يجيب password من الـbackend (المخزَّن في
///    whatsapp_sessions.admin_password_encrypted) → يحفظ الحساب الحاليّ
///    في SavedProfilesStore (للعودة السريعة) → يسجّل دخول بحساب المدير
///    الفرعي → يفتح MainShell جديد.
/// 4. الأدمن الأصلي يقدر يعود بضغطة واحدة من شاشة الدخول (chip محفوظ).
///
/// **صلاحيّة**: managers.view (نفس صلاحيّة رؤية القائمة).
class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  bool _loading = true;
  String? _error;
  List<_AccountRow> _rows = const [];
  String? _currentUsername;

  /// حساب "الأصلي" — يظهر لو الأدمن الرئيسي انتقل لحساب فرعي.
  /// null لو ما فيه انتقال جارٍ (الأدمن دخل مباشرة).
  ({String username, String password, String displayName})? _original;
  final Set<int> _switching = {};
  bool _returningToOriginal = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // الاسم الحاليّ حتى نميّزه في القائمة.
    _currentUsername = await AuthStorage.readAdminUsername();
    // الحساب الأصلي (لو الأدمن انتقل من super-admin لفرعي، نخزّن هوّيته
    // للعودة السريعة). null لو ما فيه انتقال جارٍ. أيضاً null لو الحاليّ
    // نفسه هو الأصلي (رجعنا بالفعل).
    final orig = await SavedProfilesStore.readOriginal();
    if (orig != null && orig.username != _currentUsername) {
      _original = orig;
    } else {
      _original = null;
      // نظّف إن كنّا رجعنا للأصلي طبيعياً
      if (orig != null) await SavedProfilesStore.clearOriginal();
    }
    // جلب كل المدراء (نجرّب page=1 count=200 حتى نغطّي الحسابات).
    // قد يفشل للفرعي (ما عنده مدراء تحته) — نعرض قائمة فاضية + return only.
    try {
      final res = await ManagersApi.listFull(
        page: 1,
        count: 200,
        sortBy: 'username',
        direction: 'asc',
      );
      final rows = res.rows
          .map((m) => _AccountRow(
                id: m.id,
                username: m.username,
                fullName: m.fullName,
                isActive: m.isActive,
              ))
          .toList();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _error = _original == null ? e.toString() : null;
        _loading = false;
      });
    }
  }

  Future<void> _switchTo(_AccountRow row) async {
    // منع التبديل للحساب نفسه.
    if (row.username == _currentUsername) {
      _snack('أنت الآن مسجّل دخول بهذا الحساب', error: true);
      return;
    }
    // تأكيد
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'تبديل الحساب',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w700),
        ),
        content: Text(
          'سيتمّ تسجيل دخول بحساب "${row.username}". الحساب الحاليّ يُحفظ في شاشة الدخول للعودة السريعة.',
          style: const TextStyle(fontFamily: 'Cairo', height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('تبديل',
                style: TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _switching.add(row.id));
    try {
      // 1) اجلب كلمة السر للفرعي
      final pw = await ManagersApi.fetchPassword(row.id);
      if (!mounted) return;
      if (pw.password == null) {
        _snack(pw.message ?? 'تعذّر جلب كلمة السر', error: true);
        return;
      }
      // 2) قبل ما نبدّل — احفظ الحساب الحاليّ كـ"الأصلي" حتى نقدر نرجع.
      //    نأخذ كلمة سرّه من SavedProfilesStore (كل login يخزّنه هناك).
      //    لو غير موجود لسبب ما، نتخطّى — الأدمن ما راح يشوف زر رجوع
      //    لكن العمل يكمل عادي.
      if (_currentUsername != null && _original == null) {
        final saved = await SavedProfilesStore.list();
        final me =
            saved.where((p) => p.username == _currentUsername).firstOrNull;
        if (me != null) {
          try {
            final plain =
                await SavedProfilesStore.decrypt(me.encryptedPassword);
            final displayName =
                await AuthStorage.readDisplayName() ?? _currentUsername!;
            await SavedProfilesStore.setOriginal(
              username: _currentUsername!,
              plainPassword: plain,
              displayName: displayName,
            );
          } catch (_) {/* best-effort */}
        }
      }
      // 3) اسجّل دخول بالحساب الجديد
      final res = await AuthApi.login(
        username: row.username,
        password: pw.password!,
      );
      if (!mounted) return;
      switch (res) {
        case LoginSuccess(
            :final token,
            :final adminId,
            :final adminUsername,
            :final displayName,
            :final expiresAt,
            :final isSuperAdmin,
            :final canAccessManagers,
            :final canAccessPackages,
            :final isEmployee,
            :final sas4Token,
          ):
          // 3) امسح الجلسة الحاليّة (بدون مسح الملفّات المحفوظة).
          await SessionManager.clearAllSessionData(
            unregisterFcm: false,
            clearAuth: false,
          );
          // 4) خزّن الجديد
          await AuthStorage.saveSession(
            token: token,
            adminId: adminId,
            adminUsername: adminUsername,
            displayName: displayName,
            autoLogin: true,
            tokenExpiry: expiresAt,
            isSuperAdmin: isSuperAdmin,
            canAccessManagers: canAccessManagers,
            canAccessPackages: canAccessPackages,
            isEmployee: isEmployee,
            sas4Token: sas4Token,
          );
          // 5) أضف الحساب الجديد للملفّات المحفوظة (حتى يظهر chip
          //    لاحقاً)، والحساب السابق موجود سلفاً لأنّه سجّل دخول من
          //    نفس هذا الجهاز.
          await SavedProfilesStore.upsert(
            username: row.username,
            plainPassword: pw.password!,
            displayName: displayName.isNotEmpty ? displayName : row.username,
          );
          // 6) جدّد الصلاحيّات ثم افتح MainShell جديد
          if (isEmployee) {
            final okPerms = await PermissionsService.refreshFromBackend();
            if (!mounted) return;
            if (!okPerms) await PermissionsService.clear();
          }
          // ignore: unawaited_futures
          FcmService.initAfterLogin();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainShell()),
            (route) => false,
          );
        case LoginFailure(:final message):
          _snack(message, error: true);
      }
    } catch (e) {
      if (mounted) _snack('فشل التبديل: $e', error: true);
    } finally {
      if (mounted) setState(() => _switching.remove(row.id));
    }
  }

  /// 2026-08-26: العودة للحساب الأصلي. يستدعي login بالمرجع المحفوظ في
  /// SavedProfilesStore.readOriginal() ثم يمسحه. الأدمن يرجع بضغطة واحدة.
  Future<void> _returnToOriginal() async {
    final orig = _original;
    if (orig == null) return;
    setState(() => _returningToOriginal = true);
    try {
      final res = await AuthApi.login(
        username: orig.username,
        password: orig.password,
      );
      if (!mounted) return;
      switch (res) {
        case LoginSuccess(
            :final token,
            :final adminId,
            :final adminUsername,
            :final displayName,
            :final expiresAt,
            :final isSuperAdmin,
            :final canAccessManagers,
            :final canAccessPackages,
            :final isEmployee,
            :final sas4Token,
          ):
          await SessionManager.clearAllSessionData(
            unregisterFcm: false,
            clearAuth: false,
          );
          await AuthStorage.saveSession(
            token: token,
            adminId: adminId,
            adminUsername: adminUsername,
            displayName: displayName,
            autoLogin: true,
            tokenExpiry: expiresAt,
            isSuperAdmin: isSuperAdmin,
            canAccessManagers: canAccessManagers,
            canAccessPackages: canAccessPackages,
            isEmployee: isEmployee,
            sas4Token: sas4Token,
          );
          // نظّف مرجع الأصلي — رجعنا فعلاً.
          await SavedProfilesStore.clearOriginal();
          if (isEmployee) {
            final okPerms = await PermissionsService.refreshFromBackend();
            if (!mounted) return;
            if (!okPerms) await PermissionsService.clear();
          }
          // ignore: unawaited_futures
          FcmService.initAfterLogin();
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const MainShell()),
            (route) => false,
          );
        case LoginFailure(:final message):
          _snack(message, error: true);
      }
    } catch (e) {
      if (mounted) _snack('فشلت العودة: $e', error: true);
    } finally {
      if (mounted) setState(() => _returningToOriginal = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: error ? AppColors.error : AppColors.brand,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'الصفحات',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_error != null && _original == null)
                ? _errorState()
                : RefreshIndicator(
                    onRefresh: _load,
                    color: AppColors.brand,
                    child: ListView(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom + 32),
                      children: [
                        _compactHeader(),
                        // 2026-08-26: بطاقة "العودة للحساب الأصلي" —
                        // تظهر أول شي لمّا يكون فيه انتقال جارٍ.
                        if (_original != null) _originalTile(_original!),
                        if (_rows.isEmpty && _original == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 48),
                            child: _emptyState(),
                          )
                        else if (_rows.isEmpty && _original != null)
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'لا يوجد مدراء تحت هذا الحساب — استعمل زر "العودة" أعلاه للرجوع للحساب الأصلي.',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textMid,
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          )
                        else
                          for (final r in _rows) _accountTile(r),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _compactHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.brand.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(LucideIcons.repeat2, size: 18, color: AppColors.brand),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'التبديل السريع',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textHi,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'اضغط "دخول" لتسجيل الدخول بحساب مدير آخر بلا كتابة كلمة السر.',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMid,
                    height: 1.4,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 2026-08-26: bar بارز للعودة للحساب الأصلي. لون brand بارز حتى
  /// المدير يشوفه فوراً — دخل بلا قصد لحساب فرعي والحل بضغطة واحدة.
  Widget _originalTile(
      ({String username, String password, String displayName}) orig) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brand,
            AppColors.brand.withValues(alpha: 0.8),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _returningToOriginal ? null : _returnToOriginal,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.onBrand.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    LucideIcons.arrowLeftToLine,
                    color: AppColors.onBrand,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'العودة للحساب الأصلي',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onBrand,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        orig.displayName.isNotEmpty
                            ? '${orig.displayName}  ·  @${orig.username}'
                            : '@${orig.username}',
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onBrand.withValues(alpha: 0.9),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (_returningToOriginal)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onBrand,
                    ),
                  )
                else
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.onBrand.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      LucideIcons.arrowRight,
                      color: AppColors.onBrand,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accountTile(_AccountRow row) {
    final isCurrent = row.username == _currentUsername;
    final busy = _switching.contains(row.id);
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: (isCurrent || busy) ? null : () => _switchTo(row),
        child: Container(
          padding: const EdgeInsetsDirectional.only(
              start: 12, end: 12, top: 10, bottom: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.border, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              // Rail — أخضر مفعّل / رمادي فعّل معطّل
              Container(
                width: 3,
                height: 36,
                decoration: BoxDecoration(
                  color: row.isActive ? AppColors.brand : AppColors.textLow,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.brandAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: Icon(LucideIcons.shield,
                    size: 16, color: AppColors.brandAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            row.username,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textHi,
                              height: 1.15,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isCurrent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.brandSoftBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'أنت',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brand,
                              ),
                            ),
                          ),
                        ],
                        if (!row.isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.dangerSoftBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'معطّل',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (row.fullName.isNotEmpty &&
                        row.fullName != row.username) ...[
                      const SizedBox(height: 3),
                      Text(
                        row.fullName,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMid,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isCurrent)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  child: Text(
                    'الحالي',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textLow,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 32,
                  child: FilledButton.icon(
                    onPressed: busy ? null : () => _switchTo(row),
                    icon: busy
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppColors.onBrand,
                            ),
                          )
                        : const Icon(LucideIcons.logIn, size: 14),
                    label: const Text(
                      'دخول',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
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

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.userX, size: 40, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(
            'لا يوجد مدراء فرعيّون',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textMid,
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.circleAlert, size: 40, color: AppColors.error),
          const SizedBox(height: 10),
          Text(
            _error ?? 'خطأ',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12,
              color: AppColors.textMid,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _load,
            icon: const Icon(LucideIcons.refreshCw, size: 14),
            label: const Text('إعادة المحاولة',
                style: TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
  }
}

class _AccountRow {
  final int id;
  final String username;
  final String fullName;
  final bool isActive;
  const _AccountRow({
    required this.id,
    required this.username,
    required this.fullName,
    required this.isActive,
  });
}
