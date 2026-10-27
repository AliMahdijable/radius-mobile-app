import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/fiber/fiber_band.dart';
import '../services/fiber/fiber_onu.dart';
import 'bdcom_epon.dart';
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

  /// صفّ الضوء لـONU واحدة من أعمدة VSOL.
  static BdcomOnuReading? vsolReading(Varbind? rx, Varbind? tx, Varbind? temp, Varbind? volt) {
    final r = rx == null ? null : scaled(rx, lo: -45, hi: 10);
    final reading = BdcomOnuReading(
      rxDbm: FiberBands.plausible(r) ? r : null,
      txDbm: tx == null ? null : scaled(tx, lo: -15, hi: 12),
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

  static Future<Map<String, Varbind>> _getAll(SnmpV2c snmp, List<String> oids, bool Function()? cancelled) async {
    final out = <String, Varbind>{};
    for (var s = 0; s < oids.length; s += _perGet) {
      if (cancelled?.call() == true) break;
      try {
        for (final vb in await snmp.get(oids.skip(s).take(_perGet).toList())) {
          out[vb.oid] = vb;
        }
      } catch (_) {
        // دفعةٌ لا تجيب — نتجاوزها ولا نُسقط البقيّة.
      }
    }
    return out;
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
    final got = await _getAll(snmp, oids, isCancelled);
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
    for (var s = 0; s < want.length; s += _perGet - 1) {
      if (isCancelled?.call() == true) break;
      final chunk = want.skip(s).take(_perGet - 1).toList();
      List<Varbind> vbs;
      try {
        vbs = await snmp.get([sysUpTimeOid, for (final i in chunk) '$ifLastChangeOid.$i']);
      } catch (_) {
        continue;
      }
      final at = now ?? DateTime.now();
      final by = {for (final v in vbs) v.oid: v};
      final up = by[sysUpTimeOid];
      if (up == null || up.isAbsent || !up.isNumeric) continue;
      for (final i in chunk) {
        final vb = by['$ifLastChangeOid.$i'];
        if (vb == null || vb.isAbsent || !vb.isNumeric) continue;
        final t = changedAt(upTicks: up.asInt, lastChangeTicks: vb.asInt, now: at);
        if (t != null) out[i] = t;
      }
    }
    return out;
  }

  /// أسماء الأجهزة كما كتبها الوكيل: ifAlias، ووصف VSOL EPON. الفارغ لا يُعاد.
  static Future<Map<int, String>> names(
    SnmpV2c snmp,
    OltProfile profile,
    Iterable<VsolOnu> onus, {
    bool Function()? isCancelled,
  }) async {
    final list = onus.toList();
    final out = <int, String>{};
    String? text(Varbind? vb) {
      if (vb == null || vb.isAbsent || vb.rawTag != 0x04) return null;
      // UTF-8 (أسماءٌ عربيّة)، بلا حروف تحكّم.
      final s = utf8.decode(vb.rawBytes, allowMalformed: true).replaceAll(RegExp(r'[\x00-\x1F\x7F�]'), '').trim();
      if (s.isEmpty || s.length > 64 || RegExp(r'^(onu|epon|gpon)[\d/:._-]*$', caseSensitive: false).hasMatch(s)) return null;
      return s;
    }

    final alias = await _getAll(snmp, [for (final o in list) '$ifAliasOid.${o.ifIndex}'], isCancelled);
    for (final o in list) {
      final s = text(alias['$ifAliasOid.${o.ifIndex}']);
      if (s != null) out[o.ifIndex] = s;
    }
    if (profile.readsVsolTables) {
      final epon = [
        for (final o in list)
          if (o.technology == VsolPonTechnology.epon && o.slot == 0 && !out.containsKey(o.ifIndex)) o,
      ];
      final got = await _getAll(snmp, [for (final o in epon) '$vsolEponAuth.9.${_suffix(o)}'], isCancelled);
      for (final o in epon) {
        final s = text(got['$vsolEponAuth.9.${_suffix(o)}']);
        if (s != null) out[o.ifIndex] = s;
      }
    }
    return out;
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

    final changes = await lastChanges(snmp, sample.map((o) => o.ifIndex), now: at);
    final optics = profile.readsVsolTables ? await vsolOptics(snmp, online) : const <int, BdcomOnuReading>{};
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
      final got = await _getAll(snmp, [for (final c in const [7, 6, 3, 4]) '$base.$c.${_suffix(o)}'], null);
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
    return 'str(len=${s.length})';
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
