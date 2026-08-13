import 'dart:async';

import 'package:flutter/foundation.dart';

import 'snmp_client.dart';

/// **Mimosa Networks API** — SNMP v2c only.
///
/// **لماذا SNMP فقط**: Mimosa يعطّل SSH/Telnet/CLI افتراضياً على كل الموديلات
/// (B5/B5c/B11/B24/A5/C5/C5c). REST API متاح لكن XML، محدود بـ4 endpoints،
/// ويحتاج تفعيل HTTPS أوّلاً. SNMP هو **الوحيد** الي يعطي:
///   - Signal لكل chain، SNR، Noise
///   - Throughput (PHY rates)، Packet Error Rate
///   - Temperature (بدقّة 0.1°C)
///   - GPS coordinates
///   - قائمة العملاء الكاملة (لـA5 PtMP AP)
///
/// **لا يوفّرها Mimosa عبر أي وسيلة**: CPU%، RAM (firmware مقصود).
///
/// **المصادر**:
/// - LibreNMS: https://github.com/librenms/librenms/blob/master/LibreNMS/OS/Mimosa.php
/// - MIB BFIVE (B5 PtP): https://github.com/librenms/librenms/blob/master/mibs/mimosa/MIMOSA-NETWORKS-BFIVE-MIB
/// - MIB PTMP (A5/C5):   https://github.com/librenms/librenms/blob/master/mibs/mimosa/MIMOSA-NETWORKS-PTMP-MIB
class MimosaApi {
  /// Enterprise root — `.1.3.6.1.4.1.43356`
  static const String _enterprise = '1.3.6.1.4.1.43356';

  /// BFIVE (B5, B5c, B11, B24 PtP) — `.enterprise.2.1`
  static const String _bfive = '$_enterprise.2.1';

  // — Standard MIB-II (works for any SNMP device) —
  static const String _oidSysDescr   = '1.3.6.1.2.1.1.1.0';
  static const String _oidSysUpTime  = '1.3.6.1.2.1.1.3.0';
  static const String _oidSysName    = '1.3.6.1.2.1.1.5.0';

  // — Mimosa scalar OIDs (BFIVE) —
  //   mimosaGeneral.1 = mimosaDeviceName          → 2.1.1.1.0
  //   mimosaGeneral.2 = mimosaSerialNumber        → 2.1.1.2.0
  //   mimosaGeneral.3 = mimosaFirmwareVersion     → 2.1.1.3.0
  //   mimosaGeneral.4 = mimosaFirmwareBuildDate   → 2.1.1.4.0
  //   mimosaGeneral.5 = mimosaLastRebootTime      → 2.1.1.5.0
  //   mimosaGeneral.8 = mimosaInternalTemp        → 2.1.1.8.0 (×10 lookup: 42.7°C = 427)
  static const String _oidDeviceName       = '$_bfive.1.1.0';
  static const String _oidSerialNumber     = '$_bfive.1.2.0';
  static const String _oidFirmwareVersion  = '$_bfive.1.3.0';
  static const String _oidInternalTemp     = '$_bfive.1.8.0';

  //   mimosaLocInfo.2 = longitude, .3 = latitude, .4 = altitude, .7 = gps sats
  static const String _oidLongitude        = '$_bfive.2.2.0';
  static const String _oidLatitude         = '$_bfive.2.3.0';
  static const String _oidAltitude         = '$_bfive.2.4.0';
  static const String _oidGpsSats          = '$_bfive.2.7.0';

  //   mimosaTdmaInfo.1 = wirelessMode, .3 = tdmaMode
  static const String _oidWirelessMode     = '$_bfive.4.1.0';
  static const String _oidTdmaMode         = '$_bfive.4.3.0';

  //   mimosaRfInfo.4 = antennaGain
  //   mimosaRfInfo.5 = totalTxPower
  //   mimosaRfInfo.6 = totalRxPower
  //   mimosaRfInfo.7 = targetRxPower
  static const String _oidAntennaGain      = '$_bfive.6.4.0';
  static const String _oidTotalTxPower     = '$_bfive.6.5.0';
  static const String _oidTotalRxPower     = '$_bfive.6.6.0';
  static const String _oidTargetRxPower    = '$_bfive.6.7.0';

  //   mimosaPerfInfo.1 = phyRxRate, .2 = phyTxRate, .3 = perTxRate, .4 = perRxRate
  static const String _oidPhyRxRate        = '$_bfive.7.1.0';
  static const String _oidPhyTxRate        = '$_bfive.7.2.0';
  static const String _oidPerTxRate        = '$_bfive.7.3.0';
  static const String _oidPerRxRate        = '$_bfive.7.4.0';

  // — Mimosa chain table (per-chain signal) —
  //   mimosaRfInfo.3.1.2.<chain> = mimosaChain (int)
  //   mimosaRfInfo.3.1.3.<chain> = mimosaTxPower
  //   mimosaRfInfo.3.1.4.<chain> = mimosaRxPower
  //   mimosaRfInfo.3.1.5.<chain> = mimosaRxNoise
  //   mimosaRfInfo.3.1.6.<chain> = mimosaSNR
  static const String _oidChainRxPower     = '$_bfive.6.3.1.4';   // GETBULK
  static const String _oidChainRxNoise     = '$_bfive.6.3.1.5';
  static const String _oidChainSnr         = '$_bfive.6.3.1.6';

  /// جلب صورة كاملة عن حالة الجهاز عبر SNMP GET متعدّد + GETBULK للـchain table.
  ///
  /// **Progressive rendering**: [onPartialReady] يُطلق بعد Tier 1
  /// (system + GPS + temp — ~500ms) — UI يعرض device name/temp/uptime
  /// فوراً بدل انتظار Tier 2 (RF details + chains — ~1s إضافيّة).
  static Future<MimosaStats> fetchStats({
    required String host,
    int port = 161,
    required String community,
    Duration timeout = const Duration(seconds: 5),
    void Function(MimosaStats partial)? onPartialReady,
  }) async {
    final snmp = SnmpV2c(
      host: host,
      port: port,
      community: community,
      timeout: timeout,
    );

    // ═══ Tier 1 (fast — ~500ms): system + GPS + temp ═══
    final scalarBatch1 = <String>[
      _oidSysDescr, _oidSysName, _oidSysUpTime,
      _oidDeviceName, _oidSerialNumber, _oidFirmwareVersion, _oidInternalTemp,
      _oidLongitude, _oidLatitude, _oidGpsSats,
    ];
    // ═══ Tier 2 (~500ms إضافيّة): RF details ═══
    final scalarBatch2 = <String>[
      _oidWirelessMode, _oidTdmaMode,
      _oidAntennaGain, _oidTotalTxPower, _oidTotalRxPower, _oidTargetRxPower,
      _oidPhyRxRate, _oidPhyTxRate, _oidPerTxRate, _oidPerRxRate,
    ];

    final results = <String, Varbind>{};
    try {
      // Tier 1 — نجلبه ونطلق partial فوراً
      for (final vb in await snmp.get(scalarBatch1)) {
        results[vb.oid] = vb;
      }
      // ⚡ partial: UI يعرض device name/temp/GPS/uptime — RF لا يزال فارغ
      if (onPartialReady != null) {
        try {
          onPartialReady(MimosaStats.fromVarbinds(
              Map<String, Varbind>.from(results), chains: const []));
        } catch (_) {}
      }
      // Tier 2 — RF details
      for (final vb in await snmp.get(scalarBatch2)) {
        results[vb.oid] = vb;
      }
    } on SnmpException catch (e) {
      throw MimosaException(
          'فشل جلب بيانات SNMP: $e. تحقّق: community="$community"، '
          'SNMP مفعّل من web UI للجهاز (Preferences → Management → SNMP)');
    }

    // Chain table via walk (2-4 chains عادة) — Tier 3 (اختياري)
    final chains = <MimosaChain>[];
    try {
      final rxPowers = await snmp.walk(_oidChainRxPower, chunkSize: 8);
      final rxNoises = await snmp.walk(_oidChainRxNoise, chunkSize: 8);
      final snrs = await snmp.walk(_oidChainSnr, chunkSize: 8);

      final indexRxPower = _byIndex(rxPowers, _oidChainRxPower);
      final indexRxNoise = _byIndex(rxNoises, _oidChainRxNoise);
      final indexSnr = _byIndex(snrs, _oidChainSnr);

      final allIndices = <int>{...indexRxPower.keys, ...indexRxNoise.keys, ...indexSnr.keys};
      for (final i in allIndices.toList()..sort()) {
        chains.add(MimosaChain(
          index: i,
          rxPowerDbm: _asDbmScaled(indexRxPower[i]),
          rxNoiseDbm: _asDbmScaled(indexRxNoise[i]),
          snrDb: _asDbmScaled(indexSnr[i]),
        ));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Mimosa chain walk failed: $e');
    }

    if (kDebugMode) {
      debugPrint('══════ Mimosa SNMP scalars ══════');
      results.forEach((oid, vb) {
        debugPrint('  $oid: ${vb.asString}');
      });
      debugPrint('  chains: ${chains.length}');
      debugPrint('════════════════════════════════');
    }

    return MimosaStats.fromVarbinds(results, chains: chains);
  }

  /// index → varbind (على أساس آخر ID في الـOID كـsubIndex)
  static Map<int, Varbind> _byIndex(List<Varbind> vbs, String basePrefix) {
    final map = <int, Varbind>{};
    for (final vb in vbs) {
      final suffix = vb.oid.substring(basePrefix.length + 1);
      final idx = int.tryParse(suffix.split('.').first);
      if (idx != null) map[idx] = vb;
    }
    return map;
  }

  /// Mimosa returns dBm × 10 in most fields (e.g. 427 = 42.7 dBm)
  static double? _asDbmScaled(Varbind? vb) {
    if (vb == null) return null;
    final v = vb.asInt;
    return v == 0 ? null : v / 10.0;
  }
}

// ═══════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════

class MimosaStats {
  final String? sysDescr;
  final String? sysName;
  final int sysUptimeSec;
  final String? deviceName;
  final String? serialNumber;
  final String? firmwareVersion;
  final double? temperatureC;

  // GPS
  final double? latitude;
  final double? longitude;
  final int? altitude;
  final int? gpsSats;

  // TDMA / mode
  final int? wirelessMode;      // 1=AP, 2=STA (typical)
  final int? tdmaMode;

  // RF summary
  final int? antennaGainDbi;
  final double? totalTxPowerDbm;
  final double? totalRxPowerDbm;
  final double? targetRxPowerDbm;

  // Performance
  final int? phyTxRateMbps;
  final int? phyRxRateMbps;
  final double? perTxRatePct;   // packet error rate %
  final double? perRxRatePct;

  final List<MimosaChain> chains;

  const MimosaStats({
    this.sysDescr,
    this.sysName,
    this.sysUptimeSec = 0,
    this.deviceName,
    this.serialNumber,
    this.firmwareVersion,
    this.temperatureC,
    this.latitude,
    this.longitude,
    this.altitude,
    this.gpsSats,
    this.wirelessMode,
    this.tdmaMode,
    this.antennaGainDbi,
    this.totalTxPowerDbm,
    this.totalRxPowerDbm,
    this.targetRxPowerDbm,
    this.phyTxRateMbps,
    this.phyRxRateMbps,
    this.perTxRatePct,
    this.perRxRatePct,
    this.chains = const [],
  });

  bool get hasGps => latitude != null && longitude != null &&
      latitude != 0 && longitude != 0;

  /// هامش الإشارة عن المتوقّع (dB) — سالب = أضعف من الأمثل
  double? get signalMarginDb {
    final actual = totalRxPowerDbm;
    final target = targetRxPowerDbm;
    if (actual == null || target == null) return null;
    return actual - target;
  }

  /// أفضل SNR بين الـchains
  double? get bestSnrDb {
    final snrs = chains.map((c) => c.snrDb).whereType<double>().toList();
    if (snrs.isEmpty) return null;
    return snrs.reduce((a, b) => a > b ? a : b);
  }

  /// Uptime (sysUpTime.0 يجي بوحدة TimeTicks = centiseconds)
  static int _parseUptime(Varbind? vb) {
    if (vb == null) return 0;
    return vb.asInt ~/ 100;
  }

  factory MimosaStats.fromVarbinds(
    Map<String, Varbind> m, {
    List<MimosaChain> chains = const [],
  }) {
    Varbind? g(String oid) => m[oid];
    double? _n10(String oid) {
      final vb = m[oid];
      if (vb == null) return null;
      final v = vb.asInt;
      return v == 0 ? null : v / 10.0;
    }
    int? _n(String oid) {
      final vb = m[oid];
      if (vb == null) return null;
      final v = vb.asInt;
      return v == 0 ? null : v;
    }
    String? _s(String oid) {
      final vb = m[oid];
      if (vb == null) return null;
      final s = vb.asString.trim();
      return s.isEmpty ? null : s;
    }
    double? _gps(String oid) {
      // Mimosa GPS often stored as int × 1e7 (LibreNMS uses / 1e7)
      final vb = m[oid];
      if (vb == null) return null;
      final v = vb.asInt;
      if (v == 0) return null;
      return v / 10000000.0;
    }

    return MimosaStats(
      sysDescr: _s(MimosaApi._oidSysDescr),
      sysName: _s(MimosaApi._oidSysName),
      sysUptimeSec: _parseUptime(g(MimosaApi._oidSysUpTime)),
      deviceName: _s(MimosaApi._oidDeviceName),
      serialNumber: _s(MimosaApi._oidSerialNumber),
      firmwareVersion: _s(MimosaApi._oidFirmwareVersion),
      temperatureC: _n10(MimosaApi._oidInternalTemp),
      latitude: _gps(MimosaApi._oidLatitude),
      longitude: _gps(MimosaApi._oidLongitude),
      altitude: _n(MimosaApi._oidAltitude),
      gpsSats: _n(MimosaApi._oidGpsSats),
      wirelessMode: _n(MimosaApi._oidWirelessMode),
      tdmaMode: _n(MimosaApi._oidTdmaMode),
      antennaGainDbi: _n(MimosaApi._oidAntennaGain),
      totalTxPowerDbm: _n10(MimosaApi._oidTotalTxPower),
      totalRxPowerDbm: _n10(MimosaApi._oidTotalRxPower),
      targetRxPowerDbm: _n10(MimosaApi._oidTargetRxPower),
      phyTxRateMbps: _n(MimosaApi._oidPhyTxRate),
      phyRxRateMbps: _n(MimosaApi._oidPhyRxRate),
      perTxRatePct: _n10(MimosaApi._oidPerTxRate),
      perRxRatePct: _n10(MimosaApi._oidPerRxRate),
      chains: chains,
    );
  }
}

class MimosaChain {
  final int index;              // 1..N
  final double? rxPowerDbm;
  final double? rxNoiseDbm;
  final double? snrDb;

  const MimosaChain({
    required this.index,
    this.rxPowerDbm,
    this.rxNoiseDbm,
    this.snrDb,
  });
}

class MimosaException implements Exception {
  final String message;
  MimosaException(this.message);
  @override
  String toString() => message;
}
