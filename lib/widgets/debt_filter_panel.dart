import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../api/broadcast_api.dart';
import '../core/util/amount_input.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';
import 'list_kit.dart';

/// لوحة «تحديد المدينين» — مشتركةٌ بين «التبليغات» و«إرسال عام» تلغرام (٩ نوفمبر). عمر **أقدم دينٍ لم يُسدَّد** و/أو مبلغ الدين،
/// اختياريّان، والنتيجة من الخادم تحتهما (هو وحده يحسب العمر). الحقول (الأيّام والمبلغان) هنا؛ الفلتر نفسه عند الشاشة (onChanged)،
/// والحقول تُملأ منه كلّما بُنيت اللوحة من جديد أو غيّرته الشاشة — فما يُرى هو ما يُطبَّق.
/// «نحسب…» للحساب الكبير بنصّ الخادم (pendingText). المفاتيح كما كانت في التبليغات: debt-filter-panel · df-age-N · df-age-custom ·
/// df-min · df-max · debt-filter-result.
class DebtFilterPanel extends StatefulWidget {
  const DebtFilterPanel({
    super.key,
    required this.cap,
    required this.value,
    required this.onChanged,
    required this.busy,
    this.pendingText,
    this.error,
    this.preview,
    this.onRetry,
    this.noun = 'مديناً',
  });

  final DebtFilterCapability cap;
  final DebtFilter value;
  final ValueChanged<DebtFilter> onChanged;
  final bool busy;

  /// الحساب الكبير: ما قاله الخادم وهو يحسب في الخلفيّة.
  final String? pendingText;
  final String? error;
  final BroadcastPreview? preview;
  final VoidCallback? onRetry;

  /// «مديناً يطابقون» · «مربوطاً مديناً يطابقون» (تلغرام).
  final String noun;

  @override
  State<DebtFilterPanel> createState() => _DebtFilterPanelState();
}

class _DebtFilterPanelState extends State<DebtFilterPanel> {
  final _ageCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  bool _customAge = false;

  /// آخر ما أُرسل للشاشة — نقرتان قبل إعادة البناء تبنيان على الأحدث لا على القديم.
  late DebtFilter _cur;

  static const _ranges = <(String, int?, int?)>[
    ('حتى 25 ألف', null, 25000),
    ('25 إلى 50 ألف', 25000, 50000),
    ('50 إلى 100 ألف', 50000, 100000),
    ('100 ألف فأكثر', 100000, null),
  ];

  @override
  void initState() {
    super.initState();
    _cur = widget.value;
    _fill(widget.value);
  }

  /// الحقول من الفلتر المطبَّق [f] — ما يُرى هو ما يُطبَّق (مراجعة 3.0.18): اللوحة تُبنى من جديد والفلتر باقٍ عند الشاشة (تبديل الفئة
  /// والعودة، السحب للتحديث، تمريرٌ أخرجها من القائمة الكسولة)، فكانت «من»/«إلى» تظهر فارغةً والعدّ والإرسال بمبلغها.
  void _fill(DebtFilter f) {
    _minCtrl.text = f.minAmount == null ? '' : AmountShorthand.format(f.minAmount!);
    _maxCtrl.text = f.maxAmount == null ? '' : AmountShorthand.format(f.maxAmount!);
    final d = f.minAgeDays;
    _customAge = d != null && !widget.cap.presets.contains(d);
    _ageCtrl.text = _customAge ? '$d' : '';
  }

  @override
  void didUpdateWidget(covariant DebtFilterPanel old) {
    super.didUpdateWidget(old);
    // غيّرته الشاشة لا اللوحة (مسحٌ مثلاً) ⇒ الحقول منه؛ وما أرسلته اللوحة نفسها يعود كما هو فلا يُمسّ ما يكتبه المدير
    if (widget.value != _cur) {
      _cur = widget.value;
      _fill(widget.value);
    }
  }

  @override
  void dispose() {
    _ageCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  DebtFilter get _df => _cur;
  void _set(DebtFilter f) {
    _cur = f;
    widget.onChanged(f);
  }

  Widget _note(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.sm)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: AppColors.textMid),
            const SizedBox(width: 6),
            Expanded(child: Text(text, maxLines: 3, style: AppType.micro(color: AppColors.textMid).copyWith(height: 1.5))),
          ],
        ),
      );

  Widget _amountBox(TextEditingController c, String hint, bool min) => Expanded(
        child: SizedBox(
          height: H.search,
          child: TextField(
            key: ValueKey(min ? 'df-min' : 'df-max'),
            controller: c,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.end,
            onChanged: (_) {
              final v = AmountShorthand.parse(c.text);
              final f = AmountShorthand.format(v);
              if (f != c.text) c.value = TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
              _set(min
                  ? _df.copyWith(minAmount: () => v > 0 || c.text.trim().isNotEmpty ? v : null)
                  : _df.copyWith(maxAmount: () => v > 0 ? v : null));
            },
            style: AppType.input(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: AppType.input(color: AppColors.textPlaceholder),
              suffixText: ' د.ع',
              suffixStyle: AppType.micro(color: AppColors.textMid),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.warning)),
            ),
          ),
        ),
      );

  void _setRange(int? min, int? max) {
    _minCtrl.text = min == null ? '' : AmountShorthand.format(min);
    _maxCtrl.text = max == null ? '' : AmountShorthand.format(max);
    _set(_df.copyWith(minAmount: () => min, maxAmount: () => max));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final cap = widget.cap;
    final problem = _df.problem(maxAgeDays: cap.maxAgeDays);
    final ageIsPreset = _df.minAgeDays != null && cap.presets.contains(_df.minAgeDays) && !_customAge;
    final pv = widget.preview;
    return Container(
      key: const ValueKey('debt-filter-panel'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.warningSoftBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.warningSoftBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const ListIconBox(icon: LucideIcons.funnel, tone: ListTone.warning, size: 30),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('تحديد المدينين (اختياري)', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.cardTitle(color: AppColors.textHi)),
                Text('بعمر الدين، أو بمبلغه، أو بالاثنين', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
              ]),
            ),
            if (_df.active)
              TextButton(
                onPressed: () {
                  _ageCtrl.clear();
                  _minCtrl.clear();
                  _maxCtrl.clear();
                  setState(() => _customAge = false);
                  _set(DebtFilter.none);
                },
                child: Text('مسح', style: AppType.labelBold(color: AppColors.brand)),
              ),
          ]),
          const SizedBox(height: Sp.md),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: 'عمر الدين ', style: AppType.labelBold(color: AppColors.textBody)),
              TextSpan(text: '(أقدم دين لم يُسدَّد)', style: AppType.micro(color: AppColors.textMid)),
            ]),
          ),
          const SizedBox(height: Sp.sm),
          if (cap.age) ...[
            Wrap(spacing: Sp.x6, runSpacing: Sp.x6, children: [
              ListFilterChip(
                label: 'أيّ عمر',
                tone: ListTone.warning,
                active: _df.minAgeDays == null && !_customAge,
                onTap: () {
                  setState(() => _customAge = false);
                  _set(_df.copyWith(minAgeDays: () => null));
                },
              ),
              for (final d in cap.presets)
                ListFilterChip(
                  key: ValueKey('df-age-$d'),
                  label: arDaysCount(d),
                  tone: ListTone.warning,
                  active: ageIsPreset && _df.minAgeDays == d,
                  onTap: () {
                    setState(() => _customAge = false);
                    _set(_df.copyWith(minAgeDays: () => d));
                  },
                ),
              ListFilterChip(
                label: 'مدّة أخرى',
                tone: ListTone.warning,
                active: _customAge,
                // الصندوق يبدأ بالعمر المطبَّق الآن (شريحةٌ أو ما كُتب قبلها) — لا فارغاً والفلتر بعمرٍ آخر
                onTap: () => setState(() {
                  _customAge = true;
                  _ageCtrl.text = _df.minAgeDays?.toString() ?? '';
                }),
              ),
            ]),
            if (_customAge) ...[
              const SizedBox(height: Sp.sm),
              Row(children: [
                SizedBox(
                  width: 96,
                  height: H.search,
                  child: TextField(
                    key: const ValueKey('df-age-custom'),
                    controller: _ageCtrl,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                    onChanged: (t) => _set(_df.copyWith(minAgeDays: () => int.tryParse(t))),
                    style: AppType.input(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: '45',
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide(color: AppColors.border)),
                    ),
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Text('يوماً فأكثر', style: AppType.body(color: AppColors.textMid)),
              ]),
            ] else if (_df.minAgeDays != null) ...[
              const SizedBox(height: Sp.xs),
              Text('من عمر أقدم دينٍ لم يسدّده ${arDaysCount(_df.minAgeDays!)} فأكثر، ومن عليه «دين قديم»',
                  style: AppType.micro(color: AppColors.textMid)),
            ],
          ] else
            _note(LucideIcons.info, cap.ageNote ?? 'عمر الدين غير متاحٍ لهذه الشركة — حدّد بالمبلغ'),
          const SizedBox(height: Sp.md),
          Text('مبلغ الدين', style: AppType.labelBold(color: AppColors.textBody)),
          const SizedBox(height: Sp.sm),
          // بلا فاصل «إلى» بين الصندوقين: التلميحان «من»/«إلى» يكفيان، والعرض كلّه للرقم (٣٢٠ لا يلتصق «د.ع» به)
          Row(children: [
            _amountBox(_minCtrl, 'من', true),
            const SizedBox(width: Sp.sm),
            _amountBox(_maxCtrl, 'إلى', false),
          ]),
          const SizedBox(height: Sp.sm),
          Wrap(spacing: Sp.x6, runSpacing: Sp.x6, children: [
            for (final r in _ranges)
              ListFilterChip(
                label: r.$1,
                tone: ListTone.warning,
                active: _df.minAmount == r.$2 && _df.maxAmount == r.$3,
                onTap: () => _setRange(r.$2, r.$3),
              ),
          ]),
          if (_df.active) ...[
            const SizedBox(height: Sp.md),
            Container(
              key: const ValueKey('debt-filter-result'),
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(R.md),
                border: Border.all(color: AppColors.border),
              ),
              child: problem != null
                  ? Text(problem, style: AppType.labelBold(color: AppColors.error))
                  : widget.error != null
                      ? Row(children: [
                          Expanded(child: Text(widget.error!, maxLines: 3, style: AppType.micro(color: AppColors.error))),
                          if (widget.onRetry != null)
                            TextButton(onPressed: widget.onRetry, child: Text('إعادة', style: AppType.labelBold(color: AppColors.brand))),
                        ])
                      : widget.busy || pv == null
                          ? Row(key: ValueKey(widget.pendingText != null ? 'debt-filter-pending' : 'debt-filter-busy'), children: [
                              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: Sp.sm),
                              Expanded(
                                child: Text(widget.pendingText ?? 'يحسب من يطابق…', style: AppType.micro(color: AppColors.textMid)),
                              ),
                            ])
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text.rich(TextSpan(children: [
                                TextSpan(text: '${pv.audience}', style: AppType.statValue(color: AppColors.warningOnSoft)),
                                TextSpan(text: ' ${widget.noun} يطابقون', style: AppType.body(color: AppColors.textMid)),
                              ])),
                              if (pv.count != pv.audience || pv.legacy > 0 || pv.unknownAge > 0 || pv.notFound > 0)
                                Text(
                                  [
                                    if (pv.count != pv.audience) 'سيصل ${pv.count}',
                                    if (pv.legacy > 0) '${pv.legacy} دين قديم',
                                    if (pv.unknownAge > 0) '${pv.unknownAge} بلا عمر معروف (لم يُشملوا)',
                                    if (pv.notFound > 0) '${pv.notFound} غير موجودين (لم يُشملوا)',
                                  ].join(' · '),
                                  style: AppType.micro(color: AppColors.textMid),
                                ),
                            ]),
            ),
          ],
        ],
      ),
    );
  }
}
