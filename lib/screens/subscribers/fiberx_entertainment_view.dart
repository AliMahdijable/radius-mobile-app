import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/fiberx_entertainment_api.dart';
import '../../core/util/bidi.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «مشتركون الخدمة الترفيهية» (المحتوى) لوكيل فايبر اكس — قراءةٌ فقط، كتبويب بوّابتهم:
/// أربع بطاقات أعداد (الإجمالي · نشطون · منتهون · على وشك الانتهاء) + بحثٌ محلّيّ + قائمة.
/// التفعيل غير متاحٍ بعد (مسار الكتابة لم يُلتقط) — فلا زرّ «تفعيل مستخدم جديد».
class FiberxEntertainmentView extends StatefulWidget {
  const FiberxEntertainmentView({super.key});

  @override
  State<FiberxEntertainmentView> createState() => _FiberxEntertainmentViewState();
}

class _FiberxEntertainmentViewState extends State<FiberxEntertainmentView> {
  final _searchCtrl = TextEditingController();
  FxEntResult? _data;
  String? _error;
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q != _query) setState(() => _query = q);
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final r = await FiberxEntertainmentApi.fetch();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = r.result;
      _error = r.error;
    });
  }

  List<FxEntRow> get _filtered {
    final rows = _data?.rows ?? const <FxEntRow>[];
    final q = _query.toLowerCase();
    if (q.isEmpty) return rows;
    return rows
        .where((r) =>
            '${r.username} ${r.name} ${r.phone} ${r.package}'.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (d != null) ...[
            SliverToBoxAdapter(child: _summary(d.summary)),
            SliverToBoxAdapter(child: _search()),
          ],
          if (_loading && d == null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator(color: AppColors.brand)),
            )
          else if (_error != null && d == null)
            SliverFillRemaining(hasScrollBody: false, child: _message(_error!, isError: true))
          else if (_filtered.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _message(
                  _query.isNotEmpty ? 'لا نتائج للبحث' : 'لا مشتركين بالخدمة الترفيهية'),
            )
          else
            SliverList.builder(
              itemCount: _filtered.length,
              itemBuilder: (_, i) => _row(_filtered[i]),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: Sp.lg)),
        ],
      ),
    );
  }

  Widget _summary(FxEntSummary s) => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.sm),
        child: Row(children: [
          _stat('الإجمالي', s.total, AppColors.brand, LucideIcons.users),
          const SizedBox(width: Sp.sm),
          _stat('نشطون', s.active, AppColors.success, LucideIcons.userCheck),
          const SizedBox(width: Sp.sm),
          _stat('منتهون', s.expired, AppColors.error, LucideIcons.userX),
          const SizedBox(width: Sp.sm),
          _stat('على وشك', s.nearExpiry, AppColors.warning, LucideIcons.clock),
        ]),
      );

  Widget _stat(String label, int n, Color color, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Sp.md, horizontal: Sp.xs),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: Sp.xs),
            Text(iso('$n'),
                style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 20)),
            const SizedBox(height: 2),
            Text(label,
                style: AppType.muted(color: AppColors.textMid),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

  Widget _search() => Padding(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.sm),
        child: TextField(
          controller: _searchCtrl,
          style: AppType.body(color: AppColors.textHi),
          decoration: InputDecoration(
            hintText: 'ابحث عن مشترك',
            prefixIcon: const Icon(LucideIcons.search, size: 18),
            filled: true,
            fillColor: AppColors.surfaceInput,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide.none),
          ),
        ),
      );

  Widget _row(FxEntRow r) {
    final (tone, toneBg) = switch (r.status) {
      'active' => (AppColors.success, AppColors.successSoftBg),
      'expired' => (AppColors.error, AppColors.dangerSoftBg),
      _ => (AppColors.textMid, AppColors.surfaceInput),
    };
    final title = r.name.trim().isNotEmpty ? r.name : r.username;
    return Container(
      margin: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title,
                style: AppType.bodyBold(color: AppColors.textHi),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
            decoration: BoxDecoration(
                color: toneBg, borderRadius: BorderRadius.circular(R.sm)),
            child: Text(r.statusLabel, style: AppType.muted(color: tone)),
          ),
        ]),
        if (title != r.username) ...[
          const SizedBox(height: 2),
          Text(iso(r.username), style: AppType.muted(color: AppColors.textLow)),
        ],
        const SizedBox(height: Sp.sm),
        Wrap(spacing: Sp.md, runSpacing: Sp.xs, children: [
          if (r.package.isNotEmpty) _meta(LucideIcons.package, r.package),
          if (r.expiry.isNotEmpty)
            _meta(LucideIcons.calendar, iso(r.expiry.split(' ').first)),
          if (r.remainingDays != null)
            _meta(LucideIcons.timer,
                iso(r.remainingDays! >= 0 ? '${r.remainingDays} يوم' : 'منتهٍ')),
          if (r.phone.isNotEmpty) _meta(LucideIcons.phone, iso(r.phone)),
        ]),
      ]),
    );
  }

  Widget _meta(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: AppColors.textLow),
        const SizedBox(width: 4),
        Text(text, style: AppType.muted(color: AppColors.textMid)),
      ]);

  Widget _message(String text, {bool isError = false}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.lg),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(isError ? LucideIcons.triangleAlert : LucideIcons.tv,
                size: 32, color: isError ? AppColors.error : AppColors.textLow),
            const SizedBox(height: Sp.sm),
            Text(text,
                style: AppType.body(color: AppColors.textMid), textAlign: TextAlign.center),
            if (isError) ...[
              const SizedBox(height: Sp.md),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ]),
        ),
      );
}
