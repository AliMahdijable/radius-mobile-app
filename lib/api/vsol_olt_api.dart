import 'package:flutter/foundation.dart';

import 'snmp_client.dart';

/// طبقة قراءةٍ لـ**OLT من VSOL** (سلسلة V1600D) عبر SNMP v2c.
///
/// **لماذا SNMP وحده هنا؟**
/// لأنّ الجهاز يكشف **كلّ ONU كواجهةٍ مستقلّة** في `IF-MIB`:
///
/// ```
///   GE0/1 … GE0/8        منافذ الصعود
///   EPON0/1 … EPON0/4    منافذ PON بعدّاداتها الإجماليّة
///   EPON0/3:2            ← ONU رقم ٢ على منفذ PON الثالث
/// ```
///
/// فمسحةٌ واحدة تعطي حالة كلّ المشتركين وسرعتهم وعناوينهم وترفكهم —
/// وهذا أسرع بكثيرٍ من جلسة Telnet لكلّ جهاز.
///
/// **وما لا يعطيه SNMP على هذا الجهاز** — فحصتُه على جهازٍ فعليّ
/// ٢٠٢٦-٠٩-٢٨، ولم أستنتجه من توثيق:
///   • القدرة الضوئيّة والحرارة والجهد (`show onu N ctc opm_diag`)
///   • المصنّع والطراز وإصدار البرنامج (`show onu baisc-info all`)
///   • المسافة (`show onu N rtt`)
///
/// وMIB المؤسّسة (‏`.1.3.6.1.4.1.2162`) شبه فارغ: جدول الـcommunity
/// وحده. وفحصتُ `ENTITY-SENSOR` و`ENTITY-MIB` و`OPTIF` فكلّها غائبة.
/// فمن أراد القدرة الضوئيّة فطريقه Telnet لا غير — وتلك مرحلةٌ ثانية
/// تُستدعى عند فتح ONU بعينه لا في النبضة الدوريّة.
class VsolOltApi {
  VsolOltApi._();

  static const String _oidSysDescr = '1.3.6.1.2.1.1.1.0';
  static const String _oidSysName = '1.3.6.1.2.1.1.5.0';
  static const String _oidSysUpTime = '1.3.6.1.2.1.1.3.0';

  static const String _oidIfDescr = '1.3.6.1.2.1.2.2.1.2';
  static const String _oidIfOper = '1.3.6.1.2.1.2.2.1.8';
  static const String _oidIfPhys = '1.3.6.1.2.1.2.2.1.6';
  static const String _oidIfHighSpeed = '1.3.6.1.2.1.31.1.1.1.15';
  static const String _oidIfHCIn = '1.3.6.1.2.1.31.1.1.1.6';
  static const String _oidIfHCOut = '1.3.6.1.2.1.31.1.1.1.10';

  /// لقطةٌ كاملة. يرمي [VsolException] حين يتعذّر الاتّصال.
  static Future<VsolOltStats> fetchStats({
    required String host,
    int port = 161,
    required String community,
    Duration timeout = const Duration(seconds: 5),
    void Function(VsolOltStats partial)? onPartialReady,
  }) async {
    final snmp = SnmpV2c(
      host: host,
      port: port,
      community: community,
      timeout: timeout,
    );

    String? descr, name;
    Duration? uptime;
    try {
      for (final vb
          in await snmp.get([_oidSysDescr, _oidSysName, _oidSysUpTime])) {
        if (vb.oid == _oidSysDescr) descr = vb.asString;
        if (vb.oid == _oidSysName) name = vb.asString;
        if (vb.oid == _oidSysUpTime) {
          final t = vb.asInt;
          if (t > 0) uptime = Duration(milliseconds: t * 10);
        }
      }
      // ⚡ الهويّة أوّلاً: اللوحة تعرض الطراز ومدّة التشغيل بلا انتظار
      // مسح الواجهات، وهو الجزء الثقيل (‏٣٨ واجهة × ستّة أعمدة).
      onPartialReady?.call(VsolOltStats(
        sysDescr: descr,
        sysName: name,
        uptime: uptime,
      ));
    } on SnmpException catch (e) {
      throw VsolException('تعذّر الاتّصال بالـOLT عبر SNMP: $e\n'
          'تحقّق:\n'
          '• الـcommunity "$community" صحيحة\n'
          '• المنفذ $port مفتوح (UDP)\n'
          '• SNMP مفعّل على الجهاز');
    }

    final rows = await _readIfTable(snmp);
    final parsed = VsolParse.build(rows);

    if (kDebugMode) {
      debugPrint('══════ VSOL OLT ══════');
      debugPrint('  ${descr ?? "?"} / ${name ?? "?"} · ${uptime?.inDays}d');
      debugPrint('  uplinks ${parsed.uplinks.length} · '
          'pon ${parsed.ponPorts.length} · onu ${parsed.onus.length} '
          '(${parsed.onusOnline} متّصل)');
      debugPrint('══════════════════════');
    }

    return VsolOltStats(
      sysDescr: descr,
      sysName: name,
      uptime: uptime,
      uplinks: parsed.uplinks,
      ponPorts: parsed.ponPorts,
      onus: parsed.onus,
    );
  }

  /// يقرأ جدول الواجهات مع تحمّل الأخطاء الجزئيّة.
  ///
  /// ⚠️ المسح يتوقّف عند أوّل `genErr` فيُسقط ما بعده — وهي المصيدة
  /// نفسها التي أفقدتنا ترفك روجي كلّه. فحين يرجع عمودٌ فارغاً نسأل
  /// كلّ فهرسٍ وحده ونتجاوز من يفشل.
  static Future<List<VsolIfRow>> _readIfTable(SnmpV2c snmp) async {
    Future<List<Varbind>> safeWalk(String base) async {
      try {
        return await snmp.walk(base, chunkSize: 25);
      } catch (_) {
        return const [];
      }
    }

    final descrs = await safeWalk(_oidIfDescr);
    final byIdx = <int, String>{};
    for (final vb in descrs) {
      final i = _lastIndex(vb.oid, _oidIfDescr);
      if (i != null) byIdx[i] = vb.asString.trim();
    }
    if (byIdx.isEmpty) return const [];

    Future<Map<int, Varbind>> column(String base) async {
      var vbs = await safeWalk(base);
      if (vbs.isEmpty) {
        final got = <Varbind>[];
        for (final i in byIdx.keys) {
          try {
            final r = await snmp.get(['$base.$i']);
            if (r.isNotEmpty) got.add(r.first);
          } catch (_) {/* هذه الواجهة لا تجيب — نتجاوزها */}
        }
        vbs = got;
      }
      final m = <int, Varbind>{};
      for (final vb in vbs) {
        final i = _lastIndex(vb.oid, base);
        if (i != null) m[i] = vb;
      }
      return m;
    }

    final oper = await column(_oidIfOper);
    final phys = await column(_oidIfPhys);
    final speed = await column(_oidIfHighSpeed);
    final inOct = await column(_oidIfHCIn);
    final outOct = await column(_oidIfHCOut);

    final out = <VsolIfRow>[];
    for (final i in byIdx.keys.toList()..sort()) {
      out.add(VsolIfRow(
        index: i,
        name: byIdx[i]!,
        up: oper[i]?.asInt == 1,
        mac: _macOf(phys[i]),
        speedMbps: speed[i]?.asInt ?? 0,
        rxBytes: inOct[i]?.asInt ?? 0,
        txBytes: outOct[i]?.asInt ?? 0,
      ));
    }
    return out;
  }

  static int? _lastIndex(String oid, String base) {
    if (!oid.startsWith('$base.')) return null;
    final rest = oid.substring(base.length + 1);
    final dot = rest.indexOf('.');
    return int.tryParse(dot >= 0 ? rest.substring(0, dot) : rest);
  }

  /// عنوان MAC من **البايتات الخام** لا من النصّ.
  ///
  /// 🐛 ٢٠٢٦-٠٩-٢٨ — قرأتُه أوّلاً عبر `asString`، وهي تُحوّل
  /// `OCTET STRING` بـ`String.fromCharCodes`. فبايتاتٌ مثل
  /// `7C 6A 60 0E 08 07` تصير محارف تحكّمٍ ورموزاً (`|j\u0060`)
  /// لا عنواناً. والمشغّل يُطابق هذا العنوان بما في نظام الفوترة،
  /// فالتشويه يجعله بلا قيمة.
  ///
  /// ونُصفّر البادئة: `7c:6a:60:0e:08:07` لا `7c:6a:60:e:8:7` —
  /// الصيغة الأولى هي ما يُكتب في كلّ نظامٍ آخر.
  static String? _macOf(Varbind? vb) {
    if (vb == null || vb.isAbsent) return null;
    final b = vb.rawBytes;
    if (b.length != 6) return null;
    return b
        .map((x) => x.toRadixString(16).padLeft(2, '0'))
        .join(':');
  }
}

// ═══════════════════════════════════════════════════════════
// التحليل — خالصٌ وقابلٌ للاختبار بلا شبكة
// ═══════════════════════════════════════════════════════════

/// صفٌّ خامٌّ من `IF-MIB` قبل التصنيف.
///
/// عامٌّ عمداً: التصنيف هو قلب هذه الطبقة وأكثر ما يُخطئ فيه، فيجب
/// أن يُختبَر بلقطاتٍ مركّبةٍ بلا شبكةٍ ولا جهاز.
@immutable
class VsolIfRow {
  const VsolIfRow({
    required this.index,
    required this.name,
    required this.up,
    required this.mac,
    required this.speedMbps,
    required this.rxBytes,
    required this.txBytes,
  });
  final int index;
  final String name;
  final bool up;
  final String? mac;
  final int speedMbps, rxBytes, txBytes;
}

class VsolParse {
  VsolParse._();

  /// `EPON0/3:2` → منفذ PON ‏3 و ONU ‏2. و`EPON0/3` → منفذ PON وحده.
  /// و`GE0/5` → منفذ صعود. وما لا يُطابق يُهمَل.
  ///
  /// نلتقط الشرطة المائلة والنقطتين بتعبيرٍ واحد كيلا نُصنّف
  /// `EPON0/3` ONU رقم صفر — وهو ما يُفسد عدّ المشتركين.
  static final RegExp _rePon = RegExp(r'^EPON(\d+)/(\d+)(?::(\d+))?$',
      caseSensitive: false);
  static final RegExp _reUplink =
      RegExp(r'^(?:GE|XGE|TE)(\d+)/(\d+)$', caseSensitive: false);

  static ({
    List<VsolUplink> uplinks,
    List<VsolPonPort> ponPorts,
    List<VsolOnu> onus,
    int onusOnline,
  }) build(List<VsolIfRow> rows) {
    final uplinks = <VsolUplink>[];
    final pons = <String, VsolPonPort>{};
    final onus = <VsolOnu>[];

    for (final r in rows) {
      final pon = _rePon.firstMatch(r.name);
      if (pon != null) {
        final slot = int.parse(pon.group(1)!);
        final port = int.parse(pon.group(2)!);
        final onuId = pon.group(3);
        final portKey = '$slot/$port';
        if (onuId == null) {
          pons[portKey] = VsolPonPort(
            slot: slot,
            port: port,
            up: r.up,
            rxBytes: r.rxBytes,
            txBytes: r.txBytes,
          );
        } else {
          onus.add(VsolOnu(
            ifIndex: r.index,
            slot: slot,
            ponPort: port,
            onuId: int.parse(onuId),
            online: r.up,
            // ⚠️ العنوان يُقرأ **للمتّصل وحده**.
            //
            // فحصتُ الثلاثة عشر المتّصلة على جهازٍ فعليّ وقارنتُها بما
            // يعرضه `show onu baisc-info all`: تطابقٌ تامّ. أمّا
            // المفصولة فيُرجع لها الجهاز عنواناً **قديماً مكرّراً** —
            // رأيتُ `EPON0/1:1` المفصول يحمل عنوان `EPON0/2:9`
            // المتّصل. وعرضُ عنوان مشتركٍ أمام اسم مشتركٍ آخر أسوأ من
            // ألّا نعرض شيئاً: المشغّل يُطابقه بنظام الفوترة ويبني
            // عليه قراراً.
            mac: r.up ? r.mac : null,
            speedMbps: r.speedMbps,
            rxBytes: r.rxBytes,
            txBytes: r.txBytes,
          ));
        }
        continue;
      }
      if (_reUplink.hasMatch(r.name)) {
        uplinks.add(VsolUplink(
          name: r.name,
          up: r.up,
          speedMbps: r.speedMbps,
          rxBytes: r.rxBytes,
          txBytes: r.txBytes,
        ));
      }
    }

    onus.sort((a, b) {
      final c = a.ponPort.compareTo(b.ponPort);
      return c != 0 ? c : a.onuId.compareTo(b.onuId);
    });
    final ports = pons.values.toList()
      ..sort((a, b) => a.port.compareTo(b.port));

    // عدد الـONU على كلّ منفذ — يُحسب هنا لا في الواجهة، فالواجهة
    // تُعيد الرسم كثيراً والعدّ ثابتٌ ما دامت اللقطة واحدة.
    final counted = ports.map((p) {
      final mine = onus.where((o) => o.slot == p.slot && o.ponPort == p.port);
      return p.withCounts(
        onuTotal: mine.length,
        onuOnline: mine.where((o) => o.online).length,
      );
    }).toList();

    return (
      uplinks: uplinks,
      ponPorts: counted,
      onus: onus,
      onusOnline: onus.where((o) => o.online).length,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// النماذج
// ═══════════════════════════════════════════════════════════

@immutable
class VsolUplink {
  const VsolUplink({
    required this.name,
    required this.up,
    required this.speedMbps,
    required this.rxBytes,
    required this.txBytes,
  });
  final String name;
  final bool up;
  final int speedMbps, rxBytes, txBytes;
}

@immutable
class VsolPonPort {
  const VsolPonPort({
    required this.slot,
    required this.port,
    required this.up,
    required this.rxBytes,
    required this.txBytes,
    this.onuTotal = 0,
    this.onuOnline = 0,
  });
  final int slot, port;
  final bool up;
  final int rxBytes, txBytes, onuTotal, onuOnline;

  String get label => 'EPON$slot/$port';

  VsolPonPort withCounts({required int onuTotal, required int onuOnline}) =>
      VsolPonPort(
        slot: slot,
        port: port,
        up: up,
        rxBytes: rxBytes,
        txBytes: txBytes,
        onuTotal: onuTotal,
        onuOnline: onuOnline,
      );
}

@immutable
class VsolOnu {
  const VsolOnu({
    required this.ifIndex,
    required this.slot,
    required this.ponPort,
    required this.onuId,
    required this.online,
    this.mac,
    this.speedMbps = 0,
    this.rxBytes = 0,
    this.txBytes = 0,
  });

  final int ifIndex, slot, ponPort, onuId;
  final bool online;
  final String? mac;
  final int speedMbps, rxBytes, txBytes;

  /// كما يكتبه المشغّل ويقرؤه في الـCLI: `EPON0/3:2`.
  String get label => 'EPON$slot/$ponPort:$onuId';
}

@immutable
class VsolOltStats {
  const VsolOltStats({
    this.sysDescr,
    this.sysName,
    this.uptime,
    this.uplinks = const [],
    this.ponPorts = const [],
    this.onus = const [],
  });

  final String? sysDescr, sysName;
  final Duration? uptime;
  final List<VsolUplink> uplinks;
  final List<VsolPonPort> ponPorts;
  final List<VsolOnu> onus;

  int get onusOnline => onus.where((o) => o.online).length;
  int get onusTotal => onus.length;
  int get ponUp => ponPorts.where((p) => p.up).length;

  /// إجماليّ ترفك **منافذ PON** لا مجموع الـONU.
  ///
  /// ⚠️ جمع الـONU يعدّ البايت مرّتين: ما يمرّ على ONU يمرّ على منفذ
  /// PON الذي يحمله. وهي العلّة نفسها التي أبلغ عنها المستخدم في لوحة
  /// روجي ٢٠٢٦-٠٩-٢٨.
  int get ponRxBytes => ponPorts.fold(0, (s, p) => s + p.rxBytes);
  int get ponTxBytes => ponPorts.fold(0, (s, p) => s + p.txBytes);

  bool get isEmpty => onus.isEmpty && ponPorts.isEmpty && uplinks.isEmpty;
}

class VsolException implements Exception {
  VsolException(this.message);
  final String message;
  @override
  String toString() => message;
}
