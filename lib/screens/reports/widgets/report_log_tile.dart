import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// سطر موحَّد لعرض حركة في التقارير المالية + سجل النشاط.
/// يكشف: الـaction (badge ملوّن) + الوصف + المنفِّذ (موظف لو موجود)
/// + المبلغ (سالب/موجب) + الوقت.
class ReportLogTile extends StatelessWidget {
  const ReportLogTile({
    super.key,
    required this.actionType,
    required this.description,
    this.amount = 0,
    this.adminUsername,
    this.employeeFullName,
    this.employeeUsername,
    this.targetName,
    required this.createdAt,
  });

  final String actionType;
  final String description;
  final num amount;
  final String? adminUsername;
  final String? employeeFullName;
  final String? employeeUsername;
  final String? targetName;
  final String createdAt;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final meta = _actionMeta(actionType, description);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: meta.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(meta.icon, color: meta.color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: meta.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        meta.label,
                        style: TextStyle(
                          color: meta.color,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (amount != 0)
                      Text(
                        '${meta.debit ? '-' : ''}${formatIQD(amount.abs())} د.ع',
                        style: TextStyle(
                          // debit → أحمر (سالب)، عكسه → أخضر (موجب).
                          color: meta.debit ? AppColors.error : _kPositive,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  description.isNotEmpty
                      ? description
                      : (targetName ?? '—'),
                  style: AppType.subtitle(color: AppColors.textHi)
                      .copyWith(fontSize: 12, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(LucideIcons.clock,
                        size: 10, color: AppColors.textLow),
                    const SizedBox(width: 3),
                    Text(
                      _formatDate(createdAt),
                      style:
                          AppType.muted().copyWith(fontSize: 10, height: 1.2),
                    ),
                    if (employeeFullName != null &&
                        employeeFullName!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(LucideIcons.userCheck,
                          size: 10, color: AppColors.brand),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          employeeFullName!,
                          style: AppType.muted().copyWith(
                              fontSize: 10,
                              color: AppColors.brand,
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// تنسيق تاريخ ISO إلى "YYYY-MM-DD HH:MM" — مختصر.
  /// الـbackend يرجع UTC؛ نحوّل لتوقيت Asia/Baghdad (UTC+3).
  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).add(const Duration(hours: 3));
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final mi = dt.minute.toString().padLeft(2, '0');
      return '${dt.year}-$m-$d $h:$mi';
    } catch (_) {
      return iso;
    }
  }
}

/// خصائص العرض حسب نوع العملية. نفس الـmapping في
/// client-v2/src/pages/reports/_shared.tsx mapActionType.
class _ActionMeta {
  const _ActionMeta(this.label, this.icon, this.color, {this.debit = false});
  final String label;
  final IconData icon;
  final Color color;
  final bool debit;
}

/// ألوان اتفاقية:
///   • أخضر (0xFF14B8A6) = موجب (تفعيل نقدي، تمديد نقدي، تسديد دين)
///   • أحمر (AppColors.error) = سالب (تفعيل غير نقدي، إضافة دين، صرفية)
/// المستخدم صرّح 2026-07-10 بالقاعدة.
const Color _kPositive = Color(0xFF14B8A6);

/// نقدي أم غير نقدي حسب وصف الحركة.
/// وصف مثال: "تفعيل المشترك | ... | نقدي" أو "... | غير نقدي".
bool _isNonCash(String desc) => desc.contains('غير نقدي');
bool _isCash(String desc) =>
    desc.contains('نقدي') && !desc.contains('غير نقدي');

_ActionMeta _actionMeta(String at, String desc) {
  switch (at) {
    case 'SUBSCRIBER_ACTIVATE':
      // نقدي = موجب أخضر، غير نقدي = سالب أحمر، مجهول = افتراضي.
      if (_isNonCash(desc)) {
        return _ActionMeta('تفعيل', LucideIcons.zap, AppColors.error,
            debit: true);
      }
      if (_isCash(desc)) {
        return const _ActionMeta('تفعيل', LucideIcons.zap, _kPositive);
      }
      return const _ActionMeta('تفعيل', LucideIcons.zap, _kPositive);
    case 'SUBSCRIBER_EXTEND':
      // نفس منطق التفعيل — نقدي أخضر، غير نقدي أحمر.
      if (_isNonCash(desc)) {
        return _ActionMeta('تمديد', LucideIcons.repeat, AppColors.error,
            debit: true);
      }
      return const _ActionMeta('تمديد', LucideIcons.repeat, _kPositive);
    case 'SUBSCRIBER_ADD':
      // لو الوصف تفعيل نتعامل معه مثل SUBSCRIBER_ACTIVATE.
      if (desc.contains('تفعيل')) {
        if (_isNonCash(desc)) {
          return _ActionMeta('تفعيل', LucideIcons.zap, AppColors.error,
              debit: true);
        }
        return const _ActionMeta('تفعيل', LucideIcons.zap, _kPositive);
      }
      return const _ActionMeta(
          'إضافة مشترك', LucideIcons.userPlus, _kPositive);
    case 'SUBSCRIBER_EDIT':
      return const _ActionMeta(
          'تعديل مشترك', LucideIcons.pencil, Color(0xFF3B82F6));
    case 'SUBSCRIBER_DELETE':
      return _ActionMeta('حذف مشترك', LucideIcons.trash2, AppColors.error,
          debit: false);
    case 'SUBSCRIBER_ENABLE':
      return const _ActionMeta(
          'تشغيل', LucideIcons.circleCheck, Color(0xFF14B8A6));
    case 'SUBSCRIBER_DISABLE':
      return const _ActionMeta(
          'تعطيل', LucideIcons.ban, Color(0xFFE08F2D));
    case 'BALANCE_ADD':
      // إضافة دين = سالب أحمر (مبلغ يزيد على المشترك، خسارة للمدير).
      return _ActionMeta('إضافة دين', LucideIcons.plus, AppColors.error,
          debit: true);
    case 'BALANCE_DEDUCT':
      // BALANCE_DEDUCT + description "تسديد دين …" = تسديد دين فعلياً
      // (مطابق web _shared.tsx:520-522). لون موجب أخضر.
      return const _ActionMeta(
          'تسديد دين', LucideIcons.banknote, _kPositive);
    case 'DEBT_PAY':
      return const _ActionMeta(
          'تسديد دين', LucideIcons.banknote, _kPositive);
    case 'PAYMENT_ADD':
      return const _ActionMeta(
          'دفعة', LucideIcons.banknote, Color(0xFF14B8A6));
    case 'EXPENSE_ADD':
    case 'ADMIN_EXPENSE':
      // ADMIN_EXPENSE من backend /api/reports/finance (صف صناعي).
      // EXPENSE_ADD من ExpensesApi في Activity Log. نفس المعنى، نفس التصميم.
      return _ActionMeta('صرفية', LucideIcons.receipt, AppColors.error,
          debit: true);
    case 'EXPENSE_EDIT':
      return _ActionMeta(
          'تعديل صرفية', LucideIcons.receipt, AppColors.error);
    case 'EXPENSE_DELETE':
      return _ActionMeta(
          'حذف صرفية', LucideIcons.receipt, AppColors.error);
    case 'MANAGER_ADD':
      return const _ActionMeta(
          'إضافة مدير', LucideIcons.userPlus, Color(0xFF8B5CF6));
    case 'MANAGER_EDIT':
      return const _ActionMeta(
          'تعديل مدير', LucideIcons.pencil, Color(0xFF8B5CF6));
    case 'MANAGER_DELETE':
      return _ActionMeta('حذف مدير', LucideIcons.trash2, AppColors.error);
    case 'ADMIN_ADD':
      return const _ActionMeta(
          'إضافة موظف', LucideIcons.userPlus, Color(0xFF8B5CF6));
    case 'ADMIN_EDIT':
      return const _ActionMeta(
          'تعديل موظف', LucideIcons.pencil, Color(0xFF8B5CF6));
    case 'ADMIN_DELETE':
      return _ActionMeta('حذف موظف', LucideIcons.trash2, AppColors.error);
    case 'PACKAGE_EDIT':
      return const _ActionMeta(
          'تعديل باقة', LucideIcons.package, Color(0xFF8B5CF6));
    case 'DISCOUNT_SET':
      return const _ActionMeta(
          'تطبيق خصم', LucideIcons.tag, Color(0xFF14B8A6));
    case 'DISCOUNT_REMOVE':
      return const _ActionMeta(
          'إزالة خصم', LucideIcons.tag, Color(0xFFE08F2D));
    case 'WHATSAPP_SEND_MESSAGE':
      return const _ActionMeta(
          'إرسال واتساب', LucideIcons.messageCircle, Color(0xFF25D366));
    case 'WHATSAPP_CONNECT':
      return const _ActionMeta(
          'اتصال واتساب', LucideIcons.smartphone, Color(0xFF25D366));
    case 'WHATSAPP_DISCONNECT':
      return const _ActionMeta(
          'فصل واتساب', LucideIcons.smartphone, Color(0xFFE08F2D));
    case 'WHATSAPP_TEMPLATE_SAVE':
      return const _ActionMeta(
          'حفظ قالب WA', LucideIcons.fileText, Color(0xFF25D366));
    case 'WHATSAPP_TEMPLATE_DELETE':
      return const _ActionMeta(
          'حذف قالب WA', LucideIcons.fileText, Color(0xFFE08F2D));
    case 'PRINT_RECEIPT':
      return const _ActionMeta(
          'طباعة وصل', LucideIcons.printer, Color(0xFF3B82F6));
    case 'PRINT_TEMPLATE_SAVE':
      return const _ActionMeta(
          'حفظ قالب طباعة', LucideIcons.fileText, Color(0xFF3B82F6));
    case 'LOGIN':
      return const _ActionMeta(
          'تسجيل دخول', LucideIcons.circleCheck, Color(0xFF26A69A));
    case 'LOGOUT':
      return const _ActionMeta(
          'تسجيل خروج', LucideIcons.power, Color(0xFFCD8B00));
    case 'LOGIN_FAILED':
      return _ActionMeta('فشل دخول', LucideIcons.alertCircle, AppColors.error);
    case 'EXPIRY_NOTIFICATION':
      return const _ActionMeta(
          'إشعار انتهاء', LucideIcons.bellRing, Color(0xFFE08F2D));
    case 'SYSTEM_ERROR':
      return _ActionMeta('خطأ', LucideIcons.alertTriangle, AppColors.error);
    default:
      return _ActionMeta(at, LucideIcons.activity, AppColors.textMid);
  }
}
