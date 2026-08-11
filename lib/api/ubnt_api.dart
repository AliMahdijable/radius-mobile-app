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
      // بعض UBNT (خصوصاً airFiber جديد) يقبل username فارغ — نُعطي 'ubnt' افتراضي
      final effectiveUser = user.trim().isEmpty ? 'ubnt' : user.trim();
      client = SSHClient(
        socket,
        username: effectiveUser,
        onPasswordRequest: () => pass,
      );

      // نجرّب mca-dump أوّلاً (JSON منظّم، أوثق للأجهزة الحديثة airFiber/airMax AC)
      // ثمّ fallback إلى mca-status (key=value، للـXM/AC القديمة)
      String output = '';
      bool isJsonDump = false;

      try {
        final result = await client.run('mca-dump').timeout(timeout);
        output = utf8.decode(result, allowMalformed: true).trim();
        if (output.startsWith('{') || output.startsWith('[')) {
          isJsonDump = true;
        }
      } catch (_) {}

      if (!isJsonDump) {
        try {
          final result = await client.run('mca-status').timeout(timeout);
          output = utf8.decode(result, allowMalformed: true);
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ mca-status failed: $e — trying ubntbox status');
          final result = await client.run('ubntbox status').timeout(timeout);
          output = utf8.decode(result, allowMalformed: true);
        }
      }

      if (output.trim().isEmpty) {
        throw UbntException('لم نستلم بيانات — تحقّق من صلاحيّات المستخدم');
      }

      if (kDebugMode) {
        debugPrint('══════ UBNT output (${isJsonDump ? "JSON" : "key=value"}) ══════');
        debugPrint(output.substring(0, output.length > 2000 ? 2000 : output.length));
        debugPrint('════════════════════════════════');
      }

      // لو JSON: نحوّله لـflat map key=value ليعمل مع نفس الـparser
      final parsed = isJsonDump
          ? _flattenMcaDump(output)
          : _parseMcaStatus(output);

      // — إضافات من أوامر منفصلة لتكميل ما ينقص —
      // /proc/uptime
      try {
        final r = utf8.decode(await client.run('cat /proc/uptime')
            .timeout(const Duration(seconds: 3)), allowMalformed: true).trim();
        if (parsed['uptime'] == null && r.isNotEmpty) {
          parsed['uptime'] = r.split(' ').first;
        }
      } catch (_) {}

      // /proc/loadavg
      try {
        final r = utf8.decode(await client.run('cat /proc/loadavg')
            .timeout(const Duration(seconds: 3)), allowMalformed: true).trim();
        if (parsed['cpuload'] == null && r.isNotEmpty) {
          final parts = r.split(RegExp(r'\s+'));
          if (parts.isNotEmpty) {
            final load1 = double.tryParse(parts[0]) ?? 0;
            parsed['cpuload'] = (load1 * 100).round().toString();
          }
        }
      } catch (_) {}

      // iwconfig — wireless info لو mca-status ما جاب wlan*
      String? iwconfigOut;
      try {
        iwconfigOut = utf8.decode(await client.run('iwconfig 2>/dev/null')
            .timeout(const Duration(seconds: 4)), allowMalformed: true);
      } catch (_) {}
      if (iwconfigOut != null && iwconfigOut.isNotEmpty) {
        _enrichFromIwconfig(iwconfigOut, parsed);
      }

      // ifconfig — interfaces + RX/TX bytes
      List<Map<String, String>> ifaceRaws = const [];
      try {
        final r = utf8.decode(await client.run('ifconfig')
            .timeout(const Duration(seconds: 4)), allowMalformed: true);
        ifaceRaws = _parseIfconfig(r);
      } catch (_) {}

      // link speed لكل ether — نجرّب عدّة مصادر (تختلف بين إصدارات airOS):
      //   1. /sys/class/net/eth0/speed (Linux حديث)
      //   2. mii-tool (airOS القديم — Atheros)
      //   3. ethtool (لو موجود)
      //   4. mca-status لو فيه wanSpeed
      for (final iface in ifaceRaws) {
        final name = iface['name'] ?? '';
        if (name.isEmpty || !name.startsWith('eth')) continue;

        // 1) /sys/class/net
        try {
          final r = utf8.decode(await client.run('cat /sys/class/net/$name/speed 2>/dev/null')
              .timeout(const Duration(seconds: 2)), allowMalformed: true).trim();
          if (r.isNotEmpty && int.tryParse(r) != null && int.parse(r) > 0) {
            iface['speed'] = r;
            continue;
          }
        } catch (_) {}

        // 2) mii-tool — الأشهر على airOS 5/6 القديم
        try {
          final r = utf8.decode(await client.run('mii-tool $name 2>/dev/null')
              .timeout(const Duration(seconds: 2)), allowMalformed: true).trim();
          // نموذج: "eth0: negotiated 100baseTx-FD flow-control, link ok"
          final m = RegExp(r'(\d+)base').firstMatch(r);
          if (m != null) {
            iface['speed'] = m.group(1)!;
            continue;
          }
        } catch (_) {}

        // 3) ethtool
        try {
          final r = utf8.decode(await client.run('ethtool $name 2>/dev/null')
              .timeout(const Duration(seconds: 2)), allowMalformed: true);
          // "Speed: 1000Mb/s"
          final m = RegExp(r'Speed:\s*(\d+)').firstMatch(r);
          if (m != null) {
            iface['speed'] = m.group(1)!;
            continue;
          }
        } catch (_) {}
      }

      // fallback: mca-status قد يعرض wanSpeed أو lanSpeed
      if (parsed['wanSpeed'] != null) {
        final s = int.tryParse(parsed['wanSpeed']!);
        if (s != null && s > 0) {
          final eth0 = ifaceRaws.where((i) => i['name'] == 'eth0').toList();
          if (eth0.isNotEmpty && eth0.first['speed'] == null) {
            eth0.first['speed'] = s.toString();
          }
        }
      }

      // wstalist — قائمة المحطّات المتّصلة (لـAP mode) بصيغة JSON
      // موجود على airOS 5.5+ (كل الأجهزة الحديثة نسبيّاً)
      List<Map<String, dynamic>> stations = const [];
      try {
        final r = utf8.decode(await client.run('wstalist 2>/dev/null')
            .timeout(const Duration(seconds: 4)), allowMalformed: true).trim();
        if (r.isNotEmpty && r.startsWith('[')) {
          final parsedJson = json.decode(r);
          if (parsedJson is List) {
            stations = parsedJson.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
          }
        }
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ wstalist not available: $e');
      }

      return UbntStats.fromMcaStatus(parsed, interfaces: ifaceRaws, wstalistStations: stations);
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

  /// mca-dump JSON — للـairFiber والأجهزة الحديثة. نُسطّح لصيغة key=value
  /// بأسماء متوافقة مع _parseMcaStatus عشان نفس الـfactory يشتغل.
  /// airFiber 60 LR بنيته مختلفة — نغطّي عدّة variations.
  static Map<String, String> _flattenMcaDump(String jsonStr) {
    final map = <String, String>{};
    try {
      final data = json.decode(jsonStr);
      if (data is! Map) return map;
      final root = data as Map<String, dynamic>;

      if (kDebugMode) {
        debugPrint('🔵 UBNT mca-dump root keys: ${root.keys.toList()}');
      }

      // host section — الأكثر ثباتاً بين الأجهزة
      final host = (root['host'] as Map?)?.cast<String, dynamic>() ?? const {};
      _set(map, 'deviceName', host['hostname'] ?? host['device_id']);
      _set(map, 'firmwareVersion', host['fwversion'] ?? host['firmwareVersion']);
      _set(map, 'platform', host['devmodel'] ?? host['sysid']);
      _set(map, 'uptime', host['uptime']);
      _set(map, 'cpuload', host['cpuload'] ?? host['cpu_load']);
      // درجة الحرارة قد تكون في host أو في مواقع أخرى — نجرّب كلها
      _set(map, 'temperature',
          host['temperature'] ?? host['temp'] ?? root['temperature']);

      // wireless section (airMax/airOS 5-8)
      final w = (root['wireless'] as Map?)?.cast<String, dynamic>();
      if (w != null) {
        if (kDebugMode) debugPrint('🔵 wireless keys: ${w.keys.toList()}');
        _set(map, 'wlanEssid', w['essid'] ?? w['ssid']);
        _set(map, 'wlanMode', w['mode']);
        _set(map, 'wlanSignal', w['signal'] ?? w['rssi']);
        _set(map, 'wlanNoiseFloor', w['noisef'] ?? w['noise']);
        _set(map, 'wlanCcq', w['ccq']);
        _set(map, 'wlanTxRate', w['txrate'] ?? w['tx_rate']);
        _set(map, 'wlanRxRate', w['rxrate'] ?? w['rx_rate']);
        _set(map, 'wlanChan', w['channel']);
        _set(map, 'wlanFrequency', w['frequency'] ?? w['freq']);
        _set(map, 'wlanDistance', w['distance']);
        _set(map, 'wlanChanWidth', w['chanbw'] ?? w['chwidth']);
      }

      // airFiber-specific: 'radio' section
      final radio = (root['radio'] as Map?)?.cast<String, dynamic>();
      if (radio != null) {
        if (kDebugMode) debugPrint('🔵 radio keys: ${radio.keys.toList()}');
        // نستعمل radio لتكميل ما ينقص من wireless
        map['wlanSignal'] ??= (radio['signal'] ?? radio['rxlevel'] ?? radio['rx_level'])?.toString() ?? '';
        map['wlanNoiseFloor'] ??= (radio['noise'] ?? radio['noise_level'])?.toString() ?? '';
        map['wlanFrequency'] ??= (radio['frequency'] ?? radio['freq'])?.toString() ?? '';
        // معدّلات النقل في radio.link_capacity أو radio.tx_capacity
        map['wlanTxRate'] ??= (radio['tx_capacity'] ?? radio['tx_rate'])?.toString() ?? '';
        map['wlanRxRate'] ??= (radio['rx_capacity'] ?? radio['rx_rate'])?.toString() ?? '';
        map['temperature'] ??= (radio['temperature'] ?? radio['temp'])?.toString() ?? '';
      }

      // airFiber 60: قد يكون فيه 'link' section
      final link = (root['link'] as Map?)?.cast<String, dynamic>();
      if (link != null) {
        if (kDebugMode) debugPrint('🔵 link keys: ${link.keys.toList()}');
        map['wlanTxRate'] ??= (link['tx_capacity'] ?? link['capacity'])?.toString() ?? '';
        map['wlanRxRate'] ??= (link['rx_capacity'])?.toString() ?? '';
      }

      // إزالة أي قيم فارغة
      map.removeWhere((k, v) => v.isEmpty);

      // stations: قد تكون في wireless.sta أو root.stations أو root.remote (airFiber)
      List sta = const [];
      if (w?['sta'] is List) sta = w!['sta'] as List;
      else if (root['stations'] is List) sta = root['stations'] as List;
      else if (root['peers'] is List) sta = root['peers'] as List;
      // airFiber remote peer
      final remote = (root['remote'] as Map?)?.cast<String, dynamic>();
      if (sta.isEmpty && remote != null) sta = [remote];

      for (int i = 0; i < sta.length; i++) {
        final s = sta[i];
        if (s is! Map) continue;
        final j = s.cast<String, dynamic>();
        final idx = i + 1;
        _set(map, 'station${idx}_mac',
            j['mac'] ?? j['mac_addr'] ?? j['mac_address']);
        _set(map, 'station${idx}_ip',
            j['lastip'] ?? j['ip'] ?? j['address']);
        _set(map, 'station${idx}_name',
            j['name'] ?? j['hostname'] ?? j['device_name']);
        _set(map, 'station${idx}_signal',
            j['signal'] ?? j['rssi'] ?? j['rx_level']);
        _set(map, 'station${idx}_noise',
            j['noisefloor'] ?? j['noise']);
        _set(map, 'station${idx}_ccq', j['ccq']);
        // tx/rx قد تكون بـKbps أو Mbps — نتركها كما هي والـUI يعرضها
        _set(map, 'station${idx}_tx',
            j['tx'] ?? j['tx_rate'] ?? j['tx_capacity']);
        _set(map, 'station${idx}_rx',
            j['rx'] ?? j['rx_rate'] ?? j['rx_capacity']);
        _set(map, 'station${idx}_uptime',
            j['uptime'] ?? j['conn_time']);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ mca-dump flatten error: $e');
    }
    return map;
  }

  static void _set(Map<String, String> map, String key, dynamic value) {
    if (value == null) return;
    final s = value.toString().trim();
    if (s.isEmpty || s == 'null') return;
    map[key] = s;
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

  /// iwconfig output فيه معلومات wireless
  /// نموذج:
  ///   ath0    IEEE 802.11an  ESSID:"MyWisp"  Mode:Master
  ///           Frequency:5.180 GHz  Access Point: AA:BB:CC:...
  ///           Bit Rate:270 Mb/s   Tx-Power:25 dBm
  ///           Link Quality=54/70  Signal level=-56 dBm  Noise level=-95 dBm
  static void _enrichFromIwconfig(String output, Map<String, String> map) {
    final essid = RegExp(r'ESSID:"?([^"\n]+)"?').firstMatch(output)?.group(1)?.trim();
    if (essid != null && essid.isNotEmpty && map['wlanEssid'] == null) {
      map['wlanEssid'] = essid;
    }
    final mode = RegExp(r'Mode:(\S+)').firstMatch(output)?.group(1)?.trim();
    if (mode != null && map['wlanMode'] == null) {
      map['wlanMode'] = mode;
    }
    final freq = RegExp(r'Frequency:([\d.]+)\s*GHz').firstMatch(output)?.group(1);
    if (freq != null && map['wlanFrequency'] == null) {
      // GHz → MHz
      final ghz = double.tryParse(freq);
      if (ghz != null) map['wlanFrequency'] = (ghz * 1000).round().toString();
    }
    final signal = RegExp(r'Signal level=(-?\d+)').firstMatch(output)?.group(1);
    if (signal != null && map['wlanSignal'] == null) {
      map['wlanSignal'] = signal;
    }
    final noise = RegExp(r'Noise level=(-?\d+)').firstMatch(output)?.group(1);
    if (noise != null && map['wlanNoiseFloor'] == null) {
      map['wlanNoiseFloor'] = noise;
    }
    final bitrate = RegExp(r'Bit Rate[:=]\s*([\d.]+)\s*Mb/s').firstMatch(output)?.group(1);
    if (bitrate != null) {
      final rate = double.tryParse(bitrate)?.round().toString();
      if (rate != null) {
        if (map['wlanTxRate'] == null) map['wlanTxRate'] = rate;
        if (map['wlanRxRate'] == null) map['wlanRxRate'] = rate;
      }
    }
  }

  /// ifconfig output → list of interface maps مع RX/TX bytes
  /// نموذج (busybox / Linux):
  ///   eth0      Link encap:Ethernet  HWaddr AA:BB:CC:...
  ///             UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
  ///             RX packets:12345 errors:0
  ///             RX bytes:1234567 (1.1 MB)  TX bytes:987654 (964.5 KB)
  static List<Map<String, String>> _parseIfconfig(String output) {
    final result = <Map<String, String>>[];
    // نقسّم على blocks بحيث كل block يبدأ باسم interface في العمود 0
    final lines = output.split('\n');
    Map<String, String>? current;
    for (final line in lines) {
      if (line.isEmpty) continue;
      // interface header (يبدأ بحرف في العمود 0، ليس space)
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        // نحفظ الـinterface السابق
        if (current != null && current['name'] != null) {
          result.add(current);
        }
        // اسم الـinterface هو أوّل token
        final name = line.split(RegExp(r'\s+')).first;
        current = {'name': name};
        // hwaddr قد يكون في نفس السطر
        final hw = RegExp(r'HWaddr\s+([0-9A-Fa-f:]+)').firstMatch(line)?.group(1);
        if (hw != null) current['hwaddr'] = hw;
        // flags
        final up = line.contains('UP') || line.contains('RUNNING');
        current['up'] = up ? 'true' : 'false';
      } else if (current != null) {
        // detail line
        if (current['hwaddr'] == null) {
          final hw = RegExp(r'HWaddr\s+([0-9A-Fa-f:]+)|ether\s+([0-9A-Fa-f:]+)')
              .firstMatch(line);
          if (hw != null) current['hwaddr'] = hw.group(1) ?? hw.group(2) ?? '';
        }
        final rxBytes = RegExp(r'RX\s+bytes:(\d+)|RX packets \d+\s+bytes\s+(\d+)')
            .firstMatch(line);
        if (rxBytes != null) {
          current['rx_bytes'] = rxBytes.group(1) ?? rxBytes.group(2) ?? '';
        }
        final txBytes = RegExp(r'TX\s+bytes:(\d+)|TX packets \d+\s+bytes\s+(\d+)')
            .firstMatch(line);
        if (txBytes != null) {
          current['tx_bytes'] = txBytes.group(1) ?? txBytes.group(2) ?? '';
        }
        // flags جميعاً في السطر الثاني عادة
        if (line.contains('UP') || line.contains('RUNNING')) {
          current['up'] = 'true';
        }
      }
    }
    if (current != null && current['name'] != null) {
      result.add(current);
    }
    return result;
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

  /// يبني من mca-status output map + interfaces + wstalist stations (اختياريّان)
  factory UbntStats.fromMcaStatus(
    Map<String, String> m, {
    List<Map<String, String>> interfaces = const [],
    List<Map<String, dynamic>> wstalistStations = const [],
  }) {
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

    // Stations: نُفضّل wstalist (JSON — أدقّ وأكمل) على mca-status
    final stations = <UbntStation>[];
    if (wstalistStations.isNotEmpty) {
      // wstalist format:
      // [{"mac":"AA:BB:...", "lastip":"192.168.1.10", "name":"host1",
      //   "signal":-58, "noisefloor":-95, "ccq":100, "tx":150, "rx":135,
      //   "uptime":12345, "tx_bytes":..., "rx_bytes":..., "rssi":58}, ...]
      for (final s in wstalistStations) {
        // remote قد تكون nested
        final remote = (s['remote'] as Map?)?.cast<String, dynamic>() ?? const {};
        stations.add(UbntStation(
          mac: (s['mac'] ?? '').toString(),
          ip: _strOrNull(s['lastip']) ?? _strOrNull(remote['ip']),
          hostname: _strOrNull(s['name']) ?? _strOrNull(remote['hostname']),
          signal: _n(s['signal']),
          noise: _n(s['noisefloor']),
          ccq: _n(s['ccq']),
          txRate: _n(s['tx']),
          rxRate: _n(s['rx']),
          connTime: _n(s['uptime'] ?? s['conn_time']),
        ));
      }
    } else {
      // fallback: mca-status station1_*, station2_*, ...
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
    }

    // Interfaces من ifconfig
    final ifs = interfaces.map((raw) {
      final speed = _n(raw['speed']);
      return UbntInterface(
        ifname: raw['name'] ?? '',
        hwaddr: raw['hwaddr'] ?? '',
        enabled: raw['up'] == 'true',
        plugged: raw['up'] == 'true',
        rxBytes: int.tryParse(raw['rx_bytes'] ?? ''),
        txBytes: int.tryParse(raw['tx_bytes'] ?? ''),
        speed: speed > 0 ? speed : null,
      );
    }).where((i) => i.ifname.isNotEmpty && i.ifname != 'lo').toList();

    return UbntStats(
      host: host,
      wireless: wireless,
      interfaces: ifs,
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
String? _strOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int _n(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  if (s.isEmpty) return 0;
  return int.tryParse(s) ?? (double.tryParse(s)?.toInt() ?? 0);
}
