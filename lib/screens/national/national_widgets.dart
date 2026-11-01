import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_portal_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// أدوات شاشات المشروع الوطنيّ (التذاكر، المهامّ والطلبات، الحركات الماليّة — ٣١ أكتوبر): بحثٌ بتأخيرٍ قصير، ورقة «الفلاتر»
/// باختياراتٍ (الكلّ أوّلاً)، والفترة الجاهزة، وحالات التحميل/الانتظار/الخطأ/الفراغ، و«تحميل المزيد».

/// بحثٌ يُرسَل بعد ٤٠٠مث من آخر حرف (أو زرّ الإدخال) — لا نداء لكلّ حرف.
class NationalSearchField extends StatefulWidget {
  const NationalSearchField({super.key, required this.hint, required this.onChanged, this.initial = ''});
  final String hint;
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<NationalSearchField> createState() => _NationalSearchFieldState();
}

class _NationalSearchFieldState extends State<NationalSearchField> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.initial);
  Timer? _debounce;
  late String _sent = widget.initial;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _commit() {
    _debounce?.cancel();
    final v = _ctrl.text.trim();
    if (v == _sent) return;
    _sent = v;
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _ctrl,
        textInputAction: TextInputAction.search,
        onChanged: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), _commit);
          setState(() {});
        },
        onSubmitted: (_) => _commit(),
        maxLength: 64,
        style: AppType.input(color: AppColors.textHi),
        decoration: InputDecoration(
          counterText: '',
          hintText: widget.hint,
          hintStyle: AppType.input(color: AppColors.textPlaceholder),
          prefixIcon: Icon(LucideIcons.search, size: 18, color: AppColors.textMid),
          suffixIcon: _ctrl.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'مسح',
                  icon: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
                  onPressed: () {
                    _ctrl.clear();
                    setState(() {});
                    _commit();
                  },
                ),
          filled: true,
          fillColor: AppColors.surfaceInput,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide(color: AppColors.brand, width: 1.5)),
        ),
      ),
    );
  }
}

/// زرّ «الفلاتر» بعدد المفعّل منها.
class NationalFilterButton extends StatelessWidget {
  const NationalFilterButton({super.key, required this.active, required this.onTap});
  final int active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final on = active > 0;
    return Material(
      color: on ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: on ? AppColors.brandSoftBorder : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.slidersHorizontal, size: 18, color: on ? AppColors.brand : AppColors.textMid),
              const SizedBox(width: 6),
              Text('الفلاتر', style: AppType.label(color: on ? AppColors.brand : AppColors.textHi)),
              if (on) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(R.pill)),
                  child: Text('$active', style: AppType.micro(color: AppColors.onBrand)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// اختيارٌ في ورقة الفلاتر.
class NationalChoice {
  const NationalChoice(this.value, this.label);
  final String value;
  final String label;
}

/// قسمٌ في ورقة الفلاتر: عنوانه، وخياراته (null = لم تصل بعد)، وقيمته الحاليّة ('' = الكلّ). أو ([NationalFilterSection.text])
/// حقلٌ يُكتب (رقم المعاملة، رقم الاشتراك) — فارغه = الكلّ.
class NationalFilterSection {
  const NationalFilterSection({required this.key, required this.title, required this.options, this.value = '', this.allLabel = 'الكلّ'})
      : isText = false,
        hint = null,
        digits = false;
  const NationalFilterSection.text({required this.key, required this.title, this.value = '', this.hint, this.digits = false})
      : isText = true,
        options = const [],
        allLabel = '';
  final String key;
  final String title;
  final List<NationalChoice>? options;
  final String value;
  final String allLabel;
  final bool isText;
  final String? hint;

  /// أرقامٌ وحدها (لوحة أرقام، ٤٠ حرفاً).
  final bool digits;
}

/// الفترات الجاهزة لفلترٍ اختياريّ: '' = بلا فترة.
const List<NationalChoice> nationalPeriods = [
  NationalChoice('today', 'اليوم'),
  NationalChoice('7d', 'آخر ٧ أيّام'),
  NationalChoice('30d', 'آخر ٣٠ يوماً'),
  NationalChoice('month', 'هذا الشهر'),
];

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// الفترة الجاهزة ⇒ (من، إلى) بأيّام «YYYY-MM-DD»؛ '' ⇒ (null، null).
({String? from, String? to}) nationalPeriodRange(String period, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  switch (period) {
    case 'today':
      return (from: _day(today), to: _day(today));
    case '7d':
      return (from: _day(today.subtract(const Duration(days: 6))), to: _day(today));
    case '30d':
      return (from: _day(today.subtract(const Duration(days: 29))), to: _day(today));
    case 'month':
      return (from: _day(DateTime(today.year, today.month, 1)), to: _day(today));
    default:
      return (from: null, to: null);
  }
}

/// ورقة «الفلاتر»: أقسامٌ بخياراتٍ (الكلّ أوّلاً) و«تطبيق» يعيد القيم الجديدة (key ⇒ value، '' = الكلّ)، أو null عند الإغلاق.
Future<Map<String, String>?> showNationalFilters(BuildContext context, {required List<NationalFilterSection> sections}) {
  return showAppSheet<Map<String, String>>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FiltersSheet(sections: sections),
  );
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.sections});
  final List<NationalFilterSection> sections;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late final Map<String, String> _v = {for (final s in widget.sections) s.key: s.value};
  late final Map<String, TextEditingController> _text = {
    for (final s in widget.sections)
      if (s.isText) s.key: TextEditingController(text: s.value),
  };

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(NationalFilterSection s) {
    final c = _text[s.key]!;
    return SizedBox(
      height: 44,
      child: TextField(
        controller: c,
        keyboardType: s.digits ? TextInputType.number : TextInputType.text,
        textDirection: TextDirection.ltr,
        maxLength: 40,
        // الأرقام الهنديّة (٠-٩) تُقرأ لاتينيّة قبل التنظيف — لوحة عربيّة لا تُسقط الرقم كلّه
        onChanged: (v) => _v[s.key] = s.digits ? (normalizeDigits(v) ?? '').replaceAll(RegExp(r'[^0-9]'), '') : v.trim(),
        style: AppType.input(color: AppColors.textHi),
        decoration: InputDecoration(
          counterText: '',
          hintText: s.hint,
          hintTextDirection: TextDirection.rtl,
          hintStyle: AppType.input(color: AppColors.textPlaceholder),
          filled: true,
          fillColor: AppColors.surfaceInput,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.sm), borderSide: BorderSide(color: AppColors.brand, width: 1.5)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.slidersHorizontal,
        title: 'الفلاتر',
        subtitle: 'اختر ثمّ «تطبيق»',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final s in widget.sections) ...[
            Text(s.title, style: AppType.label(color: AppColors.textLabel)),
            const SizedBox(height: Sp.sm),
            if (s.isText)
              _field(s)
            else if (s.options == null)
              Text('جارٍ تحميل الخيارات…', style: AppType.muted())
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip(s.key, '', s.allLabel),
                  for (final o in s.options!) _chip(s.key, o.value, o.label),
                ],
              ),
            const SizedBox(height: Sp.lg),
          ],
        ],
      ),
      footer: SheetFooterBar(
        label: 'تطبيق',
        icon: LucideIcons.check,
        onPressed: () => Navigator.of(context).pop(Map<String, String>.from(_v)),
      ),
    );
  }

  Widget _chip(String key, String value, String label) {
    final on = (_v[key] ?? '') == value;
    return ChoiceChip(
      label: Text(label),
      selected: on,
      onSelected: (_) => setState(() => _v[key] = value),
      labelStyle: AppType.label(color: on ? AppColors.brand : AppColors.textHi),
      selectedColor: AppColors.brandSoftBg,
      backgroundColor: AppColors.surface,
      side: BorderSide(color: on ? AppColors.brandSoftBorder : AppColors.border),
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.pill)),
    );
  }
}

/// حالة القائمة حين لا صفوف: تحميل · انتظار البوّابة · خطأ (مع إعادة) · فراغ.
class NationalStateBox extends StatelessWidget {
  const NationalStateBox.loading({super.key, this.text = 'جارٍ التحميل…'})
      : icon = null,
        onRetry = null,
        busy = true;
  const NationalStateBox.pending({super.key, this.text = 'جارٍ الجلب من بوّابة المشروع الوطني…'})
      : icon = LucideIcons.hourglass,
        onRetry = null,
        busy = true;
  const NationalStateBox.error({super.key, required this.text, required this.onRetry})
      : icon = LucideIcons.circleAlert,
        busy = false;
  const NationalStateBox.empty({super.key, required this.text, required IconData this.icon})
      : onRetry = null,
        busy = false;

  final String text;
  final IconData? icon;
  final VoidCallback? onRetry;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: Sp.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5))
          else if (icon != null)
            Icon(icon, size: 34, color: onRetry != null ? AppColors.error : AppColors.textLow),
          const SizedBox(height: Sp.md),
          Text(text, textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
          if (onRetry != null) ...[
            const SizedBox(height: Sp.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ],
      ),
    );
  }
}

/// «تحميل المزيد» أسفل القائمة.
class NationalLoadMore extends StatelessWidget {
  const NationalLoadMore({super.key, required this.loading, required this.onTap, required this.shown, required this.total, required this.unit});
  final bool loading;
  final VoidCallback onTap;
  final int shown;
  final int? total;
  final String unit;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.md),
      child: Column(
        children: [
          if (total != null)
            Text('$shown من $total $unit', style: AppType.muted()),
          const SizedBox(height: Sp.sm),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: loading ? null : onTap,
              child: loading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('تحميل المزيد'),
            ),
          ),
        ],
      ),
    );
  }
}

/// صفّ «عنوان — قيمة» في أوراق التفاصيل.
class NationalInfoRow extends StatelessWidget {
  const NationalInfoRow({super.key, required this.icon, required this.label, required this.value, this.ltr = false});
  final IconData icon;
  final String label;
  final String value;
  final bool ltr;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMid),
          const SizedBox(width: Sp.sm),
          Text(label, style: AppType.muted()),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              textDirection: ltr ? TextDirection.ltr : null,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppType.rowValue(color: AppColors.textHi),
            ),
          ),
        ],
      ),
    );
  }
}

/// مجموعة صفوفٍ بإطار.
class NationalInfoGroup extends StatelessWidget {
  const NationalInfoGroup({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, color: AppColors.divider),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// تاريخ «YYYY-MM-DD HH:MM» كما يرسله الخادم (بغداد) بلا ثوانٍ.
String nationalTime(String? v) => v == null || v.isEmpty ? '—' : (v.length > 16 ? v.substring(0, 16) : v);

/// قائمةٌ مرقّمة من قسمٍ وطنيّ: الصفوف المجموعة، وإعادة السؤال كلّ ٤ث ما دام الخادم يقول pending (حتى دقيقة)، وردٌّ قديم من
/// فلترٍ سابق يُهمل (الجيل).
class NationalPaged<T> {
  final List<T> rows = [];
  int page = 0;
  int? total;
  int? pageCount;
  bool loading = false;
  bool pending = false;
  String? error;

  /// آخر ردٍّ كاملاً (summary · balance · sum).
  Map<String, dynamic> raw = const {};
  int _gen = 0;
  int _polls = 0;
  Timer? _poll;

  bool get hasMore => pageCount != null && page < pageCount!;
  bool get started => page > 0 || loading || pending || error != null;

  void reset() {
    _poll?.cancel();
    _polls = 0;
    _gen++;
    rows.clear();
    page = 0;
    total = null;
    pageCount = null;
    // ردّ الجيل السابق يُهمل قبل أن يُطفئ «جارٍ التحميل» — فلا يبقى مشغولاً ويصدّ next() الجديد (شاشةٌ عالقة على التحميل)
    loading = false;
    pending = false;
    error = null;
    raw = const {};
  }

  /// الصفحة التالية. [onChange] بعد كلّ تغيير (setState)، و[alive] يقول إنّ الشاشة ما زالت قائمة.
  Future<void> next(
    Future<NationalResult<NationalPage<T>>> Function(int page) fetch, {
    required VoidCallback onChange,
    required bool Function() alive,
  }) async {
    if (loading) return;
    final gen = _gen;
    final want = page + 1;
    loading = true;
    onChange();
    final r = await fetch(want);
    if (!alive() || gen != _gen) return;
    loading = false;
    final d = r.data;
    if (!r.ok) {
      error = r.error;
    } else if (d!.pending) {
      pending = true;
      raw = d.raw;
    } else {
      pending = false;
      error = null;
      rows.addAll(d.items);
      page = want;
      total = d.total;
      pageCount = d.pageCount;
      raw = d.raw;
    }
    onChange();
    if (r.ok && d!.pending && _polls < 15) {
      _polls++;
      _poll?.cancel();
      _poll = Timer(const Duration(seconds: 4), () {
        if (alive() && gen == _gen) next(fetch, onChange: onChange, alive: alive);
      });
    }
  }

  void dispose() => _poll?.cancel();
}
