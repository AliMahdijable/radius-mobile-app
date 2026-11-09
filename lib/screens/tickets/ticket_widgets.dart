import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/tickets_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/util/server_time.dart';
import '../../services/merged_mode.dart';
import '../../services/permissions_service.dart';
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
  const TicketTile({super.key, required this.ticket, required this.onTap, this.compact = false});
  final Ticket ticket;
  final VoidCallback onTap;

  /// الجرس: ثلاثة أسطر لا أربعة — المعاينة (أو النوع حين لا معاينة) ثمّ النوع مع الوقت في سطرٍ واحد.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final t = ticket;
    final m = ticketStatusMeta(t.status);
    final who = t.lastAuthor == null || t.lastAuthor == 'subscriber' ? '' : 'أنت: ';
    final preview = '$who${t.lastPreview ?? ''}'.trim();
    final kind = isoJoin([ticketCategoryLabel(t.category), if ((t.subject ?? '').isNotEmpty) t.subject!], ' · ');
    final when = timeAgoAr(t.lastActivityAt);
    final lines = compact
        ? <Widget>[
            Text(preview.isNotEmpty ? preview : kind,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
            if (preview.isNotEmpty || when.isNotEmpty)
              Text(isoJoin([if (preview.isNotEmpty) ticketCategoryLabel(t.category), when], ' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textLow)),
          ]
        : <Widget>[
            Text(kind, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
            if (preview.isNotEmpty)
              Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
            if (t.lastActivityAt != null) Text(when, style: AppType.micro(color: AppColors.textLow)),
          ];
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
                ...lines,
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
/// الإشعار لشركته المفتوحة (الموجِّه يبدّل لها أوّلاً — CompanyPush) ⇒ المحادثة لها صراحةً ولو كانت تحتها صفحةٌ موجَّهة لغيرها.
Future<bool> openTicketPush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'portal_ticket') return false;
  final id = int.tryParse(data['ticket_id'] ?? '');
  await TicketsState.ensureForPush();
  if (!nav.mounted) return true;
  if (id != null && TicketsState.on) {
    await nav.push(MaterialPageRoute(builder: (_) => TicketThreadScreen(ticketId: id, openCompany: true)));
  } else {
    // القائمة للمفتوحة كذلك — لا لمختارة الشريط ([MergedMode.focusOpenCompany])
    await MergedMode.focusOpenCompany();
    if (!nav.mounted) return true;
    await nav.push(MaterialPageRoute(builder: (_) => TicketsScreen.mergedPage()));
  }
  return true;
}

/// قسم «تذاكر المشتركين» في الجرس (٩ نوفمبر — المالك: «نعم» للتذاكر بالجرس مثل طلبات التفعيل؛ كجرس الويب 2e6f9a4): ما ينتظر عملاً
/// — غير المقروءة أوّلاً ثمّ «بانتظارك» — بأحدث [TicketsState.bellMax] منها (الاسم والمعاينة والوقت)، والنقر يفتح المحادثة نفسها،
/// و«الكلّ» قسم التذاكر. يظهر حين يوجد ما ينتظر وحده (كطلبات التجديد)، ولمن يرى القسم وحده ([TicketsState.inBell]: لا موظّفٌ بلا
/// «التذاكر — العرض» ولا مقيَّدٌ بمديرٍ فرعيّ). للشركة المفتوحة دائماً — بـ«كل الشركات» لا تُخلط بغيرها (القراءة والمحادثة
/// بـ[CompanyRoute.runOpen]).
class TicketInboxSection extends StatelessWidget {
  const TicketInboxSection({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([TicketsState.gate, TicketsState.bell, PermissionsService.changes]),
      builder: (context, _) {
        Theme.of(context); // theme-dep (dark-mode)
        final b = TicketsState.bell.value;
        if (!TicketsState.inBell || b.items.isEmpty) return const SizedBox.shrink();
        final count = TicketsState.bellBadge;
        final more = TicketsState.bellWaiting - b.items.length;
        return Column(
          key: const ValueKey('tickets-inbox'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.sm),
              child: Row(children: [
                Icon(LucideIcons.ticket, size: 18, color: AppColors.info),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Row(children: [
                    Flexible(
                      child: Text('تذاكر المشتركين',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyBold(color: AppColors.textHi)),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: Sp.sm),
                      Semantics(
                        label: ticketsBadgeLabel(count, TicketsState.badgeRule),
                        excludeSemantics: true,
                        child: Container(
                          key: const ValueKey('tickets-inbox-count'),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(color: AppColors.warningSoftBg, borderRadius: BorderRadius.circular(R.pill)),
                          child: Text('$count', style: AppType.microBold(color: AppColors.warningOnSoft)),
                        ),
                      ),
                    ],
                  ]),
                ),
                TextButton(
                  key: const ValueKey('tickets-inbox-all'),
                  onPressed: () => _openAllTickets(context),
                  child: const Text('الكلّ'),
                ),
              ]),
            ),
            for (final t in b.items) ...[
              TicketTile(ticket: t, compact: true, onTap: () => _openBellTicket(context, t)),
              const SizedBox(height: Sp.sm),
            ],
            if (more > 0)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const ValueKey('tickets-inbox-more'),
                  onPressed: () => _openAllTickets(context),
                  child: Text('و$more غيرها…'),
                ),
              ),
            const SizedBox(height: Sp.md),
          ],
        );
      },
    );
  }
}

/// قارئ الشاشة لرقم رأس القسم — بالقاعدة نفسها ([kTicketsBadgeRule]: الآن كلّ ما ينتظرك)، والعدد بتمييزه العربيّ (٣ تذاكر · ١١ تذكرة).
String ticketsBadgeLabel(int n, [TicketsBadgeRule rule = kTicketsBadgeRule]) {
  final many = arCount(n, one: 'تذكرة', two: 'تذكرتان', few: 'تذاكر', many: 'تذكرة');
  return switch (rule) {
    TicketsBadgeRule.unread => switch (n) {
        1 => 'تذكرةٌ فيها جديدٌ لم تقرأه',
        2 => 'تذكرتان فيهما جديدٌ لم تقرأه',
        _ => '$many فيها جديدٌ لم تقرأه',
      },
    TicketsBadgeRule.waiting => switch (n) {
        1 => 'تذكرةٌ بانتظارك',
        2 => 'تذكرتان بانتظارك',
        _ => '$many بانتظارك',
      },
  };
}

/// من الجرس: المحادثة لشركتها المفتوحة صراحةً، وبعد الرجوع يُقرأ الجرس ثانيةً (ردٌّ أو حالةٌ أخرجتها من «بانتظارك»).
Future<void> _openBellTicket(BuildContext context, Ticket t) async {
  await Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => TicketThreadScreen(ticketId: t.id, initial: t, openCompany: true),
  ));
  unawaited(TicketsState.ensureFresh(force: true));
}

/// «الكلّ»: قسم التذاكر بغلافه («كل الشركات» — لا يُفتح قسمٌ خاماً) — للشركة المفتوحة التي يعرض الجرس تذاكرها
/// ([MergedMode.focusOpenCompany]، ٩ نوفمبر) لا لمختارة الشريط.
void _openAllTickets(BuildContext context) {
  final nav = Navigator.of(context);
  unawaited(() async {
    await MergedMode.focusOpenCompany();
    if (!nav.mounted) return;
    await nav.push(MaterialPageRoute(builder: (_) => TicketsScreen.mergedPage()));
  }());
}
