import 'package:flutter/foundation.dart';

import 'snmp_client.dart';

/// قراءات مصنّع **BDCOM EPON** — جداول `NMS-EPON-ONU` و`BDCOM-PROCESS-MIB`
/// و`NMS-CHASSIS`.
///
/// ثبتت كلّها حيّاً على P3600-04 ‏(تدقيقٌ بالقراءة وحدها ٢٠ أكتوبر:
/// GET/GETBULK بلا تعديل إعداد). وكلّ لاحقةٍ هنا هي `llidIfIndex` — فهرس
/// الـONU نفسه في IF-MIB ‏(`EPON0/1:1` ← 97)، لا رقم الـONU الظاهر.
///
/// ⚠️ **ماك الـONU من هنا وحده.** `ifPhysAddress` على هذا الجهاز عنوان
/// واجهةٍ محلّيّ: ثلاثة عناوين فقط تتكرّر على ٨٦ ONU، ولا يطابق واحدٌ منها
/// ماك الـONU في جدول المصنّع (٠ من ٨٦). فعرضُه «ماكاً» كان يُري المشغّل
/// العنوان نفسه أمام مشتركين كثيرين — بلاغ المالك: «يظهر ماكات متشابهة
/// وليس ماكات اليوزرية».
///
/// ⚠️ وماك الـONU ليس ماك راوتر المشترك: أجهزة المشترك خلف الـONU تأتي من
/// جدول الجسر ([BridgeFdb])، وهي قائمةٌ أخرى بعنوانٍ آخر.
///
/// ⚠️ BDCOM GPON لم يُختبر حيّاً — فلا تُعمَّم هذه الأعمدة عليه.
class BdcomEpon {
  BdcomEpon._();

  // ── NMS-EPON-ONU ─────────────────────────────────────────────────
  /// `onuMacAddr` — **العمود وحده**: الأعمدة المجاورة له في الجدول نفسه
  /// تحمل communities، فلا يُمسح الجدول ولا يُطلب ما بعد العمود. نسأل
  /// بـGET على فهارس نعرفها من IF-MIB، فلا يصل إلينا عمودٌ آخر أصلاً.
  static const onuMacOid = '1.3.6.1.4.1.3320.101.10.4.1.1';

  /// `onuID` — احتياطٌ موثَّق للعنوان نفسه حين يغيب الأوّل.
  static const onuIdOid = '1.3.6.1.4.1.3320.101.10.1.1.3';

  /// صانع الـONU (`HWTC`…) ورمز وحدته (`145C` — كود وحدةٍ لا اسم طرازٍ
  /// تسويقيّ).
  static const vendorOid = '1.3.6.1.4.1.3320.101.10.1.1.1';
  static const moduleOid = '1.3.6.1.4.1.3320.101.10.1.1.2';

  /// القدرة الضوئيّة عند الـONU بوحدة ٠٫١ dBm ‏(MIB): ‏‎-135 ← ‎-13.5.
  /// والقيمة لوغاريتميّة أصلاً — لا `log10` عليها ثانيةً.
  static const rxOid = '1.3.6.1.4.1.3320.101.10.5.1.5';
  static const txOid = '1.3.6.1.4.1.3320.101.10.5.1.6';

  /// حرارة وحدة الـONU (‏÷٢٥٦ ‏°C) وجهدها (‏×٠٫٠٠٠١ V).
  static const tempOid = '1.3.6.1.4.1.3320.101.10.5.1.2';
  static const voltOid = '1.3.6.1.4.1.3320.101.10.5.1.3';

  // ── الهيكل ───────────────────────────────────────────────────────
  /// متوسّط انشغال المعالج لخمس ثوانٍ ٪ (‏BDCOM-PROCESS-MIB) — جدولٌ
  /// تُكتشف لاحقاته، لا `.1` مفروضةً على كلّ طراز.
  static const cpuTableOid = '1.3.6.1.4.1.3320.9.109.1.1.1.1.3';

  /// `nmsBoxTemp` — حرارة داخل الصندوق، لا حرارة ONU.
  static const boxTempOid = '1.3.6.1.4.1.3320.3.6.14.0';

  /// `nmsprocessorRam` — إجماليّ الذاكرة **بالبايت** (256MiB على P3600-04).
  ///
  /// ⚠️ لا من `hrMemorySize`: يُرجع الرقم نفسه موسوماً KBytes، فيصير
  /// ٢٥٦ جيجا. ولا نسبة استخدام: used/free غير متوفّرين على البرمجيّة
  /// المفحوصة، والنسبة لا تُستنتج من الإجماليّ وحده.
  static const ramTotalOid = '1.3.6.1.4.1.3320.3.6.5.0';

  /// كم OID في طلب GET واحد — دون MTU مع هوامش العناوين.
  static const _perGet = 16;

  /// ماك كلّ ONU من [ifIndexes] — من `onuMacAddr` ثمّ `onuID` لما غاب.
  /// يُرجع ما ثبت وحده؛ والغائب لا يُملأ بشيء.
  static Future<Map<int, String>> onuMacs(
    SnmpV2c snmp,
    Iterable<int> ifIndexes, {
    bool Function()? isCancelled,
  }) async {
    final want = ifIndexes.toSet().toList()..sort();
    final out = <int, String>{};
    await _getColumn(snmp, onuMacOid, want, isCancelled, (i, vb) {
      final m = macFrom(vb);
      if (m != null) out[i] = m;
    });
    final missing = [for (final i in want) if (!out.containsKey(i)) i];
    if (missing.isNotEmpty) {
      await _getColumn(snmp, onuIdOid, missing, isCancelled, (i, vb) {
        final m = macFrom(vb);
        if (m != null) out[i] = m;
      });
    }
    return out;
  }

  /// قراءات الضوء للـONU المتّصلة: القدرة والحرارة والجهد.
  ///
  /// للمتّصل وحده: المفصول يُرجع `NoSuchInstance` (لا صفراً)، وسؤاله
  /// مهلةٌ بلا فائدة.
  static Future<Map<int, BdcomOnuReading>> readings(
    SnmpV2c snmp,
    Iterable<int> ifIndexes, {
    bool Function()? isCancelled,
  }) =>
      _rows(snmp, ifIndexes, const [rxOid, txOid, tempOid, voltOid], isCancelled,
          (i, v) => BdcomOnuReading(
                rxDbm: dbmFrom(v['$rxOid.$i']),
                txDbm: dbmFrom(v['$txOid.$i']),
                tempC: onuTempFrom(v['$tempOid.$i']),
                voltV: voltFrom(v['$voltOid.$i']),
              ));

  /// صانع الـONU ورمز وحدته — لا يتغيّران إلّا باستبدال الوحدة، فيُقرآن
  /// مع الماكات على الإيقاع البطيء.
  static Future<Map<int, BdcomOnuReading>> identities(
    SnmpV2c snmp,
    Iterable<int> ifIndexes, {
    bool Function()? isCancelled,
  }) =>
      _rows(snmp, ifIndexes, const [vendorOid, moduleOid], isCancelled,
          (i, v) => BdcomOnuReading(
                vendor: textFrom(v['$vendorOid.$i']),
                module: textFrom(v['$moduleOid.$i']),
              ));

  static Future<Map<int, BdcomOnuReading>> _rows(
    SnmpV2c snmp,
    Iterable<int> ifIndexes,
    List<String> cols,
    bool Function()? isCancelled,
    BdcomOnuReading Function(int ifIndex, Map<String, Varbind> byOid) build,
  ) async {
    final want = ifIndexes.toSet().toList()..sort();
    final per = (_perGet / cols.length).floor().clamp(1, _perGet);
    final out = <int, BdcomOnuReading>{};
    for (var s = 0; s < want.length; s += per) {
      if (isCancelled?.call() == true) break;
      final chunk = want.skip(s).take(per).toList();
      List<Varbind> vbs;
      try {
        vbs = await snmp.get([
          for (final i in chunk)
            for (final c in cols) '$c.$i',
        ]);
      } catch (_) {
        continue; // هذه الدفعة لا تجيب — نتجاوزها ولا نُسقط البقيّة
      }
      final byOid = {for (final v in vbs) v.oid: v};
      for (final i in chunk) {
        final r = build(i, byOid);
        if (!r.isEmpty) out[i] = r;
      }
    }
    return out;
  }

  /// المعالج والحرارة وإجماليّ الذاكرة. ما لا يُجاب يبقى `null`.
  static Future<BdcomChassis> chassis(SnmpV2c snmp) async {
    int? cpu;
    try {
      cpu = cpuFrom(await snmp.walk(cpuTableOid, chunkSize: 8, maxIterations: 2));
    } catch (_) {/* غائب */}
    int? boxTemp;
    int? ram;
    try {
      for (final vb in await snmp.get([boxTempOid, ramTotalOid])) {
        if (vb.oid == boxTempOid) boxTemp = boxTempFrom(vb);
        if (vb.oid == ramTotalOid) ram = ramFrom(vb);
      }
    } catch (_) {/* غائب */}
    return BdcomChassis(cpuPct: cpu, boxTempC: boxTemp, ramBytes: ram);
  }

  static Future<void> _getColumn(
    SnmpV2c snmp,
    String column,
    List<int> idx,
    bool Function()? isCancelled,
    void Function(int ifIndex, Varbind vb) onValue,
  ) async {
    for (var s = 0; s < idx.length; s += _perGet) {
      if (isCancelled?.call() == true) return;
      final chunk = idx.skip(s).take(_perGet).toList();
      try {
        for (final vb in await snmp.get([for (final i in chunk) '$column.$i'])) {
          if (!vb.oid.startsWith('$column.')) continue;
          final i = int.tryParse(vb.oid.substring(column.length + 1));
          if (i != null) onValue(i, vb);
        }
      } catch (_) {/* دفعةٌ لا تجيب — البقيّة تُسأل */}
    }
  }

  // ═══════════════════════════════════════════════════════════
  // التحويل — خالصٌ وقابلٌ للاختبار
  // ═══════════════════════════════════════════════════════════

  /// ماكٌ من **البايتات الخام** (لا UTF-8): ستّة بايتات، لا صفريّة ولا
  /// بثّ ولا جماعيّة.
  @visibleForTesting
  static String? macFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || vb.rawTag != 0x04) return null;
    return macOfBytes(vb.rawBytes);
  }

  static String? macOfBytes(List<int> b) {
    if (b.length != 6) return null;
    if (b.every((v) => v == 0) || b.every((v) => v == 0xff)) return null;
    if (b.first & 1 == 1) return null; // جماعيّ — لا يكون عنوان جهاز
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(':');
  }

  /// ٠٫١ dBm ← dBm، أو `null` للغائب وما خرج عن مدى الضوء المعقول. (تقرأ به شبكة الألياف عمود الضوء كاملاً أيضاً.)
  static double? dbmFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt / 10.0;
    return (v < -60 || v > 15) ? null : v;
  }

  /// ÷٢٥٦ ← °C ‏(11776 ← 46).
  @visibleForTesting
  static double? onuTempFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt / 256.0;
    return (v < -40 || v > 125) ? null : v;
  }

  /// ×٠٫٠٠٠١ ← V ‏(33170 ← 3.317).
  @visibleForTesting
  static double? voltFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt * 0.0001;
    return (v <= 0 || v > 10) ? null : v;
  }

  @visibleForTesting
  static String? textFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || vb.rawTag != 0x04) return null;
    final t = String.fromCharCodes(vb.rawBytes.where((c) => c >= 0x20 && c < 0x7f)).trim();
    if (t.isEmpty || t.toUpperCase() == 'N/A') return null;
    return t;
  }

  /// أوّل نسبةٍ صالحة في جدول المعالج (‏Gauge32 أو INTEGER، ٠..١٠٠).
  @visibleForTesting
  static int? cpuFrom(List<Varbind> vbs) {
    for (final vb in vbs) {
      if (!vb.oid.startsWith('$cpuTableOid.') || vb.isAbsent || !vb.isNumeric) {
        continue;
      }
      final v = vb.asInt;
      if (v >= 0 && v <= 100) return v;
    }
    return null;
  }

  /// حرارة الصندوق — عددٌ صحيح بمدى تشغيلٍ معقول.
  @visibleForTesting
  static int? boxTempFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt;
    return (v < -20 || v > 110) ? null : v;
  }

  @visibleForTesting
  static int? ramFrom(Varbind? vb) {
    if (vb == null || vb.isAbsent || !vb.isNumeric) return null;
    final v = vb.asInt;
    // بين ١٦ ميجا و٦٤ جيجا بالبايت — خارجها وحدةٌ أخرى لا قراءة.
    return (v < 16 * 1024 * 1024 || v > 64 * 1024 * 1024 * 1024) ? null : v;
  }
}

/// قراءات ONU واحدة عند لحظةٍ واحدة. ما لم يُجب `null` — لا صفر.
@immutable
class BdcomOnuReading {
  const BdcomOnuReading({
    this.rxDbm,
    this.txDbm,
    this.tempC,
    this.voltV,
    this.vendor,
    this.module,
  });

  final double? rxDbm, txDbm, tempC, voltV;
  final String? vendor, module;

  bool get isEmpty =>
      rxDbm == null &&
      txDbm == null &&
      tempC == null &&
      voltV == null &&
      vendor == null &&
      module == null;
}

/// قراءات الهيكل. ما لم يُجب `null`.
@immutable
class BdcomChassis {
  const BdcomChassis({this.cpuPct, this.boxTempC, this.ramBytes});
  final int? cpuPct;
  final int? boxTempC;

  /// الإجماليّ وحده — لا نسبة استخدام (انظر [BdcomEpon.ramTotalOid]).
  final int? ramBytes;

  bool get isEmpty => cpuPct == null && boxTempC == null && ramBytes == null;
}
