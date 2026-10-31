import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_portal_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'national_labels.dart';
import 'national_widgets.dart';

/// «التذاكر» — المشروع الوطنيّ (watani، ٣١ أكتوبر — المالك: «الطلبات التذاكر هاي مهمه مموجوده… والفلاتر»): تذاكر الدعم في بوّابة
/// الشركة بفلاترها (رقم التذكرة أو اسم المشترك، الحالة، الزون، الفترة)، وورقة التذكرة بتفاصيلها وتعليقاتها. قراءةٌ وحدها — الإنشاء
/// والتعليق من هنا مرحلةٌ تالية. القائمة سريعة (~١ث) وتُكاش بالخادم.
class NationalTicketsScreen extends StatefulWidget {
  const NationalTicketsScreen({super.key});

  @override
  State<NationalTicketsScreen> createState() => _NationalTicketsScreenState();
}

class _NationalTicketsScreenState extends State<NationalTicketsScreen> {
  String _q = '';
  Map<String, String> _f = const {'status': '', 'zone': '', 'period': ''};
  NationalLookups? _lk;

  final List<NationalTicket> _rows = [];
  int _page = 0;
  int? _total;
  int? _pageCount;
  bool _loading = false;
  bool _pending = false;
  String? _error;
  int _gen = 0;
  Timer? _poll;
  int _polls = 0;

  int get _active => _f.values.where((v) => v.isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _reload();
    NationalPortalApi.lookups().then((v) {
      if (mounted && v != null) setState(() => _lk = v);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _reload() {
    _poll?.cancel();
    _polls = 0;
    _gen++;
    setState(() {
      _rows.clear();
      _page = 0;
      _total = null;
      _pageCount = null;
      _error = null;
      _pending = false;
    });
    _load();
  }

  Future<void> _load() async {
    final gen = _gen;
    final page = _page + 1;
    setState(() => _loading = true);
    final period = nationalPeriodRange(_f['period'] ?? '');
    final r = await NationalPortalApi.tickets(
      page: page,
      q: _q,
      status: _f['status'],
      zone: _f['zone'],
      from: period.from,
      to: period.to,
    );
    if (!mounted || gen != _gen) return;
    final d = r.data;
    setState(() {
      _loading = false;
      if (!r.ok) {
        _error = r.error;
        return;
      }
      if (d!.pending) {
        _pending = true;
        return;
      }
      _pending = false;
      _rows.addAll(d.items);
      _page = page;
      _total = d.total;
      _pageCount = d.pageCount;
    });
    // الجلب الأوّل جارٍ بالخادم: أعد السؤال بعد ٤ث (حتى دقيقة)
    if (r.ok && d!.pending && _polls < 15) {
      _polls++;
      _poll?.cancel();
      _poll = Timer(const Duration(seconds: 4), () {
        if (mounted && gen == _gen) _load();
      });
    }
  }

  Future<void> _openFilters() async {
    final v = await showNationalFilters(context, sections: [
      NationalFilterSection(
        key: 'status',
        title: 'الحالة',
        value: _f['status'] ?? '',
        options: _lk?.ticketStatuses?.map((x) => NationalChoice(x.id, nationalTicketStatus(x.name).label)).toList(),
      ),
      NationalFilterSection(
        key: 'zone',
        title: 'الزون',
        value: _f['zone'] ?? '',
        options: _lk?.zones?.map((x) => NationalChoice(x.id, x.name.isEmpty ? x.id : x.name)).toList(),
      ),
      NationalFilterSection(key: 'period', title: 'الفترة', value: _f['period'] ?? '', options: nationalPeriods, allLabel: 'كلّ الأوقات'),
    ]);
    if (v == null || !mounted) return;
    setState(() => _f = v);
    _reload();
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
          title: Text('التذاكر', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              Row(
                children: [
                  Expanded(
                    child: NationalSearchField(
                      hint: 'رقم التذكرة أو اسم المشترك',
                      onChanged: (v) {
                        _q = v;
                        _reload();
                      },
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  NationalFilterButton(active: _active, onTap: _openFilters),
                ],
              ),
              const SizedBox(height: Sp.md),
              ..._body(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_rows.isEmpty) {
      if (_error != null) return [NationalStateBox.error(text: _error!, onRetry: _reload)];
      if (_pending) return const [NationalStateBox.pending()];
      if (_loading || _page == 0) return const [NationalStateBox.loading()];
      return [
        NationalStateBox.empty(
          text: _q.isNotEmpty || _active > 0 ? 'لا تذاكر تطابق البحث' : 'لا توجد تذاكر',
          icon: LucideIcons.headset,
        ),
      ];
    }
    return [
      for (final t in _rows) ...[
        _TicketCard(t: t, onTap: t.id == null ? null : () => _openTicket(t)),
        const SizedBox(height: Sp.sm),
      ],
      if (_pageCount != null && _page < _pageCount!)
        NationalLoadMore(loading: _loading, onTap: _load, shown: _rows.length, total: _total, unit: 'تذكرة')
      else if (_total != null)
        Padding(
          padding: const EdgeInsets.only(top: Sp.sm),
          child: Text('$_total تذكرة', textAlign: TextAlign.center, style: AppType.muted()),
        ),
    ];
  }

  void _openTicket(NationalTicket t) {
    showAppSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _TicketSheet(row: t),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.t, this.onTap});
  final NationalTicket t;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final st = nationalTicketStatus(t.status);
    final who = t.infra ? 'بنية تحتيّة' : (t.customer?.name ?? '—');
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.lg), border: Border.all(color: AppColors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(t.title.isEmpty ? '—' : t.title,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.cardTitle(color: AppColors.textHi)),
                  ),
                  const SizedBox(width: Sp.sm),
                  ToneChip(label: st.label, tone: st.tone, dense: true),
                ],
              ),
              const SizedBox(height: 4),
              Text(t.displayId, textDirection: TextDirection.ltr, textAlign: TextAlign.end, style: AppType.micro(color: AppColors.textMid)),
              if (t.summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(t.summary, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textBody)),
              ],
              const SizedBox(height: Sp.sm),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _meta(t.infra ? LucideIcons.building2 : LucideIcons.user, who),
                  if (t.zone?.name.isNotEmpty == true) _meta(LucideIcons.mapPin, t.zone!.name, ltr: true),
                  if (t.comments > 0) _meta(LucideIcons.messageSquare, '${t.comments}'),
                  _meta(LucideIcons.clock, nationalTime(t.createdAt), ltr: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData i, String text, {bool ltr = false}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 13, color: AppColors.textMid),
          const SizedBox(width: 4),
          Text(text, textDirection: ltr ? TextDirection.ltr : null, style: AppType.micro(color: AppColors.textMid)),
        ],
      );
}

class _TicketSheet extends StatefulWidget {
  const _TicketSheet({required this.row});
  final NationalTicket row;

  @override
  State<_TicketSheet> createState() => _TicketSheetState();
}

class _TicketSheetState extends State<_TicketSheet> {
  NationalTicketDetails? _d;
  String? _error;
  Timer? _poll;
  int _polls = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await NationalPortalApi.ticket(widget.row.id!);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _error = r.error);
      return;
    }
    if (r.data == null) {
      if (_polls++ < 15) _poll = Timer(const Duration(seconds: 4), _load);
      return;
    }
    setState(() {
      _d = r.data;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final d = _d;
    final st = nationalTicketStatus(d?.status ?? widget.row.status);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.headset,
        title: d?.title.isNotEmpty == true ? d!.title : (widget.row.title.isEmpty ? 'تذكرة' : widget.row.title),
        subtitle: widget.row.displayId,
        subtitleLtr: true,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: _error != null
          ? NationalStateBox.error(text: _error!, onRetry: () {
              setState(() => _error = null);
              _load();
            })
          : d == null
              ? const NationalStateBox.loading()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(alignment: AlignmentDirectional.centerStart, child: ToneChip(label: st.label, tone: st.tone)),
                    const SizedBox(height: Sp.md),
                    NationalInfoGroup(children: [
                      NationalInfoRow(icon: LucideIcons.user, label: 'المشترك', value: d.infra ? 'بنية تحتيّة' : (d.customer?.name ?? '—')),
                      if (d.zone?.name.isNotEmpty == true) NationalInfoRow(icon: LucideIcons.mapPin, label: 'الزون', value: d.zone!.name, ltr: true),
                      if ((d.category ?? d.issue) != null)
                        NationalInfoRow(icon: LucideIcons.tag, label: 'التصنيف', value: [d.category, d.issue].whereType<String>().join(' · ')),
                      NationalInfoRow(icon: LucideIcons.calendarClock, label: 'فُتحت', value: nationalTime(d.createdAt), ltr: true),
                      if (d.closedAt != null) NationalInfoRow(icon: LucideIcons.calendarCheck, label: 'أُغلقت', value: nationalTime(d.closedAt), ltr: true),
                      if (d.scheduleDate != null)
                        NationalInfoRow(icon: LucideIcons.calendarClock, label: 'موعد الزيارة', value: nationalTime(d.scheduleDate), ltr: true),
                    ]),
                    if (d.details.isNotEmpty) ...[
                      const SizedBox(height: Sp.lg),
                      Text('التفاصيل', style: AppType.label(color: AppColors.textLabel)),
                      const SizedBox(height: Sp.sm),
                      SelectableText(d.details, style: AppType.body(color: AppColors.textBody)),
                    ],
                    if (d.attachments.isNotEmpty) ...[
                      const SizedBox(height: Sp.lg),
                      Text('المرفقات (${d.attachments.length}) — تُفتح من بوّابة المشروع الوطني', style: AppType.muted()),
                    ],
                    const SizedBox(height: Sp.lg),
                    Text('التعليقات', style: AppType.label(color: AppColors.textLabel)),
                    const SizedBox(height: Sp.sm),
                    if (d.comments == null)
                      Text('تعذّر جلب التعليقات الآن.', style: AppType.muted())
                    else if (d.comments!.isEmpty)
                      Text('لا توجد تعليقات.', style: AppType.muted())
                    else
                      for (final c in d.comments!) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceSunken,
                            borderRadius: BorderRadius.circular(R.md),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(c.by.isEmpty ? '—' : c.by,
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textHi)),
                                  ),
                                  Text(nationalTime(c.at), textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              SelectableText(c.text.isEmpty ? '—' : c.text, style: AppType.body(color: AppColors.textBody)),
                            ],
                          ),
                        ),
                        const SizedBox(height: Sp.sm),
                      ],
                  ],
                ),
    );
  }
}
