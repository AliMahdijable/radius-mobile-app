import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:printing/printing.dart';

import '../../api/receipt_settings_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/print_feedback.dart';
import '../../services/print_output.dart';
import '../../services/print_prefs.dart';
import '../../services/receipt_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «الطباعة المباشرة» على الحاسبة: تختار طابعة الوصولات مرّةً فيخرج كلّ وصلٍ عليها فوراً بلا نافذة
/// طباعة (المالك ٢٤ أكتوبر: «زر طباعه مباشر ماكو»). «نافذة الطباعة كلّ مرّة» = ما كان.
Future<void> showDirectPrinterSheet(BuildContext context) => showAppSheet<void>(
      context: context,
      barrierColor: AppColors.scrim,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const DirectPrinterSheet(),
    );

class DirectPrinterSheet extends StatefulWidget {
  const DirectPrinterSheet({super.key});

  @override
  State<DirectPrinterSheet> createState() => _DirectPrinterSheetState();
}

class _DirectPrinterSheetState extends State<DirectPrinterSheet> {
  List<Printer>? _printers;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // الافتراضيّة أوّلاً ثمّ بالاسم.
    final list = [...await PrintOutput.printers()]..sort((a, b) => a.isDefault == b.isDefault
        ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
        : (a.isDefault ? -1 : 1));
    if (mounted) setState(() => _printers = list);
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final r = await ReceiptService.printSample(await ReceiptSettingsApi.fetch());
    if (!mounted) return;
    setState(() => _testing = false);
    showPrintResult(context, r);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final printers = _printers;
    return Material(
      color: AppColors.surfaceSheet,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(R.sheet)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.lg),
          child: ValueListenableBuilder<SavedPrinter?>(
            valueListenable: PrintPrefs.printer,
            builder: (_, current, __) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'printer.direct_title'.tr(),
                  textAlign: TextAlign.center,
                  style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 17),
                ),
                const SizedBox(height: 4),
                Text(
                  'printer.direct_desc'.tr(),
                  textAlign: TextAlign.center,
                  style: AppType.subtitle(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: Sp.lg),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PrinterTile(
                          icon: LucideIcons.appWindow,
                          label: 'printer.ask'.tr(),
                          subtitle: 'printer.ask_desc'.tr(),
                          selected: current == null,
                          onTap: () => PrintPrefs.setPrinter(null),
                        ),
                        if (printers == null) ...[
                          const SizedBox(height: Sp.md),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                              const SizedBox(width: Sp.sm),
                              Text('printer.loading'.tr(),
                                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
                            ],
                          ),
                        ] else if (printers.isEmpty) ...[
                          const SizedBox(height: Sp.md),
                          Text(
                            'printer.none'.tr(),
                            textAlign: TextAlign.center,
                            style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5, height: 1.5),
                          ),
                        ] else
                          for (final p in printers) ...[
                            const SizedBox(height: Sp.xs),
                            _PrinterTile(
                              icon: LucideIcons.printer,
                              label: p.name,
                              subtitle: [
                                if (p.isDefault) 'printer.default_tag'.tr(),
                                if (!p.isAvailable) 'printer.unavailable'.tr(),
                                if ((p.model ?? '').trim().isNotEmpty && p.model != p.name) p.model!.trim(),
                              ].join(' · '),
                              selected: current?.url == p.url,
                              onTap: () => PrintPrefs.setPrinter(SavedPrinter(url: p.url, name: p.name)),
                            ),
                          ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Sp.lg),
                OutlinedButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(LucideIcons.receipt, size: 16),
                  label: Text('printer.test'.tr()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brand,
                    side: BorderSide(color: AppColors.brandSoftBorder),
                    padding: const EdgeInsets.symmetric(vertical: Sp.md),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// خيارٌ بشكل خيارات «الطابعة الافتراضية» (الإعدادات).
class _PrinterTile extends StatelessWidget {
  const _PrinterTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: selected ? AppColors.brandSoftBg : AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
          decoration: BoxDecoration(
            border: Border.all(color: selected ? AppColors.brand : Colors.transparent, width: 1.4),
            borderRadius: BorderRadius.circular(R.md),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (selected ? AppColors.brand : AppColors.textMid).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 18, color: selected ? AppColors.brand : AppColors.textMid),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.label(color: AppColors.textHi).copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitle, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11)),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? AppColors.brand : AppColors.textLow,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
