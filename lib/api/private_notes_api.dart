import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «ملاحظة خاصّة» للمشترك (المالك ٣١ أكتوبر: «زر ملاحظات خاص بنظامنا… ينخزن يمنا… تنعرض بكارت المشترك فقط، لكل الساسات»):
/// نصٌّ على خادمنا وحده (`server/subscriberPrivateNotes.js`) — لا يُكتب في الساس ولا يصل المشترك. لكلّ المزوّدين بالمسار نفسه.
class PrivateNote {
  const PrivateNote({required this.note, this.updatedAt, this.updatedBy});
  final String note;
  final String? updatedAt;
  final String? updatedBy;

  static PrivateNote? fromJson(dynamic v) {
    if (v is! Map) return null;
    final note = (v['note'] ?? '').toString();
    if (note.trim().isEmpty) return null;
    final at = v['updated_at']?.toString();
    final by = v['updated_by']?.toString();
    return PrivateNote(note: note, updatedAt: (at == null || at.isEmpty) ? null : at, updatedBy: (by == null || by.isEmpty) ? null : by);
  }
}

class PrivateNotesApi {
  PrivateNotesApi._();

  /// أقصى طول (يفرضه الخادم أيضاً).
  static const int maxChars = 1000;

  static String _path(String idx) => '/api/v2/subscribers/${Uri.encodeComponent(idx)}/private-note';

  static String _msg(Object e, String fallback) {
    if (e is DioException) {
      final b = e.response?.data;
      final m = b is Map ? b['message']?.toString() : null;
      if (m != null && m.trim().isNotEmpty) return m;
    }
    return fallback;
  }

  /// الملاحظة الحاليّة — ok:true وnote:null = لا ملاحظة.
  static Future<({bool ok, PrivateNote? note, String? message})> get(String idx) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(_path(idx));
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, note: null, message: b['message']?.toString());
      return (ok: true, note: PrivateNote.fromJson(b['data']), message: null);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 private-note GET: $e');
      return (ok: false, note: null, message: _msg(e, 'تعذّر جلب الملاحظة'));
    }
  }

  /// حفظ [note] — نصٌّ فارغ يحذفها.
  static Future<({bool ok, PrivateNote? note, String? message})> save(String idx, String note) async {
    try {
      final r = note.trim().isEmpty
          ? await ApiClient.dio.delete<Map<String, dynamic>>(_path(idx))
          : await ApiClient.dio.put<Map<String, dynamic>>(_path(idx), data: {'note': note});
      final b = r.data ?? const {};
      if (b['success'] != true) return (ok: false, note: null, message: b['message']?.toString() ?? 'تعذّر حفظ الملاحظة');
      return (ok: true, note: PrivateNote.fromJson(b['data']), message: b['message']?.toString());
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 private-note save: $e');
      return (ok: false, note: null, message: _msg(e, 'تعذّر حفظ الملاحظة'));
    }
  }
}
