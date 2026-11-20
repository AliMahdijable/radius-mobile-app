import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/agent_notifs_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// يحفظ جزءاً من الإعداد ⇒ نجح أم لا (الشاشة تقول السبب).
typedef MoneyAlertsPatch = Future<bool> Function(Map<String, Object?> patch);

/// «تنبيهات المال» داخل «إشعاراتي» (٢٠ نوفمبر — المالك: «حد ادنى للشحن · سقف اعلى للديون · تذكير بالمديونين بالأيام وبالمبلغ»
/// و«ننطي صلاحيه هو يحدد واذا اكو تكرار»): ثلاث بطاقات — لكلٍّ زرّ تشغيل، وما يحدّده الوكيل، والتكرار بيده، وسطر الحال الآن.
class MoneyAlertsSection extends StatelessWidget {
  const MoneyAlertsSection({super.key, required this.data, required this.onPatch, this.busy = false});

  final AgentNotifs data;
  final MoneyAlertsPatch onPatch;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final cur = 'common.currency'.tr();
    final b = data.balance;
    final c = data.debtCap;
    final d = data.debtors;
    final low = b.threshold != null && b.now != null && b.now! < b.threshold!;
    final pct = c.percent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AlertCard(
          key: const ValueKey('ma-balance'),
          icon: LucideIcons.wallet,
          title: 'الرصيد',
          hint: 'نبّهني لمّا ينزل رصيد صفحتي تحت مبلغ أحدّده',
          enabled: b.enabled,
          busy: busy,
          onToggle: (v) => onPatch({
            'balance': {'enabled': v}
          }),
          rows: [
            _ValueRow(
              key: const ValueKey('ma-balance-threshold'),
              label: 'الحدّ الأدنى',
              value: b.threshold == null ? 'حدّد المبلغ' : '${formatIQD(b.threshold!)} $cur',
              onTap: () async {
                final v = await showAmountSheet(context,
                    title: 'الحدّ الأدنى للرصيد',
                    icon: LucideIcons.wallet,
                    initial: b.threshold,
                    quick: const [50000, 100000, 250000, 500000]);
                if (v != null) {
                  await onPatch({
                    'balance': {'threshold': v}
                  });
                }
              },
            ),
            _ValueRow(
              key: const ValueKey('ma-balance-repeat'),
              label: 'التكرار',
              value: b.repeat.label,
              onTap: () async {
                final r = await showRepeatSheet(context, initial: b.repeat, what: 'الرصيد تحت الحدّ');
                if (r != null) {
                  await onPatch({
                    'balance': {'repeat': r.toJson()}
                  });
                }
              },
            ),
          ],
          status: b.now == null
              ? _Status(balanceWhy(b), tone: AppTone.neutral, icon: b.pending ? LucideIcons.loader : LucideIcons.circleHelp)
              : _Status(
                  'رصيدك الآن ${formatIQDSigned(b.now!)} $cur${b.daysLeft == null ? '' : ' — يكفي تقريباً ${daysText(b.daysLeft!)}'}',
                  tone: low ? AppTone.warning : AppTone.neutral,
                  icon: low ? LucideIcons.triangleAlert : LucideIcons.info,
                ),
        ),
        const SizedBox(height: Sp.sm),
        _AlertCard(
          key: const ValueKey('ma-debtcap'),
          icon: LucideIcons.trendingUp,
          title: 'سقف الديون',
          hint: 'نبّهني عند 80% من سقف أحدّده وعند تجاوزه',
          enabled: c.enabled,
          busy: busy,
          onToggle: (v) => onPatch({
            'debt_cap': {'enabled': v}
          }),
          rows: [
            _ValueRow(
              key: const ValueKey('ma-debtcap-cap'),
              label: 'السقف',
              value: c.cap == null ? 'حدّد المبلغ' : '${formatIQD(c.cap!)} $cur',
              onTap: () async {
                final v = await showAmountSheet(context,
                    title: 'سقف ديون المشتركين',
                    icon: LucideIcons.trendingUp,
                    initial: c.cap,
                    quick: const [1000000, 2000000, 5000000, 10000000]);
                if (v != null) {
                  await onPatch({
                    'debt_cap': {'cap': v}
                  });
                }
              },
            ),
            _ValueRow(
              key: const ValueKey('ma-debtcap-repeat'),
              label: 'التكرار',
              value: c.repeat.label,
              onTap: () async {
                final r = await showRepeatSheet(context, initial: c.repeat, what: 'الديون فوق السقف');
                if (r != null) {
                  await onPatch({
                    'debt_cap': {'repeat': r.toJson()}
                  });
                }
              },
            ),
          ],
          extra: pct == null ? null : _CapMeter(percent: pct),
          status: c.now == null
              ? _Status(debtsWhy(c.pending, c.reason), tone: AppTone.neutral, icon: c.pending ? LucideIcons.loader : LucideIcons.circleHelp)
              : _Status(
                  'ديون مشتركيك الآن ${formatIQD(c.now!)} $cur${pct == null ? '' : ' — $pct% من السقف'}',
                  tone: pct != null && pct >= 80 ? AppTone.warning : AppTone.neutral,
                  icon: pct != null && pct >= 80 ? LucideIcons.triangleAlert : LucideIcons.info,
                ),
        ),
        const SizedBox(height: Sp.sm),
        _AlertCard(
          key: const ValueKey('ma-debtors'),
          icon: LucideIcons.listChecks,
          title: 'ملخّص المديونين',
          hint: 'قائمة المديونين حسب عمر الدين أو المبلغ',
          enabled: d.enabled,
          busy: busy,
          onToggle: (v) => onPatch({
            'debtors': {'enabled': v}
          }),
          rows: [
            _ValueRow(
              key: const ValueKey('ma-debtors-age'),
              label: 'عمر الدين',
              value: d.minDays == null ? 'أي عمر' : 'أقدم من ${daysText(d.minDays!)}',
              onTap: () => _editFilter(context, d),
            ),
            _ValueRow(
              key: const ValueKey('ma-debtors-amount'),
              label: 'المبلغ',
              value: amountRangeText(d.minAmount, d.maxAmount, cur),
              onTap: () => _editFilter(context, d),
            ),
            _ValueRow(
              key: const ValueKey('ma-debtors-schedule'),
              label: 'الموعد',
              value: d.schedule.label,
              onTap: () async {
                final s = await showDigestSheet(context, initial: d.schedule);
                if (s != null) {
                  await onPatch({
                    'debtors': {'schedule': s.toJson()}
                  });
                }
              },
            ),
          ],
          status: d.matchCount == null
              ? (d.pending || d.reason != null
                  ? _Status(d.pending ? 'جارٍ عدّ من يطابق…' : debtsWhy(false, d.reason),
                      tone: AppTone.neutral, icon: d.pending ? LucideIcons.loader : LucideIcons.circleHelp)
                  : null)
              : _Status(
                  d.matchCount == 0
                      ? 'ماكو أحد يطابق الآن — ما يوصلك ملخّص فارغ'
                      : 'يطابق الآن ${d.matchCount} مديون — ${formatIQD(d.matchTotal ?? 0)} $cur',
                  tone: AppTone.neutral,
                  icon: LucideIcons.users,
                ),
        ),
        if (data.recent.isNotEmpty) ...[
          const SizedBox(height: Sp.md),
          _RecentAlerts(lines: data.recent.take(3).toList()),
        ],
      ],
    );
  }

  Future<void> _editFilter(BuildContext context, DebtorsDigest d) async {
    final f = await showDebtorsFilterSheet(context, minDays: d.minDays, minAmount: d.minAmount, maxAmount: d.maxAmount);
    if (f == null) return;
    await onPatch({
      'debtors': {'min_days': f.minDays, 'min_amount': f.minAmount, 'max_amount': f.maxAmount}
    });
  }
}

/// لماذا لا رقم للرصيد الآن — جارٍ، أو سببٌ يفهمه الوكيل (لا «تعذّر» واحدة لكلّ شيء).
String balanceWhy(BalanceAlert b) {
  if (b.pending) return 'جارٍ قراءة رصيدك…';
  return switch (b.reason) {
    'no_wallet' => 'هذه الشركة ما تعطي رصيد صفحة يُقرأ — تنبيه الرصيد غير متاح لها',
    'no_session' => 'جلسة الشركة منتهية — ادخل شركتك من جديد حتى نقرأ رصيدك',
    _ => 'تعذّرت قراءة رصيدك الآن',
  };
}

/// لماذا لا رقم للديون / للملخّص الآن.
String debtsWhy(bool pending, String? reason) {
  if (pending) return 'جارٍ حساب ديون مشتركيك…';
  return switch (reason) {
    'no_token' || 'no_session' => 'لا جلسة محفوظة لهذه الشركة — ادخل شركتك من جديد حتى نقرأ ديون مشتركيك',
    'no_age' => 'هذه الشركة بلا أعمارٍ لديونها — حدّد الملخّص بالمبلغ',
    'age_unavailable' => 'تعذّرت قراءة أعمار الديون الآن',
    _ => 'تعذّر حساب ديون مشتركيك الآن',
  };
}

/// «يوم واحد» · «يومين» · «4 أيام» · «30 يوم».
String daysText(int n) {
  if (n == 1) return 'يوم واحد';
  if (n == 2) return 'يومين';
  return '$n ${n >= 3 && n <= 10 ? 'أيام' : 'يوم'}';
}

/// «أي مبلغ» · «أكبر من 25,000 د.ع» · «أقلّ من 100,000 د.ع» · «من 25,000 إلى 100,000 د.ع».
String amountRangeText(num? min, num? max, String cur) {
  if (min == null && max == null) return 'أي مبلغ';
  if (max == null) return 'أكبر من ${formatIQD(min!)} $cur';
  if (min == null) return 'أقلّ من ${formatIQD(max)} $cur';
  return 'من ${formatIQD(min)} إلى ${formatIQD(max)} $cur';
}

// ═══════════════════════════ البطاقة ═══════════════════════════

class _Status {
  const _Status(this.text, {required this.tone, required this.icon});
  final String text;
  final AppTone tone;
  final IconData icon;
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.enabled,
    required this.onToggle,
    required this.rows,
    this.status,
    this.extra,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String hint;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final List<Widget> rows;
  final _Status? status;
  final Widget? extra;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: enabled ? AppColors.brandSoftBorder : AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: enabled ? AppColors.brandSoftBg : AppColors.surfaceInput,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: enabled ? AppColors.brand : AppColors.textLow),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: Sp.xxs),
                    Text(hint, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.4)),
                  ],
                ),
              ),
              Switch.adaptive(value: enabled, onChanged: busy ? null : onToggle),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: Sp.sm),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: AppColors.divider),
              rows[i],
            ],
            if (extra != null) ...[const SizedBox(height: Sp.sm), extra!],
            if (status != null) ...[
              const SizedBox(height: Sp.sm),
              _StatusLine(status: status!),
            ],
          ],
        ],
      ),
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({super.key, required this.label, required this.value, required this.onTap});
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        child: Row(
          children: [
            Text(label, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceInput,
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700, fontSize: 13),
                          maxLines: 2,
                          textAlign: TextAlign.end,
                        ),
                      ),
                      const SizedBox(width: Sp.xs),
                      Icon(LucideIcons.chevronDown, size: 14, color: AppColors.textLow),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});
  final _Status status;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final warn = status.tone == AppTone.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.x6),
      decoration: BoxDecoration(
        color: warn ? AppColors.warningSoftBg : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: Sp.xxs),
            child: Icon(status.icon, size: 14, color: warn ? AppColors.warningOnSoft : AppColors.textMid),
          ),
          const SizedBox(width: Sp.x6),
          Expanded(
            child: Text(
              status.text,
              style: AppType.muted(color: warn ? AppColors.warningOnSoft : AppColors.textMid).copyWith(fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

/// شريط نسبة الديون من السقف — علامتا ٨٠٪ و١٠٠٪.
class _CapMeter extends StatelessWidget {
  const _CapMeter({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final p = (percent.clamp(0, 100)) / 100;
    final color = percent >= 100 ? AppColors.error : (percent >= 80 ? AppColors.warning : AppColors.brand);
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          height: 10,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(color: AppColors.surfaceInput, borderRadius: BorderRadius.circular(R.pill)),
              ),
              FractionallySizedBox(
                widthFactor: p.toDouble(),
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  key: const ValueKey('ma-cap-fill'),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(R.pill)),
                ),
              ),
              PositionedDirectional(
                start: box.maxWidth * 0.8 - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: AppColors.surface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentAlerts extends StatelessWidget {
  const _RecentAlerts({required this.lines});
  final List<AgentNotifLine> lines;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      key: const ValueKey('ma-recent'),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('آخر التنبيهات', style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, fontWeight: FontWeight.w700)),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    switch (l.kind) {
                      'balance' => LucideIcons.wallet,
                      'debt_cap' => LucideIcons.trendingUp,
                      _ => LucideIcons.listChecks,
                    },
                    size: 15,
                    color: AppColors.textMid,
                  ),
                  const SizedBox(width: Sp.sm),
                  // الوقت سطرٌ تحت العنوان لا ثابتٌ بجانبه — العنوان الطويل يلتفّ ولا يُسحق.
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.title, style: AppType.body(color: AppColors.textHi).copyWith(fontSize: 12.5, height: 1.45)),
                        Text(alertTimeText(l.at), style: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// «اليوم 09:00» · «أمس 21:30» · «2026/11/18» (أرقام التواريخ كما يريدها المالك).
String alertTimeText(DateTime at, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final hm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  final d0 = DateTime(n.year, n.month, n.day);
  final d = DateTime(at.year, at.month, at.day);
  final diff = d0.difference(d).inDays;
  if (diff == 0) return 'اليوم $hm';
  if (diff == 1) return 'أمس $hm';
  return '${at.year}/${at.month.toString().padLeft(2, '0')}/${at.day.toString().padLeft(2, '0')}';
}

// ═══════════════════════════ نوافذ التعديل ═══════════════════════════

Future<TimeOfDay?> _pickTime(BuildContext context, String hm) {
  final parts = hm.split(':');
  return showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}

String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// أرقامٌ لاتينيّة ويُفصل كلّ ثلاثة بفاصلة أثناء الكتابة.
class _GroupedDigits extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final raw = newValue.text
        .split('')
        .map((ch) {
          final i = ar.indexOf(ch);
          return i >= 0 ? '$i' : ch;
        })
        .join()
        .replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.isEmpty) return const TextEditingValue();
    final txt = formatIQD(int.parse(raw.length > 12 ? raw.substring(0, 12) : raw));
    return TextEditingValue(text: txt, selection: TextSelection.collapsed(offset: txt.length));
  }
}

num? _parseAmount(String s) {
  final d = s.replaceAll(RegExp(r'[^0-9]'), '');
  return d.isEmpty ? null : num.parse(d);
}

/// مبلغٌ بالدينار ⇒ القيمة (موجبة) أو null إن أُغلقت.
Future<num?> showAmountSheet(BuildContext context,
    {required String title, required IconData icon, num? initial, List<num> quick = const []}) {
  return showAppSheet<num>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AmountSheet(title: title, icon: icon, initial: initial, quick: quick),
  );
}

class _AmountSheet extends StatefulWidget {
  const _AmountSheet({required this.title, required this.icon, this.initial, this.quick = const []});
  final String title;
  final IconData icon;
  final num? initial;
  final List<num> quick;

  @override
  State<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends State<_AmountSheet> {
  late final TextEditingController _c = TextEditingController(text: widget.initial == null ? '' : formatIQD(widget.initial!));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  num? get _value => _parseAmount(_c.text);

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final v = _value;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: widget.icon,
        title: widget.title,
        subtitle: 'المبلغ بالدينار',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'حفظ',
        icon: LucideIcons.check,
        enabled: v != null && v > 0,
        onPressed: () => Navigator.of(context).pop(v),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('ma-amount-field'),
            controller: _c,
            autofocus: true,
            keyboardType: TextInputType.number,
            textDirection: ui.TextDirection.ltr,
            textAlign: TextAlign.center,
            inputFormatters: [_GroupedDigits()],
            style: AppType.amount(color: AppColors.textHi),
            decoration: InputDecoration(
              suffixText: 'common.currency'.tr(),
              hintText: '0',
              filled: true,
              fillColor: AppColors.surfaceInput,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.lg), borderSide: BorderSide.none),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.quick.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [
                for (final q in widget.quick)
                  SheetQuickChip(
                    label: formatIQD(q),
                    selected: v == q,
                    onTap: () => setState(() => _c.text = formatIQD(q)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// «التكرار» — مرّة وحدة · كل ساعتين · كل 6 ساعات · كل يوم بساعة يختارها.
Future<AlertRepeat?> showRepeatSheet(BuildContext context, {required AlertRepeat initial, required String what}) {
  return showAppSheet<AlertRepeat>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RepeatSheet(initial: initial, what: what),
  );
}

class _RepeatSheet extends StatefulWidget {
  const _RepeatSheet({required this.initial, required this.what});
  final AlertRepeat initial;
  final String what;

  @override
  State<_RepeatSheet> createState() => _RepeatSheetState();
}

class _RepeatSheetState extends State<_RepeatSheet> {
  late AlertRepeat _v = widget.initial;
  late String _at = widget.initial.at ?? '09:00';

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final options = <(AlertRepeat, String, String)>[
      (const AlertRepeat.once(), 'مرّة وحدة', 'يوصلك مرّة لمّا يصير، وما يرجع إلا إذا انحلّ ورجع صار'),
      (const AlertRepeat.everyHours(2), 'كل ساعتين', 'ما دام ${widget.what}'),
      (const AlertRepeat.everyHours(6), 'كل 6 ساعات', 'ما دام ${widget.what}'),
      (AlertRepeat.daily(_at), 'كل يوم', 'مرّة باليوم بالساعة اللي تختارها، ما دام ${widget.what}'),
    ];
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.repeat,
        title: 'التكرار',
        subtitle: 'كل شكد يرجع يذكّرك',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'حفظ',
        icon: LucideIcons.check,
        onPressed: () => Navigator.of(context).pop(_v.mode == AlertRepeatMode.daily ? AlertRepeat.daily(_at) : _v),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (value, title, sub) in options)
            _Choice(
              key: ValueKey('ma-repeat-${value.mode.name}${value.hours ?? ''}'),
              title: title,
              sub: sub,
              selected: _v.mode == value.mode && (value.mode != AlertRepeatMode.everyHours || _v.hours == value.hours),
              trailing: value.mode == AlertRepeatMode.daily
                  ? _TimeChip(
                      value: _at,
                      onTap: () async {
                        final t = await _pickTime(context, _at);
                        if (t != null) setState(() => _at = _hm(t));
                      })
                  : null,
              onTap: () => setState(() => _v = value),
            ),
          const SizedBox(height: Sp.sm),
          Text(
            'أقرب تكرار كل ساعتين، والتنبيه بأوقات السكون يتأجّل لنهايتها.',
            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({super.key, required this.title, required this.sub, required this.selected, required this.onTap, this.trailing});
  final String title;
  final String sub;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: selected ? AppColors.brandSoftBg : AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: selected ? AppColors.brandSoftBorder : AppColors.border),
            ),
            child: Row(
              children: [
                Icon(selected ? LucideIcons.circleCheck : LucideIcons.circle,
                    size: 18, color: selected ? AppColors.brand : AppColors.textHint),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: Sp.xxs),
                      Text(sub, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.4)),
                    ],
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: Sp.sm), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.value, required this.onTap});
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.x6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.clock, size: 14, color: AppColors.brand),
              const SizedBox(width: Sp.xs),
              Text(value,
                  textDirection: ui.TextDirection.ltr, style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// تحديد المديونين: عمر الدين (أيّام) و/أو مبلغه.
Future<({int? minDays, num? minAmount, num? maxAmount})?> showDebtorsFilterSheet(BuildContext context,
    {int? minDays, num? minAmount, num? maxAmount}) {
  return showAppSheet<({int? minDays, num? minAmount, num? maxAmount})>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FilterSheet(minDays: minDays, minAmount: minAmount, maxAmount: maxAmount),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({this.minDays, this.minAmount, this.maxAmount});
  final int? minDays;
  final num? minAmount;
  final num? maxAmount;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final _days = TextEditingController(text: widget.minDays?.toString() ?? '');
  late final _min = TextEditingController(text: widget.minAmount == null ? '' : formatIQD(widget.minAmount!));
  late final _max = TextEditingController(text: widget.maxAmount == null ? '' : formatIQD(widget.maxAmount!));

  @override
  void dispose() {
    _days.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  int? get _d => int.tryParse(_days.text.replaceAll(RegExp(r'[^0-9]'), ''));
  num? get _lo => _parseAmount(_min.text);
  num? get _hi => _parseAmount(_max.text);
  bool get _bad => (_lo != null && _hi != null && _lo! > _hi!) || (_d != null && (_d! < 1 || _d! > 365));

  /// خانة رقمٍ بلا عنوانٍ عائم (كان يتراكب على عنوان القسم) — الفارغة تقول معناها ([hint]).
  Widget _field(TextEditingController c, String hint, {bool money = true, Key? key}) => TextField(
        key: key,
        controller: c,
        keyboardType: TextInputType.number,
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
        inputFormatters: money ? [_GroupedDigits()] : [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppType.muted(color: AppColors.textLow).copyWith(fontSize: 13),
          hintTextDirection: ui.TextDirection.rtl,
          filled: true,
          fillColor: AppColors.surfaceInput,
          contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(R.md), borderSide: BorderSide.none),
        ),
        onChanged: (_) => setState(() {}),
      );

  /// عنوانٌ صغير فوق خانة.
  Widget _labeled(String label, Widget field) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
            child: Text(label, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          field,
        ],
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.listFilter,
        title: 'أي مديونين؟',
        subtitle: 'اترك الخانة فارغة إذا ما تريدها',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'حفظ',
        icon: LucideIcons.check,
        enabled: !_bad,
        onPressed: () => Navigator.of(context).pop((minDays: _d, minAmount: _lo, maxAmount: _hi)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSection(
            label: 'عمر الدين — أقدم من كم يوم',
            child: _field(_days, 'أي عمر', money: false, key: const ValueKey('ma-filter-days')),
          ),
          const SizedBox(height: Sp.md),
          SheetSection(
            label: 'المبلغ (بالدينار)',
            footnote: 'من وحدها = أكبر من · إلى وحدها = أقلّ من',
            child: Row(
              children: [
                Expanded(child: _labeled('من', _field(_min, 'أي مبلغ', key: const ValueKey('ma-filter-min')))),
                const SizedBox(width: Sp.sm),
                Expanded(child: _labeled('إلى', _field(_max, 'بلا حدّ', key: const ValueKey('ma-filter-max')))),
              ],
            ),
          ),
          if (_bad) ...[
            const SizedBox(height: Sp.sm),
            Text('«من» أكبر من «إلى» أو الأيام خارج 1–365', style: AppType.muted(color: AppColors.error).copyWith(fontSize: 12.5)),
          ],
        ],
      ),
    );
  }
}

/// موعد ملخّص المديونين: كل يوم · كل أسبوع بيوم · كل كم يوم — بساعة.
Future<DigestSchedule?> showDigestSheet(BuildContext context, {required DigestSchedule initial}) {
  return showAppSheet<DigestSchedule>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DigestSheet(initial: initial),
  );
}

class _DigestSheet extends StatefulWidget {
  const _DigestSheet({required this.initial});
  final DigestSchedule initial;

  @override
  State<_DigestSheet> createState() => _DigestSheetState();
}

class _DigestSheetState extends State<_DigestSheet> {
  late DigestSchedule _v = widget.initial;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const modes = [DigestMode.daily, DigestMode.weekly, DigestMode.everyDays];
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.calendarClock,
        title: 'موعد الملخّص',
        subtitle: _v.label,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: 'حفظ',
        icon: LucideIcons.check,
        onPressed: () => Navigator.of(context).pop(_v),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetSegmented(
            labels: const ['كل يوم', 'كل أسبوع', 'كل كم يوم'],
            selectedIndex: modes.indexOf(_v.mode),
            onSelect: (i) => setState(() => _v = _v.copyWith(mode: modes[i])),
          ),
          if (_v.mode == DigestMode.weekly) ...[
            const SizedBox(height: Sp.md),
            SheetSection(
              label: 'اليوم',
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final e in DigestSchedule.weekdays.entries)
                    SheetQuickChip(
                      label: e.value,
                      selected: _v.weekday == e.key,
                      onTap: () => setState(() => _v = _v.copyWith(weekday: e.key)),
                    ),
                ],
              ),
            ),
          ],
          if (_v.mode == DigestMode.everyDays) ...[
            const SizedBox(height: Sp.md),
            SheetSection(
              label: 'كل كم يوم',
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final n in const [2, 3, 5, 7, 10, 15, 30])
                    SheetQuickChip(
                      label: daysText(n),
                      selected: _v.days == n,
                      onTap: () => setState(() => _v = _v.copyWith(days: n)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Sp.md),
          SheetSection(
            label: 'الساعة',
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _TimeChip(
                value: _v.at,
                onTap: () async {
                  final t = await _pickTime(context, _v.at);
                  if (t != null) setState(() => _v = _v.copyWith(at: _hm(t)));
                },
              ),
            ),
          ),
          const SizedBox(height: Sp.sm),
          Text('إذا ماكو أحد يطابق بالموعد، ما يوصلك شي.',
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.5)),
        ],
      ),
    );
  }
}
