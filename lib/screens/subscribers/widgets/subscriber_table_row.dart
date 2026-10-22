import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/util/format.dart';
import '../../../core/util/phone.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'sort_sheet.dart';
import 'subscriber_card_v3.dart';

/// أعمدة جدول المشتركين على الحاسبة — الرأس والصفوف بالمقاسات نفسها. ما لا يتّسع يُخفى من الأقلّ
/// أهمّيّةً (الهاتف ثمّ الانتهاء)، والأيّام والدين يبقيان دائماً.
class SubscriberTableColumns {
  const SubscriberTableColumns({
    required this.showPhone,
    required this.showExpiry,
    required this.showPackage,
  });

  final bool showPhone;
  final bool showExpiry;

  /// أضيق من هذا: الباقة سطرٌ تحت اليوزر بدل عمودٍ يُبتر اسمها.
  final bool showPackage;

  static SubscriberTableColumns forWidth(double width) => SubscriberTableColumns(
        showPhone: width >= 940,
        showExpiry: width >= 720,
        showPackage: width >= 620,
      );

  static const double check = 40;
  static const double phone = 196;
  static const double expiry = 124;
  static const double days = 116;
  static const double balance = 116;
}

/// رأس الجدول: تسمياتٌ خافتة، وما يُرتَّب به سهمٌ يدلّ على الترتيب الحاليّ واتّجاهه.
class SubscriberTableHeader extends StatelessWidget {
  const SubscriberTableHeader({
    super.key,
    required this.columns,
    required this.sortField,
    required this.descending,
    required this.onSort,
    required this.allSelected,
    required this.onSelectAll,
  });

  final SubscriberTableColumns columns;
  final SortField sortField;
  final bool descending;
  final ValueChanged<SortField> onSort;
  final bool allSelected;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    Widget label(String text, {SortField? field, TextAlign align = TextAlign.start}) {
      final active = field != null && field == sortField;
      final style = AppType.muted(color: active ? AppColors.textHi : AppColors.textMid)
          .copyWith(fontSize: 13, fontWeight: FontWeight.w700);
      final row = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(text, style: style, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (field != null) ...[
            const SizedBox(width: 4),
            Icon(
              active
                  ? (descending ? LucideIcons.arrowDown : LucideIcons.arrowUp)
                  : LucideIcons.arrowUpDown,
              size: 13,
              color: active ? AppColors.brandAccent : AppColors.textLow,
            ),
          ],
        ],
      );
      final aligned = Align(
        alignment: align == TextAlign.center
            ? Alignment.center
            : align == TextAlign.end
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
        child: row,
      );
      if (field == null) return aligned;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSort(field),
          child: aligned,
        ),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsetsDirectional.only(start: Sp.sm, end: Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(R.lg)),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: SubscriberTableColumns.check,
            child: _CheckBox(value: allSelected, onTap: onSelectAll),
          ),
          const SizedBox(width: 44 + Sp.sm),
          Expanded(flex: 5, child: label('desktop.col_name'.tr(), field: SortField.firstname)),
          if (columns.showPhone)
            SizedBox(
              width: SubscriberTableColumns.phone,
              child: label('desktop.col_phone'.tr(), field: SortField.phone),
            ),
          if (columns.showPackage)
            Expanded(
              flex: 3,
              child: label('desktop.col_package'.tr(),
                  field: SortField.profileName, align: TextAlign.center),
            ),
          if (columns.showExpiry)
            SizedBox(
              width: SubscriberTableColumns.expiry,
              child: label('desktop.col_expiry'.tr(),
                  field: SortField.expiration, align: TextAlign.center),
            ),
          SizedBox(
            width: SubscriberTableColumns.days,
            child: label('desktop.col_days'.tr(),
                field: SortField.remainingDays, align: TextAlign.center),
          ),
          SizedBox(
            width: SubscriberTableColumns.balance,
            child: label('desktop.col_balance'.tr(), field: SortField.notes, align: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// صفّ مشترك في جدول الحاسبة بلغة الموقع: شريطٌ بلون الحالة على الحافّة، مربّع تحديد، صورةٌ
/// بالأحرف الأولى ونقطة الاتّصال، الاسم واليوزر، الهاتف بالاتّصال والواتساب، الباقة، الانتهاء، الأيّام
/// بشريطٍ يتناقص، والرصيد. الحالة كلمةٌ وأيقونة أيضاً (تلميح الشريط وشارة الأيّام) لا لونٌ وحده.
class SubscriberTableRow extends StatefulWidget {
  const SubscriberTableRow({
    super.key,
    required this.sub,
    required this.columns,
    required this.open,
    required this.selected,
    required this.selectionMode,
    required this.onTap,
    required this.onToggleSelect,
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
  final VoidCallback onToggleSelect;

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
    final name = s.fullName.trim().isEmpty ? s.username : s.fullName.trim();
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
        onTap: widget.selectionMode ? widget.onToggleSelect : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 64,
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
          child: Row(
            children: [
              Tooltip(
                message: st.label,
                child: Container(width: 4, color: st.color),
              ),
              const SizedBox(width: Sp.sm - 4),
              SizedBox(
                width: SubscriberTableColumns.check,
                child: _CheckBox(value: widget.selected, onTap: widget.onToggleSelect),
              ),
              _Avatar(name: name, online: s.isOnline),
              const SizedBox(width: Sp.sm),
              Expanded(
                flex: 5,
                child: _TwoLines(
                  top: name,
                  topStyle: AppType.label(color: AppColors.textHi)
                      .copyWith(fontWeight: FontWeight.w700, fontSize: 15),
                  bottom: widget.columns.showPackage || (s.profileName ?? '').isEmpty
                      ? s.username
                      : '${s.username} · ${s.profileName}',
                  bottomLtr: true,
                ),
              ),
              if (widget.columns.showPhone)
                SizedBox(width: SubscriberTableColumns.phone, child: _PhoneCell(phone: s.displayPhone)),
              if (widget.columns.showPackage)
              Expanded(
                flex: 3,
                child: Center(
                  child: s.profileName == null || s.profileName!.isEmpty
                      ? Text('—', style: AppType.muted(color: AppColors.textLow))
                      : _Pill(
                          text: s.profileName!,
                          fg: AppColors.textBody,
                          bg: AppColors.surfaceSunken,
                          border: AppColors.border,
                        ),
                ),
              ),
              if (widget.columns.showExpiry)
                SizedBox(
                  width: SubscriberTableColumns.expiry,
                  child: exp == null
                      ? Center(child: Text('—', style: AppType.muted(color: AppColors.textLow)))
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              DateFormat('yyyy-MM-dd').format(exp),
                              textDirection: TextDirection.ltr,
                              style: AppType.label(color: AppColors.textBody)
                                  .copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              DateFormat('HH:mm').format(exp),
                              textDirection: TextDirection.ltr,
                              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
                            ),
                          ],
                        ),
                ),
              SizedBox(width: SubscriberTableColumns.days, child: _DaysCell(sub: s)),
              SizedBox(
                width: SubscriberTableColumns.balance,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: Sp.md),
                  child: Align(alignment: AlignmentDirectional.centerEnd, child: _balance(s)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balance(Subscriber s) {
    final currency = 'common.currency'.tr();
    if (s.hasDebt) {
      return Text(
        '${formatIQD(s.debtAbs.round())} $currency',
        maxLines: 1,
        style: AppType.label(color: AppColors.dangerOnSoft)
            .copyWith(fontWeight: FontWeight.w700, fontSize: 14),
      );
    }
    if (s.hasCredit) {
      return Text(
        '+${formatIQD(s.balanceAmount.round())} $currency',
        maxLines: 1,
        style: AppType.label(color: AppColors.brandOnSoft)
            .copyWith(fontWeight: FontWeight.w700, fontSize: 14),
      );
    }
    return Text('—', style: AppType.muted(color: AppColors.textLow));
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
    double? fraction;
    if (expired) {
      fraction = 1;
    } else if (exp != null && !sub.isDisabled) {
      fraction = (exp.difference(DateTime.now()).inMinutes / (30 * 24 * 60)).clamp(0.04, 1.0);
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
          decoration: BoxDecoration(
            color: d.bg,
            borderRadius: BorderRadius.circular(R.sm),
          ),
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
                style: AppType.label(color: d.color).copyWith(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ],
          ),
        ),
        if (fraction != null) ...[
          const SizedBox(height: 5),
          SizedBox(
            width: 72,
            height: 4,
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(R.pill),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: fraction,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: d.color,
                        borderRadius: BorderRadius.circular(R.pill),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      return Text('—', style: AppType.muted(color: AppColors.textLow));
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
          child: SizedBox(width: 28, height: 28, child: Icon(icon, size: 15, color: color)),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.online});

  final String name;
  final bool online;

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
            decoration: BoxDecoration(color: AppColors.infoSoftBg, shape: BoxShape.circle),
            child: Text(
              _initials(name),
              style: AppType.label(color: AppColors.info).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
          ),
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
  const _Pill({
    required this.text,
    required this.fg,
    required this.bg,
    required this.border,
  });

  final String text;
  final Color fg;
  final Color bg;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
  });

  final String top;
  final String? bottom;
  final TextStyle? topStyle;
  final bool bottomLtr;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            top,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: topStyle ?? AppType.label(color: AppColors.textBody).copyWith(fontSize: 13.5),
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
