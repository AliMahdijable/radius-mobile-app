import 'package:flutter/material.dart';
import '../../../core/util/server_time.dart';

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
    AppTone tone,
    String title,
    // مطلب المستخدم 2026-07-12: نمرّر الاسم واليوزر منفصلين للـUI حتى
    // يمنح كل واحد لون منفصل (name = brand، username = رمادي). الـ
    // title القديم يبقى للحالات اللي فيها اسم واحد فقط (fallback).
    String? subscriberFullName,
    String? subscriberUsername,
    String? subLabel,
    String? detail,
    int amount,
    String timeLabel,
    String? actor,
    bool actorIsEmployee,
  }) _normalize() {
    final m = item;
    final action = (m['action'] ?? m['action_type'] ?? '').toString();
    final descr =
        (m['action_description'] ?? m['description'] ?? '').toString();
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
      tone: visual.$2,
      title: title,
      // نمرّر السـtwo parts منفصلتين لتلوينهما بشكل مستقل في الـUI.
      subscriberFullName: fullName.isEmpty ? null : fullName,
      subscriberUsername: username.isEmpty ? null : username,
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
    final isActivation = lower.contains('activ') ||
        (description.contains('تفعيل') && !description.contains('تسديد دين'));
    if (isActivation) {
      final isPartial = description.contains('جزئي');
      final isNonCash = !isPartial && description.contains('غير نقدي');
      final isCash = !isPartial && !isNonCash && description.contains('نقدي');
      final variant = isPartial
          ? 'جزئي'
          : isNonCash
              ? 'أجل'
              : isCash
                  ? 'نقدي'
                  : null;
      final label = variant != null ? 'تفعيل $variant' : 'تفعيل';
      final price =
          _extractAmount(description, RegExp(r'السعر\s*:?\s*([\d,]+)'));
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
      final price =
          _extractAmount(description, RegExp(r'السعر\s*:?\s*([\d,]+)'));
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
    // 2026-08-26: موقع GPS — SUBSCRIBER_EDIT + description يحوي "موقع GPS".
    // نُميّزها قبل قاعدة "تعديل مشترك" العامّة حتى تظهر بلابل واضح للأدمن.
    if ((lower.contains('subscriber_edit') ||
            lower.contains('edit_subscriber')) &&
        description.contains('موقع GPS')) {
      final isClear = description.contains('حذف موقع');
      return (label: 'تعديل', detail: isClear ? 'حذف موقع' : 'إضافة موقع');
    }
    if (lower.contains('subscriber_edit') ||
        lower.contains('edit_subscriber')) {
      return (label: 'تعديل مشترك', detail: null);
    }
    if (lower.contains('subscriber_delete') ||
        lower.contains('delete_subscriber')) {
      return (label: 'حذف مشترك', detail: null);
    }
    // مطلب 2026-06-11: حركات المدراء (شحن/سحب/تسديد/نقاط) كانت
    // تسقط على قواعد المشترك العامة ("إضافة دين" / "تسديد دين") لأن
    // الـaction_type نفسه (BALANCE_ADD / BALANCE_DEDUCT / DEBT_PAY)
    // مشترك. نفحص الوصف أولاً — لو يحوي أي إشارة للمدير، أعطه label
    // منفصل + استخرج المبلغ من الشكل العام "X د.ع".
    final isManagerOp = description.contains('للمدير') ||
        description.contains('من المدير') ||
        description.contains('دين المدير');
    if (isManagerOp) {
      // مطلب 2026-06-11: تسديد دين المدير. الوصف من الباك:
      //   "تسديد X د.ع من دين المدير Y"
      if (description.contains('تسديد') && description.contains('دين المدير')) {
        final amt = _extractAmount(
          description,
          RegExp(r'تسديد\s+([\d,]+)\s*د\.?ع'),
        );
        return (
          label: 'تسديد دين مدير',
          detail: amt != null ? '${_formatIntCompact(amt)} د.ع' : null,
        );
      }
      // مطلب 2026-06-11: نقاط مكافأة. الوصف من الباك:
      //   "إضافة N نقطة للمدير Y"
      if (description.contains('نقطة للمدير') || lower.contains('points')) {
        final amt = _extractAmount(
          description,
          RegExp(r'إضافة\s+([\d,]+)\s+نقطة'),
        );
        return (
          label: 'نقاط مدير',
          detail: amt != null ? '${_formatIntCompact(amt)} نقطة' : null,
        );
      }
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
      final amt = _extractAmount(description, RegExp(r'([\d,]+)\s*د\.ع'));
      return (
        label: 'إيراد',
        detail: amt != null ? '${_formatIntCompact(amt)} د.ع' : null,
      );
    }
    // مطلب المستخدم 2026-07-12: تشغيل/تعطيل/فصل حساب المشترك ما كانت
    // تظهر بـلابل في feed آخر الحركات — تُعرض بدون action label.
    if (lower.contains('subscriber_enable') ||
        lower.contains('enable_subscriber')) {
      return (label: 'تشغيل', detail: null);
    }
    if (lower.contains('subscriber_disable') ||
        lower.contains('disable_subscriber')) {
      return (label: 'تعطيل', detail: null);
    }
    if (lower.contains('subscriber_disconnect') ||
        lower.contains('disconnect_subscriber')) {
      return (label: 'فصل المستخدم', detail: null);
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
                  color: n.tone.softBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Icon(n.icon, color: n.tone.fill, size: 18),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Primary line: subscriber name (username).
                    // مطلب المستخدم 2026-07-12: الاسم العربي بلون brand
                    // مميّز، اليوزر رمادي. Text.rich تفصل التلوين مع
                    // الحفاظ على السطر الواحد. لو ما فيه اسم عربي،
                    // نعرض title الأصلي بلون textHi (يجي username صرف
                    // أو fallback لـaction).
                    if (n.subscriberFullName != null &&
                        n.subscriberFullName!.isNotEmpty)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: n.subscriberFullName!,
                              style: TextStyle(
                                color: AppColors.isDark
                                    ? AppColors.brandLight
                                    : AppColors.brand,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.3,
                                letterSpacing: -0.1,
                              ),
                            ),
                            if (n.subscriberUsername != null &&
                                n.subscriberUsername!.isNotEmpty)
                              TextSpan(
                                text: '  (${n.subscriberUsername})',
                                style: TextStyle(
                                  color: AppColors.textLow,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  height: 1.3,
                                ),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
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
                            style: AppType.muted(color: n.tone.fill).copyWith(
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
                            ).copyWith(
                                fontSize: 12.5, fontWeight: FontWeight.w700),
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
                                ? AppColors.brandAccent
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
  /// أيقونة الحركة ونغمتها.
  ///
  /// كانت تُرجع `(IconData, Color)` فيشتقّ المستدعي الخلفيّة بـ
  /// `color.withValues(alpha: .1)` — وهذا ما ينهار ليلاً. الآن تُرجع
  /// [AppTone] فتأتي التعبئة والخلفيّة والحدّ من اللوحة معاً.
  static (IconData, AppTone) _visualForAction(String action) {
    final lower = action.toLowerCase();
    // الترتيب مهمّ — `subscriber_edit` يحوي 'edit' و'subscrib' معاً،
    // فالتسميات المحدّدة تُفحص قبل المطابقة العامّة لـ'activ'.
    if (lower.contains('subscriber_add') || lower.contains('add_subscriber')) {
      return (Icons.person_add_rounded, AppTone.brand);
    }
    if (lower.contains('subscriber_edit') ||
        lower.contains('edit_subscriber')) {
      return (Icons.edit_rounded, AppTone.brand);
    }
    if (lower.contains('subscriber_delete') ||
        lower.contains('delete_subscriber')) {
      return (Icons.delete_rounded, AppTone.danger);
    }
    if (lower.contains('activ')) return (Icons.bolt_rounded, AppTone.brand);
    if (lower.contains('extend')) {
      return (Icons.loop_rounded, AppTone.brand);
    }
    if (lower.contains('pay') || lower.contains('debt_pay')) {
      return (Icons.payments_rounded, AppTone.success);
    }
    if (lower.contains('debt') || lower.contains('add_debt')) {
      return (Icons.account_balance_wallet_rounded, AppTone.danger);
    }
    if (lower.contains('whatsapp') || lower.contains('message')) {
      return (Icons.chat_bubble_rounded, AppTone.warning);
    }
    // 2026-07-12: تشغيل/تعطيل/فصل — أيقونات ونغمات مميّزة.
    if (lower.contains('subscriber_enable') ||
        lower.contains('enable_subscriber')) {
      return (Icons.check_circle_rounded, AppTone.success);
    }
    if (lower.contains('subscriber_disable') ||
        lower.contains('disable_subscriber')) {
      return (Icons.block_rounded, AppTone.warning);
    }
    if (lower.contains('subscriber_disconnect') ||
        lower.contains('disconnect_subscriber')) {
      return (Icons.power_settings_new_rounded, AppTone.danger);
    }
    return (Icons.history_rounded, AppTone.neutral);
  }

  static int _readAmount(Map<String, dynamic> m) {
    final raw = m['amount'] ?? m['paid_amount'] ?? m['debt_amount'];
    if (raw == null) return 0;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  static String _humanCreatedAt(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    // `created_at` من `activity_logs` — جدولُنا.
    //
    // ⚠️ **لم يكن معطوباً**: الاستعمال هنا `difference` وهي تقارن
    // لحظاتٍ مطلقة بلا نظرٍ إلى `isUtc`. التبديل توحيدٌ للمدخل.
    final t = parseServerUtc(iso);
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
