import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/subscriber.dart';
import '../services/auth_storage.dart';
import 'api_client.dart';

/// Live session data for one currently-connected subscriber. Pulled
/// from /api/v2/online-users so we can show DL/UL bytes + session time
/// on the detail screen without per-row fetches.
class OnlineSessionInfo {
  const OnlineSessionInfo({
    this.ip,
    this.mac,
    this.sessionTime,
    this.downloadBytes,
    this.uploadBytes,
    this.device,
  });
  final String? ip;
  final String? mac;
  final int? sessionTime;
  final int? downloadBytes;
  final int? uploadBytes;
  /// `device` from /api/v2/online-users (SAS4 `oui` — Huawei/Mikrotik/etc).
  final String? device;
}

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

  /// GET /api/v2/online-users — keyed map from lowercase username to
  /// the live session row (IP, MAC, session_time, download_bytes,
  /// upload_bytes). The screen merges this into each subscriber so
  /// the detail page can show actual DL/UL numbers instead of zeros.
  static Future<Map<String, OnlineSessionInfo>?> loadOnline() async {
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
      // Diagnostic: dump the first online row so we can see whether
      // the byte counters actually come through from the backend.
      // The user's report said DL/UL show as 0 on the card; this log
      // tells us whether the data is missing or just being mis-merged.
      if (!kReleaseMode && rows.isNotEmpty && rows.first is Map) {
        final first = rows.first as Map;
        debugPrint('🔍 online[0]: $first');
      }
      final out = <String, OnlineSessionInfo>{};
      int? toInt(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString());
      }
      for (final row in rows) {
        if (row is! Map) continue;
        final u = row['username']?.toString().toLowerCase();
        if (u == null || u.isEmpty) continue;
        out[u] = OnlineSessionInfo(
          ip: row['ip']?.toString(),
          mac: row['mac']?.toString(),
          sessionTime: toInt(row['session_time']),
          downloadBytes: toInt(row['download_bytes']),
          uploadBytes: toInt(row['upload_bytes']),
          device: row['device']?.toString(),
        );
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
  /// Hits /api/v2/subscribers (NOT /api/subscribers/with-phones).
  /// The legacy with-phones endpoint asks SAS4 for column 'idx' which
  /// SAS4 doesn't honor — the response comes back without a primary
  /// key, breaking activate/extend/disconnect (user's logs showed
  /// id=null idx=null on every row). /api/v2/subscribers asks SAS4
  /// for BOTH 'idx' AND 'id' so the primary key always lands, exactly
  /// like v1's direct SAS4 admin_list call.
  static Future<List<Subscriber>?> _loadAllRaw() async {
    final token = await AuthStorage.readToken();
    if (token == null) return null;
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers',
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
      // Diagnostic: dump the FIRST row's keys + every id-ish field +
      // the raw JSON so we can see why Subscriber.idx ends up null on
      // some admin trees (the user just hit 'المشترك بدون idx' on
      // activate/extend). One-shot — first row only.
      if (!kReleaseMode && data.isNotEmpty && data.first is Map) {
        final first = data.first as Map;
        debugPrint('🔍 first subscriber keys: ${first.keys.toList()}');
        debugPrint(
            '🔍 first subscriber id-fields: id=${first['id']} idx=${first['idx']} ID=${first['ID']} acctid=${first['acctid']} user_id=${first['user_id']}');
        debugPrint('🔍 first subscriber raw: $first');
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

  /// GET /api/v2/subscribers/:idx/activation-data — pulls everything
  /// the activate sheet needs to display in one round-trip:
  ///   - sale price (user_price), already adjusted for sub-reseller
  ///     n_required_amount fallback
  ///   - active discount + price after discount
  ///   - profile name + duration + units (renewal length)
  ///   - current balance (subscriber notes)
  ///   - manager balance + reward points
  /// The whole map is cached on the screen side and re-sent on activate
  /// (the backend enforces this — see /activate endpoint comment about
  /// SAS4 session lock).
  static Future<Map<String, dynamic>?> fetchActivationData(String idx) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers/$idx/activation-data',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        if (!kReleaseMode) {
          debugPrint('🟡 activation-data($idx): success!=true body=$body');
        }
        return null;
      }
      return (body['data'] as Map?)?.cast<String, dynamic>();
    } on DioException catch (e) {
      _log('activation-data/$idx', e);
      return null;
    } catch (e) {
      _log('activation-data/$idx', e);
      return null;
    }
  }

  /// Result of an activate call. ok=true on success; ok=false carries
  /// the backend's Arabic error message for the UI.
  static Future<({bool ok, String? message})> activate({
    required String idx,
    required String paymentType, // 'cash' | 'partial-cash' | 'non-cash'
    required Map<String, dynamic> activationData,
    int? partialAmount,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/subscribers/$idx/activate',
        data: {
          'paymentType': paymentType,
          'activationData': activationData,
          if (paymentType == 'partial-cash' && partialAmount != null)
            'partialAmount': partialAmount,
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      return (ok: ok, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('activate/$idx', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر التفعيل');
    } catch (e) {
      _log('activate/$idx', e);
      return (ok: false, message: 'تعذّر التفعيل');
    }
  }

  /// GET /api/v2/subscribers/:idx/extension-options — the list of
  /// packages this subscriber can extend INTO + current
  /// manager_balance + reward_points_balance. The current profile is
  /// excluded by the backend (you can't extend into the same package).
  /// Each entry: id, name, price, reward_points_required, duration.
  static Future<Map<String, dynamic>?> fetchExtensionOptions(String idx) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/subscribers/$idx/extension-options',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) {
        if (!kReleaseMode) {
          debugPrint('🟡 extension-options($idx): success!=true body=$body');
        }
        return null;
      }
      return (body['data'] as Map?)?.cast<String, dynamic>();
    } on DioException catch (e) {
      _log('extension-options/$idx', e);
      return null;
    } catch (e) {
      _log('extension-options/$idx', e);
      return null;
    }
  }

  /// POST /api/v2/subscribers/:idx/extend — extend into a new package.
  /// Method: 'balance' (charge manager wallet) or 'points' (deduct
  /// reward points).
  static Future<({bool ok, String? message})> extend({
    required String idx,
    required String profileId,
    required String method, // 'balance' | 'points'
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/subscribers/$idx/extend',
        data: {'profile_id': profileId, 'method': method},
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      return (ok: ok, message: body['message']?.toString());
    } on DioException catch (e) {
      _log('extend/$idx', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر التمديد');
    } catch (e) {
      _log('extend/$idx', e);
      return (ok: false, message: 'تعذّر التمديد');
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
