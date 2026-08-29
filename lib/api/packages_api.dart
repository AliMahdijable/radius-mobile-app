import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// SAS4 package — enriched with price + cost from /priceList.
class Package {
  const Package({
    required this.id,
    required this.name,
    this.userPrice,
    this.cost,
    this.basePrice,
    this.downrate,
    this.uprate,
    this.expirationAmount,
    this.usersCount,
    this.type,
  });
  final int id;
  final String name;

  /// سعر البيع للمشترك — اللي يطبع على الوصل.
  final num? userPrice;

  /// كلفة الباقة على المدير الفرعي (سعر شراء من السوبر).
  final num? cost;

  /// السعر الأصلي من SAS4 (لـSAS4 admins). أحياناً = userPrice.
  final num? basePrice;
  final int? downrate;
  final int? uprate;
  final int? expirationAmount;
  final int? usersCount;
  final String? type;

  static Package? fromJson(Map<String, dynamic> j) {
    final id = j['id'] ?? j['profile_id'];
    final idInt = id is int ? id : int.tryParse(id?.toString() ?? '');
    if (idInt == null) return null;
    final name = (j['name'] ?? j['profile_name'] ?? '').toString();
    if (name.isEmpty) return null;
    num? toNum(dynamic v) =>
        v is num ? v : (v == null ? null : num.tryParse(v.toString()));
    int? toInt(dynamic v) =>
        v is int ? v : (v == null ? null : int.tryParse(v.toString()));
    return Package(
      id: idInt,
      name: name,
      userPrice: toNum(j['user_price'] ?? j['sale_price']),
      cost: toNum(j['cost']),
      basePrice: toNum(j['price']),
      downrate: toInt(j['downrate']),
      uprate: toInt(j['uprate']),
      expirationAmount: toInt(j['expiration_amount']),
      usersCount: toInt(j['users_count']),
      type: j['type']?.toString(),
    );
  }
}

class PackagesApi {
  PackagesApi._();

  /// GET /api/v2/packages — list all packages with prices for the
  /// CURRENT admin (تسعيري الخاص). Returns enriched rows with downrate
  /// / uprate / users_count / type when SAS4 provides them.
  static Future<List<Package>> list() async {
    try {
      final r =
          await ApiClient.dio.get<Map<String, dynamic>>('/api/v2/packages');
      final body = r.data ?? const {};
      if (body['success'] != true) return const [];
      final list = body['data'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => Package.fromJson(Map<String, dynamic>.from(m)))
          .whereType<Package>()
          .toList();
    } on DioException catch (e) {
      _log('v2/packages (GET)', e);
      return const [];
    } catch (e) {
      _log('v2/packages (GET)', e);
      return const [];
    }
  }

  /// GET /api/v2/price-list/:managerId — list prices for a SPECIFIC
  /// sub-manager. Used by the super-admin/parent to view/edit a
  /// sub-manager's price list. Returns minimal Package rows (id, name,
  /// userPrice, cost, basePrice) — no SAS4 metadata.
  static Future<List<Package>> listForManager(int managerId) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/price-list/$managerId',
      );
      final body = r.data ?? const {};
      if (body['success'] != true) return const [];
      final list = body['data'];
      if (list is! List) return const [];
      return list
          .whereType<Map>()
          .map((m) => Package.fromJson(Map<String, dynamic>.from(m)))
          .whereType<Package>()
          .toList();
    } on DioException catch (e) {
      _log('v2/price-list/$managerId (GET)', e);
      return const [];
    } catch (e) {
      _log('v2/price-list/$managerId (GET)', e);
      return const [];
    }
  }

  /// POST /api/v2/price-list — save updated prices for a manager.
  /// payload is a list of (profile_id, profile_name, price, cost,
  /// user_price). The screen builds it from the current Package list
  /// and the user's edits — مطلب 2026-06-12 يحرّر `price` (سعر شراء
  /// المدير من الأب) إضافة إلى `user_price` (سعر البيع للمشترك).
  static Future<({bool ok, String? message})> savePrices({
    required int managerId,
    required List<Map<String, dynamic>> priceList,
  }) async {
    try {
      final r = await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/price-list',
        data: {
          'manager_id': managerId,
          'priceList': priceList,
        },
      );
      final body = r.data ?? const {};
      return (
        ok: body['success'] == true,
        message: body['message']?.toString()
      );
    } on DioException catch (e) {
      _log('v2/price-list (POST)', e);
      final body = e.response?.data;
      final msg = body is Map ? body['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر الحفظ');
    } catch (e) {
      _log('v2/price-list (POST)', e);
      return (ok: false, message: 'تعذّر الحفظ');
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
