import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_portal_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../reports/widgets/date_range_chip.dart';
import 'national_labels.dart';
import 'national_widgets.dart';

/// «الإيرادات» — المشروع الوطنيّ (watani، ٣١ أكتوبر — المالك: «المواضع الي متعلقة بالمالية… والفلاتر»): حركات التفعيل بكلّ طرق
/// الدفع (يدفعها الوكيل أو المشترك) + مجموع الفترة رقم البوّابة نفسها، بحثٌ بيوزر الجهاز أو اسم المشترك ومبلغٌ من/إلى. الفترة بأزرار
/// التقارير نفسها (بتوقيت بغداد، حتى ٩٢ يوماً). قراءةٌ وحدها.
///
/// «محفظتي» صارت قسماً بنفسها ([NationalWalletScreen]، ١ نوفمبر) كالبوّابة — لا تبويباً هنا.
class NationalMoneyScreen extends StatefulWidget {
  const NationalMoneyScreen({super.key});

  @override
  State<NationalMoneyScreen> createState() => _NationalMoneyScreenState();
}

class _NationalMoneyScreenState extends State<NationalMoneyScreen> {
  DateRange _range = DateRange.today();
  String _q = '';
  Map<String, String> _f = const {'amount': ''};
  final _p = NationalPaged<NationalMoneyRow>();

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// شرائح المبلغ الجاهزة ⇒ (من، إلى).
  static const _amounts = [
    NationalChoice('0-25000', 'حتى 25,000'),
    NationalChoice('25000-50000', '25,000 – 50,000'),
    NationalChoice('50000-', 'أكثر من 50,000'),
  ];

  int get _active => [_f['amount']].where((v) => v != null && v.isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _p.dispose();
    super.dispose();
  }

  void _reload() {
    _p.reset();
    setState(() {});
    _next();
  }

  void _next() {
    final amt = (_f['amount'] ?? '').split('-');
    _p.next(
      (page) => NationalPortalApi.money(
        revenue: true,
        from: _day(_range.from),
        to: _day(_range.to),
        page: page,
        q: _q,
        min: amt.isNotEmpty ? amt[0] : null,
        max: amt.length > 1 ? amt[1] : null,
      ),
      onChange: () {
        if (mounted) setState(() {});
      },
      alive: () => mounted,
    );
  }

  Future<void> _openFilters() async {
    final v = await showNationalFilters(context, sections: [
      NationalFilterSection(key: 'amount', title: 'المبلغ (دينار)', value: _f['amount'] ?? '', options: _amounts, allLabel: 'كلّ المبالغ'),
    ]);
    if (v == null || !mounted) return;
    setState(() => _f = {..._f, ...v});
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
          title: Text('الإيرادات', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              DateRangeChipBar(
                value: _range,
                onChanged: (r) {
                  setState(() => _range = r);
                  _reload();
                },
              ),
              const SizedBox(height: Sp.md),
              Row(
                children: [
                  Expanded(
                    child: NationalSearchField(
                      hint: 'يوزر الجهاز أو اسم المشترك',
                      initial: _q,
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
              _kpis(),
              const SizedBox(height: Sp.md),
              ..._body(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kpis() {
    final raw = _p.raw;
    final busy = _p.loading || _p.pending;
    final sum = raw['sum'];
    final big = busy ? '…' : sum is num ? formatIQD(sum) : '—';
    final small = 'مجموع الفترة${_p.total != null ? ' · ${_p.total} حركة' : ''}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.successSoftBg, borderRadius: BorderRadius.circular(R.icon)),
            child: Icon(LucideIcons.banknote, color: AppColors.success, size: 20),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(small, style: AppType.muted()),
                const SizedBox(height: 2),
                Text(big, textDirection: TextDirection.ltr, style: AppType.statValue(color: AppColors.textHi)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _body() {
    if (_p.rows.isEmpty) {
      if (_p.error != null) return [NationalStateBox.error(text: _p.error!, onRetry: _reload)];
      if (_p.pending) return const [NationalStateBox.pending()];
      if (_p.loading || _p.page == 0) return const [NationalStateBox.loading()];
      return [const NationalStateBox.empty(text: 'لا توجد حركات في هذه الفترة', icon: LucideIcons.receipt)];
    }
    return [
      for (final r in _p.rows) ...[
        _MoneyCard(r: r),
        const SizedBox(height: Sp.sm),
      ],
      if (_p.hasMore)
        NationalLoadMore(loading: _p.loading, onTap: _next, shown: _p.rows.length, total: _p.total, unit: 'حركة'),
    ];
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.r});
  final NationalMoneyRow r;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final amt = r.amount;
    final type = nationalTxType(r.type);
    final tone = switch (r.type.toUpperCase()) {
      'PLAN_PURCHASE' => AppTone.success,
      'PLAN_CHANGE' => AppTone.info,
      'PLAN_RENEW' || 'AUTO_RENEW' => AppTone.brand,
      _ => AppTone.neutral,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
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
                    Text(r.customer?.name ?? '—', style: AppType.listName(color: AppColors.textHi)),
                    if (r.username != null)
                      Text(r.username!, textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amt == null ? '—' : '${amt < 0 ? '−' : ''}${formatIQD(amt.abs())}',
                    textDirection: TextDirection.ltr,
                    style: AppType.amount(color: AppColors.textHi).copyWith(fontSize: 15),
                  ),
                  Text(nationalTime(r.at), textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                ],
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Tooltip(message: r.type, child: ToneChip(label: type, tone: tone, dense: true)),
              if (r.outsidePeriod) const ToneChip(label: 'خارج الفترة', tone: AppTone.warning, dense: true),
              Text(
                [nationalPayMethod(r.method), if (r.paidBy.isNotEmpty) nationalPayer(r.paidBy)].join(' · '),
                style: AppType.micro(color: AppColors.textMid),
              ),
              if (r.ends != null)
                Text('ينتهي ${iso(nationalTime(r.ends).substring(0, nationalTime(r.ends).length >= 10 ? 10 : nationalTime(r.ends).length))}',
                    style: AppType.micro(color: AppColors.textMid)),
            ],
          ),
        ],
      ),
    );
  }
}
