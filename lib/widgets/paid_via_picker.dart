import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/widgets/design_sheet.dart';
import '../services/transfer_pay.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// «استلمته» — كاش (الافتراضيّ) · زين كاش · ماستر · أخرى باسمها (٢٣ نوفمبر — «الحوالات»). شرائح صغيرة لا بلاطات (المالك:
/// «لا تخليها شكل كبير… حتى تكون انسب»)، وتحتها سطرٌ واحد بما يحدث للمبلغ: الكاش يدخل الصندوق، والحوالة رصيد طريقتها حتى تسحبه.
class PaidViaPicker extends StatefulWidget {
  const PaidViaPicker({super.key, required this.value, required this.onChanged, this.enabled = true, this.label = 'استلمته'});

  final PaidVia value;
  final ValueChanged<PaidVia> onChanged;
  final bool enabled;
  final String label;

  @override
  State<PaidViaPicker> createState() => _PaidViaPickerState();
}

class _PaidViaPickerState extends State<PaidViaPicker> {
  late final TextEditingController _other = TextEditingController(text: widget.value.key == 'other' ? widget.value.name : '');

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _pick(String key) {
    if (!widget.enabled) return;
    widget.onChanged(key == 'other' ? PaidVia('other', _other.text) : PaidVia(key));
  }

  /// ما يحدث للمبلغ بهذه الطريقة — سطرٌ واحد.
  static String noteOf(PaidVia v) => v.isCash
      ? 'يدخل الصندوق.'
      : v.valid
          ? 'يُحسب على رصيد «${v.label}» — لا يدخل الصندوق حتى تسحبه.'
          : 'اكتب اسم الطريقة.';

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final v = widget.value;
    Widget chip(String key, String label, IconData icon) => SheetQuickChip(
          key: ValueKey('paid-via-$key'),
          label: label,
          icon: icon,
          selected: v.key == key,
          enabled: widget.enabled,
          onTap: () => _pick(key),
        );
    return Column(
      key: const ValueKey('paid-via-picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: AppType.label(color: AppColors.textMid).copyWith(fontSize: 12.5)),
        const SizedBox(height: Sp.x6),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            chip('cash', 'كاش', LucideIcons.banknote),
            chip('zaincash', 'زين كاش', LucideIcons.smartphone),
            chip('master', 'ماستر', LucideIcons.landmark),
            chip('other', 'أخرى', LucideIcons.plus),
          ],
        ),
        if (v.key == 'other') ...[
          const SizedBox(height: Sp.sm),
          SheetBox(
            icon: LucideIcons.pencil,
            child: TextField(
              key: const ValueKey('paid-via-other-name'),
              controller: _other,
              enabled: widget.enabled,
              maxLength: 40,
              style: AppType.input(),
              onChanged: (t) => widget.onChanged(PaidVia('other', t)),
              decoration: InputDecoration(
                isDense: true,
                counterText: '',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'اسم الطريقة (مثلاً: آسيا حوالة)',
                hintStyle: AppType.input(color: AppColors.textPlaceholder),
              ),
            ),
          ),
          ValueListenableBuilder<List<String>>(
            valueListenable: TransferPay.recentOthers,
            builder: (context, recent, _) => recent.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: Sp.x6),
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        for (final n in recent.take(4))
                          SheetQuickChip(
                            label: n,
                            icon: LucideIcons.history,
                            selected: v.name?.trim() == n,
                            enabled: widget.enabled,
                            onTap: () {
                              _other.text = n;
                              widget.onChanged(PaidVia('other', n));
                            },
                          ),
                      ],
                    ),
                  ),
          ),
        ],
        const SizedBox(height: Sp.x6),
        Text(
          noteOf(v),
          key: const ValueKey('paid-via-note'),
          style: AppType.muted(color: v.isCash ? AppColors.textLow : AppColors.brandOnSoft).copyWith(fontSize: 12.5),
        ),
      ],
    );
  }
}
