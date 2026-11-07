import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/util/bidi.dart';
import '../models/subscriber.dart';
import '../services/connection_alerts.dart';
import '../services/vpn_now.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'company_tag.dart';
import 'vpn_now_bar.dart' show VpnTag;

/// مشاكل مشتركٍ من قراءته عبر الـVPN بحدود الوكيل (كالخادم: الكيبل، الإشارة وCCQ من جهازه أو سكتره، الضوئيّ والحرارة من الأولت).
/// أين صار المشترك بـ«تنبيهات المشتركين» — بأسماء تبويباتها (الخادم agentRoutes.STATE_WORDS بالصيغ نفسها).
const vpnCaseWords = <String, (String, String)>{
  'pending': ('بانتظار موافقتك', 'بانتظار موافقتك'),
  'queued': ('بالطابور', 'بالطابور'),
  'watching': ('تحت المراقبة', 'تحت المراقبة'),
  'sent': ('وصله التنبيه', 'وصلهم التنبيه'),
  'skipped': ('تجاهلته', 'تجاهلتهم'),
  'muted': ('أوقفت تنبيهه', 'أوقفت تنبيههم'),
  'other': ('خارج المتابعة', 'خارج المتابعة'),
};

/// «3 تحت المراقبة · 3 وصلهم التنبيه» من وسوم الصفوف؛ null بلا وسوم (خادمٌ أقدم أو ظلّ).
String? vpnCasesText(Iterable<String?> states) {
  final n = <String, int>{};
  for (final s in states) {
    if (s != null && vpnCaseWords.containsKey(s)) n[s] = (n[s] ?? 0) + 1;
  }
  final parts = [
    for (final e in vpnCaseWords.entries)
      if ((n[e.key] ?? 0) > 0) '${n[e.key]} ${n[e.key] == 1 ? e.value.$1 : e.value.$2}',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

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
  final rows = <({Subscriber? sub, String user, String? company, List<String> problems, String? state})>[];
  // «كل الشركات» (صفوفٌ بشركاتها): قراءات كلّ شركةٍ من فحصها وبحدود تنبيهها، والصفّ يطابق بشركته ويوزره معاً
  if (subscribers.any((s) => s.companyKey != null)) {
    final byKey = {
      for (final s in subscribers)
        if (s.companyKey != null) '${s.companyKey}|${s.username.trim().toLowerCase()}': s,
    };
    VpnNow.companyReadings.forEach((company, readings) {
      final lim = VpnNow.limitsOf(company) ?? t;
      readings.forEach((u, r) {
        final p = vpnProblemsOf(r, lim);
        if (p.isNotEmpty) rows.add((sub: byKey['$company|$u'], user: u, company: company, problems: p, state: r.state));
      });
    });
  } else {
    final byUser = {for (final s in subscribers) s.username.trim().toLowerCase(): s};
    VpnNow.readings.forEach((u, r) {
      final p = vpnProblemsOf(r, t);
      if (p.isNotEmpty) rows.add((sub: byUser[u], user: u, company: null, problems: p, state: r.state));
    });
  }
  final where = vpnCasesText(rows.map((r) => r.state));
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
                  child: Text(rows.isEmpty ? 'لا مشاكل بآخر فحص' : '${rows.length} بمشكلة بآخر فحص${where == null ? '' : ': $where'}',
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
                              if (r.company != null) ...[
                                const SizedBox(height: 2),
                                CompanyTag(companyKey: r.company!),
                              ],
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
                                // أين صار بـ«تنبيهات المشتركين» (تحت المراقبة/وصله التنبيه/…)
                                if (vpnCaseWords[r.state] case final w?)
                                  Container(
                                    key: ValueKey('vpn-case-${r.user}'),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.infoSoftBg,
                                      borderRadius: BorderRadius.circular(R.pill),
                                      border: Border.all(color: AppColors.infoSoftBorder),
                                    ),
                                    child: Text(w.$1, style: AppType.micro(color: AppColors.info).copyWith(fontWeight: FontWeight.w700)),
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
