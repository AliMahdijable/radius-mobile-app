import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// SAS4 widget endpoints — same set v1's dashboard_provider hits.
/// Each call returns `{data: <number>}` so we unwrap `data` and parse.
///
/// Uses ApiClient.sas4 which already has the auth interceptor wired —
/// requests get the Bearer token attached automatically, and a 401 (or
/// the SAS4-specific 200 OK with `message: 'Token has expired'` envelope)
/// triggers refresh-token + retry once, transparently to the caller.
class Sas4Api {
  Sas4Api._();

  static const String _kUsersCount = '/widgetData/internal/wd_users_count';
  static const String _kActiveCount =
      '/widgetData/internal/wd_users_active_count';
  static const String _kExpiredCount =
      '/widgetData/internal/wd_users_expired_count';
  static const String _kOnline = '/widgetData/internal/wd_users_online';
  static const String _kBalance = '/widgetData/internal/wd_balance';

  /// Fetches all 5 widget metrics in parallel. Each individual call is
  /// allowed to fail (returns null) — partial results still update the
  /// dashboard rather than blocking everything on one slow endpoint.
  static Future<Sas4Stats> fetchAll() async {
    if (!kReleaseMode) debugPrint('🔵 SAS4 widgets → calling');

    Future<dynamic> hit(String name, String url) {
      // ⚠️ `then<dynamic>` ضروريّ لا تجميليّ: بدونه يبقى المستقبَل
      // `Future<Response>`، فـ`catchError` التي تُعيد null ترمي
      // TypeError وقت الفشل بدل أن تبتلعه — فيسقط `Future.wait`
      // أدناه بكامله، وتنهار إحصاءات الداشبورد كلّها لأنّ نقطة
      // واحدة تعطّلت.
      return ApiClient.sas4.get(url).then<dynamic>((r) {
        if (!kReleaseMode) {
          debugPrint('🟢 SAS4 $name: status=${r.statusCode} data=${r.data}');
        }
        return r;
      }).catchError((e) {
        if (!kReleaseMode) debugPrint('🔴 SAS4 $name failed: $e');
        return null;
      });
    }

    final results = await Future.wait<dynamic>([
      hit('users_count', _kUsersCount),
      hit('active_count', _kActiveCount),
      hit('expired_count', _kExpiredCount),
      hit('online', _kOnline),
      hit('balance', _kBalance),
    ]);

    final stats = Sas4Stats(
      total: _toInt(results[0]),
      active: _toInt(results[1]),
      expired: _toInt(results[2]),
      online: _toInt(results[3]),
      balance: _toString(results[4]),
    );
    if (!kReleaseMode) {
      debugPrint(
          '🟢 SAS4 final stats: total=${stats.total} active=${stats.active} '
          'expired=${stats.expired} online=${stats.online} balance=${stats.balance}');
    }
    return stats;
  }

  static int? _toInt(dynamic resp) {
    final payload = resp is Response ? resp.data : resp;
    if (payload == null) return null;
    if (payload is Map && payload['data'] != null) {
      return int.tryParse(payload['data'].toString());
    }
    if (payload is int) return payload;
    if (payload is num) return payload.toInt();
    return int.tryParse(payload.toString());
  }

  static String? _toString(dynamic resp) {
    final payload = resp is Response ? resp.data : resp;
    if (payload == null) return null;
    if (payload is Map && payload['data'] != null) {
      return payload['data'].toString();
    }
    return payload.toString();
  }
}

class Sas4Stats {
  const Sas4Stats({
    this.total,
    this.active,
    this.expired,
    this.online,
    this.balance,
  });

  final int? total;
  final int? active;
  final int? expired;
  final int? online;
  final String? balance;

  Map<String, dynamic> toJson() => {
        'total': total,
        'active': active,
        'expired': expired,
        'online': online,
        'balance': balance,
      };

  factory Sas4Stats.fromJson(Map<String, dynamic> j) => Sas4Stats(
        total: (j['total'] as num?)?.toInt(),
        active: (j['active'] as num?)?.toInt(),
        expired: (j['expired'] as num?)?.toInt(),
        online: (j['online'] as num?)?.toInt(),
        balance: j['balance'] as String?,
      );
}
