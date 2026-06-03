import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';

void _logErr(String endpoint, Object err) {
  if (kReleaseMode) return;
  if (err is DioException) {
    final code = err.response?.statusCode;
    final body = err.response?.data;
    debugPrint('🔴 $endpoint failed: status=$code body=$body');
  } else {
    debugPrint('🔴 $endpoint failed: $err');
  }
}

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

class DebtorsResult {
  const DebtorsResult({
    required this.count,
    required this.total,
    required this.nearExpiry,
  });
  final int count;
  final int total;
  /// Subscribers whose remaining days fall in [0, 3] — soon-to-expire.
  final int nearExpiry;
}

enum RevenuePeriod { day, week, month }

class RevenueResult {
  const RevenueResult({required this.amount});
  final int amount;
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
    } on DioException catch (e) {
      _logErr('daily-activations', e);
      return null;
    } catch (e) {
      _logErr('daily-activations', e);
      return null;
    }
  }

  /// GET /api/subscribers/with-phones — single pass over the subscriber
  /// list. Returns the debtors metric (count + total IQD) AND the
  /// near-expiry counter (subs whose remaining_days fall in [0, 3]).
  /// Replaces v1's two-pass approach with one network call + one loop.
  static Future<DebtorsResult?> fetchDebtors() async {
    final token = await AuthStorage.readToken();
    if (token == null) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/subscribers/with-phones',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final data = (body['data'] as List?) ?? const [];

      var debtCount = 0;
      var debtTotal = 0;
      var nearExpiry = 0;
      for (final raw in data) {
        if (raw is! Map) continue;

        // Debt detection (negative notes/comments). Falls back to
        // hasDebt + debt fields the way v1's dashboard_provider does.
        final notesRaw = (raw['notes'] ?? raw['comments'] ?? '')
            .toString()
            .replaceAll(',', '')
            .trim();
        var notesVal = double.tryParse(notesRaw) ?? 0;
        if (notesVal == 0 && (raw['hasDebt'] == true || raw['hasDebt'] == 1)) {
          final d = raw['debt'];
          if (d is num && d != 0) notesVal = -d.abs().toDouble();
        }
        if (notesVal < 0) {
          debtCount++;
          debtTotal += notesVal.abs().round();
        }

        // Near-expiry: 0..3 remaining days. SAS4 names this field
        // 'remaining_days'; some rows expose 'daysRemaining'.
        final daysRaw = raw['remaining_days'] ?? raw['daysRemaining'];
        final days = daysRaw is num
            ? daysRaw.toInt()
            : int.tryParse(daysRaw?.toString() ?? '');
        if (days != null && days >= 0 && days <= 3) {
          nearExpiry++;
        }
      }
      return DebtorsResult(
        count: debtCount,
        total: debtTotal,
        nearExpiry: nearExpiry,
      );
    } on DioException catch (e) {
      _logErr('subscribers/with-phones', e);
      return null;
    } catch (e) {
      _logErr('subscribers/with-phones', e);
      return null;
    }
  }

  /// GET /api/reports/finance?date_from=...&date_to=...
  /// Same endpoint the v1 web Financial Reports page uses. Returns
  /// `data.totals.total_payments` which v1 displays as "الإيرادات" —
  /// the sum of PAYMENT_ADD + DEBT_PAY + BALANCE_DEDUCT + ACTIVATE_CASH
  /// over the date range. We build the range from a [period] enum:
  ///   day   → today 00:00:00 → 23:59:59
  ///   week  → 7 days ago → now
  ///   month → 30 days ago → now
  static Future<RevenueResult?> fetchRevenue(RevenuePeriod period) async {
    final token = await AuthStorage.readToken();
    final adminId = await AuthStorage.readAdminId();
    if (token == null) return null;
    final (from, to) = _rangeFor(period);
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/reports/finance',
        queryParameters: {
          'date_from': from,
          'date_to': to,
          // Filter to THIS admin only. Without user_id the backend
          // returns revenue across all admins, which is why v2 was
          // showing ~15M when the web showed ~200K for the same period.
          if (adminId != null) 'user_id': adminId,
          // Don't waste bandwidth on logs; we only want the total.
          'limit_logs': 1,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final totals = (body['data'] as Map?)?['totals'] as Map?;
      final v = totals?['total_payments'];
      if (v == null) return null;
      final amount = v is num ? v.toInt() : (int.tryParse(v.toString()) ?? 0);
      return RevenueResult(amount: amount);
    } on DioException catch (e) {
      _logErr('reports/finance(${period.name}) from=$from to=$to', e);
      return null;
    } catch (e) {
      _logErr('reports/finance(${period.name})', e);
      return null;
    }
  }

  static (String, String) _rangeFor(RevenuePeriod p) {
    // Backend expects YYYY-MM-DD HH:mm:ss in Baghdad time. We compute
    // in the device's local TZ — close enough for one-shot dashboard
    // queries (Iraq is the only operating region; the device clocks
    // there match Asia/Baghdad).
    final now = DateTime.now();
    String d(DateTime t) =>
        '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
    final today = d(now);
    final to = '$today 23:59:59';
    String from;
    switch (p) {
      case RevenuePeriod.day:
        from = '$today 00:00:00';
      case RevenuePeriod.week:
        from = '${d(now.subtract(const Duration(days: 6)))} 00:00:00';
      case RevenuePeriod.month:
        from = '${d(now.subtract(const Duration(days: 29)))} 00:00:00';
    }
    return (from, to);
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
    } on DioException catch (e) {
      _logErr('whatsapp/connection-status', e);
      return null;
    } catch (e) {
      _logErr('whatsapp/connection-status', e);
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
