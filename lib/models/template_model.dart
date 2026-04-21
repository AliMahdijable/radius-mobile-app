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
        return 'إشعار تمديد';
      case 'payment_confirmation':
        return 'تأكيد تسديد';
      case 'welcome_message':
        return 'رسالة ترحيب';
      case 'manager_agent':
        return 'قالب الوكيل';
      default:
        return type;
    }
  }

  static const List<String> managerAgentVariables = [
    '{manager_name}',
    '{manager_username}',
    '{amount}',
    '{action_type}',
    '{previous_credit}',
    '{current_credit}',
    '{previous_debt}',
    '{current_debt}',
    '{movement_description}',
  ];

  static List<String> variablesForType(String type) {
    if (type == 'manager_agent') return managerAgentVariables;
    return availableVariables;
  }

  // Variable names ALIGNED with the server-side canonical keys in
  // whatsapp/templateHelper.js. Previously we shipped {expiration_date}
  // and {remaining_days} which had to be aliased server-side — now
  // every chip the admin taps inserts the name the renderer natively
  // understands, so new templates render on day one.
  static const List<String> availableVariables = [
    '{firstname}',
    '{subscriber_name}',
    '{username}',
    '{phone}',
    '{package_name}',
    '{package_price}',
    '{days_remaining}',
    '{expiry_date}',
    '{debt_amount}',
    '{credit_amount}',
    '{paid_amount}',
    '{discount_amount}',
    '{discounted_price}',
  ];

  static const Map<String, String> variableLabels = {
    '{firstname}':        'الاسم الأول',
    '{subscriber_name}':  'اسم المشترك',
    '{username}':         'اسم المستخدم',
    '{phone}':            'رقم الهاتف',
    '{package_name}':     'اسم الباقة',
    '{package_price}':    'سعر الباقة',
    '{days_remaining}':   'الأيام المتبقية',
    '{expiry_date}':      'تاريخ الانتهاء',
    '{debt_amount}':      'مبلغ الدين',
    '{credit_amount}':    'الرصيد',
    '{paid_amount}':      'المبلغ المدفوع',
    '{discount_amount}':  'قيمة الخصم',
    '{discounted_price}': 'السعر بعد الخصم',
    '{manager_name}':        'اسم المدير',
    '{manager_username}':    'معرّف المدير',
    '{amount}':              'المبلغ',
    '{action_type}':         'نوع الحركة',
    '{previous_credit}':     'الرصيد السابق',
    '{current_credit}':      'الرصيد الحالي',
    '{previous_debt}':       'الدين السابق',
    '{current_debt}':        'الدين الحالي',
    '{movement_description}': 'وصف الحركة',
  };

  static const Map<String, String> variableIcons = {
    '{firstname}':        '👤',
    '{subscriber_name}':  '👤',
    '{username}':         '🔑',
    '{phone}':            '📞',
    '{package_name}':     '📦',
    '{package_price}':    '💰',
    '{days_remaining}':   '📅',
    '{expiry_date}':      '📅',
    '{debt_amount}':      '💸',
    '{credit_amount}':    '💳',
    '{paid_amount}':      '✅',
    '{discount_amount}':  '🏷️',
    '{discounted_price}': '🏷️',
    '{manager_name}':        '👤',
    '{manager_username}':    '🔑',
    '{amount}':              '💰',
    '{action_type}':         '🧾',
    '{previous_credit}':     '💳',
    '{current_credit}':      '💳',
    '{previous_debt}':       '💸',
    '{current_debt}':        '💸',
    '{movement_description}': '📝',
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
