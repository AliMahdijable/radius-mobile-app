import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/cards_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/skeleton.dart';
import 'cards_widgets.dart';
import 'sheets/series_cards_sheet.dart';

/// «الكارتات» — مخزون كارتات التعبئة للوكيل (البند ٤ §١٢).
///
/// للقراءة وحدها: كم بقي إجمالاً ولكلّ باقة، والسلاسل الأحدث أوّلاً، ومن
/// السلسلة كارتاتها — غير المستعمل أوّلاً، والمستعمل لمن ومتى. الخادم يقرأ
/// الساس ويحسب (`/api/v2/cards/*`)، والشاشة تعرض فقط.
///
/// ── السرعة ─────────────────────────────────────────────────────────
/// آخر ملخّصٍ في الجلسة (`CardsState.lastSummary`) يُرسم فور الفتح ثمّ
/// يتجدّد. وبلا ملخّص: الهيكل، ومعه العدد الإجماليّ من الشارة إن عُرف.
///
/// ⚠️ لا PIN ولا رقمٌ تسلسليّ كامل في هذا القسم كلّه.
class CardsScreen extends StatefulWidget {
  const CardsScreen({super.key});

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  CardsSummary? _summary;

  /// السلاسل الأحدث أوّلاً — تُرتَّب مرّةً مع كلّ ملخّص لا مع كلّ بناء.
  List<CardSeries> _series = const [];
  bool _loading = true;
  String? _error;

  /// طلبٌ جارٍ يُشارَك: السحب للتحديث أثناء التحميل لا يُطلق طلباً ثانياً.
  Future<void>? _inFlight;

  @override
  void initState() {
    super.initState();
    _setSummary(CardsState.lastSummary);
    _load();
  }

  void _setSummary(CardsSummary? s) {
    _summary = s;
    _series = s == null ? const [] : newestFirst(s.series);
  }

  /// [fresh]: التحديث الصريح (السحب أو زرّ التحديث) يتخطّى كاش الخادم —
  /// كارتاتٌ أضافتها الشركة للتوّ تظهر فوراً لا بعد دقيقة.
  Future<void> _load({bool fresh = false}) =>
      _inFlight ??= _fetch(fresh).whenComplete(() => _inFlight = null);

  Future<void> _refresh() => _load(fresh: true);

  Future<void> _fetch(bool fresh) async {
    if (!_loading) setState(() => _loading = true);
    final r = await CardsApi.summary(fresh: fresh);
    if (!mounted) return;
    final data = r.data;
    final hadData = _summary != null;
    setState(() {
      _loading = false;
      if (data != null) {
        _setSummary(data);
        _error = null;
      } else {
        _error = r.message ?? 'common.load_failed'.tr();
      }
    });
    // فشل تحديثٍ فوق بياناتٍ معروضة: تبقى، ويُقال إنّها لم تتجدّد.
    if (data == null && hadData) {
      showSheetSnack(context, 'cards.refresh_failed'.tr(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'cards.title'.tr(),
          style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16),
        ),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            tooltip: 'common.refresh'.tr(),
            icon: _loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textMid,
                    ),
                  )
                : Icon(LucideIcons.refreshCw,
                    size: 18, color: AppColors.textMid),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: AppColors.brandAccent,
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    final s = _summary;
    final bottom = Inset.route(context);
    final pad = EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, bottom);
    if (s == null) {
      if (_loading) {
        // العدد الإجماليّ من الشارة فوراً — ما بقي يصل مع الملخّص.
        final b = CardsState.badge.value;
        return _LoadingList(
          padding: pad,
          remaining: (b?.enabled ?? false) ? b!.remaining : null,
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        children: [
          _StateCard(
            icon: LucideIcons.circleAlert,
            text: _error ?? 'common.load_failed'.tr(),
            action: TextButton(
              onPressed: _refresh,
              child: Text('common.retry'.tr()),
            ),
          ),
        ],
      );
    }
    if (!s.enabled || (s.profiles.isEmpty && _series.isEmpty)) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        children: [
          _StateCard(
            icon: LucideIcons.ticket,
            title: 'cards.none_title'.tr(),
            text: 'cards.none_hint'.tr(),
          ),
        ],
      );
    }
    // السلاسل قد تكون مئات: تُبنى كسولاً، وما فوقها قائمةٌ عاديّة قصيرة.
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, 0),
          sliver: SliverList.list(
            children: [
              _TotalCard(remaining: s.totals.remaining, totals: s.totals),
              if (s.profiles.isNotEmpty) ...[
                const SizedBox(height: Sp.xl),
                _SectionTitle(
                  text: 'cards.by_package'.tr(),
                  trailing: '${s.profiles.length}',
                ),
                for (var i = 0; i < s.profiles.length; i++) ...[
                  if (i > 0) const SizedBox(height: Sp.sm),
                  _ProfileCard(p: s.profiles[i]),
                ],
              ],
              if (_series.isNotEmpty) ...[
                const SizedBox(height: Sp.xl),
                _SectionTitle(
                  text: 'cards.series_title'.tr(),
                  trailing: '${_series.length}',
                ),
              ],
            ],
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, bottom),
          sliver: SliverList.separated(
            itemCount: _series.length,
            separatorBuilder: (_, __) => const SizedBox(height: Sp.sm),
            itemBuilder: (_, i) => _SeriesTile(
              series: _series[i],
              onTap: () => showSeriesCardsSheet(context, _series[i]),
            ),
          ),
        ),
      ],
    );
  }
}

/// «الكارتات المتبقّية» — العدد الكبير وتفصيله.
///
/// [totals] `null` أثناء التحميل: سطر التفصيل هيكل. و[remaining] `null` حين
/// لا تُعرف الشارة بعد: العدد هيكلٌ أيضاً — لا صفرٌ مخترَع.
class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.remaining, required this.totals});
  final int? remaining;
  final CardsTotals? totals;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final n = remaining;
    final t = totals;
    // الصفر المقروء تحذير: نفاد الكارتات يوقف التفعيل بالكارت.
    final out = n == 0;
    final tone = out ? AppTone.warning : AppTone.brand;
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: H.iconBox,
            height: H.iconBox,
            decoration: BoxDecoration(
              color: tone.softBg,
              borderRadius: BorderRadius.circular(R.icon),
            ),
            child: Icon(LucideIcons.tickets, size: 20, color: tone.fill),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('cards.remaining_total'.tr(), style: AppType.label()),
                const SizedBox(height: Sp.xxs),
                if (n == null)
                  const SkeletonBox(width: 56, height: 27, borderRadius: R.sm)
                else
                  Text(
                    formatIQD(n),
                    textDirection: TextDirection.ltr,
                    style: AppType.amount(
                      color: out ? AppColors.warning : AppColors.textHi,
                    ),
                    maxLines: 1,
                  ),
                const SizedBox(height: Sp.xxs),
                if (t == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: Sp.xxs),
                    child: SkeletonBox(width: 160, height: 10),
                  )
                else
                  Text(
                    'cards.totals_line'.tr(namedArgs: {
                      'used': iso(formatIQD(t.used)),
                      'qty': iso(formatIQD(t.qty)),
                      'series': iso(formatIQD(t.series)),
                    }),
                    style: AppType.muted(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// مخزون باقة: الاسم وقيمة الكارت، والمتبقّي من الكلّ بشريطٍ رفيع.
/// الباقة النافدة باهتةٌ كلّها — تبقى ظاهرةً لأنّ «نفدت» خبرٌ أيضاً.
class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.p});
  final CardProfileStock p;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final out = p.remaining <= 0;
    final tone = out ? AppTone.neutral : AppTone.brand;
    final ratio = p.qty > 0 ? p.remaining / p.qty : 0.0;
    return Opacity(
      opacity: out ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.all(Sp.md),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.profileName,
                        style: AppType.cardTitleBold(color: AppColors.textHi),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Sp.xxs),
                      Text(
                        'cards.per_card'
                            .tr(namedArgs: {'value': cardsMoney(p.value)}),
                        style: AppType.muted(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                _StockCount(remaining: p.remaining, qty: p.qty, tone: tone),
              ],
            ),
            const SizedBox(height: Sp.sm),
            StockBar(ratio: ratio, tone: tone),
            const SizedBox(height: Sp.x6),
            Text(
              'cards.package_line'.tr(namedArgs: {
                'used': iso(formatIQD(p.used)),
                'series': iso(formatIQD(p.series)),
              }),
              style: AppType.micro(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// «3 من 500» — المتبقّي بارزاً والكلّ خافتاً بجانبه.
class _StockCount extends StatelessWidget {
  const _StockCount({
    required this.remaining,
    required this.qty,
    required this.tone,
  });
  final int remaining;
  final int qty;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          formatIQD(remaining),
          maxLines: 1,
          style: AppType.statValue(
            color: remaining > 0 ? tone.fill : AppColors.textLow,
          ),
        ),
        const SizedBox(width: Sp.xs),
        Text(
          'cards.of_qty'.tr(namedArgs: {'qty': formatIQD(qty)}),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.muted(),
        ),
      ],
    );
  }
}

/// صفّ سلسلة: رقمها، وباقتها وانتهاؤها، وحبّات حالها. ينقر ← كارتاتها.
/// المستهلكة كلّها باهتة، وتبقى تُفتح: لمن ذهبت كارتاتها سؤالٌ قائم.
class _SeriesTile extends StatelessWidget {
  const _SeriesTile({required this.series, required this.onTap});
  final CardSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = series;
    final tone = s.usable ? AppTone.brand : AppTone.neutral;
    final validity = seriesValidity(s);
    return Opacity(
      opacity: s.remaining > 0 ? 1 : 0.6,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.lg),
          child: Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: H.iconBox,
                  height: H.iconBox,
                  decoration: BoxDecoration(
                    color: tone.softBg,
                    borderRadius: BorderRadius.circular(R.icon),
                  ),
                  child: Icon(LucideIcons.ticket, size: 18, color: tone.fill),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.series,
                        textDirection: TextDirection.ltr,
                        style: AppType.bodyBold(color: AppColors.textHi),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Sp.xxs),
                      Text(
                        isoJoin([
                          seriesProfile(s),
                          if (validity != null) validity,
                        ], ' · '),
                        style: AppType.muted(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Sp.sm),
                      SeriesChips(series: s),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.xs),
                Icon(LucideIcons.chevronLeft,
                    size: 16, color: AppColors.textLow),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: AppType.cardTitleBold(color: AppColors.textHi),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ToneChip(label: trailing!, dense: true),
        ],
      ),
    );
  }
}

/// حالة الشاشة كلّها — عطلٌ بزرّ إعادة، أو حسابٌ بلا كارتات.
class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.text,
    this.title,
    this.action,
  });
  final IconData icon;
  final String? title;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.huge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          if (title != null) ...[
            Text(
              title!,
              textAlign: TextAlign.center,
              style: AppType.cardTitleBold(color: AppColors.textHi),
            ),
            const SizedBox(height: Sp.x6),
          ],
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppType.body(color: AppColors.textMid).copyWith(height: 1.6),
          ),
          if (action != null) ...[const SizedBox(height: Sp.sm), action!],
        ],
      ),
    );
  }
}

/// الهيكل أثناء أوّل تحميل — بأشكال البطاقات نفسها فلا تقفز الشاشة حين
/// تحلّ البيانات محلّه.
class _LoadingList extends StatelessWidget {
  const _LoadingList({required this.padding, required this.remaining});
  final EdgeInsets padding;
  final int? remaining;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: padding,
      children: [
        _TotalCard(remaining: remaining, totals: null),
        const SizedBox(height: Sp.xl),
        const _TitleSkeleton(width: 90),
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          const _ProfileSkeleton(),
        ],
        const SizedBox(height: Sp.xl),
        const _TitleSkeleton(width: 64),
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          const _SeriesSkeleton(),
        ],
      ],
    );
  }
}

class _TitleSkeleton extends StatelessWidget {
  const _TitleSkeleton({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: SkeletonBox(width: width, height: 16),
      ),
    );
  }
}

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 96, height: 16),
                    SizedBox(height: Sp.x6),
                    SkeletonBox(width: 120, height: 10),
                  ],
                ),
              ),
              SizedBox(width: Sp.sm),
              SkeletonBox(width: 56, height: 18),
            ],
          ),
          SizedBox(height: Sp.sm),
          SkeletonBox(height: 6, borderRadius: R.pill),
          SizedBox(height: Sp.x6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: SkeletonBox(width: 110, height: 10),
          ),
        ],
      ),
    );
  }
}

class _SeriesSkeleton extends StatelessWidget {
  const _SeriesSkeleton();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: H.iconBox, height: H.iconBox, borderRadius: R.icon),
          SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 92, height: 14),
                SizedBox(height: Sp.x6),
                SkeletonBox(width: 150, height: 10),
                SizedBox(height: Sp.sm),
                Row(
                  children: [
                    SkeletonBox(width: 52, height: 20, borderRadius: R.pill),
                    SizedBox(width: Sp.x6),
                    SkeletonBox(width: 64, height: 20, borderRadius: R.pill),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
