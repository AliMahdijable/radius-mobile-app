import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/util/format.dart';
import '../../../core/util/phone.dart';
import '../../../core/widgets/permission_locked.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/desk_pressable.dart';
import '../../../models/subscriber.dart';
import '../../../services/permissions_service.dart';
import '../../../services/subscriber_usage_store.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../desktop/desk_table_scroll.dart';
import '../sheets/activate_sheet.dart';
import '../sheets/add_debt_sheet.dart';
import '../sheets/add_credit_sheet.dart';
import '../sheets/consumption_sheet.dart';
import '../sheets/edit_subscriber_sheet.dart';
import '../sheets/extend_sheet.dart';
import '../sheets/movements_sheet.dart';
import '../sheets/pay_debt_sheet.dart';
import '../sheets/quick_discount_sheet.dart';
import '../sheets/subscriber_price_sheet.dart';
import 'device_chip_micro.dart' show DeviceProbeBus;
import 'sort_sheet.dart';
import 'subscriber_card_v3.dart';
import 'subscriber_columns.dart';
import '../../../core/widgets/print_feedback.dart';
import '../../../services/receipt_service.dart';

/// أعمدة جدول المشتركين على هذا العرض: ما اختاره المدير من زرّ «الأعمدة» بترتيبه، كلٌّ بعرضه (الافتراضيّ أو ما
/// سحبه المدير). لا يسقط عمود حين يضيق الجدول: **الجدول كلّه** يتمرّر يميناً ويساراً قطعةً واحدة — لا جزءٌ ثابت ولا
/// خطٌّ يقسمه (المالك ٢٤ أكتوبر: «الجدول خلي بي سكرول يمين ويسار ويعرض كل الاعمده… بدون ما يظهر الصفحة مقسومة»).
///
/// بلا عرضٍ مثبَّت لـ«المشترك» يملأ ما يبقى حين يتّسع الكلّ؛ وإن ثبّته المدير يبقى بعرضه والباقي فراغٌ قبل الإجراءات.
class SubscriberTableColumns {
  const SubscriberTableColumns({
    required this.shown,
    required this.widths,
    required this.nameWidth,
    required this.viewport,
    required this.content,
  });

  final List<SubCol> shown;
  final Map<SubCol, double> widths;
  final double nameWidth;

  /// عرض الجدول الظاهر (داخل حدّيه)، وعرض محتوى الصفّ كلّه: الأكبر من مجموع الأعمدة والنافذة.
  final double viewport;
  final double content;

  bool has(SubCol c) => shown.contains(c);
  double widthOf(SubCol c) => widths[c] ?? c.defaultWidth;

  /// المحتوى أعرض من الجدول ⇒ شريط تمريرٍ أفقيّ تحته.
  bool get scrolls => content - viewport > 0.5;

  static const double stripe = 4;
  static const double check = 40;
  static const double avatar = 52;

  /// أضيق ما يُسحب إليه «المشترك».
  static const double nameMin = 140;

  /// «المشترك» غير المثبَّت يملأ الباقي ما لم يضق عن هذا — دونه يتمرّر الجدول وهو على [nameDefault].
  static const double nameAutoMin = 170;
  static const double nameDefault = 200;
  static const double nameMax = 640;

  /// الأزرار الأربعة وفراغاتها (١٤٠) + هامشٌ بنهايتها (١٢) — كان «…» ملتصقاً بحافّة الجدول
  /// (المالك ٢٩ أكتوبر: «ليش ملتصق هيج»). الرأس يحجز الثابت نفسه فيبقى محاذياً.
  static const double actions = 152;

  /// حدّا الجدول الأيمن والأيسر (١ لكلٍّ منهما).
  static const double borders = 2;

  /// ما قبل «المشترك»: شريط الحالة والفراغ ومربّع التحديد والصورة.
  static const double lead = stripe + (Sp.sm - 4) + check + avatar;

  static SubscriberTableColumns forWidth(double width) {
    final inner = width - borders > 0 ? width - borders : 0.0;
    final shown = [
      for (final e in SubscriberColumnPrefs.layout.value)
        if (e.$2 && e.$1.available) e.$1,
    ];
    final widths = {for (final c in shown) c: SubscriberColumnPrefs.widthOf(c)};
    final cols = widths.values.fold<double>(0, (s, w) => s + w);
    final room = inner - lead - actions > 0 ? inner - lead - actions : 0.0;
    final pinned = SubscriberColumnPrefs.nameWidth?.clamp(nameMin, nameMax).toDouble();
    final double name = pinned ?? ((nameAutoMin + cols <= room) ? room - cols : nameDefault);
    final total = lead + name + cols + actions;
    return SubscriberTableColumns(
      shown: shown,
      widths: widths,
      nameWidth: name,
      viewport: inner,
      content: total > inner ? total : inner,
    );
  }
}

/// تغيير عرض عمودٍ بالسحب — تستدعيه الشاشة من مقبض الرأس. [key] اسم العمود أو [SubscriberColumnPrefs.nameKey]،
/// و[delta] التغيّر المطلوب بالبكسل (موجبٌ = أعرض).
///
/// أوّل سحبٍ لعمودٍ من الأعمدة و«المشترك» يملأ: يُثبَّت «المشترك» على عرضه الظاهر أوّلاً — وإلّا امتصّ هو التغيّر
/// فتحرّكت الحافّة التي قبل العمود لا الحافّة التي تحت المؤشّر.
void resizeSubscriberColumn(SubscriberTableColumns cols, String key, double delta) {
  final live = Map<String, double>.from(SubscriberColumnPrefs.widths.value);
  const nameKey = SubscriberColumnPrefs.nameKey;
  if (key != nameKey && !live.containsKey(nameKey)) live[nameKey] = cols.nameWidth;
  if (key == nameKey) {
    live[key] = (cols.nameWidth + delta)
        .clamp(SubscriberTableColumns.nameMin, SubscriberTableColumns.nameMax)
        .toDouble();
  } else {
    final c = SubCol.values.byName(key);
    live[key] = (cols.widthOf(c) + delta).clamp(c.minWidth, SubColInfo.maxWidth).toDouble();
  }
  SubscriberColumnPrefs.setWidthsLive(live);
}

/// رأس الجدول: تسمياتٌ خافتة، وما يُرتَّب به سهمٌ يدلّ على الترتيب الحاليّ واتّجاهه — نقرةٌ ترتّب ونقرةٌ ثانية
/// تعكس. وعلى نهاية كلّ عمودٍ مقبضٌ يُسحب لتوسيعه أو تضييقه (والنقر المزدوج يعيده).
class SubscriberTableHeader extends StatelessWidget {
  const SubscriberTableHeader({
    super.key,
    required this.columns,
    required this.scroll,
    required this.sortField,
    required this.descending,
    required this.onSort,
    required this.allSelected,
    required this.onSelectAll,
    required this.onResize,
    required this.onResizeEnd,
    required this.onResetWidth,
  });

  final SubscriberTableColumns columns;
  final DeskHScroll scroll;
  final SortField sortField;
  final bool descending;
  final ValueChanged<SortField> onSort;
  final bool allSelected;
  final VoidCallback onSelectAll;
  final void Function(String key, double delta) onResize;
  final VoidCallback onResizeEnd;
  final ValueChanged<String> onResetWidth;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    Widget label(String text, {SortField? field, Alignment align = Alignment.centerRight}) {
      final active = field != null && field == sortField;
      final style = AppType.muted(color: active ? AppColors.textHi : AppColors.textMid)
          .copyWith(fontSize: 13, fontWeight: active ? FontWeight.w700 : FontWeight.w500);
      final row = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          // سهم الترتيب على العمود المرتَّب وحده (البقيّة قابلةٌ للنقر بتلميحها) — لا أسهمٌ على كلّ رأس.
          if (active) ...[
            const SizedBox(width: 4),
            Icon(
              descending ? LucideIcons.arrowDown : LucideIcons.arrowUp,
              size: 13,
              color: AppColors.textHi,
            ),
          ],
        ],
      );
      final aligned = Align(alignment: _directional(align), child: row);
      if (field == null) return aligned;
      return Tooltip(
        message: 'desktop.sort_by'.tr(args: [text]),
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSort(field),
            child: aligned,
          ),
        ),
      );
    }

    // خليّة رأسٍ بعرض عمودها، ومقبض السحب فوق حافّتها الأخيرة (لا يأخذ من عرض العمود).
    Widget cell(String key, double width, Widget child) => SizedBox(
          width: width,
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: Sp.xs),
                  child: child,
                ),
              ),
              PositionedDirectional(
                end: 0,
                top: 0,
                bottom: 0,
                child: DeskColResizeHandle(
                  tooltip: 'desktop.col_resize_tip'.tr(),
                  onDrag: (d) => onResize(key, d),
                  onEnd: onResizeEnd,
                  onReset: () => onResetWidth(key),
                ),
              ),
            ],
          ),
        );

    final cols = columns;
    return _dragScroll(context, cols, scroll, Container(
      height: 48,
      // بلا شريط تعبئة: رأسٌ على سطح الجدول نفسه وخطٌّ أقوى تحته (قواعد الجداول المقيسة).
      // (إطارٌ موحّد اللون مع الزوايا — فلاتر يرفض زوايا على إطارٍ بألوانٍ مختلفة — والخطّ الأقوى فوقه.)
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
        border: Border.all(color: AppColors.border),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderStrong)),
      ),
      // الرأس كلّه يتمرّر مع الصفوف قطعةً واحدة.
      child: DeskHViewport(
        scroll: scroll,
        contentWidth: cols.content,
        child: Row(
          children: [
            const SizedBox(width: SubscriberTableColumns.stripe + Sp.sm - 4),
            SizedBox(
              width: SubscriberTableColumns.check,
              child: _CheckBox(value: allSelected, onTap: onSelectAll),
            ),
            const SizedBox(width: SubscriberTableColumns.avatar),
            cell(
              SubscriberColumnPrefs.nameKey,
              cols.nameWidth,
              label('desktop.col_name'.tr(), field: SortField.firstname),
            ),
            for (final c in cols.shown)
              cell(c.name, cols.widthOf(c), label(c.label, field: c.sortField, align: _alignOf(c))),
            const Spacer(),
            const SizedBox(width: SubscriberTableColumns.actions),
          ],
        ),
      ),
    ));
  }
}

Alignment _alignOf(SubCol c) => switch (c) {
      SubCol.package || SubCol.expiration || SubCol.remaining => Alignment.center,
      SubCol.balance => Alignment.centerLeft,
      _ => Alignment.centerRight,
    };

/// محاذاة بالاتّجاه: «بداية» السطر يمينٌ بالعربيّة.
AlignmentDirectional _directional(Alignment a) => a == Alignment.center
    ? AlignmentDirectional.center
    : a == Alignment.centerLeft
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;

/// السحب الأفقيّ بالفأرة على الرأس أو صفٍّ يمرّر الأعمدة (المحتوى يتبع المؤشّر) — حين يكون هناك ما يتمرّر وحده،
/// فالنقر والقائمة والتمرير العموديّ كما هي.
Widget _dragScroll(BuildContext context, SubscriberTableColumns cols, DeskHScroll scroll, Widget child) {
  if (!cols.scrolls) return child;
  final rtl = Directionality.of(context) == TextDirection.rtl;
  return GestureDetector(
    onHorizontalDragUpdate: (d) => scroll.scrollBy(rtl ? d.delta.dx : -d.delta.dx),
    child: child,
  );
}

/// خليّة صفٍّ بعرض عمودها نفسه (عرض الرأس) — فتبقى القيمة تحت تسميتها.
Widget _cellBox(SubscriberTableColumns cols, SubCol c, Widget child) => SizedBox(width: cols.widthOf(c), child: child);

/// صفّ مشترك في جدول الحاسبة بلغة الموقع: شريطٌ بلون الحالة على الحافّة، مربّع تحديد، صورةٌ
/// بالأحرف الأولى ونقطة الاتّصال، الاسم واليوزر، ثمّ الأعمدة المختارة بترتيبها، ثمّ الإجراءات
/// (تجديد وتمديد عند المرور + «…» بكلّ الإجراءات، والزرّ الأيمن يفتح القائمة نفسها).
class SubscriberTableRow extends StatefulWidget {
  const SubscriberTableRow({
    super.key,
    required this.sub,
    required this.columns,
    required this.scroll,
    required this.open,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onToggleSelect,
    this.hasTelegram = false,
    this.last = false,
  });

  /// آخر صفٍّ ظاهر: زاويتا الجدول السفليّتان.
  final bool last;

  /// مربوطٌ ببوت تلغرام — شارةٌ صغيرة بجنب الاسم كبطاقة الهاتف.
  final bool hasTelegram;

  final Subscriber sub;
  final SubscriberTableColumns columns;

  /// موضع التمرير الأفقيّ المشترك مع الرأس وبقيّة الصفوف.
  final DeskHScroll scroll;

  /// مفتوحٌ الآن في لوحة التفاصيل.
  final bool open;

  /// محدَّدٌ للعمليّات الجماعيّة.
  final bool selected;
  final bool selectionMode;

  /// فتح التفاصيل (اللوحة) — وفيها ما لا تحمله القائمة (تعطيل، فصل، حذف، إرسال…).
  final VoidCallback onTap;
  final VoidCallback onToggleSelect;

  @override
  State<SubscriberTableRow> createState() => _SubscriberTableRowState();
}

class _SubscriberTableRowState extends State<SubscriberTableRow> {

  void _menuAt(Offset global) {
    showSubscriberRowMenu(context, widget.sub, position: global, onOpenDetails: widget.onTap);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = widget.sub;
    final st = SubscriberCardV3.statusOf(s);
    final name = s.fullName.trim().isEmpty ? s.username : s.fullName.trim();
    final cols = widget.columns;
    // اللون على الحافّة لمن يحتاج انتباهاً وحده (منتهٍ أو قارب) — الباقي بلا لون، لا لونٌ مختلف لكلّ صفّ.
    final attention = s.isExpired || s.isNearExpiry;
    final packageInline = !cols.has(SubCol.package) && (s.profileName ?? '').isNotEmpty;
    // Tab إلى الصفّ ثمّ Enter يفتحه كالنقر (أو يحدّده في وضع التحديد)، بإطار تركيزٍ مع الكيبورد وحده.
    return _dragScroll(context, cols, widget.scroll, DeskPressable(
      onTap: widget.selectionMode ? widget.onToggleSelect : widget.onTap,
      onSecondaryTapUp: (d) => _menuAt(d.globalPosition),
      onLongPressStart: (d) => _menuAt(d.globalPosition),
      selected: widget.selected || widget.open,
      semanticLabel: name,
      builder: (context, hover) {
        // المختار/المفتوح بحبّة القائمة الرماديّة نفسها (لا أخضر)، والمرور أخفّ منها.
        final bg = widget.selected || widget.open
            ? AppColors.surfaceSunken
            : hover
                ? AppColors.surfaceSunken.withValues(alpha: 0.5)
                : AppColors.surface;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 66,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: bg,
            borderRadius:
                widget.last ? const BorderRadius.vertical(bottom: Radius.circular(R.lg)) : null,
            border: Border(
              left: BorderSide(color: AppColors.border),
              right: BorderSide(color: AppColors.border),
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
          // الصفّ كلّه يتمرّر مع الرأس قطعةً واحدة.
          child: DeskHViewport(
            scroll: widget.scroll,
            contentWidth: cols.content,
            child: Row(
            children: [
              Tooltip(
                message: st.label,
                child: Container(
                  width: SubscriberTableColumns.stripe,
                  color: attention ? st.color : Colors.transparent,
                ),
              ),
              const SizedBox(width: Sp.sm - 4),
              SizedBox(
                width: SubscriberTableColumns.check,
                child: _CheckBox(value: widget.selected, onTap: widget.onToggleSelect),
              ),
              SizedBox(
                width: SubscriberTableColumns.avatar,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _Avatar(name: name, online: s.isOnline, disabled: s.isDisabled),
                ),
              ),
              SizedBox(
                width: cols.nameWidth,
                child: _TwoLines(
                  fullOnHover: true,
                  top: name,
                  topStyle: AppType.label(color: s.isDisabled ? AppColors.textMid : AppColors.textHi)
                      .copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    decoration: s.isDisabled ? TextDecoration.lineThrough : null,
                  ),
                  trailing: _nameTrailing(s),
                  bottom: packageInline ? '${s.username} · ${s.profileName}' : s.username,
                  bottomLtr: true,
                ),
              ),
              for (final c in cols.shown) _cellBox(cols, c, _cell(c, s)),
              const Spacer(),
              SizedBox(
                width: SubscriberTableColumns.actions,
                child: _RowActions(
                  sub: s,
                  hover: hover || widget.open,
                  onMenu: _menuAt,
                ),
              ),
            ],
          ),
          ),
        );
      },
    ));
  }

  /// شارات بجنب الاسم: مربوط بتلغرام + «متّصل بلا باقة» — كبطاقة الهاتف.
  Widget? _nameTrailing(Subscriber s) {
    final onlineExpired = s.isOnline && s.isExpired;
    if (!widget.hasTelegram && !onlineExpired) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.hasTelegram)
          Tooltip(
            message: 'subscribers.telegram_linked'.tr(),
            child: Icon(Icons.send_rounded, size: 13, color: AppColors.brandAccent),
          ),
        if (widget.hasTelegram && onlineExpired) const SizedBox(width: 5),
        if (onlineExpired)
          Tooltip(
            message: 'subscribers.filter_online_no_plan'.tr(),
            child: Icon(LucideIcons.triangleAlert, size: 14, color: AppColors.anomaly),
          ),
      ],
    );
  }

  Widget _cell(SubCol c, Subscriber s) {
    final dash = Text('—', style: AppType.muted(color: AppColors.textLow));
    switch (c) {
      case SubCol.phone:
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: Sp.sm),
          child: _PhoneCell(phone: s.displayPhone),
        );
      case SubCol.package:
        return Center(child: _PackageCell(sub: s));
      case SubCol.manager:
        final m = s.parentUsername?.trim() ?? '';
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: m.isEmpty
              ? dash
              : Text(
                  m,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 13),
                ),
        );
      case SubCol.expiration:
        final exp = s.parsedExpiration;
        if (exp == null) return Center(child: dash);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat('yyyy-MM-dd').format(exp),
              textDirection: TextDirection.ltr,
              style: AppType.label(color: AppColors.textBody)
                  .copyWith(fontSize: 13.5, fontWeight: FontWeight.w600, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            Text(
              DateFormat('HH:mm').format(exp),
              textDirection: TextDirection.ltr,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        );
      case SubCol.remaining:
        return _DaysCell(sub: s);
      case SubCol.session:
        final v = SubscriberCardV3.sessionOf(s);
        if (v == null) return Align(alignment: AlignmentDirectional.centerStart, child: dash);
        return Row(
          children: [
            Icon(v.icon, size: 14, color: v.color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                v.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.muted(color: s.isOnline ? v.color : AppColors.textMid)
                    .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      case SubCol.mac:
        return _IpSignalCell(sub: s);
      case SubCol.device:
        return _DeviceCell(sub: s);
      case SubCol.usage:
        return _UsageCell(sub: s);
      case SubCol.balance:
        return Padding(
          padding: const EdgeInsetsDirectional.only(start: Sp.sm),
          child: Align(alignment: AlignmentDirectional.centerEnd, child: _balance(s)),
        );
    }
  }

  Widget _balance(Subscriber s) {
    final currency = 'common.currency'.tr();
    if (s.hasDebt) {
      return Text(
        '${formatIQD(s.debtAbs.round())} $currency',
        maxLines: 1,
        style: AppType.label(color: AppColors.dangerOnSoft)
            .copyWith(fontWeight: FontWeight.w700, fontSize: 14, fontFeatures: const [FontFeature.tabularFigures()]),
      );
    }
    if (s.hasCredit) {
      return Text(
        '+${formatIQD(s.balanceAmount.round())} $currency',
        maxLines: 1,
        style: AppType.label(color: AppColors.brandOnSoft)
            .copyWith(fontWeight: FontWeight.w700, fontSize: 14, fontFeatures: const [FontFeature.tabularFigures()]),
      );
    }
    return Text('—', style: AppType.muted(color: AppColors.textLow));
  }
}

// ───────────────────────────── الإجراءات ─────────────────────────────

/// تجديد وتمديد وطباعة الوصل تظهر عند المرور على الصفّ (كالموقع)، و«…» دائماً.
class _RowActions extends StatelessWidget {
  const _RowActions({required this.sub, required this.hover, required this.onMenu});

  final Subscriber sub;
  final bool hover;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    Widget quick(IconData icon, String tip, String perm, Future<Object?> Function() run) {
      final locked = !Perms.has(perm);
      if (locked && !permShown([perm])) return const SizedBox(width: 32);
      return AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: hover ? 1 : 0,
        child: IgnorePointer(
          ignoring: !hover,
          child: _MiniAction(
            icon: locked ? LucideIcons.lock : icon,
            color: locked ? LockedStyle.glyph : AppColors.brandAccent,
            tooltip: tip,
            onTap: locked ? () => showNoPermission(context) : () => run(),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        quick(LucideIcons.zap, 'desktop.act_renew'.tr(), 'subscribers.activate',
            () => showActivateSheet(context, sub)),
        const SizedBox(width: 4),
        quick(LucideIcons.calendarPlus, 'subscribers.op_extend'.tr(), 'subscribers.extend',
            () => showExtendSheet(context, sub)),
        const SizedBox(width: 4),
        // «طباعة وصل» بنقرة (المالك ٢٤ أكتوبر: «زر طباعة مباشر ماكو») — بلا صلاحيّة كالموقع.
        AnimatedOpacity(
          duration: const Duration(milliseconds: 120),
          opacity: hover ? 1 : 0,
          child: IgnorePointer(
            ignoring: !hover,
            child: _MiniAction(
              icon: LucideIcons.printer,
              color: AppColors.brandAccent,
              tooltip: 'printer.receipt'.tr(),
              onTap: () => printSubscriberReceipt(context, sub),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Builder(
          builder: (btn) => _MiniAction(
            icon: LucideIcons.ellipsis,
            color: AppColors.textHi,
            tooltip: 'desktop.more_actions'.tr(),
            onTap: () {
              final box = btn.findRenderObject() as RenderBox;
              onMenu(box.localToGlobal(Offset(0, box.size.height)));
            },
          ),
        ),
        // هامش النهاية — لا يلتصق «…» بحافّة الجدول ([SubscriberTableColumns.actions]).
        const SizedBox(width: 12),
      ],
    );
  }
}

/// بطاقة معلومات المشترك إلى الطابعة — مباشرةً إن اختيرت «طابعة مباشرة»، وإلّا نافذة الطباعة.
Future<void> printSubscriberReceipt(BuildContext context, Subscriber s) async {
  final r = await ReceiptService.printSubscriberCard(s);
  if (context.mounted) showPrintResult(context, r);
}

/// قائمة إجراءات المشترك (زرّ «…» والزرّ الأيمن): ما تفتحه الشيتات نفسها التي تفتحها التفاصيل،
/// بالبوّابات نفسها — مقفلٌ بمكانه لمن لا يملكه (قاعدة «مقفل لا مخفيّ»). ما يغيّر الحالة بلا شيت
/// (تعطيل، فصل، حذف، إرسال) يبقى في التفاصيل — «كلّ الإجراءات» آخر القائمة.
Future<void> showSubscriberRowMenu(
  BuildContext context,
  Subscriber s, {
  required Offset position,
  required VoidCallback onOpenDetails,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final items = <_MenuEntry?>[
    _gate('subscribers.activate', LucideIcons.zap, 'desktop.act_renew'.tr(),
        () => showActivateSheet(context, s)),
    _gate('subscribers.extend', LucideIcons.calendarPlus, 'subscribers.op_extend'.tr(),
        () => showExtendSheet(context, s)),
    _gate('subscribers.edit', LucideIcons.pencil, 'subscribers.op_edit'.tr(),
        () => showEditSubscriberSheet(context, s)),
    null,
    if (s.hasDebt)
      _gate('subscribers.pay_debt', LucideIcons.banknote, 'subscribers.op_pay_debt'.tr(),
          () => showPayDebtSheet(context, s)),
    _gate('subscribers.add_debt', LucideIcons.plus, 'subscribers.op_add_debt'.tr(),
        () => showAddDebtSheet(context, s)),
    _gate('subscribers.add_credit', LucideIcons.coins, 'إضافة رصيد',
        () => showAddCreditSheet(context, s)),
    _gate('discounts.manage', LucideIcons.tag, 'subscribers.op_quick_discount'.tr(),
        () => showQuickDiscountSheet(context, s)),
    if (s.idx != null)
      _gate(
          'subscriber_prices.manage',
          LucideIcons.badgeDollarSign,
          'sp.op_fixed_price'.tr(),
          () => showSubscriberPriceSheet(
                context,
                idx: s.idx!,
                name: s.fullName.trim().isNotEmpty ? s.fullName : s.username,
                companyKey: s.companyKey,
              )),
    null,
    _MenuEntry(LucideIcons.chartLine, 'subscribers.op_consumption'.tr(),
        () => showConsumptionSheet(context, s)),
    _gate('subscribers.view_activity', LucideIcons.history, 'subscribers.op_movements'.tr(),
        () => showMovementsSheet(context, s)),
    _MenuEntry(LucideIcons.printer, 'printer.receipt'.tr(), () async {
      await printSubscriberReceipt(context, s);
      return null;
    }),
    _MenuEntry(LucideIcons.copy, 'desktop.copy_username'.tr(), () async {
      await Clipboard.setData(ClipboardData(text: s.username));
      if (context.mounted) showSheetSnack(context, 'desktop.copied'.tr());
      return null;
    }),
    null,
    _MenuEntry(LucideIcons.panelLeftOpen, 'desktop.all_actions'.tr(), () async => onOpenDetails()),
  ].where((e) => e != const _Hidden()).toList();

  // فواصل لا تتكرّر ولا تبدأ القائمة.
  final entries = <PopupMenuEntry<int>>[];
  final actions = <int, _MenuEntry>{};
  for (final e in items) {
    if (e == null) {
      if (entries.isNotEmpty && entries.last is! PopupMenuDivider) {
        entries.add(const PopupMenuDivider(height: 9));
      }
      continue;
    }
    final i = actions.length;
    actions[i] = e;
    entries.add(PopupMenuItem<int>(
      value: i,
      height: 40,
      child: Row(
        children: [
          Icon(e.locked ? LucideIcons.lock : e.icon,
              size: 17, color: e.locked ? LockedStyle.glyph : AppColors.textMid),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Text(
              e.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.body(color: e.locked ? LockedStyle.title : AppColors.textHi)
                  .copyWith(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    ));
  }
  final picked = await showMenu<int>(
    context: context,
    position: RelativeRect.fromRect(position & const Size(1, 1), Offset.zero & overlay.size),
    color: AppColors.surface,
    constraints: const BoxConstraints(minWidth: 230, maxWidth: 300),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(R.md),
      side: BorderSide(color: AppColors.border),
    ),
    items: entries,
  );
  if (picked == null || !context.mounted) return;
  final e = actions[picked]!;
  if (e.locked) {
    showNoPermission(context);
    return;
  }
  await e.run();
}

class _MenuEntry {
  const _MenuEntry(this.icon, this.label, this.run, {this.locked = false});

  final IconData icon;
  final String label;
  final Future<Object?> Function() run;
  final bool locked;
}

class _Hidden extends _MenuEntry {
  const _Hidden() : super(LucideIcons.x, '', _noop);
  static Future<Object?> _noop() async => null;
}

/// يملكه ⇒ حيّ؛ لا يملكه ويمكن أن يُمنحه ⇒ مقفل بمكانه؛ لا يُمنح لدوره ⇒ مخفيّ (كالتفاصيل).
_MenuEntry _gate(String perm, IconData icon, String label, Future<Object?> Function() run) {
  if (Perms.has(perm)) return _MenuEntry(icon, label, run);
  if (permShown([perm])) return _MenuEntry(icon, label, run, locked: true);
  return const _Hidden();
}

// ───────────────────────────── الخلايا ─────────────────────────────

/// الباقة شارةً، وتحتها السعر — والمخصوم يُشطب قبله سعر الباقة كالموقع.
class _PackageCell extends StatelessWidget {
  const _PackageCell({required this.sub});

  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final name = sub.profileName ?? '';
    if (name.isEmpty) return Text('—', style: AppType.muted(color: AppColors.textLow));
    final base = sub.packageSalePrice;
    final now = sub.currentSalePrice;
    final discounted = base != null && now != null && now < base;
    final small = AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()]);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Pill(text: name, fg: AppColors.textBody, bg: AppColors.surfaceSunken, border: AppColors.border),
        if (now != null) ...[
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (discounted) ...[
                Text(formatIQD(base), style: small.copyWith(decoration: TextDecoration.lineThrough)),
                const SizedBox(width: 5),
              ],
              Text(
                formatIQD(now),
                style: discounted || sub.isFixedPrice
                    ? small.copyWith(color: AppColors.brandOnSoft, fontWeight: FontWeight.w700)
                    : small,
              ),
              if (sub.isFixedPrice) ...[
                const SizedBox(width: 3),
                Tooltip(
                  message: 'sp.op_fixed_price'.tr(),
                  child: Icon(LucideIcons.lock, size: 11, color: AppColors.brandOnSoft),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

TextStyle _monoStyle(bool online) => AppType.muted(color: online ? AppColors.info : AppColors.textMid)
    .copyWith(fontSize: 12.5, fontFeatures: const [FontFeature.tabularFigures()]);

Widget _dashCell() => Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text('—', style: AppType.muted(color: AppColors.textLow)),
    );

/// قيمةٌ بسطرٍ واحد من اليسار لليمين، نقرةٌ تنسخها.
Widget _copyableValue(BuildContext context, String v, TextStyle style) => Tooltip(
      message: 'desktop.copy'.tr(),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.sm),
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: v));
          if (context.mounted) showSheetSnack(context, 'desktop.copied'.tr());
        },
        child: Text(v, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr, style: style),
      ),
    );

/// «IP / الإشارة» (٢٩ أكتوبر — المالك: «ما يظهر اشارات المشتركين… تكدر تحقنهن وي حقل الماك ip»): IP الجلسة
/// للمتّصل (نقرةٌ تنسخه) وتحته قراءة جهاز المشترك من كاش الفحص — النانو: الإشارة وسرعة LAN، والـONU: الضوء
/// والحرارة — بألوان صحّة كارت الهاتف نفسها ([SubscriberNetworkMetrics])، وتتحدّث مع موجة الفحص.
class _IpSignalCell extends StatelessWidget {
  const _IpSignalCell({required this.sub});

  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final ip = sub.isOnline ? (sub.ipAddress?.trim() ?? '') : '';
    return ValueListenableBuilder<int>(
      valueListenable: DeviceProbeBus.tick,
      builder: (context, _, __) {
        final probed = SubscriberNetworkMetrics.snapshotOf(sub) != null;
        if (ip.isEmpty && !probed) return _dashCell();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ip.isNotEmpty) _copyableValue(context, ip, _monoStyle(sub.isOnline)),
            if (probed) ...[
              if (ip.isNotEmpty) const SizedBox(height: 3),
              SubscriberNetworkMetrics(sub: sub, wrap: true),
            ],
          ],
        );
      },
    );
  }
}

/// «الماك / الجهاز» (٢٩ أكتوبر — المالك: «الماك واسم الجهاز اعزله بحقل ثاني اختيار الاظهار»؛ يُخفى ويُظهَر من
/// «الأعمدة»): الماك (نقرةٌ تنسخه) — ماك الجلسة الحيّة للمتّصل وآخر ماكٍ لغيره — وتحته اسم الجهاز: اسم النانو أو
/// طراز الـONU من الفحص، وإلّا مصنّع الراوتر كما يقوله الساس.
class _DeviceCell extends StatelessWidget {
  const _DeviceCell({required this.sub});

  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final mac = sub.lastMac?.trim() ?? '';
    return ValueListenableBuilder<int>(
      valueListenable: DeviceProbeBus.tick,
      builder: (context, _, __) {
        final name = SubscriberNetworkMetrics.deviceNameOf(sub, SubscriberNetworkMetrics.snapshotOf(sub));
        if (mac.isEmpty && name == null) return _dashCell();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mac.isNotEmpty) _copyableValue(context, mac, _monoStyle(sub.isOnline)),
            if (name != null) ...[
              if (mac.isNotEmpty) const SizedBox(height: 2),
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12)),
            ],
          ],
        );
      },
    );
  }
}

/// استهلاك اليوم فوق الشهر — يُطلب للصفوف الظاهرة وحدها (دفعاتٌ من [SubscriberUsageStore]).
class _UsageCell extends StatelessWidget {
  const _UsageCell({required this.sub});

  final Subscriber sub;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final idx = sub.idx;
    if (idx == null) return Text('—', style: AppType.muted(color: AppColors.textLow));
    return ValueListenableBuilder<int>(
      valueListenable: SubscriberUsageStore.version,
      builder: (context, _, __) {
        final e = SubscriberUsageStore.get(idx, company: sub.companyKey);
        if (e == null) SubscriberUsageStore.want(idx, company: sub.companyKey);
        final label = AppType.muted(color: AppColors.textLow).copyWith(fontSize: 12.5);
        final value = AppType.label(color: AppColors.textBody)
            .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600);
        if (e == null) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              width: 90,
              height: 10,
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(R.sm),
              ),
            ),
          );
        }
        if (e.v == null) {
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text('—', style: AppType.muted(color: AppColors.textLow)),
          );
        }
        Widget line(String k, int? bytes) => Text.rich(
              TextSpan(children: [
                TextSpan(text: '$k ', style: label),
                TextSpan(text: '\u2066${formatUsageBytes(bytes)}\u2069', style: value),
              ]),
              maxLines: 1,
            );
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            line('desktop.today'.tr(), e.v!.today),
            const SizedBox(height: 2),
            line('desktop.month'.tr(), e.v!.month),
          ],
        );
      },
    );
  }
}

/// الأيّام بشارةٍ وشريطٍ تحتها يتناقص من ٣٠ يوماً (المنتهي ممتلئٌ بلونه).
class _DaysCell extends StatelessWidget {
  const _DaysCell({required this.sub});

  final Subscriber sub;

  static String _short(String word) {
    if (word.contains('ساعة')) return 'ساعة';
    if (word.contains('دقيقة')) return 'دقيقة';
    if (word.contains('يوم') || word.contains('أيام')) return 'يوم';
    return word;
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final d = SubscriberCardV3.daysOf(sub);
    final exp = sub.parsedExpiration;
    final expired = exp != null && exp.isBefore(DateTime.now());
    final text = d.small == 'منتهي' || d.small == 'معطّل'
        ? d.small
        : d.small.isEmpty
            ? d.big
            : '${d.big} ${_short(d.small)}';
    // أكثر من أسبوع = بخير: رقمٌ عاديّ بلا حبّةٍ خضراء (عشرون حبّةً خضراء في الجدول تغطّي الحمراء والصفراء التي تهمّ).
    final calm = !sub.isDisabled && exp != null && !expired && exp.difference(DateTime.now()).inDays > 7;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: calm ? null : BoxDecoration(color: d.bg, borderRadius: BorderRadius.circular(R.sm)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (expired) ...[
                Icon(LucideIcons.triangleAlert, size: 12, color: d.color),
                const SizedBox(width: 3),
              ],
              Text(
                text,
                maxLines: 1,
                style: AppType.label(color: calm ? AppColors.textHi : d.color).copyWith(
                  fontWeight: calm ? FontWeight.w600 : FontWeight.w700,
                  fontSize: calm ? 13 : 12.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// الهاتف محلّيّاً (نقرةٌ تنسخه) وبجانبه الاتّصال والواتساب.
class _PhoneCell extends StatelessWidget {
  const _PhoneCell({required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (phone.trim().isEmpty) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text('—', style: AppType.muted(color: AppColors.textLow)),
      );
    }
    final local = localPhone(phone);
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return Row(
      children: [
        Flexible(
          child: Tooltip(
            message: 'desktop.copy'.tr(),
            child: InkWell(
              borderRadius: BorderRadius.circular(R.sm),
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: local));
                if (context.mounted) showSheetSnack(context, 'desktop.copied'.tr());
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(
                  local,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: AppType.label(color: AppColors.textBody)
                      .copyWith(fontSize: 13.5, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _MiniAction(
          icon: LucideIcons.messageCircle,
          color: AppColors.success,
          tooltip: 'subscribers.op_whatsapp'.tr(),
          onTap: () => launchUrl(Uri.parse('https://wa.me/$digits'),
              mode: LaunchMode.externalApplication),
        ),
        const SizedBox(width: 4),
        _MiniAction(
          icon: LucideIcons.phone,
          color: AppColors.info,
          tooltip: 'subscribers.call'.tr(),
          onTap: () => launchUrl(Uri.parse('tel:$local'), mode: LaunchMode.externalApplication),
        ),
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.sm),
          child: SizedBox(width: 30, height: 30, child: Icon(icon, size: 15, color: color)),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.online, required this.disabled});

  final String name;
  final bool online;
  final bool disabled;

  static String _initials(String n) {
    final parts = n.trim().split(RegExp(r'[\s@._-]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '•';
    final a = parts.first.characters.first;
    final b = parts.length > 1 ? parts[1].characters.first : '';
    return (a + b).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: disabled ? AppColors.surfaceDisabled : AppColors.infoSoftBg,
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(name),
              style: AppType.label(color: disabled ? AppColors.textLabel : AppColors.info)
                  .copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
          if (!disabled)
            PositionedDirectional(
              start: 0,
              bottom: 4,
              child: Tooltip(
                message: (online ? 'desktop.online' : 'desktop.offline').tr(),
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: online ? AppColors.success : AppColors.textLow,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.value, required this.onTap});

  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Center(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: H.checkbox,
            height: H.checkbox,
            decoration: BoxDecoration(
              color: value ? AppColors.brand : AppColors.surface,
              borderRadius: BorderRadius.circular(R.check),
              border: Border.all(color: value ? AppColors.brand : AppColors.borderStrong, width: 1.5),
            ),
            child: value ? const Icon(LucideIcons.check, size: 14, color: AppColors.onBrand) : null,
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.fg, required this.bg, required this.border});

  final String text;
  final Color fg;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.label(color: fg).copyWith(fontWeight: FontWeight.w600, fontSize: 12.5),
      ),
    );
  }
}

class _TwoLines extends StatelessWidget {
  const _TwoLines({
    required this.top,
    this.bottom,
    this.topStyle,
    this.bottomLtr = false,
    this.trailing,
    this.fullOnHover = false,
  });

  final String top;
  final String? bottom;
  final TextStyle? topStyle;
  final bool bottomLtr;
  final Widget? trailing;

  /// الاسم الطويل يُقصّ بـ«…»: المرور عليه يُظهره كاملاً — حين يُقصّ فعلاً وحده (ui-ux-pro-max: truncation-strategy).
  final bool fullOnHover;

  TextStyle get _topStyle => topStyle ?? AppType.label(color: AppColors.textBody).copyWith(fontSize: 13.5);

  Widget _topText() => Text(top, maxLines: 1, overflow: TextOverflow.ellipsis, style: _topStyle);

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Flexible(
                child: fullOnHover
                    ? LayoutBuilder(builder: (context, c) {
                        final text = _topText();
                        final tp = TextPainter(
                          text: TextSpan(text: top, style: DefaultTextStyle.of(context).style.merge(_topStyle)),
                          maxLines: 1,
                          textDirection: Directionality.of(context),
                          textScaler: MediaQuery.textScalerOf(context),
                        )..layout();
                        final clipped = tp.width > c.maxWidth;
                        tp.dispose();
                        return clipped
                            ? Tooltip(message: top, waitDuration: const Duration(milliseconds: 500), child: text)
                            : text;
                      })
                    : _topText(),
              ),
              if (trailing != null) ...[const SizedBox(width: 5), trailing!],
            ],
          ),
          if (bottom != null && bottom!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              bottom!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: bottomLtr ? TextDirection.ltr : null,
              textAlign: TextAlign.start,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}
