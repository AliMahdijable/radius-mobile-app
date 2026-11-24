import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/balance_requests_api.dart';
import '../../core/util/ar_date.dart';
import '../../core/util/format.dart';
import '../../core/util/server_time.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «طلب رصيد من مديرك» — قطعٌ مشتركة بين شاشة الفرعيّ («طلباتك») وشاشة الأعلى («طلبات الرصيد»).

/// «2026/11/24 · 9:40 مساءً» — الساعة و«مساءً» بمسافةٍ لا تنكسر (لا تنزل «مساءً» وحدها لسطر بصفوف التفاصيل الضيّقة).
String balanceReqWhen(DateTime? d) => d == null ? '—' : '${iqDateOf(d)} · ${clock12Ar(d).replaceFirst(' ', '\u00a0')}';

String balanceReqIqd(num v) => '${formatIQD(v)} د.ع';

/// رصيدٌ قد يكون سالباً (مديرٌ يعمل بالآجل) — بإشارته، والسالب معزولٌ LTR فيبقى الناقص يسار الرقم داخل السطر العربيّ (كالموقع
/// formatIQDSigned). [balanceReqIqd] يُسقط الإشارة: كان رصيدٌ سالب يظهر كأنّه موجود (٢٤ نوفمبر).
String balanceReqIqdSigned(num v) => v.round() < 0 ? '\u2066${formatIQDSigned(v.round())}\u2069 د.ع' : balanceReqIqd(v);

/// حال الطلب: [forParent] = كما يراه الأعلى («بانتظارك»)، وإلّا كما يراه صاحبه («بانتظار مديرك»).
({String label, AppTone tone, IconData icon}) balanceReqStatus(BalanceRequest r, {bool forParent = false}) => switch (r.status) {
      'pending' => (label: forParent ? 'بانتظارك' : 'بانتظار مديرك', tone: AppTone.warning, icon: LucideIcons.hourglass),
      'processing' => (label: r.unverified ? 'قيد التأكّد' : 'قيد الشحن', tone: AppTone.info, icon: LucideIcons.loader),
      'done' => (label: 'شُحن', tone: AppTone.success, icon: LucideIcons.circleCheck),
      'rejected' => (label: 'مرفوض', tone: AppTone.danger, icon: LucideIcons.circleX),
      'cancelled' => (label: 'أُلغي', tone: AppTone.neutral, icon: LucideIcons.ban),
      'expired' => (label: 'انتهى بلا ردّ', tone: AppTone.neutral, icon: LucideIcons.clock),
      _ => (label: r.status, tone: AppTone.neutral, icon: LucideIcons.circle),
    };

IconData balanceReqMethodIcon(String method) => switch (method) {
      'zaincash' => LucideIcons.smartphone,
      'master' => LucideIcons.creditCard,
      'other' => LucideIcons.landmark,
      'cash' => LucideIcons.banknote,
      'loan' => LucideIcons.hourglass,
      _ => LucideIcons.wallet,
    };

AppTone balanceReqMethodTone(String method) => switch (method) {
      'zaincash' || 'master' || 'other' => AppTone.info,
      'cash' => AppTone.success,
      'loan' => AppTone.warning,
      _ => AppTone.neutral,
    };

class BalanceReqStatusChip extends StatelessWidget {
  const BalanceReqStatusChip(this.request, {super.key, this.forParent = false});
  final BalanceRequest request;
  final bool forParent;

  @override
  Widget build(BuildContext context) {
    final s = balanceReqStatus(request, forParent: forParent);
    return ToneChip(key: ValueKey('balreq-status-${request.id}'), label: s.label, tone: s.tone, icon: s.icon, dense: true);
  }
}

class BalanceReqMethodChip extends StatelessWidget {
  const BalanceReqMethodChip(this.request, {super.key});
  final BalanceRequest request;

  @override
  Widget build(BuildContext context) => ToneChip(
        label: request.methodLabel.isEmpty ? request.payMethod : request.methodLabel,
        tone: balanceReqMethodTone(request.payMethod),
        icon: balanceReqMethodIcon(request.payMethod),
        dense: true,
      );
}

/// بطاقةٌ بإطارٍ هادئ كبطاقات «قوائم أخرى».
class BalanceReqCard extends StatelessWidget {
  const BalanceReqCard({super.key, required this.child, this.padding = const EdgeInsets.all(Sp.lg), this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(R.card), onTap: onTap, child: box),
    );
  }
}

/// سطرٌ بأيقونةٍ ملوّنة ونصٍّ يلتفّ (لا يُقصّ) — للتنبيهات تحت الطلب.
class BalanceReqHint extends StatelessWidget {
  const BalanceReqHint({super.key, required this.icon, required this.text, this.tone = AppTone.neutral});
  final IconData icon;
  final String text;
  final AppTone tone;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: tone.fill)),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(text, style: AppType.body(color: tone == AppTone.neutral ? AppColors.textMid : tone.fill).copyWith(fontSize: 12.5))),
        ],
      );
}
