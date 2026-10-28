import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/fiber/fiber_band.dart';
import 'bdcom_epon.dart';
import 'olt_profile.dart';
import 'snmp_client.dart';
import 'vsol_olt_api.dart';

/// طلب GET واحد — `SnmpV2c.get` نفسه في الإنتاج، وأولتٌ وهميّ في الاختبار (فيُثبت الاختبار أنّنا لا نسأل إلّا GET).
typedef CdataGet = Future<List<Varbind>> Function(List<String> oids);

/// قراءات **أولت C-Data EPON** («GEPON OLT»، واجهته «EPON-1U4P»). يُعرف بـ`sysObjectID` = ‏`1.3.6.1.4.1.34592` نفسه
/// (مسجّلةٌ في IANA لـShenzhen C-Data Technology)، ووصفه عامّ.
///
/// ثبت كلّه حيّاً ٢٩ أكتوبر على أولت المالك (‏4 PON · 4 GE، برمجيّة `2.4.05_000(May 17 2018)`، ‏١٦٩ ONU مسجّلة منها
/// ٩١ متّصلة) بالقراءة وحدها، وطوبق بواجهة الجهاز: أعداد كلّ منفذ، والماك، والمسافة، وقيم الضوء الخام نفسها.
///
/// | ما يُقرأ | `…34592.1.3.4.1.1.<عمود>.<slot>.<pon>.<onu>` | ملاحظة |
/// |---|---|---|
/// | الحالة | ‏11 | 3 متّصل · 2 مفصول · غائب = لا ONU في هذا الموضع |
/// | الماك | ‏7 | ستّة بايتات خام |
/// | الاسم | ‏3 | الافتراضيّ «unknown» يُهمل |
/// | الصانع / الطراز | ‏41 / ‏2 | أربعة حروفٍ مرصوصة في عدد: 0x48575443 = «HWTC» — صفرٌ للمفصولة غالباً |
/// | الضوء | ‏36 rx · 37 tx · 38 جهد · 40 حرارة | rx/tx بوحدة ٠٫١ ميكروواط: dBm = 10·log₁₀(خام) − 40 (كما تحسبها واجهته)؛ الجهد ×100 ميكروفولت؛ الحرارة ÷256؛ أصفارٌ للمفصولة |
/// | المسافة | ‏13 | متر (لا تُعرض بعد) |
///
/// والمنافذ من IF-MIB بأسماء «EPON System, PON-1» و«EPON System, GE-1» — ثمانية صفوفٍ وحدها، لا صفوف ONU. عدّادات ٦٤ بت
/// تعمل (بخلاف HSGQ) وتتحدّث كلّ ~٤ ثوانٍ ([OltProfile.countersRefresh]).
///
/// ⚠️ **GET وحده بفهارس نحسبها** كـ[HsgqOlt]: GETNEXT بعد نهاية شجرة الـONU لم يُجب حتى المهلة (مرّتين). و⛔ لا يُسأل
/// الفرع `…34592.1.3.1.2` أبداً: فيه عنوان الإدارة **وكلمتا SNMP للقراءة والكتابة** نصّاً. و⛔ لا عمود 4: سؤاله لأكثر من
/// أربع ONU مفصولة في طلبٍ واحد يُسقط الردّ كلّه (مقيس: ٤ ⇒ ٠٫٢ث، ٨ ⇒ لا ردّ ولو بعد ٦ث) — في التشغيل الحيّ الأوّل فات
/// ٤٣ ماكاً وطالت المرحلة ٤٤ث بسببه.
///
/// وما لا يكشفه: المعالج والذاكرة (قيمٌ بلا تسمية — «—» لا تخمين)، سبب السقوط، وأجهزة المشترك خلف الـONU.
class CdataOlt {
  CdataOlt._();

  static const ent = '1.3.6.1.4.1.34592.1.3';

  static const serialOid = '$ent.1.3.2.0';
  static const firmwareOid = '$ent.1.3.3.0';
  static const ifNumberOid = '1.3.6.1.2.1.2.1.0';

  static const _onu = '$ent.4.1.1';

  static const _colModel = 2, _colName = 3, _colMac = 7, _colStatus = 11;
  static const _colRx = 36, _colTx = 37, _colVolt = 38, _colTemp = 40, _colVendor = 41;

  /// الحالة «متّصل» في عمود 11 (والمفصولة 2).
  static const _online = 3;

  static const _ifDescr = '1.3.6.1.2.1.2.2.1.2';
  static const _ifOper = '1.3.6.1.2.1.2.2.1.8';
  static const _ifHighSpeed = '1.3.6.1.2.1.31.1.1.1.15';
  static const _ifHCIn = '1.3.6.1.2.1.31.1.1.1.6';
  static const _ifHCOut = '1.3.6.1.2.1.31.1.1.1.10';

  /// كم OID في طلب GET واحد (كـ[HsgqOlt]).
  static const _perGet = 16;

  /// EPON ‏1:64 (واجهته تعرض ٦٤ موضعاً لكلّ منفذ)؛ ومنفذٌ بلغت فيه ONU آخر الـ٦٤ يُسأل حتى ١٢٨.
  static const _maxOnu = 64;
  static const _wideMaxOnu = 128;

  /// الأولت ذو اللوحة الواحدة: كلّ الصفوف تحت slot ‏1.
  static const _slot = 1;

  /// فهرسٌ محسوب لا يلتقي بفهارس IF-MIB (‏١..٨ هنا): ‏`0x01000000 | slot<<16 | pon<<8 | onu` — ‏PON1 · ONU22 ⇒ ‏16843030.
  static int onuIndex(int pon, int onu, {int slot = _slot}) => 0x01000000 | (slot << 16) | (pon << 8) | onu;
  static int slotOf(int index) => (index >> 16) & 0xff;
  static int ponOf(int index) => (index >> 8) & 0xff;
  static int onuOf(int index) => index & 0xff;

  static String _row(int i) => '${slotOf(i)}.${ponOf(i)}.${onuOf(i)}';
  static String colOid(int col, int i) => '$_onu.$col.${_row(i)}';
  static String statusOid(int i) => colOid(_colStatus, i);
  static String macOid(int i) => colOid(_colMac, i);
  static String nameOid(int i) => colOid(_colName, i);
  static String vendorOid(int i) => colOid(_colVendor, i);
  static String modelOid(int i) => colOid(_colModel, i);
  static String opticsOid(int col, int i) => colOid(col, i);

  // ═══════════════════════════════════════════════════════════
  // التحويل — خالصٌ وقابلٌ للاختبار
  // ═══════════════════════════════════════════════════════════

  /// 3 متّصل، وأيّ رقمٍ آخر مفصول، والغائب `null` = لا ONU في هذا الموضع.
  @visibleForTesting
  static bool? onlineFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    return vb.asInt == _online;
  }

  /// نصٌّ حتى أوّل صفر، مطبوعٌ وحده — البرمجيّة «2.4.05_000(May 17 2018)» والرقم التسلسليّ (محشوّان بأصفار).
  @visibleForTesting
  static String? textFrom(Varbind? vb, {int max = 64}) {
    if (vb == null || vb.isAbsent || vb.rawTag != 0x04) return null;
    final end = vb.rawBytes.indexOf(0);
    final b = end < 0 ? vb.rawBytes : vb.rawBytes.sublist(0, end);
    final t = String.fromCharCodes(b.where((c) => c >= 0x20 && c < 0x7f)).trim();
    return t.isEmpty || t.length > max ? null : t;
  }

  /// أربعة حروفٍ مرصوصة في عدد (رمز الصانع/الطراز في OAM): 0x48575443 ← «HWTC»، و0x5A544500 ← «ZTE». الصفر وما فيه
  /// حرفٌ غير مطبوع `null` — رمزٌ ثنائيّ لا يُعرض كأنّه اسم.
  @visibleForTesting
  static String? packedText(Varbind? vb) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt & 0xFFFFFFFF;
    if (v == 0) return null;
    final bytes = [for (var s = 24; s >= 0; s -= 8) (v >> s) & 0xff];
    while (bytes.isNotEmpty && bytes.last == 0) {
      bytes.removeLast();
    }
    if (bytes.isEmpty || bytes.any((c) => c < 0x20 || c > 0x7e)) return null;
    final t = String.fromCharCodes(bytes).trim();
    return t.isEmpty ? null : t;
  }

  /// قدرةٌ بوحدة ٠٫١ ميكروواط ← dBm: ‏10·log₁₀(خام) − 40 — ‏289 ⇒ ‎-15.39. الصفر (المفصولة) `null`.
  static double? _uw01ToDbm(Varbind? vb) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt;
    if (v <= 0) return null;
    final d = 10 * math.log(v) / math.ln10 - 40;
    return double.parse(d.toStringAsFixed(2));
  }

  /// الاستقبال عند الـONU — وما لا يُعقل ضوءاً ([FiberBands.plausible]) `null`.
  @visibleForTesting
  static double? rxFrom(Varbind? vb) {
    final v = _uw01ToDbm(vb);
    return FiberBands.plausible(v) ? v : null;
  }

  /// ⚠️ المفصولة أصفارٌ في الأعمدة الأربعة، وصفر الحرارة يُقرأ «0 °C» — فلا حرارة بلا قراءة ضوءٍ أو جهد من الوحدة نفسها.
  @visibleForTesting
  static BdcomOnuReading? readingFrom(Varbind? rx, Varbind? tx, Varbind? volt, Varbind? temp) {
    final rxDbm = rxFrom(rx);
    final txRaw = _uw01ToDbm(tx);
    final txDbm = txRaw == null || txRaw < -15 || txRaw > 12 ? null : txRaw;
    double? voltV, tempC;
    if (volt != null && !volt.isAbsent && volt.isNumeric) {
      final v = volt.asInt / 10000.0;
      if (v >= 2.5 && v <= 5.5) voltV = double.parse(v.toStringAsFixed(3));
    }
    if (rxDbm == null && txDbm == null && voltV == null) return null;
    if (temp != null && !temp.isAbsent && temp.isNumeric) {
      var raw = temp.asInt & 0xFFFF;
      if (raw >= 0x8000) raw -= 0x10000;
      final t = raw / 256.0;
      if (t >= -30 && t <= 120) tempC = double.parse(t.toStringAsFixed(1));
    }
    return BdcomOnuReading(rxDbm: rxDbm, txDbm: txDbm, voltV: voltV, tempC: tempC);
  }

  /// اسم الـONU كما كتبه المشغّل، أو `null` للافتراضيّ («unknown» في كلّ الصفوف على أولت المالك).
  @visibleForTesting
  static String? nameFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || vb.rawTag != 0x04) return null;
    final end = vb.rawBytes.indexOf(0);
    final b = end < 0 ? vb.rawBytes : vb.rawBytes.sublist(0, end);
    final s = utf8.decode(b, allowMalformed: true).replaceAll(RegExp(r'[\x00-\x1F\x7F�]'), '').trim();
    if (s.isEmpty || s.length > 64 || _defaultName.hasMatch(s) || _placeholder.hasMatch(s)) return null;
    return s;
  }

  static final _defaultName = RegExp(r'^\[?ONU\s*[-_ ]?\s*\d{1,3}(\s*[/:._-]\s*\d{1,3})?\]?$', caseSensitive: false);
  static final _placeholder = RegExp(r'^(null|none|nil|n/?a|unknown|default|-+|0+)$', caseSensitive: false);

  static int? _count(Varbind? vb, int max) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt;
    return (v < 1 || v > max) ? null : v;
  }

  /// «EPON System, PON-1» ← منفذ PON ‏1. و«EPON System, GE-1» ← صعود «GE1». وغيرها يُهمل.
  static final _rePon = RegExp(r'(?:^|[\s,])PON[-_ ]?0*(\d+)$', caseSensitive: false);
  static final _reUplink = RegExp(r'(?:^|[\s,])(X?GE|10GE|TE|SFP)[-_ ]?0*(\d+)$', caseSensitive: false);

  /// يبني اللقطة من قراءاتٍ خام (نقيّ — للاختبار): المنافذ، ثمّ الـONU مرتّبةً وعدّ كلّ منفذ.
  @visibleForTesting
  static VsolOltStats buildStats({
    required OltProfile profile,
    required List<VsolIfRow> ports,
    required Map<int, bool> status,
    Map<int, String> macs = const {},
    Map<int, String> names = const {},
    String? sysDescr,
    String? sysName,
    Duration? uptime,
    DateTime? rxAt,
    DateTime? txAt,
  }) {
    final pons = <VsolPonPort>[];
    final uplinks = <VsolUplink>[];
    final ifNames = <int, String>{};
    for (final r in ports) {
      final name = r.name.trim();
      final p = _rePon.firstMatch(name);
      final u = _reUplink.firstMatch(name);
      if (p != null) {
        pons.add(VsolPonPort(index: r.index, slot: 0, port: int.parse(p.group(1)!), up: r.up, rxBytes: r.rxBytes, txBytes: r.txBytes));
      } else if (u != null) {
        uplinks.add(VsolUplink(
          index: r.index,
          name: '${u.group(1)!.toUpperCase()}${int.parse(u.group(2)!)}',
          up: r.up,
          speedMbps: r.speedMbps,
          rxBytes: r.rxBytes,
          txBytes: r.txBytes,
        ));
      } else {
        continue;
      }
      ifNames[r.index] = r.name;
    }
    final idx = status.keys.toList()..sort();
    final onus = [
      for (final i in idx)
        VsolOnu(
          ifIndex: i,
          // اللوحة الأولى ⇒ «EPON0/…» كما تكتبها بقيّة الأولتات.
          slot: slotOf(i) - 1,
          ponPort: ponOf(i),
          onuId: onuOf(i),
          online: status[i]!,
          mac: macs[i],
          name: names[i],
        ),
    ];
    for (final o in onus) {
      ifNames[o.ifIndex] = o.label;
    }
    pons.sort((a, b) => a.port.compareTo(b.port));
    return VsolOltStats(
      sysDescr: sysDescr,
      sysName: sysName,
      uptime: uptime,
      uplinks: uplinks,
      ponPorts: [
        for (final p in pons)
          p.withCounts(
            onuTotal: onus.where((o) => o.ponPort == p.port).length,
            onuOnline: onus.where((o) => o.ponPort == p.port && o.online).length,
          ),
      ],
      onus: onus,
      rxAt: rxAt,
      txAt: txAt,
      profile: profile,
      ifNames: Map.unmodifiable(ifNames),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // القراءة — GET وحده
  // ═══════════════════════════════════════════════════════════

  /// كلّ [oids] بدفعات GET. [strict]: دفعةٌ لا تُجيب ⇒ `null` للكلّ (قراءةٌ ناقصة لا تُعرض كأنّها كاملة)؛ وإلّا
  /// تُتجاوز وحدها ويُرجع ما أجاب — و`null` إن لم تُجب دفعةٌ واحدة.
  static Future<Map<String, Varbind>?> _getAll(
    CdataGet get,
    List<String> oids, {
    bool strict = false,
    bool Function()? isCancelled,
  }) async {
    final out = <String, Varbind>{};
    var answered = oids.isEmpty;
    for (var s = 0; s < oids.length; s += _perGet) {
      if (isCancelled?.call() == true) return strict ? null : (answered ? out : null);
      final chunk = oids.sublist(s, math.min(s + _perGet, oids.length));
      try {
        for (final vb in await get(chunk)) {
          out[vb.oid] = vb;
        }
        answered = true;
      } catch (_) {
        if (strict) return null;
      }
    }
    return answered ? out : null;
  }

  /// حالة كلّ ONU موجودة (فهرس ← متّصل؟) بسؤال كلّ موضعٍ ممكن: ١..٦٤ لكلّ منفذ، وإلى ١٢٨ لمنفذٍ بلغ آخر الـ٦٤.
  /// الموضع الفارغ يُجاب «غير موجود» فوراً. `null` = دفعةٌ لم تُجب.
  static Future<Map<int, bool>?> scanOnus(CdataGet get, int pons, {bool Function()? isCancelled}) async {
    Future<Map<int, bool>?> scan(List<int> idx) async {
      final got = await _getAll(get, [for (final i in idx) statusOid(i)], strict: true, isCancelled: isCancelled);
      if (got == null) return null;
      final out = <int, bool>{};
      for (final i in idx) {
        final on = onlineFrom(got[statusOid(i)]);
        if (on != null) out[i] = on;
      }
      return out;
    }

    final out = await scan([
      for (var p = 1; p <= pons; p++)
        for (var o = 1; o <= _maxOnu; o++) onuIndex(p, o),
    ]);
    if (out == null) return null;
    final wide = {for (final i in out.keys) if (onuOf(i) > _maxOnu - 8) ponOf(i)}.toList()..sort();
    if (wide.isNotEmpty) {
      final more = await scan([
        for (final p in wide)
          for (var o = _maxOnu + 1; o <= _wideMaxOnu; o++) onuIndex(p, o),
      ]);
      if (more == null) return null;
      out.addAll(more);
    }
    return out;
  }

  /// حالة ONU بعينها (وضع الفنّي و«التقط بالفصل»): ما أجاب وحده — الغائب لا يُملأ.
  static Future<Map<int, bool>?> statusOf(CdataGet get, Iterable<int> idx, {bool Function()? isCancelled}) async {
    final want = idx.toSet().toList()..sort();
    final got = await _getAll(get, [for (final i in want) statusOid(i)], isCancelled: isCancelled);
    if (got == null) return null;
    return {
      for (final i in want)
        if (onlineFrom(got[statusOid(i)]) != null) i: onlineFrom(got[statusOid(i)])!,
    };
  }

  /// ماك كلّ ONU واسمها المكتوب (لا الافتراضيّ). للمفصولة أيضاً: الماك هويّتها المسجّلة في الجهاز.
  static Future<({Map<int, String> macs, Map<int, String> names})> details(
    CdataGet get,
    Iterable<int> idx, {
    bool Function()? isCancelled,
  }) async {
    final want = idx.toSet().toList()..sort();
    final got = await _getAll(get, [for (final i in want) ...[macOid(i), nameOid(i)]], isCancelled: isCancelled) ?? const {};
    final macs = <int, String>{};
    final names = <int, String>{};
    for (final i in want) {
      final vb = got[macOid(i)];
      final m = (vb == null || vb.isAbsent || vb.rawTag != 0x04) ? null : BdcomEpon.macOfBytes(vb.rawBytes);
      if (m != null) macs[i] = m;
      final n = nameFrom(got[nameOid(i)]);
      if (n != null) names[i] = n;
    }
    return (macs: macs, names: names);
  }

  /// أسماء الـONU المكتوبة وحدها (شبكة الألياف). `null` = لم يُجب.
  static Future<Map<int, String>?> names(CdataGet get, Iterable<int> idx, {bool Function()? isCancelled}) async {
    final want = idx.toSet().toList()..sort();
    final got = await _getAll(get, [for (final i in want) nameOid(i)], isCancelled: isCancelled);
    if (got == null) return null;
    return {
      for (final i in want)
        if (nameFrom(got[nameOid(i)]) != null) i: nameFrom(got[nameOid(i)])!,
    };
  }

  /// صانع الـONU («HWTC») ورمز طرازها حين يكون حروفاً — يغيبان عن المفصولة غالباً (الجهاز يصفّرهما).
  static Future<Map<int, BdcomOnuReading>> identities(CdataGet get, Iterable<int> idx, {bool Function()? isCancelled}) async {
    final want = idx.toSet().toList()..sort();
    final got = await _getAll(get, [for (final i in want) ...[vendorOid(i), modelOid(i)]], isCancelled: isCancelled) ?? const {};
    final out = <int, BdcomOnuReading>{};
    for (final i in want) {
      final r = BdcomOnuReading(vendor: packedText(got[vendorOid(i)]), module: packedText(got[modelOid(i)]));
      if (!r.isEmpty) out[i] = r;
    }
    return out;
  }

  /// قراءات الضوء للمتّصلة: الاستقبال والإرسال والجهد والحرارة. المفصولة أصفار — فلا تُسأل.
  static Future<Map<int, BdcomOnuReading>> readings(CdataGet get, Iterable<int> online, {bool Function()? isCancelled}) async {
    final want = online.toSet().toList()..sort();
    const cols = [_colRx, _colTx, _colVolt, _colTemp];
    final got = await _getAll(get, [for (final i in want) for (final c in cols) opticsOid(c, i)], isCancelled: isCancelled) ??
        const {};
    final out = <int, BdcomOnuReading>{};
    for (final i in want) {
      final r = readingFrom(got[opticsOid(_colRx, i)], got[opticsOid(_colTx, i)], got[opticsOid(_colVolt, i)],
          got[opticsOid(_colTemp, i)]);
      if (r != null) out[i] = r;
    }
    return out;
  }

  /// عمود الاستقبال وحده (شبكة الألياف، كلّ دقيقة). `null` = لم يُجب.
  static Future<Map<int, double>?> rxOnly(CdataGet get, Iterable<int> online, {bool Function()? isCancelled}) async {
    final want = online.toSet().toList()..sort();
    if (want.isEmpty) return const {};
    final got = await _getAll(get, [for (final i in want) opticsOid(_colRx, i)], isCancelled: isCancelled);
    if (got == null) return null;
    return {
      for (final i in want)
        if (rxFrom(got[opticsOid(_colRx, i)]) != null) i: rxFrom(got[opticsOid(_colRx, i)])!,
    };
  }

  /// لا معالج ولا ذاكرة مسمّيان في جداوله — «—» لا تخمين (القيم تحت `.1.3.1.1` بلا تسمية).
  static Future<BdcomChassis> chassis(CdataGet get) async => const BdcomChassis();

  /// منافذ الجهاز من IF-MIB بالـGET: ‏١..[count] (ثمانية على أولت المالك: GE ثمّ PON). `null` = لم يُجب.
  static Future<({List<VsolIfRow> rows, DateTime? rxAt, DateTime? txAt})?> ports(
    CdataGet get,
    int count, {
    bool counters = false,
  }) async {
    final idx = [for (var i = 1; i <= count; i++) i];
    final base = await _getAll(get, [for (final i in idx) ...['$_ifDescr.$i', '$_ifOper.$i', '$_ifHighSpeed.$i']], strict: true);
    if (base == null) return null;
    Map<String, Varbind> inOct = const {}, outOct = const {};
    DateTime? rxAt, txAt;
    if (counters) {
      final a = await _getAll(get, [for (final i in idx) '$_ifHCIn.$i']);
      rxAt = a == null ? null : DateTime.now();
      final b = await _getAll(get, [for (final i in idx) '$_ifHCOut.$i']);
      txAt = b == null ? null : DateTime.now();
      inOct = a ?? const {};
      outOct = b ?? const {};
    }
    int intOf(Map<String, Varbind> m, String oid) {
      final vb = m[oid];
      return (vb == null || vb.isAbsent || !vb.isNumeric) ? 0 : vb.asInt;
    }

    final rows = <VsolIfRow>[];
    for (final i in idx) {
      final d = base['$_ifDescr.$i'];
      if (d == null || d.isAbsent || d.rawTag != 0x04) continue;
      final name = String.fromCharCodes(d.rawBytes.where((c) => c >= 0x20 && c < 0x7f)).trim();
      if (name.isEmpty) continue;
      rows.add(VsolIfRow(
        index: i,
        name: name,
        up: intOf(base, '$_ifOper.$i') == 1,
        mac: null,
        speedMbps: intOf(base, '$_ifHighSpeed.$i'),
        rxBytes: intOf(inOct, '$_ifHCIn.$i'),
        txBytes: intOf(outOct, '$_ifHCOut.$i'),
      ));
    }
    return (rows: rows, rxAt: rxAt, txAt: txAt);
  }

  /// لقطةٌ كاملة البنية: المنافذ، ثمّ حالة كلّ ONU، ثمّ ماكها واسمها — ونشرٌ بعد كلّ مرحلة. يرمي [VsolException] لما
  /// يمنع لقطةً صادقة (لا جداول أولت، أو منافذ أو حالةٌ لم تُجب كاملة) فتبقى آخر قراءةٍ صحيحة معروضة.
  static Future<VsolOltStats> fetchStats(
    CdataGet get, {
    required OltProfile profile,
    String? sysDescr,
    String? sysName,
    Duration? uptime,
    bool withCounters = false,
    void Function(VsolOltStats partial)? onPartialReady,
  }) async {
    final id = await _getAll(get, const [ifNumberOid, firmwareOid], strict: true);
    final count = _count(id?[ifNumberOid], 64);
    if (id == null || count == null) {
      throw VsolException('جهاز C-Data لا يكشف جدول المنافذ — تأكّد أنّه أولت EPON وأنّ SNMP مفعّل للقراءة');
    }
    final fw = textFrom(id[firmwareOid]);
    final descr = [
      if (sysDescr != null && sysDescr.trim().isNotEmpty) sysDescr.trim(),
      if (fw != null) fw,
    ].join(' · ');
    final pr = await ports(get, count, counters: withCounters);
    if (pr == null) throw VsolException('تعذّرت قراءة منافذ الأولت — لم يُجب الجهاز');
    VsolOltStats snap(Map<int, bool> status, {Map<int, String> macs = const {}, Map<int, String> names = const {}}) =>
        buildStats(
          profile: profile,
          ports: pr.rows,
          status: status,
          macs: macs,
          names: names,
          sysDescr: descr.isEmpty ? null : descr,
          sysName: sysName,
          uptime: uptime,
          rxAt: pr.rxAt,
          txAt: pr.txAt,
        );
    final early = snap(const {});
    if (early.ponPorts.isEmpty) throw VsolException('قراءةٌ ناقصة: لم تظهر منافذ PON في جدول الواجهات');
    onPartialReady?.call(early);
    final pons = early.ponPorts.fold<int>(0, (m, p) => math.max(m, p.port));
    final status = await scanOnus(get, pons);
    if (status == null) throw VsolException('قراءةٌ ناقصة: لم يُجب الأولت بحالة كلّ الـONU');
    onPartialReady?.call(snap(status));
    final d = await details(get, status.keys);
    if (kDebugMode) {
      debugPrint('══════ C-Data OLT ══════');
      debugPrint('  $descr · pon ${early.ponPorts.length} · onu ${status.length} '
          '(${status.values.where((v) => v).length} متّصل) · ماك ${d.macs.length}');
    }
    return snap(status, macs: d.macs, names: d.names);
  }

  /// الحالة وحدها فوق آخر بنية: كلّ موضعٍ ممكن (فتظهر ONU سُجّلت للتوّ في [unknown] فيُعيد المستدعي البنية) وحالة
  /// المنافذ. `null` = لم يُجب كاملاً — تبقى آخر قراءةٍ صحيحة.
  static Future<({VsolOltStats stats, int unknown})?> refreshStatus(CdataGet get, VsolOltStats previous) async {
    final pons = previous.ponPorts.fold<int>(0, (m, p) => math.max(m, p.port));
    if (pons == 0) return null;
    final status = await scanOnus(get, pons);
    if (status == null) return null;
    final oper = <int, bool>{...status};
    final portIdx = [for (final p in previous.ponPorts) p.index, for (final u in previous.uplinks) u.index];
    if (portIdx.isNotEmpty) {
      final got = await _getAll(get, [for (final i in portIdx) '$_ifOper.$i'], strict: true);
      if (got == null) return null;
      for (final i in portIdx) {
        final vb = got['$_ifOper.$i'];
        if (vb != null && !vb.isAbsent && vb.isNumeric) oper[i] = vb.asInt == 1;
      }
    }
    return VsolOltApi.applyStatus(previous, oper);
  }
}
