import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/network_device.dart';
import 'api_client.dart';

/// API client لميزة الأجهزة (Devices Monitoring) — راجع
/// project_devices_monitoring_plan في memory. Slice 1: CRUD + probe.
class NetworkDevicesApi {
  /// GET /api/v2/admin/devices?brand=X&type=Y&status=Z
  static Future<List<NetworkDevice>> list({
    String? brand,
    String? type,
    String? status,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/admin/devices',
        queryParameters: {
          if (brand != null && brand.isNotEmpty) 'brand': brand,
          if (type != null && type.isNotEmpty) 'type': type,
          if (status != null && status.isNotEmpty) 'status': status,
        },
      );
      final data = (r.data?['data'] as List?) ?? const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(NetworkDevice.fromJson)
          .toList();
    } on DioException catch (e) {
      if (kDebugMode) print('❌ NetworkDevicesApi.list: ${e.message}');
      rethrow;
    }
  }

  /// POST /api/v2/admin/devices
  static Future<NetworkDevice> create(Map<String, dynamic> body) async {
    final r = await ApiClient.dio.post<Map<String, dynamic>>(
      '/api/v2/admin/devices',
      data: body,
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل إضافة الجهاز');
    }
    return NetworkDevice.fromJson(r.data!['data'] as Map<String, dynamic>);
  }

  /// PUT /api/v2/admin/devices/:id
  static Future<NetworkDevice> update(int id, Map<String, dynamic> body) async {
    final r = await ApiClient.dio.put<Map<String, dynamic>>(
      '/api/v2/admin/devices/$id',
      data: body,
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل التعديل');
    }
    return NetworkDevice.fromJson(r.data!['data'] as Map<String, dynamic>);
  }

  /// DELETE /api/v2/admin/devices/:id
  static Future<void> delete(int id) async {
    final r = await ApiClient.dio.delete<Map<String, dynamic>>(
      '/api/v2/admin/devices/$id',
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل الحذف');
    }
  }

  /// GET /api/v2/admin/devices/:id/credentials — يفكّ التشفير ويرجع الـcredentials
  /// (مطلوب عند فتح الـedit form لملء الحقول)
  static Future<Map<String, dynamic>> getCredentials(int id) async {
    final r = await ApiClient.dio.get<Map<String, dynamic>>(
      '/api/v2/admin/devices/$id/credentials',
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل جلب المعلومات');
    }
    final creds = r.data!['credentials'];
    if (creds is Map<String, dynamic>) return creds;
    return <String, dynamic>{};
  }

  /// TCP probe محلّي (من الموبايل على LAN) — يحاول socket connect على ip:port
  /// بـtimeout معطى، يرجع online + response_ms أو offline. **لا يمرّ عبر السيرفر**
  /// لأنّ السيرفر ما يوصل شبكة الوكيل. بعد الفحص، ترسل النتيجة لـsaveProbeResult.
  static Future<({String status, int? responseMs})> localTcpProbe({
    required String ip,
    required int port,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final sw = Stopwatch()..start();
    Socket? sock;
    try {
      sock = await Socket.connect(ip, port, timeout: timeout);
      sw.stop();
      await sock.close();
      return (status: 'online', responseMs: sw.elapsedMilliseconds);
    } catch (_) {
      return (status: 'offline', responseMs: null);
    } finally {
      try { await sock?.close(); } catch (_) {}
    }
  }

  /// POST /api/v2/admin/devices/:id/probe-result — يحفظ نتيجة الـprobe على السيرفر
  static Future<void> saveProbeResult({
    required int deviceId,
    required String status,
    int? responseMs,
  }) async {
    try {
      await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/admin/devices/$deviceId/probe-result',
        data: {'status': status, 'response_ms': responseMs},
      );
    } on DioException catch (e) {
      if (kDebugMode) print('⚠️ saveProbeResult: ${e.message}');
      // لا نـthrow — الفحص المحلّي نجح، حفظ النتيجة ثانوي
    }
  }
}
