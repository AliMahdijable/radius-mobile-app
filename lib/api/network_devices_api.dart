import 'package:dart_ping/dart_ping.dart';
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

  /// ICMP ping محلّي (من الموبايل على LAN) — يعمل على iOS + Android.
  /// أدقّ من TCP لأنّه لا يعتمد على منفذ محدّد. يرسل count ping ويرجع
  /// متوسّط الاستجابة + status.
  static Future<({String status, int? responseMs, double? packetLoss})> localIcmpPing({
    required String ip,
    int count = 3,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    try {
      final ping = Ping(ip, count: count, timeout: timeout.inSeconds);
      final times = <int>[];
      int received = 0;
      // dart_ping 10.x: PingEvent = sealed (PingResponse | PingError | PingSummary)
      await for (final event in ping.stream) {
        if (event is PingResponse) {
          if (event.time != null) {
            times.add(event.time!.inMilliseconds);
            received++;
          }
        } else if (event is PingSummary) {
          break;
        }
      }
      if (received == 0) {
        return (status: 'offline', responseMs: null, packetLoss: 100.0);
      }
      final avg = (times.reduce((a, b) => a + b) / times.length).round();
      final loss = ((count - received) / count) * 100.0;
      return (status: 'online', responseMs: avg, packetLoss: loss);
    } catch (e) {
      if (kDebugMode) print('⚠️ localIcmpPing failed: $e');
      return (status: 'offline', responseMs: null, packetLoss: 100.0);
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
