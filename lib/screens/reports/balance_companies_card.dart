import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/balance_reports_api.dart';
import '../../models/merged_company.dart';
import '../../services/merged_mode.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'v2/report_kit.dart';

/// «تقارير الأرصدة» بـ«كل الشركات» و«الكل» في الشريط (٢٢ نوفمبر — بند المقترح: «فتراتها تبقى مثل ما هي. بـ«كل الشركات» يظهر جدول
/// المحصَّل والمتبقّي والربح لكلّ شركة»): لكلّ شركةٍ فترتها الجارية (الأحدث) بأرقامها كما يحسبها الخادم — لا جمع فتراتٍ مختلفة
/// التواريخ في رقمٍ يوهم أنّه فترةٌ واحدة إلّا بسطر «المجموع» المعنون. شحنٌ بلا مبلغ ⇒ المتبقّي والربح «—» (لا صفر)، ومجموعهما «—»
/// إن جهلت شركة. المتعذّرة تُسمّى ولا تُجمع؛ وغير المفعّلة أو بلا شحنٍ مسجَّل سطرٌ هادئ تحته. لمسة شركة ⇒ تُعرض وحدها في القسم.
class BalanceCompaniesCard extends StatefulWidget {
  const BalanceCompaniesCard({super.key, required this.companies, this.onPick});

  /// الشركات التي يخدمها القسم (ساس، ايرث لنك، المُضافة).
  final List<MergedCompany> companies;
  final ValueChanged<MergedCompany>? onPick;

  @override
  State<BalanceCompaniesCard> createState() => _BalanceCompaniesCardState();
}

class _Line {
  _Line(this.c, {this.data, this.error, this.loading = false});
  final MergedCompany c;
  final BalanceOverview? data;
  final String? error;
  final bool loading;
}

class _BalanceCompaniesCardState extends State<BalanceCompaniesCard> {
  final _lines = <String, _Line>{};
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final seq = ++_seq;
    final cs = widget.companies;
    setState(() {
      _lines.clear();
      for (final c in cs) {
        _lines[c.key] = _Line(c, loading: true);
      }
    });
    // اثنتين اثنتين — لوحة كلّ شركةٍ حسابٌ كامل عند الخادم
    var next = 0;
    Future<void> worker() async {
      while (next < cs.length) {
        final c = cs[next++];
        await _one(c, seq);
        if (!mounted || seq != _seq) return;
      }
    }

    await Future.wait([for (var w = 0; w < 2 && w < cs.length; w++) worker()]);
  }

  Future<void> _one(MergedCompany c, int seq) async {
    final r = await BalanceReportsApi.overview(companyKey: c.key);
    if (!mounted || seq != _seq) return;
    setState(() => _lines[c.key] = _Line(c, data: r.ok ? r.data : null, error: r.ok ? null : (r.message ?? 'تعذّر تحميل تقارير الأرصدة')));
  }

  RpCompany _rp(MergedCompany c, {String? note}) => RpCompany(key: c.key, name: c.name, colorIndex: c.colorIndex, note: note);

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final lines = <RpCompanyLine>[];
    final outside = <String>[];
    final quiet = <String>[];
    var unknownRemaining = false, unknownProfit = false;
    num collected = 0, remaining = 0, profit = 0;
    for (final l in _lines.values) {
      if (l.loading) {
        lines.add(RpCompanyLine(company: _rp(l.c), state: RpCompanyState.loading));
        outside.add('${l.c.name} (تُقرأ)');
        continue;
      }
      final d = l.data;
      if (d == null) {
        lines.add(RpCompanyLine(company: _rp(l.c, note: l.error), state: RpCompanyState.failed));
        outside.add('${l.c.name} (${l.error ?? 'تعذّرت'})');
        continue;
      }
      if (!d.featureEnabled) {
        quiet.add('«${l.c.name}» غير مفعّلة');
        continue;
      }
      if (d.periods.isEmpty) {
        quiet.add('«${l.c.name}» بلا شحنٍ مسجَّل');
        continue;
      }
      final p = d.periods.first;
      final iqd = l.c.currency == null || l.c.currency == 'IQD';
      if (!iqd) {
        quiet.add('«${l.c.name}» بعملتها (${l.c.currency}) — خارج المجموع');
      }
      lines.add(RpCompanyLine(
        company: _rp(l.c),
        a: p.collected,
        b: p.amountPending ? null : p.remaining,
        c: p.amountPending ? null : p.profit,
      ));
      if (!iqd) continue;
      collected += p.collected;
      if (p.amountPending) {
        unknownRemaining = true;
        unknownProfit = true;
      } else {
        remaining += p.remaining;
        profit += p.profit;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RpSortedCompanyTable(
          sortKey: 'balances',
          heads: const ['المحصَّل', 'المتبقّي', 'ربحك'],
          tones: const [RpTone.money, RpTone.debt, RpTone.brand],
          lines: lines,
          total: [collected, unknownRemaining ? null : remaining, unknownProfit ? null : profit],
          outside: outside.isEmpty ? null : 'خارج المجموع الآن: ${outside.join(' · ')}',
          onTap: widget.onPick == null
              ? null
              : (c) {
                  final m = MergedMode.companyOf(c.key);
                  if (m != null) widget.onPick!(m);
                },
          onRetry: (c) {
            final m = _lines[c.key]?.c;
            if (m == null) return;
            setState(() => _lines[c.key] = _Line(m, loading: true));
            unawaited(_one(m, _seq));
          },
        ),
        const SizedBox(height: Sp.x6),
        Text(
          [
            'لكلّ شركةٍ فترتها الجارية — تواريخها تختلف بين الشركات',
            if (unknownRemaining) 'شحنٌ بلا مبلغ ⇒ متبقّيه وربحه «—» حتى يُكتب',
            ...quiet,
          ].join(' · '),
          style: AppType.micro(color: AppColors.textLow),
        ),
      ],
    );
  }
}
