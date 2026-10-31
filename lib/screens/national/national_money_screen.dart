import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_portal_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../reports/widgets/date_range_chip.dart';
import 'national_labels.dart';
import 'national_widgets.dart';

/// «الحركات الماليّة» — المشروع الوطنيّ (watani، ٣١ أكتوبر — المالك: «المواضع الي متعلقة بالمالية… والفلاتر»):
///   الإيرادات: حركات التفعيل بكلّ طرق الدفع (يدفعها الوكيل أو المشترك) + مجموع الفترة رقم البوّابة نفسها، بحثٌ بيوزر الجهاز أو
///              اسم المشترك ومبلغٌ من/إلى؛
///   محفظتي:   كشف محفظة الوكيل + رصيده الحاليّ، بنوع الحركة وطريقة الدفع والمبلغ.
/// الفترة بأزرار التقارير نفسها (بتوقيت بغداد، حتى ٩٢ يوماً). قراءةٌ وحدها.
class NationalMoneyScreen extends StatefulWidget {
  const NationalMoneyScreen({super.key});

  @override
  State<NationalMoneyScreen> createState() => _NationalMoneyScreenState();
}

class _NationalMoneyScreenState extends State<NationalMoneyScreen> {
  int _tab = 0; // ٠ الإيرادات · ١ محفظتي
  DateRange _range = DateRange.today();
  String _q = '';
  Map<String, String> _f = const {'type': '', 'method': '', 'amount': ''};
  NationalLookups? _lk;
  final _p = NationalPaged<NationalMoneyRow>();

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// شرائح المبلغ الجاهزة ⇒ (من، إلى).
  static const _amounts = [
    NationalChoice('0-25000', 'حتى 25,000'),
    NationalChoice('25000-50000', '25,000 – 50,000'),
    NationalChoice('50000-', 'أكثر من 50,000'),
  ];

  int get _active => [
        _f['amount'],
        if (_tab == 1) ...[_f['type'], _f['method']],
      ].where((v) => v != null && v.isNotEmpty).length;

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
        revenue: _tab == 0,
        from: _day(_range.from),
        to: _day(_range.to),
        page: page,
        q: _q,
        type: _f['type'],
        method: _f['method'],
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
    if (_tab == 1 && _lk == null) {
      NationalPortalApi.lookups().then((v) {
        if (mounted && v != null) setState(() => _lk = v);
      });
    }
    final v = await showNationalFilters(context, sections: [
      if (_tab == 1) ...[
        NationalFilterSection(
          key: 'type',
          title: 'نوع الحركة',
          value: _f['type'] ?? '',
          options: _lk?.transactionTypes?.map((x) => NationalChoice(x.id, nationalTxTypes[x.id] ?? x.name)).toList() ??
              nationalTxTypes.entries.take(6).map((e) => NationalChoice(e.key, e.value)).toList(),
        ),
        NationalFilterSection(
          key: 'method',
          title: 'طريقة الدفع',
          value: _f['method'] ?? '',
          options: const [NationalChoice('Wallet', 'محفظة'), NationalChoice('Card', 'بطاقة')],
        ),
      ],
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
          title: Text('الحركات الماليّة', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('الإيرادات'), icon: Icon(LucideIcons.banknote, size: 16)),
                  ButtonSegment(value: 1, label: Text('محفظتي'), icon: Icon(LucideIcons.walletCards, size: 16)),
                ],
                selected: {_tab},
                showSelectedIcon: false,
                onSelectionChanged: (s) {
                  setState(() {
                    _tab = s.first;
                    _f = {..._f, 'type': '', 'method': ''};
                  });
                  _reload();
                },
              ),
              const SizedBox(height: Sp.md),
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
                  if (_tab == 0)
                    Expanded(
                      child: NationalSearchField(
                        hint: 'يوزر الجهاز أو اسم المشترك',
                        initial: _q,
                        onChanged: (v) {
                          _q = v;
                          _reload();
                        },
                      ),
                    )
                  else
                    const Spacer(),
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
    String big;
    String small;
    if (_tab == 0) {
      final sum = raw['sum'];
      big = busy ? '…' : sum is num ? formatIQD(sum) : '—';
      small = 'مجموع الفترة${_p.total != null ? ' · ${_p.total} حركة' : ''}';
    } else {
      final b = raw['balance'];
      final bal = b is Map ? b['balance'] : null;
      big = bal is num ? formatIQD(bal) : (busy ? '…' : '—');
      small = 'الرصيد الحاليّ${_p.total != null ? ' · ${_p.total} حركة بالفترة' : ''}';
    }
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
            child: Icon(_tab == 0 ? LucideIcons.banknote : LucideIcons.wallet, color: AppColors.success, size: 20),
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
        _MoneyCard(r: r, wallet: _tab == 1),
        const SizedBox(height: Sp.sm),
      ],
      if (_p.hasMore)
        NationalLoadMore(loading: _p.loading, onTap: _next, shown: _p.rows.length, total: _p.total, unit: 'حركة'),
    ];
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.r, required this.wallet});
  final NationalMoneyRow r;
  final bool wallet;

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
                [nationalPayMethod(r.method), if (!wallet && r.paidBy.isNotEmpty) nationalPayer(r.paidBy)].join(' · '),
                style: AppType.micro(color: AppColors.textMid),
              ),
              if (wallet && r.balanceAfter != null)
                Text('الرصيد بعدها ${formatIQD(r.balanceAfter!)}', style: AppType.micro(color: AppColors.textMid)),
              if (!wallet && r.ends != null)
                Text('ينتهي ${nationalTime(r.ends).substring(0, nationalTime(r.ends).length >= 10 ? 10 : nationalTime(r.ends).length)}',
                    style: AppType.micro(color: AppColors.textMid)),
            ],
          ),
        ],
      ),
    );
  }
}
