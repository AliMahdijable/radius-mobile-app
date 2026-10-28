import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/fiber/fiber_band.dart';
import 'bdcom_epon.dart';
import 'olt_profile.dart';
import 'snmp_client.dart';
import 'vsol_olt_api.dart';

/// طلب GET واحد — `SnmpV2c.get` نفسه في الإنتاج، وأولتٌ وهميّ في الاختبار (فيُثبت الاختبار أنّنا لا نسأل إلّا GET).
typedef HsgqGet = Future<List<Varbind>> Function(List<String> oids);

/// قراءات **أولت HSGQ EPON** — وكلّ أولتٍ يحمل برمجيّته باسمٍ آخر (المالك ٢٨ أكتوبر: «مرات يجي باسم يختلف لكن نفس
/// القوائم والكونفك»). يُعرف بالمؤسّسة `50224` في `sysObjectID` (مسجّلةٌ في IANA لـShenzhen HS Fiber = HSGQ) لا بالاسم،
/// ووصفه «EPON OLT» وحده.
///
/// ثبت كلّه حيّاً ٢٨ أكتوبر على أولت المالك (‏4 PON · 4 GE · 4 XGE، برمجيّة `I_V3.1.20C_Rel`، ‏١٠٠ ONU) بالقراءة وحدها،
/// وطوبق بما يعرضه الجهاز: ١٠٠ ONU بماكاتٍ لا تتكرّر، وضوء الـ٦٩ المتّصلة وحدها، ولا ضوء لمفصولة.
///
/// | ما يُقرأ | المصدر | ملاحظة |
/// |---|---|---|
/// | الـONU وحالتها | `.3.3.2.1.8.<i>` | 1 متّصل · 2 مفصول · غائب = لا ONU في هذا الموضع |
/// | ماكها | `.3.3.2.1.7.<i>` | ستّة بايتات خام |
/// | اسمها | `.3.3.2.1.2.<i>` | الافتراضيّ «ONUpp/nn» لا يتبع الـONU إذا نُقلت — يُهمل |
/// | الصانع / الطراز | `.3.3.2.1.25` / `.26` | «HWTC» / «145C631» |
/// | الضوء | `.3.3.3.1.{4 rx · 5 tx · 7 V · 8 °C}.<i>.0.0` | بوحدة ٠٫٠١، للمتّصل وحده |
/// | المعالج | `.3.1.1.17.0` | ٪ — يتذبذب ٩–١٢ بين قراءاتٍ متتالية |
/// | المنافذ / البرمجيّة | `.3.1.1.8` (PON) و`.11` (الكلّ) / `.3.1.1.6` | |
///
/// (البادئة `1.3.6.1.4.1.50224`، والجداول على تخطيط NSCRTV-EPON-ONU-MIB نفسه تحت مؤسّسةٍ أخرى.) الفهرس `<i>` =
/// ‏`0x01000000 | منفذ<<8 | رقم الـONU` — ‏PON1 · ONU7 ⇒ ‏16777479.
///
/// ⚠️ **ثلاث مصائد، كلٌّ منها تُجمّد لوحةً كاملة** — لذا GET وحده بفهارس نحسبها:
///   ١. **GETBULK/GETNEXT على جدولي الـONU.** مسحٌ يعبر نهاية جدول الضوء يُعلّق الوكيل، وبعدها لا يُجيب أيّ GETBULK
///      على الجدولين (الـGET يبقى يعمل). أيّ أداة مراقبةٍ تمسح الشجرة كلّها توقعه في هذا.
///   ٢. **عدّادات ٦٤ بت (`ifHC*`).** لا تُرفض بل يُهمَل الطلب كلّه حتّى المهلة — ولو كانت معها قيمٌ سليمة.
///   ٣. **صفوف الـONU في IF-MIB.** اسمها خاطئٌ لـ٢٩ من ٦٨ متّصلة (اسم أوّل موضعٍ سُجّلت فيه)، وصفٌّ لـONU مفصولة، وأخرى
///      غائبة، وعدّاداتها أصفار — فلا هويّة منها ولا ترفك لكلّ مشترك.
///
/// وما لا يكشفه: سبب السقوط ولحظته، وأجهزة المشترك خلف الـONU (لا BRIDGE-MIB) — «—» لا تخمين.
class HsgqOlt {
  HsgqOlt._();

  static const ent = '1.3.6.1.4.1.50224.3';

  static const firmwareOid = '$ent.1.1.6.0';
  static const ponCountOid = '$ent.1.1.8.0';
  static const portCountOid = '$ent.1.1.11.0';
  static const cpuOid = '$ent.1.1.17.0';

  static const _onu = '$ent.3.2.1';
  static const _optics = '$ent.3.3.1';

  static String nameOid(int i) => '$_onu.2.$i';
  static String macOid(int i) => '$_onu.7.$i';
  static String statusOid(int i) => '$_onu.8.$i';
  static String vendorOid(int i) => '$_onu.25.$i';
  static String modelOid(int i) => '$_onu.26.$i';
  static String opticsOid(int col, int i) => '$_optics.$col.$i.0.0';

  static const _colRx = 4, _colTx = 5, _colVolt = 7, _colTemp = 8;

  static const _ifDescr = '1.3.6.1.2.1.2.2.1.2';
  static const _ifOper = '1.3.6.1.2.1.2.2.1.8';
  static const _ifHighSpeed = '1.3.6.1.2.1.31.1.1.1.15';

  /// العدّادان ٣٢ بت وحدهما — نسخة ٦٤ بت يُهمَل طلبها كلّه (المصيدة ٢).
  static const _ifIn32 = '1.3.6.1.2.1.2.2.1.10';
  static const _ifOut32 = '1.3.6.1.2.1.2.2.1.16';

  /// كم OID في طلب GET واحد (كـ[BdcomEpon]) — الوكيل يُجيب الستّ عشرة في ~٢٠ مللي.
  static const _perGet = 16;

  /// EPON ‏1:64؛ ومنفذٌ بلغت فيه ONU آخر الـ٦٤ يُسأل حتى ١٢٨ (طرزٌ تقسم أكثر).
  static const _maxOnu = 64;
  static const _wideMaxOnu = 128;

  static int onuIndex(int pon, int onu) => 0x01000000 | (pon << 8) | onu;
  static int ponOf(int index) => (index >> 8) & 0xff;
  static int onuOf(int index) => index & 0xff;

  // ═══════════════════════════════════════════════════════════
  // التحويل — خالصٌ وقابلٌ للاختبار
  // ═══════════════════════════════════════════════════════════

  /// 1 متّصل، وأيّ رقمٍ آخر مفصول (2، و3 «اختبار» في تخطيط NSCRTV)، والغائب `null` = لا ONU في هذا الموضع.
  @visibleForTesting
  static bool? onlineFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    return vb.asInt == 1;
  }

  /// البرمجيّة: بايتاتٌ حتّى أوّل صفر — «I_V3.1.20C_Rel» (الجهاز يحشوها بأصفار إلى ٣٢).
  @visibleForTesting
  static String? firmwareFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || vb.rawTag != 0x04) return null;
    final end = vb.rawBytes.indexOf(0);
    final b = end < 0 ? vb.rawBytes : vb.rawBytes.sublist(0, end);
    final t = String.fromCharCodes(b.where((c) => c >= 0x20 && c < 0x7f)).trim();
    return t.isEmpty ? null : t;
  }

  static double? _centi(Varbind? vb, double lo, double hi) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt / 100.0;
    return (v < lo || v > hi) ? null : v;
  }

  /// الاستقبال عند الـONU بوحدة ٠٫٠١ dBm ‏(‎-1823 ← ‎-18.23) — وما لا يُعقل ضوءاً ([FiberBands.plausible]) `null`.
  @visibleForTesting
  static double? rxFrom(Varbind? vb) {
    final v = _centi(vb, -45, 10);
    return FiberBands.plausible(v) ? v : null;
  }

  @visibleForTesting
  static BdcomOnuReading? readingFrom(Varbind? rx, Varbind? tx, Varbind? volt, Varbind? temp) {
    final r = BdcomOnuReading(
      rxDbm: rxFrom(rx),
      txDbm: _centi(tx, -15, 12),
      voltV: _centi(volt, 2.5, 5.5),
      tempC: _centi(temp, -30, 120),
    );
    return r.isEmpty ? null : r;
  }

  /// اسم الـONU كما كتبه المشغّل، أو `null` للافتراضيّ «ONU01/07»: يُكتب عند أوّل تسجيلٍ ولا يتبع الـONU إذا نُقلت
  /// (‏٤١ من ١٠٠ على أولت المالك تحمل اسم موضعٍ ليست فيه)، فعرضُه بجانب موضعها الحقيقيّ يُضلّل.
  @visibleForTesting
  static String? nameFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || vb.rawTag != 0x04) return null;
    final s = utf8.decode(vb.rawBytes, allowMalformed: true).replaceAll(RegExp(r'[\x00-\x1F\x7F�]'), '').trim();
    if (s.isEmpty || s.length > 64 || _defaultName.hasMatch(s) || _placeholder.hasMatch(s)) return null;
    return s;
  }

  static final _defaultName = RegExp(r'^ONU\s*\d{1,3}\s*[/:._-]\s*\d{1,3}$', caseSensitive: false);
  static final _placeholder = RegExp(r'^(null|none|nil|n/?a|unknown|default|-+|0+)$', caseSensitive: false);

  /// نصٌّ قصيرٌ مطبوع (الصانع «HWTC»، الطراز «145C631») — والفارغ `null`.
  static String? _text(Varbind? vb) {
    if (vb == null || vb.isAbsent || vb.rawTag != 0x04) return null;
    final t = String.fromCharCodes(vb.rawBytes.where((c) => c >= 0x20 && c < 0x7f)).trim();
    return t.isEmpty || t.length > 32 ? null : t;
  }

  static int? _count(Varbind? vb, int max) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt;
    return (v < 1 || v > max) ? null : v;
  }

  /// «PON01» ← منفذ PON ‏1. و«GE01»/«XGE01» ← صعود «GE1»/«XGE1» كما يكتبها جدول المنافذ في الجهاز. وغيرها يُهمل.
  static final _rePon = RegExp(r'^PON0*(\d+)$', caseSensitive: false);
  static final _reUplink = RegExp(r'^(X?GE|10GE|TE|SFP)0*(\d+)$', caseSensitive: false);

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
      final p = _rePon.firstMatch(r.name.trim());
      final u = _reUplink.firstMatch(r.name.trim());
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
          slot: 0,
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
      // ٣٢ بت دائماً هنا: لا نسأل عن ٦٤ أصلاً، ولا تُدفع مهلتها لتُتعلَّم.
      narrowCounters: true,
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
    HsgqGet get,
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
  /// الموضع الفارغ يُجاب «غير موجود» فوراً — مقيس: ٢٥٦ موضعاً في ١٧٠ مللي. `null` = دفعةٌ لم تُجب.
  static Future<Map<int, bool>?> scanOnus(HsgqGet get, int pons, {bool Function()? isCancelled}) async {
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
  static Future<Map<int, bool>?> statusOf(HsgqGet get, Iterable<int> idx, {bool Function()? isCancelled}) async {
    final want = idx.toSet().toList()..sort();
    final got = await _getAll(get, [for (final i in want) statusOid(i)], isCancelled: isCancelled);
    if (got == null) return null;
    return {
      for (final i in want)
        if (onlineFrom(got[statusOid(i)]) != null) i: onlineFrom(got[statusOid(i)])!,
    };
  }

  /// ماك كلّ ONU واسمها المكتوب (لا الافتراضيّ). للمفصولة أيضاً: الماك هويّتها المسجّلة في الجهاز، لا ماكٌ «قديم»
  /// تعلّمه — ١٠٠ ماك مختلفة لمئة موضع على أولت المالك.
  static Future<({Map<int, String> macs, Map<int, String> names})> details(
    HsgqGet get,
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
  static Future<Map<int, String>?> names(HsgqGet get, Iterable<int> idx, {bool Function()? isCancelled}) async {
    final want = idx.toSet().toList()..sort();
    final got = await _getAll(get, [for (final i in want) nameOid(i)], isCancelled: isCancelled);
    if (got == null) return null;
    return {
      for (final i in want)
        if (nameFrom(got[nameOid(i)]) != null) i: nameFrom(got[nameOid(i)])!,
    };
  }

  /// صانع الـONU («HWTC») ورمز طرازها («145C631») — يبقيان للمفصولة من آخر تسجيل، ويغيبان عمّا لم يُسجَّل قطّ.
  static Future<Map<int, BdcomOnuReading>> identities(HsgqGet get, Iterable<int> idx, {bool Function()? isCancelled}) async {
    final want = idx.toSet().toList()..sort();
    final got = await _getAll(get, [for (final i in want) ...[vendorOid(i), modelOid(i)]], isCancelled: isCancelled) ?? const {};
    final out = <int, BdcomOnuReading>{};
    for (final i in want) {
      final r = BdcomOnuReading(vendor: _text(got[vendorOid(i)]), module: _text(got[modelOid(i)]));
      if (!r.isEmpty) out[i] = r;
    }
    return out;
  }

  /// قراءات الضوء للمتّصلة: الاستقبال والإرسال والجهد والحرارة. المفصولة بلا صفٍّ في الجدول أصلاً — فلا تُسأل.
  static Future<Map<int, BdcomOnuReading>> readings(HsgqGet get, Iterable<int> online, {bool Function()? isCancelled}) async {
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
  static Future<Map<int, double>?> rxOnly(HsgqGet get, Iterable<int> online, {bool Function()? isCancelled}) async {
    final want = online.toSet().toList()..sort();
    if (want.isEmpty) return const {};
    final got = await _getAll(get, [for (final i in want) opticsOid(_colRx, i)], isCancelled: isCancelled);
    if (got == null) return null;
    return {
      for (final i in want)
        if (rxFrom(got[opticsOid(_colRx, i)]) != null) i: rxFrom(got[opticsOid(_colRx, i)])!,
    };
  }

  /// المعالج ٪. ما لا يُجاب `null`.
  static Future<BdcomChassis> chassis(HsgqGet get) async {
    final got = await _getAll(get, const [cpuOid]);
    final vb = got?[cpuOid];
    final cpu = (vb == null || vb.isAbsent || !vb.isNumeric || vb.asInt < 0 || vb.asInt > 100) ? null : vb.asInt;
    return BdcomChassis(cpuPct: cpu);
  }

  /// منافذ الجهاز من IF-MIB بالـGET: ‏١..[count] (المنافذ أوّل الجدول — PON ثمّ GE ثمّ XGE، وبعدها صفوف الـONU التي لا
  /// نقرؤها). `null` = لم يُجب.
  static Future<({List<VsolIfRow> rows, DateTime? rxAt, DateTime? txAt})?> ports(
    HsgqGet get,
    int count, {
    bool counters = false,
  }) async {
    final idx = [for (var i = 1; i <= count; i++) i];
    final base = await _getAll(get, [for (final i in idx) ...['$_ifDescr.$i', '$_ifOper.$i', '$_ifHighSpeed.$i']], strict: true);
    if (base == null) return null;
    Map<String, Varbind> inOct = const {}, outOct = const {};
    DateTime? rxAt, txAt;
    if (counters) {
      final a = await _getAll(get, [for (final i in idx) '$_ifIn32.$i']);
      rxAt = a == null ? null : DateTime.now();
      final b = await _getAll(get, [for (final i in idx) '$_ifOut32.$i']);
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
        rxBytes: intOf(inOct, '$_ifIn32.$i'),
        txBytes: intOf(outOct, '$_ifOut32.$i'),
      ));
    }
    return (rows: rows, rxAt: rxAt, txAt: txAt);
  }

  /// لقطةٌ كاملة البنية: المنافذ، ثمّ حالة كلّ ONU، ثمّ ماكها واسمها — ونشرٌ بعد كلّ مرحلة. يرمي [VsolException] لما
  /// يمنع لقطةً صادقة (لا جداول أولت، أو منافذ أو حالةٌ لم تُجب كاملة) فتبقى آخر قراءةٍ صحيحة معروضة.
  static Future<VsolOltStats> fetchStats(
    HsgqGet get, {
    required OltProfile profile,
    String? sysDescr,
    String? sysName,
    Duration? uptime,
    bool withCounters = false,
    void Function(VsolOltStats partial)? onPartialReady,
  }) async {
    final id = await _getAll(get, const [ponCountOid, portCountOid, firmwareOid], strict: true);
    final pons = _count(id?[ponCountOid], 64);
    final count = _count(id?[portCountOid], 256);
    if (id == null || pons == null || count == null) {
      throw VsolException('جهاز HSGQ لا يكشف جداول الأولت — تأكّد أنّه أولت EPON وأنّ SNMP مفعّل للقراءة');
    }
    final fw = firmwareFrom(id[firmwareOid]);
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
    final status = await scanOnus(get, pons);
    if (status == null) throw VsolException('قراءةٌ ناقصة: لم يُجب الأولت بحالة كلّ الـONU');
    onPartialReady?.call(snap(status));
    final d = await details(get, status.keys);
    if (kDebugMode) {
      debugPrint('══════ HSGQ OLT ══════');
      debugPrint('  $descr · pon ${early.ponPorts.length} · onu ${status.length} '
          '(${status.values.where((v) => v).length} متّصل) · ماك ${d.macs.length}');
    }
    return snap(status, macs: d.macs, names: d.names);
  }

  /// الحالة وحدها فوق آخر بنية: كلّ موضعٍ ممكن (فتظهر ONU سُجّلت للتوّ في [unknown] فيُعيد المستدعي البنية) وحالة
  /// المنافذ. `null` = لم يُجب كاملاً — تبقى آخر قراءةٍ صحيحة.
  static Future<({VsolOltStats stats, int unknown})?> refreshStatus(HsgqGet get, VsolOltStats previous) async {
    var pons = previous.ponPorts.fold<int>(0, (m, p) => math.max(m, p.port));
    if (pons == 0) {
      final id = await _getAll(get, const [ponCountOid], strict: true);
      pons = _count(id?[ponCountOid], 64) ?? 0;
    }
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
