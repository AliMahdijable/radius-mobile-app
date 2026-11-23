import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/widgets/app_date_picker.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import 'report_kit.dart';
import 'report_period.dart';

// ورقتا التقرير الموحّد (٢٢ نوفمبر): الفلاتر كلّها في ورقةٍ واحدة بالترتيب نفسه لكلّ تقرير — وفي «كل الشركات» كلّ شركةٍ بمدرائها
// وموظّفيها تحت اسمها — وحركات رقمٍ لُمست بطاقته.

/// شخصٌ في قائمة (مدير أو موظّف) — [parentId] مدير المدير (شجرة المدراء الفرعيّين) حين يعرفه الخادم.
class RpPerson {
  const RpPerson(this.id, this.name, {this.parentId, this.sub, this.username});
  final String id;
  final String name;
  final String? parentId;

  /// «موظّفة» · «محذوف».
  final String? sub;

  /// يوزره (لفلتر «مدير المشترك» الذي يُسأل باليوزر).
  final String? username;
}

/// مدراء وموظّفو شركةٍ واحدة — [key] «open» للشركة المفتوحة، ومفتاح الشركة في «كل الشركات».
class RpPeopleGroup {
  const RpPeopleGroup({required this.key, this.company, this.managers = const [], this.employees = const [], this.error});
  final String key;
  final RpCompany? company;
  final List<RpPerson> managers;
  final List<RpPerson> employees;

  /// تعذّر جلب قوائمها.
  final String? error;
}

/// «المدير» = من نفّذ الحركة (الافتراض)، أو مدير المشترك صاحب الحركة.
enum RpManagerMode { actor, owner }

/// ما اختاره الوكيل في الورقة — ولكلّ شركةٍ اختيارها ([managers]/[employees] بمفتاح الشركة أو «open»).
class RpFilterValue {
  const RpFilterValue({
    required this.range,
    this.compare = true,
    this.companies = const {},
    this.managers = const {},
    this.withSubs = false,
    this.managerMode = RpManagerMode.actor,
    this.employees = const {},
    this.types = const [],
    this.packages = const {},
  });

  final RpRange range;
  final bool compare;

  /// «كل الشركات»: المختارة (فارغ = كلّها).
  final Set<String> companies;
  final Map<String, Set<String>> managers;

  /// «مع مدرائه الفرعيّين» — مطفأٌ افتراضاً (قرار المالك ٢٢ نوفمبر: «حركاتي أنا»، والفرعيّون من الفلاتر بالمفتاح): المدير المختار وحده
  /// حتى يُفتح المفتاح (يظهر حين يرسل الخادم شجرة parent_id — mgrparent1122).
  final bool withSubs;
  final RpManagerMode managerMode;

  /// الموظّفون المختارون لكلّ شركة — أكثر من واحد كالمدراء (المالك ٢٣ نوفمبر: «ماكدر اختار اكثر من موظف بالفلاتر بجميع
  /// التقارير»): واحدٌ ⇒ employee_id، اثنان فأكثر ⇒ employee_ids (lib/api/employee_filter.dart).
  final Map<String, Set<String>> employees;
  final List<String> types;

  /// الباقات المختارة (بند المقترح ١٢: «الباقات تظهر باسم كلّ باقة وشركتها») — «مفتاح الشركة|اسم الباقة» (المفتوحة: «|اسمها»).
  final Set<String> packages;

  static String packageKey(String? company, String name) => '${company ?? ''}|$name';

  RpFilterValue copyWith({
    RpRange? range,
    bool? compare,
    Set<String>? companies,
    Map<String, Set<String>>? managers,
    bool? withSubs,
    RpManagerMode? managerMode,
    Map<String, Set<String>>? employees,
    List<String>? types,
    Set<String>? packages,
  }) =>
      RpFilterValue(
        range: range ?? this.range,
        compare: compare ?? this.compare,
        companies: companies ?? this.companies,
        managers: managers ?? this.managers,
        withSubs: withSubs ?? this.withSubs,
        managerMode: managerMode ?? this.managerMode,
        employees: employees ?? this.employees,
        types: types ?? this.types,
        packages: packages ?? this.packages,
      );

  /// بلا مدير ولا موظّف ولا نوع ولا باقة (الفترة والشركات والمقارنة ليست «فلاتر»).
  RpFilterValue cleared() => copyWith(managers: const {}, employees: const {}, types: const [], packages: const {});

  bool get hasPeople => managers.values.any((s) => s.isNotEmpty) || employees.values.any((s) => s.isNotEmpty);
}

/// شريحة «طريقة الدفع» = اختصارٌ لأنواع الحركة نفسها (لا فلترٌ ثانٍ بمعنى آخر).
class RpPayShortcut {
  const RpPayShortcut(this.label, this.types);
  final String label;
  final List<String> types;
}

class RpFilterSheet extends StatefulWidget {
  const RpFilterSheet({
    super.key,
    required this.subtitle,
    required this.initial,
    required this.people,
    required this.types,
    this.payments = const [],
    this.companies,
    required this.now,
    this.loadingPeople = false,
    this.onDone,
    this.showPeople = true,
    this.showManagers = true,
    this.packages = const [],
    this.showCompare = true,
    this.presets = RpRange.presets,
  });

  /// الفترات الجاهزة في الورقة — ديون المدراء يضيف «كل الفترات» ([RpPreset.all]).
  final List<RpPreset> presets;

  /// قسما «المدير» و«الموظّف» — كشف حساب مشتركٍ واحد بلاهما.
  final bool showPeople;

  /// قسم «المدير» — توزيع الباقات بالموظّف المنفِّذ وحده (النطاق من الخادم).
  final bool showManagers;

  /// قسم «الباقة»: (مفتاح [RpFilterValue.packageKey]، الاسم كما يُعرض — مع شركته في «كل الشركات»). فارغ = لا قسم.
  final List<(String, String)> packages;

  /// مفتاح «قارن» — سجلّ الحركات وكشف الحساب بلا مقارنة.
  final bool showCompare;

  /// «التقرير الماليّ · هذا الشهر».
  final String subtitle;
  final RpFilterValue initial;
  final List<RpPeopleGroup> people;
  final List<(String key, String label)> types;
  final List<RpPayShortcut> payments;

  /// «كل الشركات» وحده: الشركات القابلة للاختيار (بلا [RpCompany.selected] — الاختيار من [initial]).
  final List<RpCompany>? companies;
  final DateTime now;
  final bool loadingPeople;

  /// يُنادى بالقيمة عند «عرض النتائج» (وإلّا تُعاد بـNavigator.pop).
  final ValueChanged<RpFilterValue>? onDone;

  @override
  State<RpFilterSheet> createState() => _RpFilterSheetState();
}

class _RpFilterSheetState extends State<RpFilterSheet> {
  late RpFilterValue _v = widget.initial;

  void _set(RpFilterValue v) => setState(() => _v = v);

  bool _companyOn(String key) => _v.companies.isEmpty || _v.companies.contains(key);

  Future<void> _custom() async {
    final r = await showAppDateRangePicker(
      context: context,
      firstDate: DateTime(widget.now.year - 3),
      lastDate: widget.now,
      initialDateRange: DateTimeRange(start: _v.range.from, end: _v.range.to),
    );
    if (r == null || !mounted) return;
    _set(_v.copyWith(range: RpRange.of(RpPreset.custom, now: widget.now, from: r.start, to: r.end)));
  }

  void _toggleCompany(RpCompany c) {
    final all = widget.companies ?? const [];
    final picked = _v.companies.isEmpty ? {for (final x in all) x.key} : {..._v.companies};
    if (picked.contains(c.key)) {
      if (picked.length == 1) return; // شركةٌ واحدة على الأقلّ
      picked.remove(c.key);
    } else {
      picked.add(c.key);
    }
    _set(_v.copyWith(companies: picked.length == all.length ? const {} : picked));
  }

  void _toggleManager(String group, RpPerson p) {
    final map = {
      for (final e in _v.managers.entries) e.key: {...e.value}
    };
    final set = map[group] ?? <String>{};
    if (_v.managerMode == RpManagerMode.owner) {
      // «مدير المشترك» يُسأل بمديرٍ واحد لكلّ شركة
      map[group] = set.contains(p.id) ? <String>{} : {p.id};
    } else {
      set.contains(p.id) ? set.remove(p.id) : set.add(p.id);
      map[group] = set;
    }
    map.removeWhere((_, s) => s.isEmpty);
    _set(_v.copyWith(managers: map));
  }

  void _toggleEmployee(String group, RpPerson p) {
    final map = {
      for (final e in _v.employees.entries) e.key: {...e.value}
    };
    final set = map[group] ?? <String>{};
    set.contains(p.id) ? set.remove(p.id) : set.add(p.id);
    map[group] = set;
    map.removeWhere((_, s) => s.isEmpty);
    _set(_v.copyWith(employees: map));
  }

  void _toggleType(String key) {
    final t = [..._v.types];
    t.contains(key) ? t.remove(key) : t.add(key);
    _set(_v.copyWith(types: t));
  }

  void _togglePackage(String key) {
    final p = {..._v.packages};
    p.contains(key) ? p.remove(key) : p.add(key);
    _set(_v.copyWith(packages: p));
  }

  bool _payOn(RpPayShortcut s) => s.types.every(_v.types.contains);

  void _togglePay(RpPayShortcut s) {
    final t = [..._v.types];
    if (_payOn(s)) {
      t.removeWhere(s.types.contains);
    } else {
      for (final x in s.types) {
        if (!t.contains(x)) t.add(x);
      }
    }
    _set(_v.copyWith(types: t));
  }

  void _done() {
    final cb = widget.onDone;
    if (cb != null) {
      cb(_v);
    } else {
      Navigator.of(context).pop(_v);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final cos = widget.companies;
    final groups = [
      for (final g in widget.people)
        if (cos == null || _companyOn(g.key)) g,
    ];
    final anyTree = groups.any((g) => g.managers.any((m) => m.parentId != null));
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.slidersHorizontal,
        title: 'الفلاتر',
        subtitle: widget.subtitle,
        onClose: () => Navigator.of(context).maybePop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: 'الفترة',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: Sp.sm,
                  runSpacing: Sp.sm,
                  children: [
                    for (final p in widget.presets)
                      SheetQuickChip(
                        label: RpRange.of(p, now: widget.now).name,
                        selected: _v.range.preset == p,
                        onTap: () => _set(_v.copyWith(range: RpRange.of(p, now: widget.now))),
                      ),
                    SheetQuickChip(
                      label: _v.range.preset == RpPreset.custom ? _v.range.rangeText : 'مخصّص…',
                      selected: _v.range.preset == RpPreset.custom,
                      onTap: _custom,
                    ),
                  ],
                ),
                if (widget.showCompare) ...[
                  const SizedBox(height: Sp.sm),
                  _switchRow('قارن بالفترة السابقة', 'تحت كلّ رقم: فرقه ${_v.range.vsText}', _v.compare,
                      (on) => _set(_v.copyWith(compare: on))),
                ],
              ],
            ),
          ),
          if (cos != null) ...[
            const SizedBox(height: Sp.xl),
            SheetSection(
              label: 'الشركات',
              hint: 'تختار أكثر من شركة',
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final c in cos) _CompanyPick(company: c, selected: _companyOn(c.key), onTap: () => _toggleCompany(c)),
                ],
              ),
            ),
          ],
          if (widget.showPeople && widget.showManagers) ...[
            const SizedBox(height: Sp.xl),
            SheetSection(
              label: 'المدير',
              hint: cos != null ? 'مدراء كلّ شركة تحت اسمها' : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SheetSegmented(
                    labels: const ['من نفّذ الحركة', 'مدير المشترك'],
                    selectedIndex: _v.managerMode == RpManagerMode.actor ? 0 : 1,
                    onSelect: (i) => _set(_v.copyWith(
                      managerMode: i == 0 ? RpManagerMode.actor : RpManagerMode.owner,
                      managers: const {},
                    )),
                  ),
                  const SizedBox(height: Sp.sm),
                  _groups(groups, managers: true),
                  if (anyTree && _v.managerMode == RpManagerMode.actor) ...[
                    const SizedBox(height: Sp.sm),
                    _switchRow('مع مدرائه الفرعيّين', 'حركاتهم تدخل مع حركات من تختاره', _v.withSubs,
                        (on) => _set(_v.copyWith(withSubs: on))),
                  ],
                ],
              ),
            ),
          ],
          if (widget.showPeople) ...[
            const SizedBox(height: Sp.xl),
            SheetSection(label: 'الموظّف', hint: 'من نفّذ الحركة — واحدٌ أو أكثر', child: _groups(groups, managers: false)),
          ],
          if (widget.packages.isNotEmpty) ...[
            const SizedBox(height: Sp.xl),
            SheetSection(
              label: 'الباقة',
              hint: 'باقات هذه الفترة',
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final p in widget.packages)
                    SheetQuickChip(label: p.$2, selected: _v.packages.contains(p.$1), onTap: () => _togglePackage(p.$1)),
                ],
              ),
            ),
          ],
          // تقريرٌ بلا أنواع حركة (توزيع الباقات) ⇒ لا قسم فارغ
          if (widget.types.isNotEmpty) ...[
            const SizedBox(height: Sp.xl),
            SheetSection(
              label: 'نوع الحركة',
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final t in widget.types)
                    SheetQuickChip(label: t.$2, selected: _v.types.contains(t.$1), onTap: () => _toggleType(t.$1)),
                ],
              ),
            ),
          ],
          if (widget.payments.isNotEmpty) ...[
            const SizedBox(height: Sp.xl),
            SheetSection(
              label: 'طريقة الدفع',
              hint: 'اختصارٌ لأنواع الحركة',
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final s in widget.payments)
                    SheetQuickChip(label: s.label, selected: _payOn(s), onTap: () => _togglePay(s)),
                ],
              ),
            ),
          ],
        ],
      ),
      footer: SheetFooterBar(
        label: 'عرض النتائج',
        icon: LucideIcons.check,
        onPressed: _done,
        leading: SizedBox(
          height: H.button,
          child: Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.button),
            child: InkWell(
              onTap: () => _set(_v.cleared()),
              borderRadius: BorderRadius.circular(R.button),
              child: Ink(
                padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.button),
                  border: Border.all(color: AppColors.dangerSoftBorder),
                ),
                child: Center(child: Text('مسح الكلّ', style: AppType.buttonBold(color: AppColors.error))),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _switchRow(String title, String hint, bool on, ValueChanged<bool> onChanged) => Container(
        padding: const EdgeInsetsDirectional.only(start: Sp.md, end: Sp.xs, top: Sp.xs, bottom: Sp.xs),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.icon),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1),
                  Text(hint, style: AppType.micro(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            Switch(value: on, onChanged: onChanged, activeThumbColor: AppColors.onBrand, activeTrackColor: AppColors.brand),
          ],
        ),
      );

  /// المدراء بشجرتهم: الرئيسيّ ثمّ فرعيّوه تحته (من يعرفه الخادم)، والبقيّة كما وصلوا.
  static List<(RpPerson, int)> _tree(List<RpPerson> people) {
    final ids = {for (final p in people) p.id};
    final kids = <String, List<RpPerson>>{};
    final roots = <RpPerson>[];
    for (final p in people) {
      final parent = p.parentId;
      if (parent != null && parent != p.id && ids.contains(parent)) {
        (kids[parent] ??= []).add(p);
      } else {
        roots.add(p);
      }
    }
    final out = <(RpPerson, int)>[];
    final seen = <String>{};
    void walk(RpPerson p, int depth) {
      if (!seen.add(p.id)) return;
      out.add((p, depth));
      for (final k in kids[p.id] ?? const <RpPerson>[]) {
        walk(k, depth + 1);
      }
    }

    for (final r in roots) {
      walk(r, 0);
    }
    for (final p in people) {
      walk(p, 0); // دورةٌ في البيانات: لا يضيع أحد
    }
    return out;
  }

  Widget _groups(List<RpPeopleGroup> groups, {required bool managers}) {
    if (widget.loadingPeople && groups.every((g) => (managers ? g.managers : g.employees).isEmpty)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.md),
        child: Center(
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))),
      );
    }
    final rows = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      final grp = groups[g];
      final list = managers ? grp.managers : grp.employees;
      if (rows.isNotEmpty) rows.add(Divider(height: 1, color: AppColors.divider));
      if (grp.company != null) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.xxs),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: grp.company!.color, shape: BoxShape.circle)),
              const SizedBox(width: Sp.x6),
              Expanded(
                child: Text(grp.company!.name,
                    style: AppType.labelBold(color: AppColors.textMid), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ));
      }
      if (grp.error != null) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.xs, Sp.md, Sp.sm),
          child: Text(grp.error!, style: AppType.micro(color: AppColors.dangerOnSoft)),
        ));
        continue;
      }
      if (list.isEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.xs, Sp.md, Sp.sm),
          child: Text(managers ? 'لا مدراء فرعيّون' : 'لا موظّفون', style: AppType.micro(color: AppColors.textLow)),
        ));
        continue;
      }
      final items = managers ? _tree(list) : [for (final p in list) (p, 0)];
      for (final (p, depth) in items) {
        final on = (managers ? _v.managers[grp.key] : _v.employees[grp.key])?.contains(p.id) ?? false;
        rows.add(_pick(p, depth, on, () => managers ? _toggleManager(grp.key, p) : _toggleEmployee(grp.key, p)));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
    );
  }

  Widget _pick(RpPerson p, int depth, bool on, VoidCallback onTap) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: Sp.md + depth * Sp.xl, end: Sp.md, top: Sp.sm, bottom: Sp.sm),
            child: Row(
              children: [
                Container(
                  width: H.checkbox,
                  height: H.checkbox,
                  decoration: BoxDecoration(
                    color: on ? AppColors.brand : AppColors.surface,
                    borderRadius: BorderRadius.circular(R.check),
                    border: Border.all(color: on ? AppColors.brand : AppColors.borderStrong, width: BW.selected),
                  ),
                  child: on ? const Icon(LucideIcons.check, size: 14, color: AppColors.onBrand) : null,
                ),
                const SizedBox(width: Sp.md),
                if (depth > 0) ...[
                  Icon(LucideIcons.cornerDownLeft, size: 14, color: AppColors.textLow),
                  const SizedBox(width: Sp.xs),
                ],
                Expanded(
                  child: Text(p.name,
                      style: AppType.bodyBold(color: AppColors.textHi), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (p.sub != null) ...[
                  const SizedBox(width: Sp.sm),
                  Text(p.sub!, style: AppType.micro(color: AppColors.textLow), maxLines: 1),
                ],
              ],
            ),
          ),
        ),
      );
}

class _CompanyPick extends StatelessWidget {
  const _CompanyPick({required this.company, required this.selected, required this.onTap});
  final RpCompany company;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final c = company.color;
    return Material(
      color: selected ? c.withValues(alpha: 0.12) : AppColors.surface,
      borderRadius: BorderRadius.circular(R.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.pill),
        child: Ink(
          height: H.chip,
          padding: const EdgeInsets.symmetric(horizontal: Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.pill),
            border: Border.all(color: selected ? c : AppColors.border, width: selected ? BW.selected : BW.normal),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                Icon(LucideIcons.check, size: 14, color: c)
              else
                Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              const SizedBox(width: Sp.x6),
              Text(company.name, style: AppType.pillBold(color: selected ? AppColors.textHi : AppColors.textMid), maxLines: 1),
            ],
          ),
        ),
      ),
    );
  }
}

/// لمسة بطاقة رقم ⇒ الحركات التي صنعته، بالفترة والفلاتر نفسها — وتُصدَّر وحدها.
class RpDrillSheet extends StatelessWidget {
  const RpDrillSheet({super.key, required this.kpi, required this.scope, required this.chips, required this.rows, this.onExport});
  final RpKpi kpi;

  /// «هذا الشهر · سوبرنت، ايرث لنك».
  final String scope;
  final List<RpChip> chips;
  final RpRowsCard rows;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: kpi.icon,
        title: kpi.label,
        subtitle: scope,
        onClose: () => Navigator.of(context).maybePop(),
        tint: kpi.tone.fg,
        tintBg: kpi.tone.soft,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RpCard(
            tint: kpi.tone.fg,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المجموع', style: AppType.label(color: AppColors.textMid)),
                      RpFitText(kpi.text, style: AppType.amount(color: kpi.tone.fg)),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${rows.total}', style: AppType.statValue(color: AppColors.textHi)),
                    Text('حركة', style: AppType.micro(color: AppColors.textMid)),
                  ],
                ),
              ],
            ),
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            RpFilterBar(chips: chips),
          ],
          const SizedBox(height: Sp.md),
          rows,
        ],
      ),
      footer: SheetFooterBar(label: 'تصدير هذه الحركات', icon: LucideIcons.share2, onPressed: onExport),
    );
  }
}
