import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';

/// نطاق الإرسال (Send Scope) — يحدّد أي مشتركين تشملهم الرسائل
/// (تذكيرات دين/انتهاء/تبليغ) اللي يُطلقها المدير الرئيسي:
///   • sendToAll=true  → كل المشتركين تحت كل المدراء الفرعيين
///   • sendToAll=false → فقط مشتركو المدراء المذكورين في managedUsernames
///
/// المصدر: /api/whatsapp/send-scope/:adminId (GET) و /api/whatsapp/send-scope
/// (PATCH). الـbackend يفلتر subscriber_username حسب parent_username =
/// أي managedUsername (case-insensitive).
class SendScope {
  const SendScope({
    required this.sendToAll,
    required this.managedUsernames,
    required this.subManagers,
    this.adminUsername,
  });

  final bool sendToAll;
  final List<String> managedUsernames;

  /// كل المدراء الفرعيين المتاحين (من SAS4 tree أو subscribers fallback).
  final List<String> subManagers;
  final String? adminUsername;

  factory SendScope.fromJson(Map<String, dynamic> j) {
    List<String> _list(dynamic v) => v is List
        ? v.whereType<String>().toList()
        : v is Iterable
            ? v.map((e) => e.toString()).toList()
            : const <String>[];
    return SendScope(
      sendToAll: j['sendToAll'] == true,
      managedUsernames: _list(j['managedUsernames']),
      subManagers: _list(j['subManagers']),
      adminUsername: j['adminUsername']?.toString(),
    );
  }
}

class SendScopeApi {
  SendScopeApi._();

  /// GET /api/whatsapp/send-scope/:adminId
  static Future<SendScope?> fetch() async {
    try {
      final adminId = await AuthStorage.readAdminId();
      if (adminId == null || adminId.isEmpty) return null;
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/whatsapp/send-scope/$adminId',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      return SendScope.fromJson(Map<String, dynamic>.from(body));
    } on DioException catch (e) {
      _log('fetch', e);
      return null;
    } catch (e) {
      _log('fetch', e);
      return null;
    }
  }

  /// PATCH /api/whatsapp/send-scope
  static Future<({bool ok, String? message})> update({
    required bool sendToAll,
    required List<String> managedUsernames,
  }) async {
    try {
      final adminId = await AuthStorage.readAdminId();
      if (adminId == null || adminId.isEmpty) {
        return (ok: false, message: 'admin_id مفقود');
      }
      final r = await ApiClient.dio.patch<Map<String, dynamic>>(
        '/api/whatsapp/send-scope',
        data: {
          'adminId': adminId,
          'sendToAll': sendToAll,
          'managedUsernames': managedUsernames,
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } on DioException catch (e) {
      _log('update', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'خطأ في الشبكة');
    } catch (e) {
      _log('update', e);
      return (ok: false, message: e.toString());
    }
  }
}

void _log(String tag, Object err) {
  if (kDebugMode) debugPrint('[SendScopeApi] $tag: $err');
}
