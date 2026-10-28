import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/fiber/fiber_band.dart';
import '../services/fiber/fiber_onu.dart';
import 'bdcom_epon.dart';
import 'olt_get_tables.dart';
import 'olt_profile.dart';
import 'snmp_client.dart';
import 'vsol_olt_api.dart';

/// قرّاء شبكة الألياف — فوق قراءات لوحة الأولت ([VsolOltApi] و[BdcomEpon]): الضوء لـVSOL، سبب السقوط ولحظته، اسم الجهاز.
///
/// المصادر (GET فقط، لكلّ ONU بعينها — لا مسح جداول قد تجاور أعمدةً حسّاسة كالـLOID وكلمات السرّ):
///
/// | ما يُقرأ | المصدر | الحالة |
/// |---|---|---|
/// | لحظة آخر تغيّر | IF-MIB `ifLastChange` + `sysUpTime` | قياسيّ — يُفحص على كلّ جهاز |
/// | الضوء VSOL EPON | V1600D-MIB `opmDiagInfoTable` `.37950.1.1.5.12.2.1.8.1.{7 rx,6 tx,3 temp,4 volt}.<pon>.<onu>` نصّاً | MIB المصنّع (LibreNMS) |
/// | الضوء VSOL GPON | `.37950.1.1.6.1.1.3.1.{…}` بالبنية نفسها | مشروعٌ مفتوح (rx = .7) |
/// | سبب السقوط VSOL EPON | `onuAuthInfo2DeregReason` `.37950.1.1.5.12.1.25.1.15.<pon>.<onu>` | 1 = كهرباء ثابت بالمصدرين؛ 2 = ضوء؛ 0 غامض (MIB: wire-down، وغيره: N/A) ⇒ غير معروف |
/// | سبب السقوط BDCOM | `llidOnuBindLastDeregReason` `.3320.101.11.1.1.11.<ifIndex>` (8 wire-down، 9 power-off) | MIB المصنّع، بحسب الإصدار |
/// | اسم الجهاز | IF-MIB `ifAlias`، وVSOL EPON `onuAuthInfoDescription2` `.25.1.9` | قياسيّ / MIB |
///
/// كلّ قيمةٍ تُفحص قبل قبولها (المدى المعقول) — ما لا يُعقل `null` لا رقمٌ كاذب. وما لا يدعمه الجهاز يُتذكَّر لكلّ عنوانٍ فلا
/// يُسأل كلّ دورة ([FiberOltCaps]).
class OltFiberReads {
  OltFiberReads._();

  static const sysUpTimeOid = '1.3.6.1.2.1.1.3.0';
  static const ifLastChangeOid = '1.3.6.1.2.1.2.2.1.9';
  static const ifOperStatusOid = '1.3.6.1.2.1.2.2.1.8';
  static const ifAliasOid = '1.3.6.1.2.1.31.1.1.1.18';

  static const vsolEponOptics = '1.3.6.1.4.1.37950.1.1.5.12.2.1.8.1';
  static const vsolGponOptics = '1.3.6.1.4.1.37950.1.1.6.1.1.3.1';
  static const vsolEponAuth = '1.3.6.1.4.1.37950.1.1.5.12.1.25.1';
  static const bdcomDeregReason = '1.3.6.1.4.1.3320.101.11.1.1.11';

  /// كم OID في طلب GET واحد (كـBdcomEpon).
  static const _perGet = 16;

  // ── التحليل (نقيّ — للاختبار) ──────────────────────────────────────────────────────────

  static final _num = RegExp(r'-?\d+(?:\.\d+)?');

  /// أوّل عددٍ في نصّ القراءة: «‎-21.35» · «-21.35 dBm» · «-21.35(dBm)» · «−21.35». ما لا عدد فيه `null`.
  static double? _firstNumber(String s) {
    final t = s.replaceAll('−', '-').replaceAll(',', '.');
    final m = _num.firstMatch(t);
    return m == null ? null : double.tryParse(m.group(0)!);
  }

  static bool _hasDecimal(String s) => RegExp(r'\d[.,]\d').hasMatch(s);

  /// قيمةٌ من جدول VSOL (نصٌّ أو عدد): أوّل قسمةٍ تقع في المدى المعقول، بدءاً بالقيمة كما هي.
  /// النصّ العشريّ يُقبل كما هو وحده (لا قسمة على ما يحمل فاصلته).
  static double? scaled(Varbind vb, {required double lo, required double hi, List<double> divisors = const [1, 10, 100]}) {
    if (vb.isAbsent) return null;
    double? raw;
    var decimal = false;
    if (vb.isNumeric) {
      raw = vb.asInt.toDouble();
      if (vb.rawTag == 0x02 && raw == 0) return null;
    } else if (vb.rawTag == 0x04) {
      final s = utf8.decode(vb.rawBytes, allowMalformed: true).trim();
      if (s.isEmpty || RegExp(r'n/?a|--|null|inf', caseSensitive: false).hasMatch(s)) return null;
      raw = _firstNumber(s);
      decimal = _hasDecimal(s);
    }
    if (raw == null || raw == 0) return null;
    for (final d in decimal ? const [1.0] : divisors) {
      final v = raw / d;
      if (v >= lo && v <= hi) return double.parse(v.toStringAsFixed(2));
    }
    return null;
  }

  /// القدرة الضوئيّة بالـdBm من نصّ المصنّع: الرقم المقرون بـdBm أوّلاً — VSOL V1600D يكتب «0.0070 mW(-21.55dBm)»
  /// فأوّل رقمٍ فيه الميلّيواط (كان يُقرأ ‎0.01 ويُعدّ «قويّاً زيادة»)؛ ثمّ الميلّيواط/الميكرواط محوّلاً
  /// (10·log10)؛ وإلّا `null` ليقرّر [scaled]. نصٌّ بلا وحدةٍ يبقى لـ[scaled].
  static double? dbmText(String s) {
    final t = s.replaceAll('−', '-').replaceAll(',', '.');
    final d = RegExp(r'(-?\d+(?:\.\d+)?)\s*\(?\s*dbm', caseSensitive: false).firstMatch(t);
    if (d != null) return double.tryParse(d.group(1)!);
    double? power(RegExp re, double toMw) {
      final m = re.firstMatch(t);
      final v = m == null ? null : double.tryParse(m.group(1)!);
      if (v == null || v <= 0) return null;
      return double.parse((10 * math.log(v * toMw) / math.ln10).toStringAsFixed(2));
    }

    return power(RegExp(r'(\d+(?:\.\d+)?)\s*mw', caseSensitive: false), 1) ??
        power(RegExp(r'(\d+(?:\.\d+)?)\s*[uµ]w', caseSensitive: false), 0.001);
  }

  /// قدرةٌ ضوئيّة من عمودٍ (نصٌّ بوحدته أو عدد): [dbmText] للنصّ، و[scaled] لما سواه.
  static double? dbm(Varbind vb, {double lo = -45, double hi = 10}) {
    if (!vb.isAbsent && vb.rawTag == 0x04) {
      final s = utf8.decode(vb.rawBytes, allowMalformed: true).trim();
      if (RegExp(r'dbm|[mµu]w', caseSensitive: false).hasMatch(s)) {
        final v = dbmText(s);
        return v != null && v >= lo && v <= hi && v != 0 ? double.parse(v.toStringAsFixed(2)) : null;
      }
    }
    return scaled(vb, lo: lo, hi: hi);
  }

  /// صفّ الضوء لـONU واحدة من أعمدة VSOL.
  static BdcomOnuReading? vsolReading(Varbind? rx, Varbind? tx, Varbind? temp, Varbind? volt) {
    final r = rx == null ? null : dbm(rx);
    final reading = BdcomOnuReading(
      rxDbm: FiberBands.plausible(r) ? r : null,
      txDbm: tx == null ? null : dbm(tx, lo: -15, hi: 12),
      tempC: temp == null ? null : scaled(temp, lo: -30, hi: 120, divisors: const [1, 10, 100, 256]),
      voltV: volt == null ? null : scaled(volt, lo: 2.5, hi: 5.5, divisors: const [1, 10, 100, 1000, 10000]),
    );
    return reading.isEmpty ? null : reading;
  }

  /// سبب سقوط VSOL EPON (`onuAuthInfo2DeregReason`). 1 كهرباء بكلّ مصدر؛ 2 ضوء؛ 0 غامض ⇒ غير معروف.
  static FiberDropReason? vsolReason(Varbind vb) {
    if (vb.isAbsent || !vb.isNumeric) return null;
    return switch (vb.asInt) {
      1 => FiberDropReason.power,
      2 => FiberDropReason.fiber,
      _ => FiberDropReason.unknown,
    };
  }

  /// سبب سقوط BDCOM (`llidOnuBindLastDeregReason`).
  static FiberDropReason? bdcomReason(Varbind vb) {
    if (vb.isAbsent || !vb.isNumeric) return null;
    return switch (vb.asInt) {
      8 => FiberDropReason.fiber,
      9 => FiberDropReason.power,
      2 || 3 || 4 || 5 || 6 || 7 => FiberDropReason.other,
      _ => FiberDropReason.unknown,
    };
  }

  /// لحظة آخر تغيّر بساعة الهاتف: الآن − (sysUpTime − ifLastChange). صفرٌ أو أكبر من وقت التشغيل = قبل الإقلاع ⇒ `null`.
  static DateTime? changedAt({required int upTicks, required int lastChangeTicks, required DateTime now}) {
    if (lastChangeTicks <= 0 || upTicks <= 0 || lastChangeTicks > upTicks) return null;
    return now.subtract(Duration(milliseconds: (upTicks - lastChangeTicks) * 10));
  }

  static String _suffix(VsolOnu o) => '${o.ponPort}.${o.onuId}';

  // ── القراءة ──────────────────────────────────────────────────────────────────────────

  /// كم طلباً في الطريق معاً: يُخفي زمن الرحلة على أولتٍ بعيد (~٢٥٠ مللي عبر VPN) بلا إغراق وكيلٍ يعالج ~١٠٠ قيمة/ث.
  static const _parallel = 3;

  /// يشغّل [jobs] بـ[_parallel] عمّالٍ معاً، وما يرمي منها يُتجاوز وحده.
  static Future<void> _pool(int count, Future<void> Function(int i) job, bool Function()? cancelled, {int parallel = _parallel}) async {
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (cancelled?.call() == true) return;
        final i = next++;
        if (i >= count) return;
        try {
          await job(i);
        } catch (_) {/* دفعةٌ لا تجيب — نتجاوزها ولا نُسقط البقيّة */}
      }
    }

    await Future.wait([for (var w = 0; w < parallel && w < count; w++) worker()]);
  }

  static Future<Map<String, Varbind>> _getAll(SnmpV2c snmp, List<String> oids, bool Function()? cancelled,
      {int perGet = _perGet, int parallel = _parallel}) async {
    final out = <String, Varbind>{};
    final batches = [for (var s = 0; s < oids.length; s += perGet) oids.sublist(s, math.min(s + perGet, oids.length))];
    await _pool(batches.length, (i) async {
      for (final vb in await snmp.get(batches[i])) {
        out[vb.oid] = vb;
      }
    }, cancelled, parallel: parallel);
    return out;
  }

  /// جدول ضوء VSOL يُحسب جهازاً جهازاً حين يُسأل (V1600D، ٢٧ أكتوبر، مقيس حيّاً): مسحه (GETBULK) ~ثانية لكلّ صفّ —
  /// خمس دقائق لـ٣٠٠ جهاز — ويخنق الوكيل فتسقط القراءات الأخرى معه، وطلبٌ بستّ عشرة قيمة يتجاوز المهلة. أربع قيمٍ
  /// بالطلب ~١٫٤ث (تحت عتبة إعادة الإرسال) ⇒ أربعٌ بالطلب، طلبٌ بعد طلب.
  static const _vsolOpticsPerGet = 4;

  /// مسح عمودٍ (GETBULK) — يُرجع الموجود وحده، فلا طلبٌ لجهازٍ بلا صفٍّ يُهمَل كلّه حتى المهلة. `null` = لم يُجب.
  /// العمود الذي لم يُجب يُتذكَّر لهذا العنوان ساعة — لا ندفع مهلته كلّ دورة.
  static Future<List<Varbind>?> _walk(SnmpV2c snmp, String base, {Duration silence = const Duration(hours: 1)}) async {
    final key = '${snmp.host}|$base';
    final until = _silent[key];
    if (until != null && DateTime.now().isBefore(until)) return null;
    try {
      return await snmp.walk(base, chunkSize: 50, maxIterations: 200);
    } catch (_) {
      _silent[key] = DateTime.now().add(silence);
      return null;
    }
  }

  /// ifPhysAddress — على VSOL EPON هو ماك الـONU نفسها للمتّصلة (مقارَنٌ بالـCLI على V1600D).
  static const ifPhysOid = '1.3.6.1.2.1.2.2.1.6';

  /// ماك أجهزة VSOL EPON بمسح عمودٍ واحد (~٣٣٠ قيمة) — بها يطابق «ربط المشتركين» الجهاز بجلسة الساس.
  ///
  /// 🐛 ٢٧ أكتوبر (المالك على V1600D: «الاولتي مجاي يقره لابورات ولامكات ويطابقه وي المتصلين»): شبكة الألياف كانت تقرأ
  /// ماك BDCOM وحده، وماك VSOL في لوحة الأولت فقط — فلا ماك ولا مطابقة. عنوانٌ صفريّ أو FF (مفصولة) لا يُعدّ.
  /// `null` = العمود لم يُجب (يُعاد بعد دقيقتين لا ساعة — عمودٌ قياسيّ، فالصمت حِملٌ لا غياب).
  static Future<Map<int, String>?> vsolEponMacs(SnmpV2c snmp, Set<int> ifIndexes) async {
    if (ifIndexes.isEmpty) return const {};
    final vbs = await _walk(snmp, ifPhysOid, silence: const Duration(minutes: 2));
    if (vbs == null) return null;
    final out = <int, String>{};
    for (final vb in vbs) {
      if (!vb.oid.startsWith('$ifPhysOid.')) continue;
      final i = int.tryParse(vb.oid.substring(ifPhysOid.length + 1));
      if (i == null || !ifIndexes.contains(i) || vb.isAbsent) continue;
      final b = vb.rawBytes;
      if (b.length != 6 || b.every((v) => v == 0) || b.every((v) => v == 255)) continue;
      out[i] = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(':');
    }
    return out;
  }

  /// اسم الواجهة الافتراضيّ («EPON01ONU12» على V1600D، «EPON0/1:12»، «PON1:ONU12»، «ONU0/1:1») — ليس اسم مشترك.
  static final _defaultIfName = RegExp(r'^([eg]?pon[\d/:._-]*onu[\d/:._-]*|(onu|epon|gpon)[\d/:._-]*)$', caseSensitive: false);

  /// قيمٌ يملأ بها الأولت خانة الاسم الفارغة — ليست أسماء.
  static final _placeholderName = RegExp(r'^(null|none|nil|n/?a|unknown|undefined|default|empty|-+|0+)$', caseSensitive: false);

  /// ينظّف الأسماء: لا قيمة حشوٍ («NULL» على V1600D لكلّ الـ٣٠٢)، ولا قيمةٌ واحدة تتكرّر على أغلب الأجهزة — الاسم يميّز
  /// جهازاً، والمكرَّر على النصف حشوٌ مهما كان.
  static Map<int, String> cleanNames(Map<int, String> names) {
    final out = <int, String>{
      for (final e in names.entries)
        if (!_placeholderName.hasMatch(e.value.trim()) && !_defaultIfName.hasMatch(e.value.trim())) e.key: e.value,
    };
    if (out.length < 5) return out;
    final counts = <String, int>{};
    for (final v in out.values) {
      counts[v.toLowerCase()] = (counts[v.toLowerCase()] ?? 0) + 1;
    }
    final junk = {for (final e in counts.entries) if (e.value >= 5 && e.value * 2 >= out.length) e.key};
    if (junk.isEmpty) return out;
    out.removeWhere((_, v) => junk.contains(v.toLowerCase()));
    return out;
  }

  static final Map<String, DateTime> _silent = {};

  @visibleForTesting
  static void debugReset() => _silent.clear();

  /// ⚡ **الضوء وحده بمسح عموده** — لكلّ أولت: VSOL (EPON/GPON، فهرس المنفذ.الجهاز) وBDCOM (فهرس الواجهة). ~٧ رحلاتٍ
  /// لـ٣٠٠ جهاز بدل ٥٠ طلباً بأربع قيمٍ للجهاز؛ الإرسال والحرارة والفولتيّة لجهازٍ واحد حين يُفتح ([vsolOptics] /
  /// [BdcomEpon.readings]). `null` = العمود لم يُجب (تبقى القراءة السابقة).
  static Future<Map<int, double>?> rxColumn(SnmpV2c snmp, OltProfile profile, Iterable<VsolOnu> onus) async {
    final online = [for (final o in onus) if (o.online) o];
    if (online.isEmpty) return const {};
    final out = <int, double>{};
    var answered = false;
    if (profile.readsBdcomEponTables) {
      final want = {for (final o in online) if (o.technology == VsolPonTechnology.epon) o.ifIndex};
      if (want.isEmpty) return const {};
      final vbs = await _walk(snmp, BdcomEpon.rxOid);
      if (vbs == null) return null;
      answered = true;
      for (final vb in vbs) {
        final i = int.tryParse(vb.oid.substring(BdcomEpon.rxOid.length + 1));
        if (i == null || !want.contains(i)) continue;
        final r = BdcomEpon.dbmFrom(vb);
        if (FiberBands.plausible(r)) out[i] = r!;
      }
    } else if (profile.readsVsolTables) {
      // بالسؤال المباشر لا بالمسح ([_vsolOpticsPerGet]) — والمتّصل أعطاه المستدعي (شريحةٌ كلّ دورة على أولتٍ كبير).
      final mine = [for (final o in online) if (o.slot == 0) o];
      if (mine.isEmpty) return const {};
      String oid(VsolOnu o) => '${o.technology == VsolPonTechnology.gpon ? vsolGponOptics : vsolEponOptics}.7.${_suffix(o)}';
      final got = await _getAll(snmp, [for (final o in mine) oid(o)], null, perGet: _vsolOpticsPerGet, parallel: 1);
      if (got.isEmpty) return null;
      answered = true;
      for (final o in mine) {
        final vb = got[oid(o)];
        if (vb == null) continue;
        final r = dbm(vb);
        if (FiberBands.plausible(r)) out[o.ifIndex] = r!;
      }
    } else if (profile.readsGetTables) {
      // ⚠️ GET لا مسح: مسح جدول الضوء على HSGQ يُعلّق وكيله ([HsgqOlt])، وC-Data بالـGET كذلك ([CdataOlt]).
      return OltGetTables.of(profile)!.rxOnly(snmp.get, [for (final o in online) o.ifIndex]);
    } else {
      return const {};
    }
    return answered ? out : null;
  }

  /// ضوء VSOL للمتّصلة (ifIndex ← قراءة). البطاقة صفر وحدها (فهرس الجدول منفذٌ ورقم ONU بلا بطاقة).
  static Future<Map<int, BdcomOnuReading>> vsolOptics(
    SnmpV2c snmp,
    Iterable<VsolOnu> onus, {
    bool Function()? isCancelled,
  }) async {
    final want = [
      for (final o in onus)
        if (o.online && o.slot == 0) o,
    ];
    if (want.isEmpty) return const {};
    String base(VsolOnu o) => o.technology == VsolPonTechnology.gpon ? vsolGponOptics : vsolEponOptics;
    final oids = [
      for (final o in want)
        for (final c in const [7, 6, 3, 4]) '${base(o)}.$c.${_suffix(o)}',
    ];
    final got = await _getAll(snmp, oids, isCancelled, perGet: _vsolOpticsPerGet, parallel: 1);
    final out = <int, BdcomOnuReading>{};
    for (final o in want) {
      final b = base(o);
      final s = _suffix(o);
      final r = vsolReading(got['$b.7.$s'], got['$b.6.$s'], got['$b.3.$s'], got['$b.4.$s']);
      if (r != null) out[o.ifIndex] = r;
    }
    return out;
  }

  /// سبب سقوط المفصولة (ifIndex ← سبب). VSOL EPON وBDCOM EPON وحدهما — GPON بلا مصدرٍ معروف.
  static Future<Map<int, FiberDropReason>> dropReasons(
    SnmpV2c snmp,
    OltProfile profile,
    Iterable<VsolOnu> offline, {
    bool Function()? isCancelled,
  }) async {
    final epon = [
      for (final o in offline)
        if (!o.online && o.technology == VsolPonTechnology.epon) o,
    ];
    if (epon.isEmpty) return const {};
    final out = <int, FiberDropReason>{};
    if (profile.readsBdcomEponTables) {
      final got = await _getAll(snmp, [for (final o in epon) '$bdcomDeregReason.${o.ifIndex}'], isCancelled);
      for (final o in epon) {
        final vb = got['$bdcomDeregReason.${o.ifIndex}'];
        final r = vb == null ? null : bdcomReason(vb);
        if (r != null) out[o.ifIndex] = r;
      }
    } else if (profile.readsVsolTables) {
      final want = [
        for (final o in epon)
          if (o.slot == 0) o,
      ];
      final got = await _getAll(snmp, [for (final o in want) '$vsolEponAuth.15.${_suffix(o)}'], isCancelled);
      for (final o in want) {
        final vb = got['$vsolEponAuth.15.${_suffix(o)}'];
        final r = vb == null ? null : vsolReason(vb);
        if (r != null) out[o.ifIndex] = r;
      }
    }
    return out;
  }

  /// لحظة آخر تغيّر لكلّ ifIndex. كلّ دفعةٍ تسأل sysUpTime معها فيُطرح من القراءة نفسها.
  static Future<Map<int, DateTime>> lastChanges(
    SnmpV2c snmp,
    Iterable<int> ifIndexes, {
    DateTime? now,
    bool Function()? isCancelled,
  }) async {
    final want = ifIndexes.toSet().toList()..sort();
    final out = <int, DateTime>{};
    final chunks = [for (var s = 0; s < want.length; s += _perGet - 1) want.sublist(s, math.min(s + _perGet - 1, want.length))];
    await _pool(chunks.length, (k) async {
      final chunk = chunks[k];
      final vbs = await snmp.get([sysUpTimeOid, for (final i in chunk) '$ifLastChangeOid.$i']);
      final at = now ?? DateTime.now();
      final by = {for (final v in vbs) v.oid: v};
      final up = by[sysUpTimeOid];
      if (up == null || up.isAbsent || !up.isNumeric) return;
      for (final i in chunk) {
        final vb = by['$ifLastChangeOid.$i'];
        if (vb == null || vb.isAbsent || !vb.isNumeric) continue;
        final t = changedAt(upTicks: up.asInt, lastChangeTicks: vb.asInt, now: at);
        if (t != null) out[i] = t;
      }
    }, isCancelled);
    return out;
  }

  /// أسماء الأجهزة كما كتبها الوكيل: ifAlias، ووصف VSOL EPON. الفارغ لا يُعاد.
  /// ⚡ بمسح العمودين (GETBULK) لا بسؤال كلّ جهاز: ifAlias ثمّ — لمن بقي بلا اسم — وصف VSOL EPON. `null` = لم يُجب أيٌّ
  /// منهما (تبقى الأسماء السابقة؛ لا تُمحى بفراغ).
  static Future<Map<int, String>?> names(
    SnmpV2c snmp,
    OltProfile profile,
    Iterable<VsolOnu> onus, {
    bool Function()? isCancelled,
  }) async {
    final list = onus.toList();
    // HSGQ · C-Data: الاسم من جدول المصنّع بالـGET — ifAlias لصفوف الـONU لا يطابق موضعها (أو لا صفوف لها)، والافتراضيّ
    // («ONU01/07» · «unknown») يُهمل.
    if (profile.readsGetTables) {
      final n = await OltGetTables.of(profile)!.names(snmp.get, list.map((o) => o.ifIndex), isCancelled: isCancelled);
      return n == null ? null : cleanNames(n);
    }
    final byIf = {for (final o in list) o.ifIndex: o};
    final out = <int, String>{};
    String? text(Varbind? vb) {
      if (vb == null || vb.isAbsent || vb.rawTag != 0x04) return null;
      // UTF-8 (أسماءٌ عربيّة)، بلا حروف تحكّم.
      final s = utf8.decode(vb.rawBytes, allowMalformed: true).replaceAll(RegExp(r'[\x00-\x1F\x7F�]'), '').trim();
      if (s.isEmpty || s.length > 64 || _defaultIfName.hasMatch(s)) return null;
      // «NULL» ونحوه حشوٌ لا اسم — يُرفض هنا فيُقرأ وصف VSOL بدله.
      if (_placeholderName.hasMatch(s)) return null;
      return s;
    }

    var answered = false;
    final alias = await _walk(snmp, ifAliasOid);
    if (alias != null) {
      answered = true;
      for (final vb in alias) {
        if (!vb.oid.startsWith('$ifAliasOid.')) continue;
        final i = int.tryParse(vb.oid.substring(ifAliasOid.length + 1));
        if (i == null || !byIf.containsKey(i)) continue;
        final t = text(vb);
        if (t != null) out[i] = t;
      }
    }
    if (profile.readsVsolTables && isCancelled?.call() != true) {
      final bySuffix = {
        for (final o in list)
          if (o.technology == VsolPonTechnology.epon && o.slot == 0 && !out.containsKey(o.ifIndex)) _suffix(o): o.ifIndex,
      };
      if (bySuffix.isNotEmpty) {
        const base = '$vsolEponAuth.9';
        final got = await _walk(snmp, base);
        if (got != null) {
          answered = true;
          for (final vb in got) {
            if (!vb.oid.startsWith('$base.')) continue;
            final i = bySuffix[vb.oid.substring(base.length + 1)];
            final t = i == null ? null : text(vb);
            if (t != null) out[i!] = t;
          }
        }
      }
    }
    return answered ? cleanNames(out) : null;
  }

  // ── فحص القدرات ─────────────────────────────────────────────────────────────────────

  /// ما يدعمه هذا الأولت من قراءات الألياف — يُفحص مرّةً لكلّ جهاز (بعيّنةٍ صغيرة) ويُرفع للخادم بلا هويّات: لا ماك ولا
  /// اسم ولا SN، أعدادٌ وأشكال قيمٍ فقط. منه نعرف من الميدان ما لم نختبره على جهازٍ بأيدينا.
  static Future<FiberOltCaps> probe(
    SnmpV2c snmp,
    OltProfile profile,
    List<VsolOnu> onus, {
    DateTime? now,
  }) async {
    final online = onus.where((o) => o.online).take(4).toList();
    final offline = onus.where((o) => !o.online).take(6).toList();
    final sample = [...online, ...offline];
    final at = now ?? DateTime.now();

    // HSGQ · C-Data: فهرس الـONU فهرس جدول المصنّع لا IF-MIB — ifLastChange لا يعرفه، فلا يُسأل (ولا لحظة سقوطٍ عنده أصلاً).
    final getTables = OltGetTables.of(profile);
    final changes =
        getTables != null ? const <int, DateTime>{} : await lastChanges(snmp, sample.map((o) => o.ifIndex), now: at);
    final optics = profile.readsVsolTables
        ? await vsolOptics(snmp, online)
        : getTables != null
            ? await getTables.readings(snmp.get, online.map((o) => o.ifIndex))
            : const <int, BdcomOnuReading>{};
    final reasons = await dropReasons(snmp, profile, offline);
    final rawReasons = <String, int>{};
    if (offline.isNotEmpty) {
      final oids = profile.readsBdcomEponTables
          ? [for (final o in offline) '$bdcomDeregReason.${o.ifIndex}']
          : profile.readsVsolTables
              ? [for (final o in offline) if (o.technology == VsolPonTechnology.epon) '$vsolEponAuth.15.${_suffix(o)}']
              : const <String>[];
      if (oids.isNotEmpty) {
        final got = await _getAll(snmp, oids, null);
        for (final vb in got.values) {
          final k = vb.isAbsent ? 'absent' : (vb.isNumeric ? '${vb.asInt}' : 'tag${vb.rawTag}');
          rawReasons[k] = (rawReasons[k] ?? 0) + 1;
        }
      }
    }
    final opticsShapes = <String>[];
    if (profile.readsVsolTables && online.isNotEmpty) {
      final o = online.first;
      final base = o.technology == VsolPonTechnology.gpon ? vsolGponOptics : vsolEponOptics;
      final got = await _getAll(snmp, [for (final c in const [7, 6, 3, 4]) '$base.$c.${_suffix(o)}'], null,
          perGet: _vsolOpticsPerGet, parallel: 1);
      for (final c in const [7, 6, 3, 4]) {
        opticsShapes.add(_shape(got['$base.$c.${_suffix(o)}']));
      }
    }
    return FiberOltCaps(
      vendor: profile.vendor.name,
      model: profile.model,
      onus: onus.length,
      online: onus.where((o) => o.online).length,
      epon: onus.where((o) => o.technology == VsolPonTechnology.epon).length,
      gpon: onus.where((o) => o.technology == VsolPonTechnology.gpon).length,
      lastChange: '${changes.length}/${sample.length}',
      optics: profile.readsBdcomEponTables ? 'bdcom' : '${optics.length}/${online.length}',
      opticsShapes: opticsShapes,
      reasons: '${reasons.length}/${offline.length}',
      rawReasons: rawReasons,
      probedAt: at,
    );
  }

  /// شكل القيمة لا محتواها: «int:-2135» للأعداد، و«str:"-21.35(dBm)"» للنصّ الرقميّ وحده، وطول النصّ لغيره.
  static String _shape(Varbind? vb) {
    if (vb == null) return 'none';
    if (vb.isAbsent) return 'absent';
    if (vb.isNumeric) return 'int:${vb.asInt}';
    if (vb.rawTag != 0x04) return 'tag${vb.rawTag}';
    final s = utf8.decode(vb.rawBytes, allowMalformed: true).trim();
    if (RegExp(r'^[-−]?\d{1,5}([.,]\d{1,4})?\s*(\(?\s*(dbm|v|c|°c|ma|mw|uw)\s*\)?)?$', caseSensitive: false).hasMatch(s)) {
      return 'str:"$s"';
    }
    // صيغة النصّ مقنّعة: الأرقام 9 والحروف x إلّا الوحدات (‎0.0070 mW(-21.55dBm) ⇒ ‎9.9999 mW(-99.99dBm)) — نعرف كيف
    // يكتب الجهاز القيمة بلا القيمة نفسها، ولا يتسرّب نصٌّ حرّ (اسمٌ أو وصف) إن جاء العمود بغير المتوقَّع.
    const units = {'mw', 'dbm', 'uw', 'µw', 'c', 'v', 'ma', 'mv', 'na'};
    final masked = s
        .replaceAll(RegExp(r'\d'), '9')
        .replaceAllMapped(RegExp(r'[^\W\d_]+', unicode: true),
            (m) => units.contains(m[0]!.toLowerCase()) ? m[0]! : 'x' * m[0]!.length)
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
    return 'fmt:"${masked.length > 28 ? masked.substring(0, 28) : masked}"';
  }
}

/// ما يدعمه أولتٌ من قراءات الألياف (بلا هويّات) — يُرفع للخادم ويُعرض للوكيل «هذا الأولت لا يعطي…».
@immutable
class FiberOltCaps {
  const FiberOltCaps({
    required this.vendor,
    required this.onus,
    required this.online,
    required this.epon,
    required this.gpon,
    required this.lastChange,
    required this.optics,
    required this.opticsShapes,
    required this.reasons,
    required this.rawReasons,
    required this.probedAt,
    this.model,
  });

  final String vendor;
  final String? model;
  final int onus, online, epon, gpon;

  /// «مُجاب/مسؤول» لكلّ قراءة في العيّنة.
  final String lastChange, optics, reasons;
  final List<String> opticsShapes;
  final Map<String, int> rawReasons;
  final DateTime probedAt;

  static bool _some(String frac) {
    final p = frac.split('/');
    return p.length == 2 && (int.tryParse(p[0]) ?? 0) > 0;
  }

  bool get hasLastChange => _some(lastChange);
  bool get hasOptics => optics == 'bdcom' || _some(optics);
  bool get hasReasons => _some(reasons);

  Map<String, dynamic> toJson() => {
        'vendor': vendor,
        'model': model,
        'onus': onus,
        'online': online,
        'epon': epon,
        'gpon': gpon,
        'last_change': lastChange,
        'optics': optics,
        'optics_shapes': opticsShapes,
        'reasons': reasons,
        'raw_reasons': rawReasons,
        'probed_at': probedAt.toUtc().toIso8601String(),
      };
}
