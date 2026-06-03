import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/subscriber.dart';
import '../services/auth_storage.dart';
import 'api_client.dart';

/// Subscribers API — wraps the same endpoints v1 uses so v2 reads the
/// exact same data the v1 mobile app reads. The list comes from the
/// backend /api/subscribers/with-phones endpoint which already joins
/// active subscribers with their stored phones, debts, and discounts.
class SubscribersApi {
  SubscribersApi._();

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
