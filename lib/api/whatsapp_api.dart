import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/util/format.dart';
import '../models/subscriber.dart';
import '../services/auth_storage.dart';
import 'api_client.dart';

/// A WhatsApp template row as the backend returns from
/// /api/whatsapp/templates/:adminId. We only need a tiny subset of
/// the fields the v1 web shows.
class WhatsTemplate {
  const WhatsTemplate({
    required this.templateType,
    required this.isActive,
    required this.messageContent,
  });

  /// e.g. 'debt_reminder' / 'expiry_warning' / 'subscriber_info'.
  final String templateType;
  final bool isActive;
  /// Raw body with {variable} placeholders the client renders before
  /// calling sendMessage.
  final String messageContent;
}

/// Result of a template-send round-trip — feeds the snackbar.
class WhatsSendResult {
  const WhatsSendResult({required this.ok, this.message, this.reason});
  final bool ok;
  /// Backend message when ok=false (e.g. 'واتساب غير متصل').
  final String? message;
  /// Local short reason for UI branching ('no_template' / 'no_phone' /
  /// 'inactive' / 'wa_disconnected' / 'send_failed' / 'network').
  final String? reason;
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
        out.add(WhatsTemplate(
          templateType: type,
          isActive: isActive,
          messageContent: content,
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

  /// POST /api/whatsapp/send-message — generic send entry. `intent`
  /// drives the backend's dedup window + log tagging.
  static Future<WhatsSendResult> sendMessage({
    required String to,
    required String message,
    String intent = 'manual',
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
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      return WhatsSendResult(
        ok: ok,
        message: body['message']?.toString(),
        reason: ok ? null : 'send_failed',
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
    final matches = templates
        .where((t) => t.templateType == templateType)
        .toList();
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
    return sendMessage(to: phone, message: rendered, intent: templateType);
  }

  /// Replaces every {placeholder} in the template body. Mirrors v1's
  /// var set from subscriber_details_screen.dart line ~2012 — same
  /// keys so existing admin templates keep working unchanged.
  static String _renderTemplate(String body, Subscriber sub) {
    final arabicName = sub.fullName.trim();
    final subscriberName =
        sub.username.isNotEmpty ? sub.username : arabicName;
    final firstName = arabicName.isNotEmpty ? arabicName : sub.username;
    final price = sub.price?.toInt() ?? 0;
    final priceStr = price > 0 ? formatIQD(price) : '0';
    final debt =
        sub.balanceAmount < 0 ? sub.balanceAmount.abs().round() : 0;
    final credit =
        sub.balanceAmount > 0 ? sub.balanceAmount.round() : 0;
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
    final t = DateTime.tryParse(s) ??
        DateTime.tryParse(s.replaceAll(' ', 'T'));
    if (t == null) return s;
    String two(int n) => n.toString().padLeft(2, '0');
    final hour12 = t.hour == 0
        ? 12
        : (t.hour > 12 ? t.hour - 12 : t.hour);
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
