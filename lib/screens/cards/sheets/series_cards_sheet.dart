import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/cards_api.dart';
import '../../../core/util/bidi.dart';
import '../../../core/util/format.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../widgets/skeleton.dart';
import '../cards_widgets.dart';
import '../../../core/widgets/app_sheet.dart';

/// كارتات سلسلة — غير المستعمل أوّلاً، والمستعمل لمن ومتى، بصفحاتٍ من ٥٠.
///
/// ⚠️ لا PIN ولا رقمٌ تسلسليّ كامل: الخادم يرسل آخر أربع خانات وحدها،
/// والنموذج لا يملك حقلاً لغيرها. والقراءة من الساس بطيئة (~٢ث للصفحة)،
/// فرأس الشيت يُرسم فوراً ممّا في الملخّص والهيكل مكان القائمة.
///
/// [canTransfer] (صاحب الحساب + مفتاح الخادم + سلسلة ساس — ٢٧ أكتوبر): يُظهر «نقل لمدير فرعيّ»، والنقر يغلق الشيت
/// ويعيد `true` فتفتح الشاشة شيت النقل (لا شيتٌ فوق شيت).
Future<bool?> showSeriesCardsSheet(BuildContext context, CardSeries series, {bool canTransfer = false}) {
  return showAppSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _SeriesCardsSheet(series: series, canTransfer: canTransfer),
  );
}

class _SeriesCardsSheet extends StatefulWidget {
  const _SeriesCardsSheet({required this.series, this.canTransfer = false});
  final CardSeries series;
  final bool canTransfer;

  @override
  State<_SeriesCardsSheet> createState() => _SeriesCardsSheetState();
}

class _SeriesCardsSheetState extends State<_SeriesCardsSheet> {
  late CardSeries _series = widget.series;
  final List<CardItem> _cards = [];

  /// حارس التكرار بين الصفحات: كارتٌ يُستعمل بين صفحتين ينتقل من رأس
  /// الترتيب (غير المستعمل أوّلاً) إلى ذيله، فيعود في صفحةٍ لاحقة.
  final Set<int> _ids = {};
  int _page = 0;
  int _total = 0;
  bool _hasMore = false;

  bool _loading = true;
  String? _error;

  bool _loadingMore = false;

  /// فشل صفحةٍ لاحقة — المعروض يبقى، والسطر الأخير يعرض السبب وزرّ الإعادة.
  String? _moreError;

  @override
  void initState() {
    super.initState();
    _loadFirst();
  }

  Future<void> _loadFirst() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await CardsApi.seriesCards(widget.series.series);
    if (!mounted) return;
    final p = r.data;
    setState(() {
      _loading = false;
      if (p == null) {
        _error = r.message ?? 'common.load_failed'.tr();
        return;
      }
      _series = p.series ?? _series;
      _cards.clear();
      _ids.clear();
      _append(p);
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    final r = await CardsApi.seriesCards(widget.series.series, page: _page + 1);
    if (!mounted) return;
    final p = r.data;
    setState(() {
      _loadingMore = false;
      if (p == null) {
        _moreError = r.message ?? 'common.load_failed'.tr();
        return;
      }
      _append(p);
    });
  }

  void _append(CardsPage p) {
    for (final c in p.cards) {
      if (_ids.add(c.id)) _cards.add(c);
    }
    _page = p.page;
    _total = p.total;
    // صفحةٌ فارغة تُنهي «المزيد» مهما قال العدد — فلا زرّ يدور بلا نهاية.
    _hasMore = p.hasMore && p.cards.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = _series;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.ticket,
        // ايرث لنك: «السلسلة» باقة — عنوانها اسم الباقة لا رمزها الداخليّ.
        title: isPackageSeries(s)
            ? 'cards.package_n'.tr(namedArgs: {'name': seriesProfile(s)})
            : 'cards.series_n'.tr(namedArgs: {'series': iso(s.series)}),
        subtitle: isPackageSeries(s)
            ? 'cards.per_card'.tr(namedArgs: {'value': cardsMoney(s.value)})
            : isoJoin([
                seriesProfile(s),
                'cards.per_card'.tr(namedArgs: {'value': cardsMoney(s.value)}),
              ], ' · '),
        onClose: () => Navigator.of(context).pop(),
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.md, Sp.xl, Sp.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SeriesChips(series: s),
                if (seriesValidity(s) case final v?) ...[
                  const SizedBox(height: Sp.x6),
                  Text(
                    v,
                    style: AppType.muted(
                      color: s.expired ? AppTone.danger.fill : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (widget.canTransfer && !isPackageSeries(s)) ...[
                  const SizedBox(height: Sp.md),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('series-transfer'),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(LucideIcons.send, size: 16),
                      label: Text('cards.transfer_open'.tr()),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.dividerStrong),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _list() {
    if (_loading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [for (var i = 0; i < 7; i++) const _CardRowSkeleton()],
      );
    }
    final err = _error;
    if (err != null) {
      return _Message(
        icon: LucideIcons.circleAlert,
        text: err,
        tone: AppTone.danger,
        action: TextButton(
          onPressed: _loadFirst,
          child: Text('common.retry'.tr()),
        ),
      );
    }
    if (_cards.isEmpty) {
      return _Message(
        icon: LucideIcons.inbox,
        text: (isPackageSeries(_series)
                ? 'cards.package_empty'
                : 'cards.series_empty')
            .tr(),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: Sp.lg + MediaQuery.paddingOf(context).bottom),
      itemCount: _cards.length + 1,
      itemBuilder: (_, i) =>
          i < _cards.length ? _CardRow(card: _cards[i]) : _footer(),
    );
  }

  /// آخر سطر: كم عُرض من كم، ثمّ «عرض المزيد» أو دوّارته أو سبب فشله.
  Widget _footer() {
    final more = _moreError;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.md, Sp.xl, 0),
      child: Column(
        children: [
          Text(
            'cards.shown_of'.tr(namedArgs: {
              'n': formatIQD(_cards.length),
              'total': formatIQD(_total < _cards.length ? _cards.length : _total),
            }),
            style: AppType.muted(),
          ),
          if (more != null) ...[
            const SizedBox(height: Sp.x6),
            Text(
              more,
              textAlign: TextAlign.center,
              style: AppType.muted(color: AppTone.danger.fill),
            ),
          ],
          if (_loadingMore)
            const Padding(
              padding: EdgeInsets.all(Sp.md),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_hasMore)
            TextButton.icon(
              onPressed: _loadMore,
              icon: Icon(
                more == null ? LucideIcons.chevronDown : LucideIcons.refreshCw,
                size: 16,
              ),
              label: Text(
                more == null ? 'cards.load_more'.tr() : 'common.retry'.tr(),
              ),
            ),
        ],
      ),
    );
  }
}

/// صفّ كارت: الذيل، ثمّ «غير مستعمل» أو لمن ذهب، ومتى.
class _CardRow extends StatelessWidget {
  const _CardRow({required this.card});
  final CardItem card;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = card;
    final tone = c.used ? AppTone.neutral : AppTone.brand;
    final who = c.subscriberUsername;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.xl, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tone.softBg,
              borderRadius: BorderRadius.circular(R.md),
            ),
            child: Icon(
              c.used ? LucideIcons.ticketCheck : LucideIcons.ticket,
              size: 16,
              color: tone.fill,
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cardTail(c.serialTail),
                  textDirection: TextDirection.ltr,
                  style: AppType.bodyBold(
                    color: c.used ? AppColors.textMid : AppColors.textHi,
                  ),
                  maxLines: 1,
                ),
                const SizedBox(height: Sp.xxs),
                if (!c.used)
                  Text(
                    'cards.unused'.tr(),
                    style: AppType.muted(color: AppTone.brand.onSoft),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                else
                  Text(
                    who ?? 'cards.used'.tr(),
                    textDirection: who == null ? null : TextDirection.ltr,
                    style: AppType.muted(color: AppColors.textBody),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (c.used) ...[
            const SizedBox(width: Sp.sm),
            Text(
              cardsWhen(c.usedAtDate),
              maxLines: 1,
              textDirection: TextDirection.ltr,
              style: AppType.micro(color: AppColors.textMid),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardRowSkeleton extends StatelessWidget {
  const _CardRowSkeleton();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.xl, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: const Row(
        children: [
          SkeletonBox(width: 36, height: 36, borderRadius: R.md),
          SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: 64, height: 13),
                SizedBox(height: Sp.x6),
                SkeletonBox(width: 110, height: 10),
              ],
            ),
          ),
          SizedBox(width: Sp.sm),
          SkeletonBox(width: 84, height: 10),
        ],
      ),
    );
  }
}

/// رسالةٌ في وسط القائمة — خطأٌ بزرّ إعادة، أو سلسلةٌ بلا كارتات.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.tone = AppTone.neutral,
    this.action,
  });
  final IconData icon;
  final String text;
  final AppTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Sp.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: tone == AppTone.neutral ? AppColors.textLow : tone.fill),
            const SizedBox(height: Sp.sm),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppType.body(color: AppColors.textMid).copyWith(height: 1.6),
            ),
            if (action != null) ...[const SizedBox(height: Sp.xs), action!],
          ],
        ),
      ),
    );
  }
}
