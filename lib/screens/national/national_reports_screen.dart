import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_more_api.dart';
import '../../core/util/bidi.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'national_more_widgets.dart';
import 'national_widgets.dart';

/// «تقارير البوّابة» — المشروع الوطنيّ (١ نوفمبر، «البيانات ← التقارير» في البوّابة): «المشتركون حسب الزون» (فعّال ومنتهٍ وموقوف
/// لكلّ زون — من قائمة مشتركينا المكاشة بالخادم، بلا نداءٍ للبوّابة) و«تقرير الجلسات» (المتّصلون وغير المتّصلين لكلّ زون — من
/// البوّابة). كلّ تقريرٍ وحده: أرقامه، أو قفلٌ بسببه حين لا تعطيه البوّابة لمستخدمك (أو لا يملك الموظّف مفتاحه)، أو «جارٍ»، أو
/// تعذّر — وما لا يُعرف «—» لا صفر. الخادم `/api/v2/ftth/reports/zones` و`/reports/sessions` (العقد §7).
class NationalReportsScreen extends StatefulWidget {
  const NationalReportsScreen({super.key});

  @override
  State<NationalReportsScreen> createState() => _NationalReportsScreenState();
}

/// حال تقريرٍ واحد على الشاشة.
class _Part {
  NationalReport? data;
  NationalMoreResult<Object?>? locked;
  String? error;
  bool loading = false;
  Timer? poll;
  int polls = 0;
  int gen = 0;
}

class _NationalReportsScreenState extends State<NationalReportsScreen> {
  final _zones = _Part();
  final _sessions = _Part();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _zones.poll?.cancel();
    _sessions.poll?.cancel();
    super.dispose();
  }

  /// مفتاح التقرير يقفله على الموظّف وحده (العقد §9) — صاحب الحساب لا: قدراته من الخادم تجعل reports.sessions false لتقرير جلسات الساس
  /// العامّ (لا يخدمه حساب شركةٍ مُضافة) لا لتقرير البوّابة هذا (مراجعة ١ نوفمبر: كان «تقرير الجلسات» يقول للمالك «اطلبها من مديرك»).
  static bool _allowed(String key) => !Perms.isEmployee || Perms.has(key);

  Future<void> _loadAll() => Future.wait([
        if (_allowed(NationalPerms.zonesReport)) _load(_zones, NationalMoreApi.zonesReport),
        if (_allowed(NationalPerms.sessionsReport)) _load(_sessions, NationalMoreApi.sessionsReport),
      ]);

  /// تقريرٌ واحد، وإعادة السؤال كلّ ٤ث ما دام «جارٍ» (حتى دقيقة) — وردٌّ قديمٌ لسؤالٍ سابق يُهمل.
  Future<void> _load(_Part p, Future<NationalMoreResult<NationalReport>> Function() fetch, {bool again = false}) async {
    p.poll?.cancel();
    if (!again) p.polls = 0;
    final gen = ++p.gen;
    setState(() => p.loading = true);
    final r = await fetch();
    if (!mounted || gen != p.gen) return;
    setState(() {
      p.loading = false;
      if (r.ok) {
        if (!r.data!.pending || p.data == null) p.data = r.data;
        p.error = null;
        p.locked = null;
      } else if (r.locked) {
        p.locked = r;
      } else {
        p.error = r.error;
      }
    });
    if (r.ok && r.data!.pending && p.polls++ < 15) {
      p.poll = Timer(const Duration(seconds: 4), () {
        if (mounted && gen == p.gen) _load(p, fetch, again: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text('تقارير البوّابة', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              _ReportCard(
                title: 'المشتركون حسب الزون',
                icon: LucideIcons.users,
                part: _zones,
                noPerm: !_allowed(NationalPerms.zonesReport),
                onRetry: () => _load(_zones, NationalMoreApi.zonesReport),
                kpis: const [
                  (key: 'active', label: 'فعّال', tone: AppTone.success),
                  (key: 'expired', label: 'منتهي', tone: AppTone.warning),
                  (key: 'total', label: 'المجموع', tone: AppTone.neutral),
                ],
                row: (z) => (a: z.active, b: z.expired, extra: (z.suspended ?? 0) > 0 ? 'موقوف ${nationalCount(z.suspended)}' : null),
                aLabel: 'فعّال',
                bLabel: 'منتهي',
                note: (r) => [
                  if ((r.total('suspended') ?? 0) > 0) 'منهم موقوف: ${nationalCount(r.total('suspended'))}',
                  if (r.partial) 'من جزءٍ من القائمة (حسابٌ كبير)',
                ].join(' · '),
              ),
              const SizedBox(height: Sp.md),
              _ReportCard(
                title: 'تقرير الجلسات',
                icon: LucideIcons.activity,
                part: _sessions,
                noPerm: !_allowed(NationalPerms.sessionsReport),
                onRetry: () => _load(_sessions, NationalMoreApi.sessionsReport),
                kpis: const [
                  (key: 'online', label: 'متّصل', tone: AppTone.success),
                  (key: 'offline', label: 'غير متّصل', tone: AppTone.neutral),
                  (key: 'total', label: 'المجموع', tone: AppTone.neutral),
                ],
                row: (z) => (a: z.online, b: z.offline, extra: null),
                aLabel: 'متّصل',
                bLabel: 'غير متّصل',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _Kpi = ({String key, String label, AppTone tone});
typedef _Row = ({int? a, int? b, String? extra});

/// تقريرٌ ببطاقته: عنوانه، وأرقامه الثلاثة، وصفوف الزونات بشريطٍ نسبيّ — أو قفله/انتظاره/تعذّره.
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.title,
    required this.icon,
    required this.part,
    required this.noPerm,
    required this.onRetry,
    required this.kpis,
    required this.row,
    required this.aLabel,
    required this.bLabel,
    this.note,
  });

  final String title;
  final IconData icon;
  final _Part part;

  /// الموظّف لا يملك مفتاح هذا التقرير — لا نداء.
  final bool noPerm;
  final VoidCallback onRetry;
  final List<_Kpi> kpis;
  final _Row Function(NationalZoneCount) row;
  final String aLabel;
  final String bLabel;
  final String Function(NationalReport)? note;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final d = part.data;
    final Widget body;
    if (noPerm) {
      body = _lockLine('لا صلاحيّة — اطلبها من مديرك');
    } else if (part.locked != null) {
      body = _lockLine(part.locked!.error ?? part.locked!.lockTitle);
    } else if (d == null && part.error != null) {
      // الرسالة تلتفّ وحدها، و«إعادة» سطرٌ تحتها (لا تزاحمها)
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(part.error!, style: AppType.body(color: AppColors.textMid)),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 15),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      );
    } else if (d == null || (d.pending && d.zones.isEmpty)) {
      body = Row(
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: Sp.sm),
          Text(d?.pending == true ? 'جارٍ تجهيز التقرير…' : 'جارٍ التحميل…', style: AppType.muted()),
        ],
      );
    } else {
      final extra = note?.call(d) ?? '';
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 0; i < kpis.length; i++) ...[
                if (i > 0) const SizedBox(width: Sp.sm),
                Expanded(child: _KpiTile(label: kpis[i].label, value: d.total(kpis[i].key), tone: kpis[i].tone)),
              ],
            ],
          ),
          if (extra.isNotEmpty) ...[
            const SizedBox(height: Sp.sm),
            Text(extra, style: AppType.micro(color: AppColors.textMid)),
          ],
          if (d.zones.isNotEmpty) ...[
            const SizedBox(height: Sp.sm),
            for (final z in d.zones) _ZoneRow(z: z, v: row(z), aLabel: aLabel, bLabel: bLabel),
          ] else ...[
            const SizedBox(height: Sp.sm),
            Text('لا زونات في التقرير', style: AppType.muted()),
          ],
          if (d.fetchedAt != null) ...[
            const SizedBox(height: Sp.xs),
            Text(
              '${d.stale ? 'آخر نسخةٍ محفوظة' : 'حُدّث'} ${iso(nationalTime(d.fetchedAt))}',
              style: AppType.micro(color: AppColors.textLow),
            ),
          ],
        ],
      );
    }
    return NationalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.textMid),
              const SizedBox(width: Sp.sm),
              Expanded(child: Text(title, style: AppType.cardTitle(color: AppColors.textHi))),
            ],
          ),
          const SizedBox(height: Sp.md),
          body,
        ],
      ),
    );
  }

  Widget _lockLine(String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(LucideIcons.lock, size: 16, color: AppColors.textLow),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(text, style: AppType.body(color: AppColors.textMid))),
        ],
      );
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value, required this.tone});
  final String label;
  final int? value;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: tone == AppTone.neutral ? AppColors.surfaceSunken : tone.softBg,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
          const SizedBox(height: 2),
          Text(nationalCount(value), textDirection: TextDirection.ltr, style: AppType.statValue(color: AppColors.textHi).copyWith(fontSize: 19)),
        ],
      ),
    );
  }
}

/// صفّ زون: اسمه (يميناً) والرقمان، وشريطٌ نسبيّ تحته (الأوّل بنغمة النجاح والثاني محايد). المجهول «—» بلا شريط.
class _ZoneRow extends StatelessWidget {
  const _ZoneRow({required this.z, required this.v, required this.aLabel, required this.bLabel});
  final NationalZoneCount z;
  final _Row v;
  final String aLabel;
  final String bLabel;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final a = v.a, b = v.b;
    final sum = a != null && b != null ? a + b : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(z.zone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: AppType.label(color: AppColors.textHi)),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Text(
                ['$aLabel ${nationalCount(a)}', '$bLabel ${nationalCount(b)}', if (v.extra != null) v.extra!].join(' · '),
                style: AppType.micro(color: AppColors.textMid),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: SizedBox(
              height: 6,
              child: sum == null || sum == 0
                  ? ColoredBox(color: AppColors.surfaceSunken)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (a! > 0) Expanded(flex: a, child: ColoredBox(color: AppColors.success)),
                        if (b! > 0) Expanded(flex: b, child: ColoredBox(color: AppColors.surfaceSunken)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
