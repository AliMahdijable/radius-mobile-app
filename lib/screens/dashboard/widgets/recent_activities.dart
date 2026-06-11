import 'package:flutter/material.dart';

import '../../../core/util/format.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Recent activity feed for home. Backend rows from
/// /api/activities/daily-activations are raw maps; the row widget reads
/// each field directly. No mock fallback — loading/empty/error states
/// are rendered by the dashboard.
class RecentActivities extends StatelessWidget {
  const RecentActivities({super.key, required this.items});

  /// Backend rows from /api/activities/daily-activations.
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _Row(item: items[i]),
            if (i < items.length - 1)
              Divider(
                height: 1,
                indent: Sp.huge + Sp.sm,
                endIndent: Sp.lg,
                color: AppColors.border,
              ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});
  final Map<String, dynamic> item;

  ({
    IconData icon,
    Color color,
    String title,
    String? subLabel,
    String? detail,
    int amount,
    String timeLabel,
    String? actor,
    bool actorIsEmployee,
  }) _normalize() {
    final m = item;
    final action = (m['action'] ?? m['action_type'] ?? '').toString();
    final descr = (m['action_description'] ?? m['description'] ?? '').toString();
    final visual = _visualForAction(action);
    // Backend enriches each row with user_firstname / user_lastname /
    // user_username via SAS4's user directory (see
    // /api/activities/daily-activations row enrichment). The Arabic
    // full name reads at-a-glance; the username goes in parentheses
    // as a secondary identifier so admins still see "the same
    // ahmed@x" they're used to from the v1 web. Falls back to
    // username alone when no name is in SAS4.
    final firstname = (m['user_firstname'] ?? '').toString().trim();
    final lastname = (m['user_lastname'] ?? '').toString().trim();
    final username = (m['user_username'] ??
            m['target_name'] ??
            m['subscriber_username'] ??
            m['username'] ??
            '')
        .toString()
        .trim();
    final fullName =
        [firstname, lastname].where((s) => s.isNotEmpty).join(' ').trim();
    final title = fullName.isNotEmpty
        ? (username.isNotEmpty ? '$fullName ($username)' : fullName)
        : (username.isNotEmpty ? username : action);
    final details = _actionDetails(action, descr);
    final amount = _readAmount(m);
    final created = m['created_at']?.toString();
    final timeLabel = _humanCreatedAt(created);
    // مطلب 2026-06-11: عرض منو سوة الحركة. v1 backend يرجّع
    // acting_employee_* لما الموظف ينفّذها، وadmin_username للمدير
    // (الأب) دائماً. الموظف أولوية لأنه الفاعل الفعلي حتى لو الـadmin_id
    // هو الأب. لو الـemployee فارغ نرجع للـadmin_username (نص "أنت"
    // ما يتطابق هنا لأن المدير ممكن يشوف نشاطات موظفه فيحتاج اسم محدد).
    final empName = (m['acting_employee_full_name'] ?? '').toString().trim();
    final empUser = (m['acting_employee_username'] ?? '').toString().trim();
    final adminUser = (m['admin_username'] ?? '').toString().trim();
    String? actor;
    var isEmployee = false;
    if (empName.isNotEmpty || empUser.isNotEmpty) {
      actor = empName.isNotEmpty ? empName : empUser;
      isEmployee = true;
    } else if (adminUser.isNotEmpty) {
      actor = adminUser;
    }
    return (
      icon: visual.$1,
      color: visual.$2,
      title: title,
      subLabel: details.label,
      detail: details.detail,
      amount: amount,
      timeLabel: timeLabel,
      actor: actor,
      actorIsEmployee: isEmployee,
    );
  }

  /// Compact action summary for the row's sub-line.
  ///   label  — short, colored: 'تفعيل نقدي' / 'تفعيل أجل' /
  ///            'تفعيل جزئي' / 'تمديد' / 'تسديد دين' / 'إضافة دين' /
  ///            'إيراد'. Encodes both the operation AND, for
  ///            activations, the payment variant — admin sees the
  ///            cash vs. credit split at a glance without scanning
  ///            descriptions.
  ///   detail — neutral, additional context: package price for
  ///            activations (parsed from action_description), or null
  ///            when there's nothing extra to show.
  static ({String? label, String? detail}) _actionDetails(
    String action,
    String description,
  ) {
    final lower = action.toLowerCase();
    // Activations: parse payment variant + price out of the verbose
    // description. The description shape is:
    //   'تفعيل نقدي - المستخدم: ahmed@x | السعر: 35,000 د.ع'
    //   'تفعيل نقدي جزئي - ... | السعر: 35,000 د.ع | المدفوع: 10,000 د.ع | الدين: 25,000 د.ع'
    //   'تفعيل غير نقدي - ... | السعر: 35,000 د.ع | الدين: 35,000 د.ع'
    final isActivation =
        lower.contains('activ') ||
            (description.contains('تفعيل') &&
                !description.contains('تسديد دين'));
    if (isActivation) {
      final isPartial = description.contains('جزئي');
      final isNonCash = !isPartial && description.contains('غير نقدي');
      final isCash =
          !isPartial && !isNonCash && description.contains('نقدي');
      final variant = isPartial
          ? 'جزئي'
          : isNonCash
              ? 'أجل'
              : isCash
                  ? 'نقدي'
                  : null;
      final label = variant != null ? 'تفعيل $variant' : 'تفعيل';
      final price = _extractAmount(description, RegExp(r'السعر\s*:?\s*([\d,]+)'));
      final paid =
          _extractAmount(description, RegExp(r'المدفوع\s*:?\s*([\d,]+)'));
      // For partial we want both السعر + المدفوع because the cash
      // flow is the latter; for others just the price.
      String? detail;
      if (price != null) {
        detail = '${_formatIntCompact(price)} د.ع';
        if (isPartial && paid != null && paid != price) {
          detail = '$detail · دُفع ${_formatIntCompact(paid)}';
        }
      }
      return (label: label, detail: detail);
    }
    if (lower.contains('extend')) {
      final price = _extractAmount(description, RegExp(r'السعر\s*:?\s*([\d,]+)'));
      return (
        label: 'تمديد',
        detail: price != null ? '${_formatIntCompact(price)} د.ع' : null,
      );
    }
    // مطلب 2026-06-10: add + edit + delete chips on dashboard feed.
    // Order matters — subscriber_edit also contains 'edit'-ish
    // substrings that other rules look for, so we test these specific
    // labels first.
    if (lower.contains('subscriber_add') || lower.contains('add_subscriber')) {
      return (label: 'إضافة مشترك', detail: null);
    }
    if (lower.contains('subscriber_edit') ||
        lower.contains('edit_subscriber')) {
      return (label: 'تعديل مشترك', detail: null);
    }
    if (lower.contains('subscriber_delete') ||
        lower.contains('delete_subscriber')) {
      return (label: 'حذف مشترك', detail: null);
    }
    // مطلب 2026-06-11: شحن/سحب الرصيد للمدير الفرعي كان يتسجّل
    // بـBALANCE_ADD/BALANCE_DEDUCT ويسقط على قاعدة "إضافة دين" /
    // "تسديد دين" المصممة للمشترك. افحص الوصف أولاً — لو يحوي
    // "للمدير" / "من المدير" أعطه label مدير منفصل.
    if (description.contains('للمدير') || description.contains('من المدير')) {
      final isWithdraw = description.contains('سحب') ||
          lower.contains('balance_deduct') ||
          lower.contains('balance_withdraw');
      final amt = _extractAmount(
        description,
        RegExp(r'(?:شحن(?:\s+رصيد\s+\S+)?|سحب(?:\s+رصيد)?)\s+([\d,]+)'),
      );
      return (
        label: isWithdraw ? 'سحب رصيد مدير' : 'شحن رصيد مدير',
        detail: amt != null ? '${_formatIntCompact(amt)} د.ع' : null,
      );
    }
    // Order matters — 'debt_pay' contains 'debt' before 'pay', and
    // 'balance_deduct' contains neither. Check the specific labels
    // before falling through.
    //
    // Backend descriptions for these have the amount right after the
    // Arabic label, e.g. 'تسديد دين 5,000 د.ع للمشترك ahmed@x' or
    // 'إضافة دين 10,000 د.ع للمشترك …'. Parse it out and surface as
    // the detail chip so admins see the cash value in the row
    // without needing the trailing +/- chip.
    if (lower.contains('debt_pay') ||
        lower.contains('balance_deduct') ||
        lower.contains('deduct_balance') ||
        lower.contains('pay_debt')) {
      final amt = _extractAmount(
        description,
        RegExp(r'تسديد\s+دين\s+([\d,]+)'),
      );
      return (
        label: 'تسديد دين',
        detail: amt != null ? '${_formatIntCompact(amt)} د.ع' : null,
      );
    }
    if (lower.contains('balance_add') || lower.contains('add_debt')) {
      final amt = _extractAmount(
        description,
        RegExp(r'إضافة\s+دين\s+([\d,]+)'),
      );
      return (
        label: 'إضافة دين',
        detail: amt != null ? '${_formatIntCompact(amt)} د.ع' : null,
      );
    }
    if (lower.contains('payment_add')) {
      // Generic amount fallback for manual payment-add — the
      // description shape varies, but a leading numeric chunk is
      // common ('PAYMENT_ADD 5,000 …').
      final amt =
          _extractAmount(description, RegExp(r'([\d,]+)\s*د\.ع'));
      return (
        label: 'إيراد',
        detail: amt != null ? '${_formatIntCompact(amt)} د.ع' : null,
      );
    }
    return (label: null, detail: null);
  }

  static int? _extractAmount(String s, RegExp re) {
    final m = re.firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(1)!.replaceAll(',', ''));
  }

  /// 35000 → "35,000". Local mini-formatter — the project-wide
  /// formatIQD is already imported but takes num; this is direct int.
  static String _formatIntCompact(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final n = _normalize();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.lg,
            vertical: Sp.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: n.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(n.icon, color: n.color, size: 18),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Primary line: subscriber name (username) — admin
                    // sees the readable Arabic name first and the
                    // technical username in parentheses for fast cross-
                    // reference with v1's flow. Single line keeps the
                    // row compact; the action type is conveyed by the
                    // tinted icon + the short label below.
                    Text(
                      n.title,
                      style: AppType.label(color: AppColors.textHi).copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (n.subLabel != null) ...[
                          Text(
                            n.subLabel!,
                            style: AppType.muted(color: n.color).copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppColors.textLow,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (n.detail != null) ...[
                          Flexible(
                            child: Text(
                              n.detail!,
                              style: AppType.muted(color: AppColors.textMid)
                                  .copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppColors.textLow,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          n.timeLabel,
                          style: AppType.muted(color: AppColors.textLow)
                              .copyWith(
                                  fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                        if (n.amount != 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: AppColors.textLow,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${n.amount < 0 ? '-' : '+'}${formatIQD(n.amount)} د.ع',
                            style: AppType.label(
                              color: n.amount < 0
                                  ? AppColors.error
                                  : AppColors.brand,
                            ).copyWith(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ],
                    ),
                    // مطلب 2026-06-11: سطر ثالث رفيع 'بواسطة: <اسم>'
                    // يعرض الموظف لو هو الفاعل، أو المدير. يخفى لو
                    // الـbackend ما رجّع لا هذا ولا ذاك (لا يحدث عملياً).
                    if (n.actor != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            n.actorIsEmployee ? Icons.badge : Icons.shield,
                            size: 10,
                            color: n.actorIsEmployee
                                ? const Color(0xFF7C3AED)
                                : AppColors.textMid,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              n.actorIsEmployee
                                  ? 'الموظف: ${n.actor}'
                                  : 'المدير: ${n.actor}',
                              style: AppType.muted(color: AppColors.textMid)
                                  .copyWith(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Maps backend action_type strings to (icon, color).
  static (IconData, Color) _visualForAction(String action) {
    final lower = action.toLowerCase();
    // Order matters — subscriber_edit contains 'edit' (and 'subscrib')
    // so check the specific labels before the generic 'activ' match.
    if (lower.contains('subscriber_add') || lower.contains('add_subscriber')) {
      return (Icons.person_add_rounded, const Color(0xFF8B5CF6));
    }
    if (lower.contains('subscriber_edit') ||
        lower.contains('edit_subscriber')) {
      return (Icons.edit_rounded, const Color(0xFF2D5F47));
    }
    if (lower.contains('subscriber_delete') ||
        lower.contains('delete_subscriber')) {
      return (Icons.delete_rounded, AppColors.error);
    }
    if (lower.contains('activ')) return (Icons.bolt_rounded, AppColors.brand);
    if (lower.contains('extend')) {
      return (Icons.loop_rounded, const Color(0xFF3B82F6));
    }
    if (lower.contains('pay') || lower.contains('debt_pay')) {
      return (Icons.payments_rounded, AppColors.brand);
    }
    if (lower.contains('debt') || lower.contains('add_debt')) {
      return (Icons.account_balance_wallet_rounded, AppColors.error);
    }
    if (lower.contains('whatsapp') || lower.contains('message')) {
      return (Icons.chat_bubble_rounded, const Color(0xFFE08F2D));
    }
    return (Icons.history_rounded, AppColors.textMid);
  }

  static int _readAmount(Map<String, dynamic> m) {
    final raw = m['amount'] ?? m['paid_amount'] ?? m['debt_amount'];
    if (raw == null) return 0;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  static String _humanCreatedAt(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final t = DateTime.tryParse(iso);
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    final days = diff.inDays;
    if (days == 1) return 'قبل يوم';
    return 'قبل $days أيام';
  }
}
