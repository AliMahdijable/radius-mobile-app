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
  // النوع والوحدة غير مقروءين حاليّاً — نكتفي بـSize/Used ونفترض
  // وحدة البايت. يبقيان لاكتمال صفّ الـMIB وللاستعمال عند دعم
  // أقراص بوحدات مختلفة.
  // ignore: unused_field
  static const String _oidHrStorageType = '1.3.6.1.2.1.25.2.3.1.2';
  static const String _oidHrStorageDescr = '1.3.6.1.2.1.25.2.3.1.3';
  // ignore: unused_field
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

  // ═══ جسور airMetro — جداول روجي الخاصّة ═══
  //
  // اكتُشفت بالمسح على AIRMETRO460G فعليّ (٢٠٢٦-٠٩-٢٨) لا من توثيق:
  // روجي لا تنشر MIB لهذه العائلة. والأعمدة سُمّيت بمطابقة القيم
  // بما تعرضه واجهة الجهاز نفسها في اللحظة نفسها.
  //
  //   2.1.1  = دور الجهاز («ap» / «cpe»)
  //   2.2.x  = جدول الطرف المقابل: MAC · تسلسليّ · IP · مُصنّع · طراز
  //   2.3.x  = جدول الارتباط اللاسلكيّ: انظر الثوابت أدناه
  static const String _oidRjBridgeRole = '$_enterprise.1.1.10.2.195.1.1.0';
  static const String _oidRjPeer = '$_enterprise.1.1.10.2.195.2.2.1';
  static const String _oidRjLink = '$_enterprise.1.1.10.2.195.2.3.1';

  // أعمدة جدول الطرف المقابل
  static const int _peerSerial = 2, _peerIp = 3, _peerVendor = 4, _peerModel = 5;

  // أعمدة جدول الارتباط — المحسومة بالمطابقة
  static const int _linkBand = 3; // «5G»
  static const int _linkSsid = 4; // اسم شبكة الجسر
  static const int _linkNoise = 6; // dBm
  static const int _linkSignal = 7; // dBm
  static const int _linkActive = 8; // ثوانٍ منذ قيام الارتباط
  static const int _linkRxRate = 9; // ميجابت/ث
  static const int _linkChannel = 14; // قناة التحكّم
  static const int _linkFreq = 16; // تردّد التحكّم MHz
  // والمرجَّحة — تُعرَض بأسمائها الحذرة حتّى تُثبَّت بمطابقةٍ ثانية:
  // 🐛 ظننتُها «القناة المركزيّة» فقرأتُها 156، ثمّ صارت 468 بعد ساعة
  // — والقنوات لا تتغيّر. فهي معدّلٌ يرافق `.9`، والأرجح أنّه اتّجاه
  // الإرسال. أُبقيها باسمٍ محايدٍ حتّى تُثبَّت بمطابقةٍ لحظيّة، ولا
  // أعرضها بعنوانٍ قد يكذب على المشغّل.
  static const int _linkRateB = 10;
  static const int _linkFlowA = 11;
  static const int _linkFlowB = 12;
  static const int _linkDistance = 13; // متر (مرجَّح)
  static const int _linkCenterFreq = 15;

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
      // كلّها عبر `_walkSafe`: أيّ مسحٍ يرمي كان يُسقط الكتلة بأسرها
      // فتصير المنافذ صفراً — وهو ما رأيناه على airMetro.
      final descrs = await _walkSafe(snmp, _oidIfDescr);
      final ops = await _walkSafe(snmp, _oidIfOperStatus);
      final speeds = await _walkSafe(snmp, _oidIfSpeed);
      // 🐛 ٢٠٢٦-٠٩-٢٨ — المسح كان يرجع فارغاً دائماً فلا يظهر ترفك.
      // السبب أنّ منفذاً **واحداً** (‏LAN1 على airMetro) يردّ `genError`
      // على عدّاداته، والمسح يتوقّف عند أوّل خطأ فيُسقط المنافذ كلّها
      // — ومنها `br-wan` الذي يحمل الترفك الحقيقيّ. نفس المصيدة التي
      // أوقعت `snmpwalk` في سطر الأوامر.
      //
      // الحلّ: نحاول المسح، وإن رجع ناقصاً نسأل كلّ منفذٍ وحده
      // ونتجاوز من يفشل. منفذٌ بلا عدّاد أهون من لوحةٍ بلا ترفك.
      var inOctets = await _walkSafe(snmp, _oidIfHCInOctets);
      var outOctets = await _walkSafe(snmp, _oidIfHCOutOctets);

      final descrByIdx = _mapByLastIndex(descrs, _oidIfDescr);

      // البديل الفرديّ: حين يسقط مسح العدّادات (منفذٌ واحدٌ يردّ
      // genErr فيُسقط الجدول) نسأل كلّ فهرسٍ وحده ونتجاوز من يفشل.
      // بلا هذا يظهر الترفك صفراً على أجهزةٍ تحمله فعلاً.
      // الحالة والسرعة تسقطان بالسبب نفسه، ومنفذٌ بلا حالةٍ يُعرَض
      // «ساقطاً» وهو يعمل — كذبٌ أسوأ من الفراغ. فنُعمّم البديل.
      var ops2 = ops, speeds2 = speeds;
      Future<List<Varbind>> perIndex(String base) async {
        final out = <Varbind>[];
        for (final idx in descrByIdx.keys) {
          try {
            final r = await snmp.get(['$base.$idx']);
            if (r.isNotEmpty) out.add(r.first);
          } catch (_) {/* هذا المنفذ لا يجيب — نتجاوزه */}
        }
        return out;
      }

      if (ops2.isEmpty) ops2 = await perIndex(_oidIfOperStatus);
      if (speeds2.isEmpty) speeds2 = await perIndex(_oidIfSpeed);
      if (inOctets.isEmpty) inOctets = await perIndex(_oidIfHCInOctets);
      if (outOctets.isEmpty) outOctets = await perIndex(_oidIfHCOutOctets);
      final opsByIdx = _mapByLastIndex(ops2, _oidIfOperStatus);
      final speedByIdx = _mapByLastIndex(speeds2, _oidIfSpeed);
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

    // ═══ Tier 4: الجسر اللاسلكيّ — جداول روجي الخاصّة ═══
    //
    // تُقرأ أخيراً وبصمت: أغلب أجهزة روجي ليست جسوراً، وغيابها ليس
    // عطلاً. ومن لا يدعمها يمرّ بلا تأخيرٍ يُذكَر لأنّ الجدول صغير.
    RuijieWirelessLink? link;
    RuijiePeer? peer;
    String? role;
    try {
      final linkCols = await _readRjTable(snmp, _oidRjLink);
      if (linkCols.isNotEmpty) {
        int? n(int c) => linkCols[c]?.asInt;
        String? t(int c) {
          final v = linkCols[c]?.asString.trim();
          return (v == null || v.isEmpty) ? null : v;
        }

        link = RuijieWirelessLink(
          ssid: t(_linkSsid),
          band: t(_linkBand),
          signalDbm: n(_linkSignal),
          noiseDbm: n(_linkNoise),
          activeSeconds: n(_linkActive),
          rxRateMbps: n(_linkRxRate),
          channel: n(_linkChannel),
          freqMhz: n(_linkFreq),
          txRateMbps: n(_linkRateB),
          centerFreqMhz: n(_linkCenterFreq),
          distanceM: n(_linkDistance),
          flowA: n(_linkFlowA),
          flowB: n(_linkFlowB),
        );

        final peerCols = await _readRjTable(snmp, _oidRjPeer);
        if (peerCols.isNotEmpty) {
          String? pt(int c) {
            final v = peerCols[c]?.asString.trim();
            return (v == null || v.isEmpty) ? null : v;
          }

          peer = RuijiePeer(
            serial: pt(_peerSerial),
            ip: pt(_peerIp),
            vendor: pt(_peerVendor),
            model: pt(_peerModel),
          );
        }
        try {
          role = (await snmp.get([_oidRjBridgeRole])).first.asString.trim();
        } catch (_) {}
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Ruijie bridge tables: $e');
    }

    if (kDebugMode) {
      debugPrint('  link:     ${link?.ssid} ${link?.signalDbm}dBm '
          'SNR ${link?.snrDb} · peer ${peer?.ip}');
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
      link: link,
      peer: peer,
      bridgeRole: role,
    );
  }

  /// مسحٌ يتحمّل الأخطاء الجزئيّة.
  ///
  /// `walk` القياسيّ يتوقّف عند أوّل `genError` فيُضيّع ما بعده. وأجهزة
  /// روجي تردّ بذلك على أعمدةٍ بعينها دون غيرها، فالتوقّف يعني خسارة
  /// كلّ شيء بسبب صفٍّ واحد.
  static Future<List<Varbind>> _walkSafe(SnmpV2c snmp, String base) async {
    try {
      final r = await snmp.walk(base, chunkSize: 20);
      if (r.isNotEmpty) return r;
    } catch (_) {/* نهبط إلى الاستعلام الفرديّ */}
    return const [];
  }

  /// يقرأ جدولاً خاصّاً بروجي ويُعيده مفهرساً بالعمود.
  ///
  /// مفتاح الصفّ هنا **عنوان MAC** لا رقماً، فلا يصلح `_mapByLastIndex`
  /// الذي يقرأ أوّل جزءٍ بعد الأساس.
  static Future<Map<int, Varbind>> _readRjTable(
      SnmpV2c snmp, String base) async {
    final out = <int, Varbind>{};
    try {
      for (final vb in await snmp.walk(base, chunkSize: 16)) {
        if (!vb.oid.startsWith('$base.')) continue;
        final rest = vb.oid.substring(base.length + 1);
        final col = int.tryParse(rest.split('.').first);
        if (col != null) out.putIfAbsent(col, () => vb);
      }
    } catch (_) {/* الجهاز لا يدعم الجدول — ليس جسراً */}
    return out;
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

/// الطرف المقابل في جسرٍ لاسلكيّ.
class RuijiePeer {
  const RuijiePeer({this.mac, this.serial, this.ip, this.vendor, this.model});
  final String? mac, serial, ip, vendor, model;
  bool get isEmpty => (ip ?? mac ?? model) == null;
}

/// حالة الارتباط اللاسلكيّ.
///
/// ⚠️ **هذه القيم قد تكون قديمة.** فيرموير airMetro يُحدّث جدوله
/// الخاصّ على فتراتٍ متباعدة — رصدتُه ثابتاً عشر دقائق كاملة بينما
/// `sysUpTime` القياسيّ يتقدّم لحظيّاً. ولذلك يحمل النموذج
/// [activeSeconds] عمداً: تكراره بين قراءتين يعني أنّ الجهاز لم
/// يُحدّث قياسه، وواجب اللوحة أن تقول ذلك لا أن تعرضه كأنّه لحظيّ.
class RuijieWirelessLink {
  const RuijieWirelessLink({
    this.ssid,
    this.band,
    this.signalDbm,
    this.noiseDbm,
    this.activeSeconds,
    this.rxRateMbps,
    this.channel,
    this.freqMhz,
    this.txRateMbps,
    this.centerFreqMhz,
    this.distanceM,
    this.flowA,
    this.flowB,
  });

  final String? ssid, band;
  final int? signalDbm, noiseDbm, activeSeconds, rxRateMbps;
  final int? channel, freqMhz, txRateMbps, centerFreqMhz, distanceM;
  final int? flowA, flowB;

  /// نسبة الإشارة إلى الضجيج — المقياس الذي يقرّر جودة الوصلة فعلاً،
  /// لا الإشارة وحدها: ‏−44 مع ضجيج ‏−50 وصلةٌ سيّئة، ومع ‏−86 ممتازة.
  int? get snrDb => (signalDbm != null && noiseDbm != null)
      ? signalDbm! - noiseDbm!
      : null;

  bool get isEmpty => ssid == null && signalDbm == null;
}

class RuijieStats {
  final String? sysDescr;
  final String? sysName;
  final Duration? uptime;
  final double? cpuPercent;
  final double? memPercent;
  final List<RuijieInterface> ifaces;
  final RuijieWirelessLink? link;
  final RuijiePeer? peer;
  final String? bridgeRole;

  const RuijieStats({
    this.sysDescr,
    this.sysName,
    this.uptime,
    this.cpuPercent,
    this.memPercent,
    this.ifaces = const [],
    this.link,
    this.peer,
    this.bridgeRole,
  });

  /// هل هذا جسرٌ لاسلكيّ — يقرّر أيّ أقسامٍ تُعرَض.
  bool get isBridge => link != null && !link!.isEmpty;

  /// المنفذ الذي يُرسَم منحنى الترفك عليه.
  ///
  /// ⚠️ **منفذٌ واحدٌ لا مجموع.** جمع الواجهات يعدّ البايت الواحد
  /// مرّتين أو ثلاثاً — يدخل من منفذ LAN ويخرج من WAN ويمرّ على
  /// الجسر — فيخرج رقمٌ مضخَّمٌ واتّجاهٌ يُلغي نفسه: ما هو صادرٌ هنا
  /// واردٌ هناك. (بلاغ المستخدم ٢٠٢٦-٠٩-٢٨.)
  ///
  /// الترتيب: `WAN` بالاسم، ثمّ `br-wan` وهو جسر الخروج في فيرموير
  /// Reyee، ثمّ الأثقل بين المنافذ الفيزيائيّة. و`lo` مستبعدٌ لأنّه
  /// حلقةٌ محلّيّة لا تعبر شيئاً، والجسور مستبعدةٌ من جولة «الأثقل»
  /// لأنّها تُظلّل المنافذ التي تحتها.
  RuijieInterface? get uplink {
    if (ifaces.isEmpty) return null;
    final byName = <String, RuijieInterface>{
      for (final i in ifaces) i.name.toLowerCase(): i,
    };
    for (final k in const ['wan', 'br-wan']) {
      final hit = byName[k];
      if (hit != null) return hit;
    }
    RuijieInterface? best;
    for (final i in ifaces) {
      final n = i.name.toLowerCase();
      if (n == 'lo' || n.startsWith('br-')) continue;
      if (best == null || i.rxBytes + i.txBytes > best.rxBytes + best.txBytes) {
        best = i;
      }
    }
    return best;
  }

  /// هل المنفذ المختار منفذ صعودٍ حقيقيّ — يقرّر تسمية الاتّجاهين.
  bool get uplinkIsWan {
    final u = uplink;
    return u != null && const ['wan', 'br-wan'].contains(u.name.toLowerCase());
  }

  factory RuijieStats.fromResults(
    Map<String, Varbind> r, {
    double? cpuPercent,
    double? memPercent,
    required List<RuijieInterface> ifaces,
    RuijieWirelessLink? link,
    RuijiePeer? peer,
    String? bridgeRole,
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
      link: link,
      peer: peer,
      bridgeRole: bridgeRole,
    );
  }
}

class RuijieException implements Exception {
  final String message;
  RuijieException(this.message);
  @override
  String toString() => 'RuijieException: $message';
}
