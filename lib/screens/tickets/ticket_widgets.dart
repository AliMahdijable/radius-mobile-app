import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/tickets_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/server_time.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'ticket_thread_screen.dart';
import 'tickets_screen.dart';

/// «التذاكر» (المالك ٩ نوفمبر): ألوان الحالة ونصوصها، صفّ التذكرة في القائمة، ونقر إشعارها.

({String label, Color fg, Color bg, IconData icon}) ticketStatusMeta(String status) => switch (status) {
      'open' => (label: 'بانتظارك', fg: AppColors.warningOnSoft, bg: AppColors.warningSoftBg, icon: LucideIcons.hourglass),
      'answered' => (label: 'تمّ الردّ', fg: AppColors.info, bg: AppColors.infoSoftBg, icon: LucideIcons.messageSquareText),
      'in_progress' => (label: 'قيد المعالجة', fg: AppColors.brand, bg: AppColors.brandSoftBg, icon: LucideIcons.wrench),
      'resolved' => (label: 'تمّ الحلّ', fg: AppColors.success, bg: AppColors.successSoftBg, icon: LucideIcons.circleCheck),
      'closed' => (label: 'مغلقة', fg: AppColors.textMid, bg: AppColors.surfaceSunken, icon: LucideIcons.archive),
      'cancelled' => (label: 'ألغاها المشترك', fg: AppColors.textMid, bg: AppColors.surfaceSunken, icon: LucideIcons.x),
      _ => (label: status, fg: AppColors.textMid, bg: AppColors.surfaceSunken, icon: LucideIcons.ticket),
    };

/// سطر الحدث في المحادثة («قيد المعالجة» …).
String ticketEventLabel(String? event) => switch (event) {
      'in_progress' => 'صارت قيد المعالجة',
      'resolved' => 'تمّ الحلّ',
      'closed' => 'أُغلقت التذكرة',
      'reopened' => 'أُعيد فتحها',
      'cancelled' => 'ألغاها المشترك',
      _ => 'تغيّرت الحالة',
    };

/// زرّ الحالة كما يضبطه الوكيل.
String ticketActionLabel(String action) => switch (action) {
      'in_progress' => 'قيد المعالجة',
      'resolved' => 'تمّ الحلّ',
      'closed' => 'إغلاق',
      _ => action,
    };

String filterLabel(TicketFilter f) => switch (f) {
      TicketFilter.open => 'بانتظارك',
      TicketFilter.answered => 'تمّ الردّ',
      TicketFilter.closed => 'المنتهية',
      TicketFilter.all => 'الكلّ',
    };

String _initials(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).take(2).map((x) => x.characters.first).join();
  return w.isEmpty ? '؟' : w;
}

class TicketStatusChip extends StatelessWidget {
  const TicketStatusChip({super.key, required this.status, this.moved = false});
  final String status;

  /// انتقل المشترك لوكيلٍ آخر — للقراءة وحدها.
  final bool moved;

  @override
  Widget build(BuildContext context) {
    final m = moved
        ? (label: 'انتقل المشترك', fg: AppColors.textMid, bg: AppColors.surfaceSunken, icon: LucideIcons.arrowRightLeft)
        : ticketStatusMeta(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
      decoration: BoxDecoration(color: m.bg, borderRadius: BorderRadius.circular(R.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(m.icon, size: 12, color: m.fg),
        const SizedBox(width: 4),
        Text(m.label, style: AppType.micro(color: m.fg).copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// صفٌّ مختصر في القائمة: المشترك، الحالة، النوع ومعاينة آخر رسالة، والوقت. غير المقروءة بإطارٍ ونقطة.
class TicketTile extends StatelessWidget {
  const TicketTile({super.key, required this.ticket, required this.onTap});
  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final t = ticket;
    final m = ticketStatusMeta(t.status);
    final who = t.lastAuthor == null || t.lastAuthor == 'subscriber' ? '' : 'أنت: ';
    final preview = '$who${t.lastPreview ?? ''}'.trim();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        key: ValueKey('ticket-tile-${t.id}'),
        borderRadius: BorderRadius.circular(R.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: t.unread ? AppColors.warningSoftBorder : AppColors.border),
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: m.bg, shape: BoxShape.circle),
              child: Text(_initials(t.subscriber.title), style: AppType.bodyBold(color: m.fg).copyWith(fontSize: 13)),
            ),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (t.unread) ...[
                    Container(
                      key: ValueKey('ticket-unread-${t.id}'),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: AppColors.warning, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(t.subscriber.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.unread ? AppType.bodyBold(color: AppColors.textHi) : AppType.bodyStrong(color: AppColors.textHi)),
                  ),
                  const SizedBox(width: Sp.sm),
                  TicketStatusChip(status: t.status, moved: t.moved),
                ]),
                const SizedBox(height: 2),
                Text(isoJoin([ticketCategoryLabel(t.category), if ((t.subject ?? '').isNotEmpty) t.subject!], ' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
                if (preview.isNotEmpty)
                  Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
                if (t.lastActivityAt != null) Text(timeAgoAr(t.lastActivityAt), style: AppType.micro(color: AppColors.textLow)),
              ]),
            ),
            const SizedBox(width: Sp.xs),
            Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
          ]),
        ),
      ),
    );
  }
}

/// نقر إشعار تذكرة (FCM أو الحاسبة أو صندوق الإشعارات) ⇒ المحادثة نفسها؛ غيره false. القسم مقفلٌ/غير متاح ⇒ القائمة تقول السبب.
Future<bool> openTicketPush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'portal_ticket') return false;
  final id = int.tryParse(data['ticket_id'] ?? '');
  await TicketsState.ensureFresh(force: true);
  if (!nav.mounted) return true;
  if (id != null && TicketsState.on) {
    await nav.push(MaterialPageRoute(builder: (_) => TicketThreadScreen(ticketId: id)));
  } else {
    await nav.push(MaterialPageRoute(builder: (_) => TicketsScreen.mergedPage()));
  }
  return true;
}
