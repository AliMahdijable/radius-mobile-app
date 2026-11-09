import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../services/client_diag.dart';
import '../../services/phone_output.dart';
import '../../services/print_output.dart';
import '../../services/receipt_printer/receipt_printer.dart';
import '../../theme/colors.dart';
import 'design_sheet.dart';
import 'sheet_scaffold.dart';

/// وسم إشعار «جاري الطباعة» ونتيجتها على طابعة الوصولات — الجديد يحلّ محلّ القديم.
const Object printJobSnackTag = #receiptPrintJob;

/// ما يقال بعد الطباعة. الطباعة المباشرة: «أُرسل الوصل إلى X» (لا نافذة تقول شيئاً)؛ الفشل: سببه
/// العامّ بدل الصمت — كان الزرّ يبدو «ما يشتغل» حين تفشل الطباعة. الإلغاء ونافذة النظام صامتان.
///
/// طابعة الوصولات (بلوتوث / طابعة الجهاز، ٩ نوفمبر): «أُرسل» غير «طُبع» (حين تؤكّد الطابعة)، والفشل سببٌ مفهوم
/// («البلوتوث مطفأ»، «نفد الورق»…) مع «حاول مرّة ثانية»، والانقطاع أثناء الإرسال «غير مؤكَّد» مع «إعادة الطباعة».
void showPrintResult(BuildContext context, PrintResult r) {
  if (!context.mounted) return;
  switch (r.outcome) {
    case PrintOutcome.printed:
      final p = r.printer;
      if (p == null) break;
      switch (r.ack) {
        case PrintAck.none:
          showSheetSnack(context, 'printer.sent_to'.tr(args: [p]));
        case PrintAck.sent:
          showSheetSnack(context, 'printer.sent_to'.tr(args: [p]), tag: printJobSnackTag);
        case PrintAck.confirmed:
          showSheetSnack(context, 'receipt_printer.printed_on'.tr(args: [p]), tag: printJobSnackTag);
        case PrintAck.duplicate:
          showSheetSnack(context, 'receipt_printer.duplicate'.tr(), tag: printJobSnackTag);
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
        showSheetSnack(context, 'printer.failed'.tr(), isError: true, autoExplain: false);
        break;
      }
      dismissSheetSnack(printJobSnackTag);
      unawaited(_receiptPrinterProblem(context, r, issue));
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

/// ورقة السبب: «حاول مرّة ثانية» (لم يُطبع شيء)، أو «إعادة الطباعة» (غير مؤكَّد)، أو «فتح الإعدادات» (الإذن مرفوضٌ دائماً).
Future<void> _receiptPrinterProblem(BuildContext context, PrintResult r, PrintIssue issue) async {
  final message = receiptPrinterIssueText(issue, r.printer ?? '');
  final retry = r.retry;
  if (retry == null || issue == PrintIssue.notConfigured) {
    showSheetSnack(context, message, isError: true, autoExplain: false);
    return;
  }
  final blocked = issue == PrintIssue.permissionBlocked;
  final go = await showConfirmSheet(
    context,
    title: r.uncertain ? 'receipt_printer.uncertain_title'.tr() : 'receipt_printer.failed_title'.tr(),
    message: message,
    confirmLabel: blocked
        ? 'receipt_printer.open_settings'.tr()
        : (r.uncertain ? 'receipt_printer.reprint'.tr() : 'receipt_printer.try_again'.tr()),
    cancelLabel: 'receipt_printer.close'.tr(),
    icon: r.uncertain ? LucideIcons.triangleAlert : LucideIcons.printer,
    tone: AppTone.warning,
  );
  if (go != true) return;
  if (blocked) {
    await ReceiptPrinter.instance.openAppSettings();
    return;
  }
  final next = await retry();
  // الورقة التي طلبت الطباعة قد تكون أُغلقت — النتيجة على المتصفّح الجذر.
  final ctx = context.mounted ? context : PhoneOutput.navigatorKey?.currentContext;
  if (ctx != null && ctx.mounted) showPrintResult(ctx, next);
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
