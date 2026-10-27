import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mikrotik_api.dart';
import 'snmp_client.dart';

/// ميكروتك عبر SNMP v2c — حين يختار الوكيل SNMP لأنّ الـAPI والويب وSSH مقفولة عليه.
///
/// ٢٧ أكتوبر — المالك: «لازم نفعل ميزات ssh و snmp وويب للمايكروتيك اكو اجهزه هواي مقفول عليها».
/// الأرقام من MIKROTIK-MIB الرسميّ (REVISION 2026-07-07) وHOST-RESOURCES-MIB وIF-MIB، وتُبنى منها `MikrotikStats`
/// نفسها فتعمل اللوحة والنظرة العامّة بلا تفريع. ما لا يحمله SNMP يبقى فارغاً لا صفراً: عرض القناة وقدرة الإرسال
/// وحالة مزوّد الطاقة.
class MikrotikSnmp {
  MikrotikSnmp._();

  /// الاختبارات واللقطات: إحصاءاتٌ جاهزة بدل UDP حقيقيّ.
  @visibleForTesting
  static Future<MikrotikStats> Function()? debugFetch;

  static const sysDescr = '1.3.6.1.2.1.1.1.0';
  static const sysUpTime = '1.3.6.1.2.1.1.3.0';
  static const boardName = '1.3.6.1.4.1.14988.1.1.7.9.0';
  static const licVersion = '1.3.6.1.4.1.14988.1.1.4.4.0';
  // صحّة الجهاز — الصيغة «d-1» في الـMIB: أعشار (حرارة ×10 · فولت ×10).
  static const hlCpuTemp = '1.3.6.1.4.1.14988.1.1.3.6.0';
  static const hlBoardTemp = '1.3.6.1.4.1.14988.1.1.3.7.0';
  static const hlVoltage = '1.3.6.1.4.1.14988.1.1.3.8.0';
  static const hlTemperature = '1.3.6.1.4.1.14988.1.1.3.10.0';
  static const hlProcessorTemp = '1.3.6.1.4.1.14988.1.1.3.11.0';
  static const hlCpuFrequency = '1.3.6.1.4.1.14988.1.1.3.14.0';
  static const scalars = [
    sysDescr, sysUpTime, boardName, licVersion, //
    hlCpuTemp, hlBoardTemp, hlVoltage, hlTemperature, hlProcessorTemp, hlCpuFrequency,
  ];

  static const hrProcessorLoad = '1.3.6.1.2.1.25.3.3.1.2';
  static const hrStorageEntry = '1.3.6.1.2.1.25.2.3.1'; // .3 الوصف · .4 الوحدة · .5 الحجم · .6 المستعمل
  /// جدول المقاييس (RouterOS 7): .2 الاسم · .3 القيمة · .4 الوحدة (1 °C · 2 rpm · 3 dV · 4 dA · 5 dW · 6 حالة).
  static const gaugeEntry = '1.3.6.1.4.1.14988.1.1.3.100.1';

  static const ifName = '1.3.6.1.2.1.31.1.1.1.1';
  static const ifType = '1.3.6.1.2.1.2.2.1.3';
  static const ifMtu = '1.3.6.1.2.1.2.2.1.4';
  static const ifAdmin = '1.3.6.1.2.1.2.2.1.7';
  static const ifOper = '1.3.6.1.2.1.2.2.1.8';
  static const ifHcIn = '1.3.6.1.2.1.31.1.1.1.6';
  static const ifHcOut = '1.3.6.1.2.1.31.1.1.1.10';
  static const ifHighSpeed = '1.3.6.1.2.1.31.1.1.1.15';
  static const ifColumns = [ifName, ifType, ifMtu, ifAdmin, ifOper, ifHcIn, ifHcOut, ifHighSpeed];

  /// وضع المحطّة: .2 إرسال · .3 استقبال (bps) · .4 الإشارة · .5 SSID · .6 BSSID · .7 التردّد · .8 النطاق · .9/.10 CCQ.
  static const wlStatEntry = '1.3.6.1.4.1.14988.1.1.1.1.1';

  /// جدول التسجيل — الفهرس ماك العميل (٦ أجزاء) ثمّ ifIndex: .3 الإشارة · .8/.9 السرعتان (bps) · .11 المدّة (TimeTicks)
  /// · .12 SNR · .19 إشارة الإرسال · .20 اسم الراديو.
  static const wlRtabEntry = '1.3.6.1.4.1.14988.1.1.1.2.1';

  /// وضع نقطة الوصول: .4 SSID · .6 العملاء · .7 التردّد · .8 النطاق · .10 CCQ.
  static const wlApEntry = '1.3.6.1.4.1.14988.1.1.1.3.1';

  /// 60 GHz: .2 الوضع (0 ap-bridge · 1 station-bridge · 2 sniff · 3 bridge) · .3 SSID · .4 متّصل · .5 الطرف الآخر
  /// · .6 التردّد · .7 MCS · .8 جودة الإشارة ٪ · .9 القطاع · .11 وصفه · .12 RSSI dBm · .13 سرعة الربط.
  static const w60gEntry = '1.3.6.1.4.1.14988.1.1.1.8.1';

  /// محطّات 60 GHz: .2 متّصل · .3 الطرف الآخر · .4 MCS · .5 الجودة · .8 السرعة Mbps · .9 RSSI · .10 المسافة (م).
  static const w60gStaEntry = '1.3.6.1.4.1.14988.1.1.1.9.1';

  static Future<MikrotikStats> fetch({
    required String host,
    int port = 161,
    required String community,
    Duration timeout = const Duration(seconds: 4),
    bool vitalsOnly = false,
    void Function(MikrotikStats partial)? onPartialReady,
  }) async {
    final fake = debugFetch;
    if (fake != null) {
      final s = await fake();
      onPartialReady?.call(s);
      return s;
    }
    final snmp = SnmpV2c(host: host, port: port, community: community, timeout: timeout);
    final all = <String, Varbind>{};
    void put(Iterable<Varbind> vbs) {
      for (final v in vbs) {
        if (!v.isAbsent) all[v.oid] = v;
      }
    }

    try {
      put(await snmp.get(scalars));
    } catch (_) {
      throw MikrotikException('لا ردّ من SNMP — فعّله على الجهاز (IP ← SNMP) وتأكّد من الـcommunity والمنفذ $port');
    }
    if (all.isEmpty) {
      throw MikrotikException('الجهاز ردّ بلا قيم — الـcommunity لا تملك صلاحيّة القراءة');
    }
    Future<void> walk(String base, {int chunk = 20}) async {
      try {
        put(await snmp.walk(base, chunkSize: chunk));
      } catch (_) {/* جدولٌ لا يدعمه الإصدار — يبقى فارغاً */}
    }

    await walk(hrProcessorLoad, chunk: 8);
    await walk(hrStorageEntry, chunk: 12);
    await walk(gaugeEntry);
    if (onPartialReady != null) {
      try {
        onPartialReady(build(all, vitalsOnly: true, withInterfaces: false));
      } catch (_) {}
    }
    try {
      put(await _pairedColumns(snmp, ifColumns));
    } catch (_) {/* بلا منافذ — تبقى الأرقام الحيويّة */}
    if (!vitalsOnly) {
      for (final t in [wlApEntry, wlStatEntry, wlRtabEntry, w60gEntry, w60gStaEntry]) {
        await walk(t);
      }
    }
    return build(all, vitalsOnly: vitalsOnly);
  }

  /// أعمدةٌ متوازية بطلبٍ واحد لكلّ دفعة صفوف — راوتر PPPoE فيه مئات الواجهات، وثمانية مسوحٍ منفصلة تعني مئة طلب.
  static Future<List<Varbind>> _pairedColumns(SnmpV2c snmp, List<String> columns,
      {int rows = 10, int maxRounds = 60}) async {
    final out = <Varbind>[];
    var cursors = [...columns];
    for (var round = 0; round < maxRounds; round++) {
      final vbs = await snmp.getBulkColumns(cursors, maxRepetitions: rows);
      if (vbs.isEmpty) break;
      final next = [...cursors];
      var progressed = false;
      for (var i = 0; i < vbs.length; i++) {
        final col = i % columns.length;
        final v = vbs[i];
        if (v.isAbsent || !v.oid.startsWith('${columns[col]}.')) continue;
        out.add(v);
        next[col] = v.oid;
        progressed = true;
      }
      // العمود الأوّل (الاسم) يقود: خرج من شجرته ⇒ انتهى الجدول.
      if (!progressed || next[0] == cursors[0]) break;
      cursors = next;
    }
    return out;
  }

  /// المجموعة المقروءة (OID ← قيمة) ← إحصاءات. مكشوفة للاختبار بقيمٍ ثابتة.
  @visibleForTesting
  static MikrotikStats build(Map<String, Varbind> all, {bool vitalsOnly = false, bool withInterfaces = true}) {
    int? i(String oid) => all[oid]?.isNumeric == true ? all[oid]!.asInt : null;
    String? s(String oid) {
      final v = all[oid];
      if (v == null || v.rawTag != 0x04) return null;
      final t = v.asString.trim();
      return t.isEmpty ? null : t;
    }

    // ── المعالج والذاكرة ──
    final loads = [for (final e in _column(all, hrProcessorLoad).values) if (e.isNumeric) e.asInt];
    final cpu = loads.isEmpty ? 0 : (loads.reduce((a, b) => a + b) / loads.length).round();
    final storage = _table(all, hrStorageEntry);
    int memTotal = 0, memUsed = 0;
    for (final idx in (storage[3] ?? const <String, Varbind>{}).keys) {
      final descr = storage[3]![idx]!.asString.toLowerCase();
      if (!descr.contains('main memory') && !descr.contains('ram')) continue;
      final units = storage[4]?[idx]?.asInt ?? 1;
      memTotal = (storage[5]?[idx]?.asInt ?? 0) * units;
      memUsed = (storage[6]?[idx]?.asInt ?? 0) * units;
      break;
    }

    // ── الصحّة: جدول المقاييس (7) أوّلاً، ثمّ القيم المفردة (6) بأعشارها ──
    int? temp;
    double? voltage;
    final fans = <MikrotikHealthItem>[];
    final temps = <MikrotikHealthItem>[];
    final gauges = _table(all, gaugeEntry);
    for (final idx in (gauges[2] ?? const <String, Varbind>{}).keys) {
      final name = gauges[2]![idx]!.asString.trim().toLowerCase();
      final value = gauges[3]?[idx];
      final unit = gauges[4]?[idx]?.asInt;
      if (name.isEmpty || value == null || !value.isNumeric) continue;
      final v = value.asInt;
      switch (unit) {
        case 1: // °C
          temps.add(MikrotikHealthItem(name: name, valueStr: '$v C', intValue: v));
          if (temp == null || name.contains('cpu')) temp = v;
        case 2: // rpm
          if (v > 0) fans.add(MikrotikHealthItem(name: name.replaceAll('-speed', ''), valueStr: '$v RPM', intValue: v));
        case 3: // dV
          if (name.contains('voltage')) voltage ??= v / 10;
      }
    }
    int? deci(String oid) {
      final v = i(oid);
      return v == null || v == 0 ? null : (v / 10).round();
    }

    temp ??= deci(hlProcessorTemp) ?? deci(hlCpuTemp) ?? deci(hlTemperature) ?? deci(hlBoardTemp);
    if (voltage == null) {
      final v = i(hlVoltage);
      if (v != null && v > 0) voltage = v / 10;
    }

    final descr = s(sysDescr) ?? '';
    final board = s(boardName) ?? descr.replaceFirst(RegExp(r'^RouterOS\s*'), '').trim();
    final ticks = i(sysUpTime);

    // ── المنافذ ──
    final names = {for (final e in _column(all, ifName).entries) e.key: e.value.asString};
    final types = _column(all, ifType);
    final admin = _column(all, ifAdmin);
    final oper = _column(all, ifOper);
    final mtus = _column(all, ifMtu);
    final hcIn = _column(all, ifHcIn);
    final hcOut = _column(all, ifHcOut);
    final speeds = _column(all, ifHighSpeed);
    final interfaces = <MikrotikInterface>[];
    var ppp = 0;
    if (withInterfaces) {
      for (final idx in names.keys) {
        final name = names[idx]!;
        final t = types[idx]?.asInt;
        final running = oper[idx]?.asInt == 1;
        if (t == 23) {
          // جلسات PPP (PPPoE/L2TP/…) واجهاتٌ ديناميكيّة — تُعدّ ولا تُسرد (مئاتٌ على راوتر المشتركين).
          if (running) ppp++;
          continue;
        }
        final type = switch (t) {
          6 => name.startsWith('sfp') ? 'sfp' : (name.startsWith('wlan60') ? 'w60g' : 'ether'),
          71 => 'wlan',
          209 => 'bridge',
          135 => 'vlan',
          _ => '',
        };
        final speed = speeds[idx]?.asInt ?? 0;
        interfaces.add(MikrotikInterface(
          name: name,
          type: type,
          running: running,
          disabled: admin[idx]?.asInt == 2,
          mtu: mtus[idx]?.asInt,
          rxBytes: hcIn[idx]?.asIntOrNull,
          txBytes: hcOut[idx]?.asIntOrNull,
          linkSpeed: running && (type == 'ether' || type == 'sfp') && speed > 0 ? speedText(speed) : null,
        ));
      }
    }

    final stats = MikrotikStats(
      cpuLoad: cpu,
      memUsedPercent: memTotal > 0 ? (memUsed * 100 / memTotal).round() : 0,
      memTotalBytes: memTotal,
      memFreeBytes: memTotal > 0 ? memTotal - memUsed : 0,
      uptime: ticks == null ? '' : uptimeText(ticks ~/ 100),
      version: s(licVersion) ?? '',
      boardName: board,
      architectureName: '',
      cpuCount: loads.length,
      cpuFrequencyMhz: i(hlCpuFrequency) ?? 0,
      temperature: temp,
      voltage: voltage,
      fans: fans,
      extraTemps: temps,
      interfaces: interfaces,
      pppActiveCount: ppp,
      via: 'SNMP',
    );
    if (vitalsOnly) return stats;

    // ── اللاسلكيّ ──
    String nameOf(String idx) => names[idx] ?? 'if$idx';
    final wireless = <MikrotikWireless>[];
    final clients = <MikrotikWirelessClient>[];
    final ap = _table(all, wlApEntry);
    for (final idx in (ap[4] ?? ap[7] ?? const <String, Varbind>{}).keys) {
      wireless.add(MikrotikWireless(
        name: nameOf(idx),
        ssid: ap[4]?[idx]?.asString ?? '',
        mode: 'ap-bridge',
        band: ap[8]?[idx]?.asString ?? '',
        frequency: ap[7]?[idx]?.asInt ?? 0,
        channelWidth: 0,
        txPower: 0,
        disabled: admin[idx]?.asInt == 2,
        running: oper[idx]?.asInt == 1,
      ));
    }
    final st = _table(all, wlStatEntry);
    for (final idx in (st[5] ?? st[7] ?? const <String, Varbind>{}).keys) {
      final name = nameOf(idx);
      wireless.add(MikrotikWireless(
        name: name,
        ssid: st[5]?[idx]?.asString ?? '',
        mode: 'station',
        band: st[8]?[idx]?.asString ?? '',
        frequency: st[7]?[idx]?.asInt ?? 0,
        channelWidth: 0,
        txPower: 0,
        disabled: admin[idx]?.asInt == 2,
        running: oper[idx]?.asInt == 1,
      ));
      // المحطّة: الطرف الآخر نقطة الوصول — كما يُرجعه جدول التسجيل عبر الـAPI.
      final bssid = st[6]?[idx]?.asMac;
      final sig = st[4]?[idx]?.asInt ?? 0;
      if (bssid != null && sig < 0) {
        clients.add(MikrotikWirelessClient(
          mac: bssid,
          iface: name,
          signalStrength: sig,
          signalToNoise: 0,
          txCcq: st[9]?[idx]?.asInt ?? 0,
          rxCcq: st[10]?[idx]?.asInt ?? 0,
          txRate: ((st[2]?[idx]?.asInt ?? 0) / 1000000).round(),
          rxRate: ((st[3]?[idx]?.asInt ?? 0) / 1000000).round(),
          uptime: 0,
        ));
      }
    }
    final rt = _table(all, wlRtabEntry);
    for (final idx in (rt[3] ?? const <String, Varbind>{}).keys) {
      final parts = idx.split('.');
      if (parts.length < 7) continue;
      final mac = [for (final p in parts.take(6)) (int.tryParse(p) ?? 0).toRadixString(16).padLeft(2, '0')]
          .join(':')
          .toUpperCase();
      final radio = rt[20]?[idx]?.asString.trim();
      clients.add(MikrotikWirelessClient(
        mac: mac,
        iface: nameOf(parts[6]),
        signalStrength: rt[3]![idx]!.asInt,
        txSignalStrength: rt[19]?[idx]?.asInt ?? 0,
        signalToNoise: rt[12]?[idx]?.asInt ?? 0,
        txCcq: 0,
        rxCcq: 0,
        txRate: ((rt[8]?[idx]?.asInt ?? 0) / 1000000).round(),
        rxRate: ((rt[9]?[idx]?.asInt ?? 0) / 1000000).round(),
        uptime: (rt[11]?[idx]?.asInt ?? 0) ~/ 100,
        hostname: radio == null || radio.isEmpty ? null : radio,
      ));
    }

    // ── 60 GHz ──
    final links = <MikrotikW60gLink>[];
    final w = _table(all, w60gEntry);
    final sta = _table(all, w60gStaEntry);
    final staConnected = [for (final e in (sta[2] ?? const <String, Varbind>{}).entries) if (e.value.asInt == 1) e.key];
    final w60gIdx = (w[2] ?? w[6] ?? const <String, Varbind>{}).keys.toList();
    for (final idx in w60gIdx) {
      final name = nameOf(idx);
      final mode = switch (w[2]?[idx]?.asInt) {
        0 => 'ap-bridge',
        1 => 'station-bridge',
        2 => 'sniff',
        _ => 'bridge',
      };
      final connected = w[4]?[idx]?.asInt == 1;
      final freq = w[6]?[idx]?.asInt;
      wireless.add(MikrotikWireless(
        name: name,
        ssid: w[3]?[idx]?.asString ?? '',
        mode: mode,
        band: '60ghz',
        frequency: freq ?? 0,
        channelWidth: 2160,
        txPower: 0,
        disabled: admin[idx]?.asInt == 2,
        running: oper[idx]?.asInt == 1,
      ));
      int? signed(int col) => connected && w[col]?[idx] != null ? w[col]![idx]!.asInt : null;
      final rssi = signed(12);
      final pct = signed(8);
      var phy = signed(13);
      if (phy != null && phy > 100000) phy = (phy / 1000000).round(); // احتياط: إصدارٌ يكتبها bps
      // المسافة في جدول المحطّات وحده؛ تُنسب للواجهة حين لا لبس: واجهة 60 واحدة ومحطّة متّصلة واحدة.
      double? distance;
      if (connected && w60gIdx.length == 1 && staConnected.length == 1) {
        final d = sta[10]?[staConnected.first]?.asInt;
        if (d != null && d > 0) distance = d.toDouble();
      }
      final info = w[11]?[idx]?.asString.trim();
      links.add(MikrotikW60gLink(
        iface: name,
        connected: connected,
        frequency: freq != null && freq > 0 ? freq : null,
        remoteMac: connected ? (w[5]?[idx])?.asMac : null,
        rssi: rssi != null && rssi < 0 ? rssi : null,
        signalPercent: pct != null && pct >= 0 && pct <= 100 ? pct : null,
        mcs: signed(7),
        phyRateMbps: phy != null && phy > 0 ? phy : null,
        distanceMeters: distance,
        txSector: signed(9),
        txSectorInfo: connected && info != null && info.isNotEmpty ? info : null,
        stations: mode == 'ap-bridge' ? staConnected.length : 0,
      ));
    }

    return stats.copyWith(wirelessInterfaces: wireless, wirelessClients: clients, w60gLinks: links);
  }

  /// «1Gbps» · «2.5Gbps» · «100Mbps» — كما يكتبها `ethernet monitor` فتُلوَّن بالقاعدة نفسها.
  @visibleForTesting
  static String speedText(int mbps) {
    if (mbps < 1000) return '${mbps}Mbps';
    final g = mbps / 1000;
    return g == g.roundToDouble() ? '${g.round()}Gbps' : '${g}Gbps';
  }

  /// ثوانٍ ← «1w2d3h4m5s» كما يكتبها RouterOS — وعليها يُبنى «يعمل منذ».
  @visibleForTesting
  static String uptimeText(int seconds) {
    if (seconds <= 0) return '0s';
    final w = seconds ~/ 604800, d = seconds % 604800 ~/ 86400, h = seconds % 86400 ~/ 3600;
    final m = seconds % 3600 ~/ 60, s = seconds % 60;
    return [if (w > 0) '${w}w', if (d > 0) '${d}d', if (h > 0) '${h}h', if (m > 0) '${m}m', if (s > 0) '${s}s'].join();
  }

  /// عمودٌ واحد: الفهرس (ما بعد العمود) ← القيمة.
  static Map<String, Varbind> _column(Map<String, Varbind> all, String column) {
    final p = '$column.';
    return {for (final e in all.entries) if (e.key.startsWith(p)) e.key.substring(p.length): e.value};
  }

  /// جدول: رقم العمود ← (الفهرس ← القيمة). الفهرس نصٌّ لأنّه قد يكون مركّباً (ماك + ifIndex).
  static Map<int, Map<String, Varbind>> _table(Map<String, Varbind> all, String entry) {
    final p = '$entry.';
    final out = <int, Map<String, Varbind>>{};
    for (final e in all.entries) {
      if (!e.key.startsWith(p)) continue;
      final rest = e.key.substring(p.length);
      final dot = rest.indexOf('.');
      if (dot <= 0) continue;
      final col = int.tryParse(rest.substring(0, dot));
      if (col == null) continue;
      (out[col] ??= <String, Varbind>{})[rest.substring(dot + 1)] = e.value;
    }
    return out;
  }
}
