import 'dart:async';

import 'package:flutter/foundation.dart';

import 'snmp_client.dart';

/// **Ruijie / Reyee API** — SNMP v2c only (MVP).
///
/// **لماذا SNMP فقط**:
/// - REST على Ruijie Cloud = partner-gated (نحتاج contract مع Ruijie).
/// - REST داخل الجهاز = غير موثّق علناً.
/// - SSH يعطي per-STA RSSI لكن يحتاج parser معقّد (Netmiko `ruijie_os`).
/// - SNMP يعطي 80% من احتياج WISP: CPU/RAM/temp/interfaces/uptime.
/// - نستعمل نفس SnmpV2c الذي يستعمله Mimosa (لا transport جديد).
///
/// **متطلّبات على الجهاز**:
/// - Reyee AP: فعّل SNMP من web UI (Advanced → Basics → SNMP) + community read-only.
/// - RGOS: `snmp-server community <str> ro` — لا default community.
///
/// **نطاق MVP**: sysDescr، sysName، uptime، CPU، RAM، interfaces (Rx/Tx + status).
/// المتبقّي (temperature، AP count، wireless clients، reboot) — Phase 2.
///
/// **مصادر الـOIDs**:
/// - Ruijie support forum thread 151 (enterprise .4881.*)
/// - IF-MIB (RFC 2863)، HOST-RESOURCES-MIB (RFC 2790) — fallback عام
class RuijieApi {
  /// Enterprise root — `.1.3.6.1.4.1.4881` (Ruijie/myMgmt)
  static const String _enterprise = '1.3.6.1.4.1.4881';

  // — Standard MIB-II (يعمل على أي جهاز SNMP) —
  static const String _oidSysDescr = '1.3.6.1.2.1.1.1.0';
  static const String _oidSysUpTime = '1.3.6.1.2.1.1.3.0';
  static const String _oidSysName = '1.3.6.1.2.1.1.5.0';

  // — HOST-RESOURCES-MIB fallback (يشتغل حتى لو Ruijie enterprise mib غير موجود) —
  static const String _oidHrProcessorLoad = '1.3.6.1.2.1.25.3.3.1.2';
  static const String _oidHrStorageType = '1.3.6.1.2.1.25.2.3.1.2';
  static const String _oidHrStorageDescr = '1.3.6.1.2.1.25.2.3.1.3';
  static const String _oidHrStorageUnits = '1.3.6.1.2.1.25.2.3.1.4';
  static const String _oidHrStorageSize = '1.3.6.1.2.1.25.2.3.1.5';
  static const String _oidHrStorageUsed = '1.3.6.1.2.1.25.2.3.1.6';

  // — IF-MIB (interfaces) —
  static const String _oidIfDescr = '1.3.6.1.2.1.2.2.1.2';
  static const String _oidIfOperStatus = '1.3.6.1.2.1.2.2.1.8';
  static const String _oidIfSpeed = '1.3.6.1.2.1.2.2.1.5';
  static const String _oidIfHCInOctets = '1.3.6.1.2.1.31.1.1.1.6';
  static const String _oidIfHCOutOctets = '1.3.6.1.2.1.31.1.1.1.10';

  // — Ruijie enterprise (fallback + primary if HOST-RESOURCES يفشل) —
  //   CPU: 4881.1.1.10.2.36.1.1  (table — walk، خذ average أو max)
  //   Memory used/total: 4881.1.1.10.2.35.1.1.1  (walk، احسب %)
  static const String _oidRuijieCpuTable = '$_enterprise.1.1.10.2.36.1.1';
  static const String _oidRuijieMemTable = '$_enterprise.1.1.10.2.35.1.1.1';

  /// جلب بيانات كاملة عن الجهاز عبر SNMP.
  static Future<RuijieStats> fetchStats({
    required String host,
    int port = 161,
    required String community,
    Duration timeout = const Duration(seconds: 5),
    void Function(RuijieStats partial)? onPartialReady,
  }) async {
    final snmp = SnmpV2c(
      host: host,
      port: port,
      community: community,
      timeout: timeout,
    );

    // ═══ Tier 1 (سريع ~500ms): system identity + uptime ═══
    final scalars = <String>[
      _oidSysDescr,
      _oidSysName,
      _oidSysUpTime,
    ];

    final results = <String, Varbind>{};
    try {
      for (final vb in await snmp.get(scalars)) {
        results[vb.oid] = vb;
      }
      // ⚡ partial: UI يعرض model/uptime فوراً
      if (onPartialReady != null) {
        try {
          onPartialReady(RuijieStats.fromResults(
            Map<String, Varbind>.from(results),
            cpuPercent: null,
            memPercent: null,
            ifaces: const [],
          ));
        } catch (_) {}
      }
    } on SnmpException catch (e) {
      throw RuijieException('فشل الاتصال SNMP: $e\n'
          'تحقّق:\n'
          '• community="$community" صحيح\n'
          '• SNMP مُفعّل على الجهاز (Reyee: Advanced → Basics → SNMP)\n'
          '• Port $port مفتوح (default 161/UDP)');
    }

    // ═══ Tier 2 (~500ms): CPU + Memory عبر HOST-RESOURCES-MIB ═══
    double? cpuPercent;
    double? memPercent;

    // CPU: HOST-RESOURCES-MIB → hrProcessorLoad (يشتغل على 90% من الأجهزة)
    try {
      final cpuLoads = await snmp.walk(_oidHrProcessorLoad, chunkSize: 8);
      if (cpuLoads.isNotEmpty) {
        // Multi-core: خذ المعدّل
        final values = cpuLoads
            .map((vb) => vb.asInt)
            .where((v) => v > 0 && v <= 100)
            .toList();
        if (values.isNotEmpty) {
          cpuPercent = values.reduce((a, b) => a + b) / values.length;
        }
      }
    } catch (_) {/* fallback أدناه */}

    // Fallback CPU: Ruijie enterprise table (.4881.1.1.10.2.36.1.1)
    if (cpuPercent == null) {
      try {
        final rjCpu = await snmp.walk(_oidRuijieCpuTable, chunkSize: 4);
        if (rjCpu.isNotEmpty) {
          final values = rjCpu
              .map((vb) => vb.asInt)
              .where((v) => v >= 0 && v <= 100)
              .toList();
          if (values.isNotEmpty) {
            cpuPercent = values.reduce((a, b) => a + b) / values.length;
          }
        }
      } catch (_) {}
    }

    // Memory: HOST-RESOURCES-MIB hrStorageTable
    //   احسب used% لكل storage entry من نوع "Physical/RAM"
    try {
      final descrRows = await snmp.walk(_oidHrStorageDescr, chunkSize: 12);
      final sizeRows = await snmp.walk(_oidHrStorageSize, chunkSize: 12);
      final usedRows = await snmp.walk(_oidHrStorageUsed, chunkSize: 12);

      final descrByIdx = _mapByLastIndex(descrRows, _oidHrStorageDescr);
      final sizeByIdx = _mapByLastIndex(sizeRows, _oidHrStorageSize);
      final usedByIdx = _mapByLastIndex(usedRows, _oidHrStorageUsed);

      // ابحث عن أوّل entry يحوي "RAM" أو "Physical" أو "memory" في descr
      for (final idx in sizeByIdx.keys) {
        final descr = descrByIdx[idx]?.asString.toLowerCase() ?? '';
        final size = sizeByIdx[idx]?.asInt ?? 0;
        final used = usedByIdx[idx]?.asInt ?? 0;
        if (size > 0 &&
            (descr.contains('ram') ||
                descr.contains('physical') ||
                descr.contains('memory'))) {
          memPercent = (used / size) * 100.0;
          break;
        }
      }
    } catch (_) {/* fallback */}

    // Fallback memory: Ruijie enterprise table
    if (memPercent == null) {
      try {
        final rjMem = await snmp.walk(_oidRuijieMemTable, chunkSize: 4);
        // .4881.1.1.10.2.35.1.1.1 يرجع عادةً pool used + total كصفوف منفصلة
        // نجمع القيم كـpairs (index odd/even)
        int total = 0, used = 0;
        for (var i = 0; i + 1 < rjMem.length; i += 2) {
          total += rjMem[i].asInt;
          used += rjMem[i + 1].asInt;
        }
        if (total > 0) memPercent = (used / total) * 100.0;
      } catch (_) {}
    }

    // ═══ Tier 3 (~500ms-1s): Interfaces عبر IF-MIB ═══
    final ifaces = <RuijieInterface>[];
    try {
      final descrs = await snmp.walk(_oidIfDescr, chunkSize: 20);
      final ops = await snmp.walk(_oidIfOperStatus, chunkSize: 20);
      final speeds = await snmp.walk(_oidIfSpeed, chunkSize: 20);
      final inOctets = await snmp.walk(_oidIfHCInOctets, chunkSize: 20);
      final outOctets = await snmp.walk(_oidIfHCOutOctets, chunkSize: 20);

      final descrByIdx = _mapByLastIndex(descrs, _oidIfDescr);
      final opsByIdx = _mapByLastIndex(ops, _oidIfOperStatus);
      final speedByIdx = _mapByLastIndex(speeds, _oidIfSpeed);
      final inByIdx = _mapByLastIndex(inOctets, _oidIfHCInOctets);
      final outByIdx = _mapByLastIndex(outOctets, _oidIfHCOutOctets);

      for (final idx in descrByIdx.keys.toList()..sort()) {
        final name = descrByIdx[idx]?.asString ?? '';
        if (name.isEmpty) continue;
        // تجاهل الـloopback + null interfaces
        final lower = name.toLowerCase();
        if (lower.contains('loop') || lower.contains('null')) continue;
        ifaces.add(RuijieInterface(
          index: idx,
          name: name,
          operUp: opsByIdx[idx]?.asInt == 1,
          speedMbps: (speedByIdx[idx]?.asInt ?? 0) ~/ 1000000,
          rxBytes: inByIdx[idx]?.asInt ?? 0,
          txBytes: outByIdx[idx]?.asInt ?? 0,
        ));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Ruijie IF-MIB walk فشل: $e');
    }

    if (kDebugMode) {
      debugPrint('══════ Ruijie SNMP snapshot ══════');
      debugPrint('  sysDescr: ${results[_oidSysDescr]?.asString}');
      debugPrint('  sysName:  ${results[_oidSysName]?.asString}');
      debugPrint('  uptime:   ${results[_oidSysUpTime]?.asInt} ticks');
      debugPrint('  CPU:      ${cpuPercent?.toStringAsFixed(1)}%');
      debugPrint('  Memory:   ${memPercent?.toStringAsFixed(1)}%');
      debugPrint('  ifaces:   ${ifaces.length}');
      debugPrint('═══════════════════════════════════');
    }

    return RuijieStats.fromResults(
      results,
      cpuPercent: cpuPercent,
      memPercent: memPercent,
      ifaces: ifaces,
    );
  }

  /// نُظّم varbinds حسب آخر جزء من OID (index الصفّ في الجدول).
  static Map<int, Varbind> _mapByLastIndex(List<Varbind> vbs, String baseOid) {
    final map = <int, Varbind>{};
    for (final vb in vbs) {
      if (!vb.oid.startsWith('$baseOid.')) continue;
      final suffix = vb.oid.substring(baseOid.length + 1);
      final firstDot = suffix.indexOf('.');
      final indexStr = firstDot >= 0 ? suffix.substring(0, firstDot) : suffix;
      final idx = int.tryParse(indexStr);
      if (idx != null) map[idx] = vb;
    }
    return map;
  }
}

// ═══════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════

class RuijieInterface {
  final int index;
  final String name;
  final bool operUp;
  final int speedMbps;
  final int rxBytes;
  final int txBytes;

  const RuijieInterface({
    required this.index,
    required this.name,
    required this.operUp,
    required this.speedMbps,
    required this.rxBytes,
    required this.txBytes,
  });
}

class RuijieStats {
  final String? sysDescr;
  final String? sysName;
  final Duration? uptime;
  final double? cpuPercent;
  final double? memPercent;
  final List<RuijieInterface> ifaces;

  const RuijieStats({
    this.sysDescr,
    this.sysName,
    this.uptime,
    this.cpuPercent,
    this.memPercent,
    this.ifaces = const [],
  });

  factory RuijieStats.fromResults(
    Map<String, Varbind> r, {
    double? cpuPercent,
    double? memPercent,
    required List<RuijieInterface> ifaces,
  }) {
    // sysUpTime في SNMP = timeticks (1/100 ثانية)
    final upTicks = r[RuijieApi._oidSysUpTime]?.asInt ?? 0;
    return RuijieStats(
      sysDescr: r[RuijieApi._oidSysDescr]?.asString,
      sysName: r[RuijieApi._oidSysName]?.asString,
      uptime: upTicks > 0 ? Duration(milliseconds: upTicks * 10) : null,
      cpuPercent: cpuPercent,
      memPercent: memPercent,
      ifaces: ifaces,
    );
  }
}

class RuijieException implements Exception {
  final String message;
  RuijieException(this.message);
  @override
  String toString() => 'RuijieException: $message';
}
