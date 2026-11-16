import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/balance_reports_api.dart';
import '../../core/platform/desktop_layout.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'balance_period_screen.dart';

/// «تقارير الأرصدة» (١٥ نوفمبر — المالك: «في قسم التقارير نفتح قسم خاص… تقارير الأرصدة» + «اهتم بالتصميم وعرض التفاصيل بوضع
/// الويب والتطبيق»): فترةٌ لكلّ شحنة رصيد — «هذا ربحك، هذا الإجمالي اللي طبّلك، هذا اللي معوز حتى يوصل للسقف»، «تسوية الرصيد»،
/// ثمّ الإغلاق، وما يتسدّد من ديون الفترة بعد إغلاقها ربح. كلّ رقمٍ من الخادم، والكتابة تعيد اللوحة محدَّثةً فلا يُعرض رقمٌ قديم.

AppTone balanceToneOf(BalanceTone t) => switch (t) {
      BalanceTone.success => AppTone.success,
      BalanceTone.warning => AppTone.warning,
      BalanceTone.danger => AppTone.danger,
      BalanceTone.brand => AppTone.brand,
      BalanceTone.neutral => AppTone.neutral,
    };

AppTone balanceStateTone(BalanceState s) => switch (s) {
      BalanceState.running => AppTone.brand,
      BalanceState.waiting => AppTone.warning,
      BalanceState.closed => AppTone.neutral,
    };

/// لوحة القسم بين الشاشتين (القائمة وتفاصيل الفترة): ما يكتبه أحدهما يراه الآخر فوراً.
class BalanceReportsController extends ChangeNotifier {
  BalanceOverview? data;
  String? error;
  bool loading = true;

  /// رصيد الوكيل الآن عند شركته، أو null إن لم يُعرف.
  double? live;

  /// يزيد مع كلّ لوحةٍ جديدة — قوائم الحركات تعيد قراءتها.
  int version = 0;
  bool _disposed = false;

  BalancePeriod? get current => (data?.periods.isNotEmpty ?? false) ? data!.periods.first : null;

  Future<void> load() async {
    final r = await BalanceReportsApi.overview();
    if (_disposed) return;
    loading = false;
    if (r.ok) {
      apply(r.data!);
      // الرصيد يُسأل حين تكون الفترة جاريةً وحدها (لنقول «رصيدك خلص» بعلم)
      if (current?.state == BalanceState.running) {
        final b = await BalanceReportsApi.liveBalance();
        if (_disposed) return;
        live = b;
        notifyListeners();
      }
    } else {
      error = r.message ?? 'تعذّر تحميل تقارير الأرصدة';
      notifyListeners();
    }
  }

  void apply(BalanceOverview o) {
    data = o;
    error = null;
    loading = false;
    version++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class BalanceReportsScreen extends StatefulWidget {
  const BalanceReportsScreen({super.key});

  @override
  State<BalanceReportsScreen> createState() => _BalanceReportsScreenState();
}

class _BalanceReportsScreenState extends State<BalanceReportsScreen> {
  final _c = BalanceReportsController();

  @override
  void initState() {
    super.initState();
    _c.load();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _new() async {
    final o = await showBalanceTopupSheet(context);
    if (o != null) _c.apply(o);
  }

  void _detail(BalancePeriod p) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => BalancePeriodScreen(controller: _c, periodId: p.id)));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final desktop = DesktopScope.of(context);
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final data = _c.data;
        final on = data?.featureEnabled ?? false;
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.bg,
            title: Text('تقارير الأرصدة', style: AppType.title(color: AppColors.textHi)),
            actions: [
              if (on && desktop)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: Sp.md),
                  child: TextButton.icon(key: const ValueKey('bal-new'), onPressed: _new, icon: const Icon(LucideIcons.plus, size: 16), label: const Text('شحنة جديدة')),
                ),
            ],
          ),
          floatingActionButton: on && !desktop && data!.periods.isNotEmpty
              ? FloatingActionButton.extended(
                  key: const ValueKey('bal-new'),
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.onBrand,
                  onPressed: _new,
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('شحنة جديدة'),
                )
              : null,
          body: SafeArea(child: _body(data)),
        );
      },
    );
  }

  Widget _body(BalanceOverview? data) {
    if (data == null) {
      if (_c.loading) return const Center(child: CircularProgressIndicator());
      return _Message(
        key: const ValueKey('bal-error'),
        icon: LucideIcons.triangleAlert,
        tone: AppTone.danger,
        title: 'تعذّر تحميل تقارير الأرصدة',
        body: _c.error ?? 'حاول بعد قليل',
        action: 'أعد المحاولة',
        actionKey: const ValueKey('bal-retry'),
        onAction: () {
          setState(() => _c.loading = true);
          _c.load();
        },
      );
    }
    if (!data.featureEnabled) {
      return const _Message(key: ValueKey('bal-off'), icon: LucideIcons.walletCards, tone: AppTone.neutral, title: 'تقارير الأرصدة غير مفعّلة لحسابك بعد', body: 'راسل الدعم لتفعيلها.');
    }
    if (data.periods.isEmpty) {
      return _Message(
        key: const ValueKey('bal-empty'),
        icon: LucideIcons.walletCards,
        tone: AppTone.brand,
        title: 'سجّل أوّل شحنة رصيد',
        body: 'اكتب تاريخ الشحنة ومبلغها، والنظام يحسب من سجلّاته شگد طبّلك منها وشگد باقي حتى يرجع مبلغها — حتى لو تاريخها قديم.',
        action: 'شحنة جديدة',
        actionKey: const ValueKey('bal-first'),
        onAction: _new,
      );
    }
    final periods = data.periods;
    final outside = data.outside;
    final notes = data.qualityNotes;
    return RefreshIndicator(
      onRefresh: _c.load,
      color: AppColors.brand,
      child: ListView(
        key: const ValueKey('bal-list'),
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, 96),
        children: [
          Text('لكلّ شحنة رصيد: شگد طبّلك منها، شگد معوز حتى يرجع مبلغها، وشگد ربحك', style: AppType.muted(color: AppColors.textMid)),
          const SizedBox(height: Sp.md),
          BalancePeriodHero(period: periods.first, live: _c.live, controller: _c, onDetail: () => _detail(periods.first)),
          if (periods.length > 1) ...[
            const SizedBox(height: Sp.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
              child: Text('الفترات السابقة', style: AppType.bodyBold(color: AppColors.textHi)),
            ),
            const SizedBox(height: Sp.sm),
            for (final p in periods.skip(1)) ...[
              _PeriodCard(key: ValueKey('bal-period-${p.id}'), period: p, controller: _c, onDetail: () => _detail(p)),
              const SizedBox(height: Sp.sm),
            ],
          ],
          if (outside.isNotEmpty || notes.isNotEmpty) ...[
            const SizedBox(height: Sp.lg),
            _Panel(
              key: const ValueKey('bal-outside'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (outside.isNotEmpty) ...[
                    Text('خارج حساب الشحنات', style: AppType.bodyBold(color: AppColors.textHi)),
                    const SizedBox(height: 2),
                    Text('مبالغ دخلت من غير تفعيلات الفترات — ما تدخل بمبلغ أيّ شحنة.', style: AppType.micro(color: AppColors.textMid)),
                    const SizedBox(height: Sp.sm),
                    for (final o in outside) BalanceLine(key: ValueKey('bal-outside-${o.id}'), label: o.label, value: balanceIqd(o.value)),
                  ],
                  for (final n in notes)
                    Padding(
                      padding: const EdgeInsets.only(top: Sp.x6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.triangleAlert, size: 13, color: AppTone.warning.onSoft)),
                          const SizedBox(width: Sp.x6),
                          Expanded(child: Text(n, key: const ValueKey('bal-quality'), style: AppType.micro(color: AppTone.warning.onSoft))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────── قطع مشتركة ───────────────────────────

class _Message extends StatelessWidget {
  const _Message({super.key, required this.icon, required this.tone, required this.title, required this.body, this.action, this.actionKey, this.onAction});
  final IconData icon;
  final AppTone tone;
  final String title;
  final String body;
  final String? action;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Sp.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.lg)),
              child: Icon(icon, size: 24, color: tone.fill),
            ),
            const SizedBox(height: Sp.lg),
            Text(title, textAlign: TextAlign.center, style: AppType.cardTitleBold(color: AppColors.textHi)),
            const SizedBox(height: Sp.x6),
            Text(body, textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
            if (action != null) ...[
              const SizedBox(height: Sp.lg),
              FilledButton.icon(
                key: actionKey,
                onPressed: onAction,
                icon: Icon(onAction == null ? LucideIcons.loader : LucideIcons.plus, size: 16),
                label: Text(action!),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size(180, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// كرتٌ بسطح التطبيق وحدّه.
class _Panel extends StatelessWidget {
  const _Panel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.card), side: BorderSide(color: AppColors.border)),
        child: Padding(padding: const EdgeInsets.all(Sp.lg), child: child),
      );
}

/// سطر «تسمية ← قيمة»: التسمية تلتفّ والقيمة لا تُقصّ (تصغر إن ضاق السطر).
class BalanceLine extends StatelessWidget {
  const BalanceLine({super.key, required this.label, required this.value, this.strong = false, this.valueColor});
  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final style = strong ? AppType.bodyBold(color: AppColors.textHi) : AppType.body(color: AppColors.textMid);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, maxLines: 3, overflow: TextOverflow.ellipsis, style: style)),
            const SizedBox(width: Sp.md),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.55),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(
                  value,
                  maxLines: 1,
                  style: (strong ? AppType.bodyBold(color: valueColor ?? AppColors.textHi) : AppType.bodyStrong(color: valueColor ?? AppColors.textBody))
                      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ما اكتمل من مبلغ الشحنة: الأخضر ما دخل («طبّلك»)، ولون العلامة ما أضافه بـ«تسوية الرصيد».
class BalanceProgress extends StatelessWidget {
  const BalanceProgress({super.key, required this.period, this.height = 10});
  final BalancePeriod period;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = period.amount <= 0 ? 1.0 : period.amount;
    final got = ((period.collected / total) * 1000).round().clamp(0, 1000);
    final adj = ((period.adjustmentsSum / total) * 1000).round().clamp(0, 1000 - got);
    final rest = 1000 - got - adj;
    return Semantics(
      label: 'اكتمل ${(period.progress * 100).round()}% من مبلغ الشحنة',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(R.pill),
        child: SizedBox(
          height: height,
          // stretch: مربّعٌ ملوَّن بلا ابنٍ يأخذ أصغر ارتفاعٍ يُسمح به — بلا التمديد يصير صفراً ولا يُرى الشريط
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (got > 0) Expanded(flex: got, child: ColoredBox(color: AppColors.success)),
              if (adj > 0) Expanded(flex: adj, child: ColoredBox(color: AppColors.brandAccent)),
              if (rest > 0) Expanded(flex: rest, child: ColoredBox(color: AppColors.surfaceSunken)),
            ],
          ),
        ),
      ),
    );
  }
}

/// كرت رقم: الأيقونة والعنوان سطر، والرقم تحتهما بعرض الكرت — يصغر ولا يُقصّ، وتحته سطورٌ قصيرة.
class _Stat extends StatelessWidget {
  const _Stat({super.key, required this.icon, required this.tone, required this.label, required this.value, this.lines = const []});
  final IconData icon;
  final AppTone tone;
  final String label;
  final String value;
  final List<String?> lines;

  @override
  Widget build(BuildContext context) {
    final subs = lines.whereType<String>().where((x) => x.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.icon)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.sm)),
                child: Icon(icon, size: 14, color: tone.fill),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid))),
            ],
          ),
          const SizedBox(height: Sp.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: AppType.rowValue(color: AppColors.textHi).copyWith(fontSize: 17, fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          if (subs.isNotEmpty) ...[
            const SizedBox(height: Sp.x6),
            Divider(height: 1, thickness: 1, color: AppColors.divider),
            const SizedBox(height: Sp.x6),
            for (final s in subs) Text(s, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
          ],
        ],
      ),
    );
  }
}

/// الأرقام الأربعة: طبّلك · المعوز · ديون الفترة · ربحك.
class BalanceStats extends StatelessWidget {
  const BalanceStats({super.key, required this.period});
  final BalancePeriod period;

  @override
  Widget build(BuildContext context) {
    final p = period;
    final mg = p.managers;
    final profitSub = p.pocketOutstanding > 0
        ? 'دفعت ${formatIQD(p.pocketOutstanding)} بالتسوية وبعدها ما رجعت'
        : p.isClosed && p.lateProfit > 0
            ? 'منها بعد الإغلاق ${formatIQD(p.lateProfit)}'
            : p.net < 0
                ? 'يبدي بعد ما يرجع مبلغ الشحنة'
                : null;
    Widget pair(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [Expanded(child: a), const SizedBox(width: Sp.sm), Expanded(child: b)],
          ),
        );
    return Column(
      children: [
        pair(
          _Stat(
            key: const ValueKey('bal-stat-collected'),
            icon: LucideIcons.handCoins,
            tone: AppTone.success,
            label: 'طبّلك',
            value: balanceIqd(p.collected),
            lines: [
              'نقد التفعيلات ${formatIQD(p.cashNow)}',
              'تسديد ديونها ${formatIQD(p.paidIn)}',
              // المدراء الفرعيّون داخل الرقم (حين يفتح الخادم مفتاحهم): ما دخل منهم، وما رُدّ لهم بالسحب
              if (mg != null && mg.cash + mg.paidIn > 0) 'من المدراء الفرعيّين ${formatIQD(mg.cash + mg.paidIn)}',
              if (mg != null && mg.withdrawn > 0) 'ناقص سحبٍ من المدراء ${formatIQD(mg.withdrawn)}',
            ],
          ),
          p.remaining > 0
              ? _Stat(
                  key: const ValueKey('bal-stat-remaining'),
                  icon: LucideIcons.scale,
                  tone: AppTone.warning,
                  label: 'المعوز',
                  value: balanceIqd(p.remaining),
                  lines: [p.adjustmentsSum > 0 ? 'بعد تسوية ${formatIQD(p.adjustmentsSum)}' : 'حتى يرجع مبلغ الشحنة'],
                )
              : _Stat(
                  key: const ValueKey('bal-stat-remaining'),
                  icon: LucideIcons.circleCheck,
                  tone: AppTone.success,
                  label: 'المعوز',
                  value: 'مكتمل',
                  lines: [p.adjustmentsSum > 0 ? 'منها تسوية ${formatIQD(p.adjustmentsSum)}' : 'رجع مبلغ الشحنة كاملاً'],
                ),
        ),
        const SizedBox(height: Sp.sm),
        pair(
          _Stat(
            key: const ValueKey('bal-stat-debts'),
            icon: LucideIcons.clock,
            tone: p.debtsOpen > 0 ? AppTone.danger : AppTone.success,
            label: 'ديون الفترة',
            value: balanceIqd(p.debtsOpen),
            lines: ['باقية من أصل ${formatIQD(p.debtsCreated)}', if (mg != null && mg.open > 0) 'منها على المدراء ${formatIQD(mg.open)}'],
          ),
          _Stat(key: const ValueKey('bal-stat-profit'), icon: LucideIcons.trendingUp, tone: AppTone.brand, label: 'ربحك', value: balanceIqd(p.profit), lines: [profitSub]),
        ),
      ],
    );
  }
}

class BalanceBannerBox extends StatelessWidget {
  const BalanceBannerBox({super.key, required this.kind, required this.text});
  final BalanceBannerKind kind;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tone = kind == BalanceBannerKind.done ? AppTone.success : AppTone.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
      decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(kind == BalanceBannerKind.done ? LucideIcons.circleCheck : LucideIcons.triangleAlert, size: 16, color: tone.onSoft),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(text, style: AppType.bodyBold(color: tone.onSoft))),
        ],
      ),
    );
  }
}

/// سطور «تسوية الرصيد» المسجّلة على الفترة، وحذف الواحدة ما دامت الفترة غير مغلقة.
class BalanceAdjustmentsList extends StatelessWidget {
  const BalanceAdjustmentsList({super.key, required this.period, required this.controller});
  final BalancePeriod period;
  final BalanceReportsController controller;

  @override
  Widget build(BuildContext context) {
    if (period.adjustments.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(R.md), border: Border.all(color: AppColors.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surfaceSunken,
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.x6),
            child: Text('تسويات الرصيد', style: AppType.microBold(color: AppColors.textHi)),
          ),
          for (final a in period.adjustments) ...[
            Divider(height: 1, thickness: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Sp.md, end: Sp.xs, top: Sp.x6, bottom: Sp.x6),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${a.source.label} · ${balanceDay(a.createdAtMs)}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(color: AppColors.textHi)),
                        if (a.note != null) Text(a.note!, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textBody)),
                      ],
                    ),
                  ),
                  const SizedBox(width: Sp.sm),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(balanceIqd(a.amount), maxLines: 1, style: AppType.bodyBold(color: AppColors.textHi).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ),
                  if (!period.isClosed)
                    IconButton(
                      key: ValueKey('bal-unadjust-${a.id}'),
                      tooltip: 'حذف التسوية',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(LucideIcons.trash2, size: 16, color: AppColors.textMid),
                      onPressed: () => confirmBalanceUnadjust(context, controller, period, a),
                    )
                  else
                    const SizedBox(width: Sp.sm),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// أزرار الفترة: المعوز ⇒ «تسوية الرصيد»، اكتمل ⇒ «إغلاق الفترة»، مغلقة ⇒ «إلغاء الإغلاق».
class BalanceActions extends StatelessWidget {
  const BalanceActions({super.key, required this.period, required this.controller, this.onDetail});
  final BalancePeriod period;
  final BalanceReportsController controller;
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context) {
    final p = period;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button));
    final primary = FilledButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size.fromHeight(50), shape: shape);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p.canClose)
          FilledButton.icon(
            key: ValueKey('bal-close-${p.id}'),
            onPressed: () => confirmBalanceClose(context, controller, p),
            icon: const Icon(LucideIcons.circleCheck, size: 18),
            label: const Text('إغلاق الفترة'),
            style: primary,
          ),
        if (!p.isClosed && p.remaining > 0)
          FilledButton.icon(
            key: ValueKey('bal-adjust-${p.id}'),
            onPressed: () async {
              final o = await showBalanceAdjustSheet(context, p);
              if (o != null) controller.apply(o);
            },
            icon: const Icon(LucideIcons.scale, size: 18),
            label: const Text('تسوية الرصيد'),
            style: primary,
          ),
        if (onDetail != null) ...[
          if (!p.isClosed) const SizedBox(height: Sp.sm),
          OutlinedButton.icon(
            key: ValueKey('bal-detail-${p.id}'),
            onPressed: onDetail,
            icon: const Icon(LucideIcons.listTree, size: 18),
            label: const Text('الحركات والتفاصيل'),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.textHi, minimumSize: const Size.fromHeight(50), shape: shape, side: BorderSide(color: AppColors.borderStrong)),
          ),
        ],
        if (p.isClosed) ...[
          const SizedBox(height: Sp.xs),
          TextButton.icon(
            key: ValueKey('bal-reopen-${p.id}'),
            onPressed: () => confirmBalanceReopen(context, controller, p),
            icon: const Icon(LucideIcons.undo2, size: 16),
            label: const Text('إلغاء الإغلاق'),
            style: TextButton.styleFrom(foregroundColor: AppColors.textMid),
          ),
        ],
      ],
    );
  }
}

/// الفترة الأحدث: كرتٌ كبير بكلّ أرقامها وتنبيهها وأزرارها.
class BalancePeriodHero extends StatelessWidget {
  const BalancePeriodHero({super.key, required this.period, required this.controller, this.live, this.onDetail});
  final BalancePeriod period;
  final BalanceReportsController controller;
  final double? live;
  final VoidCallback? onDetail;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final p = period;
    final banner = balanceBanner(p, live);
    final showLive = live != null && p.state == BalanceState.running;
    return _Panel(
      key: const ValueKey('bal-hero'),
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
                    Wrap(
                      spacing: Sp.sm,
                      runSpacing: Sp.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(balancePeriodTitle(p), style: AppType.cardTitleBold(color: AppColors.textHi)),
                        ToneChip(key: const ValueKey('bal-state'), label: p.state.label, tone: balanceStateTone(p.state), dense: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${balancePeriodRange(p)}${p.note == null ? '' : ' · ${p.note}'}', maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
                  ],
                ),
              ),
              if (!p.isClosed) ...[
                IconButton(
                  key: ValueKey('bal-edit-${p.id}'),
                  tooltip: 'تعديل الشحنة',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons.pencil, size: 17, color: AppColors.textMid),
                  onPressed: () async {
                    final o = await showBalanceTopupSheet(context, period: p);
                    if (o != null) controller.apply(o);
                  },
                ),
                IconButton(
                  key: ValueKey('bal-delete-${p.id}'),
                  tooltip: 'حذف الشحنة',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(LucideIcons.trash2, size: 17, color: AppColors.textMid),
                  onPressed: () => confirmBalanceDelete(context, controller, p),
                ),
              ],
            ],
          ),
          const SizedBox(height: Sp.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('مبلغ الشحنة', style: AppType.micro(color: AppColors.textMid)),
              const SizedBox(width: Sp.md),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    balanceIqd(p.amount),
                    key: const ValueKey('bal-amount'),
                    maxLines: 1,
                    style: AppType.amount(color: AppColors.textHi).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          BalanceProgress(period: p),
          const SizedBox(height: Sp.x6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'طبّلك ${formatIQD(p.collected)}${p.adjustmentsSum > 0 ? ' + تسوية ${formatIQD(p.adjustmentsSum)}' : ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.micro(color: AppColors.textMid),
                ),
              ),
              Text('${(p.progress * 100).round()}%', key: const ValueKey('bal-percent'), style: AppType.microBold(color: AppColors.textMid)),
            ],
          ),
          if (banner != null) ...[
            const SizedBox(height: Sp.md),
            BalanceBannerBox(key: const ValueKey('bal-banner'), kind: banner.kind, text: banner.text),
          ],
          const SizedBox(height: Sp.md),
          BalanceStats(period: p),
          if (showLive || p.incomeInWindow > 0 || p.transfersCount > 0) ...[
            const SizedBox(height: Sp.md),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
              decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showLive) BalanceLine(key: const ValueKey('bal-live'), label: 'رصيدك الآن عند الشركة', value: balanceIqd(live!)),
                  if (p.incomeInWindow > 0) BalanceLine(key: const ValueKey('bal-income'), label: 'دخلك خلال هذه الفترة من ديونٍ سابقة', value: balanceIqd(p.incomeInWindow)),
                  if (p.transfersCount > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        '${p.transfersCount} تحويل رصيد لمدراء فرعيّين بمبلغ ${balanceIqd(p.transfersSum)} — غير داخلة بالحساب',
                        key: const ValueKey('bal-transfers'),
                        style: AppType.micro(color: AppColors.textMid),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (p.adjustments.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            BalanceAdjustmentsList(period: p, controller: controller),
          ],
          const SizedBox(height: Sp.md),
          BalanceActions(period: p, controller: controller, onDetail: onDetail),
        ],
      ),
    );
  }
}

/// فترةٌ سابقة: كرتٌ مختصر بأهمّ أرقامها، وتفاصيلها بضغطة.
class _PeriodCard extends StatelessWidget {
  const _PeriodCard({super.key, required this.period, required this.controller, required this.onDetail});
  final BalancePeriod period;
  final BalanceReportsController controller;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final p = period;
    final facts = <({String label, String value, Color? color})>[
      (label: 'طبّلك', value: formatIQD(p.collected), color: null),
      (label: 'ديون باقية', value: formatIQD(p.debtsOpen), color: p.debtsOpen > 0 ? AppTone.danger.onSoft : null),
      p.isClosed
          ? (label: 'صافي الربح', value: '${p.net < 0 ? '−' : ''}${formatIQD(p.net.abs())}', color: p.net >= 0 ? AppTone.success.onSoft : AppTone.danger.onSoft)
          : (label: 'المعوز', value: p.remaining > 0 ? formatIQD(p.remaining) : 'مكتمل', color: p.remaining > 0 ? AppTone.warning.onSoft : AppTone.success.onSoft),
    ];
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.card), side: BorderSide(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onDetail,
            child: Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Wrap(
                          spacing: Sp.sm,
                          runSpacing: Sp.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(balancePeriodTitle(p), style: AppType.bodyBold(color: AppColors.textHi)),
                            ToneChip(label: p.state.label, tone: balanceStateTone(p.state), dense: true),
                          ],
                        ),
                      ),
                      const SizedBox(width: Sp.sm),
                      // Expanded لا Flexible: المبلغ يلزق بحافّة الكرت (Flexible يترك الفراغ الزائد بعده على الشاشة العريضة)
                      Expanded(
                        flex: 2,
                        child: FittedBox(
                          key: ValueKey('bal-period-amount-${p.id}'),
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(balanceIqd(p.amount), maxLines: 1, style: AppType.bodyBold(color: AppColors.textHi).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(balancePeriodRange(p), style: AppType.micro(color: AppColors.textMid)),
                  const SizedBox(height: Sp.sm),
                  BalanceProgress(period: p, height: 6),
                  const SizedBox(height: Sp.sm),
                  Row(
                    children: [
                      for (final f in facts)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textLow)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(f.value, maxLines: 1, style: AppType.bodyBold(color: f.color ?? AppColors.textHi).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (p.state == BalanceState.waiting)
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
              child: BalanceActions(period: p, controller: controller),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────── التأكيدات ───────────────────────────

Future<void> _runWrite(BuildContext context, BalanceReportsController c, Future<BalanceResult<BalanceOverview>> Function() send, String done, {VoidCallback? after}) async {
  final r = await send();
  if (!context.mounted) return;
  if (!r.ok) {
    showSheetSnack(context, r.message ?? 'تعذّر التنفيذ — أعد المحاولة', isError: true);
    return;
  }
  c.apply(r.data!);
  showSheetSnack(context, done);
  after?.call();
}

Future<void> confirmBalanceClose(BuildContext context, BalanceReportsController c, BalancePeriod p) async {
  final ok = await showConfirmSheet(
    context,
    title: 'إغلاق الفترة',
    subtitle: balancePeriodTitle(p),
    message: 'تغلق الفترة بمبلغها ${balanceIqd(p.amount)}؟\nبعد الإغلاق، كلّ ما يتسدّد من ديونها (${balanceIqd(p.debtsOpen)} باقية) ينحسب ربح.',
    confirmLabel: 'إغلاق الفترة',
    icon: LucideIcons.circleCheck,
  );
  if (ok != true || !context.mounted) return;
  await _runWrite(context, c, () => BalanceReportsApi.closePeriod(p.id), 'أُغلقت الفترة');
}

Future<void> confirmBalanceReopen(BuildContext context, BalanceReportsController c, BalancePeriod p) async {
  final ok = await showConfirmSheet(
    context,
    title: 'إلغاء الإغلاق',
    subtitle: balancePeriodTitle(p),
    message: 'ترجّع الفترة مفتوحة؟\nما دخل بعد إغلاقها يرجع ينحسب «طبّلك» لا ربح.',
    confirmLabel: 'إلغاء الإغلاق',
    icon: LucideIcons.undo2,
  );
  if (ok != true || !context.mounted) return;
  await _runWrite(context, c, () => BalanceReportsApi.reopenPeriod(p.id), 'رجعت الفترة مفتوحة');
}

Future<void> confirmBalanceDelete(BuildContext context, BalanceReportsController c, BalancePeriod p, {VoidCallback? after}) async {
  final ok = await showConfirmSheet(
    context,
    title: 'حذف الشحنة',
    subtitle: '${balancePeriodTitle(p)} — ${balanceIqd(p.amount)}',
    message: 'تنحذف من هذا التقرير هي وتسوياتها.\nحركات المشتركين وديونهم ما تتغيّر.',
    confirmLabel: 'حذف',
    icon: LucideIcons.trash2,
    tone: AppTone.danger,
  );
  if (ok != true || !context.mounted) return;
  await _runWrite(context, c, () => BalanceReportsApi.deletePeriod(p.id), 'حُذفت الشحنة', after: after);
}

Future<void> confirmBalanceUnadjust(BuildContext context, BalanceReportsController c, BalancePeriod p, BalanceAdjustment a) async {
  final ok = await showConfirmSheet(
    context,
    title: 'حذف التسوية',
    subtitle: '${a.source.label} — ${balanceIqd(a.amount)}',
    message: 'يرجع المعوز يزيد بقدرها.',
    confirmLabel: 'حذف التسوية',
    icon: LucideIcons.trash2,
    tone: AppTone.danger,
  );
  if (ok != true || !context.mounted) return;
  await _runWrite(context, c, () => BalanceReportsApi.removeAdjustment(p.id, a.id), 'حُذفت التسوية');
}

// ─────────────────────────── شحنة جديدة / تعديلها ───────────────────────────

/// ورقة «شحنة رصيد جديدة» (أو تعديل [period]). تُرجع اللوحة كما صارت عند الخادم، أو null إن تراجع.
Future<BalanceOverview?> showBalanceTopupSheet(BuildContext context, {BalancePeriod? period}) {
  return showAppSheet<BalanceOverview>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => BalanceTopupSheet(period: period),
  );
}

class BalanceTopupSheet extends StatefulWidget {
  const BalanceTopupSheet({super.key, this.period, this.nowMs});
  final BalancePeriod? period;

  /// للاختبار: «الآن» ثابت.
  final int? nowMs;

  @override
  State<BalanceTopupSheet> createState() => _BalanceTopupSheetState();
}

class _BalanceTopupSheetState extends State<BalanceTopupSheet> {
  late final _amountCtrl = TextEditingController(text: widget.period == null ? '' : AmountShorthand.format(widget.period!.amount.round()));
  late final _noteCtrl = TextEditingController(text: widget.period?.note ?? '');
  late DateTime _at = balanceBaghdad(widget.period?.startedAtMs ?? _now);
  bool _busy = false;

  /// مفتاحٌ واحد لهذه الورقة: إعادة الضغط أو انقطاع الشبكة لا يسجّلان الشحنة مرّتين.
  final String _ref = BalanceReportsApi.newRef('p');

  int get _now => widget.nowMs ?? DateTime.now().millisecondsSinceEpoch;
  int get _amount => AmountShorthand.expand(AmountShorthand.parse(_amountCtrl.text));
  int get _ms => balanceMsFromBaghdad(_at.year, _at.month, _at.day, _at.hour, _at.minute);

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String? get _problem {
    if (_amount <= 0) return 'اكتب مبلغ الشحنة';
    if (_ms > _now + 5 * 60 * 1000) return 'تاريخ الشحنة لا يكون في المستقبل';
    return null;
  }

  Future<void> _pickDate() async {
    final today = balanceBaghdad(_now);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_at.year, _at.month, _at.day),
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(today.year, today.month, today.day),
      helpText: 'تاريخ الشحنة',
      cancelText: 'رجوع',
      confirmText: 'تمام',
    );
    if (picked != null && mounted) setState(() => _at = DateTime.utc(picked.year, picked.month, picked.day, _at.hour, _at.minute));
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _at.hour, minute: _at.minute),
      helpText: 'وقت الشحنة',
      cancelText: 'رجوع',
      confirmText: 'تمام',
    );
    if (picked != null && mounted) setState(() => _at = DateTime.utc(_at.year, _at.month, _at.day, picked.hour, picked.minute));
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_problem != null || _busy) return;
    final p = widget.period;
    final amount = _amount;
    final ms = _ms;
    setState(() => _busy = true);
    final r = p == null
        ? await BalanceReportsApi.createPeriod(amount: amount, startedAtMs: ms, note: _noteCtrl.text, clientRef: _ref)
        : await BalanceReportsApi.updatePeriod(p.id, amount: amount, startedAtMs: ms == p.startedAtMs ? null : ms, note: _noteCtrl.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? (p == null ? 'تعذّر تسجيل الشحنة' : 'تعذّر حفظ التعديل'), isError: true);
      return;
    }
    Navigator.of(context).pop(r.data);
    showSheetSnack(context, p == null ? 'سُجّلت الشحنة ${balanceIqd(amount)}' : 'حُفظ تعديل الشحنة');
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final edit = widget.period != null;
    final problem = _problem;
    final time = '${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}';
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.walletCards,
        title: edit ? 'تعديل الشحنة' : 'شحنة رصيد جديدة',
        subtitle: 'المبلغ اللي دفعته للشركة — هو السقف اللي لازم يرجع',
        subtitleMaxLines: 2,
        onClose: _busy ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('bal-topup-save'),
        label: _busy ? 'جاري الحفظ...' : (problem ?? (edit ? 'حفظ التعديل' : 'تسجيل الشحنة — ${balanceIqd(_amount)}')),
        icon: LucideIcons.check,
        busy: _busy,
        enabled: problem == null,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: 'مبلغ الشحنة',
            child: SheetBox(
              focused: _amount > 0,
              child: AmountTextField(key: const ValueKey('bal-topup-amount'), controller: _amountCtrl, enabled: !_busy, autofocus: !edit, onValue: (_) => setState(() {})),
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'تاريخ الشحنة ووقتها',
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _PickBox(key: const ValueKey('bal-topup-date'), icon: LucideIcons.calendarDays, text: balanceDay(_ms, nowMs: _now), onTap: _busy ? null : _pickDate),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  flex: 2,
                  child: _PickBox(key: const ValueKey('bal-topup-time'), icon: LucideIcons.clock, text: time, ltr: true, onTap: _busy ? null : _pickTime),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.sm),
          Text('النظام يحسب من هذا الوقت كلّ تفعيل (نقدي، آجل، جزئي) وتسديد ديونه. بيع الموادّ والصرفيات ما تدخل.', style: AppType.muted(color: AppColors.textHint)),
          const SizedBox(height: Sp.lg),
          SheetNoteField(controller: _noteCtrl, hint: 'ملاحظة (اختياريّ)', maxLength: 200, enabled: !_busy),
        ],
      ),
    );
  }
}

class _PickBox extends StatelessWidget {
  const _PickBox({super.key, required this.icon, required this.text, this.onTap, this.ltr = false});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;
  final bool ltr;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.lg),
        child: SheetBox(
          child: Row(
            children: [
              Icon(icon, size: 16, color: AppColors.textMid),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(text, maxLines: 1, textDirection: ltr ? TextDirection.ltr : null, style: AppType.input(color: AppColors.textHi)),
                ),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────── تسوية الرصيد ───────────────────────────

/// ورقة «تسوية الرصيد» على [period]. تُرجع اللوحة كما صارت عند الخادم، أو null إن تراجع.
Future<BalanceOverview?> showBalanceAdjustSheet(BuildContext context, BalancePeriod period) {
  return showAppSheet<BalanceOverview>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => BalanceAdjustSheet(period: period),
  );
}

class BalanceAdjustSheet extends StatefulWidget {
  const BalanceAdjustSheet({super.key, required this.period});
  final BalancePeriod period;

  @override
  State<BalanceAdjustSheet> createState() => _BalanceAdjustSheetState();
}

class _BalanceAdjustSheetState extends State<BalanceAdjustSheet> {
  late final _amountCtrl = TextEditingController(text: AmountShorthand.format(widget.period.remaining.round()));
  final _noteCtrl = TextEditingController();
  BalanceSource _source = BalanceSource.income;
  bool _busy = false;
  final String _ref = BalanceReportsApi.newRef('j');

  int get _amount => AmountShorthand.expand(AmountShorthand.parse(_amountCtrl.text));

  @override
  void initState() {
    super.initState();
    // «غير ذلك» يطلب ملاحظة: الزرّ يتبدّل مع الكتابة
    _noteCtrl.addListener(_onNote);
  }

  void _onNote() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _noteCtrl.removeListener(_onNote);
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  String? get _problem {
    final a = _amount;
    if (a <= 0) return 'اكتب المبلغ';
    if (a > widget.period.remaining + 0.5) return 'المبلغ أكبر من المعوز (${balanceIqd(widget.period.remaining)})';
    if (_source == BalanceSource.other && _noteCtrl.text.trim().isEmpty) return 'اكتب ملاحظة توضّح مصدر المبلغ';
    return null;
  }

  Future<void> _submit() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_problem != null || _busy) return;
    final amount = _amount;
    setState(() => _busy = true);
    final r = await BalanceReportsApi.addAdjustment(widget.period.id, amount: amount, source: _source, note: _noteCtrl.text, clientRef: _ref);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!r.ok) {
      showSheetSnack(context, r.message ?? 'تعذّر تسجيل التسوية', isError: true);
      return;
    }
    Navigator.of(context).pop(r.data);
    showSheetSnack(context, 'سُجّلت تسوية ${balanceIqd(amount)}');
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final p = widget.period;
    final problem = _problem;
    const sources = BalanceSource.values;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.scale,
        title: 'تسوية الرصيد',
        subtitle: balancePeriodTitle(p),
        onClose: _busy ? () {} : () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('bal-adjust-save'),
        label: _busy ? 'جاري التسجيل...' : (problem ?? 'تسجيل التسوية — ${balanceIqd(_amount)}'),
        icon: LucideIcons.check,
        busy: _busy,
        enabled: problem == null,
        onPressed: _submit,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // لا صندوق الخلاصة المشترك: تسميته سطرٌ واحد يُقصّ ورقمه لا يصغر — هنا التسمية تلتفّ والرقم يصغر ولا يفيض
          Container(
            key: const ValueKey('bal-adjust-remaining'),
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm + 2),
            decoration: BoxDecoration(
              color: AppTone.warning.softBg,
              borderRadius: BorderRadius.circular(R.card),
              border: Border.all(color: AppTone.warning.softBorder),
            ),
            child: BalanceLine(label: 'المعوز حتى يكتمل مبلغ الشحنة', value: balanceIqd(p.remaining), strong: true, valueColor: AppTone.warning.onSoft),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'المبلغ اللي تضيفه',
            child: SheetBox(
              focused: _amount > 0,
              child: AmountTextField(key: const ValueKey('bal-adjust-amount'), controller: _amountCtrl, enabled: !_busy, onValue: (_) => setState(() {})),
            ),
          ),
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'منين المبلغ؟',
            child: SheetSegmented(
              key: const ValueKey('bal-adjust-source'),
              labels: [for (final s in sources) s.label],
              selectedIndex: sources.indexOf(_source),
              onSelect: (i) {
                if (!_busy) setState(() => _source = sources[i]);
              },
            ),
          ),
          if (_source == BalanceSource.income && p.incomeInWindow > 0) ...[
            const SizedBox(height: Sp.x6),
            Text('دخلك خلال هذه الفترة من ديونٍ سابقة: ${balanceIqd(p.incomeInWindow)}', key: const ValueKey('bal-adjust-income'), style: AppType.muted(color: AppColors.textMid)),
          ],
          const SizedBox(height: Sp.lg),
          SheetNoteField(
            key: const ValueKey('bal-adjust-note'),
            controller: _noteCtrl,
            hint: _source == BalanceSource.other ? 'اكتب مصدر المبلغ' : 'ملاحظة (اختياريّ)',
            maxLength: 200,
            enabled: !_busy,
          ),
          const SizedBox(height: Sp.sm),
          Text('التسوية تكمّل مبلغ الشحنة حتى تگدر تغلق الفترة. قيدٌ بهذا التقرير بس — ما تغيّر صندوقك ولا ديون المشتركين.', style: AppType.muted(color: AppColors.textHint)),
        ],
      ),
    );
  }
}
