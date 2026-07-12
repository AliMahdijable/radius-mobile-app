/// تسميات عربية لأنواع الحركات — تُستعمل في exports (Excel/PDF) بدل
/// الرموز الإنجليزية (SUBSCRIBER_ACTIVATE, BALANCE_DEDUCT...) حتى الشيت
/// يكون مفهوم للمستخدم النهائي.
///
/// المصدر: نفس mapping في [report_log_tile.dart::_actionMeta] — نُبقيه
/// متزامن يدوياً (لأن _actionMeta يرجع widget-meta معه أيقونة/لون، وما
/// نحتاجه هنا هو مجرد string). التعديل في مكان واحد ينعكس على كل شاشات
/// التقارير الأربعة.
library;

String arabicActionLabel(String actionType, [String description = '']) {
  final at = actionType.trim().toUpperCase();
  final nonCash = description.contains('غير نقدي');
  switch (at) {
    case 'SUBSCRIBER_ACTIVATE':
      return nonCash ? 'تفعيل (غير نقدي)' : 'تفعيل';
    case 'SUBSCRIBER_EXTEND':
      return nonCash ? 'تمديد (غير نقدي)' : 'تمديد';
    case 'SUBSCRIBER_ADD':
      if (description.contains('تفعيل')) return 'تفعيل';
      return 'إضافة مشترك';
    case 'SUBSCRIBER_EDIT':
      return 'تعديل مشترك';
    case 'SUBSCRIBER_DELETE':
      return 'حذف مشترك';
    case 'SUBSCRIBER_ENABLE':
      return 'تشغيل';
    case 'SUBSCRIBER_DISABLE':
      return 'تعطيل';
    case 'BALANCE_ADD':
      return 'إضافة دين';
    case 'BALANCE_DEDUCT':
      return 'تسديد دين';
    case 'DEBT_PAY':
      return 'تسديد دين';
    case 'PAYMENT_ADD':
      return 'دفعة';
    case 'EXPENSE_ADD':
    case 'ADMIN_EXPENSE':
      return 'صرفية';
    case 'EXPENSE_EDIT':
      return 'تعديل صرفية';
    case 'EXPENSE_DELETE':
      return 'حذف صرفية';
    case 'MANAGER_ADD':
      return 'إضافة مدير';
    case 'MANAGER_EDIT':
      return 'تعديل مدير';
    case 'MANAGER_DELETE':
      return 'حذف مدير';
    case 'ADMIN_ADD':
      return 'إضافة موظف';
    case 'ADMIN_EDIT':
      return 'تعديل موظف';
    case 'ADMIN_DELETE':
      return 'حذف موظف';
    case 'PACKAGE_EDIT':
      return 'تعديل باقة';
    case 'DISCOUNT_SET':
      return 'تطبيق خصم';
    case 'DISCOUNT_REMOVE':
      return 'إزالة خصم';
    case 'WHATSAPP_SEND_MESSAGE':
      return 'إرسال واتساب';
    case 'WHATSAPP_CONNECT':
      return 'اتصال واتساب';
    case 'WHATSAPP_DISCONNECT':
      return 'فصل واتساب';
    case 'WHATSAPP_TEMPLATE_SAVE':
      return 'حفظ قالب WA';
    case 'WHATSAPP_TEMPLATE_DELETE':
      return 'حذف قالب WA';
    case 'PRINT_RECEIPT':
      return 'طباعة وصل';
    case 'PRINT_TEMPLATE_SAVE':
      return 'حفظ قالب طباعة';
    case 'LOGIN':
      return 'تسجيل دخول';
    case 'LOGOUT':
      return 'تسجيل خروج';
    case 'LOGIN_FAILED':
      return 'فشل دخول';
    case 'EXPIRY_NOTIFICATION':
      return 'إشعار انتهاء';
    case 'SYSTEM_ERROR':
      return 'خطأ';
    default:
      return actionType;
  }
}
