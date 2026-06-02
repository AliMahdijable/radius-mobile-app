import 'package:dio/dio.dart';

import '../services/auth_storage.dart';

/// SAS4 widget endpoints — same set v1's dashboard_provider hits.
/// Each call returns `{data: <number>}` so we unwrap `data` and parse.
///
/// SAS4 lives at a separate host. Auth: the user's main token doubles
/// as the SAS4 token for regular admins (and the parent admin's token
/// for employees — that distinction lives at login time and is the
/// same value we save in AuthStorage.readToken()).
class Sas4Api {
  Sas4Api._();

  static const String _baseUrl =
      'https://reseller-supernet.net/admin/api/index.php/api';

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    headers: const {'Accept': 'application/json'},
    validateStatus: (s) => s != null && s < 500,
  ));

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
    final token = await AuthStorage.readToken();
    if (token == null) return const Sas4Stats();

    final opts = Options(headers: {
      'Authorization': 'Bearer $token',
      'x-auth-token': token,
    });

    final results = await Future.wait<dynamic>([
      _dio.get(_kUsersCount, options: opts).catchError((_) => null),
      _dio.get(_kActiveCount, options: opts).catchError((_) => null),
      _dio.get(_kExpiredCount, options: opts).catchError((_) => null),
      _dio.get(_kOnline, options: opts).catchError((_) => null),
      _dio.get(_kBalance, options: opts).catchError((_) => null),
    ]);

    return Sas4Stats(
      total: _toInt(results[0]),
      active: _toInt(results[1]),
      expired: _toInt(results[2]),
      online: _toInt(results[3]),
      balance: _toString(results[4]),
    );
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
}
