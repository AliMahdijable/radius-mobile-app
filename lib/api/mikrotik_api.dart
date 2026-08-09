import 'package:flutter/foundation.dart';

import 'mikrotik_binary_api.dart';

/// Mikrotik high-level API — يستعمل Binary API (port 8728 افتراضي).
/// يجلب system/resource + interfaces + ppp active بالتوازي.
class MikrotikApi {
  /// جلب صورة كاملة عن حالة الراوتر عبر Binary API.
  /// **يعمل مع RouterOS 6.43+** (login sentence بسيط).
  static Future<MikrotikStats> fetchStats({
    required String ip,
    required int port,          // 8728 (api) أو 8729 (api-ssl)
    required String user,
    required String pass,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final client = MikrotikBinaryClient(
      host: ip,
      port: port,
      user: user,
      pass: pass,
      timeout: timeout,
    );
    try {
      await client.connect();
      await client.login();

      // نجيبهم بالتسلسل — Binary API socket واحد فقط
      final resourceRows = await client.query(['/system/resource/print']);
      final interfaceRows = await client.query(['/interface/print']);
      List<Map<String, String>> pppRows = const [];
      try {
        pppRows = await client.query(['/ppp/active/print']);
      } catch (_) {
        // ppp/active قد لا يكون موجوداً — تجاهل
      }

      // اجلب سرعة الـport الفعليّة (1Gbps/100Mbps/10Mbps) لكل ethernet
      // عبر /interface/ethernet/monitor لكل ether بشكل منفصل (أضمن).
      final Map<String, Map<String, String>> ethMonitorByName = {};
      for (final row in interfaceRows) {
        final name = row['name'];
        if (name == null || name.isEmpty) continue;
        final type = row['type'] ?? '';
        if (type != 'ether' && type != 'sfp') continue;
        try {
          final monResult = await client.query([
            '/interface/ethernet/monitor',
            '=numbers=$name',
            '=once=',
          ]);
          if (monResult.isNotEmpty) {
            ethMonitorByName[name] = monResult.first;
            if (kDebugMode) {
              debugPrint('🔵 ether monitor $name: rate=${monResult.first["rate"]} status=${monResult.first["status"]}');
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ ether monitor $name failed: $e');
        }
      }

      if (resourceRows.isEmpty) {
        throw MikrotikBinaryException('لم يرجع الراوتر معلومات system/resource');
      }
      final resource = resourceRows.first;

      return MikrotikStats(
        cpuLoad: _asInt(resource['cpu-load']),
        memUsedPercent: _calcMemUsed(resource),
        memTotalBytes: _asInt(resource['total-memory']),
        memFreeBytes: _asInt(resource['free-memory']),
        uptime: resource['uptime'] ?? '',
        version: resource['version'] ?? '',
        boardName: resource['board-name'] ?? '',
        architectureName: resource['architecture-name'] ?? '',
        cpuCount: _asInt(resource['cpu-count']),
        cpuFrequencyMhz: _asInt(resource['cpu-frequency']),
        interfaces: interfaceRows.map((row) {
          final name = row['name'] ?? '';
          final monitor = ethMonitorByName[name];
          return MikrotikInterface.fromApiMap(row, monitor: monitor);
        }).toList(),
        pppActiveCount: pppRows.length,
      );
    } on MikrotikBinaryException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ MikrotikApi: $e');
      throw MikrotikException(_translateSocketError(e));
    } finally {
      await client.close();
    }
  }

  static String _translateSocketError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('SocketException') && msg.contains('refused')) {
      return 'الراوتر رفض الاتصال — تأكّد /ip service enable api على المنفذ 8728';
    }
    if (msg.contains('timed out') || msg.contains('timeout')) {
      return 'انتهت مهلة الاتصال — تأكّد أنك على شبكة الراوتر';
    }
    if (msg.contains('Network is unreachable')) {
      return 'الشبكة غير قابلة للوصول — تحقّق من الاتصال';
    }
    return 'خطأ اتصال: $msg';
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static int _calcMemUsed(Map<String, String> resource) {
    final total = _asInt(resource['total-memory']);
    final free = _asInt(resource['free-memory']);
    if (total == 0) return 0;
    return (((total - free) / total) * 100).round();
  }
}

/// alias حتى الـ UI يبقى نفسه
typedef MikrotikException = MikrotikBinaryException;

class MikrotikStats {
  final int cpuLoad;
  final int memUsedPercent;
  final int memTotalBytes;
  final int memFreeBytes;
  final String uptime;
  final String version;
  final String boardName;
  final String architectureName;
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
  int get memUsedBytes => memTotalBytes - memFreeBytes;
}

class MikrotikInterface {
  final String name;
  final String type;
  final bool running;
  final bool disabled;
  final int? mtu;
  final int? rxBytes;
  final int? txBytes;
  /// سرعة الـport الفعليّة من ethernet/monitor (مثل "1Gbps", "100Mbps")
  final String? linkSpeed;
  /// full-duplex من ethernet/monitor
  final bool fullDuplex;

  const MikrotikInterface({
    required this.name,
    required this.type,
    required this.running,
    required this.disabled,
    this.mtu,
    this.rxBytes,
    this.txBytes,
    this.linkSpeed,
    this.fullDuplex = true,
  });

  /// Binary API يرجع كل القيم كـString — نحوّل نحن.
  /// monitor (اختياري) من /interface/ethernet/monitor يحوي rate + full-duplex
  factory MikrotikInterface.fromApiMap(
    Map<String, String> j, {
    Map<String, String>? monitor,
  }) {
    bool asBool(String? v) => v?.toLowerCase() == 'true';
    int? asInt(String? v) {
      if (v == null) return null;
      return int.tryParse(v);
    }
    return MikrotikInterface(
      name: j['name'] ?? '',
      type: j['type'] ?? '',
      running: asBool(j['running']),
      disabled: asBool(j['disabled']),
      mtu: asInt(j['actual-mtu'] ?? j['mtu']),
      rxBytes: asInt(j['rx-byte']),
      txBytes: asInt(j['tx-byte']),
      linkSpeed: monitor?['rate'],
      fullDuplex: monitor == null ? true : asBool(monitor['full-duplex']),
    );
  }
}
