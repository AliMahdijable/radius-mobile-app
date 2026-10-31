import '../../theme/colors.dart';

/// أسماء المشروع الوطنيّ بالعربيّ — نسخة الموقع (`client-v2/src/components/ftth/ftth.ts`) حرفاً، فالشاشتان تقولان الكلمة نفسها.
/// لا «تمديد» أبداً (المالك ٢٠ أكتوبر: تمديد البوّابة تفعيل)؛ ما لا نعرفه يبقى كما جاء.

typedef NationalLabel = ({String label, AppTone tone});

const Map<String, NationalLabel> _ticketStatuses = {
  'new': (label: 'جديدة', tone: AppTone.info),
  'in progress': (label: 'قيد المعالجة', tone: AppTone.warning),
  'resolved': (label: 'محلولة', tone: AppTone.success),
  'closed': (label: 'مغلقة', tone: AppTone.neutral),
  'close': (label: 'مغلقة', tone: AppTone.neutral),
  'canceled': (label: 'ملغاة', tone: AppTone.neutral),
  'cancelled': (label: 'ملغاة', tone: AppTone.neutral),
  'contractor feedback': (label: 'بانتظار ردّك', tone: AppTone.warning),
  'reopened': (label: 'أُعيد فتحها', tone: AppTone.warning),
  'on hold': (label: 'معلّقة', tone: AppTone.neutral),
  'waiting for response': (label: 'بانتظار الردّ', tone: AppTone.info),
};
NationalLabel nationalTicketStatus(String s) =>
    _ticketStatuses[s.trim().toLowerCase()] ?? (label: s.isEmpty ? '—' : s, tone: AppTone.neutral);

const Map<String, NationalLabel> _requestStatuses = {
  'done': (label: 'منجز', tone: AppTone.success),
  'new': (label: 'جديد', tone: AppTone.info),
  'open': (label: 'مفتوح', tone: AppTone.info),
  'inprogress': (label: 'قيد التنفيذ', tone: AppTone.warning),
  'in progress': (label: 'قيد التنفيذ', tone: AppTone.warning),
  'error': (label: 'خطأ', tone: AppTone.danger),
  'canceled': (label: 'ملغى', tone: AppTone.neutral),
  'cancelled': (label: 'ملغى', tone: AppTone.neutral),
};
NationalLabel nationalRequestStatus(String s) =>
    _requestStatuses[s.trim().toLowerCase()] ?? (label: s.isEmpty ? '—' : s, tone: AppTone.neutral);

const Map<String, String> _requestTypes = {
  'CustomerOnboardingRequest': 'تسجيل زبون جديد',
  'NewAddressRequest': 'عنوان جديد',
  'SubscriptionTransferRequest': 'نقل ملكيّة اشتراك',
  'SubscriptionTransferRequestNewCustomer': 'نقل ملكيّة لزبون جديد',
  'ChangeAccountInformationRequest': 'تغيير معلومات الحساب',
  'LegacySubscriptionMigrationRequest': 'ترحيل من النظام القديم',
};
String nationalRequestType(String type) => _requestTypes[type] ?? (type.isEmpty ? '—' : 'طلب آخر');

/// أسماء أنواع الطلبات كما تعطيها قائمة الأنواع (إنكليزيّة) ⇒ عربيّة — لفلتر النوع.
const Map<String, String> _requestTypeNames = {
  'customer onboarding request': 'تسجيل زبون جديد',
  'new address onboarding request': 'عنوان جديد',
  'wireless customer onboarding request': 'تسجيل زبون لاسلكيّ',
  'wireless new address onboarding request': 'عنوان جديد لاسلكيّ',
  'change account information': 'تغيير معلومات الحساب',
  'subscription transfer request': 'نقل ملكيّة اشتراك',
  'subscription transfer request new customer': 'نقل ملكيّة لزبون جديد',
  'subscription migration request': 'ترحيل من النظام القديم',
};
String nationalRequestTypeName(String name) => _requestTypeNames[name.trim().toLowerCase()] ?? name;

const Map<String, NationalLabel> _taskStatuses = {
  'completed': (label: 'مكتملة', tone: AppTone.success),
  'not started': (label: 'لم تبدأ', tone: AppTone.info),
  'open': (label: 'مفتوحة', tone: AppTone.info),
  'new': (label: 'جديدة', tone: AppTone.info),
  'in progress': (label: 'قيد التنفيذ', tone: AppTone.warning),
  'inprogress': (label: 'قيد التنفيذ', tone: AppTone.warning),
  'canceled': (label: 'ملغاة', tone: AppTone.neutral),
  'cancelled': (label: 'ملغاة', tone: AppTone.neutral),
};
NationalLabel nationalTaskStatus(String s) =>
    _taskStatuses[s.trim().toLowerCase()] ?? (label: s.isEmpty ? '—' : s, tone: AppTone.neutral);

const Map<String, String> _taskTitles = {
  'connect customer': 'توصيل زبون',
  'sign contract': 'توقيع عقد',
  'maintenance': 'صيانة',
};
String nationalTaskTitle(String t) => _taskTitles[t.trim().toLowerCase()] ?? (t.isEmpty ? '—' : t);

/// أنواع الحركات الماليّة (transactions/types — ٤٥ نوعاً، حيّاً ٣١ أكتوبر).
const Map<String, String> nationalTxTypes = {
  'PLAN_RENEW': 'تجديد',
  'PLAN_PURCHASE': 'اشتراك جديد',
  'PLAN_CHANGE': 'تغيير باقة',
  'AUTO_RENEW': 'تجديد تلقائيّ',
  'PLAN_C_RENEW': 'تجديد مع تغيير',
  'PLAN_EMI_RENEW': 'تجديد بالتقسيط',
  'PLAN_PURCHASE_S': 'اشتراك جديد (مجدول)',
  'PLAN_REACTIVATE': 'إعادة تفعيل',
  'PLAN_SCHEDULE': 'تغيير مجدول',
  'SCHEDULE_CANCEL': 'إلغاء تغيير مجدول',
  'PLAN_SUSPEND': 'إيقاف مؤقّت',
  'PLAN_EXPIRATION': 'انتهاء الباقة',
  'CHANGE_DATE': 'تغيير التاريخ',
  'TRIAL_PERIOD': 'فترة تجريبيّة',
  'TERMINATE': 'إنهاء',
  'TERMINATE_SUBSCRIPTION': 'إنهاء اشتراك',
  'GRACE_DAY_GRANT': 'منح أيّام سماح',
  'RENEW_REVERSAL': 'عكس تجديد',
  'CHANGE_REVERSAL': 'عكس تغيير باقة',
  'PURCHASE_REVERSAL': 'عكس اشتراك',
  'WALLET_TOPUP': 'شحن المحفظة',
  'WALLET_TOPUP_PRLN': 'شحن المحفظة بكارت',
  'WALLET_TRANSFER': 'تحويل رصيد',
  'WALLET_TRANSFER_FEE': 'رسوم تحويل',
  'WALLET_TRANSFER_COMMISSION': 'عمولة تحويل',
  'WALLET_REFUND': 'استرجاعٌ للمحفظة',
  'WALLET_REVERSAL': 'عكس حركة محفظة',
  'BAL_CARD_SELL': 'بيع كارت رصيد',
  'BAL_CARD_PRLN': 'كارت رصيد',
  'CASHOUT': 'سحبٌ نقديّ',
  'CASHBACK_COMMISSION': 'عمولة كاش باك',
  'COMMISSION_TRANSFER': 'تحويل عمولة',
  'COMMISSION_ADJUSTMENT_CREDIT': 'تسوية عمولة (إضافة)',
  'COMMISSION_ADJUSTMENT_DEBIT': 'تسوية عمولة (خصم)',
  'PURCHASE_COMMISSION': 'عمولة اشتراك',
  'PURCH_COMM_REVERSAL': 'عكس عمولة اشتراك',
  'MAINTENANCE_COMMISSION': 'عمولة صيانة',
  'MAINT_COMM_REVERSAL': 'عكس عمولة صيانة',
  'REFILL_TEAM_MEMBER_BALANCE': 'تعبئة رصيد موظّف',
  'TOPUP_INVOICE_PAYMENT': 'دفع فاتورة شحن',
  'TOPUP_INVOICE_REFUND': 'استرجاع فاتورة شحن',
  'SHOP_CASH_SALE_PAYMENT': 'بيعٌ نقديّ (المتجر)',
  'SHOP_CASH_WALLET_TOPUP': 'شحنٌ نقديّ (المتجر)',
  'SHOP_CASH_WALLET_REFUND': 'استرجاعٌ نقديّ (المتجر)',
  'SHOP_CASH_WITHDRAWAL': 'سحبٌ نقديّ (المتجر)',
};
String nationalTxType(String t) => nationalTxTypes[t.trim().toUpperCase()] ?? (t.isEmpty ? '—' : 'حركة أخرى');

/// أصناف التذاكر الثلاثة (support/tickets/categories — ٣١ أكتوبر).
String nationalTicketCategory(String c) =>
    const {'service request': 'طلب خدمة', 'inquiry': 'استفسار', 'incident': 'عطل / انقطاع'}[c.trim().toLowerCase()] ?? (c.isEmpty ? '—' : c);

String nationalPayMethod(String m) => const {'Wallet': 'محفظة', 'Card': 'بطاقة'}[m] ?? (m.isEmpty ? '—' : m);
String nationalPayer(String p) => const {'Partner': 'الوكيل', 'Customer': 'المشترك'}[p] ?? p;
String nationalPlanKind(String k) => const {'BASE_PLAN': 'باقة', 'VAS': 'خدمة مضافة'}[k] ?? k;
