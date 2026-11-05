import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/util/bidi.dart';
import '../models/subscriber.dart';
import '../services/connection_alerts.dart';
import '../services/vpn_now.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'vpn_now_bar.dart' show VpnTag;

/// مشاكل مشتركٍ من قراءته عبر الـVPN بحدود الوكيل (كالخادم: الكيبل، الإشارة وCCQ من جهازه أو سكتره، الضوئيّ والحرارة من الأولت).
List<String> vpnProblemsOf(VpnSubReading r, ConnectionAlertThresholds t) {
  final out = <String>[];
  if (r.lan == 'unplugged') out.add('الكيبل غير مربوط');
  if (r.lan == '10') out.add('الكيبل 10 ميكا');
  final sig = r.sig;
  if (sig != null && sig < 0 && sig < t.signalDbm) out.add('إشارة ${iso('$sig dBm')}');
  final ccq = r.ccq;
  if (ccq != null && ccq > 0 && ccq <= t.ccqPct) out.add('CCQ ${iso('$ccq%')}');
  final rx = r.rx;
  if (rx != null && rx < 0 && rx < t.fiberRxDbm) out.add('ضوئي ${iso('${rx.toStringAsFixed(1)} dBm')}');
  final temp = r.temp;
  if (temp != null && temp > t.fiberTempC) out.add('حرارة ${iso('${temp.round()}°C')}');
  return out;
}

/// «المشاكل» من شريط «وضع VPN» (٦ نوفمبر — المالك: «من انقر ع المشاكل المفروض يعرض المشاكل كبل… يوديني للقسم وليس المشاكل»):
/// المشتركون الذين بقراءتهم مشكلةٌ بآخر فحص — كلٌّ بمشكلته، والنقر يفتحه؛ و«تنبيهات المشتركين» تحتها لمن يريد القسم.
Future<void> showVpnProblemsSheet(
  BuildContext context, {
  required List<Subscriber> subscribers,
  required void Function(Subscriber s) onOpen,
  required VoidCallback onSection,
}) async {
  final t = await ConnectionAlertSettings.ensureLoaded();
  if (!context.mounted) return;
  final byUser = {for (final s in subscribers) s.username.trim().toLowerCase(): s};
  final rows = <({Subscriber? sub, String user, List<String> problems})>[];
  VpnNow.readings.forEach((u, r) {
    final p = vpnProblemsOf(r, t);
    if (p.isNotEmpty) rows.add((sub: byUser[u], user: u, problems: p));
  });
  rows.sort((a, b) => b.problems.length.compareTo(a.problems.length));
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    barrierColor: AppColors.scrim,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.xl))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.sm),
              child: Row(children: [
                Icon(LucideIcons.triangleAlert, size: 18, color: AppColors.warningOnSoft),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(rows.isEmpty ? 'لا مشاكل بآخر فحص' : '${rows.length} بمشكلة بآخر فحص',
                      style: AppType.bodyStrong()),
                ),
                const VpnTag(),
              ]),
            ),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
                child: Text('كلّ المقروئين بحدودك سليمون', style: AppType.muted()),
              )
            else
              Flexible(
                child: ListView.separated(
                  key: const ValueKey('vpn-problems-list'),
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md),
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.borderSoft),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final name = r.sub?.fullName.trim().isNotEmpty == true ? r.sub!.fullName.trim() : r.user;
                    return Material(
                      type: MaterialType.transparency,
                      child: InkWell(
                        onTap: r.sub == null
                            ? null
                            : () {
                                Navigator.of(ctx).pop();
                                onOpen(r.sub!);
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm + 2),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: AppType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text(iso(r.user), style: AppType.micro(color: AppColors.textMid)),
                              const SizedBox(height: Sp.xs),
                              Wrap(spacing: Sp.xs, runSpacing: Sp.xs, children: [
                                for (final p in r.problems)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.dangerSoftBg,
                                      borderRadius: BorderRadius.circular(R.pill),
                                      border: Border.all(color: AppColors.dangerSoftBorder),
                                    ),
                                    child: Text(p, style: AppType.micro(color: AppColors.dangerOnSoft).copyWith(fontWeight: FontWeight.w700)),
                                  ),
                              ]),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.md),
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  onSection();
                },
                icon: const Icon(LucideIcons.bellRing, size: 16),
                label: const Text('تنبيهات المشتركين'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
