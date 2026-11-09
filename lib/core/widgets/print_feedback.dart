import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/client_diag.dart';
import '../../services/phone_output.dart';
import '../../services/print_output.dart';
import '../../services/receipt_printer/receipt_printer.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'app_sheet.dart';
import 'design_sheet.dart';
import 'sheet_scaffold.dart';

/// وسم إشعار «جاري الطباعة» ونتيجتها على طابعة الوصولات — الجديد يحلّ محلّ القديم.
const Object printJobSnackTag = #receiptPrintJob;

/// ما يقال بعد الطباعة. الطباعة المباشرة: «أُرسل الوصل إلى X» (لا نافذة تقول شيئاً)؛ الفشل: سببه
/// العامّ بدل الصمت — كان الزرّ يبدو «ما يشتغل» حين تفشل الطباعة. الإلغاء ونافذة النظام صامتان.
///
/// طابعة الوصولات (بلوتوث / طابعة الجهاز، ٩ نوفمبر): «أُرسل» غير «طُبع» (حين تؤكّد الطابعة)، والفشل سببٌ مفهوم
/// («البلوتوث مطفأ»، «نفد الورق»…) مع «حاول مرّة ثانية»، والانقطاع أثناء الإرسال «غير مؤكَّد» مع «إعادة الطباعة».
///
/// يكتمل حين ينتهي كلّ ما يخصّ هذه الطباعة: ورقة السبب أُغلقت، و«إعادة الطباعة» التي طلبها الوكيل منها بنقرة
/// انتهت وقيلت نتيجتها. ⚠️ من يُغلق ورقته بعد الطباعة (التفعيل، التمديد، التسديد) **ينتظره قبل `pop`**: ورقة
/// السبب تُفتح فوق ورقته، و`pop` بلا انتظار يُغلقها هي بدل ورقته (مراجعة 179 الثانية — كان `pop(true)` يُفهم
/// «إعادة الطباعة» فيُطبع الوصل المدفوع مرّةً ثانية بلا نقرة). ما لا يُغلق شيئاً بعدها (الشاشات) لا يلزمه الانتظار.
Future<void> showPrintResult(BuildContext context, PrintResult r) async {
  if (!context.mounted) return;
  switch (r.outcome) {
    case PrintOutcome.printed:
      final p = r.printer;
      if (p == null) break;
      switch (r.ack) {
        case PrintAck.none:
          unawaited(showSheetSnack(context, 'printer.sent_to'.tr(args: [p])));
        case PrintAck.sent:
          _receiptSnack(context, 'printer.sent_to'.tr(args: [p]), tag: printJobSnackTag);
        case PrintAck.confirmed:
          _receiptSnack(context, 'receipt_printer.printed_on'.tr(args: [p]), tag: printJobSnackTag);
        case PrintAck.duplicate:
          _receiptSnack(context, 'receipt_printer.duplicate'.tr(), tag: printJobSnackTag);
      }
    // نافذة المشاركة نفسها تقول ما جرى (صورة الوصل بالهاتف)
    case PrintOutcome.shared:
    case PrintOutcome.cancelled:
      break;
    case PrintOutcome.failed:
      // سبب الفشل يصلنا (بلا هويّة) — «تعذّرت الطباعة» وحدها لا تُصلَح (المالك ١ نوفمبر: «بالوطني الطباعه مجاي تشتغل»).
      ClientDiag.report('print_failed', message: r.error);
      final issue = r.issue;
      if (issue == null) {
        unawaited(showSheetSnack(context, 'printer.failed'.tr(), isError: true, autoExplain: false));
        break;
      }
      dismissSheetSnack(printJobSnackTag);
      await _receiptPrinterProblem(context, r, issue);
  }
}

/// سبب فشل طابعة الوصولات بكلماتٍ يفهمها الوكيل — [printer] اسمها.
String receiptPrinterIssueText(PrintIssue issue, String printer) => switch (issue) {
      PrintIssue.permission => 'receipt_printer.issue_permission'.tr(),
      PrintIssue.permissionBlocked => 'receipt_printer.issue_permission_blocked'.tr(),
      PrintIssue.btUnsupported => 'receipt_printer.issue_bt_unsupported'.tr(),
      PrintIssue.btOff => 'receipt_printer.issue_bt_off'.tr(),
      PrintIssue.notFound => 'receipt_printer.issue_not_found'.tr(args: [printer]),
      PrintIssue.connectFailed => 'receipt_printer.issue_connect_failed'.tr(args: [printer]),
      PrintIssue.timeout => 'receipt_printer.issue_timeout'.tr(args: [printer]),
      PrintIssue.noWriteChannel => 'receipt_printer.issue_no_write'.tr(args: [printer]),
      PrintIssue.disconnected => 'receipt_printer.issue_disconnected'.tr(args: [printer]),
      PrintIssue.disconnectedMidway => 'receipt_printer.issue_disconnected_midway'.tr(args: [printer]),
      PrintIssue.paperOut => 'receipt_printer.issue_paper_out'.tr(),
      PrintIssue.paperOutMidway => 'receipt_printer.issue_paper_out_midway'.tr(),
      PrintIssue.coverOpen => 'receipt_printer.issue_cover_open'.tr(),
      PrintIssue.overheated => 'receipt_printer.issue_overheated'.tr(),
      PrintIssue.builtinMissing => 'receipt_printer.issue_builtin_missing'.tr(),
      PrintIssue.builtinFault => 'receipt_printer.issue_builtin_fault'.tr(),
      PrintIssue.builtinBusy => 'receipt_printer.issue_builtin_busy'.tr(),
      PrintIssue.builtinUnconfirmed => 'receipt_printer.issue_builtin_unconfirmed'.tr(),
      PrintIssue.builtinRejected => 'receipt_printer.issue_builtin_rejected'.tr(),
      PrintIssue.render => 'receipt_printer.issue_render'.tr(),
      PrintIssue.notConfigured => 'receipt_printer.issue_not_configured'.tr(),
      PrintIssue.unknown => 'receipt_printer.issue_unknown'.tr(args: [printer]),
    };

/// إشعار طابعة الوصولات على الطبقة العليا — ولو كان [context] المتصفّحَ الجذر نفسه (وصل البيع بعد إغلاق ورقته، أو نتيجة
/// إعادة طباعةٍ بعد أن أُغلقت الورقة التي طلبتها): الطبقة هناك تحته لا فوقه، و`showSheetSnack` يصمت.
void _receiptSnack(BuildContext context, String message, {Object? tag, bool isError = false}) {
  OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null && context is StatefulElement && context.state is NavigatorState) {
    overlay = (context.state as NavigatorState).overlay;
  }
  overlay ??= PhoneOutput.navigatorKey?.currentState?.overlay;
  if (overlay == null) return;
  unawaited(showSheetSnackOn(overlay, message, isError: isError, tag: tag, autoExplain: false));
}

/// جواب «فتح الإعدادات» من ورقة السبب — نوعٌ خاصٌّ بها: `pop(true)` من أيّ ورقةٍ أخرى لا يُفهم موافقة.
const Object _openSettings = #receiptPrinterOpenSettings;

/// «إعادة الطباعة» التي بدأها الوكيل من ورقة السبب — تُنتظر ونتيجتها تُقال ولو أُغلقت الورقة قبل أن تنتهي.
class _Reprint {
  Future<PrintResult>? running;
}

/// ورقة السبب: «حاول مرّة ثانية» (لم يُطبع شيء)، أو «إعادة الطباعة» (غير مؤكَّد)، أو «فتح الإعدادات» (الإذن مرفوضٌ دائماً).
///
/// 🐛 مراجعة 179 الثانية (٩ نوفمبر): كانت `showConfirmSheet` (جوابها `bool`) فوق ورقة التفعيل/التمديد/التسديد،
/// وتلك تُغلق نفسها بـ`pop(true)` فور الطباعة — فأغلق ذلك الـ`pop` ورقةَ السبب بـ«نعم»: وصلٌ مدفوع يُطبع ثانيةً بلا
/// نقرة (بلا منع التكرار)، و«غير مؤكَّد» لا يُرى، والإذن المرفوض يفتح الإعدادات وحده، وورقة العمليّة تبقى مفتوحة. الآن:
///   • جواب الورقة من أزرارها وحدها ([_openSettings] و[_Reprint]) — أيّ `pop` من غيرها يُغلقها بلا شيء؛
///   • «إعادة الطباعة» داخل الورقة نفسها بنقرةٍ صريحة: تبقى فوق ورقة العمليّة حتى تنتهي (لا يعود زرّ العمليّة
///     للنقر أثناءها)، وفشلٌ جديدٌ يظهر فيها بسببه؛
///   • ومن يُغلق ورقته ينتظر [showPrintResult] قبل `pop`.
Future<void> _receiptPrinterProblem(BuildContext context, PrintResult r, PrintIssue issue) async {
  if (r.retry == null || issue == PrintIssue.notConfigured) {
    _receiptSnack(context, receiptPrinterIssueText(issue, r.printer ?? ''), isError: true);
    return;
  }
  final reprint = _Reprint();
  final answer = await showAppSheet<Object?>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => _ReceiptPrinterProblemSheet(first: r, reprint: reprint),
  );
  // أُغلقت (بزرّها أو بالسحب أو بالرجوع أو بـ`pop` من غيرها) وإعادةٌ بدأها الوكيل جاريةٌ أو انتهت ⇒ تُنتظر وتُقال.
  final running = reprint.running;
  if (running != null) {
    final next = await running;
    // الورقة التي طلبت الطباعة قد تكون أُغلقت — النتيجة على المتصفّح الجذر.
    final ctx = context.mounted ? context : PhoneOutput.navigatorKey?.currentContext;
    if (ctx != null && ctx.mounted) await showPrintResult(ctx, next);
    return;
  }
  if (identical(answer, _openSettings)) await ReceiptPrinter.instance.openAppSettings();
}

class _ReceiptPrinterProblemSheet extends StatefulWidget {
  const _ReceiptPrinterProblemSheet({required this.first, required this.reprint});

  final PrintResult first;
  final _Reprint reprint;

  @override
  State<_ReceiptPrinterProblemSheet> createState() => _ReceiptPrinterProblemSheetState();
}

class _ReceiptPrinterProblemSheetState extends State<_ReceiptPrinterProblemSheet> {
  late PrintResult _r = widget.first;

  /// كم مرّةً أُعيدت من هنا ولم تنجح — «حاولنا ثانيةً» حتى لا يبدو النقر بلا أثر.
  int _failedAgain = 0;

  bool get _busy => widget.reprint.running != null;

  PrintIssue get _issue => _r.issue ?? PrintIssue.unknown;

  bool get _blocked => _issue == PrintIssue.permissionBlocked;

  /// تُغلق هي وحدها — لا ورقةً فوقها ولا تحتها.
  void _closeSelf([Object? result]) {
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(result);
    } else {
      Navigator.of(context).removeRoute(route, result);
    }
  }

  Future<void> _act() async {
    if (_busy) return;
    if (_blocked) {
      _closeSelf(_openSettings);
      return;
    }
    final retry = _r.retry;
    if (retry == null) return;
    // لا ترمي أبداً: من فتح الورقة ينتظرها قبل أن يُغلق ورقة العمليّة — خطأٌ غير متوقَّع سببٌ يُقال لا ورقةٌ عالقة.
    final printer = _r.printer;
    final running = retry().catchError(
      (Object e) => PrintResult.failed('reprint: $e', printer: printer, issue: PrintIssue.unknown, retry: retry),
    );
    setState(() {
      widget.reprint.running = running;
    });
    final next = await running;
    // أُغلقت أثناءها ⇒ من فتحها ينتظرها ويقول نتيجتها.
    if (!mounted) return;
    final issue = next.issue;
    if (next.outcome == PrintOutcome.failed &&
        issue != null &&
        next.retry != null &&
        issue != PrintIssue.notConfigured) {
      setState(() {
        widget.reprint.running = null;
        _r = next;
        _failedAgain++;
      });
      return;
    }
    // طُبع (أو نتيجةٌ يكفيها إشعار) ⇒ تُغلق ومن فتحها يقولها.
    _closeSelf();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    const tone = AppTone.warning;
    final uncertain = _r.uncertain;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: uncertain ? LucideIcons.triangleAlert : LucideIcons.printer,
        title: uncertain ? 'receipt_printer.uncertain_title'.tr() : 'receipt_printer.failed_title'.tr(),
        subtitle: '',
        tint: tone.fill,
        tintBg: tone.softBg,
        onClose: _closeSelf,
      ),
      footer: SheetFooterBar(
        key: const ValueKey('receipt-problem-action'),
        label: _blocked
            ? 'receipt_printer.open_settings'.tr()
            : (uncertain ? 'receipt_printer.reprint'.tr() : 'receipt_printer.try_again'.tr()),
        icon: _blocked ? LucideIcons.settings : LucideIcons.printer,
        color: tone.fill,
        busy: _busy,
        onPressed: _act,
        leading: SheetSecondaryButton(label: 'receipt_printer.close'.tr(), onTap: _closeSelf),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            receiptPrinterIssueText(_issue, _r.printer ?? ''),
            style: AppType.rowValue(color: AppColors.textBody).copyWith(height: 1.6),
          ),
          if (_failedAgain > 0) ...[
            const SizedBox(height: Sp.sm),
            Text(
              'receipt_printer.failed_again'.tr(),
              key: const ValueKey('receipt-problem-again'),
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

/// «جاري الطباعة على «X»…» طوال وصل طابعة الوصولات — يُربط مرّةً من main (الوصل يُطبع من خدماتٍ بلا سياق).
class ReceiptPrintFeedback {
  ReceiptPrintFeedback._();

  static GlobalKey<NavigatorState>? _nav;
  static bool _showing = false;

  static void attach(GlobalKey<NavigatorState> nav) {
    final first = _nav == null;
    _nav = nav;
    if (first) ReceiptPrinter.instance.status.addListener(_changed);
  }

  static void _changed() {
    final s = ReceiptPrinter.instance.status.value;
    if (s == null) {
      // انتهى: النتيجة (إشعارٌ بالوسم نفسه أو ورقة سبب) يعرضها من طلب الطباعة.
      if (_showing) dismissSheetSnack(printJobSnackTag);
      _showing = false;
      return;
    }
    if (_showing || s.quiet) return;
    final overlay = _nav?.currentState?.overlay;
    if (overlay == null) return;
    _showing = true;
    unawaited(showSheetSnackOn(
      overlay,
      'receipt_printer.printing_on'.tr(args: [s.printer]),
      tag: printJobSnackTag,
      duration: const Duration(seconds: 45),
      autoExplain: false,
    ));
  }
}
