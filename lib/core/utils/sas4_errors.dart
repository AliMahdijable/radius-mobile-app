// ترجمة رموز خطأ SAS4 إلى رسائل عربية مفهومة.
// يجب أن يبقى متطابقاً مع `server/utils/sas4Errors.js` في الـbackend.
class Sas4Errors {
  static const Map<String, String> _ar = {
    'rsp_success': 'تمّت العملية بنجاح',

    // الرصيد / النقاط
    'rsp_insufficient_balance': 'رصيد المدير غير كافٍ لإتمام العملية',
    'rsp_insufficient_points': 'النقاط غير كافية لإتمام العملية',
    'rsp_reward_reached_limit': 'وصلت للحد الأقصى من النقاط المسموح بها',
    'rsp_reward_not_enough': 'النقاط غير كافية',

    // التوثيق
    'rsp_invalid_username_or_password': 'اسم المستخدم أو كلمة المرور غير صحيحة',
    'rsp_invalid_token': 'انتهت صلاحية الجلسة، يرجى تسجيل الدخول من جديد',
    'rsp_token_expired': 'انتهت صلاحية الجلسة، يرجى تسجيل الدخول من جديد',
    'rsp_unauthorized': 'غير مخوّل لتنفيذ هذه العملية',
    'rsp_permission_denied': 'ليس لديك صلاحية لهذه العملية',
    'rsp_session_expired': 'انتهت صلاحية الجلسة',
    'rsp_account_locked': 'الحساب موقوف، تواصل مع الإدارة',
    'rsp_locked': 'الحساب موقوف',

    // المشتركين
    'rsp_user_not_found': 'المشترك غير موجود',
    'rsp_user_already_exists': 'المشترك موجود مسبقاً',
    'rsp_user_disabled': 'المشترك معطّل',
    'rsp_username_taken': 'اسم المستخدم محجوز مسبقاً',

    // الباقات
    'rsp_profile_not_found': 'الباقة غير موجودة',
    'rsp_profile_not_allowed': 'الباقة غير مسموحة لهذا المشترك',
    'rsp_no_allowed_extensions': 'لا توجد باقات تمديد مُهيّأة',

    // عام
    'rsp_invalid_input': 'بيانات غير صالحة',
    'rsp_invalid_data': 'بيانات غير صالحة',
    'rsp_invalid_request': 'طلب غير صالح',
    'rsp_quota_exceeded': 'تجاوزت الحد المسموح',
    'rsp_rate_limited': 'محاولات كثيرة، يرجى الانتظار قليلاً',
    'rsp_error_general': 'حدث خطأ في الخادم',
    'rsp_internal_error': 'خطأ داخلي في النظام',
    'rsp_database_error': 'خطأ في قاعدة البيانات',
    'rsp_network_error': 'خطأ في الاتصال بالشبكة',

    // الفواتير / المعاملات
    'rsp_invoice_not_found': 'الفاتورة غير موجودة',
    'rsp_transaction_failed': 'فشلت المعاملة',
    'rsp_duplicate_transaction': 'هذه المعاملة منفّذة مسبقاً',
  };

  /// يحوّل رمز SAS4 لرسالة عربية. لو الرمز غير معروف يُعاد كما هو
  /// (داخل قوسين بعد fallback) حتى لا نُخفي خطأ غير مترجم.
  static String translate(String? rspMessage, {String fallback = 'فشلت العملية'}) {
    if (rspMessage == null) return fallback;
    final raw = rspMessage.trim();
    if (raw.isEmpty) return fallback;
    final key = raw.toLowerCase();
    final ar = _ar[key];
    if (ar != null) return ar;
    if (key.startsWith('rsp_')) return '$fallback ($rspMessage)';
    // أخطاء dio/network الإنجليزية الجاهزة — استبدل بالـfallback العربي
    // بدل ما يطلع للمستخدم نص "Connection error" أو "Http status error 502".
    final lower = raw.toLowerCase();
    if (lower.startsWith('http status error') ||
        lower.startsWith('connection error') ||
        lower.startsWith('connection timeout') ||
        lower.startsWith('connection failed') ||
        lower.startsWith('receive timeout') ||
        lower.startsWith('send timeout') ||
        lower.startsWith('socketexception') ||
        lower.startsWith('request failed')) {
      return fallback;
    }
    return rspMessage;
  }
}
