import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
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

/// ايرث لنك — ثلاث شاشاتٍ للقراءة فقط (البند ٤، EarthLink وحدهم):
///   • «استخدام التجريبيّ» → GET /api/v2/el/test-usage
///   • «سجلّ ايرث لنك»      → GET /api/v2/el/audit?rowcount=N
///   • «المشتركون حسب الباقة» → GET /api/v2/el/by-package
///
/// كلّها قوائمُ تُقرأ ولا تُعدَّل. تشترك في هيكلٍ واحد ([_ElReadScaffold]):
/// ترويسةٌ بعنوانٍ وتحديث، سحبٌ للتحديث، وحالاتُ تحميلٍ/خطأٍ/فراغ موحّدة —
/// بلغة المخطّط نفسها التي عليها «الكارتات المطلوبة».

// ═════════════════ استخدام التجريبيّ ═════════════════

class ElTestUsageScreen extends StatefulWidget {
  const ElTestUsageScreen({super.key});

  @override
  State<ElTestUsageScreen> createState() => _ElTestUsageScreenState();
}

class _ElTestUsageScreenState extends State<ElTestUsageScreen> {
  List<ElTestUsageRow>? _items;
  bool _loading = true;
  String? _error;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final req = ++_req;
    if (mounted) setState(() => _loading = true);
    final r = await EarthlinkApi.testUsage();
    if (!mounted || req != _req) return;
    setState(() {
      _loading = false;
      if (r.message == null) {
        _items = r.items;
        _error = null;
      } else {
        _error = r.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return _ElReadScaffold(
      title: 'el.test_usage_title'.tr(),
      subtitle: 'el.test_usage_hint'.tr(),
      loading: _loading,
      error: _error,
      hasData: items != null,
      isEmpty: items != null && items.isEmpty,
      emptyIcon: LucideIcons.flaskConical,
      emptyText: 'el.test_usage_empty'.tr(),
      onRefresh: _load,
      content: items == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ElSummaryCard(
                  icon: LucideIcons.flaskConical,
                  label: 'el.test_usage_count'.tr(),
                  value: formatIQD(items.length),
                ),
                const SizedBox(height: Sp.lg),
                _ElListCard(
                  icon: LucideIcons.users,
                  title: 'el.test_usage_title'.tr(),
                  countLabel: _subsCount(items.length),
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: Sp.sm),
                      _TestUsageRow(row: items[i]),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

class _TestUsageRow extends StatelessWidget {
  const _TestUsageRow({required this.row});
  final ElTestUsageRow row;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(color: AppColors.textHi)
                      .copyWith(fontSize: 13.5),
                ),
                if (row.username != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    row.username!,
                    textDirection: ui.TextDirection.ltr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted(color: AppColors.textLow),
                  ),
                ],
              ],
            ),
          ),
          if (row.date != null || row.usage != null) ...[
            const SizedBox(width: Sp.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (row.usage != null)
                  Text(
                    formatIQD(row.usage!),
                    textDirection: ui.TextDirection.ltr,
                    style: AppType.statValue(color: AppColors.brand),
                  ),
                if (row.date != null)
                  Text(
                    _shortDate(row.date),
                    textDirection: ui.TextDirection.ltr,
                    style: AppType.micro(color: AppColors.textLow),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════ سجلّ ايرث لنك ═════════════════

class ElAuditScreen extends StatefulWidget {
  const ElAuditScreen({super.key});

  @override
  State<ElAuditScreen> createState() => _ElAuditScreenState();
}

class _ElAuditScreenState extends State<ElAuditScreen> {
  static const List<int> _counts = [50, 100, 200];
  static const List<String> _countLabels = ['٥٠', '١٠٠', '٢٠٠'];

  int _index = 1; // ١٠٠ افتراضاً
  List<ElAuditRow>? _items;
  bool _loading = true;
  String? _error;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final req = ++_req;
    if (mounted) setState(() => _loading = true);
    final r = await EarthlinkApi.audit(rowCount: _counts[_index]);
    if (!mounted || req != _req) return;
    setState(() {
      _loading = false;
      if (r.message == null) {
        _items = r.items;
        _error = null;
      } else {
        _error = r.message;
      }
    });
  }

  void _select(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = i;
      _items = null;
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return _ElReadScaffold(
      title: 'el.audit_title'.tr(),
      subtitle: 'el.audit_hint'.tr(),
      loading: _loading,
      error: _error,
      hasData: items != null,
      isEmpty: items != null && items.isEmpty,
      emptyIcon: LucideIcons.history,
      emptyText: 'el.audit_empty'.tr(),
      onRefresh: _load,
      header: SheetSegmented(
        labels: _countLabels,
        selectedIndex: _index,
        onSelect: _select,
      ),
      content: items == null
          ? const SizedBox.shrink()
          : _ElListCard(
              icon: LucideIcons.history,
              title: 'el.audit_title'.tr(),
              countLabel: formatIQD(items.length),
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: Sp.sm),
                  _AuditRow(row: items[i]),
                ],
              ],
            ),
    );
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.row});
  final ElAuditRow row;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final meta = <String>[
      if (row.actor != null) 'el.audit_by'.tr(namedArgs: {'name': row.actor!}),
      if (row.date != null) _shortDate(row.date),
    ].join('  ·  ');
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.dot, size: 16, color: AppColors.brand),
          ),
          const SizedBox(width: Sp.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.text,
                  style: AppType.body(color: AppColors.textHi)
                      .copyWith(height: 1.4),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    style: AppType.micro(color: AppColors.textLow),
                  ),
                ],
              ],
            ),
          ),
          if (row.amount != null && row.amount != 0) ...[
            const SizedBox(width: Sp.sm),
            Text(
              formatIQD(row.amount!),
              textDirection: ui.TextDirection.ltr,
              style: AppType.statValue(
                color: row.amount! < 0 ? AppColors.error : AppColors.success,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════ المشتركون حسب الباقة ═════════════════

class ElByPackageScreen extends StatefulWidget {
  const ElByPackageScreen({super.key});

  @override
  State<ElByPackageScreen> createState() => _ElByPackageScreenState();
}

class _ElByPackageScreenState extends State<ElByPackageScreen> {
  List<ElPackageCount>? _items;
  bool _loading = true;
  String? _error;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final req = ++_req;
    if (mounted) setState(() => _loading = true);
    final r = await EarthlinkApi.byPackage();
    if (!mounted || req != _req) return;
    setState(() {
      _loading = false;
      if (r.message == null) {
        _items = r.items;
        _error = null;
      } else {
        _error = r.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final total =
        items == null ? 0 : items.fold<int>(0, (s, p) => s + p.count);
    final max = items == null || items.isEmpty
        ? 0
        : items.map((p) => p.count).reduce((a, b) => a > b ? a : b);
    return _ElReadScaffold(
      title: 'el.by_package_title'.tr(),
      subtitle: 'el.by_package_hint'.tr(),
      loading: _loading,
      error: _error,
      hasData: items != null,
      isEmpty: items != null && items.isEmpty,
      emptyIcon: LucideIcons.package,
      emptyText: 'el.by_package_empty'.tr(),
      onRefresh: _load,
      content: items == null
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ElSummaryCard(
                  icon: LucideIcons.users,
                  label: 'el.by_package_total'.tr(),
                  value: formatIQD(total),
                  trailingLabel: 'el.by_package_count'.tr(),
                  trailingValue: formatIQD(items.length),
                ),
                const SizedBox(height: Sp.lg),
                _ElListCard(
                  icon: LucideIcons.package,
                  title: 'el.by_package_title'.tr(),
                  countLabel: formatIQD(items.length),
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: Sp.sm),
                      _PackageRow(row: items[i], max: max),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

class _PackageRow extends StatelessWidget {
  const _PackageRow({required this.row, required this.max});
  final ElPackageCount row;
  final int max;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final ratio = max <= 0 ? 0.0 : (row.count / max).clamp(0.0, 1.0);
    return Container(
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
            children: [
              Expanded(
                child: Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(color: AppColors.textHi)
                      .copyWith(fontSize: 13.5),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Text(
                _subsCount(row.count),
                style: AppType.bodyStrong(color: AppColors.brand),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.surfaceSunken,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.brand),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════ الهيكل المشترك ═════════════════

String _subsCount(int n) => '${formatIQD(n)} ${'el.subscriber_unit'.tr()}';

/// «2026-11-02 10:00» — يقصّ الثواني ومحرف الفصل T إن وُجد. يبقى LTR.
String _shortDate(String? raw) {
  if (raw == null) return '';
  final s = raw.trim().replaceFirst('T', ' ');
  return s.length >= 16 ? s.substring(0, 16) : s;
}

class _ElReadScaffold extends StatelessWidget {
  const _ElReadScaffold({
    required this.title,
    required this.subtitle,
    required this.loading,
    required this.error,
    required this.hasData,
    required this.isEmpty,
    required this.emptyIcon,
    required this.emptyText,
    required this.onRefresh,
    required this.content,
    this.header,
  });

  final String title;
  final String subtitle;
  final bool loading;
  final String? error;
  final bool hasData;
  final bool isEmpty;
  final IconData emptyIcon;
  final String emptyText;
  final Future<void> Function() onRefresh;
  final Widget content;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Directionality(
      textDirection: ui.TextDirection.rtl,
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
                Text(title,
                    style: AppType.title(color: AppColors.textHi)
                        .copyWith(fontSize: 16)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted().copyWith(fontSize: 11)),
              ],
            ),
            actions: [
              if (loading)
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
                  onPressed: () => onRefresh(),
                  tooltip: 'el.refresh'.tr(),
                  icon: Icon(LucideIcons.refreshCw,
                      size: 18, color: AppColors.textMid),
                ),
            ],
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            color: AppColors.brandAccent,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                if (header != null) ...[
                  header!,
                  const SizedBox(height: Sp.lg),
                ],
                if (!hasData && error != null)
                  _errorState(context, error!, onRefresh, loading)
                else if (!hasData)
                  _skeleton(header == null)
                else if (isEmpty)
                  _stateBox(
                    icon: emptyIcon,
                    tone: AppTone.brand,
                    title: emptyText,
                  )
                else
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: loading ? 0.6 : 1,
                    child: content,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _skeleton(bool withSummary) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (withSummary) ...[
        const SkeletonBox(height: 96, borderRadius: R.card),
        const SizedBox(height: Sp.lg),
      ],
      for (var i = 0; i < 5; i++) ...[
        if (i > 0) const SizedBox(height: Sp.sm),
        const SkeletonBox(height: 64, borderRadius: R.md),
      ],
    ],
  );
}

Widget _errorState(
  BuildContext context,
  String message,
  Future<void> Function() onRetry,
  bool loading,
) {
  return _stateBox(
    icon: LucideIcons.triangleAlert,
    tone: AppTone.danger,
    title: message,
    message: 'el.error_hint'.tr(),
    action: SizedBox(
      height: H.button,
      child: Material(
        color: AppColors.brand,
        borderRadius: BorderRadius.circular(R.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : () => onRetry(),
          child: Center(
            child: loading
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
                      Text('common.retry'.tr(),
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

/// بطاقة ملخّصٍ خضراء كرأس «الكارتات المطلوبة» — قيمةٌ رئيسيّة وربّما ثانويّة.
class _ElSummaryCard extends StatelessWidget {
  const _ElSummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    this.trailingLabel,
    this.trailingValue,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? trailingLabel;
  final String? trailingValue;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _stat(icon: icon, label: label, value: value),
            ),
            if (trailingLabel != null && trailingValue != null) ...[
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: Sp.md),
                color: AppColors.onBrandFill2,
              ),
              Expanded(
                child: _stat(
                  icon: LucideIcons.layers,
                  label: trailingLabel!,
                  value: trailingValue!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat({
    required IconData icon,
    required String label,
    required String value,
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
          child: Text(
            value,
            textDirection: ui.TextDirection.ltr,
            style:
                AppType.amount(color: AppColors.onBrand).copyWith(fontSize: 22),
          ),
        ),
      ],
    );
  }
}

/// بطاقة قائمةٍ بيضاء برأسٍ (أيقونة + عنوان + عدّاد) ثمّ الصفوف.
class _ElListCard extends StatelessWidget {
  const _ElListCard({
    required this.icon,
    required this.title,
    required this.countLabel,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String countLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
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
                child: Icon(icon, size: 18, color: AppColors.brand),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.cardTitleBold(color: AppColors.textHi)),
              ),
              Text(countLabel, style: AppType.muted(color: AppColors.textMid)),
            ],
          ),
          const SizedBox(height: Sp.lg),
          ...children,
        ],
      ),
    );
  }
}
