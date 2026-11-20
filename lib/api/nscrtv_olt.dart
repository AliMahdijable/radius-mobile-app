import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/fiber/fiber_band.dart';
import 'bdcom_epon.dart';
import 'olt_profile.dart';
import 'snmp_client.dart';
import 'vsol_olt_api.dart';

/// طلب GET واحد — `SnmpV2c.get` نفسه في الإنتاج، وأولتٌ وهميّ في الاختبار (فيُثبت الاختبار أنّنا لا نسأل إلّا GET).
typedef NscrtvGet = Future<List<Varbind>> Function(List<String> oids);

/// قراءات **أولت EPON بجداول NSCRTV القياسيّة** (‏NSCRTV-FTTX-EPON-MIB تحت المؤسّسة `17409` — معيار الكيبل الصينيّ الذي
/// تبني عليه أولتاتٌ كثيرة جداولها). يُعرف بـ`sysObjectID` = ‏`1.3.6.1.4.1.17409` لا بالاسم.
///
/// ثبت حيّاً ٢٠ نوفمبر عبر VPN الوكيل (GET وحده، ٣٢ طلباً): أولتٌ سجّله وكيله «C-Data»، وصفه «EasyPath Ethernet-PON»،
/// ‏4 PON · 4 GE · 2 XGE، ‏١٠٧ ONU مسجّلة (٦٨ متّصلة: ٦/٧ · ٢٢/٣٤ · ١١/٢٠ · ٢٩/٤٦)، ضوء الـ٦٨ كلّها (‎-28.24 … ‎-15.24 dBm).
///
/// | ما يُقرأ | المصدر | ملاحظة |
/// |---|---|---|
/// | المنافذ | IF-MIB: «pon0/0/1..4» (الفهرس 7..10)، «ge0/0/1..4»، «xge0/0/1..2» | عدّادات ٦٤ بت تعمل وتتحدّث لحظيّاً |
/// | الـONU وحالتها | `17409.2.3.4.1.1.8.<i>` | 1 متّصل · 2 مفصول · غائب = لا ONU في هذا الموضع |
/// | ماكها / اسمها | `.7` / `.2` | ستّة بايتات خام / فارغٌ على أولت الوكيل |
/// | الصانع / الطراز | `.25` / `.26` | «HWTC» / رمز وحدة («120C») — فارغان للمفصولة |
/// | الضوء | `17409.2.3.4.2.1.{4 rx · 5 tx · 7 جهد · 8 حرارة}.<i>.0.0` | rx/tx بوحدة ٠٫٠١ dBm، الحرارة ٠٫٠١°، الجهد ٠٫٠١ ملّي فولت (‏321000 = ‏3.21V) |
///
/// الفهرس `<i>` (EponDeviceIndex): بايت الأولت 1 · بايت البطاقة 0 · **بايت المنفذ = فهرس منفذ الـPON في IF-MIB** · رقم الـONU.
/// ‏pon0/0/1 فهرسه 7 ⇒ أوّل ONU عليه ‏`0x01000701` = ‏16779009 (أوّل صفٍّ أجاب به الجهاز نفسه).
///
/// ⚠️ **GET وحده، وعلى منافذ الجدول وحدها:**
///   ١. سؤال مواضع على بايت منفذٍ غير موجود (‏0x11…0x14) **لا يُجاب حتى المهلة** — مقيس: دفعتان من ١٦ ضاعتا. فالمواضع
///      تُحسب من فهارس منافذ «pon» في IF-MIB وحدها.
///   ٢. GETNEXT على جذر جدول الـONU أو عمود الماك لم يُجب (مهلة، مرّتان) — لا مسح هنا أبداً.
///   ٣. لا معالج ولا ذاكرة للأولت في هذه الجداول — «—» لا تخمين.
class NscrtvOlt {
  NscrtvOlt._();

  static const ent = '1.3.6.1.4.1.17409.2.3';

  static const ifNumberOid = '1.3.6.1.2.1.2.1.0';

  static const _onu = '$ent.4.1.1';
  static const _optics = '$ent.4.2.1';

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
  static const _ifHCIn = '1.3.6.1.2.1.31.1.1.1.6';
  static const _ifHCOut = '1.3.6.1.2.1.31.1.1.1.10';

  /// كم OID في طلب GET واحد — ١٦ أجابت كلّها عبر VPN بلا مهلة (٢٠ نوفمبر).
  static const _perGet = 16;

  /// صفوف IF-MIB التي تُسأل (المنافذ أوّل الجدول؛ أولت الوكيل عشرة).
  static const _maxIfRows = 128;

  /// EPON ‏1:64؛ ومنفذٌ بلغت فيه ONU آخر الـ٦٤ يُسأل حتى ١٢٨.
  static const _maxOnu = 64;
  static const _wideMaxOnu = 128;

  /// EponDeviceIndex: ‏`0x01 · بطاقة 0 · فهرس منفذ الـPON في IF-MIB · رقم الـONU`.
  static int onuIndex(int ponIfIndex, int onu) => 0x01000000 | ((ponIfIndex & 0xff) << 8) | (onu & 0xff);
  static int ponIfIndexOf(int index) => (index >> 8) & 0xff;
  static int onuOf(int index) => index & 0xff;

  // ═══════════════════════════════════════════════════════════
  // التحويل — خالصٌ وقابلٌ للاختبار
  // ═══════════════════════════════════════════════════════════

  /// 1 متّصل، وأيّ رقمٍ آخر مفصول (2، و3 «اختبار» في المعيار)، والغائب `null` = لا ONU في هذا الموضع.
  @visibleForTesting
  static bool? onlineFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    return vb.asInt == 1;
  }

  static double? _scaled(Varbind? vb, double div, double lo, double hi) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt / div;
    return (v < lo || v > hi) ? null : v;
  }

  /// الاستقبال عند الـONU بوحدة ٠٫٠١ dBm ‏(‎-2155 ← ‎-21.55) — وما لا يُعقل ضوءاً ([FiberBands.plausible]) `null`.
  @visibleForTesting
  static double? rxFrom(Varbind? vb) {
    final v = _scaled(vb, 100, -45, 10);
    return FiberBands.plausible(v) ? v : null;
  }

  /// الإرسال ٠٫٠١ dBm، والجهد ٠٫٠١ ملّي فولت (‏321000 ← ‏3.21V)، والحرارة ٠٫٠١° (‏3000 ← ‏30°).
  @visibleForTesting
  static BdcomOnuReading? readingFrom(Varbind? rx, Varbind? tx, Varbind? volt, Varbind? temp) {
    final r = BdcomOnuReading(
      rxDbm: rxFrom(rx),
      txDbm: _scaled(tx, 100, -15, 12),
      voltV: _scaled(volt, 100000, 2.5, 5.5),
      tempC: _scaled(temp, 100, -30, 120),
    );
    return r.isEmpty ? null : r;
  }

  /// اسم الـONU كما كتبه المشغّل، أو `null` للفارغ والافتراضيّ («ONU01/07» · «pon0/0/1:7»): الافتراضيّ اسم موضعٍ لا يتبع
  /// الـONU إذا نُقلت.
  @visibleForTesting
  static String? nameFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || vb.rawTag != 0x04) return null;
    final s = utf8.decode(vb.rawBytes, allowMalformed: true).replaceAll(RegExp(r'[\x00-\x1F\x7F�]'), '').trim();
    if (s.isEmpty || s.length > 64 || _defaultName.hasMatch(s) || _placeholder.hasMatch(s)) return null;
    return s;
  }

  static final _defaultName = RegExp(
      r'^(ONU\s*\d{1,3}\s*[/:._-]\s*\d{1,3}|[eg]?pon\s*\d{1,2}(/\d{1,2}){0,2}\s*[:._-]\s*\d{1,3})$',
      caseSensitive: false);
  static final _placeholder = RegExp(r'^(null|none|nil|n/?a|unknown|default|-+|0+)$', caseSensitive: false);

  /// نصٌّ قصيرٌ مطبوع (الصانع «HWTC»، الطراز «120C») — والفارغ `null`.
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

  /// «pon0/0/1» ← منفذ PON ‏1 على اللوحة 0 (و«EPON0/1» و«PON1»). و«ge0/0/1»/«xge0/0/2» ← صعود «GE1»/«XGE2». وغيرها يُهمل.
  static final _rePon = RegExp(r'^[eg]?pon[-_ ]?(?:(\d+)/)?(?:(\d+)/)?0*(\d+)$', caseSensitive: false);
  static final _reUplink = RegExp(r'^(x?ge|10ge|te|sfp)[-_ ]?(?:(\d+)/)?(?:(\d+)/)?0*(\d+)$', caseSensitive: false);

  /// اللوحة من الاسم: الرقم قبل المنفذ («pon0/2/1» ⇒ 2)، وصفرٌ لما لا لوحة فيه.
  static int _slotOf(RegExpMatch m) => int.tryParse(m.group(2) ?? m.group(1) ?? '0') ?? 0;

  /// يبني اللقطة من قراءاتٍ خام (نقيّ — للاختبار): المنافذ، ثمّ الـONU مرتّبةً وعدّ كلّ منفذ. الـONU على منفذٍ لا يعرفه
  /// جدول المنافذ تُهمل (لا رقم منفذٍ يُعرض لها).
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
      final u = p == null ? _reUplink.firstMatch(name) : null;
      if (p != null) {
        pons.add(VsolPonPort(index: r.index, slot: _slotOf(p), port: int.parse(p.group(3)!), up: r.up, rxBytes: r.rxBytes, txBytes: r.txBytes));
      } else if (u != null) {
        // «ge0/0/1»: الإطار ثمّ اللوحة ثمّ المنفذ — اللوحة الرقم قبل المنفذ كما في منافذ PON.
        final slot = int.tryParse(u.group(3) ?? u.group(2) ?? '0') ?? 0;
        final port = int.parse(u.group(4)!);
        uplinks.add(VsolUplink(
          index: r.index,
          name: '${u.group(1)!.toUpperCase()}${slot > 0 ? '$slot/' : ''}$port',
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
    final byIf = {for (final p in pons) p.index: p};
    final idx = status.keys.where((i) => byIf.containsKey(ponIfIndexOf(i))).toList()..sort();
    final onus = [
      for (final i in idx)
        VsolOnu(
          ifIndex: i,
          slot: byIf[ponIfIndexOf(i)]!.slot,
          ponPort: byIf[ponIfIndexOf(i)]!.port,
          onuId: onuOf(i),
          online: status[i]!,
          mac: macs[i],
          name: names[i],
        ),
    ];
    for (final o in onus) {
      ifNames[o.ifIndex] = o.label;
    }
    pons.sort((a, b) => a.slot != b.slot ? a.slot.compareTo(b.slot) : a.port.compareTo(b.port));
    return VsolOltStats(
      sysDescr: sysDescr,
      sysName: sysName,
      uptime: uptime,
      uplinks: uplinks,
      ponPorts: [
        for (final p in pons)
          p.withCounts(
            onuTotal: onus.where((o) => o.slot == p.slot && o.ponPort == p.port).length,
            onuOnline: onus.where((o) => o.slot == p.slot && o.ponPort == p.port && o.online).length,
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
    NscrtvGet get,
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

  /// منافذ PON التي يُسأل عنها جدول الـONU: فهرسها في IF-MIB يتّسع لبايتٍ واحد في الفهرس المحسوب.
  static List<int> _ponIfIndexes(Iterable<VsolPonPort> pons) => [
        for (final p in pons)
          if (p.index > 0 && p.index <= 0xff) p.index,
      ];

  /// حالة كلّ ONU موجودة (فهرس ← متّصل؟) بسؤال كلّ موضعٍ ممكن على منافذ الجدول وحدها: ١..٦٤ لكلّ منفذ، وإلى ١٢٨ لمنفذٍ
  /// بلغ آخر الـ٦٤. الموضع الفارغ يُجاب «غير موجود» فوراً. `null` = دفعةٌ لم تُجب.
  static Future<Map<int, bool>?> scanOnus(NscrtvGet get, List<int> ponIfIndexes, {bool Function()? isCancelled}) async {
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
      for (final p in ponIfIndexes)
        for (var o = 1; o <= _maxOnu; o++) onuIndex(p, o),
    ]);
    if (out == null) return null;
    final wide = {for (final i in out.keys) if (onuOf(i) > _maxOnu - 8) ponIfIndexOf(i)}.toList()..sort();
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
  static Future<Map<int, bool>?> statusOf(NscrtvGet get, Iterable<int> idx, {bool Function()? isCancelled}) async {
    final want = idx.toSet().toList()..sort();
    final got = await _getAll(get, [for (final i in want) statusOid(i)], isCancelled: isCancelled);
    if (got == null) return null;
    return {
      for (final i in want)
        if (onlineFrom(got[statusOid(i)]) != null) i: onlineFrom(got[statusOid(i)])!,
    };
  }

  /// ماك كلّ ONU واسمها المكتوب (لا الافتراضيّ). للمفصولة أيضاً: الماك هويّتها المسجّلة (‏١٠٧ من ١٠٧ على أولت الوكيل).
  static Future<({Map<int, String> macs, Map<int, String> names})> details(
    NscrtvGet get,
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
  static Future<Map<int, String>?> names(NscrtvGet get, Iterable<int> idx, {bool Function()? isCancelled}) async {
    final want = idx.toSet().toList()..sort();
    final got = await _getAll(get, [for (final i in want) nameOid(i)], isCancelled: isCancelled);
    if (got == null) return null;
    return {
      for (final i in want)
        if (nameFrom(got[nameOid(i)]) != null) i: nameFrom(got[nameOid(i)])!,
    };
  }

  /// صانع الـONU («HWTC») ورمز وحدتها («120C») — فارغان للمفصولة على أولت الوكيل.
  static Future<Map<int, BdcomOnuReading>> identities(NscrtvGet get, Iterable<int> idx, {bool Function()? isCancelled}) async {
    final want = idx.toSet().toList()..sort();
    final got = await _getAll(get, [for (final i in want) ...[vendorOid(i), modelOid(i)]], isCancelled: isCancelled) ?? const {};
    final out = <int, BdcomOnuReading>{};
    for (final i in want) {
      final r = BdcomOnuReading(vendor: _text(got[vendorOid(i)]), module: _text(got[modelOid(i)]));
      if (!r.isEmpty) out[i] = r;
    }
    return out;
  }

  /// قراءات الضوء للمتّصلة: الاستقبال والإرسال والجهد والحرارة. المفصولة لا تُسأل.
  static Future<Map<int, BdcomOnuReading>> readings(NscrtvGet get, Iterable<int> online, {bool Function()? isCancelled}) async {
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
  static Future<Map<int, double>?> rxOnly(NscrtvGet get, Iterable<int> online, {bool Function()? isCancelled}) async {
    final want = online.toSet().toList()..sort();
    if (want.isEmpty) return const {};
    final got = await _getAll(get, [for (final i in want) opticsOid(_colRx, i)], isCancelled: isCancelled);
    if (got == null) return null;
    return {
      for (final i in want)
        if (rxFrom(got[opticsOid(_colRx, i)]) != null) i: rxFrom(got[opticsOid(_colRx, i)])!,
    };
  }

  /// لا معالج ولا ذاكرة للأولت في جداول NSCRTV — «—» لا تخمين.
  static Future<BdcomChassis> chassis(NscrtvGet get) async => const BdcomChassis();

  /// منافذ الجهاز من IF-MIB بالـGET: ‏١..[count]. `null` = لم يُجب.
  static Future<({List<VsolIfRow> rows, DateTime? rxAt, DateTime? txAt})?> ports(
    NscrtvGet get,
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
  /// يمنع لقطةً صادقة (لا جدول منافذ، أو لا منافذ PON، أو حالةٌ لم تُجب كاملة) فتبقى آخر قراءةٍ صحيحة معروضة.
  static Future<VsolOltStats> fetchStats(
    NscrtvGet get, {
    required OltProfile profile,
    String? sysDescr,
    String? sysName,
    Duration? uptime,
    bool withCounters = false,
    void Function(VsolOltStats partial)? onPartialReady,
  }) async {
    final id = await _getAll(get, const [ifNumberOid], strict: true);
    final count = _count(id?[ifNumberOid], 4096);
    if (id == null || count == null) {
      throw VsolException('الأولت لا يكشف جدول المنافذ — تأكّد أنّه أولت EPON وأنّ SNMP مفعّل للقراءة');
    }
    final pr = await ports(get, math.min(count, _maxIfRows), counters: withCounters);
    if (pr == null) throw VsolException('تعذّرت قراءة منافذ الأولت — لم يُجب الجهاز');
    final descr = sysDescr?.trim();
    VsolOltStats snap(Map<int, bool> status, {Map<int, String> macs = const {}, Map<int, String> names = const {}}) =>
        buildStats(
          profile: profile,
          ports: pr.rows,
          status: status,
          macs: macs,
          names: names,
          sysDescr: descr == null || descr.isEmpty ? null : descr,
          sysName: sysName,
          uptime: uptime,
          rxAt: pr.rxAt,
          txAt: pr.txAt,
        );
    final early = snap(const {});
    if (early.ponPorts.isEmpty) throw VsolException('قراءةٌ ناقصة: لم تظهر منافذ PON في جدول الواجهات');
    final ponIdx = _ponIfIndexes(early.ponPorts);
    if (ponIdx.isEmpty) throw VsolException('قراءةٌ ناقصة: أرقام منافذ PON في جدول الواجهات خارج ترقيم جدول الـONU');
    onPartialReady?.call(early);
    final status = await scanOnus(get, ponIdx);
    if (status == null) throw VsolException('قراءةٌ ناقصة: لم يُجب الأولت بحالة كلّ الـONU');
    // لا ONU في أيّ موضع: أولتٌ فارغ («noSuchInstance» لكلّ موضع) أم جدولٌ غائب أصلاً («noSuchObject»)؟ الثاني يقال صراحةً،
    // لا «٠ مشترك» على أولتٍ يخدم مئة.
    if (status.isEmpty) {
      final probe = statusOid(onuIndex(ponIdx.first, 1));
      final vb = (await _getAll(get, [probe]))?[probe];
      if (vb != null && vb.rawTag == 0x80) {
        throw VsolException('قراءةٌ ناقصة: هذا الأولت لا يكشف قائمة الـONU بجداول NSCRTV');
      }
    }
    onPartialReady?.call(snap(status));
    final d = await details(get, status.keys);
    if (kDebugMode) {
      debugPrint('══════ NSCRTV OLT ══════');
      debugPrint('  $descr · pon ${early.ponPorts.length} · onu ${status.length} '
          '(${status.values.where((v) => v).length} متّصل) · ماك ${d.macs.length}');
    }
    return snap(status, macs: d.macs, names: d.names);
  }

  /// الحالة وحدها فوق آخر بنية: كلّ موضعٍ ممكن (فتظهر ONU سُجّلت للتوّ في [unknown] فيُعيد المستدعي البنية) وحالة
  /// المنافذ. `null` = لم يُجب كاملاً — تبقى آخر قراءةٍ صحيحة.
  static Future<({VsolOltStats stats, int unknown})?> refreshStatus(NscrtvGet get, VsolOltStats previous) async {
    final ponIdx = _ponIfIndexes(previous.ponPorts);
    if (ponIdx.isEmpty) return null;
    final status = await scanOnus(get, ponIdx);
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
