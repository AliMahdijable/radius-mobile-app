import 'package:dio/dio.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';

/// Dashboard data fetchers. Each call returns a typed result or `null`
/// on failure — callers fall back to a previous value or a sensible
/// placeholder rather than blocking the whole screen on one slow call.

class DailyActivationsResult {
  const DailyActivationsResult({
    required this.activations,
    required this.extensions,
    required this.recent,
  });
  final int activations;
  final int extensions;
  final List<Map<String, dynamic>> recent;
}

class WhatsAppStatusResult {
  const WhatsAppStatusResult({
    required this.connected,
    required this.phone,
  });
  final bool connected;
  final String phone;
}

class DashboardApi {
  DashboardApi._();

  /// GET /api/activities/daily-activations?admin_id=X
  /// Backend aggregates today's activation + extension counts and the
  /// last N recent activity rows. Same endpoint v1 uses.
  static Future<DailyActivationsResult?> fetchDailyActivations() async {
    final token = await AuthStorage.readToken();
    final adminId = await AuthStorage.readAdminId();
    if (token == null || adminId == null) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/activities/daily-activations',
        queryParameters: {'admin_id': adminId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final counts = (body['counts'] as Map?) ?? const {};
      final list = (body['data'] as List?) ?? const [];
      return DailyActivationsResult(
        activations: _toInt(counts['activations']) ??
            _toInt(counts['activate']) ??
            0,
        extensions:
            _toInt(counts['extensions']) ?? _toInt(counts['extend']) ?? 0,
        recent: list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  /// GET /api/whatsapp/connection-status/:adminId
  /// Returns whether the admin's WhatsApp session is live + the bound
  /// phone number for display. Used by the dashboard header chip.
  static Future<WhatsAppStatusResult?> fetchWhatsAppStatus() async {
    final token = await AuthStorage.readToken();
    final adminId = await AuthStorage.readAdminId();
    if (token == null || adminId == null) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/whatsapp/connection-status/$adminId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final body = r.data ?? const {};
      return WhatsAppStatusResult(
        connected: body['connected'] == true || body['isConnected'] == true,
        phone: (body['phone'] ?? body['whatsappPhone'] ?? '').toString(),
      );
    } on DioException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }
}
