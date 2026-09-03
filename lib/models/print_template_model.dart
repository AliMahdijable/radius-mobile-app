class PrintTemplateModel {
  final int? id;
  final String adminId;
  final String templateType; // 'a4' or 'pos'
  final String templateName;
  final String content; // HTML with placeholders
  final String? templateData; // JSON builder state
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  const PrintTemplateModel({
    this.id,
    required this.adminId,
    required this.templateType,
    required this.templateName,
    required this.content,
    this.templateData,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory PrintTemplateModel.fromJson(Map<String, dynamic> json) {
    return PrintTemplateModel(
      id: json['id'] as int?,
      adminId: json['admin_id']?.toString() ?? '',
      templateType: json['template_type']?.toString() ?? 'pos',
      templateName: json['template_name']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      templateData: json['template_data']?.toString(),
      isActive: json['is_active'] == 1 || json['is_active'] == true,
      createdAt: json['created_at']?.toString(),
      updatedAt: json['updated_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'adminId': adminId,
        'templateType': templateType,
        'templateName': templateName,
        'content': content,
        if (templateData != null) 'templateData': templateData,
        'isActive': isActive,
      };

  PrintTemplateModel copyWith({
    int? id,
    String? adminId,
    String? templateType,
    String? templateName,
    String? content,
    String? templateData,
    bool? isActive,
  }) {
    return PrintTemplateModel(
      id: id ?? this.id,
      adminId: adminId ?? this.adminId,
      templateType: templateType ?? this.templateType,
      templateName: templateName ?? this.templateName,
      content: content ?? this.content,
      templateData: templateData ?? this.templateData,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  static const List<String> availableVariables = [
    '{invoice_number}',
    '{date}',
    '{subscriber_name}',
    '{phone_number}',
    '{package_name}',
    '{package_price}',
    '{paid_amount}',
    '{remaining_amount}',
    '{expiry_date}',
    '{debt_amount}',
  ];

  static const Map<String, String> variableLabels = {
    '{invoice_number}': 'رقم الفاتورة',
    '{date}': 'التاريخ',
    '{subscriber_name}': 'اسم المشترك',
    '{phone_number}': 'رقم الهاتف',
    '{package_name}': 'اسم الباقة',
    '{package_price}': 'سعر الباقة',
    '{paid_amount}': 'المبلغ المدفوع',
    '{remaining_amount}': 'المبلغ المتبقي',
    '{expiry_date}': 'تاريخ الانتهاء',
    '{debt_amount}': 'مبلغ الدين',
  };
}
