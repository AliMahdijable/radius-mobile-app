import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../core/util/format.dart';
import '../models/subscriber.dart';
import '../models/whatsapp_schedule.dart';
import '../services/auth_storage.dart';
import '../services/manual_wa_sender.dart';
import '../widgets/manual_wa_chip.dart';
import 'api_client.dart';

/// A WhatsApp template row as the backend returns from
/// /api/whatsapp/templates/:adminId. We only need a tiny subset of
/// the fields the v1 web shows.
class WhatsTemplate {
  const WhatsTemplate({
    required this.templateType,
    required this.isActive,
    required this.messageContent,
    this.defaultChannel = 'auto',
  });

  /// e.g. 'debt_reminder' / 'expiry_warning' / 'subscriber_info'.
  final String templateType;
  final bool isActive;

  /// Raw body with {variable} placeholders the client renders before
  /// calling sendMessage.
  final String messageContent;

  /// 2026-08-26: قناة افتراضيّة لهذا القالب — 'auto' (بحسب binding
  /// المشترك) / 'whatsapp' (يجبر WA) / 'telegram' (يجبر TG). backend
  /// يقرأها في _v2NotifySubscriberWA ويمرّر forceChannel.
  final String defaultChannel;
}

Map<String, dynamic>? _waMap(dynamic value) {
  if (value is! Map) return null;
  return value.map((key, item) => MapEntry(key.toString(), item));
}

dynamic _waFirst(Map<String, dynamic>? source, List<String> keys) {
  if (source == null) return null;
  for (final key in keys) {
    final value = source[key];
    if (value != null) return value;
  }
  return null;
}

bool? _waBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
        return true;
      case 'false':
      case '0':
      case 'no':
        return false;
    }
  }
  return null;
}

int? _waInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

int? _waUnixSeconds(dynamic value) {
  final numeric = _waInt(value);
  if (numeric != null) {
    // WAHA returns seconds. Accept milliseconds as a defensive fallback.
    return numeric > 10000000000 ? numeric ~/ 1000 : numeric;
  }
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return null;
  return parsed.millisecondsSinceEpoch ~/ 1000;
}

/// WhatsApp's per-cycle allowance for opening new 1:1 conversations.
/// `CAPPED` blocks new conversations until [cycleEnd], while existing chats
/// keep working. The session must not be logged out or re-paired for this.
class WhatsMessageCapping {
  const WhatsMessageCapping({
    required this.status,
    this.totalQuota,
    this.usedQuota,
    this.cycleStart,
    this.cycleEnd,
    this.mvStatus,
    this.oteStatus,
  });

  final String status;
  final int? totalQuota;
  final int? usedQuota;
  final int? cycleStart;
  final int? cycleEnd;
  final String? mvStatus;
  final String? oteStatus;

  bool get isCapped => status == 'CAPPED';
  bool get isWarning => status.isNotEmpty && status != 'NONE' && !isCapped;

  static WhatsMessageCapping? fromJson(dynamic value) {
    final j = _waMap(value);
    if (j == null) return null;
    final status = (_waFirst(j, const [
              'cappingStatus',
              'capping_status',
              'status',
            ]) ??
            '')
        .toString()
        .toUpperCase();
    if (status.isEmpty && j.isEmpty) return null;
    return WhatsMessageCapping(
      status: status,
      totalQuota: _waInt(_waFirst(j, const ['totalQuota', 'total_quota'])),
      usedQuota: _waInt(_waFirst(j, const ['usedQuota', 'used_quota'])),
      cycleStart: _waUnixSeconds(_waFirst(
          j, const ['cycleStart', 'cycle_start', 'cycle_start_timestamp'])),
      cycleEnd: _waUnixSeconds(
          _waFirst(j, const ['cycleEnd', 'cycle_end', 'cycle_end_timestamp'])),
      mvStatus: _waFirst(j, const ['mvStatus', 'mv_status'])?.toString(),
      oteStatus: _waFirst(j, const ['oteStatus', 'ote_status'])?.toString(),
    );
  }
}

/// حالة اتصال واتساب الـadmin الحالية.
class WhatsConnectionStatus {
  const WhatsConnectionStatus({
    required this.connected,
    this.stabilizing = false,
    this.phone,
    this.pushname,
    this.platform,
    this.sessionStatus,
    this.needsPairing = false,
    this.metaRestricted = false,
    this.reachoutRestricted = false,
    this.restrictionEndsAt,
    this.restrictionEnforcementType,
    this.messageCapping,
  });
  const WhatsConnectionStatus.disconnected()
      : connected = false,
        stabilizing = false,
        phone = null,
        pushname = null,
        platform = null,
        sessionStatus = null,
        needsPairing = false,
        metaRestricted = false,
        reachoutRestricted = false,
        restrictionEndsAt = null,
        restrictionEnforcementType = null,
        messageCapping = null;
  final bool connected;
  final bool stabilizing;
  final String? phone;
  final String? pushname;
  final String? platform;
  final String? sessionStatus;
  final bool needsPairing;
  final bool metaRestricted;
  final bool reachoutRestricted;
  final int? restrictionEndsAt;
  final String? restrictionEnforcementType;
  final WhatsMessageCapping? messageCapping;

  bool get hasSendingRestriction =>
      metaRestricted || messageCapping?.isCapped == true;

  factory WhatsConnectionStatus.fromJson(Map<String, dynamic> body) {
    final session = _waMap(body['session']);
    final me = _waMap(body['me']) ?? _waMap(session?['me']);
    final reachout = _waMap(body['reachoutTimelock']) ??
        _waMap(body['reachout_timelock']) ??
        _waMap(me?['reachoutTimelock']) ??
        _waMap(me?['reachout_timelock']);
    final cappingJson = body['messageCapping'] ??
        body['message_capping'] ??
        me?['messageCapping'] ??
        me?['message_capping'];
    final rawStatus = _waFirst(body, const [
          'status',
          'sessionStatus',
          'session_status',
        ]) ??
        _waFirst(session, const ['status', 'sessionStatus', 'session_status']);
    final sessionStatus = rawStatus?.toString().toUpperCase();
    const pairingStatuses = {
      'SCAN_QR_CODE',
      'PASSKEY_REQUIRED',
      'PASSKEY_CONFIRMATION_REQUIRED',
    };

    final messageCapping = WhatsMessageCapping.fromJson(cappingJson);
    final metaRestricted = _waBool(_waFirst(
          body,
          const ['metaRestricted', 'meta_restricted'],
        )) ??
        false;
    final explicitReachout = _waBool(
      _waFirst(reachout, const ['isActive', 'is_active']),
    );
    final restrictionEnforcementType = (_waFirst(
              body,
              const [
                'restrictionEnforcementType',
                'restriction_enforcement_type',
              ],
            ) ??
            _waFirst(
              reachout,
              const ['enforcementType', 'enforcement_type'],
            ))
        ?.toString();

    return WhatsConnectionStatus(
      connected: body['connected'] == true || body['isConnected'] == true,
      stabilizing: body['stabilizing'] == true,
      phone: body['phone']?.toString(),
      pushname: body['pushname']?.toString(),
      platform: body['platform']?.toString(),
      sessionStatus: sessionStatus,
      needsPairing: _waBool(_waFirst(
            body,
            const ['needsPairing', 'needs_pairing'],
          )) ??
          pairingStatuses.contains(sessionStatus),
      metaRestricted: metaRestricted || explicitReachout == true,
      reachoutRestricted: explicitReachout ??
          (metaRestricted &&
              ((restrictionEnforcementType ?? '').isNotEmpty ||
                  messageCapping?.isCapped != true)),
      restrictionEndsAt: _waUnixSeconds(_waFirst(
            body,
            const ['restrictionEndsAt', 'restriction_ends_at'],
          ) ??
          _waFirst(
            reachout,
            const ['timeEnforcementEnds', 'time_enforcement_ends'],
          )),
      restrictionEnforcementType: restrictionEnforcementType,
      messageCapping: messageCapping,
    );
  }
}

/// 7 toggles لكل المسارات التلقائية في واتساب. مطابق صفّ
/// whatsapp_features في الـDB.
class WhatsFeatures {
  const WhatsFeatures({
    this.notificationsEnabled = true,
    this.sendOnActivation = false,
    this.expiryReminder = false,
    this.debtReminder = false,
    this.serviceEndNotification = false,
    this.welcomeMessage = false,
    this.sendOnExtension = false,
  });

  /// Master switch — لو معطل، كل الإشعارات تتوقف بغض النظر عن بقية toggles.
  final bool notificationsEnabled;
  final bool sendOnActivation;
  final bool expiryReminder;
  final bool debtReminder;
  final bool serviceEndNotification;
  final bool welcomeMessage;
  final bool sendOnExtension;

  WhatsFeatures copyWith({
    bool? notificationsEnabled,
    bool? sendOnActivation,
    bool? expiryReminder,
    bool? debtReminder,
    bool? serviceEndNotification,
    bool? welcomeMessage,
    bool? sendOnExtension,
  }) {
    return WhatsFeatures(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      sendOnActivation: sendOnActivation ?? this.sendOnActivation,
      expiryReminder: expiryReminder ?? this.expiryReminder,
      debtReminder: debtReminder ?? this.debtReminder,
      serviceEndNotification:
          serviceEndNotification ?? this.serviceEndNotification,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      sendOnExtension: sendOnExtension ?? this.sendOnExtension,
    );
  }

  static WhatsFeatures fromJson(Map<String, dynamic> j) {
    bool b(dynamic v) =>
        v is bool ? v : (v is num ? v != 0 : v?.toString() == 'true');
    return WhatsFeatures(
      notificationsEnabled: b(j['notificationsEnabled'] ?? true),
      sendOnActivation: b(j['sendOnActivation']),
      expiryReminder: b(j['expiryReminder']),
      debtReminder: b(j['debtReminder']),
      serviceEndNotification: b(j['serviceEndNotification']),
      welcomeMessage: b(j['welcomeMessage']),
      sendOnExtension: b(j['sendOnExtension']),
    );
  }

  Map<String, dynamic> toJson() => {
        'notificationsEnabled': notificationsEnabled,
        'sendOnActivation': sendOnActivation,
        'expiryReminder': expiryReminder,
        'debtReminder': debtReminder,
        'serviceEndNotification': serviceEndNotification,
        'welcomeMessage': welcomeMessage,
        'sendOnExtension': sendOnExtension,
      };
}

/// Result of a template-send round-trip — feeds the snackbar.
class WhatsSendResult {
  const WhatsSendResult({
    required this.ok,
    this.message,
    this.reason,
    this.channel,
  });
  final bool ok;

  /// Backend message when ok=false (e.g. 'واتساب غير متصل').
  final String? message;

  /// Local short reason for UI branching ('no_template' / 'no_phone' /
  /// 'inactive' / 'wa_disconnected' / 'send_failed' / 'network').
  final String? reason;

  /// 2026-08-26: القناة الفعليّة التي مرّت بها الرسالة عند النجاح —
  /// 'whatsapp' أو 'telegram'. backend يعيدها في data.channel.
  /// null على الفشل أو ردود قديمة. الـUI يستعملها لعرض "عبر تلغرام/واتساب".
  final String? channel;

  String? get channelArabic {
    switch (channel) {
      case 'telegram':
        return 'تلغرام';
      case 'whatsapp':
        return 'واتساب';
      default:
        return null;
    }
  }
}

/// Mirrors v1's _sendWhatsAppFromTemplate flow in
/// mobile-app/lib/screens/subscribers/subscriber_details_screen.dart:
///   1. Load the admin's templates (cached for the session).
///   2. Pick the active row of the requested type.
///   3. Fill {variable} placeholders from the subscriber.
///   4. POST /api/whatsapp/send-message with the rendered body and a
///      matching intent tag so the backend's dedup window applies.
///
/// We intentionally skip the heavier v1 plumbing — settings provider,
/// feature flags, whatsappProvider reconnect dance — for now. The
/// backend's /api/whatsapp/send-message itself attempts a reconnect
/// when the admin's session is offline (see server.js line ~2561).
class WhatsAppApi {
  WhatsAppApi._();

  // Process-wide template cache — admins rarely change templates
  // during a session and the list is small. TTL keeps recently-edited
  // templates from going stale forever.
  static List<WhatsTemplate>? _templates;
  static DateTime? _templatesAt;
  static const _ttl = Duration(minutes: 10);

  /// 2026-08-28 (Google 2027 audit CRITICAL fix): يُستدعى من
  /// SessionManager.clearAllSessionData عند logout — يمسح cache
  /// القوالب حتى المدير التالي على نفس الجهاز لا يرى/يعدّل قوالب
  /// المدير السابق (تسريب PII استمرّ حتى 10 دقائق).
  static void clearCaches() {
    _templates = null;
    _templatesAt = null;
  }

  /// GET /api/whatsapp/templates/:adminId — returns the cached list
  /// when warm, else round-trips. Null on auth / network failure;
  /// callers fall back to a snackbar.
  static Future<List<WhatsTemplate>?> loadTemplates({
    bool refresh = false,
  }) async {
    if (!refresh &&
        _templates != null &&
        _templatesAt != null &&
        DateTime.now().difference(_templatesAt!) < _ttl) {
      return _templates;
    }
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) {
      _log('templates', 'missing adminId');
      return null;
    }
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/whatsapp/templates/$adminId',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        _log('templates', 'success!=true body=$body');
        return null;
      }
      final list = (body['templates'] as List?) ?? const [];
      final out = <WhatsTemplate>[];
      for (final row in list) {
        if (row is! Map) continue;
        final type = row['template_type']?.toString();
        if (type == null || type.isEmpty) continue;
        final active = row['is_active'];
        final isActive = active is bool
            ? active
            : (active is num ? active != 0 : active?.toString() == '1');
        final content = (row['message_content'] ?? '').toString();
        final chRaw = row['default_channel']?.toString() ?? 'auto';
        final ch =
            ['auto', 'whatsapp', 'telegram'].contains(chRaw) ? chRaw : 'auto';
        out.add(WhatsTemplate(
          templateType: type,
          isActive: isActive,
          messageContent: content,
          defaultChannel: ch,
        ));
      }
      _templates = out;
      _templatesAt = DateTime.now();
      return out;
    } on DioException catch (e) {
      _log('templates', e);
      return null;
    } catch (e) {
      _log('templates', e);
      return null;
    }
  }

  /// GET /api/whatsapp/connection-status/:adminId — حالة الاتصال
  /// الحيّة. يدعم `live=true` لإعادة ربط تلقائي عند فتح الصفحة.
  static Future<WhatsConnectionStatus?> connectionStatus({
    bool live = false,
  }) async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/whatsapp/connection-status/$adminId',
        queryParameters: live ? {'live': 'true'} : null,
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        return const WhatsConnectionStatus.disconnected();
      }
      return WhatsConnectionStatus.fromJson(body);
    } on DioException catch (e) {
      _log('whatsapp/connection-status', e);
      return null;
    } catch (e) {
      _log('whatsapp/connection-status', e);
      return null;
    }
  }

  /// POST /api/whatsapp/start-session — يطلق session جديد ينتج QR.
  /// الـQR يُجلب لاحقاً عبر pending-qr / get-qr.
  ///
  /// Backend requires BOTH adminId and adminUsername (server.js line 2309).
  /// Sending adminId alone was returning 400 "Admin ID and username are required".
  static Future<({bool ok, String? message})> startSession() async {
    final adminId = await AuthStorage.readAdminId();
    final adminUsername = await AuthStorage.readAdminUsername();
    if (adminId == null || adminUsername == null) {
      return (ok: false, message: 'لا توجد جلسة دخول');
    }
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/start-session',
        data: {'adminId': adminId, 'adminUsername': adminUsername},
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } on DioException catch (e) {
      _log('whatsapp/start-session', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر بدء الجلسة');
    } catch (e) {
      _log('whatsapp/start-session', e);
      return (ok: false, message: 'تعذّر بدء الجلسة');
    }
  }

  /// POST /api/whatsapp/start-session-code — يطلق pair code (8 أرقام)
  /// بدل QR. ينتج رمز يكتبه المستخدم في واتساب الويب على الجهاز.
  static Future<({bool ok, String? code, String? message})> startSessionCode({
    required String phone,
  }) async {
    final adminId = await AuthStorage.readAdminId();
    final adminUsername = await AuthStorage.readAdminUsername();
    if (adminId == null || adminUsername == null) {
      return (ok: false, code: null, message: 'لا توجد جلسة دخول');
    }
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/start-session-code',
        data: {
          'adminId': adminId,
          'adminUsername': adminUsername,
          'phone': phone,
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        code: body['code']?.toString() ?? body['pairCode']?.toString(),
        message: body['message']?.toString(),
      );
    } on DioException catch (e) {
      _log('whatsapp/start-session-code', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, code: null, message: msg ?? 'تعذّر إنشاء الرمز');
    } catch (e) {
      _log('whatsapp/start-session-code', e);
      return (ok: false, code: null, message: 'تعذّر إنشاء الرمز');
    }
  }

  /// GET /api/whatsapp/pending-qr/:adminId — يجلب الـQR المعلّق من الـ
  /// clientRouter الحيّ (in-memory). هذا الـendpoint الصحيح للـpolling
  /// أثناء انتظار المستخدم يمسح — مطابق v1 web (WhatsApp.tsx: startPolling).
  ///
  /// يرجّع (qr: null, connected: true) عند الاتصال بين محاولات الـpoll.
  static Future<({String? qr, bool connected})> pendingQr() async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return (qr: null, connected: false);
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/whatsapp/pending-qr/$adminId',
      );
      final body = r.data ?? const {};
      if (body['alreadyConnected'] == true) {
        return (qr: null, connected: true);
      }
      if (body['success'] == true) {
        return (qr: body['qrCode']?.toString(), connected: false);
      }
      return (qr: null, connected: false);
    } catch (_) {
      return (qr: null, connected: false);
    }
  }

  /// POST /api/whatsapp/reconnect
  ///
  /// Backend accepts adminId alone, but resolveWhatsAppAdminContext needs
  /// adminUsername to route sub-admins correctly. We pass it when available.
  static Future<({bool ok, String? message})> reconnect() async {
    final adminId = await AuthStorage.readAdminId();
    final adminUsername = await AuthStorage.readAdminUsername();
    if (adminId == null) return (ok: false, message: 'لا توجد جلسة دخول');
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/reconnect',
        data: {
          'adminId': adminId,
          if (adminUsername != null) 'adminUsername': adminUsername,
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('whatsapp/reconnect', e);
      return (ok: false, message: 'فشل إعادة الاتصال');
    }
  }

  /// POST /api/whatsapp/disconnect — يقطع الجلسة لكن يبقي بيانات الـauth.
  static Future<({bool ok, String? message})> disconnect() async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return (ok: false, message: 'لا توجد جلسة دخول');
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/disconnect',
        data: {'adminId': adminId},
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('whatsapp/disconnect', e);
      return (ok: false, message: 'فشل قطع الاتصال');
    }
  }

  /// POST /api/whatsapp/soft-reset — يمسح الـauth ويبدأ جلسة جديدة
  /// (يجبر إعادة QR). يُستعمل لما الجلسة عالقة.
  static Future<({bool ok, String? message})> softReset() async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return (ok: false, message: 'لا توجد جلسة دخول');
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/soft-reset',
        data: {'adminId': adminId},
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('whatsapp/soft-reset', e);
      return (ok: false, message: 'فشل إعادة التهيئة');
    }
  }

  /// GET /api/whatsapp/get-features/:adminId
  static Future<WhatsFeatures?> getFeatures() async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/whatsapp/get-features/$adminId',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final f = body['features'];
      if (f is! Map) return null;
      return WhatsFeatures.fromJson(Map<String, dynamic>.from(f));
    } catch (_) {
      return null;
    }
  }

  /// POST /api/whatsapp/save-features
  static Future<({bool ok, String? message})> saveFeatures(
      WhatsFeatures features) async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return (ok: false, message: 'لا توجد جلسة دخول');
    try {
      // Backend expects `{ adminId, features }` — nested. v1 web sends the
      // same shape (client-v2/src/pages/WhatsApp.tsx). Spreading toJson()
      // at the top level was returning 400 "adminId and features are required".
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/save-features',
        data: {
          'adminId': adminId,
          'features': features.toJson(),
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('whatsapp/save-features', e);
      return (ok: false, message: 'تعذّر الحفظ');
    }
  }

  /// POST /api/whatsapp/save-template — جديد أو تعديل قالب.
  ///
  /// Backend requires `templateName` (server.js line 3445). v1 web sends
  /// it too (client-v2/src/pages/WhatsAppTemplates.tsx). Omitting it was
  /// returning 400 "جميع الحقول مطلوبة". `isActive` is passed for parity
  /// but the backend save endpoint currently ignores it.
  static Future<({bool ok, String? message})> saveTemplate({
    required String templateType,
    required String templateName,
    required String messageContent,
    required bool isActive,

    /// 2026-08-26: قناة افتراضيّة للقالب — 'auto' / 'whatsapp' / 'telegram'.
    String defaultChannel = 'auto',
  }) async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return (ok: false, message: 'لا توجد جلسة دخول');
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/save-template',
        data: {
          'adminId': adminId,
          'templateType': templateType,
          'templateName': templateName,
          'messageContent': messageContent,
          'isActive': isActive,
          'defaultChannel': defaultChannel,
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('whatsapp/save-template', e);
      return (ok: false, message: 'تعذّر الحفظ');
    }
  }

  /// DELETE /api/whatsapp/template/:adminId/:templateType
  static Future<({bool ok, String? message})> deleteTemplate(
      String templateType) async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return (ok: false, message: 'لا توجد جلسة دخول');
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/whatsapp/template/$adminId/$templateType',
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('whatsapp/template DELETE', e);
      return (ok: false, message: 'تعذّر الحذف');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // WhatsApp Schedules (وقت/أيام إرسال التبليغات التلقائيّة)
  // منقولة من v1 mobile — نفس الـendpoints بالتحديد.
  // ─────────────────────────────────────────────────────────────

  /// GET /api/whatsapp/schedules/:adminId — يرجع قائمة WhatsAppSchedule
  /// (نوع واحد لكل schedule_type: expiry_warning + debt_reminder + service_end).
  /// نُرجع null على فشل الشبكة، [] على استجابة فارغة (مثلاً مدير جديد).
  static Future<List<WhatsAppSchedule>?> loadSchedules() async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return null;
    try {
      final r = await ApiClient.dio.get<dynamic>(
        '/api/whatsapp/schedules/$adminId',
      );
      final data = r.data;
      List<dynamic> rows;
      if (data is List) {
        rows = data;
      } else if (data is Map && data['schedules'] is List) {
        rows = data['schedules'] as List;
      } else {
        rows = const [];
      }
      final list = <WhatsAppSchedule>[];
      for (final row in rows) {
        if (row is! Map) continue;
        try {
          list.add(WhatsAppSchedule.fromJson(
            Map<String, dynamic>.from(row),
          ));
        } catch (_) {
          // صف تالف — نتخطّاه بدل إسقاط كل القائمة
        }
      }
      return list;
    } catch (e) {
      _log('whatsapp/schedules GET', e);
      return null;
    }
  }

  /// POST /api/whatsapp/save-schedule — upsert جدولة كاملة (وقت + أيام + وضع).
  static Future<({bool ok, String? message})> saveSchedule(
      WhatsAppSchedule schedule) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/save-schedule',
        data: schedule.toSaveJson(),
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      return (
        ok: ok,
        message: ok
            ? null
            : (body['message']?.toString() ??
                body['error']?.toString() ??
                'تعذّر حفظ الجدولة'),
      );
    } catch (e) {
      _log('whatsapp/save-schedule POST', e);
      return (ok: false, message: 'تعذّر حفظ الجدولة');
    }
  }

  /// PATCH /api/whatsapp/schedule-toggle — تبديل التفعيل بدون تغيير باقي
  /// الحقول (وقت/أيام). أسرع من saveSchedule الكامل + يعمل على جدولة
  /// موجودة (لا يُنشئ صف جديد).
  static Future<({bool ok, String? message})> toggleSchedule({
    required String scheduleType,
    required bool isEnabled,
  }) async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return (ok: false, message: 'لا توجد جلسة دخول');
    try {
      final r = await ApiClient.dio.patch<Map<String, dynamic>>(
        '/api/whatsapp/schedule-toggle',
        data: {
          'adminId': adminId,
          'scheduleType': scheduleType,
          'isEnabled': isEnabled,
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      return (
        ok: ok,
        message: ok
            ? null
            : (body['message']?.toString() ??
                body['error']?.toString() ??
                'تعذّر تحديث الحالة'),
      );
    } catch (e) {
      _log('whatsapp/schedule-toggle PATCH', e);
      return (ok: false, message: 'تعذّر تحديث الحالة');
    }
  }

  /// DELETE /api/whatsapp/schedule/:adminId/:scheduleType — مسح كامل.
  static Future<({bool ok, String? message})> deleteSchedule(
      String scheduleType) async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return (ok: false, message: 'لا توجد جلسة دخول');
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/whatsapp/schedule/$adminId/$scheduleType',
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      return (
        ok: ok,
        message: ok ? null : (body['message']?.toString() ?? 'تعذّر الحذف'),
      );
    } catch (e) {
      _log('whatsapp/schedule DELETE', e);
      return (ok: false, message: 'تعذّر الحذف');
    }
  }

  /// POST /api/whatsapp/trigger-schedule — تنفيذ فوري (تجاوز الوقت المجدول).
  /// يستعملها زر "شغّل الآن" في UI.
  static Future<({bool ok, String? message})> triggerSchedule(
      String scheduleType) async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) return (ok: false, message: 'لا توجد جلسة دخول');
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/trigger-schedule',
        data: {
          'adminId': adminId,
          'scheduleType': scheduleType,
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      return (
        ok: ok,
        message: ok ? null : (body['message']?.toString() ?? 'تعذّر التشغيل'),
      );
    } catch (e) {
      _log('whatsapp/trigger-schedule POST', e);
      return (ok: false, message: 'تعذّر التشغيل');
    }
  }

  /// POST /api/whatsapp/send-message — generic send entry. `intent`
  /// drives the backend's dedup window + log tagging.
  ///
  /// 2026-08-26 (tg parity): `sas4Idx` اختياريّ — لو موجود، backend
  /// channelRouter يفحص لو المشترك مربوط ببوت تلغرام الأدمن ويوجّه له
  /// عبر TG تلقائياً (بلا هذا الـidx، channelRouter يعود لواتساب فقط
  /// ويفشل بـconnectionError لو WA غير متصل). `forceChannel` يجبر
  /// قناة معيّنة ('auto' | 'whatsapp' | 'telegram').
  static Future<WhatsSendResult> sendMessage({
    required String to,
    required String message,
    String intent = 'manual',
    String? sas4Idx,
    String? forceChannel,
  }) async {
    final adminId = await AuthStorage.readAdminId();
    if (adminId == null) {
      return const WhatsSendResult(
        ok: false,
        reason: 'no_auth',
        message: 'يجب تسجيل الدخول',
      );
    }
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/whatsapp/send-message',
        data: {
          'adminId': adminId,
          'to': to,
          'message': message,
          'intent': intent,
          if (sas4Idx != null) 'sas4Idx': sas4Idx,
          if (forceChannel == 'whatsapp' || forceChannel == 'telegram')
            'forceChannel': forceChannel,
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      // 2026-08-26: backend يعيد channel في جذر الردّ (whatsapp/telegram)
      // للرد المؤكّد، وأحياناً داخل data.channel. نقبل الاثنين.
      final rawChannel = body['channel']?.toString() ??
          (body['data'] is Map
              ? (body['data'] as Map)['channel']?.toString()
              : null);
      final channel = (rawChannel == 'whatsapp' || rawChannel == 'telegram')
          ? rawChannel
          : null;
      return WhatsSendResult(
        ok: ok,
        message: body['message']?.toString(),
        reason: ok ? null : 'send_failed',
        channel: channel,
      );
    } on DioException catch (e) {
      _log('send-message', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return WhatsSendResult(
        ok: false,
        reason: 'network',
        message: msg ?? 'تعذّر الإرسال — تحقق من الاتصال',
      );
    } catch (e) {
      _log('send-message', e);
      return const WhatsSendResult(
        ok: false,
        reason: 'network',
        message: 'تعذّر الإرسال',
      );
    }
  }

  /// High-level helper used by the operations grid buttons
  /// (تذكير دين / تذكير انتهاء / إرسال المعلومات). Loads templates,
  /// finds the active matching one, renders variables from `sub`,
  /// and sends. Returns a structured result so the caller can pick
  /// the right snackbar.
  static Future<WhatsSendResult> sendTemplateForSubscriber({
    required Subscriber sub,
    required String templateType,
  }) async {
    final phone = sub.displayPhone;
    if (phone.isEmpty) {
      return const WhatsSendResult(
        ok: false,
        reason: 'no_phone',
        message: 'لا يوجد رقم هاتف للمشترك',
      );
    }
    final templates = await loadTemplates();
    if (templates == null) {
      return const WhatsSendResult(
        ok: false,
        reason: 'network',
        message: 'تعذّر جلب قوالب الواتساب',
      );
    }
    final matches =
        templates.where((t) => t.templateType == templateType).toList();
    if (matches.isEmpty) {
      final arabic = _arabicForTemplate(templateType);
      return WhatsSendResult(
        ok: false,
        reason: 'no_template',
        message: 'لا يوجد قالب "$arabic" — أضفه من إعدادات الواتساب',
      );
    }
    final active = matches.where((t) => t.isActive).toList();
    if (active.isEmpty) {
      final arabic = _arabicForTemplate(templateType);
      return WhatsSendResult(
        ok: false,
        reason: 'inactive',
        message: 'قالب "$arabic" مُعطَّل — فعّله من إعدادات الواتساب',
      );
    }
    final rendered = _renderTemplate(active.first.messageContent, sub);
    return sendMessage(
      to: phone,
      message: rendered,
      intent: templateType,
      sas4Idx: sub.idx,
    );
  }

  /// 2026-08-26: النسخة المعتَمدة للأزرار المباشرة (تذكير دين / تحذير
  /// انتهاء / إرسال معلومات). تعرض mini-sheet بـ:
  ///  - معاينة الرسالة كاملة (يرى المدير ماذا سيرسل)
  ///  - chip يعكس الوضع الحالي (تلقائي/يدوي) — قابل للتبديل لهذه العمليّة
  ///  - زر إرسال يفتح واتساب الشخصي (يدوي) أو يمرّر عبر السيرفر (تلقائي)
  ///
  /// الوضع الافتراضي يُقرأ من ManualWaPrefs.enabled (setting المدير).
  ///
  /// يرجع WhatsSendResult مثل sendMessage — لكن reason='cancelled' إذا
  /// أغلق المدير الـsheet بلا تأكيد.
  static Future<WhatsSendResult> sendTemplateWithPreview({
    required BuildContext context,
    required Subscriber sub,
    required String templateType,
  }) async {
    final phone = sub.displayPhone;
    if (phone.isEmpty) {
      return const WhatsSendResult(
        ok: false,
        reason: 'no_phone',
        message: 'لا يوجد رقم هاتف للمشترك',
      );
    }
    final templates = await loadTemplates();
    if (templates == null) {
      return const WhatsSendResult(
        ok: false,
        reason: 'network',
        message: 'تعذّر جلب قوالب الواتساب',
      );
    }
    final matches =
        templates.where((t) => t.templateType == templateType).toList();
    if (matches.isEmpty) {
      final arabic = _arabicForTemplate(templateType);
      return WhatsSendResult(
        ok: false,
        reason: 'no_template',
        message: 'لا يوجد قالب "$arabic" — أضفه من إعدادات الواتساب',
      );
    }
    final active = matches.where((t) => t.isActive).toList();
    if (active.isEmpty) {
      final arabic = _arabicForTemplate(templateType);
      return WhatsSendResult(
        ok: false,
        reason: 'inactive',
        message: 'قالب "$arabic" مُعطَّل — فعّله من إعدادات الواتساب',
      );
    }
    final rendered = _renderTemplate(active.first.messageContent, sub);

    if (!context.mounted) {
      return const WhatsSendResult(
        ok: false,
        reason: 'network',
        message: 'الشاشة أُغلقت',
      );
    }
    final choice = await showManualWaPreviewSheet(
      context,
      title: _arabicForTemplate(templateType),
      phone: phone,
      messagePreview: rendered,
    );
    if (choice == null || !choice.confirmed) {
      return const WhatsSendResult(ok: false, reason: 'cancelled');
    }

    if (choice.manualMode) {
      final ok = await openManualWa(
        phone: phone,
        message: rendered,
        // السياق قد يكون مات أثناء انتظار اختيار المستخدم أعلاه.
        // `openManualWa` تقبل null وتتخطّى الـsnack عندها.
        context: context.mounted ? context : null,
      );
      return WhatsSendResult(
        ok: ok,
        channel: 'whatsapp',
        reason: ok ? null : 'manual_wa_failed',
        message: ok
            ? 'افتح واتساب واضغط "إرسال" لإتمام العمليّة'
            : 'تعذّر فتح واتساب',
      );
    }
    return sendMessage(
      to: phone,
      message: rendered,
      intent: templateType,
      sas4Idx: sub.idx,
    );
  }

  /// Replaces every {placeholder} in the template body. Mirrors v1's
  /// var set from subscriber_details_screen.dart line ~2012 — same
  /// keys so existing admin templates keep working unchanged.
  static String _renderTemplate(String body, Subscriber sub) {
    final arabicName = sub.fullName.trim();
    final subscriberName = sub.username.isNotEmpty ? sub.username : arabicName;
    final firstName = arabicName.isNotEmpty ? arabicName : sub.username;
    final price = sub.price?.toInt() ?? 0;
    final priceStr = price > 0 ? formatIQD(price) : '0';
    final debt = sub.balanceAmount < 0 ? sub.balanceAmount.abs().round() : 0;
    final credit = sub.balanceAmount > 0 ? sub.balanceAmount.round() : 0;
    final remainingDays = sub.remainingDays?.toString() ?? '';
    final expiry = _formatExpiryArabic(sub.expiration);
    final vars = <String, String>{
      '{subscriber_name}': subscriberName,
      '{firstname}': firstName,
      '{lastname}': sub.lastname,
      '{phone}': sub.displayPhone,
      '{remaining_days}': remainingDays,
      '{days_remaining}': remainingDays,
      '{expiration_date}': expiry,
      '{expiry_date}': expiry,
      '{package_name}': sub.profileName ?? '',
      '{package_price}': priceStr,
      '{debt_amount}': debt > 0 ? formatIQD(debt) : '0',
      '{credit_amount}': credit > 0 ? formatIQD(credit) : '0',
      '{discount_amount}': sub.discount != null && sub.discount! > 0
          ? formatIQD(sub.discount!.round())
          : '0',
      '{discounted_price}': priceStr,
      '{paid_amount}': '0',
      '{username}': sub.username,
    };
    var out = body;
    vars.forEach((k, v) => out = out.replaceAll(k, v));
    return out;
  }

  /// '2026/04/25  05:59:00 مساءً' style — v1 normalizes to this so we
  /// match. Falls back to the raw string if parsing fails.
  static String _formatExpiryArabic(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '';
    final s = raw.trim();
    final t = DateTime.tryParse(s) ?? DateTime.tryParse(s.replaceAll(' ', 'T'));
    if (t == null) return s;
    String two(int n) => n.toString().padLeft(2, '0');
    final hour12 = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final suffix = t.hour < 12 ? 'صباحاً' : 'مساءً';
    return '${t.year}/${two(t.month)}/${two(t.day)}  '
        '${two(hour12)}:${two(t.minute)}:${two(t.second)} $suffix';
  }

  /// User-facing template names — shown in error snackbars when the
  /// template is missing or inactive.
  static String _arabicForTemplate(String type) {
    switch (type) {
      case 'debt_reminder':
        return 'تذكير الدين';
      case 'expiry_warning':
        return 'تذكير قرب الانتهاء';
      case 'subscriber_info':
        return 'معلومات المشترك';
      case 'payment_confirmation':
        return 'تأكيد الدفع';
      case 'activation_notice':
        return 'إشعار التفعيل';
      case 'extension_notice':
        return 'إشعار التمديد';
      case 'service_end':
        return 'انتهاء الخدمة';
      default:
        return type;
    }
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
        '🔴 wa/$endpoint: status=${err.response?.statusCode} body=${err.response?.data}',
      );
    } else {
      debugPrint('🔴 wa/$endpoint: $err');
    }
  }
}
