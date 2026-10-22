import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/earthlink_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/skeleton.dart';
import '../desktop/desk_widgets.dart';

/// ايرث لنك — «الكارتات المطلوبة» (البند ٤، EarthLink وحدهم).
///
/// لكلّ مدّة (يوم · ٣ أيام · أسبوع · شهر): كم كارتاً من كلّ باقة سيلزم،
/// وكم رصيداً — بكلفة الشركة — يلزم لشرائها. لا أسعار بيع ولا ربح هنا؛
/// أسعار البيع بشاشة الباقات. توقّعٌ للعرض فقط: «طلب الكارتات» من ايرث لنك
/// أُلغي نهائيّاً (قرار المالك ١٩ أكتوبر) فلا زرّ طلب هنا.
///
/// نتيجة كلّ مدّة تُحفَظ: الرجوع لمدّةٍ سبق جلبها فوريّ ثمّ تُحدَّث بالخلفيّة.
class ElRequiredCardsScreen extends StatefulWidget {
  const ElRequiredCardsScreen({super.key});

  @override
  State<ElRequiredCardsScreen> createState() => _ElRequiredCardsScreenState();
}

class _ElRequiredCardsScreenState extends State<ElRequiredCardsScreen> {
  static const List<int> _days = [1, 3, 7, 30];
  static const List<String> _labels = ['يوم', '٣ أيام', 'أسبوع', 'شهر'];
  static const List<String> _periodText = [
    'ليوم واحد',
    'لـ٣ أيام',
    'لأسبوع',
    'لشهر',
  ];

  int _index = 0;
  final Map<int, List<ElNeededCard>> _cache = {};
  bool _loading = true;
  String? _error;

  /// رقم آخر طلب — ردٌّ متأخّر لمدّةٍ سابقة لا يغيّر حالة المدّة الحاليّة.
  int _req = 0;

  int get _currentDays => _days[_index];
  List<ElNeededCard>? get _items => _cache[_currentDays];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final days = _currentDays;
    final req = ++_req;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final r = await EarthlinkApi.prepaidNeeded(days: days);
    if (!mounted) return;
    final latest = req == _req;
    setState(() {
      // نتيجةٌ سليمة تُحفَظ لمدّتها حتى لو تجاوزها المستخدم.
      if (r.message == null) _cache[days] = _sorted(r.items);
      if (latest) {
        _loading = false;
        _error = r.message;
      }
    });
    // فشل تحديثٍ والبيانات السابقة معروضة ⇒ تنبيهٌ لا استبدال للشاشة.
    if (latest && r.message != null && _cache[days] != null) {
      _snack(r.message!, error: true);
    }
  }

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = i;
      _error = null;
    });
    _load();
  }

  /// الأعلى طلباً أوّلاً؛ ما لا يحتاج تزويداً (المطلوب = 0) في الآخر.
  static List<ElNeededCard> _sorted(List<ElNeededCard> list) {
    final out = [...list];
    out.sort((a, b) {
      final byNeeded = b.needed.compareTo(a.needed);
      if (byNeeded != 0) return byNeeded;
      final byUsed = b.used.compareTo(a.used);
      if (byUsed != 0) return byUsed;
      return a.name.compareTo(b.name);
    });
    return List<ElNeededCard>.unmodifiable(out);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: AppType.button(color: AppColors.onBrand)),
        backgroundColor: error ? AppColors.errorFill : AppColors.brand,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
        margin: const EdgeInsets.all(Sp.lg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final items = _items;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: deskPageBar(
          context,
          mobile: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            scrolledUnderElevation: 0,
            iconTheme: IconThemeData(color: AppColors.textHi),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('الكارتات المطلوبة',
                    style: AppType.title(color: AppColors.textHi)
                        .copyWith(fontSize: 16)),
                Text('توقّع الكارتات والرصيد اللازمَين لكلّ مدّة',
                    style: AppType.muted().copyWith(fontSize: 11)),
              ],
            ),
            actions: [
              if (_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.brandAccent),
                    ),
                  ),
                )
              else
                IconButton(
                  onPressed: _load,
                  tooltip: 'تحديث',
                  icon: Icon(LucideIcons.refreshCw,
                      size: 18, color: AppColors.textMid),
                ),
            ],
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppColors.brandAccent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding:
                  const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                SheetSegmented(
                  labels: _labels,
                  selectedIndex: _index,
                  onSelect: _select,
                ),
                const SizedBox(height: Sp.lg),
                if (items == null && _error != null)
                  _errorState(_error!)
                else if (items == null)
                  _skeleton()
                else
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _loading ? 0.6 : 1,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _summary(items),
                        const SizedBox(height: Sp.lg),
                        if (items.isEmpty) _emptyState() else _list(items),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════ الملخّص ═══════════════

  Widget _summary(List<ElNeededCard> items) {
    final totalNeeded = items.fold<int>(0, (s, c) => s + c.needed);
    final totalBalance = items.fold<num>(0, (s, c) => s + c.balanceNeeded);
    // بسعر الكارت لدى ايرث لنك (ما تُشترى به الكارتات) حين يصل من الخادم.
    final byCardPrice = items.any((c) => c.cardPrice != null);
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: _stat(
                    icon: LucideIcons.tickets,
                    label: 'الكارتات المطلوبة',
                    value: formatIQD(totalNeeded),
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: Sp.md),
                  color: AppColors.onBrandFill2,
                ),
                Expanded(
                  flex: 3,
                  child: _stat(
                    icon: LucideIcons.wallet,
                    label: byCardPrice
                        ? 'الرصيد المطلوب (بسعر الكارت)'
                        : 'الرصيد المطلوب (بكلفة الشركة)',
                    value: formatIQD(totalBalance),
                    unit: 'د.ع',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Sp.md),
          Text(
            byCardPrice
                ? '${_periodText[_index]} — المبلغ اللازم تعبئته لشراء الكارتات '
                    'المطلوبة، بسعر ايرث لنك للكارت'
                : '${_periodText[_index]} — المبلغ اللازم تعبئته لشراء الكارتات المطلوبة',
            style: AppType.muted(color: AppColors.onBrandSecondary),
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required String label,
    required String value,
    String? unit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 14, color: AppColors.onBrandSecondary),
            ),
            const SizedBox(width: Sp.xs),
            Expanded(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label(color: AppColors.onBrandSecondary)),
            ),
          ],
        ),
        const SizedBox(height: Sp.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textBaseline: TextBaseline.alphabetic,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            children: [
              Text(
                value,
                textDirection: TextDirection.ltr,
                style: AppType.amount(color: AppColors.onBrand)
                    .copyWith(fontSize: 22),
              ),
              if (unit != null) ...[
                const SizedBox(width: 6),
                Text(unit,
                    style: AppType.body(color: AppColors.onBrandSecondary)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════ القائمة ═══════════════

  Widget _list(List<ElNeededCard> items) {
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: H.iconBox,
                height: H.iconBox,
                decoration: BoxDecoration(
                  color: AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.icon),
                ),
                child: Icon(LucideIcons.tickets,
                    size: 18, color: AppColors.brand),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text('حسب الباقة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.cardTitleBold(color: AppColors.textHi)),
              ),
              Text(
                  items.length == 1
                      ? 'باقة واحدة'
                      : '${items.length} باقات',
                  style: AppType.muted(color: AppColors.textMid)),
            ],
          ),
          const SizedBox(height: Sp.lg),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: Sp.sm),
            _NeededRow(card: items[i]),
          ],
        ],
      ),
    );
  }

  // ═══════════════ الحالات ═══════════════

  Widget _skeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SkeletonBox(height: 112, borderRadius: R.card),
        const SizedBox(height: Sp.lg),
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          const SkeletonBox(height: 88, borderRadius: R.md),
        ],
      ],
    );
  }

  Widget _emptyState() {
    return _stateBox(
      icon: LucideIcons.packageCheck,
      tone: AppTone.brand,
      title: 'لا توجد كارتات مطلوبة لهذه المدّة',
    );
  }

  /// [message] رسالة الخادم العربيّة أو البديل «تعذّر جلب الكارتات المطلوبة» —
  /// تصير العنوان، والسطر تحته تلميح الإجراء (لا تكرار للعنوان).
  Widget _errorState(String message) {
    return _stateBox(
      icon: LucideIcons.triangleAlert,
      tone: AppTone.danger,
      title: message,
      message: 'تحقّق من الاتصال ثم أعد المحاولة.',
      action: SizedBox(
        height: H.button,
        child: Material(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(R.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _loading ? null : _load,
            child: Center(
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: AppColors.onBrand),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.refreshCw,
                            size: 18, color: AppColors.onBrand),
                        const SizedBox(width: Sp.sm),
                        Text('إعادة المحاولة',
                            style: AppType.button(color: AppColors.onBrand)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stateBox({
    required IconData icon,
    required AppTone tone,
    required String title,
    String? message,
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.xl, vertical: Sp.huge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tone.softBg,
                borderRadius: BorderRadius.circular(R.icon),
                border: Border.all(color: tone.softBorder),
              ),
              child: Icon(icon, size: 24, color: tone.fill),
            ),
          ),
          const SizedBox(height: Sp.md),
          Text(title,
              textAlign: TextAlign.center,
              style: AppType.cardTitleBold(color: AppColors.textHi)),
          if (message != null) ...[
            const SizedBox(height: Sp.xs),
            Text(message,
                textAlign: TextAlign.center,
                style: AppType.body(color: AppColors.textMid)),
          ],
          if (action != null) ...[
            const SizedBox(height: Sp.lg),
            action,
          ],
        ],
      ),
    );
  }
}

/// صفّ باقة: الاسم وكلفة الكارت، المطلوب بارزاً، ثمّ المتوفّر والمُستهلَك
/// خلال المدّة ورصيد الباقة اللازم. ما لا يحتاج تزويداً يُعرَض باهتاً.
class _NeededRow extends StatelessWidget {
  const _NeededRow({required this.card});
  final ElNeededCard card;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final idle = card.needed == 0;
    final row = Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.borderSoft),
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
                    Text(
                      card.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.bodyStrong(color: AppColors.textHi)
                          .copyWith(fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    // سعر الكارت (ما تُشترى به)، وكلفة التفعيل من الرصيد
                    // حين تختلف عنه — وإلّا الكلفة وحدها (خادمٌ لا يرسل السعر).
                    if (card.cardPrice != null) ...[
                      Text('سعر الكارت ${formatIQD(card.cardPrice!)} د.ع',
                          style: AppType.muted(color: AppColors.textLow)),
                      if (card.cost > 0 && card.cost != card.cardPrice)
                        Text('التفعيل من الرصيد ${formatIQD(card.cost)} د.ع',
                            style: AppType.muted(color: AppColors.textLow)),
                    ] else
                      Text('كلفة الكارت ${formatIQD(card.cost)} د.ع',
                          style: AppType.muted(color: AppColors.textLow)),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              _NeededPill(value: card.needed),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MiniStat(
                    label: 'المتوفّر', value: formatIQD(card.available)),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: _MiniStat(
                    label: 'المُستهلَك خلال المدّة',
                    value: formatIQD(card.used)),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: _MiniStat(
                  label: 'الرصيد المطلوب',
                  value: idle ? '—' : '${formatIQD(card.balanceNeeded)} د.ع',
                  strong: !idle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return idle ? Opacity(opacity: 0.55, child: row) : row;
  }
}

/// المطلوب — الرقم الأبرز في الصفّ.
class _NeededPill extends StatelessWidget {
  const _NeededPill({required this.value});
  final int value;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final on = value > 0;
    final ink = on ? AppColors.brand : AppColors.textLow;
    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
      decoration: BoxDecoration(
        color: on ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(
            color: on ? AppColors.brandSoftBorder : AppColors.borderSoft),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(formatIQD(value),
              textDirection: TextDirection.ltr,
              style: AppType.statValue(color: ink)),
          Text('المطلوب', style: AppType.micro(color: ink)),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.strong = false,
  });
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppType.micro(color: AppColors.textLow)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: AppType.bodyStrong(
                color: strong ? AppColors.textHi : AppColors.textBody),
          ),
        ),
      ],
    );
  }
}
