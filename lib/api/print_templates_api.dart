import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';

/// نموذج قالب طباعة — a4 أو pos. **read-only على الموبايل**.
/// التحرير يتم من الويب فقط (client-v2). الموبايل يستهلكه عند الطباعة.
class PrintTemplate {
  const PrintTemplate({
    this.id,
    required this.adminId,
    required this.templateType,
    required this.templateName,
    required this.content,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  final String adminId;
  final String templateType; // 'a4' | 'pos'
  final String templateName;
  final String content; // HTML مع placeholders {var}
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
        isActive: j['is_active'] == 1 || j['is_active'] == true,
        createdAt: j['created_at']?.toString(),
        updatedAt: j['updated_at']?.toString(),
      );
}

/// Print templates API — يجيب قوالب الأدمن الحالي فقط. التحرير من الويب.
class PrintTemplatesApi {
  PrintTemplatesApi._();

  /// GET /api/print-templates/templates/:adminId
  /// يرجع قائمة القوالب (عادة a4 + pos، UNIQUE key على السيرفر).
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

  /// أرجع القالب لنوع معيّن ('a4' أو 'pos'). null لو ما موجود.
  /// يُستدعى وقت الطباعة الفعليّة لاستخراج content.
  static Future<PrintTemplate?> byType(String type) async {
    final all = await list();
    for (final t in all) {
      if (t.templateType == type) return t;
    }
    return null;
  }
}

void _log(String tag, Object e) {
  if (kDebugMode) debugPrint('[PrintTemplatesApi] $tag: $e');
}
