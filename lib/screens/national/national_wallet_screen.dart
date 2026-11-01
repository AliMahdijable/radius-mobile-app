import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_portal_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../reports/widgets/date_range_chip.dart';
import 'national_labels.dart';
import 'national_widgets.dart';

/// «محفظتي» — المشروع الوطنيّ (watani، ١ نوفمبر — المالك: حركات التفعيل لا تظهر عندنا كما في البوّابة). كصفحة البوّابة نفسها
/// (المحفظة ← «محفظتى»): رصيد المحفظة (أو «حدّ المحفظة» لعضو فريقٍ بحدّ) ورصيد العمولة، وحركات محفظتي **بنوعيها** (الرئيسيّة
/// والعمولة) لآخر ٣٠ يوماً افتراضاً — لا «اليوم» وحده — ومجموعاتٌ سريعة («حركات التفعيل» · «الشحن والتحويل» · «المرتجعات» ·
/// «العمولات»)، وبحثٌ برمز الاشتراك أو اسم المشترك، وفلاتر البوّابة (النوع، المحفظة، التغيير، الدفع، المنفّذ، رقم المعاملة/الاشتراك).
/// و«التحويلات» (حين يملكها الحساب في البوّابة — caps.transfers) لكلّ المحافظ التي يراها الحساب، ومنها دفع المشتركين بالبطاقة، لآخر
/// ٧ أيّام افتراضاً. قراءةٌ وحدها: لا شحن ولا تحويل من هنا. الخادم `/api/v2/ftth/wallet` و`/api/v2/ftth/transfers`.
class NationalWalletScreen extends StatefulWidget {
  const NationalWalletScreen({super.key});

  @override
  State<NationalWalletScreen> createState() => _NationalWalletScreenState();
}

class _NationalWalletScreenState extends State<NationalWalletScreen> {
  bool _transfers = false;
  DateRange _walletRange = DateRange.lastDays(30);
  DateRange _transfersRange = DateRange.lastDays(7);
  String _group = '';
  String _q = '';
  int _qGen = 0;
  static const _empty = {
    'type': '',
    'wallet': '',
    'change': '',
    'sales': '',
    'by': '',
    'tx': '',
    'sub': '',
    'owner': '',
    'method': '',
  };
  Map<String, String> _f = _empty;
  NationalLookups? _lk;

  /// آخر رصيدٍ وقدراتٍ وصلت سليمة — تبقى أثناء التحميل التالي وفي «التحويلات» (لا وميض «—»).
  NationalWalletMeta _meta = const NationalWalletMeta();

  /// الردّ الأخير (اقتراحات الاسم) — يتبع كلّ ردّ.
  NationalWalletMeta _last = const NationalWalletMeta();

  /// الخادم يفهم «محفظتي» v2 (المجموعات والقدرات)؟ null = لم يردّ بعد.
  bool? _v2;
  final _p = NationalPaged<NationalMoneyRow>();

  static const _maxDays = 92;

  DateRange get _range => _transfers ? _transfersRange : _walletRange;

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static List<DateRange> _presets() => [DateRange.today(), DateRange.lastDays(7), DateRange.lastDays(30)];

  int get _active => [
        for (final k in ['type', 'wallet', 'change', 'sales', 'by', 'tx', 'sub', if (_transfers) ...['owner', 'method']]) _f[k],
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
    final r = _range;
    _p.next(
      (page) => NationalPortalApi.wallet(
        transfers: _transfers,
        from: _day(r.from),
        to: _day(r.to),
        page: page,
        group: _group,
        type: _f['type'],
        wallet: _f['wallet'],
        owner: _f['owner'],
        method: _f['method'],
        change: _f['change'],
        sales: _f['sales'],
        tx: _f['tx'],
        sub: _f['sub'],
        q: _q,
        mine: _f['by'] == 'me',
      ),
      onChange: () {
        if (!mounted) return;
        final raw = _p.raw;
        if (raw.isNotEmpty && !_p.pending && _p.error == null) {
          final m = NationalWalletMeta.fromRaw(raw);
          _last = m;
          _v2 = m.v2 || (_v2 ?? false);
          // الرصيد والقدرات حين يحملها الردّ (ردّ «التحويلات» قد لا يحملهما) — وإلّا يبقى ما وصل قبله
          final hasBal = raw['balance'] is Map;
          final hasCaps = raw['caps'] is Map;
          if (hasBal || hasCaps) {
            _meta = NationalWalletMeta(
              balance: hasBal ? m.balance : _meta.balance,
              commission: hasBal ? m.commission : _meta.commission,
              limit: hasBal ? m.limit : _meta.limit,
              currency: hasBal ? m.currency : _meta.currency,
              caps: hasCaps ? m.caps : _meta.caps,
              v2: _v2!,
            );
          }
        }
        setState(() {});
      },
      alive: () => mounted,
    );
  }

  void _setRange(DateRange r) {
    if (r.to.difference(r.from).inDays + 1 > _maxDays) {
      showSheetSnack(context, 'الفترة حتى $_maxDays يوماً — اختر فترةً أقصر', isError: true);
      return;
    }
    setState(() => _transfers ? _transfersRange = r : _walletRange = r);
    _reload();
  }

  void _pickSuggestion(({String? customerId, String name, String? username}) s) {
    final u = s.username;
    if (u == null || u.isEmpty) return;
    setState(() {
      _q = u;
      _qGen++;
    });
    _reload();
  }

  Future<void> _openFilters() async {
    if (_lk == null) {
      NationalPortalApi.lookups().then((v) {
        if (mounted && v != null) setState(() => _lk = v);
      });
    }
    final v = await showNationalFilters(context, sections: [
      NationalFilterSection(
        key: 'type',
        title: 'نوع الحركة',
        value: _f['type'] ?? '',
        options: _lk?.transactionTypes?.map((x) => NationalChoice(x.id, nationalTxTypes[x.id] ?? x.name)).toList() ??
            nationalTxTypes.entries.take(8).map((e) => NationalChoice(e.key, e.value)).toList(),
      ),
      NationalFilterSection(
        key: 'wallet',
        title: 'نوع المحفظة',
        value: _f['wallet'] ?? '',
        options: const [NationalChoice('main', 'الرئيسي'), NationalChoice('commission', 'العمولة')],
      ),
      if (_transfers) ...[
        NationalFilterSection(
          key: 'owner',
          title: 'مالك المحفظة',
          value: _f['owner'] ?? '',
          options: const [NationalChoice('partner', 'الوكلاء'), NationalChoice('customer', 'المشتركين')],
        ),
        NationalFilterSection(
          key: 'method',
          title: 'طريقة الدفع',
          value: _f['method'] ?? '',
          options: const [
            NationalChoice('wallet', 'محفظة'),
            NationalChoice('card', 'بطاقة دفع'),
            NationalChoice('balancecard', 'بطاقة رصيد'),
            NationalChoice('cash', 'نقد'),
            NationalChoice('fastpay', 'فاست باي'),
          ],
        ),
      ],
      NationalFilterSection(
        key: 'change',
        title: 'نوع التغيير',
        value: _f['change'] ?? '',
        options: const [NationalChoice('scheduled', 'مجدول'), NationalChoice('instant', 'فوري')],
      ),
      NationalFilterSection(
        key: 'sales',
        title: 'نوع الدفع',
        value: _f['sales'] ?? '',
        options: const [NationalChoice('upfront', 'دفعة واحدة'), NationalChoice('installment', 'دفعات شهرية')],
      ),
      NationalFilterSection(
        key: 'by',
        title: 'المنفّذ',
        value: _f['by'] ?? '',
        options: const [NationalChoice('me', 'أنا وحدي')],
      ),
      NationalFilterSection.text(key: 'tx', title: 'رقم المعاملة', value: _f['tx'] ?? '', hint: 'كما في البوّابة', digits: true),
      NationalFilterSection.text(key: 'sub', title: 'رقم الاشتراك', value: _f['sub'] ?? '', hint: 'المعرّف في البوّابة', digits: true),
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
          title: Text('محفظتي', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
          iconTheme: IconThemeData(color: AppColors.textHi),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
            children: [
              if (_meta.cap('transfers')) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('محفظتي'), icon: Icon(LucideIcons.walletCards, size: 16)),
                    ButtonSegment(value: true, label: Text('التحويلات'), icon: Icon(LucideIcons.arrowLeftRight, size: 16)),
                  ],
                  selected: {_transfers},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    setState(() {
                      _transfers = s.first;
                      _f = {..._f, 'owner': '', 'method': ''};
                    });
                    _reload();
                  },
                ),
                const SizedBox(height: Sp.md),
              ],
              _BalanceCard(meta: _meta, total: _p.total, busy: _p.loading || _p.pending, transfers: _transfers),
              const SizedBox(height: Sp.md),
              DateRangeChipBar(value: _range, presets: _presets, onChanged: _setRange),
              // خادمٌ أقدم (v1) لا يفهم المجموعات ولا بحث «محفظتي» وأغلب فلاترها ⇒ لا شرائح ولا بحث ولا «الفلاتر» تَعِد بفرزٍ لا يقع
              if (_v2 != false) ...[
                const SizedBox(height: Sp.sm),
                _GroupChips(
                  value: _group,
                  onChanged: (g) {
                    setState(() => _group = g);
                    _reload();
                  },
                ),
                const SizedBox(height: Sp.md),
                Row(
                  children: [
                    Expanded(
                      child: NationalSearchField(
                        key: ValueKey('q$_qGen'),
                        hint: 'رمز الاشتراك أو الاسم',
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
      if (_p.error != null) return [NationalStateBox.error(text: _p.error!, onRetry: _reload)];
      if (_p.pending) return const [NationalStateBox.pending()];
      if (_p.loading || _p.page == 0) return const [NationalStateBox.loading()];
      final amb = _last.ambiguous;
      if (amb != null && amb.isNotEmpty) return [_AmbiguousBox(items: amb, onPick: _pickSuggestion)];
      return [
        NationalStateBox.empty(
          text: _q.isEmpty && _active == 0 && _group.isEmpty
              ? 'لا توجد حركات في هذه الفترة — جرّب فترةً أطول'
              : 'لا حركات تطابق البحث أو الفلاتر في هذه الفترة',
          icon: LucideIcons.receipt,
        ),
      ];
    }
    return [
      for (final r in _p.rows) ...[
        _WalletRowCard(r: r, transfers: _transfers),
        const SizedBox(height: Sp.sm),
      ],
      if (_p.hasMore)
        NationalLoadMore(loading: _p.loading, onTap: _next, shown: _p.rows.length, total: _p.total, unit: 'حركة'),
    ];
  }
}

/// رصيد المحفظة (أو «حدّ المحفظة») ورصيد العمولة وعدد حركات الفترة — ما لا يُعرف «—» لا صفر.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.meta, required this.total, required this.busy, required this.transfers});
  final NationalWalletMeta meta;
  final int? total;
  final bool busy;
  final bool transfers;

  String _money(num? v) => v == null ? (busy ? '…' : '—') : formatIQD(v);

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final limited = meta.limit != null;
    final showCommission = meta.cap('commission') || (meta.commission != null && meta.commission != 0);
    final count = total == null ? (busy ? '…' : '—') : '$total';
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
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.successSoftBg, borderRadius: BorderRadius.circular(R.icon)),
                child: Icon(LucideIcons.wallet, color: AppColors.success, size: 20),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(limited ? 'حدّ المحفظة' : 'رصيد المحفظة', style: AppType.muted()),
                    const SizedBox(height: 2),
                    Text(
                      _money(limited ? meta.limit : meta.balance),
                      textDirection: TextDirection.ltr,
                      style: AppType.statValue(color: AppColors.textHi),
                    ),
                  ],
                ),
              ),
              if (showCommission) ...[
                Container(width: 1, height: 36, color: AppColors.divider),
                const SizedBox(width: Sp.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('رصيد العمولة', style: AppType.muted()),
                    const SizedBox(height: 2),
                    Text(
                      _money(meta.commission),
                      textDirection: TextDirection.ltr,
                      style: AppType.amount(color: AppColors.textHi).copyWith(fontSize: 15),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const SizedBox(height: Sp.sm),
          Text(
            transfers ? 'حركات التحويلات في الفترة: $count' : 'حركات محفظتي في الفترة: $count',
            style: AppType.micro(color: AppColors.textMid),
          ),
        ],
      ),
    );
  }
}

/// المجموعات السريعة سطراً واحداً يمرّر أفقيّاً (لا شريطٌ يكبر).
class _GroupChips extends StatelessWidget {
  const _GroupChips({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final items = [(key: '', label: 'الكلّ'), ...nationalTxGroups];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final it = items[i];
          final on = value == it.key;
          return ChoiceChip(
            label: Text(it.label),
            selected: on,
            onSelected: (_) => onChanged(it.key),
            labelStyle: AppType.label(color: on ? AppColors.brand : AppColors.textHi),
            selectedColor: AppColors.brandSoftBg,
            backgroundColor: AppColors.surface,
            side: BorderSide(color: on ? AppColors.brandSoftBorder : AppColors.border),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.pill)),
          );
        },
      ),
    );
  }
}

/// الاسم يطابق أكثر من مشترك ⇒ اختر واحداً (برمز اشتراكه) — لا تخمين.
class _AmbiguousBox extends StatelessWidget {
  const _AmbiguousBox({required this.items, required this.onPick});
  final List<({String? customerId, String name, String? username})> items;
  final ValueChanged<({String? customerId, String name, String? username})> onPick;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.sm),
          child: Text('أكثر من مشترك بهذا الاسم — اختر واحداً:', style: AppType.label(color: AppColors.textLabel)),
        ),
        NationalInfoGroup(
          children: [
            for (final it in items)
              InkWell(
                onTap: (it.username ?? '').isEmpty ? null : () => onPick(it),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      Icon(LucideIcons.user, size: 16, color: AppColors.textMid),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: Text(
                          it.name.isEmpty ? '—' : it.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.rowValue(color: AppColors.textHi),
                        ),
                      ),
                      if ((it.username ?? '').isNotEmpty)
                        Text(it.username!, textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

const _activationTypes = {
  'PLAN_RENEW', 'AUTO_RENEW', 'PLAN_C_RENEW', 'PLAN_EMI_RENEW', 'PLAN_PURCHASE', 'PLAN_PURCHASE_S', 'PLAN_CHANGE', //
  'PLAN_SCHEDULE', 'PLAN_REACTIVATE',
};
const _refundTypes = {
  'WALLET_REFUND', 'WALLET_REVERSAL', 'RENEW_REVERSAL', 'PURCHASE_REVERSAL', 'CHANGE_REVERSAL', 'TOPUP_INVOICE_REFUND', //
  'SHOP_CASH_WALLET_REFUND',
};

AppTone _toneOf(NationalMoneyRow r) {
  final t = r.type.toUpperCase();
  if (_activationTypes.contains(t)) return AppTone.brand;
  if (_refundTypes.contains(t)) return AppTone.warning;
  if (r.isCommission || t.contains('COMM')) return AppTone.info;
  if (t.startsWith('WALLET_') || t.contains('TOPUP') || t.startsWith('BAL_CARD')) return AppTone.success;
  return AppTone.neutral;
}

/// صفّ حركة: المبلغ بإشارته (إيداعٌ أخضر، سحبٌ أحمر)، والمشترك ورمز اشتراكه، والنوع، والرصيد بعدها (رصيد العمولة لصفوفها)، وسطر
/// الباقة، و«المنفّذ»، و«من … إلى …» للتحويل.
class _WalletRowCard extends StatelessWidget {
  const _WalletRowCard({required this.r, required this.transfers});
  final NationalMoneyRow r;
  final bool transfers;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final amt = r.amount;
    final sign = r.isOut ? '−' : (r.isIn ? '+' : '');
    final amtColor = r.isOut ? AppColors.error : (r.isIn ? AppColors.success : AppColors.textHi);
    final type = nationalTxType(r.type);
    final title = r.customer?.name ?? (r.transferTo?.name ?? type);
    String day(String? v) => v == null || v.length < 10 ? (v ?? '') : v.substring(0, 10);
    final method = nationalPayMethod(r.payMethod.isNotEmpty ? r.payMethod : r.method);
    // كلّ مقطعٍ معزولٌ وحده (اسم الباقة والتاريخ لاتينيّان داخل سطرٍ عربيّ — بلاه يُقلب «2026-11-30» إلى «30-11-2026»)
    final plan = [
      if ((r.planName ?? '').isNotEmpty) iso(r.planName!),
      if ((r.ends ?? '').isNotEmpty) 'ينتهي ${iso(day(r.ends))}',
      if (r.discount != null && r.discount! > 0) 'خصم ${iso(formatIQD(r.discount!))}',
    ];
    final transfer = r.transferFrom != null || r.transferTo != null
        ? 'من ${r.transferFrom?.name ?? '—'} إلى ${r.transferTo?.name ?? '—'}'
        : null;
    final by = switch (r.by) {
      'me' => 'المنفّذ: أنت',
      'team' => 'المنفّذ: مستخدمٌ آخر لحسابك',
      _ => null,
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
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.listName(color: AppColors.textHi)),
                    if (r.username != null)
                      Text(r.username!, textDirection: TextDirection.ltr, style: AppType.micro(color: AppColors.textMid)),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amt == null ? '—' : '$sign${formatIQD(amt.abs())}',
                    textDirection: TextDirection.ltr,
                    style: AppType.amount(color: amtColor).copyWith(fontSize: 15),
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
              ToneChip(label: type, tone: _toneOf(r), dense: true),
              if (r.isCommission) const ToneChip(label: 'العمولة', tone: AppTone.info, dense: true),
              if (r.changeType == 'Scheduled') ToneChip(label: nationalChangeType(r.changeType), tone: AppTone.warning, dense: true),
              if (transfers && r.owner.isNotEmpty) ToneChip(label: nationalWalletOwner(r.owner), dense: true),
              if (method != '—') Text(method, style: AppType.micro(color: AppColors.textMid)),
              if (r.balanceAfter != null && !transfers)
                Text(
                  '${r.isCommission ? 'رصيد العمولة بعدها' : 'الرصيد بعدها'} ${iso(formatIQD(r.balanceAfter!))}',
                  style: AppType.micro(color: AppColors.textMid),
                ),
            ],
          ),
          if (plan.isNotEmpty || transfer != null || by != null) ...[
            const SizedBox(height: 6),
            Text(
              [if (plan.isNotEmpty) plan.join(' · '), if (transfer != null) transfer, if (by != null) by].join('\n'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.micro(color: AppColors.textMid),
            ),
          ],
        ],
      ),
    );
  }
}
