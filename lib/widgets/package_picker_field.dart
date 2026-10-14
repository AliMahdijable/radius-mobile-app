// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع dart:ui
// المستعمَل في `textDirection` عبر الملفّ.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/util/bidi.dart';
import '../core/util/format.dart';
import '../core/widgets/design_sheet.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// حقل اختيار الباقة — حقلٌ واحد يفتح قائمةً، بدل صفوف اختيارٍ طويلة.
///
/// ── لماذا ─────────────────────────────────────────────────────────
/// بلاغ المالك ٢٠٢٦-١٠-١٣ بلقطة «تجديد اشتراك»: باقات ايرث لنك (Ta3leem
/// بأربعة أسعار · AlManasa · Economy · Plus · Standard · Turbo · More ·
/// باقات الثلاثة أشهر · Business Pro …) معروضةٌ كلّها صفوفَ اختيارٍ داخل
/// المودل، فيصير المودل قائمةً تُمرَّر قبل الوصول إلى طريقة الدفع:
/// «خليها سلكت واختيار وليس هلشكل».
///
/// ── ما يتغيّر وما لا يتغيّر ──────────────────────────────────────
/// العرض وحده: الترتيب يأتي من المستدعي كما هو، والاختيار الافتراضيّ
/// والسعر وما يُرسَل للخادم كلّها عنده. هذا الحقل لا يعرف إلّا معرّفاً
/// يُعيده عند الاختيار.
///
/// الحقل يعرض الباقة المختارة وسعرها (و«الحاليّة» إن كانت باقة المشترك)،
/// والنقر يفتح ورقةً سفليّة بكلّ الباقات: المختارة معلَّمة، والحاليّة
/// موسومة، ومربّع بحثٍ حين تزيد على [_searchThreshold].
///
/// خاصٌّ بجلسات ايرث لنك اليوم — مستدعوه يقرّرون ذلك؛ واجهة SAS4 لم تتغيّر.

/// خيار باقة — ما يُعرض فقط؛ المعنى (ما يُرسَل) يبقى عند المستدعي.
@immutable
class PackageOption {
  const PackageOption({
    required this.id,
    required this.name,
    this.price,
    this.points,
  });

  /// المعرّف الذي يعود به الاختيار — كما يقرؤه المستدعي.
  final String id;

  /// اسم الباقة كما يرسله المزوّد — لاتينيٌّ غالباً، فيُعزل اتّجاهيّاً.
  final String name;

  /// السعر بالدينار. `null` يُخفيه (لا «0 د.ع» حين لا سعر).
  final num? price;

  /// نقاطٌ مطلوبة (التمديد) — حبّة «N نقطة» حين تزيد على صفر.
  final num? points;
}

/// أكثر من هذا العدد ⇒ مربّع بحثٍ، والورقة بطول الشاشة فلا تقفز مع الفلترة.
const int _searchThreshold = 6;

String _priceLabel(num v) =>
    '${formatIQD(v.round())} ${'common.currency'.tr()}';

String _pointsLabel(num v) => '${formatIQD(v.round())} نقطة';

/// «١٨ باقة» بعدد المعدود العربيّ: باقة واحدة · باقتان · ٣–١٠ باقات · ١١+ باقة.
String _countLabel(int n) {
  if (n == 1) return 'باقة واحدة';
  if (n == 2) return 'باقتان';
  if (n >= 3 && n <= 10) return '$n باقات';
  return '$n باقة';
}

/// ما يقرؤه قارئ الشاشة للباقة: الاسم، السعر، النقاط، «الحاليّة».
String _spokenValue(PackageOption o, {required bool current}) {
  final parts = <String>[iso(o.name)];
  final price = o.price;
  if (price != null) parts.add(_priceLabel(price));
  final points = o.points ?? 0;
  if (points > 0) parts.add(_pointsLabel(points));
  if (current) parts.add('الحاليّة');
  return parts.join('، ');
}

/// يفتح ورقة الباقات ويعيد معرّف المختارة، أو `null` إن أُغلقت بلا اختيار.
Future<String?> showPackagePickerSheet(
  BuildContext context, {
  required List<PackageOption> options,
  String? selectedId,
  String? currentId,
  String title = 'اختر الباقة',
}) async {
  final overlay = Navigator.maybeOf(context)?.overlay;
  Future<void>? gone;
  final picked = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      gone ??= ModalRoute.of(sheetContext)?.completed;
      return _PackagePickerSheet(
        options: options,
        selectedId: selectedId,
        currentId: currentId,
        title: title,
      );
    },
  );
  _swallowTapsUntil(overlay, gone);
  return picked;
}

/// ⚠️ مراجعة ٢٠٢٦-١٠-١٣: الورقة تتجاهل اللمس طوال انزلاقها للإغلاق (سلوك
/// Flutter لكلّ مسارٍ يُغلق)، فالنقرة الثانية من نقرةٍ مزدوجة على صفّ باقة
/// تقع على شيت التجديد تحتها — فوق «تجديد الآن» أرسلت التجديد فعلاً (وباسورد
/// الإيداع مكتوب)، وفوق «طباعة وصل» قلبتها، وفوق ✕ أغلقت الشيت.
/// حاجزٌ شفّاف فوق الكلّ يبتلع اللمس حتى تكتمل حركة الإغلاق ثمّ يُزال؛
/// و`completed` يكتمل أيضاً لو أُزيل المسار بلا حركة، فلا يبقى الحاجز أبداً.
void _swallowTapsUntil(OverlayState? overlay, Future<void>? gone) {
  if (overlay == null || !overlay.mounted || gone == null) return;
  final shield = OverlayEntry(
    builder: (_) => const AbsorbPointer(child: SizedBox.expand()),
  );
  overlay.insert(shield);
  gone.whenComplete(() {
    shield.remove();
    shield.dispose();
  });
}

/// الحقل المطويّ: الباقة المختارة + سعرها + «الحاليّة»، وسهمٌ يفتح القائمة.
class PackagePickerField extends StatelessWidget {
  const PackagePickerField({
    super.key,
    required this.options,
    required this.selectedId,
    required this.onSelected,
    this.currentId,
    this.enabled = true,
    this.loading = false,
    this.compact = false,
    this.label = 'الباقة',
    this.placeholder = 'اختر الباقة',
    this.emptyText = 'لا توجد باقات',
  });

  /// بالترتيب الذي يريده المستدعي — لا يُعاد ترتيبها هنا.
  final List<PackageOption> options;
  final String? selectedId;

  /// باقة المشترك الآن — تُوسم «الحاليّة» في الحقل والقائمة.
  final String? currentId;
  final ValueChanged<String> onSelected;
  final bool enabled;

  /// الباقات لم تصل بعد — دوّارة بدل السهم، والحقل لا يُفتح.
  final bool loading;

  /// نصف قطرٍ وحشوةٌ أصغر — ليجاور حقول `TextField` الكثيفة (شيت التعديل).
  final bool compact;

  /// تسمية الحقل لقارئ الشاشة (التسمية المرئيّة فوقه عند المستدعي).
  final String label;
  final String placeholder;
  final String emptyText;

  PackageOption? get _selected {
    final id = selectedId;
    if (id == null || id.isEmpty) return null;
    for (final o in options) {
      if (o.id == id) return o;
    }
    return null;
  }

  bool _isCurrent(PackageOption o) {
    final c = currentId;
    return c != null && c.isNotEmpty && o.id == c;
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showPackagePickerSheet(
      context,
      options: options,
      selectedId: selectedId,
      currentId: currentId,
      title: placeholder,
    );
    if (picked == null || !context.mounted) return;
    if (picked != selectedId) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final sel = _selected;
    final empty = !loading && options.isEmpty;
    final live = enabled && !loading && !empty;
    final radius = compact ? R.sm : R.lg;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: AppColors.border),
    );

    final String spoken;
    final Widget value;
    if (loading) {
      spoken = 'جارٍ تحميل الباقات';
      value = Text(
        'جارٍ تحميل الباقات…',
        style: AppType.input(color: AppColors.textLow),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (empty) {
      spoken = emptyText;
      value = Text(
        emptyText,
        style: AppType.input(color: AppColors.textMid),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else if (sel == null) {
      spoken = placeholder;
      value = Text(
        placeholder,
        style: AppType.input(color: AppColors.textLow),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      final current = _isCurrent(sel);
      spoken = _spokenValue(sel, current: current);
      value = _FieldValue(option: sel, current: current);
    }

    final Widget trailing = loading
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.brand),
          )
        : Icon(LucideIcons.chevronDown,
            size: 18, color: live ? AppColors.textMid : AppColors.textHint);

    return Semantics(
      container: true,
      button: true,
      enabled: live,
      label: label,
      value: spoken,
      hint: live ? 'اضغط لاختيار باقة' : null,
      onTap: live ? () => _open(context) : null,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: live ? () => _open(context) : null,
          focusColor: AppColors.brandSoftBg,
          child: ConstrainedBox(
            constraints:
                BoxConstraints(minHeight: compact ? H.segment : H.button),
            child: Padding(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 10, vertical: Sp.sm)
                  : const EdgeInsets.symmetric(horizontal: 14, vertical: Sp.md),
              child: Row(
                children: [
                  if (!empty) ...[
                    Icon(
                      LucideIcons.package,
                      size: compact ? 16 : 18,
                      color: sel != null
                          ? AppColors.brandAccent
                          : AppColors.textHint,
                    ),
                    const SizedBox(width: Sp.sm),
                  ],
                  Expanded(child: value),
                  if (!empty) ...[
                    const SizedBox(width: Sp.sm),
                    trailing,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// قيمة الحقل: الاسم بسطرٍ كامل، وتحته السعر (والنقاط) و«الحاليّة».
///
/// سطران لا سطر: على ٣٢٠ بتكبير ١٫٢ لا يتّسع سطرٌ واحد للاسم والسعر
/// والوسم معاً — فيُقصّ الاسم، وهو أهمّ ما في الحقل.
class _FieldValue extends StatelessWidget {
  const _FieldValue({required this.option, required this.current});
  final PackageOption option;
  final bool current;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final price = option.price;
    final points = option.points ?? 0;
    final hasMeta = price != null || points > 0 || current;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          iso(option.name),
          style: AppType.input(color: AppColors.textHi),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (hasMeta) ...[
          const SizedBox(height: Sp.xxs),
          Wrap(
            spacing: Sp.x6,
            runSpacing: Sp.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (price != null)
                Text(
                  _priceLabel(price),
                  textDirection: TextDirection.ltr,
                  style: AppType.bodyStrong(color: AppColors.brandAccent)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              if (points > 0)
                ToneChip(
                  label: _pointsLabel(points),
                  tone: AppTone.warning,
                  dense: true,
                ),
              if (current) const _CurrentChip(),
            ],
          ),
        ],
      ],
    );
  }
}

/// وسم «الحاليّة» — باقة المشترك الآن.
class _CurrentChip extends StatelessWidget {
  const _CurrentChip();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return const ToneChip(label: 'الحاليّة', tone: AppTone.brand, dense: true);
  }
}

/// ورقة الباقات: رأس الطقم + بحث (لأكثر من ستّ) + صفوف اختيار.
class _PackagePickerSheet extends StatefulWidget {
  const _PackagePickerSheet({
    required this.options,
    required this.selectedId,
    required this.currentId,
    required this.title,
  });

  final List<PackageOption> options;
  final String? selectedId;
  final String? currentId;
  final String title;

  @override
  State<_PackagePickerSheet> createState() => _PackagePickerSheetState();
}

class _PackagePickerSheetState extends State<_PackagePickerSheet> {
  final _search = TextEditingController();

  /// صفّ المختارة — تُمرَّر القائمة إليه عند الفتح لو كان أسفلها.
  final _selectedKey = GlobalKey();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  /// القائمة تبدأ من أوّلها (ترتيب الخادم)؛ وإن وقعت المختارة خارج ما يظهر
  /// تُمرَّر إليها وتُوسَّط — لا تحريك حين تكون ظاهرةً أصلاً.
  void _revealSelected() {
    final ctx = _selectedKey.currentContext;
    if (!mounted || ctx == null) return;
    final box = ctx.findRenderObject();
    final position = Scrollable.maybeOf(ctx)?.position;
    final viewport = box == null ? null : RenderAbstractViewport.maybeOf(box);
    if (box == null || position == null || viewport == null) return;
    final atTop = viewport.getOffsetToReveal(box, 0.0).offset;
    final atBottom = viewport.getOffsetToReveal(box, 1.0).offset;
    final visible =
        position.pixels >= atBottom - 0.5 && position.pixels <= atTop + 0.5;
    if (visible) return;
    Scrollable.ensureVisible(ctx, alignment: 0.5);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// مطابقةٌ تتسامح مع ما يكتبه المدير: الأرقام الهنديّة («٥٠») والفواصل
  /// والمسافات («50000» تجد «Ta3leem 50,000»، و«plus3» تجد «Plus 3 Months»).
  static String _norm(String s) => (normalizeDigits(s) ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[\s,،٬._\-]+'), '');

  bool _isCurrent(PackageOption o) {
    final c = widget.currentId;
    return c != null && c.isNotEmpty && o.id == c;
  }

  void _pick(PackageOption o) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(o.id);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final all = widget.options;
    final withSearch = all.length > _searchThreshold;
    final q = _norm(_query);
    final shown =
        q.isEmpty ? all : all.where((o) => _norm(o.name).contains(q)).toList();
    // المفتاح لأوّل صفٍّ مختار وحده — معرّفٌ مكرّر لا يُكرّر GlobalKey.
    final keyAt = shown.indexWhere((o) => o.id == widget.selectedId);

    final Widget list = shown.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(Sp.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.searchX,
                      size: 28, color: AppColors.textHint),
                  const SizedBox(height: Sp.sm),
                  Text(
                    'لا توجد باقة بهذا الاسم',
                    style: AppType.body(color: AppColors.textMid),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        : SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: Sp.xl,
                      endIndent: Sp.xl,
                      color: AppColors.divider,
                    ),
                  _PackageRow(
                    key: i == keyAt ? _selectedKey : null,
                    option: shown[i],
                    selected: shown[i].id == widget.selectedId,
                    current: _isCurrent(shown[i]),
                    onTap: () => _pick(shown[i]),
                  ),
                ],
              ],
            ),
          );

    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.package,
        title: widget.title,
        subtitle: _countLabel(all.length),
        onClose: () => Navigator.of(context).pop(),
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      // كثيرةٌ ⇒ بحثٌ وورقةٌ بطول الشاشة (لا تقفز حين تقصر النتائج)؛
      // قليلةٌ ⇒ الورقة بقدر صفوفها.
      body: withSearch
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(Sp.xl, Sp.md, Sp.xl, Sp.sm),
                  child: SheetSearchField(
                    controller: _search,
                    hint: 'ابحث باسم الباقة…',
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                Expanded(child: list),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: Sp.xs),
                Flexible(child: list),
              ],
            ),
    );
  }
}

/// صفّ باقة في الورقة — دائرة الاختيار + الاسم (و«الحاليّة») + السعر.
class _PackageRow extends StatelessWidget {
  const _PackageRow({
    super.key,
    required this.option,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final PackageOption option;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final price = option.price;
    final points = option.points ?? 0;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: _spokenValue(option, current: current),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.brandSoftBg : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          focusColor: AppColors.brandSoftBg,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: Sp.xl, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    selected ? LucideIcons.circleCheck : LucideIcons.circle,
                    size: 20,
                    color: selected ? AppColors.brand : AppColors.textHint,
                  ),
                  const SizedBox(width: Sp.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          iso(option.name),
                          style: AppType.input(
                            color: selected
                                ? AppColors.textHi
                                : AppColors.textBody,
                          ).copyWith(
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (current) ...[
                          const SizedBox(height: Sp.xs),
                          const _CurrentChip(),
                        ],
                      ],
                    ),
                  ),
                  if (price != null || points > 0) ...[
                    const SizedBox(width: Sp.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (price != null)
                          Text(
                            _priceLabel(price),
                            textDirection: TextDirection.ltr,
                            style:
                                AppType.bodyStrong(color: AppColors.brandAccent)
                                    .copyWith(fontWeight: FontWeight.w700),
                          ),
                        if (points > 0) ...[
                          if (price != null) const SizedBox(height: Sp.xxs),
                          ToneChip(
                            label: _pointsLabel(points),
                            tone: AppTone.warning,
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
