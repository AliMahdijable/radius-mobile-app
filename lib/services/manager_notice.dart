import '../api/managers_api.dart';
import '../api/whatsapp_api.dart';

/// نتيجة محاولة إرسال إشعار للمدير. يُرجع كلا الاتجاهين منفصلاً
/// عشان الـsnackbar يبيّن سبب فشل أيّهما إذا فشل.
class ManagerNoticeResult {
  const ManagerNoticeResult({
    required this.whatsAppOk,
    required this.pushOk,
    this.whatsAppMessage,
    this.pushMessage,
  });
  final bool whatsAppOk;
  final bool pushOk;
  final String? whatsAppMessage;
  final String? pushMessage;
}

/// مطلب 2026-06-12: إشعار للمدير الفرعي بعد كل عملية رصيد. مطابق
/// v1 _autoSendManagerNotice (managers_screen.dart:245). الـactionKind
/// يجب أن يكون أحد:
///   'deposit_cash' | 'deposit_loan' | 'withdraw' | 'sas_pay_debt'
///   | 'add_points' | 'debt_created' | 'debt_payment'
///
/// رسالة الواتساب تستعمل قالب `manager_agent` لو موجود، وإلا تستعمل
/// رسالة افتراضية مبنية على placeholders. الـpush يرسل عبر
/// /api/fcm/send-manager-balance-update.
class ManagerNoticeService {
  ManagerNoticeService._();

  static Future<ManagerNoticeResult> notify({
    required Manager manager,
    required num amount,
    required bool isLoan,
    required num previousCredit,
    required num previousDebt,
    required num currentCredit,
    required num currentDebt,
    required String actionKind,
    String? notes,
    bool sendWhatsApp = true,
    bool sendPush = true,
  }) async {
    bool whatsAppOk = false;
    bool pushOk = false;
    String? whatsAppMessage;
    String? pushMessage;

    // WhatsApp branch
    if (sendWhatsApp) {
      final phone = (manager.mobile ?? '').trim();
      if (phone.isEmpty) {
        whatsAppMessage = 'لا يوجد رقم هاتف للمدير';
      } else {
        final templates = await WhatsAppApi.loadTemplates();
        WhatsTemplate? managerTemplate;
        if (templates != null) {
          for (final t in templates) {
            if (t.templateType == 'manager_agent' && t.isActive) {
              managerTemplate = t;
              break;
            }
          }
        }
        final body = managerTemplate != null
            ? _renderTemplate(
                managerTemplate.messageContent,
                manager: manager,
                amount: amount,
                isLoan: isLoan,
                previousCredit: previousCredit,
                currentCredit: currentCredit,
                currentDebt: currentDebt,
                actionKind: actionKind,
                notes: notes,
              )
            : _defaultMessage(
                manager: manager,
                amount: amount,
                isLoan: isLoan,
                currentCredit: currentCredit,
                currentDebt: currentDebt,
                actionKind: actionKind,
                notes: notes,
              );
        final r = await WhatsAppApi.sendMessage(
          to: phone,
          message: body,
          intent: 'manager_notice',
        );
        whatsAppOk = r.ok;
        whatsAppMessage = r.message;
      }
    }

    // Push branch
    if (sendPush) {
      final r = await ManagersApi.sendBalanceUpdatePush(
        manager: manager,
        amount: amount,
        isLoan: isLoan,
        previousCredit: previousCredit,
        previousDebt: previousDebt,
        currentCredit: currentCredit,
        currentDebt: currentDebt,
        actionKind: actionKind,
        notes: notes,
      );
      pushOk = r.ok;
      pushMessage = r.message;
    }

    return ManagerNoticeResult(
      whatsAppOk: whatsAppOk,
      pushOk: pushOk,
      whatsAppMessage: whatsAppMessage,
      pushMessage: pushMessage,
    );
  }

  /// Render template تستعمل placeholders مثل v1 _ManagerFinancialNoticeData
  /// {manager_name} / {manager_username} / {amount} / {previous_credit}
  /// / {current_credit} / {current_debt} / {action_label} / {notes}.
  static String _renderTemplate(
    String template, {
    required Manager manager,
    required num amount,
    required bool isLoan,
    required num previousCredit,
    required num currentCredit,
    required num currentDebt,
    required String actionKind,
    String? notes,
  }) {
    final actionLabel = _actionLabel(actionKind, isLoan: isLoan);
    return template
        .replaceAll('{manager_name}', manager.fullName)
        .replaceAll('{manager_username}', manager.username)
        .replaceAll('{amount}', _fmt(amount))
        .replaceAll('{previous_credit}', _fmt(previousCredit))
        .replaceAll('{current_credit}', _fmt(currentCredit))
        .replaceAll('{current_debt}', _fmt(currentDebt))
        .replaceAll('{action_label}', actionLabel)
        .replaceAll('{notes}', (notes ?? '').trim());
  }

  /// Fallback message لو ما يوجد قالب manager_agent فعّال.
  static String _defaultMessage({
    required Manager manager,
    required num amount,
    required bool isLoan,
    required num currentCredit,
    required num currentDebt,
    required String actionKind,
    String? notes,
  }) {
    final name = manager.fullName.isNotEmpty
        ? manager.fullName
        : manager.username;
    final label = _actionLabel(actionKind, isLoan: isLoan);
    final lines = <String>[
      'مرحباً $name،',
      'تم تنفيذ: $label ${_fmt(amount)} د.ع',
      'رصيدك الحالي: ${_fmt(currentCredit)} د.ع',
      if (currentDebt > 0) 'الدين عليك: ${_fmt(currentDebt)} د.ع',
      if ((notes ?? '').trim().isNotEmpty) 'ملاحظة: ${notes!.trim()}',
    ];
    return lines.join('\n');
  }

  static String _actionLabel(String kind, {required bool isLoan}) {
    switch (kind) {
      case 'deposit_cash':
        return isLoan ? 'إيداع آجل' : 'شحن رصيد';
      case 'deposit_loan':
        return 'إيداع آجل';
      case 'withdraw':
        return 'سحب رصيد';
      case 'sas_pay_debt':
        return 'تسديد دين';
      case 'add_points':
        return 'إضافة نقاط';
      case 'debt_created':
        return 'إضافة دين';
      case 'debt_payment':
        return 'تسديد دين خارجي';
      default:
        return 'حركة رصيد';
    }
  }

  static String _fmt(num v) {
    final s = v.toInt().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}
