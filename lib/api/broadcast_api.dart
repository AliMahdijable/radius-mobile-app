import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';

/// نوع رسالة (intent) — مطابق للـweb + backend.
enum MessageIntent {
  general,
  debtors,
  expired,
  expiring,
}

extension MessageIntentX on MessageIntent {
  String get apiValue {
    switch (this) {
      case MessageIntent.general:
        return 'general';
      case MessageIntent.debtors:
        return 'debtors';
      case MessageIntent.expired:
        return 'expired';
      case MessageIntent.expiring:
        return 'expiring';
    }
  }

  /// الرسالة اختياريّة لهذا النوع (backend يستعمل قالب افتراضي).
  bool get messageOptional =>
      this == MessageIntent.debtors || this == MessageIntent.expiring;
}

/// سجل رسالة من whatsapp_message_queue أو whatsapp_send_logs.
class MessageLog {
  const MessageLog({
    required this.id,
    required this.status,
    required this.createdAt,
    this.recipientPhone,
    this.recipientUsername,
    this.recipientName,
    this.errorMessage,
    this.messageType,
    this.messagePreview,
    this.source,
    this.channel,
  });

  final int id;

  /// sent | pending | failed | cancelled | processing
  final String status;
  final String createdAt;
  final String? recipientPhone;
  final String? recipientUsername;
  final String? recipientName;
  final String? errorMessage;
  final String? messageType;
  final String? messagePreview;

  /// queue | send_logs
  final String? source;

  /// القناة الفعليّة/المطلوبة: auto | whatsapp | telegram.
  /// send_logs يعطي القناة اللي مرّت فعلاً، queue قد يكون 'auto' لسّه ما تحدّدت.
  final String? channel;

  bool get isSent => status == 'sent';
  bool get isPending => status == 'pending' || status == 'processing';
  bool get isFailed => status == 'failed';
  bool get isCancelled => status == 'cancelled';

  static MessageLog? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final idInt = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (idInt == null) return null;
    // recipient_firstname/lastname يجيان من إثراء SAS4 على backend — نبني
    // recipientName منهما، وإلا نأخذ recipient_name المستخرَج من body.
    final fn = j['recipient_firstname']?.toString().trim();
    final ln = j['recipient_lastname']?.toString().trim();
    final arabicName = [fn, ln]
        .where((p) => p != null && p.isNotEmpty)
        .map((p) => p!)
        .join(' ');
    return MessageLog(
      id: idInt,
      status: (j['status'] ?? 'pending').toString(),
      createdAt: (j['created_at'] ?? '').toString(),
      recipientPhone: j['recipient_phone']?.toString(),
      recipientUsername: j['recipient_username']?.toString(),
      recipientName:
          arabicName.isNotEmpty ? arabicName : j['recipient_name']?.toString(),
      errorMessage: j['error_message']?.toString(),
      messageType: j['message_type']?.toString(),
      messagePreview: j['message_preview']?.toString(),
      source: j['source']?.toString(),
      channel: j['channel']?.toString(),
    );
  }
}

class LogsStats {
  const LogsStats({
    required this.total,
    required this.sent,
    required this.pending,
    required this.failed,
    this.cancelled = 0,
    this.processing = 0,
  });

  final int total;
  final int sent;
  final int pending;
  final int failed;
  final int cancelled;
  final int processing;

  static LogsStats fromJson(Map<String, dynamic> j) => LogsStats(
        total: _toInt(j['total']),
        sent: _toInt(j['sent']),
        pending: _toInt(j['pending']),
        failed: _toInt(j['failed']),
        cancelled: _toInt(j['cancelled']),
        processing: _toInt(j['processing']),
      );
}

// 2026-07-13: الـbackend (server.js:5228) يرجع stats كنصوص لأن SUM على
// tinyint في MySQL يجيء كـchar. `x as num?` يرمي TypeError على String —
// كان يخلي fromJson يفشل صامتاً في الـcatch، فتظهر الشاشة فارغة رغم أن
// الـrows موجودة. `_toInt` يقبل int/num/String/null.
int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

/// Broadcast API — يستهلك backend `/api/whatsapp/*`.
class BroadcastApi {
  BroadcastApi._();

  /// أقصى حجم صورة نسمح به قبل تحويلها لـbase64. الصورة تُنسخ
  /// لكل مستقبل في `whatsapp_message_queue.media_data` (LONGTEXT)،
  /// فرفع 500 مستقبل بصورة 3MB = 1.5GB بالطابور. نضغطها للحدود
  /// ونرفض الأكبر.
  static const int maxImageBytes = 300 * 1024; // 300KB binary

  /// POST /api/whatsapp/broadcast
  /// نتيجة: عدد الرسائل التي دخلت الطابور.
  ///
  /// [imageBytes] اختياريّة — صورة تُرسل كمرفق (caption = نص الرسالة).
  /// يجب أن تكون ≤ [maxImageBytes] بعد الضغط، وإلا نرمي [ArgumentError]
  /// قبل الشبكة (توفيراً للـbandwidth). Backend عنده نفس السقف كحارس ثانٍ.
  static Future<({bool ok, int? queued, int? excludedHighRisk, String? message})>
      broadcast({
    required MessageIntent intent,
    required String message,
    List<String>? targetUsernames,
    Uint8List? imageBytes,
    String? imageMime,
    String? imageFilename,
    // 2026-08-26 (tg parity): 'auto' | 'whatsapp' | 'telegram'.
    // 'auto' = يحترم ربط المشترك، 'telegram' = يفلتر المربوطين فقط، 'whatsapp' = يجبر واتساب.
    String? forceChannel,
    // 2026-09-03: الخادم يستبعد الدرجة الحرجة افتراضيّاً. true يُعيدهم
    // بعد أن يكون المدير رأى عددهم في حوار التأكيد.
    bool includeHighRisk = false,
  }) async {
    try {
      final body = <String, dynamic>{
        'message': message,
        'type': intent.apiValue,
        if (includeHighRisk) 'includeHighRisk': true,
      };
      if (targetUsernames != null && targetUsernames.isNotEmpty) {
        body['targetUsernames'] = targetUsernames;
      }
      if (forceChannel == 'whatsapp' || forceChannel == 'telegram') {
        body['forceChannel'] = forceChannel;
      }
      if (imageBytes != null && imageBytes.isNotEmpty) {
        if (imageBytes.length > maxImageBytes) {
          return (
            ok: false,
            queued: null,
            excludedHighRisk: null,
            message:
                'الصورة أكبر من الحدّ (${(maxImageBytes / 1024).round()}KB).',
          );
        }
        body['imageBase64'] = base64Encode(imageBytes);
        body['imageMime'] = imageMime ?? 'image/jpeg';
        body['imageFilename'] = imageFilename ?? 'broadcast.jpg';
      }
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/broadcast',
        data: body,
      );
      final data = r.data ?? const {};
      if (data['success'] == false) {
        return (
          ok: false,
          queued: null,
          excludedHighRisk: null,
          message: data['message']?.toString() ?? 'فشل الإرسال',
        );
      }
      // ⚠️ الخادم يضع العدّادات في `summary` — والقراءة من الجذر وحده
      // كانت تُرجع null دائماً، فيعرض التطبيق عدد المستهدَفين بدل عدد
      // ما دخل الطابور فعلاً.
      final sum = data['summary'] is Map
          ? (data['summary'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      final queued = sum['queued'] ??
          data['queued'] ?? data['totalQueued'] ?? data['count'];
      final excluded = sum['excludedHighRisk'];
      return (
        ok: true,
        queued: queued == null ? null : _toInt(queued),
        excludedHighRisk: excluded == null ? null : _toInt(excluded),
        message: null,
      );
    } on DioException catch (e) {
      _log('broadcast', e);
      final m = e.response?.data is Map
          ? (e.response!.data as Map)['message']?.toString()
          : null;
      return (ok: false, queued: null, excludedHighRisk: null, message: m ?? 'خطأ في الشبكة');
    } catch (e) {
      _log('broadcast', e);
      return (ok: false, queued: null, excludedHighRisk: null, message: e.toString());
    }
  }

  /// POST /api/whatsapp/broadcast/retry-failed
  /// يعيد جدولة الرسائل الفاشلة من آخر [sinceHours] ساعة.
  static Future<({bool ok, String? message})> retryFailed({
    int sinceHours = 24,
    bool includeSuppressed = false,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/broadcast/retry-failed',
        data: {
          'sinceHours': sinceHours,
          'includeSuppressed': includeSuppressed,
        },
      );
      final data = r.data ?? const {};
      return (
        ok: data['success'] != false,
        message: data['message']?.toString(),
      );
    } on DioException catch (e) {
      _log('retryFailed', e);
      final m = e.response?.data is Map
          ? (e.response!.data as Map)['message']?.toString()
          : null;
      return (ok: false, message: m ?? 'خطأ في الشبكة');
    } catch (e) {
      _log('retryFailed', e);
      return (ok: false, message: e.toString());
    }
  }

  /// GET /api/whatsapp/message-logs/:adminId — سجل موحّد
  /// (whatsapp_message_queue + whatsapp_send_logs). يدعم:
  ///  - فلتر الحالة (all/sent/pending/processing/failed/cancelled)
  ///  - فلتر النوع (all/broadcast/debt_reminder/expiry_warning/…)
  ///  - بحث نصّي (username | phone | body)
  ///  - نافذة تاريخ (dateFrom/dateTo — YYYY-MM-DD)
  ///  - pagination عبر page/limit
  static Future<
      ({
        bool ok,
        List<MessageLog> messages,
        LogsStats? stats,
        int total,
        bool hasMore,
      })> messageLogs({
    String? statusFilter,
    String? typeFilter,
    String? search,
    String? dateFrom,
    String? dateTo,
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final adminId = await AuthStorage.readAdminId();
      if (adminId == null || adminId.isEmpty) {
        return (
          ok: false,
          messages: <MessageLog>[],
          stats: null,
          total: 0,
          hasMore: false,
        );
      }
      final params = <String, dynamic>{
        'page': '$page',
        'limit': '$limit',
      };
      if (statusFilter != null && statusFilter != 'all') {
        params['status'] = statusFilter;
      }
      if (typeFilter != null && typeFilter != 'all') {
        params['type'] = typeFilter;
      }
      if (search != null && search.trim().isNotEmpty) {
        params['search'] = search.trim();
      }
      if (dateFrom != null) params['dateFrom'] = dateFrom;
      if (dateTo != null) params['dateTo'] = dateTo;

      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/whatsapp/message-logs/$adminId',
        queryParameters: params,
      );
      final data = r.data ?? const {};
      final list = data['messages'];
      final statsRaw = data['stats'];
      final messages = <MessageLog>[];
      if (list is List) {
        for (final m in list) {
          if (m is Map) {
            final parsed = MessageLog.fromJson(Map<String, dynamic>.from(m));
            if (parsed != null) messages.add(parsed);
          }
        }
      }
      final stats = statsRaw is Map
          ? LogsStats.fromJson(Map<String, dynamic>.from(statsRaw))
          : null;
      final total = _toInt(data['total']) == 0
          ? (stats?.total ?? messages.length)
          : _toInt(data['total']);
      return (
        ok: data['success'] != false,
        messages: messages,
        stats: stats,
        total: total,
        hasMore: messages.length >= limit,
      );
    } on DioException catch (e) {
      _log('messageLogs', e);
      return (
        ok: false,
        messages: <MessageLog>[],
        stats: null,
        total: 0,
        hasMore: false,
      );
    } catch (e) {
      _log('messageLogs', e);
      return (
        ok: false,
        messages: <MessageLog>[],
        stats: null,
        total: 0,
        hasMore: false,
      );
    }
  }
}

/// المتغيّرات المتاحة في محرّر الرسالة — تُستبدَل server-side.
class BroadcastVariables {
  BroadcastVariables._();
  static const List<({String token, String label})> all = [
    (token: '{subscriber_name}', label: 'اسم المشترك'),
    (token: '{firstname}', label: 'الاسم الأول'),
    (token: '{username}', label: 'اسم المستخدم'),
    (token: '{package_name}', label: 'الباقة'),
    (token: '{expiry_date}', label: 'تاريخ الانتهاء'),
    (token: '{days_remaining}', label: 'الأيام المتبقّية'),
    (token: '{debt_amount}', label: 'مبلغ الدين'),
    (token: '{phone}', label: 'الهاتف'),
  ];
}

void _log(String tag, Object e) {
  if (kDebugMode) debugPrint('[BroadcastApi] $tag: $e');
}
