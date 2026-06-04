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

/// Process-wide cache for the subscribers list — the with-phones
/// endpoint is the heaviest call on the dashboard (returns every row
/// for the admin) AND the same call powers the subscribers tab. Without
/// this cache the app fires it TWICE on initial open. The cache is
/// keyed by adminId and held for [_ttl]; both Dashboard.fetchDebtors and
/// SubscribersApi.loadAll go through this gate.
///
/// Also de-dupes in-flight requests so 2 concurrent callers share one
/// network call instead of racing.
class _SubsListCache {
  _SubsListCache._();
  static const _ttl = Duration(seconds: 45);

  static List<Subscriber>? _list;
  static DateTime? _at;
  static Future<List<Subscriber>?>? _inFlight;

  static Future<List<Subscriber>?> get() {
    final now = DateTime.now();
    if (_list != null && _at != null && now.difference(_at!) < _ttl) {
      return Future.value(_list);
    }
    final running = _inFlight;
    if (running != null) return running;
    final fresh = _fetch();
    _inFlight = fresh;
    return fresh;
  }

  static Future<List<Subscriber>?> _fetch() async {
    try {
      final result = await SubscribersApi._loadAllRaw();
      if (result != null) {
        _list = result;
        _at = DateTime.now();
      }
      return result;
    } finally {
      _inFlight = null;
    }
  }

  /// Forces a refetch on next get() — used by pull-to-refresh on the
  /// subscribers screen so the admin always sees fresh data on demand.
  static void invalidate() {
    _list = null;
    _at = null;
  }
}

/// Subscribers API — wraps the same endpoints v1 uses so v2 reads the
/// exact same data the v1 mobile app reads. The list comes from the
/// backend /api/subscribers/with-phones endpoint which already joins
/// active subscribers with their stored phones, debts, and discounts.
class SubscribersApi {
  SubscribersApi._();

  /// GET /api/v2/packages — fetches the package catalogue (id → name
  /// + sale price) so we can fill in subscriber.profileName + price
  /// when the with-phones row only carried profile_id. Mirrors v1's
  /// loadPackages + _enrichWithPackage flow + priceList enrichment.
  static Future<Map<String, PackageInfo>?> loadPackages() async {
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
      final out = <String, PackageInfo>{};
      for (final row in rows) {
        if (row is! Map) continue;
        final id = (row['id'] ?? row['profile_id'])?.toString();
        final name = (row['name'] ?? row['profile_name'])?.toString();
        if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
        // Backend's /api/v2/packages returns `price` as the user-facing
        // sale price (priceList.user_price/sale_price). 0 means 'no
        // price loaded' — store as null so the card knows to hide the
        // chip instead of rendering '0 د.ع'.
        final rawPrice = row['price'] ?? row['user_price'] ?? row['sale_price'];
        num? price;
        if (rawPrice is num) {
          price = rawPrice > 0 ? rawPrice : null;
        } else {
          final parsed = num.tryParse((rawPrice ?? '').toString().replaceAll(',', ''));
          price = (parsed != null && parsed > 0) ? parsed : null;
        }
        out[id] = PackageInfo(name: name, price: price);
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

  /// GET /api/subscribers/with-phones — process-wide cached for 45s
  /// so Dashboard and SubscribersScreen don't double-fetch on app
  /// open. Use [refreshAll] for pull-to-refresh.
  static Future<List<Subscriber>?> loadAll() => _SubsListCache.get();

  /// Forces the next `loadAll` to re-fetch from the backend instead
  /// of serving the cached list. Hooked to the subscribers screen
  /// pull-to-refresh.
  static Future<List<Subscriber>?> refreshAll() {
    _SubsListCache.invalidate();
    return _SubsListCache.get();
  }

  /// Raw fetch — used internally by the cache. Don't call directly.
  static Future<List<Subscriber>?> _loadAllRaw() async {
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

  /// GET /user/disconnect/acctid/{idx} on SAS4 — forces the subscriber
  /// off the network if they currently have an active session. Mirrors
  /// v1's `disconnectUser`. SAS4 returns 200 on success; any non-200
  /// is treated as failure.
  static Future<bool> disconnect(String idx) async {
    try {
      final r = await ApiClient.sas4.get('/user/disconnect/acctid/$idx');
      if (!kReleaseMode) {
        debugPrint('🟢 SAS4 disconnect $idx: status=${r.statusCode}');
      }
      return r.statusCode != null && r.statusCode! < 400;
    } on DioException catch (e) {
      _log('SAS4 disconnect/$idx', e);
      return false;
    } catch (e) {
      _log('SAS4 disconnect/$idx', e);
      return false;
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
