import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/discounts_api.dart';
import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Existing discount preview lookup map by username (lower-cased).
/// Built once after loading discounts so the grid can show 'يوجد خصم'
/// badge on subscribers who already have one (مطلب 2026-06-12 مطابق
/// v1 _SubscriberSelectCard).
typedef _ExistingMap = Map<String, num>;

/// تطبيق خصم على عدة مشتركين دفعة واحدة. مطابق v1
/// (mobile-app/lib/screens/discounts_screen.dart) مع تحسينات تصميم.
/// الـbackend: POST /api/v2/discounts/bulk-apply.
Future<bool?> showBulkApplyDiscountSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _BulkApplySheet(),
  );
}

class _BulkApplySheet extends StatefulWidget {
  const _BulkApplySheet();

  @override
  State<_BulkApplySheet> createState() => _BulkApplySheetState();
}

class _BulkApplySheetState extends State<_BulkApplySheet> {
  final _amountCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  int _amount = 0;
  bool _submitting = false;
  bool _loadingSubs = true;
  bool _suppressFormat = false;
  List<Subscriber> _all = const [];
  _ExistingMap _existing = const {};
  final Set<String> _selected = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onAmount);
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q == _query) return;
      setState(() => _query = q);
    });
    _loadSubs();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSubs() async {
    // نحمّل المشتركين + الخصومات الحالية بالتوازي عشان نقدر نظهر
    // 'يوجد خصم' badge على مَن يحمل خصماً سابقاً.
    final results = await Future.wait([
      SubscribersApi.loadAll(),
      DiscountsApi.list(),
    ]);
    if (!mounted) return;
    final list = results[0] as List<Subscriber>?;
    final discounts = results[1] as List<Discount>;
    final map = <String, num>{};
    for (final d in discounts) {
      map[d.subscriberUsername.toLowerCase()] = d.discountAmount;
    }
    setState(() {
      _all = list ?? const [];
      _existing = map;
      _loadingSubs = false;
    });
  }

  void _onAmount() {
    if (_suppressFormat) return;
    final digits = _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final parsed = int.tryParse(digits) ?? 0;
    final formatted = _fmt(parsed);
    if (formatted != _amountCtrl.text) {
      _suppressFormat = true;
      _amountCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
      _suppressFormat = false;
    }
    if (parsed != _amount) setState(() => _amount = parsed);
  }

  static String _fmt(int v) {
    if (v == 0) return '';
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  List<Subscriber> get _filtered {
    if (_query.isEmpty) return _all;
    final q = _query.toLowerCase();
    return _all.where((s) {
      return s.username.toLowerCase().contains(q) ||
          s.fullName.toLowerCase().contains(q) ||
          s.displayPhone.contains(q);
    }).toList();
  }

  void _toggle(String username) {
    setState(() {
      if (_selected.contains(username)) {
        _selected.remove(username);
      } else {
        _selected.add(username);
      }
    });
  }

  void _selectAllVisible() {
    setState(() {
      for (final s in _filtered) {
        _selected.add(s.username);
      }
    });
  }

  void _clearSelection() {
    setState(() => _selected.clear());
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (_amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل قيمة الخصم'),
          backgroundColor: Color(0xFFE08F2D),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر مشتركاً واحداً على الأقل'),
          backgroundColor: Color(0xFFE08F2D),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    final r = await DiscountsApi.bulkApply(
      usernames: _selected.toList(),
      discountAmount: _amount,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    final summary = r.ok
        ? 'جديد ${r.applied} · محدّث ${r.updated}'
            '${r.failed > 0 ? ' · فشل ${r.failed}' : ''}'
        : (r.message ?? 'فشل التطبيق');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary),
        backgroundColor: r.ok ? AppColors.brand : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
    if (r.ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const accent = Color(0xFF14B8A6);
    final filtered = _filtered;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(R.xl)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(R.md),
                      ),
                      child: const Icon(LucideIcons.percent,
                          size: 16, color: accent),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تطبيق خصم دفعة',
                            style: AppType.title(color: AppColors.textHi)
                                .copyWith(fontSize: 15),
                          ),
                          Text(
                            '${_selected.length} مشترك مختار',
                            style: AppType.muted().copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.x, size: 16),
                      color: AppColors.textMid,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4, right: 2),
                      child: Text(
                        'قيمة الخصم *',
                        style: AppType.muted(color: AppColors.textMid)
                            .copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      style: AppType.input(color: AppColors.textHi),
                      decoration: InputDecoration(
                        hintText: 'مثلاً 5,000',
                        hintStyle:
                            AppType.input(color: AppColors.textLow),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.sm),
                          borderSide: BorderSide(
                              color: AppColors.border
                                  .withValues(alpha: 0.5)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.sm),
                          borderSide: BorderSide(
                              color: AppColors.border
                                  .withValues(alpha: 0.5)),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        suffixText: 'د.ع',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final v in const [
                          5000,
                          10000,
                          15000,
                          20000,
                          25000
                        ])
                          _quickAmount(v, accent),
                      ],
                    ),
                    const SizedBox(height: Sp.md),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(R.pill),
                        border: Border.all(
                            color: AppColors.border
                                .withValues(alpha: 0.5)),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: Sp.md),
                      child: Row(
                        children: [
                          Icon(LucideIcons.search,
                              size: 16, color: AppColors.textMid),
                          const SizedBox(width: Sp.sm),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              style:
                                  AppType.input(color: AppColors.textHi),
                              decoration: InputDecoration(
                                hintText: 'ابحث عن مشترك…',
                                hintStyle: AppType.input(
                                    color: AppColors.textLow),
                                border: InputBorder.none,
                                isCollapsed: true,
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _miniBtn(
                          icon: LucideIcons.listChecks,
                          label: 'اختر المرئيين',
                          onTap: filtered.isEmpty
                              ? null
                              : _selectAllVisible,
                          color: accent,
                        ),
                        const SizedBox(width: 6),
                        _miniBtn(
                          icon: LucideIcons.eraser,
                          label: 'مسح',
                          onTap: _selected.isEmpty ? null : _clearSelection,
                          color: AppColors.error,
                        ),
                        const Spacer(),
                        Text(
                          '${filtered.length} نتيجة',
                          style: AppType.muted().copyWith(fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loadingSubs
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(Sp.huge),
                            child: Center(
                              child: Text(
                                _query.isEmpty
                                    ? 'لا يوجد مشتركون'
                                    : 'لا توجد نتائج لـ "$_query"',
                                style: AppType.muted().copyWith(fontSize: 12),
                              ),
                            ),
                          )
                        : GridView.builder(
                            controller: controller,
                            padding: const EdgeInsets.fromLTRB(
                                Sp.lg, 0, Sp.lg, 0),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 2.4,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final s = filtered[i];
                              final selected =
                                  _selected.contains(s.username);
                              final existingAmount =
                                  _existing[s.username.toLowerCase()];
                              return _SubscriberCard(
                                sub: s,
                                selected: selected,
                                accent: accent,
                                existingDiscount: existingAmount,
                                onTap: () => _toggle(s.username),
                              );
                            },
                          ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      Sp.lg, 0, Sp.lg, Sp.md),
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed:
                          (_amount > 0 && _selected.isNotEmpty && !_submitting)
                              ? _submit
                              : null,
                      icon: _submitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.percent, size: 16),
                      label: Text(
                        _submitting
                            ? 'جاري التطبيق...'
                            : (_amount > 0 && _selected.isNotEmpty
                                ? 'تطبيق ${formatIQD(_amount)} على ${_selected.length}'
                                : 'تطبيق الخصم'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(R.md),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _quickAmount(int v, Color accent) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final next = _amount + v;
          final f = _fmt(next);
          _suppressFormat = true;
          _amountCtrl.value = TextEditingValue(
              text: f,
              selection: TextSelection.collapsed(offset: f.length));
          _suppressFormat = false;
          setState(() => _amount = next);
        },
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: accent.withValues(alpha: 0.3)),
          ),
          child: Text(
            '+${_fmt(v)}',
            style: TextStyle(
              color: accent,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
  }) {
    final disabled = onTap == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: disabled
                ? AppColors.surfaceInput
                : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: disabled
                  ? AppColors.border
                  : color.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 11,
                  color: disabled ? AppColors.textLow : color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: disabled ? AppColors.textLow : color,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// مطلب 2026-06-12: card grid مطابق v1 _SubscriberSelectCard.
/// يعرض اليوزر + الاسم العربي + الباقة + badge 'يوجد خصم' بقيمته
/// لو المشترك عنده خصم سابق.
class _SubscriberCard extends StatelessWidget {
  const _SubscriberCard({
    required this.sub,
    required this.selected,
    required this.accent,
    required this.existingDiscount,
    required this.onTap,
  });
  final Subscriber sub;
  final bool selected;
  final Color accent;
  final num? existingDiscount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(
              color: selected
                  ? accent
                  : AppColors.border.withValues(alpha: 0.5),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(
                    selected
                        ? LucideIcons.squareCheck
                        : LucideIcons.square,
                    size: 12,
                    color: selected ? accent : AppColors.textLow,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      sub.username,
                      style: AppType.label(color: AppColors.textHi)
                          .copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (sub.fullName != sub.username) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    sub.fullName,
                    style: AppType.muted().copyWith(fontSize: 9.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if ((sub.profileName ?? '').isNotEmpty) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    sub.profileName!,
                    style: AppType.label(color: const Color(0xFF14B8A6))
                        .copyWith(
                            fontSize: 9.5, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (existingDiscount != null && existingDiscount! > 0) ...[
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE08F2D).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(R.sm),
                    border: Border.all(
                        color: const Color(0xFFE08F2D)
                            .withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '-${formatIQD(existingDiscount!)}',
                    style: const TextStyle(
                      color: Color(0xFFE08F2D),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
