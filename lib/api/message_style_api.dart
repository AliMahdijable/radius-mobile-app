import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';

/// «سُمك خطّ الرسائل» (٢ نوفمبر — الخادم server/messageStyle.js): العريض في رسائل واتساب وتلغرام لهذا الحساب —
///   GET /api/whatsapp/message-style/:adminId ⇒ {weight, options, previews}
///   PUT /api/whatsapp/message-style/:adminId {weight} (بصلاحيّة whatsapp.templates)
/// الدرجات: normal «عادي» · values «القيم عريضة» · bold «كلّها عريضة». المعاينة من الخادم بعلامات واتساب (`*…*` = عريض).
class MessageStyle {
  const MessageStyle({required this.weight, required this.options, required this.previews});
  final String weight;
  final List<String> options;
  final Map<String, String> previews;

  static const labels = {'normal': 'عادي', 'values': 'القيم عريضة', 'bold': 'كلّها عريضة'};

  static MessageStyle? fromJson(Object? d) {
    if (d is! Map) return null;
    final opts = (d['options'] is List ? (d['options'] as List).map((e) => e.toString()) : labels.keys).where(labels.containsKey).toList();
    final w = d['weight']?.toString() ?? 'normal';
    final p = d['previews'] is Map ? Map<String, dynamic>.from(d['previews'] as Map) : const <String, dynamic>{};
    return MessageStyle(
      weight: opts.contains(w) ? w : 'normal',
      options: opts.isEmpty ? labels.keys.toList() : opts,
      previews: {for (final e in p.entries) e.key: e.value?.toString() ?? ''},
    );
  }
}

class MessageStyleApi {
  MessageStyleApi._();

  static Future<String?> _path() async {
    final id = await AuthStorage.readAdminId();
    return id == null ? null : '/api/whatsapp/message-style/$id'; // كقوالب الواتساب (المعرّف بلا ترميز)
  }

  /// null ⇒ خادمٌ أقدم أو بلا صلاحيّة أو تعذّر — لا تُعرض البطاقة.
  static Future<MessageStyle?> load() async {
    final p = await _path();
    if (p == null) return null;
    try {
      final r = await ApiClient.dio.get<dynamic>(p);
      final b = r.data;
      return b is Map && b['success'] == true ? MessageStyle.fromJson(b['data']) : null;
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 message-style GET: $e');
      return null;
    }
  }

  /// يحفظ الدرجة ⇒ (ok, error).
  static Future<({bool ok, String? error})> save(String weight) async {
    final p = await _path();
    if (p == null) return (ok: false, error: 'انتهت الجلسة — سجّل الدخول');
    try {
      final r = await ApiClient.dio.put<dynamic>(p, data: {'weight': weight});
      final b = r.data;
      return b is Map && b['success'] == true ? (ok: true, error: null) : (ok: false, error: (b is Map ? b['message']?.toString() : null) ?? 'تعذّر الحفظ');
    } on DioException catch (e) {
      final b = e.response?.data;
      final status = e.response?.statusCode;
      final msg = b is Map ? b['message']?.toString() : null;
      return (ok: false, error: msg ?? (status == 403 ? 'لا صلاحيّة لتعديل قوالب الواتساب' : 'تعذّر الاتّصال — أعد المحاولة'));
    } catch (e) {
      return (ok: false, error: 'تعذّر الحفظ — أعد المحاولة');
    }
  }
}
