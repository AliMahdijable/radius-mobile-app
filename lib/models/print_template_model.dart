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
    '{receipt_no}',
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
    '{receipt_no}': 'رقم الوصل (No. 00000)',
    '{invoice_number}': 'رقم الفاتورة (legacy)',
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

  /// قوالب افتراضية جاهزة (POS 80mm + A4) — تُستخدم عند إنشاء قالب جديد.
  static String defaultPosTemplate() => '''
<div style="font-family: Cairo, sans-serif; padding: 8px; max-width: 280px; margin: auto; direction: rtl;">
  <div style="text-align:center; border-bottom: 2px dashed #333; padding-bottom: 8px; margin-bottom: 8px;">
    <h2 style="margin: 0; font-size: 16px;">MyServices</h2>
    <div style="font-size: 11px; color: #666;">{receipt_no}</div>
    <div style="font-size: 10px; color: #999;">{date}</div>
  </div>
  <div style="font-size: 12px; line-height: 1.7;">
    <div><b>المشترك:</b> {subscriber_name}</div>
    <div><b>الهاتف:</b> {phone_number}</div>
    <div><b>الباقة:</b> {package_name}</div>
    <div><b>السعر:</b> {package_price}</div>
    <div><b>المدفوع:</b> {paid_amount}</div>
    <div><b>المتبقي:</b> {remaining_amount}</div>
    <div><b>الانتهاء:</b> {expiry_date}</div>
  </div>
  <div style="text-align:center; border-top: 2px dashed #333; margin-top: 8px; padding-top: 8px; font-size: 10px; color: #666;">
    شكراً لاختيارك خدماتنا
  </div>
</div>''';

  static String defaultA4Template() => '''
<div style="padding: 40px; font-family: Cairo, sans-serif; direction: rtl;">
  <div style="display: flex; justify-content: space-between; border-bottom: 3px solid #10b981; padding-bottom: 20px; margin-bottom: 30px;">
    <div>
      <h1 style="margin: 0; color: #10b981; font-size: 24px;">فاتورة</h1>
      <p style="margin: 5px 0; color: #6b7280; font-size: 12px;">{receipt_no}</p>
    </div>
    <div style="text-align: left;">
      <p style="margin: 2px 0; font-size: 12px;">{date}</p>
    </div>
  </div>
  <div style="margin-bottom: 30px;">
    <h3 style="margin: 0 0 10px; color: #1f2937; font-size: 16px;">معلومات المشترك</h3>
    <table style="width: 100%; border-collapse: collapse; font-size: 13px;">
      <tr><td style="padding: 6px; border: 1px solid #e5e7eb; background: #f9fafb;">الاسم</td>
          <td style="padding: 6px; border: 1px solid #e5e7eb;">{subscriber_name}</td></tr>
      <tr><td style="padding: 6px; border: 1px solid #e5e7eb; background: #f9fafb;">الهاتف</td>
          <td style="padding: 6px; border: 1px solid #e5e7eb;">{phone_number}</td></tr>
      <tr><td style="padding: 6px; border: 1px solid #e5e7eb; background: #f9fafb;">الباقة</td>
          <td style="padding: 6px; border: 1px solid #e5e7eb;">{package_name}</td></tr>
      <tr><td style="padding: 6px; border: 1px solid #e5e7eb; background: #f9fafb;">سعر الباقة</td>
          <td style="padding: 6px; border: 1px solid #e5e7eb;">{package_price}</td></tr>
      <tr><td style="padding: 6px; border: 1px solid #e5e7eb; background: #f9fafb;">المدفوع</td>
          <td style="padding: 6px; border: 1px solid #e5e7eb;">{paid_amount}</td></tr>
      <tr><td style="padding: 6px; border: 1px solid #e5e7eb; background: #f9fafb;">المتبقي</td>
          <td style="padding: 6px; border: 1px solid #e5e7eb;">{remaining_amount}</td></tr>
      <tr><td style="padding: 6px; border: 1px solid #e5e7eb; background: #f9fafb;">تاريخ الانتهاء</td>
          <td style="padding: 6px; border: 1px solid #e5e7eb;">{expiry_date}</td></tr>
    </table>
  </div>
  <div style="text-align: center; margin-top: 50px; padding-top: 20px; border-top: 1px solid #e5e7eb; color: #6b7280; font-size: 11px;">
    شكراً لاختيارك خدماتنا
  </div>
</div>''';
}
