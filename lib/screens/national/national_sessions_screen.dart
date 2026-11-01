import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_more_api.dart';
import '../../api/national_portal_api.dart';
import '../../core/util/bidi.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'national_more_widgets.dart';
import 'national_widgets.dart';

/// «الجلسات» — المشروع الوطنيّ (١ نوفمبر، قسم البوّابة نفسه): المتّصلون الآن وغير المتّصلين، ببحثٍ باسم الجهاز (بالبوّابة) أو باسم
/// المشترك (داخل الصفحة المعروضة وحدها — يُقال ذلك) وفلتر الزون، صفحاتٌ من ٢٥. البطاقة مختصرة (الاسم والجهاز، الزون والمدّة
/// والاستهلاك)، والنقر يفتح تفاصيل الجلسة (الآيبي والماك والبداية والباقة). قراءةٌ وحدها — لا «قطع الاتصال» من هنا. الخادم
/// `/api/v2/ftth/sessions` (العقد §4)؛ بلا صلاحيّة البوّابة ⇒ قفلٌ هادئ بسببه.
class NationalSessionsScreen extends StatefulWidget {
  const NationalSessionsScreen({super.key, this.initialOnline = true});

  /// true = «متّصل الآن» أوّلاً.
  final bool initialOnline;

  @override
  State<NationalSessionsScreen> createState() => _NationalSessionsScreenState();
}

class _NationalSessionsScreenState extends State<NationalSessionsScreen> {
  late bool _online = widget.initialOnline;
  String _q = '';
  String _zone = '';
  NationalLookups? _lk;

  /// قفل القسم (البوّابة لا تعطيه لمستخدمك، أو تجريبيٌّ لم يُفتح للحساب) — بدل «تعذّر».
  NationalMoreResult<Object?>? _locked;
  final _p = NationalPaged<NationalSession>();

  @override
  void initState() {
    super.initState();
    _reload();
    // الزونات لورقة الفلاتر من الآن (كاش ستّ ساعات بالخادم) — لا «جارٍ تحميل الخيارات» عند فتحها
    _loadLookups();
  }

  void _loadLookups() {
    NationalPortalApi.lookups().then((v) {
      if (mounted && v != null) setState(() => _lk = v);
    });
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  void _reload() {
    _p.reset();
    _locked = null;
    setState(() {});
    _next();
  }

  void _next() {
    final online = _online;
    _p.next(
      (page) async {
        final r = await NationalMoreApi.sessions(online: online, page: page, q: _q, zone: _zone);
        if (r.locked && mounted && online == _online) _locked = r;
        return r.toResult();
      },
      onChange: () {
        if (mounted) setState(() {});
      },
      alive: () => mounted,
    );
  }

  Future<void> _openFilters() async {
    if (_lk == null) _loadLookups();
    final v = await showNationalFilters(context, sections: [
      NationalFilterSection(
        key: 'zone',
        title: 'الزون',
        value: _zone,
        options: _lk?.zones?.map((x) => NationalChoice(x.id, x.name.isEmpty ? x.id : x.name)).toList(),
        allLabel: 'كلّ الزونات',
      ),
    ]);
    if (v == null || !mounted) return;
    setState(() => _zone = v['zone'] ?? '');
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final inPage = _p.raw['filtered_in_page'] == true && _q.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text('الجلسات', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('متّصل الآن'), icon: Icon(LucideIcons.wifi, size: 16)),
                  ButtonSegment(value: false, label: Text('غير متّصل'), icon: Icon(LucideIcons.wifiOff, size: 16)),
                ],
                selected: {_online},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setState(() => _online = s.first);
                  _reload();
                },
              ),
              const SizedBox(height: Sp.md),
              Row(
                children: [
                  Expanded(
                    child: NationalSearchField(
                      hint: 'اسم الجهاز أو المشترك',
                      initial: _q,
                      onChanged: (v) {
                        _q = v;
                        _reload();
                      },
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  NationalFilterButton(active: _zone.isEmpty ? 0 : 1, onTap: _openFilters),
                ],
              ),
              if (inPage) ...[
                const SizedBox(height: Sp.sm),
                Text('البحث بالاسم داخل الصفحة المعروضة وحدها — ابحث باسم الجهاز لكلّ النتائج',
                    style: AppType.micro(color: AppColors.textMid)),
              ] else if (_p.total != null && _p.rows.isNotEmpty) ...[
                const SizedBox(height: Sp.sm),
                Text(
                  _online ? 'متّصل الآن: ${nationalCount(_p.total)}' : 'غير متّصل: ${nationalCount(_p.total)}',
                  style: AppType.micro(color: AppColors.textMid),
                ),
              ],
              const SizedBox(height: Sp.md),
              ..._body(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_p.rows.isEmpty) {
      final l = _locked;
      if (l != null) return [NationalLockedBox(title: l.lockTitle, text: l.error ?? '')];
      if (_p.error != null) return [NationalStateBox.error(text: _p.error!, onRetry: _reload)];
      if (_p.pending) return const [NationalStateBox.pending()];
      if (_p.loading || _p.page == 0) return const [NationalStateBox.loading()];
      final filtered = _q.isNotEmpty || _zone.isNotEmpty;
      return [
        NationalStateBox.empty(
          text: filtered ? 'لا جلسات تطابق البحث' : (_online ? 'لا أحد متّصلٌ الآن' : 'لا يوجد غير متّصلين'),
          icon: _online ? LucideIcons.wifi : LucideIcons.wifiOff,
        ),
      ];
    }
    return [
      for (final s in _p.rows) ...[
        _SessionCard(s: s, onlineTab: _online, onTap: () => _openSession(s)),
        const SizedBox(height: Sp.sm),
      ],
      if (_p.hasMore)
        NationalLoadMore(loading: _p.loading, onTap: _next, shown: _p.rows.length, total: _p.total, unit: 'جلسة'),
    ];
  }

  void _openSession(NationalSession s) => showAppSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: AppColors.scrim,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _SessionSheet(s: s, onlineTab: _online),
      );
}

/// الحالة: «منتهي» للاشتراك المنتهي، وإلّا متّصل/غير متّصل.
Widget _statusChip(NationalSession s, bool online) => s.expired == true
    ? const ToneChip(label: 'منتهي', tone: AppTone.warning, dense: true)
    : online
        ? const ToneChip(label: 'متّصل', tone: AppTone.success, icon: LucideIcons.wifi, dense: true)
        : const ToneChip(label: 'غير متّصل', tone: AppTone.neutral, dense: true);

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.s, required this.onlineTab, required this.onTap});
  final NationalSession s;
  final bool onlineTab;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final online = s.online ?? onlineTab;
    final name = s.customer?.name.isNotEmpty == true ? s.customer!.name : null;
    return NationalCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name ?? (s.username.isEmpty ? '—' : s.username),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: name == null ? TextDirection.ltr : null,
                      style: AppType.listName(color: AppColors.textHi),
                    ),
                    if (name != null && s.username.isNotEmpty)
                      Text(s.username, textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              _statusChip(s, online),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (s.zone != null) nationalMeta(LucideIcons.mapPin, s.zone!, ltr: true),
              if (online && s.durationSec != null) nationalMeta(LucideIcons.clock, nationalDuration(s.durationSec)),
              // التنزيل وحده بالبطاقة (سطرٌ واحد بعرض ٣٢٠)؛ الرفع والآيبي والماك في التفاصيل
              if (online && s.download != null) nationalMeta(LucideIcons.arrowDown, nationalBytes(s.download), ltr: true),
              if (!online && s.plan != null) nationalMeta(LucideIcons.package, s.plan!, ltr: true),
            ],
          ),
        ],
      ),
    );
  }
}

/// تفاصيل الجلسة كاملةً — ما لا يعطيه الصفّ «—».
class _SessionSheet extends StatelessWidget {
  const _SessionSheet({required this.s, required this.onlineTab});
  final NationalSession s;
  final bool onlineTab;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final online = s.online ?? onlineTab;
    String v(String? x) => x == null || x.isEmpty ? '—' : x;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: online ? LucideIcons.wifi : LucideIcons.wifiOff,
        title: s.customer?.name.isNotEmpty == true ? s.customer!.name : 'تفاصيل الجلسة',
        subtitle: online ? 'متّصل الآن' : 'غير متّصل',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: AlignmentDirectional.centerStart, child: _statusChip(s, online)),
          const SizedBox(height: Sp.md),
          NationalInfoGroup(children: [
            NationalInfoRow(icon: LucideIcons.router, label: 'اسم الجهاز', value: v(s.username), ltr: true),
            NationalInfoRow(icon: LucideIcons.mapPin, label: 'الزون', value: v(s.zone), ltr: true),
            NationalInfoRow(icon: LucideIcons.package, label: 'الاشتراك', value: v(s.plan), ltr: true),
            NationalInfoRow(icon: LucideIcons.calendarClock, label: 'بداية الجلسة', value: s.startedAt == null ? '—' : iso(nationalTime(s.startedAt))),
            NationalInfoRow(icon: LucideIcons.clock, label: 'مدّة الجلسة', value: nationalDuration(s.durationSec)),
            NationalInfoRow(icon: LucideIcons.network, label: 'IP', value: v(s.ip), ltr: true),
            NationalInfoRow(icon: LucideIcons.cpu, label: 'MAC', value: v(s.mac), ltr: true),
            NationalInfoRow(icon: LucideIcons.arrowDown, label: 'التنزيل', value: nationalBytes(s.download), ltr: true),
            NationalInfoRow(icon: LucideIcons.arrowUp, label: 'الرفع', value: nationalBytes(s.upload), ltr: true),
          ]),
          if (!online) ...[
            const SizedBox(height: Sp.sm),
            Text('البوّابة لا تعطي الآيبي ولا المدّة لغير المتّصل', style: AppType.micro(color: AppColors.textMid)),
          ],
        ],
      ),
    );
  }
}
