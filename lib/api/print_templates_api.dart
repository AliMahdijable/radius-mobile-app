import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';

/// نموذج قالب طباعة — a4 أو pos.
class PrintTemplate {
  const PrintTemplate({
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

  final int? id;
  final String adminId;
  final String templateType; // 'a4' | 'pos'
  final String templateName;
  final String content; // HTML مع placeholders {var}
  final String? templateData; // JSON اختياري لحفظ الـbuilder state
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  static PrintTemplate fromJson(Map<String, dynamic> j) => PrintTemplate(
        id: (j['id'] is int)
            ? j['id'] as int
            : int.tryParse(j['id']?.toString() ?? ''),
        adminId: j['admin_id']?.toString() ?? '',
        templateType: j['template_type']?.toString() ?? 'pos',
        templateName: j['template_name']?.toString() ?? '',
        content: j['content']?.toString() ?? '',
        templateData: j['template_data']?.toString(),
        isActive: j['is_active'] == 1 || j['is_active'] == true,
        createdAt: j['created_at']?.toString(),
        updatedAt: j['updated_at']?.toString(),
      );

  PrintTemplate copyWith({
    String? templateName,
    String? content,
    bool? isActive,
  }) =>
      PrintTemplate(
        id: id,
        adminId: adminId,
        templateType: templateType,
        templateName: templateName ?? this.templateName,
        content: content ?? this.content,
        templateData: templateData,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// المتغيّرات المتاحة داخل القالب — للـpicker في المحرّر.
  static const List<VariableInfo> availableVariables = [
    VariableInfo('{invoice_number}', 'رقم الفاتورة'),
    VariableInfo('{date}', 'التاريخ'),
    VariableInfo('{subscriber_name}', 'اسم المشترك'),
    VariableInfo('{phone_number}', 'رقم الهاتف'),
    VariableInfo('{package_name}', 'اسم الباقة'),
    VariableInfo('{package_price}', 'سعر الباقة'),
    VariableInfo('{paid_amount}', 'المبلغ المدفوع'),
    VariableInfo('{remaining_amount}', 'المبلغ المتبقي'),
    VariableInfo('{expiry_date}', 'تاريخ الانتهاء'),
    VariableInfo('{debt_amount}', 'مبلغ الدين'),
  ];
}

class VariableInfo {
  const VariableInfo(this.token, this.label);
  final String token;
  final String label;
}

/// Print templates API — يستهلك backend `/api/print-templates/*`.
class PrintTemplatesApi {
  PrintTemplatesApi._();

  /// GET /api/print-templates/templates/:adminId
  static Future<List<PrintTemplate>> list() async {
    try {
      final adminId = await AuthStorage.readAdminId();
      if (adminId == null || adminId.isEmpty) return const [];
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/print-templates/templates/$adminId');
      final body = r.data ?? const {};
      if (body['success'] != true) return const [];
      final list = body['templates'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => PrintTemplate.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      _log('list', e);
      return const [];
    } catch (e) {
      _log('list', e);
      return const [];
    }
  }

  /// POST /api/print-templates/create — إنشاء قالب جديد.
  static Future<PrintTemplate?> create({
    required String templateType,
    required String templateName,
    required String content,
    bool isActive = true,
  }) async {
    try {
      final adminId = await AuthStorage.readAdminId();
      if (adminId == null || adminId.isEmpty) return null;
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/print-templates/create',
        data: {
          'adminId': adminId,
          'templateType': templateType,
          'templateName': templateName,
          'content': content,
          'isActive': isActive,
        },
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final t = body['template'];
      if (t is Map) return PrintTemplate.fromJson(Map<String, dynamic>.from(t));
      return null;
    } on DioException catch (e) {
      _log('create', e);
      return null;
    } catch (e) {
      _log('create', e);
      return null;
    }
  }

  /// PUT /api/print-templates/update/:id
  static Future<bool> update(
    int id, {
    String? templateName,
    String? content,
    bool? isActive,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (templateName != null) body['templateName'] = templateName;
      if (content != null) body['content'] = content;
      if (isActive != null) body['isActive'] = isActive;
      if (body.isEmpty) return true;
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/print-templates/update/$id',
        data: body,
      );
      return r.data?['success'] == true;
    } on DioException catch (e) {
      _log('update $id', e);
      return false;
    } catch (e) {
      _log('update $id', e);
      return false;
    }
  }

  /// DELETE /api/print-templates/delete/:id
  static Future<bool> delete(int id) async {
    try {
      final r = await ApiClient.dio
          .delete<Map<String, dynamic>>('/api/print-templates/delete/$id');
      return r.data?['success'] == true;
    } on DioException catch (e) {
      _log('delete $id', e);
      return false;
    } catch (e) {
      _log('delete $id', e);
      return false;
    }
  }
}

void _log(String tag, Object e) {
  if (kDebugMode) debugPrint('[PrintTemplatesApi] $tag: $e');
}
