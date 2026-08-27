import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// 2026-08-26: TelegramApi — Dart client لعشرة endpoints في backend
/// تلغرام. مصمَّم بنفس pattern الـclient-v2 (web) — نفس الحقول والمنطق.
///
/// **backend endpoints**:
/// - GET  /api/telegram/status/:adminId
/// - POST /api/telegram/connect
/// - POST /api/telegram/disconnect
/// - GET  /api/telegram/bindings/:adminId
/// - DELETE /api/telegram/bindings/:adminId/:idx
/// - GET  /api/telegram/deep-link/:adminId/:idx
/// - POST /api/telegram/send-link-via-wa/:adminId/:idx
/// - POST /api/telegram/broadcast-links/:adminId  (dry+real)
/// - POST /api/telegram/broadcast                 (dry+real)

class TelegramStatus {
  final bool exists;
  final bool connected;
  final String? botUsername;
  final String? botFirstName;
  final String? lastError;
  final int totalBindings;
  final int activeBindings;
  final int blockedBindings;

  const TelegramStatus({
    required this.exists,
    required this.connected,
    this.botUsername,
    this.botFirstName,
    this.lastError,
    this.totalBindings = 0,
    this.activeBindings = 0,
    this.blockedBindings = 0,
  });

  static TelegramStatus fromJson(Map<String, dynamic> j) {
    final b = j['bindings'] is Map ? j['bindings'] as Map : const {};
    return TelegramStatus(
      exists: j['exists'] == true,
      connected: j['connected'] == true,
      botUsername: j['botUsername']?.toString(),
      botFirstName: j['botFirstName']?.toString(),
      lastError: j['lastError']?.toString(),
      totalBindings: (b['total'] as num?)?.toInt() ?? 0,
      activeBindings: (b['active'] as num?)?.toInt() ?? 0,
      blockedBindings: (b['blocked'] as num?)?.toInt() ?? 0,
    );
  }
}

class TelegramBinding {
  final int id;
  final String adminId;
  final String sas4Idx;
  final String chatId;
  final String? tgUsername;
  final String? tgFirstName;
  final String? verifiedAt;
  final String? lastSendAt;
  final bool isBlocked;
  final String? blockedAt;

  const TelegramBinding({
    required this.id,
    required this.adminId,
    required this.sas4Idx,
    required this.chatId,
    this.tgUsername,
    this.tgFirstName,
    this.verifiedAt,
    this.lastSendAt,
    this.isBlocked = false,
    this.blockedAt,
  });

  static TelegramBinding? fromJson(Map<String, dynamic> j) {
    final id = int.tryParse(j['id']?.toString() ?? '');
    final sas = j['sas4_idx']?.toString();
    if (id == null || sas == null) return null;
    return TelegramBinding(
      id: id,
      adminId: j['admin_id']?.toString() ?? '',
      sas4Idx: sas,
      chatId: j['chat_id']?.toString() ?? '',
      tgUsername: j['tg_username']?.toString(),
      tgFirstName: j['tg_first_name']?.toString(),
      verifiedAt: j['verified_at']?.toString(),
      lastSendAt: j['last_send_at']?.toString(),
      isBlocked: j['is_blocked'] == 1 || j['is_blocked'] == true,
      blockedAt: j['blocked_at']?.toString(),
    );
  }
}

class BroadcastLinksPreview {
  final int totalSubs;
  final int alreadyBound;
  final int eligible;
  final int skippedNoPhone;
  const BroadcastLinksPreview({
    required this.totalSubs,
    required this.alreadyBound,
    required this.eligible,
    required this.skippedNoPhone,
  });
  static BroadcastLinksPreview fromJson(Map<String, dynamic> j) =>
      BroadcastLinksPreview(
        totalSubs: (j['totalSubs'] as num?)?.toInt() ?? 0,
        alreadyBound: (j['alreadyBound'] as num?)?.toInt() ?? 0,
        eligible: (j['eligible'] as num?)?.toInt() ?? 0,
        skippedNoPhone: (j['skippedNoPhone'] as num?)?.toInt() ?? 0,
      );
}

class BroadcastPreview {
  final int totalBound;
  final int eligible;
  final int blocked;

  /// 2026-08-26 (TG scope): مربوطون خارج نطاق الإرسال الحالي (send-scope
  /// المدير). لو المدير نطاقه sendToAll=false ومحدَّد مدراء فرعيّون معيّنون،
  /// المشتركون التابعون لغيرهم يُستَثنَون تلقائياً. الـUI يعرض هذا العدد
  /// حتى الأدمن يفهم ليش eligible أقلّ من totalBound.
  final int outOfScope;
  const BroadcastPreview({
    required this.totalBound,
    required this.eligible,
    required this.blocked,
    this.outOfScope = 0,
  });
  static BroadcastPreview fromJson(Map<String, dynamic> j) => BroadcastPreview(
        totalBound: (j['totalBound'] as num?)?.toInt() ?? 0,
        eligible: (j['eligible'] as num?)?.toInt() ?? 0,
        blocked: (j['blocked'] as num?)?.toInt() ?? 0,
        outOfScope: (j['outOfScope'] as num?)?.toInt() ?? 0,
      );
}

class TelegramApi {
  TelegramApi._();

  static Future<TelegramStatus?> getStatus(String adminId) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/telegram/status/$adminId',
      );
      final body = r.data ?? const {};
      final s = body['status'];
      if (s is Map) return TelegramStatus.fromJson(Map<String, dynamic>.from(s));
      return null;
    } catch (e) {
      _log('status', e);
      return null;
    }
  }

  static Future<({bool ok, String? message, String? botUsername})> connectBot({
    required String adminId,
    required String adminUsername,
    required String botToken,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/telegram/connect',
        data: {
          'adminId': adminId,
          'adminUsername': adminUsername,
          'botToken': botToken,
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        botUsername: body['botUsername']?.toString(),
      );
    } on DioException catch (e) {
      _log('connect', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'فشل الربط', botUsername: null);
    } catch (e) {
      _log('connect', e);
      return (ok: false, message: 'فشل الربط', botUsername: null);
    }
  }

  static Future<bool> disconnectBot(String adminId) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/telegram/disconnect',
        data: {'adminId': adminId},
      );
      return r.data?['success'] == true;
    } catch (e) {
      _log('disconnect', e);
      return false;
    }
  }

  static Future<List<TelegramBinding>> listBindings(String adminId) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/telegram/bindings/$adminId',
      );
      final list = r.data?['bindings'];
      if (list is! List) return const [];
      final out = <TelegramBinding>[];
      for (final v in list) {
        if (v is Map) {
          final b = TelegramBinding.fromJson(Map<String, dynamic>.from(v));
          if (b != null) out.add(b);
        }
      }
      return out;
    } catch (e) {
      _log('bindings', e);
      return const [];
    }
  }

  static Future<bool> unbind(String adminId, String idx) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/telegram/bindings/$adminId/$idx',
      );
      return r.data?['success'] == true;
    } catch (e) {
      _log('unbind', e);
      return false;
    }
  }

  static Future<({String? link, String? botUsername, String? message})>
      generateDeepLink(String adminId, String idx) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/telegram/deep-link/$adminId/$idx',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return (
          link: null,
          botUsername: null,
          message: body['message']?.toString(),
        );
      }
      return (
        link: body['link']?.toString(),
        botUsername: body['botUsername']?.toString(),
        message: null,
      );
    } on DioException catch (e) {
      _log('deep-link', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (link: null, botUsername: null, message: msg ?? 'فشل التوليد');
    } catch (e) {
      _log('deep-link', e);
      return (link: null, botUsername: null, message: 'فشل التوليد');
    }
  }

  static Future<({bool ok, String? message})>
      sendLinkViaWa(String adminId, String idx) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/telegram/send-link-via-wa/$adminId/$idx',
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString() ??
            (body['sent'] is Map
                ? (body['sent'] as Map)['message']?.toString()
                : null),
      );
    } on DioException catch (e) {
      _log('send-link-via-wa', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'فشل الإرسال');
    } catch (e) {
      _log('send-link-via-wa', e);
      return (ok: false, message: 'فشل الإرسال');
    }
  }

  static Future<BroadcastLinksPreview?> previewBroadcastLinks(
      String adminId) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/telegram/broadcast-links/$adminId',
        data: {'dryRun': true},
      );
      final body = r.data ?? const {};
      if (body is Map) {
        return BroadcastLinksPreview.fromJson(Map<String, dynamic>.from(body));
      }
      return null;
    } catch (e) {
      _log('broadcast-links dry', e);
      return null;
    }
  }

  static Future<({bool ok, int enqueued, String? message})>
      sendBroadcastLinks(String adminId) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/telegram/broadcast-links/$adminId',
        data: {},
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        enqueued: (body['enqueued'] as num?)?.toInt() ?? 0,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('broadcast-links send', e);
      return (ok: false, enqueued: 0, message: 'فشل الإرسال');
    }
  }

  static Future<BroadcastPreview?> previewBroadcast(
      String adminId, String message) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/telegram/broadcast',
        data: {
          'adminId': adminId,
          'message': message.trim(),
          'dryRun': true,
        },
      );
      final body = r.data ?? const {};
      if (body is Map) {
        return BroadcastPreview.fromJson(Map<String, dynamic>.from(body));
      }
      return null;
    } catch (e) {
      _log('broadcast dry', e);
      return null;
    }
  }

  static Future<({bool ok, int enqueued, String? message})> sendBroadcast(
    String adminId,
    String message,
  ) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/telegram/broadcast',
        data: {
          'adminId': adminId,
          'message': message.trim(),
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        enqueued: (body['enqueued'] as num?)?.toInt() ?? 0,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('broadcast send', e);
      return (ok: false, enqueued: 0, message: 'فشل الإرسال');
    }
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
        'telegram/$endpoint → ${err.response?.statusCode} ${err.message}',
      );
    } else {
      debugPrint('telegram/$endpoint → $err');
    }
  }
}
