import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/util/format.dart';
import '../models/merged_company.dart';
import '../services/active_company.dart';
import '../services/merged_mode.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// «كل الشركات»: شريط الشركات أعلى الرئيسية والمشتركين والتقرير الماليّ — كشريط الويب (client-v2 CompanyStrip):
/// «الكل» ثمّ شارةٌ لكلّ شركة بلونها (وعددها إن أُعطي). الضغط على شركة يعرضها وحدها (MergedMode.focus) والضغط ثانيةً
/// أو على «الكل» يعيد المدموج. شركةٌ لا تدخل (تحتاج دخول، كبيرة، تعذّرت، من الموقع وحده) شارتها بلون حالها، وضغطها
/// يقول السبب ولا يختارها. يتمرّر أفقيّاً، وزرّ الخروج أيقونةٌ صغيرة لا زرّ نصّيّ.
class MergedCompanyStrip extends StatelessWidget {
  const MergedCompanyStrip({
    super.key,
    this.countOf,
    this.total,
    this.problemOf,
    this.note,
    this.onExit,
    this.onProblem,
  });

  /// عدد الشركة على شارتها (null: لا عدد).
  final int? Function(MergedCompany c)? countOf;

  /// عدد «الكل» (null: لا عدد).
  final int? total;

  /// حال شركةٍ صالحة لا تُختار هنا (كبيرة، تعذّرت…) — نصٌّ قصير على شارتها، وإلّا null.
  final String? Function(MergedCompany c)? problemOf;

  /// سطرٌ صغير تحت الشارات: من لم يدخل الأرقام ولماذا.
  final String? note;

  /// يُظهر أيقونة الخروج من الوضع.
  final VoidCallback? onExit;

  /// ضغط شارة شركةٍ لا تُختار (افتراضاً: رسالتها).
  final void Function(MergedCompany c, String message)? onProblem;

  static String? statusLabel(MergedCompany c) {
    if (!c.appCapable) return 'merged.web_only'.tr();
    return switch (c.status) {
      MergedStatus.ok => null,
      MergedStatus.needsLogin => 'merged.needs_login'.tr(),
      MergedStatus.loading => 'merged.chip_loading'.tr(),
      MergedStatus.unavailable => 'merged.chip_unavailable'.tr(),
    };
  }

  void _say(BuildContext context, MergedCompany c, String msg) {
    if (onProblem != null) {
      onProblem!(c, msg);
      return;
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ValueListenableBuilder<String?>(
      valueListenable: MergedMode.focus,
      builder: (context, _, __) {
        final focused = MergedMode.focused;
        final companies = MergedMode.companies;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.layers_rounded, size: 16, color: AppColors.brand),
                const SizedBox(width: 6),
                Text(
                  '${'merged.header'.tr()} · ${MergedMode.usable.length}',
                  style: AppType.bodyStrong(color: AppColors.textHi).copyWith(fontSize: 13),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    focused == null ? 'merged.strip_hint'.tr() : 'merged.strip_focused'.tr(args: [focused.name]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body(color: AppColors.textLow).copyWith(fontSize: 11.5),
                  ),
                ),
                if (onExit != null)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      tooltip: 'merged.exit'.tr(),
                      onPressed: onExit,
                      icon: Icon(Icons.close_rounded, color: AppColors.textMid),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Chip(
                    label: 'merged.all_chip'.tr(),
                    count: total,
                    selected: focused == null,
                    onTap: () => MergedMode.focus.value = null,
                  ),
                  for (final c in companies) ...[
                    const SizedBox(width: 6),
                    Builder(builder: (context) {
                      final status = statusLabel(c);
                      final problem = status ?? problemOf?.call(c);
                      if (problem != null) {
                        return _Chip(
                          label: c.name,
                          dot: AppColors.company(c.colorIndex),
                          problem: problem,
                          warn: c.status == MergedStatus.needsLogin,
                          loading: c.status == MergedStatus.loading,
                          onTap: () => _say(context, c, c.message ?? '«${c.name}» — $problem'),
                        );
                      }
                      final on = focused?.key == c.key;
                      return _Chip(
                        label: c.name,
                        dot: AppColors.company(c.colorIndex),
                        count: countOf?.call(c),
                        selected: on,
                        onTap: () => MergedMode.focus.value = on ? null : c.key,
                      );
                    }),
                  ],
                ],
              ),
            ),
            if (note != null && note!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                note!,
                style: AppType.body(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.5),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.onTap,
    this.dot,
    this.count,
    this.selected = false,
    this.problem,
    this.warn = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback onTap;
  final Color? dot;
  final int? count;
  final bool selected;
  final String? problem;
  final bool warn;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final bad = problem != null;
    final bg = selected
        ? AppColors.brandSoftBg
        : bad
            ? (warn ? AppColors.warningSoftBg : AppColors.surfaceSunken)
            : AppColors.surface;
    final border = selected
        ? AppColors.brand
        : bad
            ? (warn ? AppColors.warningSoftBorder : AppColors.border)
            : AppColors.border;
    final fg = bad ? (warn ? AppColors.warningOnSoft : AppColors.textMid) : AppColors.textHi;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: border, width: selected ? 1.4 : 1)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 34, maxWidth: 230),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dot != null) ...[
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body(color: fg).copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      formatIQD(count!),
                      style: AppType.body(color: selected ? AppColors.brand : AppColors.textMid)
                          .copyWith(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                  if (problem != null) ...[
                    const SizedBox(width: 4),
                    Text(
                      '· $problem',
                      style: AppType.body(color: fg).copyWith(fontSize: 11.5),
                    ),
                  ],
                  if (loading) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.textMid),
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

/// «كل الشركات»: سطرٌ أعلى قسمٍ يعمل للشركة المفتوحة وحدها («قوائم أخرى»، التقارير…) — يسمّيها، فلا يُظنّ رقمه مجموع
/// الشركات. خارج الوضع لا يظهر شيء.
class MergedOpenCompanyNote extends StatelessWidget {
  const MergedOpenCompanyNote({super.key, this.textKey = 'merged.others_note', this.padding = EdgeInsets.zero});

  /// مفتاح النصّ — `{}` اسم الشركة المفتوحة.
  final String textKey;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MergedMode.active,
      builder: (context, on, _) {
        if (!on) return const SizedBox.shrink();
        Theme.of(context); // theme-dep (dark-mode)
        final open = ActiveCompany.current;
        final name = open == null
            ? '—'
            : (open.username.isEmpty || open.username == open.label ? open.label : '${open.label} · ${open.username}');
        return Padding(
          padding: padding,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceSunken,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.layers_rounded, size: 15, color: AppColors.textMid),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    textKey.tr(args: [name]),
                    style: AppType.body(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
