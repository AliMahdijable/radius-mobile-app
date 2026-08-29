import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// One discount row stored in the admin's admin_discounts table.
class Discount {
  const Discount({
    required this.id,
    required this.subscriberUsername,
    required this.discountAmount,
    this.packageName,
    this.packagePrice,
    this.subscriberId,
    this.notes,
    this.createdAt,
  });
  final int id;
  final String subscriberUsername;
  final num discountAmount;
  final String? packageName;
  final num? packagePrice;
  final int? subscriberId;
  final String? notes;
  final String? createdAt;

  /// السعر بعد الخصم — useful for the UI to show the "بعد الخصم" pill.
  num? get effectivePrice {
    final p = packagePrice;
    if (p == null) return null;
    final after = p - discountAmount;
    return after < 0 ? 0 : after;
  }

  static Discount? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final idInt = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (idInt == null) return null;
    final username = (j['subscriber_username'] ?? '').toString();
    if (username.isEmpty) return null;
    num? toNum(dynamic v) =>
        v is num ? v : (v == null ? null : num.tryParse(v.toString()));
    int? toInt(dynamic v) =>
        v is int ? v : (v == null ? null : int.tryParse(v.toString()));
    return Discount(
      id: idInt,
      subscriberUsername: username,
      discountAmount: toNum(j['discount_amount']) ?? 0,
      packageName: j['package_name']?.toString(),
      packagePrice: toNum(j['package_price']),
      subscriberId: toInt(j['subscriber_id']),
      notes: j['notes']?.toString(),
      createdAt: j['created_at']?.toString(),
    );
  }
}

class DiscountsApi {
  DiscountsApi._();

  /// GET /api/discounts
  static Future<List<Discount>> list() async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>('/api/discounts');
      final body = r.data ?? const {};
      if (body['success'] != true) return const [];
      final list = body['data'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => Discount.fromJson(Map<String, dynamic>.from(m)))
          .whereType<Discount>()
          .toList();
    } on DioException catch (e) {
      _log('discounts (GET)', e);
      return const [];
    } catch (e) {
      _log('discounts (GET)', e);
      return const [];
    }
  }

  /// POST /api/discounts
  static Future<({bool ok, String? message, int? id})> create({
    required String subscriberUsername,
    required num discountAmount,
    int? subscriberId,
    String? packageName,
    num? packagePrice,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/discounts',
        data: {
          'subscriber_username': subscriberUsername,
          'discount_amount': discountAmount,
          if (subscriberId != null) 'subscriber_id': subscriberId,
          if (packageName != null && packageName.isNotEmpty)
            'package_name': packageName,
          if (packagePrice != null) 'package_price': packagePrice,
        },
      );
      final body = r.data ?? const {};
      final rawId = body['id'] ?? body['data']?['id'];
      final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        id: id,
      );
    } on DioException catch (e) {
      _log('discounts (POST)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الإنشاء', id: null);
    } catch (e) {
      _log('discounts (POST)', e);
      return (ok: false, message: 'تعذّر الإنشاء', id: null);
    }
  }

  /// PUT /api/discounts/:id
  static Future<({bool ok, String? message})> update({
    required int id,
    required num discountAmount,
  }) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/discounts/$id',
        data: {'discount_amount': discountAmount},
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
    } on DioException catch (e) {
      _log('discounts (PUT)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر التعديل');
    } catch (e) {
      _log('discounts (PUT)', e);
      return (ok: false, message: 'تعذّر التعديل');
    }
  }

  /// POST /api/v2/discounts/bulk-apply — apply ONE amount to MANY
  /// subscribers. Backend upserts: returns count of new + updated +
  /// failed usernames so the UI can show a precise snackbar.
  static Future<
          ({bool ok, int applied, int updated, int failed, String? message})>
      bulkApply({
    required List<String> usernames,
    required num discountAmount,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/discounts/bulk-apply',
        data: {
          'usernames': usernames,
          'discount_amount': discountAmount,
        },
      );
      final body = r.data ?? const {};
      final ok = body['success'] == true;
      int toInt(dynamic v) =>
          v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
      final failedList = body['failed'];
      final failedCount =
          failedList is List ? failedList.length : toInt(failedList);
      return (
        ok: ok,
        applied: toInt(body['applied']),
        updated: toInt(body['updated']),
        failed: failedCount,
        message: body['message']?.toString(),
      );
    } on DioException catch (e) {
      _log('v2/discounts/bulk-apply', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (
        ok: false,
        applied: 0,
        updated: 0,
        failed: 0,
        message: msg ?? 'تعذّر التطبيق',
      );
    } catch (e) {
      _log('v2/discounts/bulk-apply', e);
      return (
        ok: false,
        applied: 0,
        updated: 0,
        failed: 0,
        message: 'تعذّر التطبيق',
      );
    }
  }

  /// DELETE /api/discounts/:id
  static Future<({bool ok, String? message})> delete(int id) async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/discounts/$id',
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
    } on DioException catch (e) {
      _log('discounts (DELETE)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الحذف');
    } catch (e) {
      _log('discounts (DELETE)', e);
      return (ok: false, message: 'تعذّر الحذف');
    }
  }

  /// DELETE /api/discounts — حذف كل خصومات الـadmin. مطابق v1
  /// mobile-app/lib/screens/discounts_screen.dart:177 (_confirmDeleteAll).
  /// الـbackend يرجع عدد الخصومات المحذوفة كي نطبع رسالة دقيقة.
  static Future<({bool ok, String? message, int deleted})> deleteAll() async {
    try {
      final r = await ApiClient.dio.delete<Map<String, dynamic>>(
        '/api/discounts',
      );
      final body = r.data ?? const {};
      final rawDel = body['deleted'];
      final del =
          rawDel is int ? rawDel : int.tryParse(rawDel?.toString() ?? '') ?? 0;
      return (
        ok: body['success'] == true,
        message: body['message']?.toString(),
        deleted: del,
      );
    } on DioException catch (e) {
      _log('discounts deleteAll', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الحذف', deleted: 0);
    } catch (e) {
      _log('discounts deleteAll', e);
      return (ok: false, message: 'تعذّر الحذف', deleted: 0);
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
