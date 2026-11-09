import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';
import 'company_route.dart';

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
  static Future<({bool ok, int? queued, int? excludedHighRisk, String? message, String? code})>
      broadcast({
    required MessageIntent intent,
    required String message,
    List<String>? targetUsernames,
    // «تحديد المدينين» (٩ نوفمبر): يُرسَل مع بصمة معاينته وحدها — الخادم يرفض الفلتر بلا بصمة (422) أو إن تغيّرت القائمة (409).
    DebtFilter? debtFilter,
    String? audienceKey,
    int? audienceCount,
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
      if (debtFilter != null && debtFilter.active) {
        body['debtFilter'] = debtFilter.toJson();
        if (audienceKey != null) body['audienceKey'] = audienceKey;
        if (audienceCount != null) body['audienceCount'] = audienceCount;
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
            code: null,
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
          code: data['code']?.toString(),
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
      // «تحديد المدينين»: من لم يُعرف عمر دينه لم يُشمل — الخادم يقوله في نصّه، فيُعرض كما هو بدل الصمت
      final df = sum['debtFilter'] is Map ? (sum['debtFilter'] as Map) : null;
      final unknownAge = df == null ? 0 : _toInt(df['unknownAge']);
      return (
        ok: true,
        queued: queued == null ? null : _toInt(queued),
        excludedHighRisk: excluded == null ? null : _toInt(excluded),
        // الحساب الكبير «عام»: الخادم بدأ التجهيز في الخلفيّة (pending) — رسالته تُعرض كما هي، والنتيجة بإشعار
        message: data['pending'] == true || unknownAge > 0 ? data['message']?.toString() : null,
        code: null,
      );
    } on DioException catch (e) {
      _log('broadcast', e);
      final d = e.response?.data is Map ? (e.response!.data as Map) : null;
      return (
        ok: false,
        queued: null,
        excludedHighRisk: null,
        message: d?['message']?.toString() ?? 'خطأ في الشبكة',
        code: d?['code']?.toString(),
      );
    } catch (e) {
      _log('broadcast', e);
      return (ok: false, queued: null, excludedHighRisk: null, message: e.toString(), code: null);
    }
  }

  /// GET /api/whatsapp/broadcast/debt-filter — ما يدعمه الخادم من «تحديد المدينين» لهذا الحساب. null ⇒ لا لوحة (خادمٌ أقدم أو
  /// بلا صلاحيّة أو تعذّر): الشاشة كما كانت.
  static Future<DebtFilterCapability?> debtFilterCapability() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/whatsapp/broadcast/debt-filter');
      final d = r.data?['debtFilter'];
      if (r.statusCode != 200 || d is! Map) return null;
      return DebtFilterCapability.fromJson(Map<String, dynamic>.from(d));
    } catch (e) {
      _log('debtFilterCapability', e);
      return null;
    }
  }

  /// POST /api/whatsapp/broadcast {dryRun:true} — من يطابق الطلب نفسه (بالتحديد والمختارين) بلا إرسال: العدد والقائمة والبصمة.
  static Future<({BroadcastPreview? preview, String? message, String? code})> preview({
    required MessageIntent intent,
    DebtFilter? debtFilter,
    List<String>? targetUsernames,
  }) async {
    try {
      final body = <String, dynamic>{
        'type': intent.apiValue,
        'message': '',
        'dryRun': true,
        if (debtFilter != null && debtFilter.active) 'debtFilter': debtFilter.toJson(),
        if (targetUsernames != null && targetUsernames.isNotEmpty) 'targetUsernames': targetUsernames,
      };
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/whatsapp/broadcast', data: body);
      final data = r.data ?? const {};
      // الحساب الكبير: «نحسب…» — ليست خطأً؛ الشاشة تعيد السؤال حتى تجهز
      if ((r.statusCode == 202 || data['pending'] == true) && data['success'] != false) {
        return (preview: BroadcastPreview.pendingOf(data['message']?.toString()), message: null, code: null);
      }
      if (r.statusCode != 200 || data['success'] == false || data['dryRun'] != true) {
        return (preview: null, message: data['message']?.toString() ?? 'تعذّرت المعاينة — لم يُرسَل شيء', code: data['code']?.toString());
      }
      return (preview: BroadcastPreview.fromJson(data), message: null, code: null);
    } on DioException catch (e) {
      _log('preview', e);
      final d = e.response?.data is Map ? (e.response!.data as Map) : null;
      return (preview: null, message: d?['message']?.toString() ?? 'خطأ في الشبكة', code: d?['code']?.toString());
    } catch (e) {
      _log('preview', e);
      return (preview: null, message: 'تعذّرت المعاينة', code: null);
    }
  }

  /// POST /api/telegram/broadcast {dryRun:true, debtFilter} — «إرسال عام» تلغرام بالتحديد: من يطابق من المربوطين المدينين
  /// بالاسم والدين والعمر وبصمتهم. message اختياريّة للمعاينة (الشرائح وحدها).
  static Future<({BroadcastPreview? preview, String? message, String? code})> telegramPreview({
    required String adminId,
    required DebtFilter debtFilter,
    String message = '',
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/telegram/broadcast', data: {
        'adminId': adminId,
        if (message.trim().isNotEmpty) 'message': message.trim(),
        'dryRun': true,
        'debtFilter': debtFilter.toJson(),
      });
      final data = r.data ?? const {};
      if (r.statusCode != 200 || data['success'] == false || data['dryRun'] != true) {
        return (preview: null, message: data['message']?.toString() ?? 'تعذّرت المعاينة — لم يُرسَل شيء', code: data['code']?.toString());
      }
      return (preview: BroadcastPreview.fromTelegramJson(data), message: null, code: null);
    } on DioException catch (e) {
      _log('telegramPreview', e);
      final d = e.response?.data is Map ? (e.response!.data as Map) : null;
      return (preview: null, message: d?['message']?.toString() ?? 'خطأ في الشبكة', code: d?['code']?.toString());
    } catch (e) {
      _log('telegramPreview', e);
      return (preview: null, message: 'تعذّرت المعاينة', code: null);
    }
  }

  /// POST /api/telegram/broadcast بالتحديد — يحمل بصمة المعاينة؛ تغيّرت القائمة ⇒ 409 بلا إرسال (code BROADCAST_AUDIENCE_CHANGED).
  static Future<({bool ok, int enqueued, String? message, String? code})> telegramSend({
    required String adminId,
    required String message,
    required DebtFilter debtFilter,
    required String audienceKey,
    required int audienceCount,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/telegram/broadcast', data: {
        'adminId': adminId,
        'message': message.trim(),
        'debtFilter': debtFilter.toJson(),
        'audienceKey': audienceKey,
        'audienceCount': audienceCount,
      });
      final data = r.data ?? const {};
      return (
        ok: r.statusCode == 200 && data['success'] == true,
        enqueued: _toInt(data['enqueued']),
        message: data['message']?.toString(),
        code: data['code']?.toString(),
      );
    } on DioException catch (e) {
      _log('telegramSend', e);
      final d = e.response?.data is Map ? (e.response!.data as Map) : null;
      return (ok: false, enqueued: 0, message: d?['message']?.toString() ?? 'فشل الإرسال', code: d?['code']?.toString());
    } catch (e) {
      _log('telegramSend', e);
      return (ok: false, enqueued: 0, message: 'فشل الإرسال', code: null);
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
      // «كل الشركات» (٨ نوفمبر): قسمٌ مفتوحٌ بشركةٍ أخرى ⇒ مديرها (الخادم يطابق :adminId بجلستها)
      final adminId = CompanyRoute.adminIdFor('/api/whatsapp/message-logs') ?? await AuthStorage.readAdminId();
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

  // ── حملات البثّ (٢٧ أكتوبر): قائمة + إيقاف/استئناف/حذف لكلّ حملة ──

  /// GET /api/whatsapp/broadcasts/:adminId — حملات الوكيل (كلّ بثٍّ أرسله، بأعداده وحالته).
  static Future<({bool ok, List<BroadcastCampaign> campaigns, String? message})> listCampaigns() async {
    try {
      final adminId = CompanyRoute.adminIdFor('/api/whatsapp/broadcasts') ?? await AuthStorage.readAdminId();
      if (adminId == null || adminId.isEmpty) {
        return (ok: false, campaigns: const <BroadcastCampaign>[], message: null);
      }
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/whatsapp/broadcasts/$adminId');
      final list = (r.data ?? const {})['campaigns'];
      final out = <BroadcastCampaign>[];
      if (list is List) {
        for (final m in list) {
          if (m is Map) {
            final c = BroadcastCampaign.fromJson(Map<String, dynamic>.from(m));
            if (c != null) out.add(c);
          }
        }
      }
      return (ok: true, campaigns: out, message: null);
    } on DioException catch (e) {
      _log('listCampaigns', e);
      final m = e.response?.data is Map ? (e.response!.data as Map)['message']?.toString() : null;
      return (ok: false, campaigns: const <BroadcastCampaign>[], message: m ?? 'تعذّر جلب الحملات');
    } catch (e) {
      _log('listCampaigns', e);
      return (ok: false, campaigns: const <BroadcastCampaign>[], message: e.toString());
    }
  }

  /// إيقاف مؤقّت / استئناف / حذف حملةٍ بمعرّفها. action ∈ {pause, resume, delete}.
  static Future<({bool ok, int affected, String? message})> campaignAction(String batchId, String action) async {
    try {
      final adminId = CompanyRoute.adminIdFor('/api/whatsapp/broadcast') ?? await AuthStorage.readAdminId();
      if (adminId == null || adminId.isEmpty) return (ok: false, affected: 0, message: null);
      final path = '/api/whatsapp/broadcast/${Uri.encodeComponent(batchId)}${action == 'delete' ? '' : '/$action'}';
      final body = {'adminId': adminId};
      final Response<Map<String, dynamic>> r = action == 'delete'
          ? await ApiClient.dio.delete<Map<String, dynamic>>(path, data: body)
          : await ApiClient.dio.post<Map<String, dynamic>>(path, data: body);
      final data = r.data ?? const {};
      return (
        ok: data['success'] != false,
        affected: (data['affected'] is num) ? (data['affected'] as num).toInt() : 0,
        message: data['message']?.toString(),
      );
    } on DioException catch (e) {
      _log('campaignAction', e);
      final m = e.response?.data is Map ? (e.response!.data as Map)['message']?.toString() : null;
      return (ok: false, affected: 0, message: m ?? 'خطأ في الشبكة');
    } catch (e) {
      _log('campaignAction', e);
      return (ok: false, affected: 0, message: e.toString());
    }
  }
}

/// حملة بثٍّ واحدة (صفوف طابورٍ تحمل نفس batch_id) — للعرض والتحكّم.
class BroadcastCampaign {
  const BroadcastCampaign({
    required this.batchId,
    required this.sample,
    required this.total,
    required this.sent,
    required this.pending,
    required this.processing,
    required this.failed,
    required this.cancelled,
    required this.paused,
    required this.telegram,
    this.createdAt,
  });

  final String batchId;

  /// عيّنة نصّ الرسالة (أوّل ١٦٠ حرفاً) — ليميّزها الوكيل.
  final String sample;
  final int total;
  final int sent;
  final int pending;
  final int processing;
  final int failed;
  final int cancelled;

  /// الحملة موقوفةٌ مؤقّتاً (لها معلّقٌ paused).
  final bool paused;

  /// كم من رسائلها عبر تلغرام.
  final int telegram;
  final DateTime? createdAt;

  /// ما زالت تُرسِل (فيها معلّقٌ أو قيد المعالجة) — تُعرض لها أزرار التحكّم.
  bool get active => pending > 0 || processing > 0;

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  static BroadcastCampaign? fromJson(Map<String, dynamic> j) {
    final id = j['batch_id']?.toString();
    if (id == null || id.isEmpty) return null;
    return BroadcastCampaign(
      batchId: id,
      sample: (j['sample'] ?? '').toString(),
      total: _int(j['total']),
      sent: _int(j['sent']),
      pending: _int(j['pending']),
      processing: _int(j['processing']),
      failed: _int(j['failed']),
      cancelled: _int(j['cancelled']),
      paused: j['paused'] == true || j['paused'] == 1,
      telegram: _int(j['telegram']),
      createdAt: DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal(),
    );
  }
}

/// «تحديد المدينين» في التبليغات (المالك ٩ نوفمبر: «تحديد نطاقة جلب اليوزرية حسب اقدم مده دين وسقف من والى الدين … اما المده او
/// المبلغ او الاثنين»). العمر = عمر **أقدم دينٍ لم يُسدَّد** (قراره بمثاله: ٣٥ ألفاً منذ ٩٠ يوماً + ٣٥ ألفاً قبل يومين ⇒ ٩٠ يوماً) —
/// يحسبه الخادم وحده من دفتر حركات الدين؛ التطبيق يرسل الحدود ويعرض ما يردّه.
@immutable
class DebtFilter {
  const DebtFilter({this.minAgeDays, this.minAmount, this.maxAmount});
  final int? minAgeDays;
  final int? minAmount;
  final int? maxAmount;

  static const none = DebtFilter();

  bool get active => minAgeDays != null || minAmount != null || maxAmount != null;

  DebtFilter copyWith({int? Function()? minAgeDays, int? Function()? minAmount, int? Function()? maxAmount}) => DebtFilter(
        minAgeDays: minAgeDays != null ? minAgeDays() : this.minAgeDays,
        minAmount: minAmount != null ? minAmount() : this.minAmount,
        maxAmount: maxAmount != null ? maxAmount() : this.maxAmount,
      );

  /// جسم الطلب: أرقامٌ وحدها، والغائب لا يُرسَل.
  Map<String, int> toJson() => {
        if (minAgeDays != null) 'minAgeDays': minAgeDays!,
        if (minAmount != null) 'minAmount': minAmount!,
        if (maxAmount != null) 'maxAmount': maxAmount!,
      };

  /// خطأٌ يُرى قبل الإرسال (الخادم يردّه 422 أيضاً) — null حين سليم.
  String? problem({int maxAgeDays = 3650}) {
    final d = minAgeDays;
    if (d != null && (d < 1 || d > maxAgeDays)) return 'عمر الدين بين 1 و$maxAgeDays يوماً';
    if (maxAmount != null && maxAmount! <= 0) return 'الحدّ الأعلى أكبر من صفر';
    if (minAmount != null && maxAmount != null && minAmount! > maxAmount!) return 'الحدّ الأدنى أكبر من الأعلى';
    return null;
  }

  /// الجملة التي يقرؤها الوكيل: «أقدم دين 30 يوماً فأكثر · من 50,000 إلى 100,000 د.ع».
  String describe() {
    final parts = <String>[];
    if (minAgeDays != null) parts.add('أقدم دين ${arDaysCount(minAgeDays!)} فأكثر');
    String f(int v) => _thousands(v);
    if (minAmount != null && maxAmount != null) {
      parts.add('من ${f(minAmount!)} إلى ${f(maxAmount!)} د.ع');
    } else if (minAmount != null) {
      parts.add('${f(minAmount!)} د.ع فأكثر');
    } else if (maxAmount != null) {
      parts.add('حتى ${f(maxAmount!)} د.ع');
    }
    return parts.join(' · ');
  }

  @override
  bool operator ==(Object other) =>
      other is DebtFilter && other.minAgeDays == minAgeDays && other.minAmount == minAmount && other.maxAmount == maxAmount;

  @override
  int get hashCode => Object.hash(minAgeDays, minAmount, maxAmount);
}

/// «يوم» · «يومين» · «5 أيام» · «30 يوماً» — كالويب والخادم.
String arDaysCount(int n) {
  if (n == 1) return 'يوم';
  if (n == 2) return 'يومين';
  final r = n % 100;
  if (r >= 3 && r <= 10) return '$n أيام';
  if (r <= 2) return '$n يوم';
  return '$n يوماً';
}

String _thousands(num v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// ما يدعمه الخادم لهذا الحساب: المبلغ دائماً، والعمر حيث لديونه دفتر (وإلّا سببه بكلماتٍ يفهمها الوكيل).
@immutable
class DebtFilterCapability {
  const DebtFilterCapability({
    required this.age,
    required this.presets,
    this.ageNote,
    this.maxAgeDays = 3650,
    this.telegram = false,
    this.bigAsync = false,
  });
  final bool age;
  final String? ageNote;
  final List<int> presets;
  final int maxAgeDays;

  /// «إرسال عام» تلغرام يقبل التحديد (الخادم version ≥ 3).
  final bool telegram;

  /// الحساب الكبير (≥ ٥٠٠٠): المعاينة تُحسب في الخلفيّة — الخادم يردّ «نحسب…» والشاشة تعيد السؤال (bigPreview: 'async').
  final bool bigAsync;

  static DebtFilterCapability? fromJson(Map<String, dynamic> j) {
    if (j['amount'] != true || j['presets'] is! List) return null;
    return DebtFilterCapability(
      age: j['age'] == true,
      ageNote: j['ageNote']?.toString(),
      presets: [for (final p in j['presets'] as List) if (_toInt(p) > 0) _toInt(p)],
      maxAgeDays: _toInt(j['maxAgeDays']) > 0 ? _toInt(j['maxAgeDays']) : 3650,
      telegram: j['telegram'] == true,
      bigAsync: j['bigPreview'] == 'async',
    );
  }
}

@immutable
class BroadcastPreviewRow {
  const BroadcastPreviewRow({required this.username, this.name, required this.debt, this.days, this.legacy = false});
  final String username;
  final String? name;
  final num debt;

  /// عمر أقدم دينٍ لم يُسدَّد بالأيّام — null لـ«دين قديم» أو المجهول.
  final int? days;

  /// «دين قديم»: جزءٌ من دينه أقدم من سجلّاتنا (استيراد/ترحيل/إضافةٌ من لوحة الساس) — أقدم من أيّ مدّة.
  final bool legacy;
}

/// ردّ المعاينة: من يطابق (المشمولون قبل الدمج وحارس الحظر) وكم سيصل، وبصمة القائمة التي يحملها الإرسال.
@immutable
class BroadcastPreview {
  const BroadcastPreview({
    required this.count,
    required this.audience,
    required this.excludedHighRisk,
    required this.deduped,
    required this.rows,
    required this.truncated,
    required this.audienceKey,
    this.missing = 0,
    this.partial = false,
    this.unknownAge = 0,
    this.legacy = 0,
    this.ageUnsupported = false,
    this.pending = false,
    this.pendingMessage,
    this.notFound = 0,
    this.notDebtor = 0,
    this.blocked = 0,
    this.totalBound = 0,
  });

  /// الحساب الكبير: الخادم ما زال يحسب (202) — تُعاد المعاينة بعد ثوانٍ.
  const BroadcastPreview.pendingOf(this.pendingMessage)
      : pending = true,
        count = 0,
        audience = 0,
        excludedHighRisk = 0,
        deduped = 0,
        rows = const [],
        truncated = false,
        audienceKey = '',
        missing = 0,
        partial = false,
        unknownAge = 0,
        legacy = 0,
        ageUnsupported = false,
        notFound = 0,
        notDebtor = 0,
        blocked = 0,
        totalBound = 0;

  final bool pending;
  final String? pendingMessage;

  /// تلغرام: مربوطون لم نجدهم في قائمة الشركة (لم يُشملوا) · مربوطون بلا دين · حظروا البوت · كلّ المربوطين.
  final int notFound;
  final int notDebtor;
  final int blocked;
  final int totalBound;
  final int count;
  final int audience;
  final int excludedHighRisk;
  final int deduped;
  final List<BroadcastPreviewRow> rows;
  final bool truncated;
  final String audienceKey;
  final int missing;
  final bool partial;
  final int unknownAge;
  final int legacy;
  final bool ageUnsupported;

  static BroadcastPreview fromJson(Map<String, dynamic> j) {
    final df = j['debtFilter'] is Map ? Map<String, dynamic>.from(j['debtFilter'] as Map) : const <String, dynamic>{};
    final rows = <BroadcastPreviewRow>[];
    if (j['rows'] is List) {
      for (final r in j['rows'] as List) {
        if (r is! Map) continue;
        final name = r['name']?.toString().trim();
        rows.add(BroadcastPreviewRow(
          username: (r['username'] ?? '').toString(),
          name: name == null || name.isEmpty ? null : name,
          debt: r['debt'] is num ? r['debt'] as num : num.tryParse('${r['debt']}') ?? 0,
          days: r['days'] is num ? (r['days'] as num).toInt() : null,
          legacy: r['legacy'] == true,
        ));
      }
    }
    return BroadcastPreview(
      count: _toInt(j['count']),
      audience: _toInt(j['audience']),
      excludedHighRisk: _toInt(j['excludedHighRisk']),
      deduped: _toInt(j['deduped']),
      rows: rows,
      truncated: j['truncated'] == true,
      audienceKey: (j['audienceKey'] ?? '').toString(),
      missing: _toInt(j['missing']),
      partial: j['partial'] == true,
      unknownAge: _toInt(df['unknownAge']),
      legacy: _toInt(df['legacy']),
      ageUnsupported: df['ageUnsupported'] == true,
      notFound: _toInt(df['notFound']),
      notDebtor: _toInt(df['notDebtor']),
      blocked: _toInt(j['blocked']),
      totalBound: _toInt(j['totalBound']),
    );
  }

  /// معاينة «إرسال عام» تلغرام: eligible = من يطابق ويصله (لا دمج أرقام ولا حارس حظر في تلغرام).
  static BroadcastPreview fromTelegramJson(Map<String, dynamic> j) {
    final eligible = _toInt(j['eligible']);
    return BroadcastPreview.fromJson({...j, 'count': eligible, 'audience': eligible, 'excludedHighRisk': 0, 'deduped': 0});
  }
}

/// المتغيّرات المتاحة في محرّر الرسالة — تُستبدَل server-side.
class BroadcastVariables {
  BroadcastVariables._();
  static const List<({String token, String label})> all = [
    (token: '{subscriber_name}', label: 'اسم المشترك'),
    (token: '{firstname}', label: 'الاسم الأول'),
    (token: '{username}', label: 'اسم المستخدم'),
    // رمز وكيل المُرسِل — الخادم يملؤه مرّةً للبثّ كلّه (وسيط البوّابة §10).
    (token: '{agent_code}', label: 'رمز الوكيل'),
    (token: '{package_name}', label: 'الباقة'),
    // اسم الساس كما هو — {package_name} يأخذ اسمها في «بوابة المشترك» إن كُتب
    (token: '{sas_package_name}', label: 'الباقة (الساس)'),
    (token: '{expiry_date}', label: 'تاريخ الانتهاء'),
    (token: '{days_remaining}', label: 'الأيام المتبقّية'),
    (token: '{debt_amount}', label: 'مبلغ الدين'),
    (token: '{phone}', label: 'الهاتف'),
  ];
}

void _log(String tag, Object e) {
  if (kDebugMode) debugPrint('[BroadcastApi] $tag: $e');
}
