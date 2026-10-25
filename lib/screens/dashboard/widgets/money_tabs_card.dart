import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'hero_revenue_card.dart';
import 'packages_summary_card.dart';

/// الهاتف وحده: «الإيرادات» و«توزيع الباقات» في بطاقةٍ واحدة بتبويبين (المالك ٢٥ أكتوبر: «دمج الكارت بالداش بورد…
/// هلشي فقط للهاتف، الحاسبة والويب خليهن منفصلات»). الإيرادات وحدها في تبويبها، والأرباح (المتحقّق والمقدَّر) مع الباقات.
///
/// - البطاقتان حيّتان معاً (المخفيّة خارج الشاشة بحالتها): التبديل فوريّ بلا جلبٍ جديد، وكلٌّ تتحدّث بإشاراتها كما كانت.
/// - آخر تبويبٍ يُحفظ على الجهاز.
/// - يبنيها المتّصل حين يُعرض القسمان ويملك صلاحيّتيهما معاً فقط؛ وإلّا بطاقتان كما كانتا (المقفلة بمكانها).
class MoneyTabsCard extends StatefulWidget {
  const MoneyTabsCard({super.key});

  static const prefKey = 'dash.money_tab';
  static const tabs = ['revenue', 'packages'];

  @override
  State<MoneyTabsCard> createState() => _MoneyTabsCardState();
}

class _MoneyTabsCardState extends State<MoneyTabsCard> {
  String _tab = MoneyTabsCard.tabs.first;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final v = p.getString(MoneyTabsCard.prefKey);
      if (mounted && v != null && v != _tab && MoneyTabsCard.tabs.contains(v)) {
        setState(() => _tab = v);
      }
    }).catchError((_) {});
  }

  void _pick(String tab) {
    if (tab == _tab) return;
    HapticFeedback.selectionClick();
    setState(() => _tab = tab);
    SharedPreferences.getInstance().then((p) => p.setString(MoneyTabsCard.prefKey, tab)).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TabsBar(
            current: _tab,
            onSelect: _pick,
            labels: {
              'revenue': 'dashboard.revenue'.tr(),
              'packages': 'pkgdist.card_title'.tr(),
            },
          ),
          const SizedBox(height: Sp.md),
          Visibility(
            visible: _tab == 'revenue',
            maintainState: true,
            child: const HeroRevenueCard(embedded: true),
          ),
          Visibility(
            visible: _tab == 'packages',
            maintainState: true,
            child: const PackagesSummaryCard(embedded: true),
          ),
        ],
      ),
    );
  }
}

/// تبويبان بعرض البطاقة: مسارٌ مدوّر والمختار حبّةٌ بلون العلامة — كفترات الإيرادات ([PillTabs]) لكن بعرضٍ كامل.
class _TabsBar extends StatelessWidget {
  const _TabsBar({required this.current, required this.onSelect, required this.labels});

  final String current;
  final ValueChanged<String> onSelect;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        children: [
          for (final e in labels.entries) ...[
            if (e.key != labels.keys.first) const SizedBox(width: 4),
            Expanded(child: _tab(e.key, e.value)),
          ],
        ],
      ),
    );
  }

  Widget _tab(String key, String label) {
    final selected = key == current;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: Sp.sm),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brand : Colors.transparent,
            borderRadius: BorderRadius.circular(R.pill),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.label(color: selected ? AppColors.onBrand : AppColors.textMid)
                .copyWith(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
