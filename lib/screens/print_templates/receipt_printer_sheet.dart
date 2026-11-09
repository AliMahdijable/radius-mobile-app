import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/receipt_settings_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/print_feedback.dart';
import '../../services/print_output.dart';
import '../../services/receipt_pdf.dart';
import '../../services/receipt_printer/printer_bridge.dart';
import '../../services/receipt_printer/receipt_printer.dart';
import '../../services/receipt_printer/receipt_printer_prefs.dart';
import '../../services/receipt_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';

/// «طابعة الوصولات» بالهاتف (٩ نوفمبر — المالك: «اندرويد وايفون ماتطبع… اخذ النقوصات وضمنهن»): نافذة الطباعة كما
/// كانت (الافتراضيّ)، أو طابعة كاشير بلوتوث، أو طابعة الجهاز المدمجة (SUNMI) — مع عرض الورق ٥٨/٨٠ و«طباعة تجريبيّة».
Future<void> showReceiptPrinterSheet(BuildContext context) => showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (ctx) => const ReceiptPrinterSheet(),
    );

class ReceiptPrinterSheet extends StatefulWidget {
  const ReceiptPrinterSheet({super.key, this.sampleBuilder});

  /// الوصل التجريبيّ — للاختبار؛ بلاه وصلٌ بتصميم الحساب ([ReceiptService.sampleDoc]).
  final Future<PrintDoc> Function()? sampleBuilder;

  @override
  State<ReceiptPrinterSheet> createState() => _ReceiptPrinterSheetState();
}

class _ReceiptPrinterSheetState extends State<ReceiptPrinterSheet> {
  ReceiptPrinter get _printer => ReceiptPrinter.instance;

  PrinterDiscovery? _found;
  bool _searching = false;
  BuiltinInfo? _builtin;
  Future<BuiltinInfo?>? _builtinCheck;
  bool _builtinChecked = false;
  bool _testing = false;
  PrintResult? _last;

  bool get _checkingBuiltin => _builtinCheck != null;

  @override
  void initState() {
    super.initState();
    final mode = ReceiptPrinterPrefs.mode.value;
    // أندرويد: المقترنة تُقرأ فوراً (الإذن يُطلب الآن إن لم يُمنح)؛ الآيفون يبحث بطلبٍ صريح.
    if (mode == ReceiptPrinterMode.bluetooth && !ReceiptPrinterPrefs.isIos) unawaited(_discover());
    // طابعة الجهاز تُفحص حين تُفتح الورقة (أندرويد): الهاتف العاديّ يرى خيارها معطّلاً بسببه قبل أن ينقره، والمختارة
    // على جهازٍ بلا طابعةٍ مدمجة تعود «نافذة الطباعة». فحصٌ سريع بلا ربط حيث لا خدمة SUNMI.
    if (ReceiptPrinterPrefs.builtinSupported) {
      _builtinCheck = _printer.builtinInfo();
      unawaited(_checkBuiltin());
    }
  }

  Future<void> _setMode(ReceiptPrinterMode m) async {
    if (_testing) return;
    if (m == ReceiptPrinterMode.builtin) return _pickBuiltin();
    await ReceiptPrinterPrefs.setMode(m);
    if (!mounted) return;
    setState(() => _last = null);
    if (m == ReceiptPrinterMode.bluetooth) await _discover();
  }

  /// «طابعة الجهاز المدمجة» تُحفظ بعد أن يقول الفحص إنّ في الجهاز طابعة — هاتفٌ بلا خدمتها لا يحفظها (خيارها
  /// معطّلٌ بسببه)، فلا يصير كلّ وصلٍ «اطبع على طابعة الجهاز» يفشل.
  Future<void> _pickBuiltin() async {
    final info = await _checkBuiltin();
    if (!mounted || _testing || ReceiptPrinterPrefs.builtinPresent.value == false) return;
    await ReceiptPrinterPrefs.setMode(ReceiptPrinterMode.builtin);
    if (!mounted) return;
    setState(() => _last = null);
    // ورق طابعة الجهاز كما تقوله هي — حين تُختار، لا كلّما فُتحت الورقة (اختيار المدير يبقى).
    if (info != null && info.available && (info.paperMm == 58 || info.paperMm == 80)) {
      await ReceiptPrinterPrefs.setPaper(info.paperMm == 80 ? ReceiptPaper.mm80 : ReceiptPaper.mm58);
    }
  }

  Future<void> _discover() async {
    if (_searching) return;
    setState(() => _searching = true);
    final r = await _printer.discover();
    if (!mounted) return;
    setState(() {
      _found = r;
      _searching = false;
    });
  }

  /// فحص طابعة الجهاز — فحصٌ واحدٌ في كلّ مرّة (نقرةٌ أثناء فحص الفتح تنتظره لا تبدأ غيره).
  Future<BuiltinInfo?> _checkBuiltin() async {
    var check = _builtinCheck;
    if (check == null) {
      check = _printer.builtinInfo();
      setState(() {
        _builtinCheck = check;
      });
    }
    final info = await check;
    if (!mounted) return info;
    setState(() {
      if (identical(_builtinCheck, check)) _builtinCheck = null;
      _builtin = info;
      _builtinChecked = true;
    });
    return info;
  }

  void _pick(BtDevice d) {
    if (d.leOnly) return;
    unawaited(ReceiptPrinterPrefs.setDevice(
      SavedReceiptPrinter(id: d.id, name: d.name.isEmpty ? d.id : d.name, ble: ReceiptPrinterPrefs.isIos),
    ));
    setState(() => _last = null);
  }

  static Future<PrintDoc> _sample() async {
    final settings = await ReceiptSettingsApi.fetch().timeout(const Duration(seconds: 8), onTimeout: () => null);
    return ReceiptPdf.build(await ReceiptService.sampleDoc(settings), a4: false);
  }

  Future<void> _test() async {
    if (_testing || !ReceiptPrinterPrefs.enabled) return;
    setState(() {
      _testing = true;
      _last = null;
    });
    PrintResult r;
    try {
      final doc = await (widget.sampleBuilder ?? _sample)();
      r = await _printer.send(doc, force: true, quiet: true);
    } catch (e) {
      r = PrintResult.failed('sample: $e', issue: PrintIssue.render);
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _last = r;
    });
  }

  Future<void> _fixIssue(PrintIssue issue) async {
    switch (issue) {
      case PrintIssue.permissionBlocked:
        await _printer.openAppSettings();
      case PrintIssue.btOff:
        await _printer.openBluetoothSettings();
      default:
        await _discover();
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return AnimatedBuilder(
      animation: ReceiptPrinterPrefs.changes,
      builder: (context, _) {
        final mode = ReceiptPrinterPrefs.mode.value;
        return DesignSheet(
          header: SheetHeaderBar(
            icon: LucideIcons.printer,
            title: 'receipt_printer.title'.tr(),
            subtitle: 'receipt_printer.subtitle'.tr(),
            onClose: () => Navigator.of(context).pop(),
          ),
          footer: mode == ReceiptPrinterMode.system
              ? null
              : SheetFooterBar(
                  key: const ValueKey('receipt-printer-test'),
                  label: 'receipt_printer.test'.tr(),
                  icon: LucideIcons.receipt,
                  busy: _testing,
                  enabled: ReceiptPrinterPrefs.enabled,
                  onPressed: _test,
                ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetSection(
                label: 'receipt_printer.mode_label'.tr(),
                child: Column(
                  children: [
                    _Tile(
                      key: const ValueKey('receipt-mode-system'),
                      icon: LucideIcons.appWindow,
                      title: 'receipt_printer.mode_system'.tr(),
                      subtitle: 'receipt_printer.mode_system_desc'.tr(),
                      selected: mode == ReceiptPrinterMode.system,
                      onTap: () => _setMode(ReceiptPrinterMode.system),
                    ),
                    const SizedBox(height: Sp.xs),
                    _Tile(
                      key: const ValueKey('receipt-mode-bluetooth'),
                      icon: LucideIcons.bluetooth,
                      title: 'receipt_printer.mode_bluetooth'.tr(),
                      subtitle: ReceiptPrinterPrefs.isIos
                          ? 'receipt_printer.mode_bluetooth_desc_ios'.tr()
                          : 'receipt_printer.mode_bluetooth_desc'.tr(),
                      selected: mode == ReceiptPrinterMode.bluetooth,
                      onTap: () => _setMode(ReceiptPrinterMode.bluetooth),
                    ),
                    if (ReceiptPrinterPrefs.builtinSupported) ...[
                      const SizedBox(height: Sp.xs),
                      _builtinTile(mode),
                    ],
                  ],
                ),
              ),
              if (mode == ReceiptPrinterMode.bluetooth) ...[
                const SizedBox(height: Sp.lg),
                _bluetoothSection(),
              ],
              if (mode == ReceiptPrinterMode.builtin) ...[
                const SizedBox(height: Sp.lg),
                _builtinSection(),
              ],
              if (mode != ReceiptPrinterMode.system) ...[
                const SizedBox(height: Sp.lg),
                SheetSection(
                  label: 'receipt_printer.paper_label'.tr(),
                  footnote: 'receipt_printer.paper_hint'.tr(),
                  child: SheetSegmented(
                    labels: ['receipt_printer.paper_58'.tr(), 'receipt_printer.paper_80'.tr()],
                    selectedIndex: ReceiptPrinterPrefs.paper.value == ReceiptPaper.mm80 ? 1 : 0,
                    onSelect: (i) {
                      unawaited(ReceiptPrinterPrefs.setPaper(i == 1 ? ReceiptPaper.mm80 : ReceiptPaper.mm58));
                      setState(() => _last = null);
                    },
                  ),
                ),
                const SizedBox(height: Sp.md),
                _jobLine(),
                _resultBanner(),
                const SizedBox(height: Sp.sm),
                Text(
                  'receipt_printer.image_note'.tr(),
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// «طابعة الجهاز المدمجة»: هاتفٌ بلا خدمة طابعةٍ مدمجة يراها **معطّلةً بسببها** (لا تُختار)؛ وأثناء الفحص
  /// «جاري الفحص».
  Widget _builtinTile(ReceiptPrinterMode mode) {
    final absent = ReceiptPrinterPrefs.builtinPresent.value == false;
    final selected = mode == ReceiptPrinterMode.builtin;
    return _Tile(
      key: const ValueKey('receipt-mode-builtin'),
      icon: LucideIcons.tabletSmartphone,
      title: 'receipt_printer.mode_builtin'.tr(),
      subtitle: absent
          ? 'receipt_printer.issue_builtin_missing'.tr()
          : (_checkingBuiltin && !selected
              ? 'receipt_printer.checking_builtin'.tr()
              : 'receipt_printer.mode_builtin_desc'.tr()),
      selected: selected && !absent,
      enabled: !absent,
      onTap: () => _setMode(ReceiptPrinterMode.builtin),
    );
  }

  Widget _bluetoothSection() {
    final saved = ReceiptPrinterPrefs.device.value;
    final found = _found;
    final ios = ReceiptPrinterPrefs.isIos;
    final children = <Widget>[];
    if (_searching) {
      children.add(_Waiting(ios ? 'receipt_printer.scanning'.tr() : 'receipt_printer.loading_paired'.tr()));
    } else if (found?.issue != null) {
      final issue = found!.issue!;
      children.add(_Banner(
        key: const ValueKey('receipt-printer-issue'),
        tone: AppTone.warning,
        icon: issue == PrintIssue.btOff ? LucideIcons.bluetoothOff : LucideIcons.circleAlert,
        text: receiptPrinterIssueText(issue, saved?.name ?? ''),
        action: switch (issue) {
          PrintIssue.permissionBlocked => 'receipt_printer.open_settings'.tr(),
          PrintIssue.btOff => ios ? 'receipt_printer.retry_search'.tr() : 'receipt_printer.bt_settings'.tr(),
          PrintIssue.btUnsupported => null,
          _ => 'receipt_printer.retry_search'.tr(),
        },
        onAction: () => _fixIssue(ios && issue == PrintIssue.btOff ? PrintIssue.unknown : issue),
      ));
    }
    final devices = found?.devices ?? const <BtDevice>[];
    // المحفوظة أوّلاً ولو لم تظهر في البحث (الآيفون بلا بحثٍ بعد، أو الطابعة مطفأة الآن).
    if (saved != null && !devices.any((d) => d.id == saved.id)) {
      children.add(_Tile(
        key: ValueKey('receipt-device-${saved.id}'),
        icon: LucideIcons.printer,
        title: saved.name,
        subtitle: 'receipt_printer.saved_device'.tr(),
        selected: true,
        onTap: () {},
      ));
    }
    for (final d in devices) {
      if (children.isNotEmpty) children.add(const SizedBox(height: Sp.xs));
      children.add(_Tile(
        key: ValueKey('receipt-device-${d.id}'),
        icon: d.printer ? LucideIcons.printer : LucideIcons.bluetooth,
        title: d.name.isEmpty ? d.id : d.name,
        subtitle: d.leOnly
            ? 'receipt_printer.le_only'.tr()
            : [if (d.printer) 'receipt_printer.printer_tag'.tr(), if (!ios) d.id].join(' · '),
        selected: saved?.id == d.id,
        enabled: !d.leOnly,
        onTap: () => _pick(d),
      ));
    }
    if (!_searching && found != null && found.issue == null && devices.isEmpty) {
      children.add(_Banner(
        key: const ValueKey('receipt-printer-empty'),
        tone: AppTone.info,
        icon: LucideIcons.info,
        text: ios ? 'receipt_printer.none_found_ios'.tr() : 'receipt_printer.none_paired'.tr(),
        action: ios ? null : 'receipt_printer.bt_settings'.tr(),
        onAction: () => _fixIssue(PrintIssue.btOff),
      ));
    }
    children.add(const SizedBox(height: Sp.sm));
    children.add(Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: const ValueKey('receipt-printer-refresh'),
        onPressed: _searching ? null : _discover,
        icon: Icon(ios ? LucideIcons.bluetoothSearching : LucideIcons.refreshCw, size: 16, color: AppColors.brand),
        label: Text(
          ios ? 'receipt_printer.search'.tr() : 'receipt_printer.refresh'.tr(),
          style: AppType.bodyStrong(color: AppColors.brand),
        ),
      ),
    ));
    return SheetSection(label: 'receipt_printer.device_label'.tr(), child: Column(children: children));
  }

  Widget _builtinSection() {
    final info = _builtin;
    final Widget child;
    if (_checkingBuiltin || !_builtinChecked) {
      child = _Waiting('receipt_printer.checking_builtin'.tr());
    } else if (info == null || !info.available) {
      child = _Banner(
        key: const ValueKey('receipt-builtin-missing'),
        tone: AppTone.warning,
        icon: LucideIcons.circleAlert,
        text: '${'receipt_printer.issue_builtin_missing'.tr()}\n${'receipt_printer.builtin_other_hint'.tr()}',
        action: 'receipt_printer.recheck'.tr(),
        onAction: _checkBuiltin,
      );
    } else {
      final issue = ReceiptPrinter.builtinIssue(info.status);
      final name = info.model.isEmpty ? 'SUNMI' : info.model;
      child = _Banner(
        key: const ValueKey('receipt-builtin-state'),
        tone: issue == null ? AppTone.success : AppTone.warning,
        icon: issue == null ? LucideIcons.circleCheck : LucideIcons.circleAlert,
        text: issue == null
            ? (info.paperMm > 0
                ? 'receipt_printer.builtin_ready_paper'.tr(args: [name, '${info.paperMm}'])
                : 'receipt_printer.builtin_ready'.tr(args: [name]))
            : receiptPrinterIssueText(issue, name),
        action: 'receipt_printer.recheck'.tr(),
        onAction: _checkBuiltin,
      );
    }
    return SheetSection(label: 'receipt_printer.builtin_label'.tr(), child: child);
  }

  /// سطر الوصل الجاري (الطباعة التجريبيّة).
  Widget _jobLine() => ValueListenableBuilder<ReceiptJobStatus?>(
        valueListenable: _printer.status,
        builder: (context, s, _) {
          if (s == null || !_testing) return const SizedBox.shrink();
          final text = switch (s.phase) {
            ReceiptJobPhase.preparing => 'receipt_printer.phase_preparing'.tr(),
            ReceiptJobPhase.connecting => 'receipt_printer.phase_connecting'.tr(args: [s.printer]),
            ReceiptJobPhase.checking => 'receipt_printer.phase_checking'.tr(),
            ReceiptJobPhase.sending =>
              'receipt_printer.phase_sending'.tr(args: ['${(s.progress * 100).clamp(0, 100).round()}']),
            ReceiptJobPhase.confirming => 'receipt_printer.phase_confirming'.tr(),
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: _Waiting(text, key: const ValueKey('receipt-printer-job')),
          );
        },
      );

  Widget _resultBanner() {
    final r = _last;
    if (r == null || _testing) return const SizedBox.shrink();
    if (r.ok) {
      final confirmed = r.ack == PrintAck.confirmed;
      return _Banner(
        key: const ValueKey('receipt-printer-result'),
        tone: confirmed ? AppTone.success : AppTone.info,
        icon: confirmed ? LucideIcons.circleCheck : LucideIcons.send,
        text: confirmed ? 'receipt_printer.test_confirmed'.tr() : 'receipt_printer.test_sent'.tr(),
      );
    }
    final issue = r.issue ?? PrintIssue.unknown;
    return _Banner(
      key: const ValueKey('receipt-printer-result'),
      tone: r.uncertain ? AppTone.warning : AppTone.danger,
      icon: r.uncertain ? LucideIcons.triangleAlert : LucideIcons.circleAlert,
      text: r.uncertain
          ? '${'receipt_printer.uncertain_title'.tr()} — ${receiptPrinterIssueText(issue, r.printer ?? '')}'
          : receiptPrinterIssueText(issue, r.printer ?? ''),
      action: issue == PrintIssue.permissionBlocked ? 'receipt_printer.open_settings'.tr() : null,
      onAction: () => _fixIssue(issue),
    );
  }
}

/// خيارٌ بشكل خيارات «الطباعة المباشرة» و«الطابعة الافتراضيّة».
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final tint = selected ? AppColors.brand : AppColors.textMid;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Material(
        color: selected ? AppColors.brandSoftBg : AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
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
                    color: tint.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(R.sm),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: tint),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
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
      ),
    );
  }
}

/// سطر انتظار: دائرةٌ صغيرة ونصّ.
class _Waiting extends StatelessWidget {
  const _Waiting(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        children: [
          const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// بانر حالةٍ ملوّن بنصٍّ يلتفّ وزرٍّ اختياريّ تحته.
class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.tone,
    required this.icon,
    required this.text,
    this.action,
    this.onAction,
  });

  final AppTone tone;
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Sp.md),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: tone.softBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 16, color: tone.onSoft),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  text,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body(color: tone.onSoft).copyWith(fontSize: 13),
                ),
              ),
            ],
          ),
          if (action != null && onAction != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: onAction,
                child: Text(action!, style: AppType.bodyStrong(color: tone.fill)),
              ),
            ),
        ],
      ),
    );
  }
}
