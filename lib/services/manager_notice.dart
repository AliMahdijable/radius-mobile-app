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
    /// مطلب 2026-06-11 (مطابق v1 _ManagerFinancialNoticeData): الكاش
    /// والقالب يفصلان دين الـSAS عن الديون الأخرى. callers يعرفون
    /// التقسيم عند العملية ويمرّرونه؛ لو ما مرّر سيُحسب كله SAS.
    num sasDebts = 0,
    num otherDebts = 0,
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
                previousDebt: previousDebt,
                currentCredit: currentCredit,
                currentDebt: currentDebt,
                sasDebts: sasDebts,
                otherDebts: otherDebts,
                actionKind: actionKind,
                notes: notes,
              )
            : _defaultMessage(
                manager: manager,
                amount: amount,
                isLoan: isLoan,
                previousCredit: previousCredit,
                previousDebt: previousDebt,
                currentCredit: currentCredit,
                currentDebt: currentDebt,
                sasDebts: sasDebts,
                otherDebts: otherDebts,
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

  /// Render the `manager_agent` template. Placeholders mirror v1
  /// _ManagerFinancialNoticeData.applyTemplate (managers_screen:132):
  ///   {manager_name}, {manager_username}, {amount},
  ///   {action_type}      ← الـlabel القصير (مطابق v1)
  ///   {previous_credit}, {current_credit},
  ///   {previous_debt},   ← v2 كان ناسيها
  ///   {current_debt},
  ///   {sas_debts}, {other_debts}, {total_debts},
  ///   {movement_description} ← الـnotes إن وُجد، وإلا الـdescription
  ///                            الافتراضي للنوع.
  /// نُبقي `{action_label}` و `{notes}` كـaliases للقوالب القديمة
  /// التي قد يكون admin أنشأها بالأسماء V2 الأصلية.
  static String _renderTemplate(
    String template, {
    required Manager manager,
    required num amount,
    required bool isLoan,
    required num previousCredit,
    required num previousDebt,
    required num currentCredit,
    required num currentDebt,
    required num sasDebts,
    required num otherDebts,
    required String actionKind,
    String? notes,
  }) {
    final actionTypeLabel = _actionTypeLabel(actionKind, isLoan: isLoan);
    final movementDescription = _movementDescription(
      actionKind,
      isLoan: isLoan,
      notes: notes,
    );
    final managerName = manager.fullName.isNotEmpty
        ? manager.fullName
        : manager.username;
    final replacements = <String, String>{
      '{manager_name}': managerName,
      '{manager_username}': manager.username,
      '{amount}': _fmt(amount),
      '{action_type}': actionTypeLabel,
      '{action_label}': actionTypeLabel, // alias للتوافق
      '{previous_credit}': _fmt(previousCredit),
      '{current_credit}': _fmt(currentCredit),
      '{previous_debt}': _fmt(previousDebt),
      '{current_debt}': _fmt(currentDebt),
      '{sas_debts}': _fmt(sasDebts),
      '{other_debts}': _fmt(otherDebts),
      '{total_debts}': _fmt(sasDebts + otherDebts),
      '{movement_description}': movementDescription,
      '{notes}': (notes ?? '').trim(),
    };
    var result = template;
    replacements.forEach((k, v) {
      result = result.replaceAll(k, v);
    });
    return result;
  }

  /// Fallback message لو ما يوجد قالب manager_agent فعّال. النصّ
  /// مبسّط يطابق preview v1 (managers_screen:160) — تحية + سطر
  /// العملية + الرصيد + الدين + الملاحظة.
  static String _defaultMessage({
    required Manager manager,
    required num amount,
    required bool isLoan,
    required num previousCredit,
    required num previousDebt,
    required num currentCredit,
    required num currentDebt,
    required num sasDebts,
    required num otherDebts,
    required String actionKind,
    String? notes,
  }) {
    final name = manager.fullName.isNotEmpty
        ? manager.fullName
        : manager.username;
    final label = _actionTypeLabel(actionKind, isLoan: isLoan);
    final totalDebt = sasDebts + otherDebts > 0
        ? sasDebts + otherDebts
        : currentDebt;
    final lines = <String>[
      'عزيزي المدير $name، 👋',
      '',
      '🧾 العملية: $label',
      '💵 المبلغ: ${_fmt(amount)} د.ع',
      '',
      '💳 رصيدك الحالي: ${_fmt(currentCredit)} د.ع',
      if (previousDebt > 0)
        '↩️ الدين السابق: ${_fmt(previousDebt)} د.ع',
      if (totalDebt > 0) '📊 الدين الحالي: ${_fmt(totalDebt)} د.ع',
      if ((notes ?? '').trim().isNotEmpty)
        '📝 ملاحظة: ${notes!.trim()}',
    ];
    return lines.join('\n');
  }

  /// مطابق v1 _ManagerFinancialNoticeData.actionTypeLabel.
  static String _actionTypeLabel(String kind, {required bool isLoan}) {
    switch (kind) {
      case 'cash_deposit':
      case 'deposit_cash':
        return 'إيداع نقدي';
      case 'loan_deposit':
      case 'deposit_loan':
        return 'إيداع دين';
      case 'withdraw':
        return 'سحب رصيد';
      case 'sas_pay_debt':
      case 'debt_payment':
        return 'تسديد دين';
      case 'add_points':
        return 'إضافة نقاط';
      case 'debt_created':
        return 'إضافة دين';
      case 'info':
        return 'معلومات الحساب';
      default:
        return 'حركة رصيد';
    }
  }

  /// مطابق v1 _ManagerFinancialNoticeData.movementDescription —
  /// لو الـadmin مرّر ملاحظة نظهرها، وإلا الـdescription الافتراضي.
  static String _movementDescription(
    String kind, {
    required bool isLoan,
    String? notes,
  }) {
    final trimmed = (notes ?? '').trim();
    if (trimmed.isNotEmpty) return trimmed;
    switch (kind) {
      case 'cash_deposit':
      case 'deposit_cash':
        return 'إضافة رصيد نقدي';
      case 'loan_deposit':
      case 'deposit_loan':
        return 'إضافة رصيد آجل';
      case 'withdraw':
        return 'سحب رصيد من الحساب';
      case 'sas_pay_debt':
      case 'debt_payment':
        return 'تسديد دين مدير';
      case 'add_points':
        return 'إضافة نقاط مكافأة';
      case 'debt_created':
        return 'تسجيل دين جديد';
      case 'info':
        return 'استعلام عن الحساب';
      default:
        return 'حركة على الحساب';
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
