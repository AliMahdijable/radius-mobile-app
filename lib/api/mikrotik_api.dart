import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Mikrotik RouterOS REST API client (RouterOS 7+).
///
/// **متطلّبات**:
/// - على الراوتر: `/ip service enable www` أو `/ip service enable www-ssl`
/// - المنفذ الافتراضي: 80 (HTTP) أو 443 (HTTPS)
/// - المستخدم: يفضّل مستخدم ذو group='read' أو 'full' حسب الحاجة
///
/// الاتصال من الموبايل مباشرة على شبكة LAN. السيرفر لا يوصل الراوتر.
class MikrotikApi {
  /// جلب صورة كاملة عن حالة الراوتر — resource + interfaces + ppp active.
  /// يعمل مع HTTP و HTTPS (self-signed). timeout قصير لأنه على LAN.
  static Future<MikrotikStats> fetchStats({
    required String ip,
    required int port,
    required String user,
    required String pass,
    bool? useHttps,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    // كشف HTTPS تلقائيّاً حسب الـport لو ما مُحدَّد
    final https = useHttps ?? (port == 443 || port == 8443);
    // خطأ شائع: المستخدم يضع 8728 ظنّاً أنه port الـAPI. لكن 8728 هو binary
    // WinBox API، مو REST. REST يحتاج www (80) أو www-ssl (443).
    if (port == 8728 || port == 8729) {
      throw MikrotikException(
        'المنفذ $port هو للـWinBox API القديم (binary). '
        'REST API يستعمل 80 (HTTP) أو 443 (HTTPS). '
        'فعّل /ip service www على الراوتر واستعمل 80.',
      );
    }
    final scheme = https ? 'https' : 'http';
    final baseUrl = '$scheme://$ip:$port';
    final auth = 'Basic ${base64Encode(utf8.encode('$user:$pass'))}';

    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      headers: {
        'Authorization': auth,
        'Accept': 'application/json',
      },
      // RouterOS يرجع أحياناً 200 مع HTML للـlogin — نقبل كل status
      // ونتحقّق من النوع
      validateStatus: (s) => s != null && s < 500,
    ));

    try {
      // نستدعي بالتوازي — كل واحد عادةً <200ms على LAN
      final results = await Future.wait<Response<dynamic>>([
        dio.get('/rest/system/resource'),
        dio.get('/rest/interface'),
        // ppp/active قد يكون فارغاً أو غير موجود (لو الراوتر ما يستعمل PPP)
        dio.get('/rest/ppp/active').catchError(
          (_) => Response(requestOptions: RequestOptions(path: ''), data: <dynamic>[]),
        ),
      ]);

      // system/resource
      final r0 = results[0];
      if (r0.statusCode == 401) {
        throw MikrotikException('اسم المستخدم أو كلمة المرور خطأ (401)');
      }
      if (r0.data is! Map) {
        throw MikrotikException('استجابة غير متوقّعة من الراوتر — تأكّد من تفعيل خدمة www في /ip service');
      }
      final resource = r0.data as Map<String, dynamic>;

      // interfaces
      final r1 = results[1];
      final interfaces = <MikrotikInterface>[];
      if (r1.data is List) {
        for (final item in r1.data as List) {
          if (item is Map) interfaces.add(MikrotikInterface.fromJson(item));
        }
      }

      // ppp active
      final r2 = results[2];
      final pppCount = (r2.data is List) ? (r2.data as List).length : 0;

      return MikrotikStats(
        cpuLoad: _asInt(resource['cpu-load']),
        memUsedPercent: _calcMemUsed(resource),
        memTotalBytes: _asInt(resource['total-memory']),
        memFreeBytes: _asInt(resource['free-memory']),
        uptime: (resource['uptime'] ?? '').toString(),
        version: (resource['version'] ?? '').toString(),
        boardName: (resource['board-name'] ?? '').toString(),
        architectureName: (resource['architecture-name'] ?? '').toString(),
        cpuCount: _asInt(resource['cpu-count']),
        cpuFrequencyMhz: _asInt(resource['cpu-frequency']),
        interfaces: interfaces,
        pppActiveCount: pppCount,
      );
    } on DioException catch (e) {
      if (kDebugMode) debugPrint('❌ MikrotikApi: $e');
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw MikrotikException('انتهت مهلة الاتصال — تأكّد أن الجهاز قابل للوصول على LAN');
      }
      throw MikrotikException('فشل الاتصال: ${e.message ?? "غير معروف"}');
    } catch (e) {
      if (e is MikrotikException) rethrow;
      throw MikrotikException('خطأ: $e');
    }
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static int _calcMemUsed(Map<String, dynamic> resource) {
    final total = _asInt(resource['total-memory']);
    final free = _asInt(resource['free-memory']);
    if (total == 0) return 0;
    return (((total - free) / total) * 100).round();
  }
}

class MikrotikException implements Exception {
  final String message;
  MikrotikException(this.message);
  @override
  String toString() => message;
}

class MikrotikStats {
  final int cpuLoad;              // %
  final int memUsedPercent;       // %
  final int memTotalBytes;
  final int memFreeBytes;
  final String uptime;            // e.g. "3w2d15h4m5s"
  final String version;           // e.g. "7.16.2 (stable)"
  final String boardName;         // e.g. "RB5009UG+S+"
  final String architectureName;  // e.g. "arm64"
  final int cpuCount;
  final int cpuFrequencyMhz;
  final List<MikrotikInterface> interfaces;
  final int pppActiveCount;

  const MikrotikStats({
    required this.cpuLoad,
    required this.memUsedPercent,
    required this.memTotalBytes,
    required this.memFreeBytes,
    required this.uptime,
    required this.version,
    required this.boardName,
    required this.architectureName,
    required this.cpuCount,
    required this.cpuFrequencyMhz,
    required this.interfaces,
    required this.pppActiveCount,
  });

  int get upInterfacesCount => interfaces.where((i) => i.running && !i.disabled).length;
  int get downInterfacesCount => interfaces.where((i) => !i.running && !i.disabled).length;

  /// حجم الذاكرة المستعمل bytes
  int get memUsedBytes => memTotalBytes - memFreeBytes;
}

class MikrotikInterface {
  final String name;
  final String type;       // ether, wlan, bridge, vlan, ...
  final bool running;      // link up + admin enabled
  final bool disabled;
  final int? mtu;
  final int? rxBytes;      // cumulative من boot
  final int? txBytes;

  const MikrotikInterface({
    required this.name,
    required this.type,
    required this.running,
    required this.disabled,
    this.mtu,
    this.rxBytes,
    this.txBytes,
  });

  factory MikrotikInterface.fromJson(Map j) {
    bool asBool(dynamic v) {
      if (v is bool) return v;
      return v?.toString().toLowerCase() == 'true';
    }
    int? asInt(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }
    return MikrotikInterface(
      name: (j['name'] ?? '').toString(),
      type: (j['type'] ?? '').toString(),
      running: asBool(j['running']),
      disabled: asBool(j['disabled']),
      mtu: asInt(j['actual-mtu'] ?? j['mtu']),
      rxBytes: asInt(j['rx-byte'] ?? j['rx-bytes']),
      txBytes: asInt(j['tx-byte'] ?? j['tx-bytes']),
    );
  }

  /// اقتراح أيقونة حسب النوع
  String get iconHint => switch (type) {
        'ether' => 'ether',
        'wlan' => 'wifi',
        'bridge' => 'bridge',
        'vlan' => 'vlan',
        'pppoe-in' || 'pppoe-out' => 'ppp',
        _ => 'other',
      };
}
