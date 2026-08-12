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
      // Health — حرارة + فولتيّة (اختياري، بعض الأجهزة الصغيرة ما تدعمه)
      List<Map<String, String>> healthRows = const [];
      try {
        healthRows = await client.query(['/system/health/print']);
      } catch (_) {}
      List<Map<String, String>> pppRows = const [];
      try {
        pppRows = await client.query(['/ppp/active/print']);
      } catch (_) {}

      // Wireless — لو الجهاز يدعم wireless package
      List<Map<String, String>> wirelessRows = const [];
      List<Map<String, String>> wirelessClients = const [];
      try {
        wirelessRows = await client.query(['/interface/wireless/print']);
      } catch (_) {
        // بعض الأجهزة ما تدعم wireless (مثل CCR raw routers)
      }
      if (wirelessRows.isNotEmpty) {
        try {
          wirelessClients = await client.query(['/interface/wireless/registration-table/print']);
        } catch (_) {}
      }

      // نبني map غنيّ MAC→(hostname, IP) من 3 مصادر بأولويّة:
      //   1. /ip/dhcp-server/lease — host-name + IP (لو الراوتر DHCP server)
      //   2. /interface/wireless/access-list — comment (اسم مخصّص لكل client)
      //   3. /ip/arp — IP فقط (شامل حتى لو DHCP على راوتر آخر)
      final Map<String, ({String? hostname, String? ip})> dhcpMap = {};

      // 1. DHCP leases
      try {
        final leases = await client.query(['/ip/dhcp-server/lease/print']);
        for (final l in leases) {
          final mac = (l['mac-address'] ?? '').toUpperCase();
          if (mac.isEmpty) continue;
          dhcpMap[mac] = (
            hostname: _nonEmpty(l['host-name']) ?? _nonEmpty(l['comment']),
            ip: _nonEmpty(l['active-address']) ?? _nonEmpty(l['address']),
          );
        }
      } catch (_) {}

      // 2. Wireless access-list — comments هي أسماء client محفوظة يدوياً
      try {
        final acl = await client.query(['/interface/wireless/access-list/print']);
        for (final a in acl) {
          final mac = (a['mac-address'] ?? '').toUpperCase();
          final comment = _nonEmpty(a['comment']);
          if (mac.isEmpty || comment == null) continue;
          final existing = dhcpMap[mac];
          dhcpMap[mac] = (
            hostname: existing?.hostname ?? comment,   // comment fallback لـhostname
            ip: existing?.ip,
          );
        }
      } catch (_) {}

      // 3. ARP table — للـIP لو ما لكيناه من DHCP
      try {
        final arp = await client.query(['/ip/arp/print']);
        for (final a in arp) {
          final mac = (a['mac-address'] ?? '').toUpperCase();
          final ip = _nonEmpty(a['address']);
          final comment = _nonEmpty(a['comment']);
          if (mac.isEmpty) continue;
          final existing = dhcpMap[mac];
          if (existing == null) {
            dhcpMap[mac] = (hostname: comment, ip: ip);
          } else {
            dhcpMap[mac] = (
              hostname: existing.hostname ?? comment,
              ip: existing.ip ?? ip,
            );
          }
        }
      } catch (_) {}

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
          }
        } catch (_) {}
      }

      if (resourceRows.isEmpty) {
        throw MikrotikBinaryException('لم يرجع الراوتر معلومات system/resource');
      }
      final resource = resourceRows.first;

      // Health parsing — RouterOS v7 يرجع list of {name, value, type}
      // بينما v6 قد يرجع flat map {temperature: "45C", voltage: "24V"}
      int? healthTemp;
      double? healthVoltage;
      for (final h in healthRows) {
        final name = (h['name'] ?? '').toLowerCase();
        final valueStr = h['value'] ?? '';
        if (name.contains('temp')) {
          // القيمة قد تكون "45" أو "45C"
          final v = double.tryParse(valueStr.replaceAll(RegExp(r'[^\d.-]'), ''));
          if (v != null && (healthTemp == null || name.contains('cpu'))) {
            healthTemp = v.round();
          }
        } else if (name.contains('voltage') || name == 'v') {
          final v = double.tryParse(valueStr.replaceAll(RegExp(r'[^\d.-]'), ''));
          if (v != null) healthVoltage = v;
        }
      }
      // fallback: بعض الإصدارات ترجع flat في نفس row واحد
      if (healthRows.length == 1) {
        final r = healthRows.first;
        healthTemp ??= _asInt(r['temperature']?.replaceAll(RegExp(r'[^\d-]'), ''));
        if (healthVoltage == null && r['voltage'] != null) {
          healthVoltage = double.tryParse(r['voltage']!.replaceAll(RegExp(r'[^\d.-]'), ''));
        }
      }
      // fallback نهائي: system/resource قد يحوي cpu-temperature
      healthTemp ??= _asInt(resource['cpu-temperature']);
      if (healthTemp == 0) healthTemp = null;

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
        temperature: healthTemp,
        voltage: healthVoltage,
        interfaces: interfaceRows.map((row) {
          final name = row['name'] ?? '';
          final monitor = ethMonitorByName[name];
          return MikrotikInterface.fromApiMap(row, monitor: monitor);
        }).toList(),
        pppActiveCount: pppRows.length,
        wirelessInterfaces: wirelessRows.map(MikrotikWireless.fromApiMap).toList(),
        wirelessClients: wirelessClients.map((c) {
          final macUpper = (c['mac-address'] ?? '').toUpperCase();
          final dhcp = dhcpMap[macUpper];
          return MikrotikWirelessClient.fromApiMap(
            c,
            hostname: dhcp?.hostname,
            ip: dhcp?.ip,
          );
        }).toList(),
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
  final int? temperature;         // °C من /system/health
  final double? voltage;          // V من /system/health
  final List<MikrotikInterface> interfaces;
  final int pppActiveCount;
  final List<MikrotikWireless> wirelessInterfaces;
  final List<MikrotikWirelessClient> wirelessClients;

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
    this.temperature,
    this.voltage,
    required this.interfaces,
    required this.pppActiveCount,
    this.wirelessInterfaces = const [],
    this.wirelessClients = const [],
  });

  bool get hasWireless => wirelessInterfaces.isNotEmpty;

  int get upInterfacesCount => interfaces.where((i) => i.running && !i.disabled).length;
  int get downInterfacesCount => interfaces.where((i) => !i.running && !i.disabled).length;
  int get memUsedBytes => memTotalBytes - memFreeBytes;
}

/// معلومات wireless interface (link / sector / AP)
class MikrotikWireless {
  final String name;              // wlan1, wlan2, ...
  final String ssid;
  final String mode;              // ap-bridge, station, station-bridge, wds-slave, ...
  final String band;              // 5ghz-a, 5ghz-n, 2ghz-b/g/n, ...
  final int frequency;            // MHz
  final int channelWidth;         // MHz
  final int txPower;              // dBm
  final bool disabled;
  final bool running;

  const MikrotikWireless({
    required this.name,
    required this.ssid,
    required this.mode,
    required this.band,
    required this.frequency,
    required this.channelWidth,
    required this.txPower,
    required this.disabled,
    required this.running,
  });

  bool get isAp => mode.startsWith('ap') || mode == 'bridge';
  bool get isStation => mode.startsWith('station');

  factory MikrotikWireless.fromApiMap(Map<String, String> j) {
    bool asBool(String? v) => v?.toLowerCase() == 'true';
    return MikrotikWireless(
      name: j['name'] ?? '',
      ssid: j['ssid'] ?? '',
      mode: j['mode'] ?? '',
      band: j['band'] ?? '',
      frequency: _iOrZero(j['frequency']),
      channelWidth: _iOrZero(j['channel-width']?.replaceAll(RegExp(r'[^0-9]'), '')),
      txPower: _iOrZero(j['tx-power']),
      disabled: asBool(j['disabled']),
      running: asBool(j['running']),
    );
  }
}

/// عميل wireless متصل (من registration-table + DHCP lease enrichment)
class MikrotikWirelessClient {
  final String mac;
  final String iface;             // wlan1, wlan2 — أي wireless انضمّ عليه
  final int signalStrength;       // dBm — RX (كيف نستقبل من العميل)
  final int txSignalStrength;     // dBm — TX (كيف العميل يستقبل منّا). 0 = غير متوفّر
  final int signalToNoise;        // dB (SNR)
  final int txCcq;                // Client Connection Quality % (0-100)
  final int rxCcq;                // %
  final int txRate;               // Mbps
  final int rxRate;               // Mbps
  final int uptime;               // seconds
  final String? comment;          // من registration-table comment
  final String? hostname;         // من DHCP host-name أو lease comment
  final String? ip;                // من DHCP active-address

  const MikrotikWirelessClient({
    required this.mac,
    required this.iface,
    required this.signalStrength,
    this.txSignalStrength = 0,
    required this.signalToNoise,
    required this.txCcq,
    required this.rxCcq,
    required this.txRate,
    required this.rxRate,
    required this.uptime,
    this.comment,
    this.hostname,
    this.ip,
  });

  /// أفضل اسم لعرض العميل: hostname (DHCP) > comment (registration) > MAC
  String get displayName => hostname ?? comment ?? mac;

  /// عرض الإشارة كما WinBox: "TX/RX" مثل "-36/-51". لو txSignal غير متوفّر
  /// نعرض الـRX فقط.
  String get signalDisplay {
    if (txSignalStrength != 0) return '$txSignalStrength/$signalStrength';
    return '$signalStrength';
  }

  factory MikrotikWirelessClient.fromApiMap(
    Map<String, String> j, {
    String? hostname,
    String? ip,
  }) {
    // radio-name = اسم الجهاز البعيد (لو Mikrotik→Mikrotik) — يظهر في WinBox
    // كـidentity للـsector/client. أولويّة عالية للعرض.
    final radioName = _nonEmpty(j['radio-name']);
    return MikrotikWirelessClient(
      mac: j['mac-address'] ?? '',
      iface: j['interface'] ?? '',
      // RX = signal-strength (نستقبل من العميل)
      signalStrength: _parseSignal(j['signal-strength'] ?? j['signal']),
      // TX = tx-signal-strength (العميل يستقبل منّا) — يظهر في WinBox
      // كنصف "Tx/Rx Signal Strength" الأيسر
      txSignalStrength: _parseSignal(j['tx-signal-strength']),
      signalToNoise: _iOrZero(j['signal-to-noise']),
      txCcq: _iOrZero(j['tx-ccq']),
      rxCcq: _iOrZero(j['rx-ccq']),
      txRate: _parseRate(j['tx-rate']),
      rxRate: _parseRate(j['rx-rate']),
      uptime: _parseUptimeSeconds(j['uptime']),
      comment: _nonEmpty(j['comment']),
      // نُفضّل: DHCP hostname > radio-name (Mikrotik identity) > wireless comment > null
      hostname: hostname ?? radioName,
      ip: ip,
    );
  }

  /// "-58@1Mbps" أو "-58" → -58
  static int _parseSignal(String? raw) {
    if (raw == null) return 0;
    final m = RegExp(r'-?\d+').firstMatch(raw);
    return m == null ? 0 : (int.tryParse(m.group(0)!) ?? 0);
  }

  /// "270Mbps-40MHz/2S/SGI" → 270
  static int _parseRate(String? raw) {
    if (raw == null) return 0;
    final m = RegExp(r'(\d+)').firstMatch(raw);
    return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  }

  /// "3w2d15h4m5s" → seconds
  static int _parseUptimeSeconds(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    int total = 0;
    final w = RegExp(r'(\d+)w').firstMatch(raw)?.group(1);
    final d = RegExp(r'(\d+)d').firstMatch(raw)?.group(1);
    final h = RegExp(r'(\d+)h').firstMatch(raw)?.group(1);
    final m = RegExp(r'(\d+)m(?!s)').firstMatch(raw)?.group(1);
    final s = RegExp(r'(\d+)s').firstMatch(raw)?.group(1);
    if (w != null) total += int.parse(w) * 604800;
    if (d != null) total += int.parse(d) * 86400;
    if (h != null) total += int.parse(h) * 3600;
    if (m != null) total += int.parse(m) * 60;
    if (s != null) total += int.parse(s);
    return total;
  }
}

int _iOrZero(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  return int.tryParse(v.toString()) ?? 0;
}

String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

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
