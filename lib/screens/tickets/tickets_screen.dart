import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/company_route.dart';
import '../../api/tickets_api.dart';
import '../../models/merged_company.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/merged_section.dart';
import '../desktop/desk_widgets.dart';
import 'ticket_thread_screen.dart';
import 'ticket_widgets.dart';

/// «التذاكر» (المالك ٩ نوفمبر): تذاكر مشتركيك من تطبيقهم — «بانتظارك» (جديدة أو قيد المعالجة) و«تمّ الردّ» و«المنتهية» والكلّ،
/// غير المقروءة أوّلاً، والنقر يفتح المحادثة (الردّ والحالة). الموظّف بلا «التذاكر — العرض» يراها مقفلةً لا مخفيّة.
class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  /// «كل الشركات»: القائمة والمحادثة قراءةٌ موجَّهة لكلّ شركة (الخادم companyRoutingAllow) — غير المفتوحة للعرض، والردّ والحالة
  /// من صفحتها. الوطنيّ لا تذاكر له.
  static Widget mergedPage() => MergedSection(
      readOnly: true,
      prefixes: const [TicketsApi.base],
      serves: (c) => c.provider != MergedProvider.ftth && !c.code.toLowerCase().startsWith('watani'),
      servesNote: 'التذاكر لكلّ الشركات ما عدا المشروع الوطني',
      lockTitle: 'التذاكر',
      child: const TicketsScreen());

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  TicketsAccess? _access;
  TicketFilter _filter = TicketFilter.open;
  List<Ticket> _items = const [];
  TicketCounts _counts = const TicketCounts();
  bool _hasMore = false;
  int? _nextOffset;
  bool _loading = true;
  bool _more = false;
  bool _failed = false;
  int _seq = 0;

  /// «كل الشركات»: شركةٌ غير المفتوحة في القسم ⇒ للعرض (القسم يُدخَل قبل بناء الشاشة؛ الإطار يُقرأ في build).
  bool _viewOnly = false;

  @override
  void initState() {
    super.initState();
    _viewOnly = CompanyRoute.sectionKeyFor(TicketsApi.base) != null;
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    final a = await TicketsApi.summary();
    TicketsPage? p;
    if (a != null && a.on) p = await TicketsApi.list(filter: _filter);
    if (!mounted || seq != _seq) return;
    setState(() {
      _access = a;
      _failed = a == null || (a.on && p == null);
      if (p != null) {
        _items = p.items;
        _counts = p.counts;
        _hasMore = p.hasMore;
        _nextOffset = p.nextOffset;
      }
      _loading = false;
    });
    // الشارة تتبع ما رأيته هنا — للمفتوحة وحدها (شركةٌ أخرى معروضة هنا لا تكتب عدّادها فوق شارة المفتوحة)
    if (p != null && !(MergedSection.of(context)?.routed ?? false)) unawaited(TicketsState.ensureFresh(force: true));
  }

  Future<void> _loadMore() async {
    final from = _nextOffset;
    if (_more || from == null) return;
    setState(() => _more = true);
    final seq = _seq;
    final p = await TicketsApi.list(filter: _filter, offset: from);
    if (!mounted || seq != _seq) return;
    setState(() {
      _more = false;
      if (p != null) {
        final seen = {for (final t in _items) t.id};
        _items = [..._items, ...p.items.where((t) => !seen.contains(t.id))];
        _counts = p.counts;
        _hasMore = p.hasMore;
        _nextOffset = p.nextOffset;
      }
    });
  }

  void _setFilter(TicketFilter f) {
    if (f == _filter) return;
    setState(() {
      _filter = f;
      _loading = true;
      _items = const [];
    });
    _load();
  }

  Future<void> _open(Ticket t) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TicketThreadScreen(ticketId: t.id, initial: t, viewOnly: _viewOnly),
    ));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    _viewOnly = MergedSection.viewOnlyOf(context) || CompanyRoute.sectionKeyFor(TicketsApi.base) != null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Text('التذاكر', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        ),
        title: 'التذاكر',
      ),
      body: MergedSectionBody(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                  children: _body(),
                ),
              ),
      ),
    );
  }

  List<Widget> _body() {
    final a = _access;
    if (a == null) return [_center(LucideIcons.wifiOff, 'تعذّر جلب التذاكر الآن', 'اسحب للأسفل لإعادة المحاولة')];
    if (!a.available) return [_center(LucideIcons.ticket, 'قسم التذاكر غير متاحٍ لهذا الحساب', '')];
    if (!a.canView) {
      return [
        _center(
          LucideIcons.lock,
          'لا صلاحيّة',
          a.scoped
              ? 'التذاكر من كلّ مشتركي الحساب — لا تُفتح لموظّفٍ مقيَّد بمديرٍ فرعيّ'
              : 'يفتحها لك المدير من صلاحيّاتك: «التذاكر من تطبيق المشترك — عرضها وإشعاراتها»',
          key: const ValueKey('tickets-locked'),
        ),
      ];
    }
    return [
      if (_viewOnly) ...[
        _note(LucideIcons.eye, 'للعرض هنا — الردّ وتغيير الحالة من صفحة الشركة نفسها'),
        const SizedBox(height: Sp.md),
      ],
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in TicketFilter.values) ...[
            ChoiceChip(
              key: ValueKey('tickets-filter-${f.name}'),
              label: Text(_chipText(f)),
              selected: _filter == f,
              showCheckmark: false,
              onSelected: (_) => _setFilter(f),
            ),
            const SizedBox(width: Sp.sm),
          ],
        ]),
      ),
      const SizedBox(height: Sp.md),
      if (_failed)
        _center(LucideIcons.wifiOff, 'تعذّر جلب التذاكر الآن', 'اسحب للأسفل لإعادة المحاولة')
      else if (_items.isEmpty)
        _center(LucideIcons.ticket, _emptyTitle(), 'حين يكتب مشتركٌ تذكرةً من تطبيقه تظهر هنا ويصلك إشعار')
      else ...[
        for (final t in _items) ...[
          TicketTile(ticket: t, onTap: () => _open(t)),
          const SizedBox(height: Sp.sm),
        ],
        if (_hasMore)
          Center(
            child: TextButton(
              key: const ValueKey('tickets-more'),
              onPressed: _more ? null : _loadMore,
              child: _more
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('عرض المزيد'),
            ),
          ),
      ],
    ];
  }

  /// العدد لما ينتظر عملاً («بانتظارك» و«تمّ الردّ») — المنتهية والكلّ بلا رقمٍ يكبر بلا معنى.
  String _chipText(TicketFilter f) {
    final n = _counts.of(f);
    return (f == TicketFilter.open || f == TicketFilter.answered) && n > 0 ? '${filterLabel(f)} ($n)' : filterLabel(f);
  }

  String _emptyTitle() => switch (_filter) {
        TicketFilter.open => 'لا تذاكر بانتظارك الآن',
        TicketFilter.answered => 'لا تذاكر بانتظار ردّ المشترك',
        TicketFilter.closed => 'لا تذاكر منتهية',
        TicketFilter.all => 'لا تذاكر بعد',
      };

  Widget _note(IconData icon, String text) => Container(
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.infoSoftBg,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.infoSoftBorder),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.info),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(text, style: AppType.label(color: AppColors.textBody).copyWith(height: 1.5))),
        ]),
      );

  Widget _center(IconData icon, String title, String sub, {Key? key}) => Padding(
        key: key,
        padding: const EdgeInsets.only(top: Sp.mega),
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.brandSoftBg, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.brand),
          ),
          const SizedBox(height: Sp.md),
          Text(title, textAlign: TextAlign.center, style: AppType.bodyStrong(color: AppColors.textHi)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: Sp.xs),
            Text(sub, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
          ],
        ]),
      );
}
