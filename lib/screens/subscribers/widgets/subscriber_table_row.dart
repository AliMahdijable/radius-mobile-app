import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'subscriber_card_v3.dart';

/// أعمدة جدول المشتركين على الحاسبة — الرأس والصفوف بالمقاسات نفسها.
class SubscriberTableColumns {
  const SubscriberTableColumns({required this.showExpiry});

  /// تاريخ الانتهاء يُخفى حين يضيق الجدول (لوحة التفاصيل مفتوحة على نافذةٍ صغيرة) — الأيّام تبقى.
  final bool showExpiry;

  static SubscriberTableColumns forWidth(double width) =>
      SubscriberTableColumns(showExpiry: width >= 640);

  static const double status = 34;
  static const double days = 92;
  static const double balance = 112;
}

/// رأس الجدول: تسمياتٌ خافتة بلا خطوط ثقيلة.
class SubscriberTableHeader extends StatelessWidget {
  const SubscriberTableHeader({super.key, required this.columns});

  final SubscriberTableColumns columns;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final style = AppType.micro(color: AppColors.textLow).copyWith(fontWeight: FontWeight.w600);
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const SizedBox(width: SubscriberTableColumns.status + Sp.sm),
          Expanded(flex: 5, child: Text('desktop.col_name'.tr(), style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Expanded(flex: 4, child: Text('desktop.col_package'.tr(), style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (columns.showExpiry)
            Expanded(flex: 4, child: Text('desktop.col_expiry'.tr(), style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: SubscriberTableColumns.days,
            child: Text('desktop.col_days'.tr(), style: style, textAlign: TextAlign.center),
          ),
          SizedBox(
            width: SubscriberTableColumns.balance,
            child: Text('desktop.col_balance'.tr(), style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// صفّ مشترك في جدول الحاسبة: ما تعرضه بطاقة الهاتف في سطرٍ واحد (حالةٌ بأيقونةٍ وتسمية، الاسم
/// واليوزر، الباقة وسعرها، الانتهاء والجلسة، الأيّام، الدين) — فيرى المدير أضعاف الصفوف. الأرقام بلون
/// النصّ، والحالة أيقونةٌ وشارة لا لون رقم.
class SubscriberTableRow extends StatefulWidget {
  const SubscriberTableRow({
    super.key,
    required this.sub,
    required this.columns,
    required this.open,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    this.last = false,
  });

  /// آخر صفٍّ ظاهر: زاويتا الجدول السفليّتان.
  final bool last;

  final Subscriber sub;
  final SubscriberTableColumns columns;

  /// مفتوحٌ الآن في لوحة التفاصيل.
  final bool open;

  /// محدَّدٌ للعمليّات الجماعيّة.
  final bool selected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<SubscriberTableRow> createState() => _SubscriberTableRowState();
}

class _SubscriberTableRowState extends State<SubscriberTableRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = widget.sub;
    final st = SubscriberCardV3.statusOf(s);
    final days = SubscriberCardV3.daysOf(s);
    final session = SubscriberCardV3.sessionOf(s);
    final name = s.fullName.trim().isEmpty ? s.username : s.fullName.trim();
    final price = s.currentSalePrice;
    final exp = s.parsedExpiration;
    final bg = widget.selected || widget.open
        ? AppColors.brandSoftBg
        : _hover
            ? AppColors.surfaceSunken
            : AppColors.surface;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: widget.last
                ? const BorderRadius.vertical(bottom: Radius.circular(R.lg))
                : null,
            border: Border(
              left: BorderSide(color: AppColors.border),
              right: BorderSide(color: AppColors.border),
              bottom: BorderSide(color: AppColors.border),
            ),
          ),
          child: Row(
            children: [
              Tooltip(
                message: st.label,
                child: Container(
                  width: SubscriberTableColumns.status,
                  height: SubscriberTableColumns.status,
                  decoration: BoxDecoration(
                    color: widget.selectionMode && widget.selected ? AppColors.brand : st.bg,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Icon(
                    widget.selectionMode && widget.selected ? LucideIcons.check : st.icon,
                    size: 16,
                    color: widget.selectionMode && widget.selected ? AppColors.onBrand : st.color,
                  ),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                flex: 5,
                child: _TwoLines(
                  top: name,
                  topStyle: AppType.label(color: AppColors.textHi)
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 14),
                  bottom: s.username,
                  bottomLtr: true,
                ),
              ),
              Expanded(
                flex: 4,
                child: _TwoLines(
                  top: s.profileName ?? '—',
                  bottom: price == null ? null : '${formatIQD(price)} ${'common.currency'.tr()}',
                ),
              ),
              if (widget.columns.showExpiry)
                Expanded(
                  flex: 4,
                  child: _TwoLines(
                    top: exp == null ? '—' : DateFormat('yyyy/MM/dd · HH:mm').format(exp),
                    topLtr: true,
                    bottom: session?.text,
                  ),
                ),
              SizedBox(
                width: SubscriberTableColumns.days,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: days.bg,
                      borderRadius: BorderRadius.circular(R.pill),
                      border: Border.all(color: days.border),
                    ),
                    child: Text(
                      days.small.isEmpty ? days.big : '${days.big} ${_short(days.small)}',
                      maxLines: 1,
                      style: AppType.label(color: days.color)
                          .copyWith(fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: SubscriberTableColumns.balance,
                child: Align(alignment: AlignmentDirectional.centerEnd, child: _balance(s)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// «أيام متبقية» ⇒ «يوم»: الشارة كلمةٌ واحدة بجانب الرقم.
  static String _short(String word) {
    if (word.contains('ساعة')) return 'س';
    if (word.contains('دقيقة')) return 'د';
    if (word.contains('يوم') || word.contains('أيام')) return 'يوم';
    return word;
  }

  Widget _balance(Subscriber s) {
    if (s.hasDebt) {
      return _Pill(
        text: '${'desktop.debt'.tr()} ${formatIQD(s.debtAbs.round())}',
        fg: AppColors.dangerOnSoft,
        bg: AppColors.dangerSoftBg,
        border: AppColors.dangerSoftBorder,
      );
    }
    if (s.hasCredit) {
      return _Pill(
        text: '+${formatIQD(s.balanceAmount.round())}',
        fg: AppColors.brandOnSoft,
        bg: AppColors.brandSoftBg,
        border: AppColors.brandSoftBorder,
      );
    }
    return Text('—', style: AppType.muted(color: AppColors.textLow));
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.label(color: fg).copyWith(fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }
}

class _TwoLines extends StatelessWidget {
  const _TwoLines({
    required this.top,
    this.bottom,
    this.topStyle,
    this.topLtr = false,
    this.bottomLtr = false,
  });

  final String top;
  final String? bottom;
  final TextStyle? topStyle;
  final bool topLtr;
  final bool bottomLtr;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            top,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: topLtr ? TextDirection.ltr : null,
            style: topStyle ?? AppType.label(color: AppColors.textBody).copyWith(fontSize: 13.5),
          ),
          if (bottom != null && bottom!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              bottom!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: bottomLtr ? TextDirection.ltr : null,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}
