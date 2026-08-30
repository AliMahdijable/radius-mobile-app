import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_storage.dart';
import 'api_client.dart';
import 'subscribers_api.dart';
import 'whatsapp_api.dart';

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

void _logSilent(String endpoint, String reason, dynamic body) {
  if (kReleaseMode) return;
  debugPrint('🟡 $endpoint returned null: $reason | body=$body');
}

void _logStart(String endpoint) {
  if (kReleaseMode) return;
  debugPrint('🔵 $endpoint → calling');
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
    this.needsPairing = false,
    this.sendingRestricted = false,
    this.cappingWarning = false,
  });
  final bool connected;
  final String phone;
  final bool needsPairing;
  final bool sendingRestricted;
  final bool cappingWarning;
}

class DebtorsResult {
  const DebtorsResult({
    required this.count,
    required this.total,
    required this.nearExpiry,
    required this.online,
    required this.offline,
    required this.active,
    required this.expired,
    required this.totalSubs,
    required this.onlineNoPlan,
    required this.disabled,
  });
  final int count;
  final int total;

  /// Subscribers whose remaining days fall in [0, 3] — soon-to-expire.
  final int nearExpiry;

  /// مطلب 2026-06-11: حسابات حالة الاتصال من القائمة المحلية مثل v1
  /// لأن SAS4 widget الـactive يرجّع رقم خاطئ على بعض الحسابات
  /// (offline يحسب صفر مع وجود متصلين). نمشي بنفس predicate v1:
  ///   isOnline / isOffline = !isOnline && !isExpired / isExpired
  final int online;
  final int offline;
  final int active; // !isExpired && !isDisabled (or per model)
  final int expired;
  final int totalSubs;

  /// "بدون نت" — متصل + منتهي. المشترك يسحب data لكن اشتراكه انتهى.
  /// الإدمن يحتاج يمدّد أو يفصل. نحسبها هنا مرة واحدة لتُستهلك في
  /// dashboard KPI ولتفادي تمرير القائمة الكاملة للـstats-mapper.
  final int onlineNoPlan;

  /// المشتركون الموقوفون بيد المدير (`isDisabled`) — يختلفون عن
  /// المنتهين: هؤلاء انتهت باقتهم، وأولئك أوقفهم المدير عمداً.
  final int disabled;
}

enum RevenuePeriod { day, week, month }

/// Manager wallet snapshot — balance (managers carry credit for activations)
/// + reward points (SAS4 incentive system). Pulled from /api/v2/admin-widgets
/// which wraps SAS4's wd_balance + wd_reward_points widgets.
class WalletResult {
  const WalletResult({required this.balance, required this.points});
  final num balance;
  final num points;

  Map<String, dynamic> toJson() => {'balance': balance, 'points': points};
  factory WalletResult.fromJson(Map<String, dynamic> j) => WalletResult(
        balance: (j['balance'] as num?) ?? 0,
        points: (j['points'] as num?) ?? 0,
      );
}

/// نقطة على منحنى الإيراد — يوم واحد ومجموعه.
class RevenuePoint {
  const RevenuePoint({required this.date, required this.amount});
  final DateTime date;
  final int amount;

  Map<String, dynamic> toJson() =>
      {'d': date.toIso8601String(), 'a': amount};
  factory RevenuePoint.fromJson(Map<String, dynamic> j) => RevenuePoint(
        date: DateTime.tryParse(j['d']?.toString() ?? '') ?? DateTime(2000),
        amount: (j['a'] as num?)?.toInt() ?? 0,
      );
}

class RevenueResult {
  const RevenueResult({required this.amount, this.series = const []});
  final int amount;

  /// سلسلة يوميّة للمدى نفسه. مجموعها = `amount` بالضبط: الخادم يجمع
  /// الدلاء الأربعة ذاتها في الاثنين (أُصلح 2026-08-30 — كان يجمع
  /// دلوين في السلسلة وأربعة في الرقم، فتظهر أعمدة صفريّة تحت ملايين).
  final List<RevenuePoint> series;

  Map<String, dynamic> toJson() =>
      {'amount': amount, 'series': series.map((p) => p.toJson()).toList()};
  factory RevenueResult.fromJson(Map<String, dynamic> j) => RevenueResult(
        amount: (j['amount'] as num?)?.toInt() ?? 0,
        series: ((j['series'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => RevenuePoint.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

class DashboardApi {
  DashboardApi._();

  /// GET /api/activities/daily-activations?admin_id=X
  /// Backend aggregates today's activation + extension counts and the
  /// last N recent activity rows. Same endpoint v1 uses.
  static Future<DailyActivationsResult?> fetchDailyActivations() async {
    _logStart('daily-activations');
    final token = await AuthStorage.readToken();
    final adminId = await AuthStorage.readAdminId();
    if (token == null || adminId == null) {
      _logSilent(
          'daily-activations',
          'missing token or adminId (token=${token != null} adminId=$adminId)',
          null);
      return null;
    }
    try {
      // include_payments=1 → backend also returns DEBT_PAY /
      // BALANCE_DEDUCT / PAYMENT_ADD / BALANCE_ADD rows alongside the
      // activations/extensions. Without this flag the web's "تفعيلات
      // اليوم" report stays activations-only as before; the mobile
      // dashboard wants the broader revenue stream so the recent
      // activity feed shows debt payments too (مطلب 2026-06-07).
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/activities/daily-activations',
        queryParameters: {
          'admin_id': adminId,
          'include_payments': '1',
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        _logSilent('daily-activations', 'success != true', body);
        return null;
      }
      final counts = (body['counts'] as Map?) ?? const {};
      final list = (body['data'] as List?) ?? const [];
      return DailyActivationsResult(
        activations:
            _toInt(counts['activations']) ?? _toInt(counts['activate']) ?? 0,
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
    _logStart('subscribers/with-phones (debtors)');
    // Goes through SubscribersApi's process-wide cache so the dashboard
    // and the subscribers tab share ONE fetch on app open instead of
    // double-fetching the same heavy endpoint.
    final list = await SubscribersApi.loadAll();
    if (list == null) {
      _logSilent('subscribers/with-phones', 'loadAll returned null', null);
      return null;
    }
    var debtCount = 0;
    var debtTotal = 0;
    var nearExpiry = 0;
    var online = 0;
    var offline = 0;
    var active = 0;
    var expired = 0;
    var onlineNoPlan = 0;
    var disabled = 0;
    for (final s in list) {
      if (s.hasDebt) {
        debtCount++;
        debtTotal += s.debtAbs.round();
      }
      if (s.isNearExpiry) nearExpiry++;
      // 2026-07-16: "متصل" في الداشبورد يستثني المنتهين — عندهم فلتر
      // مخصّص onlineNoPlan (بدون نت). المستخدم يريد الفصل الدقيق.
      if (s.isOnline && !s.isExpired) online++;
      if (s.isOffline) offline++; // !isOnline && !isExpired
      if (s.isExpired) expired++;
      if (s.isActive) active++; // matches isExpired==false
      if (s.isOnline && s.isExpired) onlineNoPlan++;
      // 2026-08-30: «غير مفعّل» — حساب موقوف بيد المدير، لا منتهٍ.
      // يُحسب هنا لأنّ الحلقة تمرّ على القائمة مرّةً واحدة أصلاً،
      // فالعدّاد الجديد بلا كلفة شبكيّة ولا مرور ثانٍ.
      if (s.isDisabled) disabled++;
    }
    return DebtorsResult(
      count: debtCount,
      total: debtTotal,
      nearExpiry: nearExpiry,
      online: online,
      offline: offline,
      active: active,
      expired: expired,
      totalSubs: list.length,
      onlineNoPlan: onlineNoPlan,
      disabled: disabled,
    );
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
    _logStart('reports/finance(${period.name})');
    final token = await AuthStorage.readToken();
    final adminId = await AuthStorage.readAdminId();
    if (token == null) {
      _logSilent('reports/finance', 'missing token', null);
      return null;
    }
    final (from, to) = _rangeFor(period);
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/reports/finance',
        queryParameters: {
          'date_from': from,
          'date_to': to,
          if (adminId != null) 'user_id': adminId,
          'limit_logs': 1,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        _logSilent('reports/finance', 'success != true', body);
        return null;
      }
      final totals = (body['data'] as Map?)?['totals'] as Map?;
      final v = totals?['total_payments'];
      if (v == null) {
        _logSilent(
            'reports/finance', 'data.totals.total_payments missing', body);
        return null;
      }
      final amount = v is num ? v.toInt() : (int.tryParse(v.toString()) ?? 0);

      // السلسلة اختياريّة: غيابها لا يمنع عرض الرقم — الخادم القديم
      // (قبل إصلاح 2026-08-30) يُرجعها صفريّة، والأقدم لا يُرجعها.
      final rawSeries = (body['data'] as Map?)?['timeseries'];
      final series = <RevenuePoint>[];
      if (rawSeries is List) {
        for (final e in rawSeries) {
          if (e is! Map) continue;
          final d = DateTime.tryParse(e['date']?.toString() ?? '');
          if (d == null) continue;
          final a = e['payments_sum'];
          series.add(RevenuePoint(
            date: DateTime(d.year, d.month, d.day),
            amount: a is num ? a.toInt() : (int.tryParse(a.toString()) ?? 0),
          ));
        }
        series.sort((x, y) => x.date.compareTo(y.date));
      }
      return RevenueResult(amount: amount, series: series);
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
    String d(DateTime t) => '${t.year.toString().padLeft(4, '0')}-'
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

  /// GET /api/v2/admin-widgets — `{success, balance, points}`.
  /// Backend already aggregates SAS4's wd_balance + wd_reward_points
  /// widgets for us.
  static Future<WalletResult?> fetchWallet() async {
    _logStart('v2/admin-widgets');
    final token = await AuthStorage.readToken();
    if (token == null) {
      _logSilent('v2/admin-widgets', 'missing token', null);
      return null;
    }
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/admin-widgets',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        _logSilent('v2/admin-widgets', 'success != true', body);
        return null;
      }
      final balance = body['balance'];
      final points = body['points'];
      return WalletResult(
        balance:
            balance is num ? balance : (num.tryParse(balance.toString()) ?? 0),
        points: points is num ? points : (num.tryParse(points.toString()) ?? 0),
      );
    } on DioException catch (e) {
      _logErr('v2/admin-widgets', e);
      return null;
    } catch (e) {
      _logErr('v2/admin-widgets', e);
      return null;
    }
  }

  /// GET /api/whatsapp/connection-status/:adminId
  /// Returns whether the admin's WhatsApp session is live + the bound
  /// phone number for display. Used by the dashboard header chip.
  static Future<WhatsAppStatusResult?> fetchWhatsAppStatus() async {
    _logStart('whatsapp/connection-status');
    final token = await AuthStorage.readToken();
    final adminId = await AuthStorage.readAdminId();
    if (token == null || adminId == null) {
      _logSilent(
          'whatsapp/connection-status',
          'missing token or adminId (token=${token != null} adminId=$adminId)',
          null);
      return null;
    }
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/whatsapp/connection-status/$adminId',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final body = r.data ?? const {};
      final status = WhatsConnectionStatus.fromJson(body);
      return WhatsAppStatusResult(
        connected: status.connected,
        phone: (body['phone'] ?? body['whatsappPhone'] ?? '').toString(),
        needsPairing: status.needsPairing,
        sendingRestricted: status.hasSendingRestriction,
        cappingWarning: status.messageCapping?.isWarning == true,
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
