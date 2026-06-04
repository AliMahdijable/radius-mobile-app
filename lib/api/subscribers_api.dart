import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/subscriber.dart';
import '../services/auth_storage.dart';
import 'api_client.dart';

/// Set of usernames currently online (from /api/v2/online-users) and a
/// map of username→last-payment row (from /api/subscribers/
/// last-financial-movements). Both are merged into the subscribers list
/// on the screen side so cards can show the live flags + payment line
/// without re-fetching per row.
class LiveOverlay {
  const LiveOverlay({
    required this.onlineUsernames,
    required this.lastPaymentByUsername,
  });
  final Set<String> onlineUsernames;
  final Map<String, Map<String, dynamic>> lastPaymentByUsername;
}

/// Subscribers API — wraps the same endpoints v1 uses so v2 reads the
/// exact same data the v1 mobile app reads. The list comes from the
/// backend /api/subscribers/with-phones endpoint which already joins
/// active subscribers with their stored phones, debts, and discounts.
class SubscribersApi {
  SubscribersApi._();

  /// GET /api/v2/packages — fetches the package catalogue (id → name)
  /// so we can fill in subscriber.profileName when the with-phones row
  /// only carried profile_id (which is what SAS4 actually sends most
  /// of the time). Mirrors v1's loadPackages + _enrichWithPackage flow.
  /// Returns a Map keyed by profile_id (as String).
  static Future<Map<String, String>?> loadPackages() async {
    final token = await AuthStorage.readToken();
    if (token == null) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/packages');
      final body = r.data ?? const {};
      if (body['success'] != true) {
        if (!kReleaseMode) {
          debugPrint('🟡 v2/packages: success!=true body=$body');
        }
        return null;
      }
      final rows = (body['data'] as List?) ?? const [];
      final out = <String, String>{};
      for (final row in rows) {
        if (row is! Map) continue;
        final id = (row['id'] ?? row['profile_id'])?.toString();
        final name = (row['name'] ?? row['profile_name'])?.toString();
        if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
          out[id] = name;
        }
      }
      if (!kReleaseMode) debugPrint('🟢 v2/packages: ${out.length} loaded');
      return out;
    } on DioException catch (e) {
      _log('v2/packages', e);
      return null;
    } catch (e) {
      _log('v2/packages', e);
      return null;
    }
  }

  /// GET /api/v2/online-users — list of subscribers currently
  /// connected (SAS4 online widget, paginated 8×250 on the backend).
  /// Returns just the lowercase usernames for fast O(1) membership tests.
  static Future<Set<String>?> loadOnline() async {
    final token = await AuthStorage.readToken();
    if (token == null) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/online-users',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        if (!kReleaseMode) {
          debugPrint('🟡 v2/online-users: success!=true body=$body');
        }
        return null;
      }
      final rows = (body['data'] as List?) ?? const [];
      final out = <String>{};
      for (final row in rows) {
        if (row is Map) {
          final u = row['username']?.toString().toLowerCase();
          if (u != null && u.isNotEmpty) out.add(u);
        }
      }
      return out;
    } on DioException catch (e) {
      _log('v2/online-users', e);
      return null;
    } catch (e) {
      _log('v2/online-users', e);
      return null;
    }
  }

  /// GET /api/subscribers/last-financial-movements/{adminId} — recent
  /// payment per subscriber. Same endpoint v1 hits; falls back to
  /// last-payments if the modern one isn't available.
  static Future<Map<String, Map<String, dynamic>>?> loadLastPayments() async {
    final token = await AuthStorage.readToken();
    final adminId = await AuthStorage.readAdminId();
    if (token == null || adminId == null) return null;
    Future<Map<String, Map<String, dynamic>>?> tryUrl(String url) async {
      try {
        final r = await ApiClient.dio.get<Map<String, dynamic>>(
          url,
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
        final body = r.data ?? const {};
        if (body['success'] != true) return null;
        final list = (body['payments'] as List?) ?? const [];
        final out = <String, Map<String, dynamic>>{};
        for (final p in list) {
          if (p is Map) {
            final u = p['subscriber_username']?.toString();
            if (u != null && u.isNotEmpty) {
              out[u] = Map<String, dynamic>.from(p);
            }
          }
        }
        return out;
      } catch (e) {
        _log(url, e);
        return null;
      }
    }
    final modern = await tryUrl(
        '/api/subscribers/last-financial-movements/$adminId');
    if (modern != null) return modern;
    return tryUrl('/api/subscribers/last-payments/$adminId');
  }

  /// GET /api/subscribers/with-phones — returns every subscriber with
  /// phone/debt/discount/expiration prefilled.
  static Future<List<Subscriber>?> loadAll() async {
    final token = await AuthStorage.readToken();
    if (token == null) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/subscribers/with-phones',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        if (!kReleaseMode) {
          debugPrint('🟡 subscribers/with-phones: success!=true body=$body');
        }
        return null;
      }
      final data = (body['data'] as List?) ?? const [];
      // Diagnostic: dump the FIRST row's keys + sample values so we
      // can see which field actually carries the package name (the v2
      // model was reading null for hakem@poox — maybe SAS4 puts it
      // somewhere we haven't tried). One-shot — first row only.
      if (!kReleaseMode && data.isNotEmpty && data.first is Map) {
        final first = data.first as Map;
        debugPrint('🔍 first subscriber keys: ${first.keys.toList()}');
        debugPrint('🔍 first subscriber profile_details=${first['profile_details']}');
        debugPrint('🔍 first subscriber profile_name=${first['profile_name']} name=${first['name']} profile_id=${first['profile_id']}');
      }
      return data
          .whereType<Map>()
          .map((m) => Subscriber.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } on DioException catch (e) {
      _log('with-phones', e);
      return null;
    } catch (e) {
      _log('with-phones', e);
      return null;
    }
  }

  /// POST /api/subscribers/{id}/toggle — disable or enable.
  static Future<bool> toggle(String id, {required bool enable}) async {
    final token = await AuthStorage.readToken();
    if (token == null) return false;
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/subscribers/$id/toggle',
        data: {'enabled': enable ? 1 : 0},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return r.data?['success'] == true;
    } on DioException catch (e) {
      _log('subscribers/$id/toggle', e);
      return false;
    } catch (e) {
      _log('subscribers/$id/toggle', e);
      return false;
    }
  }

  /// DELETE /api/subscribers/{id}.
  static Future<bool> delete(String id) async {
    final token = await AuthStorage.readToken();
    if (token == null) return false;
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/subscribers/$id',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return r.data?['success'] == true;
    } on DioException catch (e) {
      _log('DELETE subscribers/$id', e);
      return false;
    } catch (e) {
      _log('DELETE subscribers/$id', e);
      return false;
    }
  }

  static void _log(String endpoint, Object err) {
    if (kReleaseMode) return;
    if (err is DioException) {
      debugPrint(
        '🔴 $endpoint: status=${err.response?.statusCode} body=${err.response?.data}',
      );
    } else {
      debugPrint('🔴 $endpoint: $err');
    }
  }
}
