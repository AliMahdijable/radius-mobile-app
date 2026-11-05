import 'package:flutter/material.dart';

import '../../../services/subscriber_usage_store.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// «الاستهلاك» عند الطلب لصفّ المشتركين — المشروع الوطنيّ (المالك ٥ نوفمبر: «كونه ثكيل استعلامته… ينقر ع عرض الاستهلاك حتى
/// يكون بطلب منفصل»): زرّ «عرض الاستهلاك» ⇒ «يُجلب…» ⇒ اليوم · الشهر وزرّ تحديث؛ والتعذّر برسالة الخادم و«أعد المحاولة».
/// [stacked]: اليوم فوق الشهر (عمود الجدول)، وإلّا سطرٌ واحد (كارت الهاتف). لمسته لا تفتح المشترك (أعمق متعرّفٍ يربح).
class UsageOnDemand extends StatelessWidget {
  const UsageOnDemand(
      {super.key, required this.idx, this.company, this.stacked = false});

  final String idx;

  /// «كل الشركات»: شركة الصفّ — يُسأل خادمها لا الشركة المفتوحة.
  final String? company;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ValueListenableBuilder<int>(
      valueListenable: SubscriberUsageStore.version,
      builder: (context, _, __) {
        final s = SubscriberUsageStore.one(idx, company: company);
        final v = s.v;
        if (v == null) {
          if (s.loading) return _loading();
          return _ask(s.err);
        }
        final values = stacked ? _stacked(v, s.loading) : _line(v, s.loading);
        if (s.err == null) return values;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            values,
            const SizedBox(height: Sp.xxs),
            Tooltip(
              message: s.err!,
              child: Text(
                'تعذّر التحديث — القيمة السابقة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.body(color: AppColors.dangerOnSoft)
                    .copyWith(fontSize: 11.5),
              ),
            ),
          ],
        );
      },
    );
  }

  void _load({bool fresh = false}) =>
      SubscriberUsageStore.requestOne(idx, company: company, fresh: fresh);

  Widget _spinner() => SizedBox(
        width: 13,
        height: 13,
        child: CircularProgressIndicator(
            strokeWidth: 1.6, color: AppColors.brandAccent),
      );

  Widget _loading() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _spinner(),
          const SizedBox(width: Sp.x6),
          Flexible(
            child: Text('يُجلب الاستهلاك…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.body(color: AppColors.textLabel)
                    .copyWith(fontSize: 12.5)),
          ),
        ],
      );

  Widget _ask(String? err) {
    final chip = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(R.pill),
        onTap: _load,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.sm + 2, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.data_usage_rounded,
                  size: 14, color: AppColors.brandAccent),
              const SizedBox(width: Sp.xs),
              Flexible(
                child: Text(
                  err != null ? 'أعد المحاولة' : 'عرض الاستهلاك',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body(color: AppColors.textBody)
                      .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (err == null) return chip;
    final why = Text(
      err,
      maxLines: stacked ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style:
          AppType.body(color: AppColors.dangerOnSoft).copyWith(fontSize: 11.5),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [chip, const SizedBox(height: Sp.xxs), why],
    );
  }

  Widget _refresh(bool loading) => loading
      ? Padding(padding: const EdgeInsets.all(Sp.xs), child: _spinner())
      : Material(
          type: MaterialType.transparency,
          child: InkResponse(
            radius: 16,
            onTap: () => _load(fresh: true),
            child: Padding(
              padding: const EdgeInsets.all(Sp.xs),
              child: Tooltip(
                message: 'تحديث الاستهلاك',
                child: Icon(Icons.refresh_rounded,
                    size: 16, color: AppColors.textHint),
              ),
            ),
          ),
        );

  TextStyle get _label =>
      AppType.body(color: AppColors.textLabel).copyWith(fontSize: 12.5);
  TextStyle get _value =>
      AppType.body().copyWith(fontSize: 12.5, fontWeight: FontWeight.w600);

  Widget _line(SubscriberUsage v, bool loading) => Row(
        children: [
          Icon(Icons.data_usage_rounded, size: 15, color: AppColors.textHint),
          const SizedBox(width: Sp.x6),
          Flexible(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: 'اليوم ', style: _label),
                TextSpan(
                    text: '\u2066${formatUsageBytes(v.today)}\u2069',
                    style: _value),
                TextSpan(text: '  ·  ', style: _label),
                TextSpan(text: 'الشهر ', style: _label),
                TextSpan(
                    text: '\u2066${formatUsageBytes(v.month)}\u2069',
                    style: _value),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _refresh(loading),
        ],
      );

  Widget _stacked(SubscriberUsage v, bool loading) {
    Widget line(String k, int? bytes) => Text.rich(
          TextSpan(children: [
            TextSpan(text: '$k ', style: _label),
            TextSpan(
                text: '\u2066${formatUsageBytes(bytes)}\u2069', style: _value),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line('اليوم', v.today),
              const SizedBox(height: 2),
              line('الشهر', v.month)
            ],
          ),
        ),
        _refresh(loading),
      ],
    );
  }
}
