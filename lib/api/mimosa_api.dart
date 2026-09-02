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

  /// شجرة بيانات الجهاز — `.enterprise.2.1.2` (mimosaBFive).
  ///
  /// 🐛 عطلٌ صامت منذ بناء دعم ميموزا، كُشف ٢٠٢٦-٠٩-٠٢:
  ///
  /// كانت هنا `.2.1` بمستوىً ناقص، فكلّ استعلام يقع على
  /// `43356.2.1.<مجموعة>` بدل `43356.2.1.2.<مجموعة>`. والأسوأ أنّ
  /// `43356.2.1.1` **فرع الفخّاخ** (mimosaTrapMessage · mimosaOldSpeed
  /// · mimosaNewSpeed) لا بيانات الجهاز — فكنّا نسأل عن إشعاراتٍ
  /// تُرسَل، لا عن قياساتٍ تُقرأ.
  ///
  /// والجهاز يردّ `noSuchObject` على الجميع، وكان العميل يترجمه صفراً
  /// (راجع `Varbind.isAbsent`) — فبدت اللوحة مليئةً بأصفارٍ صادقة.
  ///
  /// المصدر: MIMOSA-NETWORKS-BFIVE-MIB — وطُوبق على مسح جهاز C5c حيّ
  /// (najaf2262) قُورنت قيمُه بلوحته الشبكيّة واحدةً واحدة.
  static const String _bfive = '$_enterprise.2.1.2';

  /// PTMP (A5, A5c, A6, C5, C5c, C5x — Sector APs) — `.enterprise.2.2`.
  /// جدول العملاء المتصلين بالسكتور. LibreNMS MIB reference:
  /// https://github.com/librenms/librenms/blob/master/mibs/mimosa/MIMOSA-NETWORKS-PTMP-MIB
  static const String _ptmp = '$_enterprise.2.2';

  // — Mimosa PTMP Station Table (mimosaPtmpStaTable) —
  //   entry index = MAC as 6 octets في الـsuffix (مثال: .0.15.140.1.2.3)
  //   الأعمدة (columns) داخل mimosaPtmpStaEntry:
  //     1  = mimosaPtmpStaMAC        (index-اختياري لأنّه في الـsuffix أصلاً)
  //     2  = mimosaPtmpStaIPAddress  (string)
  //     3  = mimosaPtmpStaName       (string — hostname/alias)
  //     4  = mimosaPtmpStaHwModel    (string)
  //     5  = mimosaPtmpStaFwVersion  (string)
  //     6  = mimosaPtmpStaRSSI       (int, dBm — قد يكون سالب صريح)
  //     7  = mimosaPtmpStaSNR        (int, dB)
  //     8  = mimosaPtmpStaTxRate     (int, Mbps)
  //     9  = mimosaPtmpStaRxRate     (int, Mbps)
  //     10 = mimosaPtmpStaTxPower    (int, dBm)
  //     11 = mimosaPtmpStaDistance   (int, meters)
  //     12 = mimosaPtmpStaUptime     (int, seconds)
  //     13 = mimosaPtmpStaOnline     (int, 1=online 0=offline)
  // جذر جدول محطّات PtMP. الجدول نفسه **منفَّذ** — `fetchClients()`
  // أدناه تمشي على أعمدته عموداً عموداً. هذا الجذر محفوظ لتحويل
  // مستقبلي إلى walk واحد على الجدول كلّه بدل عشرة: يوفّر تسع دورات
  // GETBULK، لكنّ بعض الـfirmware يرفض المشي على الجذر ويقبل الأعمدة
  // مفردة — فلا يُبدَّل قبل اختبار ميداني.
  //
  // (تصحيح 2026-08-30: التعليق السابق هنا زعم أنّ الجدول «لم يُنفَّذ»
  //  وكان بائتاً منذ 6b9f6d6 — أضلّ مراجعةً كاملة.)
  // ignore: unused_field
  static const String _oidPtmpStaTable = '$_ptmp.2';
  static const String _oidPtmpStaIP = '$_ptmp.2.1.2';
  static const String _oidPtmpStaName = '$_ptmp.2.1.3';
  static const String _oidPtmpStaHw = '$_ptmp.2.1.4';
  static const String _oidPtmpStaFw = '$_ptmp.2.1.5';
  static const String _oidPtmpStaRssi = '$_ptmp.2.1.6';
  static const String _oidPtmpStaSnr = '$_ptmp.2.1.7';
  static const String _oidPtmpStaTxRate = '$_ptmp.2.1.8';
  static const String _oidPtmpStaRxRate = '$_ptmp.2.1.9';
  static const String _oidPtmpStaTxPower = '$_ptmp.2.1.10';
  static const String _oidPtmpStaDist = '$_ptmp.2.1.11';
  static const String _oidPtmpStaUptime = '$_ptmp.2.1.12';
  static const String _oidPtmpStaOnline = '$_ptmp.2.1.13';

  // — Standard MIB-II (works for any SNMP device) —
  /// جذر شجرة ميموزا (رقم المؤسّسة IANA ‎43356).
  static const String _oidMimosaRoot = '1.3.6.1.4.1.43356';
  static const String _oidSysDescr = '1.3.6.1.2.1.1.1.0';
  static const String _oidSysUpTime = '1.3.6.1.2.1.1.3.0';
  static const String _oidSysName = '1.3.6.1.2.1.1.5.0';

  // ── عدّادات المرور (IF-MIB القياسيّ) ──────────────────────────────
  //
  // 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «ترفك لحد هسه ماكو». وما كانت اللوحة تعرضه
  // (٦٥٠/٦٥٠) هو **سعة** الوصلة لا حركتها.
  //
  // ⚠️ ولم أستعمل `mimosaPerfInfo` رغم أنّ الـMIB يسمّيه «معدّل على
  // خمس ثوانٍ»: قيمه على C5c حيّ ١٤٦٧٢٨٣ و٣٥٩٣١٧١ بوحدة «kbps»
  // المذكورة = ١٫٥ و٣٫٦ غيغابت، وسعة الجهاز ٦٥٠ ميغا. فالوحدة ليست ما
  // يقوله المصدر، وعرضُ رقمٍ بوحدةٍ مجهولة أسوأ من عدم عرضه.
  //
  // والأوكتِتات لا لبس فيها: عدّاد تراكميّ بالبايت، والفارق بين
  // لقطتين ÷ الزمن = بت/ثانية. نفس تقنية جدار الأجهزة.
  //
  // نُفضّل عدّادات ٦٤-بت (ifHC*) فعدّاد ٣٢-بت يلتفّ كلّ ٣٤ ثانية على
  // غيغابت — أي بين نبضتين.
  static const String _oidIfName = '1.3.6.1.2.1.31.1.1.1.1';
  static const String _oidIfHcIn = '1.3.6.1.2.1.31.1.1.1.6';
  static const String _oidIfHcOut = '1.3.6.1.2.1.31.1.1.1.10';
  static const String _oidIfIn32 = '1.3.6.1.2.1.2.2.1.10';
  static const String _oidIfOut32 = '1.3.6.1.2.1.2.2.1.16';

  // — Mimosa scalar OIDs (BFIVE) —
  //   mimosaGeneral.1 = mimosaDeviceName          → 2.1.1.1.0
  //   mimosaGeneral.2 = mimosaSerialNumber        → 2.1.1.2.0
  //   mimosaGeneral.3 = mimosaFirmwareVersion     → 2.1.1.3.0
  //   mimosaGeneral.4 = mimosaFirmwareBuildDate   → 2.1.1.4.0
  //   mimosaGeneral.5 = mimosaLastRebootTime      → 2.1.1.5.0
  //   mimosaGeneral.8 = mimosaInternalTemp        → 2.1.1.8.0 (×10 lookup: 42.7°C = 427)
  static const String _oidDeviceName = '$_bfive.1.1.0';
  static const String _oidSerialNumber = '$_bfive.1.2.0';
  static const String _oidFirmwareVersion = '$_bfive.1.3.0';
  static const String _oidInternalTemp = '$_bfive.1.8.0';

  //   mimosaLocInfo.2 = longitude, .3 = latitude, .4 = altitude, .7 = gps sats
  static const String _oidLongitude = '$_bfive.2.2.0';
  static const String _oidLatitude = '$_bfive.2.3.0';
  static const String _oidAltitude = '$_bfive.2.4.0';
  static const String _oidGpsSats = '$_bfive.2.7.0';

  //   mimosaTdmaInfo.1 = wirelessMode, .3 = tdmaMode
  //   mimosaWirelessInfo.1 = SSID · .4 = مدّة الوصلة (TimeTicks)
  static const String _oidSsid = '$_bfive.3.1.0';

  /// مدّة بقاء **الوصلة** قائمةً — بجزء من مئة الثانية.
  ///
  /// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «لنك أب تايم — هنا يكتب الوقت خطأ». اللوحة
  /// كانت تعرض `sysUpTime` (‎1.3.6.1.2.1.1.3.0) وهو عمر **وكيل SNMP**
  /// لا عمر الوصلة. ففي جهاز najaf2262 قال وكيلُه ١٠ دقائق بينما
  /// وصلته قائمة منذ ٩ أيّام.
  ///
  /// والفرق ليس تفصيلاً: من يراقب برجاً يسأل «منذ متى والوصلة ثابتة»،
  /// وإعادةُ تشغيل وكيلٍ تُصفّر الرقم الأوّل ولا تمسّ الثاني.
  ///
  /// تحقّق: مسح الجهاز أعطى ‎78966700 ÷ ١٠٠ = ٧٨٩٦٦٧ ثانية = ٩ي ٠٣س
  /// ٢١د، ولوحته وقتها ٩d 03h 46m — والفارق زمن اللقطتين.
  static const String _oidLinkUptime = '$_bfive.3.4.0';

  static const String _oidWirelessMode = '$_bfive.4.1.0';
  static const String _oidTdmaMode = '$_bfive.4.3.0';

  //   mimosaRfInfo.4 = antennaGain
  //   mimosaRfInfo.5 = totalTxPower
  //   mimosaRfInfo.6 = totalRxPower
  //   mimosaRfInfo.7 = targetRxPower
  static const String _oidAntennaGain = '$_bfive.6.4.0';
  static const String _oidTotalTxPower = '$_bfive.6.5.0';
  static const String _oidTotalRxPower = '$_bfive.6.6.0';
  static const String _oidTargetRxPower = '$_bfive.6.7.0';

  //   mimosaPerfInfo.1 = phyRxRate, .2 = phyTxRate, .3 = perTxRate, .4 = perRxRate
  static const String _oidPhyRxRate = '$_bfive.7.1.0';
  static const String _oidPhyTxRate = '$_bfive.7.2.0';
  static const String _oidPerTxRate = '$_bfive.7.3.0';
  static const String _oidPerRxRate = '$_bfive.7.4.0';

  // — جدول السلاسل (mimosaChainTable) = mimosaRfInfo.1.1.<عمود>.<سلسلة> —
  //
  // 🐛 خطأ ثانٍ مستقلّ عن الجذر: كان الجدول `6.3.1` والأعمدة ٤ و٥ و٦.
  // والحقيقة `6.1.1` والأعمدة ٣ و٤ و٥ — أي **الجدول خطأ والأعمدة
  // منزاحةٌ بواحد**. فحتّى لو صحّ الجذر لقرأنا الضجيج مكان الاستقبال،
  // وSNR مكان الضجيج، والتردّد مكان SNR.
  //
  //   عمود ٢ = قدرة الإرسال (dBm)      [مسح C5c: ٢١ لكلّ سلسلة]
  //   عمود ٣ = قدرة الاستقبال (dBm)    [−٤٥ · واللوحة تقول −٤٣٫١ مجموعاً]
  //   عمود ٤ = أرضيّة الضجيج (dBm)     [−٧٤ · واللوحة −٧٤٫٤]
  //   عمود ٥ = SNR (dB)                [٢٩ · واللوحة ٢٨]
  //   عمود ٦ = التردّد المركزيّ (MHz)   [٦٢٧٥ · واللوحة ٦٢٧٥]
  /// جذور الجداول — تُمشى مرّةً ثمّ تُقسَّم أعمدةً.
  static const String _oidChainTable = '$_bfive.6.1.1';
  static const String _oidStreamTable = '$_bfive.6.2.1';
  static const String _oidChannelTable = '$_bfive.6.3.1';

  static const String _oidChainTxPower = '$_bfive.6.1.1.2';
  static const String _oidChainRxPower = '$_bfive.6.1.1.3'; // GETBULK
  static const String _oidChainRxNoise = '$_bfive.6.1.1.4';
  static const String _oidChainSnr = '$_bfive.6.1.1.5';
  static const String _oidChainFreq = '$_bfive.6.1.1.6';

  // — جدول التدفّقات (mimosaStreamTable) = mimosaRfInfo.2.1.<عمود> —
  //   عمود ٢ = معدّل PHY للإرسال   [٣٢٥ لكلّ تدفّق · واللوحة ٦٥٠ مجموعاً]
  //   عمود ٥ = معدّل PHY للاستقبال [٣٢٥ · واللوحة ٦٥٠]
  static const String _oidStreamTxPhy = '$_bfive.6.2.1.2';
  static const String _oidStreamRxPhy = '$_bfive.6.2.1.5';

  // — جدول القناة (mimosaChannelTable) = mimosaRfInfo.3.1.<عمود> —
  //   عمود ٣ = عرض القناة (MHz) [٨٠ · واللوحة ٨٠]
  static const String _oidChannelWidth = '$_bfive.6.3.1.3';

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
      _oidSysDescr,
      _oidSysName,
      _oidSysUpTime,
      _oidDeviceName,
      _oidSerialNumber,
      _oidFirmwareVersion,
      _oidInternalTemp,
      _oidLongitude,
      _oidLatitude,
      // ⚠️ كان غائباً عن الدفعتين رغم أنّ الـOID معرَّف (:92) ويُقرأ في
      // `fromVarbinds` (:516) ويُعرض في اللوحة — فصفّ «Altitude» لم
      // يُرسم قطّ. عطل صامت: لا خطأ، فقط سطر لا يظهر أبداً.
      _oidAltitude,
      _oidGpsSats,
    ];
    // ═══ Tier 2 (~500ms إضافيّة): RF details ═══
    final scalarBatch2 = <String>[
      _oidSsid,
      _oidLinkUptime,
      _oidWirelessMode,
      _oidTdmaMode,
      _oidAntennaGain,
      _oidTotalTxPower,
      _oidTotalRxPower,
      _oidTargetRxPower,
      _oidPhyRxRate,
      _oidPhyTxRate,
      _oidPerTxRate,
      _oidPerRxRate,
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
              Map<String, Varbind>.from(results),
              chains: const []));
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

    // ⚠️ قيم الجدول تُقرأ **بلا قسمة**.
    //
    // خطأ رابع كُشف ٢٠٢٦-٠٩-٠٢: كان الجدول يمرّ على `_asDbmScaled`
    // فيُقسم على عشرة. لكنّ المقياسة هي **المجاميع وحدها**
    // (‎6.5.0=240 → ٢٤ dBm · ‎6.6.0=−425 → −٤٢٫٥)، أمّا الجدول فيعطي
    // القيمة كما هي (−٤٥ · −٧٤ · ٢٩ — طابقتها لوحة الجهاز). فالقسمة
    // كانت ستُظهر إشارةً بـ‎−٤٫٥ dBm.
    // Chain table via walk (2-4 chains عادة) — Tier 3 (اختياري)
    final chains = <MimosaChain>[];
    int? txPhyTotal;
    int? rxPhyTotal;
    int? channelWidth;
    final counters = <MimosaIfCounter>[];
    try {
      // ⚠️ مشيةٌ واحدة على **جذر الجدول** لا مشيةٌ لكلّ عمود.
      //
      // كانت خمس مشياتٍ للسلاسل واثنتان للتدفّقات وواحدة للقناة = ثمانٍ،
      // كلٌّ منها عدّة جولات UDP. على وصلةٍ زمنها ٢١٣ms صار التحديث
      // ثقيلاً ومتقطّعاً — وأنا من رفع العدد حين أضفتُ الأعمدة.
      //
      // والمشية الواحدة أصدق أيضاً: كلّ الأعمدة من **لقطةٍ واحدة**، لا
      // من ثوانٍ متفرّقة قد يتغيّر الجهاز بينها.
      final chainRows = await snmp.walk(_oidChainTable, chunkSize: 16);
      final txPowers = _column(chainRows, _oidChainTxPower);
      final rxPowers = _column(chainRows, _oidChainRxPower);
      final rxNoises = _column(chainRows, _oidChainRxNoise);
      final snrs = _column(chainRows, _oidChainSnr);
      final freqs = _column(chainRows, _oidChainFreq);
      // معدّلات PHY من **جدول التدفّقات** لا من `mimosaPerfInfo`.
      //
      // الـMIB يسمّي ‎7.1/7.2 «PhyTxRate/PhyRxRate» بوحدة kbps، لكنّ
      // جهاز C5c حيّاً يعيد فيهما ١٤٦٧٢٨٣ و٣٥٩٣١٧١ — أي ١٫٥ و٣٫٦
      // غيغابت، وسعة الجهاز ٦٥٠ ميغا. فهما عدّادان تراكميّان على هذا
      // الإصدار لا معدّلان.
      //
      // وجدول التدفّقات يعطي ٣٢٥ لكلّ تدفّق × ٢ = ٦٥٠ — وهو **بالضبط**
      // ما تعرضه لوحة الجهاز (PHY Tx/Rx 650/650). فالمجموع هو الصادق.
      final streamRows = await snmp.walk(_oidStreamTable, chunkSize: 16);
      txPhyTotal = _sumStream(_column(streamRows, _oidStreamTxPhy));
      rxPhyTotal = _sumStream(_column(streamRows, _oidStreamRxPhy));

      final channelRows = await snmp.walk(_oidChannelTable, chunkSize: 8);

      // عدّادات المرور — ٦٤-بت أوّلاً والسقوط إلى ٣٢-بت عند غيابها.
      var inRows = await snmp.walk(_oidIfHcIn, chunkSize: 16);
      var outRows = await snmp.walk(_oidIfHcOut, chunkSize: 16);
      if (inRows.isEmpty || outRows.isEmpty) {
        inRows = await snmp.walk(_oidIfIn32, chunkSize: 16);
        outRows = await snmp.walk(_oidIfOut32, chunkSize: 16);
      }
      final names = await snmp.walk(_oidIfName, chunkSize: 16);
      final nameByIdx = <int, String>{};
      for (final vb in names) {
        final i = _lastIndex(vb.oid);
        if (i != null && !vb.isAbsent) nameByIdx[i] = vb.asString;
      }
      final inByIdx = <int, int>{};
      for (final vb in inRows) {
        final i = _lastIndex(vb.oid);
        if (i != null && !vb.isAbsent) inByIdx[i] = vb.asInt;
      }
      for (final vb in outRows) {
        final i = _lastIndex(vb.oid);
        if (i == null || vb.isAbsent || !inByIdx.containsKey(i)) continue;
        counters.add(MimosaIfCounter(
          index: i,
          name: nameByIdx[i] ?? 'if$i',
          rxOctets: inByIdx[i]!,
          txOctets: vb.asInt,
        ));
      }
      final widths = _column(channelRows, _oidChannelWidth);
      if (widths.isNotEmpty) channelWidth = widths.first.asInt;

      final indexTxPower = _byIndex(txPowers, _oidChainTxPower);
      final indexRxPower = _byIndex(rxPowers, _oidChainRxPower);
      final indexRxNoise = _byIndex(rxNoises, _oidChainRxNoise);
      final indexSnr = _byIndex(snrs, _oidChainSnr);
      final indexFreq = _byIndex(freqs, _oidChainFreq);

      final allIndices = <int>{
        ...indexTxPower.keys,
        ...indexRxPower.keys,
        ...indexRxNoise.keys,
        ...indexSnr.keys,
      };
      for (final i in allIndices.toList()..sort()) {
        chains.add(MimosaChain(
          index: i,
          txPowerDbm: _asPlain(indexTxPower[i]),
          rxPowerDbm: _asPlain(indexRxPower[i]),
          rxNoiseDbm: _asPlain(indexRxNoise[i]),
          snrDb: _asPlain(indexSnr[i]),
          centerFreqMhz: _asPlain(indexFreq[i])?.round(),
        ));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Mimosa chain walk failed: $e');
    }

    if (kDebugMode) {
      final absent = results.values.where((v) => v.isAbsent).length;
      debugPrint('══════ Mimosa SNMP scalars ══════');
      results.forEach((oid, vb) {
        debugPrint('  $oid: ${vb.asString}');
      });
      debugPrint('  chains: ${chains.length}  |  غائبة: $absent/${results.length}');

      // ── مسح استكشافيّ ────────────────────────────────────────────
      //
      // حين تغيب أغلب OIDs الخاصّة بميموزا، فالشجرة التي تفترضها هذه
      // الشيفرة لا تطابق ما يعرضه هذا الطراز/الإصدار. المسح يطبع ما
      // **يملكه الجهاز فعلاً** بدل أن نُخمّن OIDs واحداً واحداً.
      //
      // ⚠️ في وضع التطوير فقط، ومرّةً حين يكون الغياب أغلبيّاً: المسح
      // عشرات الطلبات على UDP ولا يُحتمل في كلّ نبضة.
      if (absent > results.length ~/ 2) {
        debugPrint('⚠️ أغلب OIDs غائبة — أمسح شجرة ميموزا لاكتشاف الصحيح…');
        try {
          final found = await snmp.walk(_oidMimosaRoot, maxIterations: 10);
          debugPrint('── ما يعرضه الجهاز تحت $_oidMimosaRoot ──');
          if (found.isEmpty) {
            debugPrint('  (فارغة — الجهاز لا يعرض شجرة ميموزا أصلاً)');
          }
          for (final vb in found) {
            debugPrint('  ${vb.oid} = ${vb.asString}');
          }
          debugPrint('── نهاية المسح (${found.length} عنصراً) ──');
        } catch (e) {
          debugPrint('⚠️ فشل المسح الاستكشافيّ: $e');
        }
      }
      debugPrint('════════════════════════════════');
    }

    return MimosaStats.fromVarbinds(
      results,
      chains: chains,
      txPhyMbps: txPhyTotal,
      rxPhyMbps: rxPhyTotal,
      channelWidthMhz: channelWidth,
      counters: counters,
    );
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
  /// جلبٌ خفيف للعدّادات وحدها — بلا RF ولا سلاسل ولا نظام.
  ///
  /// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «الترفك الوحيد يتأخّر — كلّ البيانات تظهر
  /// وهو يأخذ ٣٠ ثانية».
  ///
  /// والسبب حسابيّ لا شبكيّ: المعدّل فارقُ عيّنتين، والنبضة كلّ ١٥
  /// ثانية — فأوّل رقم لا يُولد قبل الثلاثين. وبقيّة القيم مطلقةٌ
  /// تظهر من العيّنة الأولى.
  ///
  /// فالعيّنة الثانية تُؤخذ بعد ثوانٍ قليلة بجلبٍ مقتصر: ثلاث مشيات
  /// بدل عشر، فلا تُثقل ولا تنتظر النبضة.
  static Future<List<MimosaIfCounter>> fetchCounters({
    required String host,
    int port = 161,
    required String community,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final snmp = SnmpV2c(
        host: host, port: port, community: community, timeout: timeout);
    var inRows = await snmp.walk(_oidIfHcIn, chunkSize: 16);
    var outRows = await snmp.walk(_oidIfHcOut, chunkSize: 16);
    if (inRows.isEmpty || outRows.isEmpty) {
      inRows = await snmp.walk(_oidIfIn32, chunkSize: 16);
      outRows = await snmp.walk(_oidIfOut32, chunkSize: 16);
    }
    final inByIdx = <int, int>{};
    for (final vb in inRows) {
      final i = _lastIndex(vb.oid);
      if (i != null && !vb.isAbsent) inByIdx[i] = vb.asInt;
    }
    final out = <MimosaIfCounter>[];
    for (final vb in outRows) {
      final i = _lastIndex(vb.oid);
      if (i == null || vb.isAbsent || !inByIdx.containsKey(i)) continue;
      out.add(MimosaIfCounter(
        index: i,
        name: 'if$i',
        rxOctets: inByIdx[i]!,
        txOctets: vb.asInt,
      ));
    }
    return out;
  }

  /// آخر رقم في الـOID — فهرس الواجهة.
  static int? _lastIndex(String oid) {
    final i = oid.lastIndexOf('.');
    if (i < 0) return null;
    return int.tryParse(oid.substring(i + 1));
  }

  /// يستخرج عموداً من صفوف جدولٍ مُمشيّ.
  ///
  /// الفاصل نقطة صريحة: بلاها يلتقط `.11` مرشّحُ `.1`.
  static List<Varbind> _column(List<Varbind> rows, String columnOid) {
    final prefix = '$columnOid.';
    return [
      for (final vb in rows)
        if (vb.oid.startsWith(prefix) && !vb.isAbsent) vb
    ];
  }

  /// مجموع عمودٍ في جدول التدفّقات — الوصلة تحمل تدفّقين فأكثر،
  /// والمعدّل الكلّيّ مجموعُها لا واحدٌ منها.
  static int? _sumStream(List<Varbind> vbs) {
    var total = 0;
    var seen = false;
    for (final vb in vbs) {
      if (vb.isAbsent) continue;
      total += vb.asInt;
      seen = true;
    }
    return seen ? total : null;
  }

  /// قيمة جدولٍ كما هي — بلا القسمة على عشرة التي تحتاجها المجاميع.
  static double? _asPlain(Varbind? vb) {
    if (vb == null || vb.isAbsent) return null;
    return vb.asInt.toDouble();
  }


  /// جلب قائمة العملاء (Stations) المتصلة بسكتور PtMP.
  ///
  /// يُستعمل لأجهزة Mimosa A5/A6/C5 (السكتورات). أجهزة PtP (B5) ترجع قائمة
  /// فارغة (لا يوجد "clients" في PtP — فقط peer واحد).
  ///
  /// المنطق:
  /// 1. Walk على 6 أعمدة رئيسيّة (IP, name, RSSI, SNR, tx, rx) بالتوازي
  /// 2. الـsuffix بعد كل عمود = MAC كسلسلة أرقام (6 octets)
  /// 3. نجمع الأسطر حسب الـMAC ونبني قائمة MimosaClient
  ///
  /// لو الجهاز لا يدعم PtMP MIB (مثل B5 PtP) → walk يرجع فارغاً → قائمة فارغة.
  /// لا نرمي exception — نعطي [] ونترك الـUI يعرض "لا يوجد عملاء".
  static Future<List<MimosaClient>> fetchClients({
    required String host,
    int port = 161,
    required String community,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final snmp = SnmpV2c(
      host: host,
      port: port,
      community: community,
      timeout: timeout,
    );

    try {
      // 6 أعمدة بالتوازي — كلها walks على نفس الجدول
      final futures = await Future.wait([
        snmp.walk(_oidPtmpStaIP, chunkSize: 20),
        snmp.walk(_oidPtmpStaName, chunkSize: 20),
        snmp.walk(_oidPtmpStaRssi, chunkSize: 20),
        snmp.walk(_oidPtmpStaSnr, chunkSize: 20),
        snmp.walk(_oidPtmpStaTxRate, chunkSize: 20),
        snmp.walk(_oidPtmpStaRxRate, chunkSize: 20),
        snmp.walk(_oidPtmpStaTxPower, chunkSize: 20),
        snmp.walk(_oidPtmpStaDist, chunkSize: 20),
        snmp.walk(_oidPtmpStaUptime, chunkSize: 20),
        snmp.walk(_oidPtmpStaOnline, chunkSize: 20),
        // الطراز والإصدار: عمودان في الجدول نفسه، وكانا معرَّفين
        // وغير مقروءين. يميّزان جهاز العميل حين تتشابه الأسماء.
        snmp.walk(_oidPtmpStaHw, chunkSize: 20),
        snmp.walk(_oidPtmpStaFw, chunkSize: 20),
      ]);

      final ipsBySuffix = _byMacSuffix(futures[0], _oidPtmpStaIP);
      final namesBySuffix = _byMacSuffix(futures[1], _oidPtmpStaName);
      final rssiBySuffix = _byMacSuffix(futures[2], _oidPtmpStaRssi);
      final snrBySuffix = _byMacSuffix(futures[3], _oidPtmpStaSnr);
      final txRateBySuffix = _byMacSuffix(futures[4], _oidPtmpStaTxRate);
      final rxRateBySuffix = _byMacSuffix(futures[5], _oidPtmpStaRxRate);
      final txPowerBySuffix = _byMacSuffix(futures[6], _oidPtmpStaTxPower);
      final distBySuffix = _byMacSuffix(futures[7], _oidPtmpStaDist);
      final uptimeBySuffix = _byMacSuffix(futures[8], _oidPtmpStaUptime);
      final onlineBySuffix = _byMacSuffix(futures[9], _oidPtmpStaOnline);
      final hwBySuffix = _byMacSuffix(futures[10], _oidPtmpStaHw);
      final fwBySuffix = _byMacSuffix(futures[11], _oidPtmpStaFw);

      // كل الـMAC suffixes الي شفناها (union)
      final allSuffixes = <String>{
        ...ipsBySuffix.keys,
        ...namesBySuffix.keys,
        ...rssiBySuffix.keys,
        ...snrBySuffix.keys,
        ...onlineBySuffix.keys,
      };

      final clients = <MimosaClient>[];
      for (final suffix in allSuffixes) {
        clients.add(MimosaClient(
          mac: _suffixToMac(suffix),
          ip: ipsBySuffix[suffix]?.asString,
          name: namesBySuffix[suffix]?.asString,
          rssiDbm: rssiBySuffix[suffix]?.asInt,
          snrDb: snrBySuffix[suffix]?.asInt,
          txRateMbps: txRateBySuffix[suffix]?.asInt,
          rxRateMbps: rxRateBySuffix[suffix]?.asInt,
          txPowerDbm: txPowerBySuffix[suffix]?.asInt,
          distanceMeters: distBySuffix[suffix]?.asInt,
          uptimeSec: uptimeBySuffix[suffix]?.asInt,
          online: (onlineBySuffix[suffix]?.asInt ?? 0) == 1,
          hwModel: hwBySuffix[suffix]?.asString,
          fwVersion: fwBySuffix[suffix]?.asString,
        ));
      }
      // ترتيب: online أوّلاً، ثم بأقوى signal (rssi أقرب للصفر أفضل)
      clients.sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        final ra = a.rssiDbm ?? -999;
        final rb = b.rssiDbm ?? -999;
        return rb.compareTo(ra);
      });
      return clients;
    } on SnmpException catch (_) {
      // الجهاز لا يدعم PtMP MIB — قائمة فارغة بدلاً من exception
      return const [];
    } catch (_) {
      return const [];
    }
  }

  /// يُحوّل suffix رقمي (بعد OID root) لـMAC نصّي "AA:BB:CC:DD:EE:FF".
  /// المثال: "0.15.140.1.2.3" → "00:0F:8C:01:02:03"
  static String _suffixToMac(String suffix) {
    final parts = suffix.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.length < 6) return suffix;
    final macBytes = parts.take(6).map((s) {
      final n = int.tryParse(s) ?? 0;
      return n.toRadixString(16).padLeft(2, '0').toUpperCase();
    }).join(':');
    return macBytes;
  }

  /// يبني map: suffix (بعد الـbase) → Varbind. الـsuffix هو الـMAC كأرقام.
  static Map<String, Varbind> _byMacSuffix(List<Varbind> vbs, String base) {
    final map = <String, Varbind>{};
    for (final vb in vbs) {
      if (vb.oid.length > base.length + 1) {
        map[vb.oid.substring(base.length + 1)] = vb;
      }
    }
    return map;
  }

  /// إعادة تشغيل الجهاز — **غير مدعومة على Mimosa عن بُعد**.
  ///
  /// السبب: SSH مقفول في firmware، وMimosa لا توفّر OID موثّق للـreboot عبر
  /// SNMP SET (اختبرنا 1.3.6.1.4.1.43356.2.1.1.6.0 وأخوته — لا تستجيب).
  ///
  /// الطريقة الوحيدة: web UI مباشرة عبر HTTPS.
  static Future<void> rebootDevice({
    required String host,
    int port = 161,
    required String community,
  }) async {
    throw MimosaException(
      'Reboot لا يُدعم عن بُعد لأجهزة Mimosa. '
      'يجب استعمال web UI: https://$host',
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════

class MimosaStats {
  final String? sysDescr;
  final String? sysName;
  final int sysUptimeSec;

  /// مدّة بقاء الوصلة — `null` إن لم يعرضها الطراز.
  final int? linkUptimeSec;
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
  final int? wirelessMode; // 1=AP, 2=STA (typical)
  final int? tdmaMode;

  // RF summary
  final int? antennaGainDbi;
  final double? totalTxPowerDbm;
  final double? totalRxPowerDbm;
  final double? targetRxPowerDbm;

  // Performance
  final int? phyTxRateMbps;
  final int? phyRxRateMbps;

  /// عرض القناة MHz — من `mimosaChannelTable`.
  final int? channelWidthMhz;

  /// اسم الوصلة اللاسلكيّة — كان يُجلَب ولا يُقرأ.
  final String? ssid;

  /// عدّادات الواجهات — تُطرح منها لقطةُ الجولة التالية.
  final List<MimosaIfCounter> counters;
  final double? perTxRatePct; // packet error rate %
  final double? perRxRatePct;

  final List<MimosaChain> chains;

  const MimosaStats({
    this.sysDescr,
    this.sysName,
    this.sysUptimeSec = 0,
    this.linkUptimeSec,
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
    this.channelWidthMhz,
    this.ssid,
    this.counters = const [],
    this.perTxRatePct,
    this.perRxRatePct,
    this.chains = const [],
  });

  bool get hasGps =>
      latitude != null && longitude != null && latitude != 0 && longitude != 0;

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
  /// TimeTicks (جزء من مئة الثانية) → ثوانٍ. صفرٌ للغائب.
  static int _parseUptime(Varbind? vb) {
    if (vb == null || vb.isAbsent) return 0;
    return vb.asInt ~/ 100;
  }

  factory MimosaStats.fromVarbinds(
    Map<String, Varbind> m, {
    List<MimosaChain> chains = const [],
    int? txPhyMbps,
    int? rxPhyMbps,
    int? channelWidthMhz,
    List<MimosaIfCounter> counters = const [],
  }) {
    Varbind? g(String oid) => m[oid];
    double? n10(String oid) {
      final vb = m[oid];
      // ⚠️ الغياب ≠ الصفر: `asInt` كان يعيد صفراً لوسم «غير موجود»،
      // فيُخفى الفرق بين «الجهاز لا يدعمه» و«القيمة صفر».
      if (vb == null || vb.isAbsent) return null;
      final v = vb.asInt;
      return v == 0 ? null : v / 10.0;
    }

    int? n(String oid) {
      final vb = m[oid];
      if (vb == null) return null;
      final v = vb.asInt;
      return v == 0 ? null : v;
    }

    String? s(String oid) {
      final vb = m[oid];
      if (vb == null) return null;
      final s = vb.asString.trim();
      return s.isEmpty ? null : s;
    }

    double? gps(String oid) {
      // Mimosa GPS often stored as int × 1e7 (LibreNMS uses / 1e7)
      final vb = m[oid];
      if (vb == null) return null;
      final v = vb.asInt;
      if (v == 0) return null;
      return v / 10000000.0;
    }

    return MimosaStats(
      sysDescr: s(MimosaApi._oidSysDescr),
      sysName: s(MimosaApi._oidSysName),
      sysUptimeSec: _parseUptime(g(MimosaApi._oidSysUpTime)),
      linkUptimeSec: _parseUptime(g(MimosaApi._oidLinkUptime)) == 0
          ? null
          : _parseUptime(g(MimosaApi._oidLinkUptime)),
      deviceName: s(MimosaApi._oidDeviceName),
      serialNumber: s(MimosaApi._oidSerialNumber),
      firmwareVersion: s(MimosaApi._oidFirmwareVersion),
      temperatureC: n10(MimosaApi._oidInternalTemp),
      latitude: gps(MimosaApi._oidLatitude),
      longitude: gps(MimosaApi._oidLongitude),
      altitude: n(MimosaApi._oidAltitude),
      gpsSats: n(MimosaApi._oidGpsSats),
      wirelessMode: n(MimosaApi._oidWirelessMode),
      tdmaMode: n(MimosaApi._oidTdmaMode),
      antennaGainDbi: n(MimosaApi._oidAntennaGain),
      totalTxPowerDbm: n10(MimosaApi._oidTotalTxPower),
      totalRxPowerDbm: n10(MimosaApi._oidTotalRxPower),
      targetRxPowerDbm: n10(MimosaApi._oidTargetRxPower),
      // من جدول التدفّقات — راجع التعليق في `fetchStats`. ونسقط إلى
      // `mimosaPerfInfo` فقط إن غاب الجدول كلّيّاً.
      phyTxRateMbps: txPhyMbps ?? n(MimosaApi._oidPhyTxRate),
      phyRxRateMbps: rxPhyMbps ?? n(MimosaApi._oidPhyRxRate),
      channelWidthMhz: channelWidthMhz,
      counters: counters,
      ssid: g(MimosaApi._oidSsid)?.isAbsent == false
          ? g(MimosaApi._oidSsid)!.asString
          : null,
      perTxRatePct: n10(MimosaApi._oidPerTxRate),
      perRxRatePct: n10(MimosaApi._oidPerRxRate),
      chains: chains,
    );
  }
}

/// عدّاد أوكتِتات واجهة — أساس حساب المرور الفعليّ.
///
/// عدّادٌ تراكميّ بالبايت، والفارق بين لقطتين ÷ الزمن = بت/ثانية.
class MimosaIfCounter {
  const MimosaIfCounter({
    required this.index,
    required this.name,
    required this.rxOctets,
    required this.txOctets,
  });

  final int index;
  final String name;
  final int rxOctets;
  final int txOctets;
}

class MimosaChain {
  final int index; // 1..N
  final double? txPowerDbm;
  final double? rxPowerDbm;
  final double? rxNoiseDbm;
  final double? snrDb;
  final int? centerFreqMhz;

  const MimosaChain({
    required this.index,
    this.txPowerDbm,
    this.rxPowerDbm,
    this.rxNoiseDbm,
    this.snrDb,
    this.centerFreqMhz,
  });
}

class MimosaException implements Exception {
  final String message;
  MimosaException(this.message);
  @override
  String toString() => message;
}

/// عميل PtMP مُتصل بسكتور Mimosa (A5/A6/C5).
/// كل الحقول nullable لأنّ MIB implementation يختلف بين firmware versions —
/// الـUI يعرض ما هو متوفّر فقط.
class MimosaClient {
  final String mac;
  final String? ip;
  final String? name;
  final int? rssiDbm; // dBm — أقرب للصفر أفضل (-40 ممتاز، -80 ضعيف)
  final int? snrDb; // dB — أعلى أفضل (35+ ممتاز، 15- سيئ)
  final int? txRateMbps; // معدّل الإرسال من الجهاز للعميل
  final int? rxRateMbps; // معدّل الاستقبال من العميل
  final int? txPowerDbm;
  final int? distanceMeters;
  final int? uptimeSec;
  final bool online;

  /// طراز جهاز العميل وإصداره — يميّزانه حين تتشابه الأسماء.
  final String? hwModel;
  final String? fwVersion;

  const MimosaClient({
    required this.mac,
    this.ip,
    this.name,
    this.rssiDbm,
    this.snrDb,
    this.txRateMbps,
    this.rxRateMbps,
    this.txPowerDbm,
    this.distanceMeters,
    this.uptimeSec,
    required this.online,
      this.hwModel,
    this.fwVersion,
  });

  /// تصنيف جودة الـsignal حسب RSSI:
  /// - ممتاز: >= -50
  /// - جيّد: -50 .. -65
  /// - متوسط: -65 .. -75
  /// - ضعيف: < -75
  String get signalQuality {
    final r = rssiDbm;
    if (r == null) return 'unknown';
    if (r >= -50) return 'excellent';
    if (r >= -65) return 'good';
    if (r >= -75) return 'fair';
    return 'poor';
  }
}
