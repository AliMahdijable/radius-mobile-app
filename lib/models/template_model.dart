class TemplateModel {
  final int? id;
  final String adminId;
  final String templateType;
  final String templateName;
  final String messageContent;
  final bool isActive;

  const TemplateModel({
    this.id,
    required this.adminId,
    required this.templateType,
    required this.templateName,
    required this.messageContent,
    this.isActive = true,
  });

  static String getArabicType(String type) {
    switch (type) {
      case 'debt_reminder':
        return 'تذكير دين';
      case 'expiry_warning':
        return 'تحذير انتهاء';
      case 'service_end':
        return 'انتهاء الخدمة';
      case 'activation_notice':
        return 'إشعار تفعيل';
      case 'renewal':
        return 'تجديد اشتراك';
      case 'payment_confirmation':
        return 'تأكيد تسديد';
      case 'welcome_message':
        return 'رسالة ترحيب';
      default:
        return type;
    }
  }

  static const List<String> availableVariables = [
    '{subscriber_name}',
    '{firstname}',
    '{debt_amount}',
    '{credit_amount}',
    '{phone}',
    '{remaining_days}',
    '{days_remaining}',
    '{expiration_date}',
    '{expiry_date}',
    '{package_name}',
    '{package_price}',
    '{paid_amount}',
    '{discount_amount}',
    '{discounted_price}',
    '{username}',
  ];

  static const Map<String, String> variableLabels = {
    '{subscriber_name}': 'اسم المشترك',
    '{firstname}': 'الاسم الأول',
    '{debt_amount}': 'مبلغ الدين',
    '{credit_amount}': 'الرصيد',
    '{phone}': 'رقم الهاتف',
    '{remaining_days}': 'الأيام المتبقية',
    '{days_remaining}': 'أيام متبقية',
    '{expiration_date}': 'تاريخ الانتهاء',
    '{expiry_date}': 'تاريخ النفاذ',
    '{package_name}': 'اسم الباقة',
    '{package_price}': 'سعر الباقة',
    '{paid_amount}': 'المبلغ المدفوع',
    '{discount_amount}': 'قيمة الخصم',
    '{discounted_price}': 'السعر بعد الخصم',
    '{username}': 'اسم المستخدم',
  };

  factory TemplateModel.fromJson(Map<String, dynamic> json) {
    return TemplateModel(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? ''),
      adminId: (json['admin_id'] ?? '').toString(),
      templateType: (json['template_type'] ?? '').toString(),
      templateName: (json['template_name'] ?? '').toString(),
      messageContent: (json['message_content'] ?? '').toString(),
      isActive: json['is_active'] == true || json['is_active'] == 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'adminId': adminId,
        'templateType': templateType,
        'templateName': templateName,
        'messageContent': messageContent,
      };
}
