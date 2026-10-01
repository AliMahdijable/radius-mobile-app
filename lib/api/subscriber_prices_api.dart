import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// «أسعار المشتركين» — سعر بيعٍ ثابت لمشتركٍ بعينه.
///
/// القواعد كلّها في الخادم (`server/subscriberPricing.js`): الثابت يلغي
/// الخصم، ومربوطٌ بباقة المشترك فإن تغيّرت يرجع الطبيعيّ مع تنبيه.
/// التطبيق لا يحسب مبلغاً — يقرأ ما يعيده الخادم في activation-data
/// والقائمة.
class SubscriberPrice {
  const SubscriberPrice({
    required this.idx,
    required this.username,
    required this.price,
    this.profileId,
    this.profileName,
    this.normalPrice,
    this.setByAdminUsername,
    this.updatedAt,
  });

  final String idx;
  final String username;
  final num price;
  final int? profileId;
  final String? profileName;

  /// السعر الطبيعي للباقة التي سُعّرت (من قائمة أسعار المدير) أو null.
  final num? normalPrice;
  final String? setByAdminUsername;
  final String? updatedAt;

  static SubscriberPrice? fromJson(Map<String, dynamic> j) {
    final idx = (j['idx'] ?? '').toString();
    final username = (j['username'] ?? '').toString();
    num? toNum(dynamic v) =>
        v is num ? v : (v == null ? null : num.tryParse(v.toString()));
    final price = toNum(j['price']);
    if (idx.isEmpty || username.isEmpty || price == null) return null;
    final pid = j['profile_id'];
    return SubscriberPrice(
      idx: idx,
      username: username,
      price: price,
      profileId: pid is int ? pid : int.tryParse(pid?.toString() ?? ''),
      profileName: j['profile_name']?.toString(),
      normalPrice: toNum(j['normal_price']),
      setByAdminUsername: j['set_by_admin_username']?.toString(),
      updatedAt: j['updated_at']?.toString(),
    );
  }
}

class SubscriberPricesApi {
  SubscriberPricesApi._();

  static String? _message(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['message'] != null) return d['message'].toString();
    }
    return null;
  }

  static void _log(String what, Object e) {
    if (!kReleaseMode) debugPrint('🔴 subscriber-prices/$what: $e');
  }

  /// GET /api/v2/subscriber-prices — أسعار المدير (من وضعها هو أو موظّفوه).
  /// `null` عند الفشل، لتفرّق الشاشة بين «لا شيء» و«تعذّر الجلب».
  static Future<List<SubscriberPrice>?> list() async {
    try {
      final r = await ApiClient.dio
          .get<Map<String, dynamic>>('/api/v2/subscriber-prices');
      final body = r.data ?? const {};
      if (body['success'] != true) return null;
      final data = body['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map>()
          .map((m) => SubscriberPrice.fromJson(Map<String, dynamic>.from(m)))
          .whereType<SubscriberPrice>()
          .toList();
    } catch (e) {
      _log('list', e);
      return null;
    }
  }

  /// POST /api/v2/subscribers/:idx/price — يُربط بباقة المشترك الحاليّة.
  static Future<({bool ok, String? message})> set(
      String idx, num price) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/subscribers/$idx/price',
        data: {'price': price},
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('set', e);
      return (ok: false, message: _message(e));
    }
  }

  /// DELETE /api/v2/subscribers/:idx/price — يرجع المشترك لسعره الطبيعي.
  static Future<({bool ok, String? message})> remove(String idx) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/v2/subscribers/$idx/price',
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
      );
    } catch (e) {
      _log('remove', e);
      return (ok: false, message: _message(e));
    }
  }

  /// POST /api/v2/subscriber-prices/bulk-apply — سعرٌ واحد لعدّة مشتركين.
  static Future<({bool ok, String? message, int applied, int failed})>
      bulkApply(List<String> idxs, num price) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/subscriber-prices/bulk-apply',
        data: {'idxs': idxs, 'price': price},
      );
      final body = r.data ?? const {};
      final data = body['data'] is Map ? body['data'] as Map : const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        applied: (data['applied'] is List) ? (data['applied'] as List).length : 0,
        failed: (data['failed'] is List) ? (data['failed'] as List).length : 0,
      );
    } catch (e) {
      _log('bulk-apply', e);
      return (ok: false, message: _message(e), applied: 0, failed: idxs.length);
    }
  }

  /// POST /api/v2/subscriber-prices/bulk-remove
  static Future<({bool ok, String? message, int removed})> bulkRemove(
      List<String> idxs) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/subscriber-prices/bulk-remove',
        data: {'idxs': idxs},
      );
      final body = r.data ?? const {};
      final data = body['data'] is Map ? body['data'] as Map : const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        removed: (data['removed'] is List) ? (data['removed'] as List).length : 0,
      );
    } catch (e) {
      _log('bulk-remove', e);
      return (ok: false, message: _message(e), removed: 0);
    }
  }
}
