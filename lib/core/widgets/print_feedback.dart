import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

import '../../services/print_output.dart';
import 'sheet_scaffold.dart';

/// ما يقال بعد الطباعة. الطباعة المباشرة: «أُرسل الوصل إلى X» (لا نافذة تقول شيئاً)؛ الفشل: سببه
/// العامّ بدل الصمت — كان الزرّ يبدو «ما يشتغل» حين تفشل الطباعة. الإلغاء ونافذة النظام صامتان.
void showPrintResult(BuildContext context, PrintResult r) {
  if (!context.mounted) return;
  switch (r.outcome) {
    case PrintOutcome.printed:
      if (r.printer != null) showSheetSnack(context, 'printer.sent_to'.tr(args: [r.printer!]));
    case PrintOutcome.cancelled:
      break;
    case PrintOutcome.failed:
      showSheetSnack(context, 'printer.failed'.tr(), isError: true, autoExplain: false);
  }
}
