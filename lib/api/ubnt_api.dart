import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// UBNT airOS SSH client — يستعمل SSH لتشغيل `mca-status` وجلب المعلومات.
///
/// **لماذا SSH بدل HTTP**:
/// - يعمل على كل إصدارات airOS 5/6/7/8 بدون فروقات
/// - LibreNMS + Zabbix + كل ISPs يستعملون SSH
/// - HTTP في airOS 5/6 القديم يواجه cookie/session/redirect issues
/// - user/pass نفسها للـweb (لا شيء إضافي)
///
/// **الأمر الرئيسي**: `mca-status` يُرجع نصّاً بصيغة key=value يشمل كل شيء.
/// **fallbacks**: `ubntbox status`، `iwconfig`، `/proc/*`، `ifconfig`.
class UbntApi {
  /// جلب صورة كاملة عن حالة الجهاز عبر SSH.
  static Future<UbntStats> fetchStats({
    required String ip,
    int port = 22,
    required String user,
    required String pass,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    SSHClient? client;
    SSHSocket? socket;
    try {
      socket = await SSHSocket.connect(ip, port, timeout: timeout);
      client = SSHClient(
        socket,
        username: user,
        onPasswordRequest: () => pass,
      );

      // ننفّذ mca-status ونحصل على output
      String output;
      try {
        final result = await client.run('mca-status').timeout(timeout);
        output = utf8.decode(result, allowMalformed: true);
      } catch (e) {
        // fallback لو mca-status غير موجود (نادر)
        if (kDebugMode) debugPrint('⚠️ mca-status failed: $e — trying ubntbox status');
        final result = await client.run('ubntbox status').timeout(timeout);
        output = utf8.decode(result, allowMalformed: true);
      }

      if (output.trim().isEmpty) {
        throw UbntException('mca-status رجع فارغ — تحقّق من صلاحيّات المستخدم');
      }

      // نستخرج أيضاً uptime + load (بعض الأجهزة ما ترجعها في mca-status)
      String? extraUptime;
      String? extraLoad;
      try {
        extraUptime = utf8.decode(
          await client.run('cat /proc/uptime').timeout(const Duration(seconds: 3)),
          allowMalformed: true,
        ).trim();
      } catch (_) {}
      try {
        extraLoad = utf8.decode(
          await client.run('cat /proc/loadavg').timeout(const Duration(seconds: 3)),
          allowMalformed: true,
        ).trim();
      } catch (_) {}

      final parsed = _parseMcaStatus(output);
      if (extraUptime != null && parsed['uptime'] == null) {
        parsed['uptime'] = extraUptime.split(' ').first;
      }
      if (extraLoad != null && parsed['cpuload'] == null) {
        // /proc/loadavg: "0.05 0.03 0.00 1/45 12345"
        final parts = extraLoad.split(RegExp(r'\s+'));
        if (parts.isNotEmpty) {
          final load1 = double.tryParse(parts[0]) ?? 0;
          parsed['cpuload'] = (load1 * 100).round().toString();
        }
      }

      return UbntStats.fromMcaStatus(parsed);
    } on SSHAuthAbortError {
      throw UbntException('اسم المستخدم أو كلمة المرور خطأ (SSH auth failed)');
    } on SSHAuthFailError {
      throw UbntException('اسم المستخدم أو كلمة المرور خطأ (SSH auth failed)');
    } on TimeoutException {
      throw UbntException('انتهت مهلة الاتصال — تأكّد من IP وأن SSH مفعّل');
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('SocketException')) {
        throw UbntException('الجهاز غير قابل للوصول — تحقّق من الشبكة والـIP');
      }
      if (msg.contains('Connection refused')) {
        throw UbntException('SSH port 22 مغلق — تأكّد أن SSH مفعّل على الجهاز');
      }
      if (msg.contains('Handshake') || msg.contains('SSH')) {
        throw UbntException('فشل SSH handshake: $msg');
      }
      throw UbntException('خطأ: $msg');
    } finally {
      try { client?.close(); } catch (_) {}
      try { socket?.close(); } catch (_) {}
    }
  }

  /// mca-status output: أسطر key=value، بعض القيم متعدّدة (station1_ip=...)
  static Map<String, String> _parseMcaStatus(String output) {
    final map = <String, String>{};
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final key = trimmed.substring(0, eq).trim();
      final val = trimmed.substring(eq + 1).trim();
      map[key] = val;
    }
    return map;
  }
}

class UbntException implements Exception {
  final String message;
  UbntException(this.message);
  @override
  String toString() => message;
}

// ═══════════════════════════════════════════════════════════
// Models — mca-status parser
// ═══════════════════════════════════════════════════════════

class UbntStats {
  final int apiVersion;               // 5 (SSH-based → نعتبرها 5+)
  final UbntHost host;
  final UbntWireless? wireless;
  final List<UbntInterface> interfaces;
  final List<UbntStation> stations;

  const UbntStats({
    this.apiVersion = 5,
    required this.host,
    this.wireless,
    this.interfaces = const [],
    this.stations = const [],
  });

  bool get isAp => wireless?.mode.toLowerCase().contains('ap') ?? false ||
      wireless?.mode.toLowerCase().contains('master') == true;
  bool get isStation => wireless?.mode.toLowerCase().contains('sta') ?? false ||
      wireless?.mode.toLowerCase().contains('managed') == true;

  /// يبني من mca-status output map
  factory UbntStats.fromMcaStatus(Map<String, String> m) {
    // mca-status keys شائعة (تختلف قليلاً حسب الإصدار):
    // deviceId, firmwareVersion, deviceName, uptime,
    // cpuLoadAvg, temperature, memTotal, memFree, memBuffers, memCached,
    // wlanRxRate, wlanTxRate, wlanSignal, wlanNoiseFloor,
    // wlanChan, wlanChanWidth, wlanEssid, wlanMode, wlanFrequency, wlanCcq,
    // wlanConnections, wlanTxPower
    // + إذا AP: station1_mac, station1_signal, station1_ccq, station1_ip, ...

    final host = UbntHost(
      hostname: m['deviceName'] ?? m['hostname'] ?? '',
      devmodel: m['platform'] ?? m['deviceId'] ?? '',  // deviceId هو MAC عادة
      fwversion: m['firmwareVersion'] ?? m['fwVersion'] ?? '',
      uptime: _n(m['uptime']),
      cpuload: _cpuFromLoadAvg(m['cpuLoadAvg']) ?? _n(m['cpuload']),
      temperature: _n(m['temperature']),
    );

    UbntWireless? wireless;
    if (m.containsKey('wlanSignal') || m.containsKey('wlanEssid')) {
      wireless = UbntWireless(
        essid: m['wlanEssid'] ?? '',
        mode: _normalizeMode(m['wlanMode'] ?? ''),
        signal: _n(m['wlanSignal']),
        noise: _n(m['wlanNoiseFloor']),
        ccq: _n(m['wlanCcq']),
        txRate: _n(m['wlanTxRate']),
        rxRate: _n(m['wlanRxRate']),
        channel: _n(m['wlanChan']),
        frequency: _n(m['wlanFrequency']),
        distance: _n(m['wlanDistance']),
        chanbw: _n(m['wlanChanWidth']),
      );
    }

    // Stations: station1_mac, station1_signal, ...
    final stations = <UbntStation>[];
    for (int i = 1; i <= 128; i++) {
      final mac = m['station${i}_mac'];
      if (mac == null || mac.isEmpty) break;
      stations.add(UbntStation(
        mac: mac,
        ip: m['station${i}_ip'],
        hostname: m['station${i}_name'] ?? m['station${i}_hostname'],
        signal: _n(m['station${i}_signal']),
        noise: _n(m['station${i}_noise']),
        ccq: _n(m['station${i}_ccq']),
        txRate: _n(m['station${i}_tx']),
        rxRate: _n(m['station${i}_rx']),
        connTime: _n(m['station${i}_uptime']),
      ));
    }

    // Interfaces من mca-status محدودة — عادةً نجيبها بأمر ifconfig منفصل لاحقاً.
    // للـSlice الحالي، نتركها فارغة (الـwireless هو الأهمّ لـUBNT).
    return UbntStats(
      host: host,
      wireless: wireless,
      stations: stations,
    );
  }

  static int? _cpuFromLoadAvg(String? loadAvg) {
    if (loadAvg == null || loadAvg.isEmpty) return null;
    // Format: "0.05 0.03 0.00" أو "(0.05 0.03 0.00)"
    final cleaned = loadAvg.replaceAll(RegExp(r'[()]'), '').trim();
    final parts = cleaned.split(RegExp(r'[,\s]+'));
    if (parts.isEmpty) return null;
    final load = double.tryParse(parts.first);
    return load == null ? null : (load * 100).round();
  }

  static String _normalizeMode(String raw) {
    final low = raw.toLowerCase();
    // mca-status: "master" = AP، "managed"/"station" = STA
    // نحوّل لصيغة موحّدة مثل airOS 8: ap-ptp/sta-ptp/ap-ptmp/sta-ptmp
    if (low.contains('master') || low.contains('ap')) return 'ap-ptmp';
    if (low.contains('managed') || low.contains('station') || low.contains('sta')) return 'sta-ptp';
    return raw;
  }
}

class UbntHost {
  final String hostname;
  final String devmodel;
  final String fwversion;
  final int uptime;
  final int cpuload;
  final int temperature;

  const UbntHost({
    required this.hostname,
    required this.devmodel,
    required this.fwversion,
    required this.uptime,
    required this.cpuload,
    required this.temperature,
  });
}

class UbntWireless {
  final String essid;
  final String mode;
  final int signal;
  final int noise;
  final int ccq;
  final int txRate;
  final int rxRate;
  final int channel;
  final int frequency;
  final int distance;
  final int chanbw;

  const UbntWireless({
    required this.essid,
    required this.mode,
    required this.signal,
    required this.noise,
    required this.ccq,
    required this.txRate,
    required this.rxRate,
    required this.channel,
    required this.frequency,
    required this.distance,
    required this.chanbw,
  });

  int get snr => (signal - noise).abs();

  double get signalQualityPercent {
    if (signal >= -40) return 100.0;
    if (signal <= -95) return 0.0;
    return ((-40.0 - signal.abs().toDouble()) / 55.0 * 100 + 100).clamp(0, 100);
  }
}

class UbntInterface {
  final String ifname;
  final String hwaddr;
  final bool enabled;
  final bool plugged;
  final int? rxBytes;
  final int? txBytes;
  final int? speed;
  final bool duplex;

  const UbntInterface({
    required this.ifname,
    required this.hwaddr,
    required this.enabled,
    required this.plugged,
    this.rxBytes,
    this.txBytes,
    this.speed,
    this.duplex = false,
  });
}

class UbntStation {
  final String mac;
  final String? ip;
  final String? hostname;
  final int signal;
  final int noise;
  final int ccq;
  final int txRate;
  final int rxRate;
  final int connTime;

  const UbntStation({
    required this.mac,
    this.ip,
    this.hostname,
    required this.signal,
    required this.noise,
    required this.ccq,
    required this.txRate,
    required this.rxRate,
    required this.connTime,
  });

  int get snr => (signal - noise).abs();
}

// ── Utilities
int _n(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  if (s.isEmpty) return 0;
  return int.tryParse(s) ?? (double.tryParse(s)?.toInt() ?? 0);
}
