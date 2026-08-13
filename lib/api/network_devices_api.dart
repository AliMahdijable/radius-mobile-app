import 'dart:io' show Socket;

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

  /// Local probe محلّي — يستعمل TCP كأولوية (أدقّ من ICMP على iOS)
  /// مع fallback على ICMP لو الـport مجهول.
  ///
  /// **iOS ICMP quirk**: dart_ping على iOS يرجع بيانات مزيّفة أحياناً
  /// (نفس latency=156ms لكل الأجهزة، أو "online" لأجهزة offline).
  /// السبب: iOS يمنع raw ICMP sockets بدون entitlement خاصّ، فالمكتبة
  /// تلجأ لـfallback غير موثوق.
  ///
  /// **الحل**: TCP connect probe:
  ///   - سريع (~1-100ms على LAN)
  ///   - دقيق (successful connect = server-side pipeline يستجيب)
  ///   - يعمل على iOS + Android بلا permissions
  ///
  /// نستعمل [tcpPort] لو متوفّر (Mikrotik=8728، UBNT=22، Mimosa=161).
  /// ICMP fallback فقط لأجهزة بلا port معروف.
  static Future<({String status, int? responseMs, double? packetLoss})> localIcmpPing({
    required String ip,
    int count = 3,
    Duration timeout = const Duration(seconds: 2),
    int? tcpPort,   // نُفضّله على ICMP
  }) async {
    // ── 1. TCP probe (الأولوية) ──
    if (tcpPort != null && tcpPort > 0) {
      return _tcpProbe(ip: ip, port: tcpPort, timeout: timeout);
    }
    // ── 2. ICMP fallback (لو ما فيه port) ──
    return _icmpProbe(ip: ip, count: count, timeout: timeout);
  }

  /// TCP connect probe — أدقّ probe للأجهزة على LAN.
  /// نجاح = الجهاز يقبل connections على هذا الـport (بمعنى: online + السيرفس شغّال).
  /// فشل = timeout أو refused → offline.
  static Future<({String status, int? responseMs, double? packetLoss})> _tcpProbe({
    required String ip,
    required int port,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      sw.stop();
      socket.destroy();
      return (status: 'online', responseMs: sw.elapsedMilliseconds, packetLoss: 0.0);
    } catch (e) {
      if (kDebugMode) print('⚠️ tcpProbe $ip:$port failed: $e');
      try { socket?.destroy(); } catch (_) {}
      return (status: 'offline', responseMs: null, packetLoss: 100.0);
    }
  }

  /// ICMP ping — fallback لو ما نعرف الـport.
  static Future<({String status, int? responseMs, double? packetLoss})> _icmpProbe({
    required String ip,
    required int count,
    required Duration timeout,
  }) async {
    try {
      final ping = Ping(ip, count: count, timeout: timeout.inSeconds);
      final times = <int>[];
      int received = 0;
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
      if (kDebugMode) print('⚠️ icmpProbe $ip failed: $e');
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
