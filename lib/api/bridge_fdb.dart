import 'package:flutter/foundation.dart';

import 'snmp_client.dart';

/// **أجهزة المشترك خلف كلّ ONU** — من جدول الجسر القياسيّ (‏Q-BRIDGE-MIB
/// ثمّ BRIDGE-MIB احتياطاً)، لا من ماك الواجهة ولا من ماك الـONU.
///
/// المسار مثبتٌ حيّاً على BDCOM P3600-04 ‏(٢٠ أكتوبر، قراءةٌ وحدها): ‏٤٠
/// عنواناً متعلَّماً، ‏٣٩ منها على ٣٩ ONU وواحدٌ على منفذ صعود — وكلّها
/// غير ماكات وحدات الـONU نفسها.
///
///   `dot1qTpFdbPort.<fdbId>.<m1..m6>` = منفذ الجسر
///   `dot1qTpFdbStatus.<…>`            = 3 learned (وحدها تُعدّ)
///   `dot1dBasePortIfIndex.<bridgePort>` = ifIndex
///
/// القواعد — وكلٌّ منها مصيدةٌ معروفة:
///   · **الربط عبر الجدول دائماً.** ‏`bridgePort = ifIndex` صادف تساويهما
///     على هذا الجهاز، ولا يصحّ افتراضه — وبلا جدول ربطٍ لا نُسند شيئاً.
///   · **مفتاح الصفّ من الـOID نفسه** لا من ترتيب الصفوف ولا آخر رقم:
///     عمودا المنفذ والحالة يُقرآن معاً في الردّ الواحد، فلا ينزاح صفٌّ
///     تعلّمه الجهاز أو نسيه بين مسحتين.
///   · `fdbId` سياق الجدول لا رقم VLAN — لا يُعرض VLAN منه.
///   · لا عناوين الصعود ولا منفذ PON المشترك تحت أيّ مشترك: ما لا يربطه
///     الجدول بـONU بعينها لا يُوزَّع على أحد.
///   · عنوانٌ رآه المسح على ONU‏َين ملتبسٌ (انتقالٌ أو حلقة) — يُسقط.
///   · Q-BRIDGE أوّلاً، وBRIDGE-MIB **بديلاً لا إضافة**: الجمع يضاعف العدد.
///   · المسح الناقص لا يُقدَّم كاملاً، والقائمة الفارغة لا تُملأ بماك الـONU.
///     والجدول يعكس ما تعلّمه الجهاز الآن ويشيخ — فراغُه ليس «لا أجهزة».
class BridgeFdb {
  BridgeFdb._();

  static const basePortIfIndexOid = '1.3.6.1.2.1.17.1.4.1.2';
  static const qPortOid = '1.3.6.1.2.1.17.7.1.2.2.1.2';
  static const qStatusOid = '1.3.6.1.2.1.17.7.1.2.2.1.3';
  static const dPortOid = '1.3.6.1.2.1.17.4.3.1.2';
  static const dStatusOid = '1.3.6.1.2.1.17.4.3.1.3';

  /// الحالة المعدودة وحدها: `learned(3)`. لا `self(4)` ولا `mgmt(5)`.
  static const learned = 3;

  /// يقرأ الجدول ويُسند لكلّ ONU من [targets] (فهارسها في IF-MIB) أجهزتها.
  static Future<FdbSnapshot> fetch(
    SnmpV2c snmp, {
    required Set<int> targets,
    bool Function()? isCancelled,
    Duration budget = const Duration(seconds: 45),
  }) async {
    final ports = <int, int>{};
    try {
      for (final vb in await snmp.walk(basePortIfIndexOid, chunkSize: 40, maxIterations: 40)) {
        if (!vb.oid.startsWith('$basePortIfIndexOid.') || vb.isAbsent || !vb.isNumeric) continue;
        final bp = int.tryParse(vb.oid.substring(basePortIfIndexOid.length + 1));
        if (bp != null) ports[bp] = vb.asInt;
      }
    } catch (_) {/* بلا ربطٍ لا إسناد */}
    if (ports.isEmpty) return FdbSnapshot.unsupported;

    final clock = Stopwatch()..start();
    var q = await _pairs(snmp, qPortOid, qStatusOid, withFdbId: true, isCancelled: isCancelled, clock: clock, budget: budget);
    // BRIDGE-MIB بديلاً حين لا يدعم الجهاز Q-BRIDGE — لا يُجمع معه.
    if (!q.supported) {
      q = await _pairs(snmp, dPortOid, dStatusOid, withFdbId: false, isCancelled: isCancelled, clock: clock, budget: budget);
    }
    if (!q.supported) return FdbSnapshot.unsupported;
    return build(
      bridgePortToIfIndex: ports,
      rows: q.rows,
      targets: targets,
      complete: q.complete,
    );
  }

  /// العمودان معاً في كلّ ردّ — كقارئ جدول VSOL GPON ‏(`VsolGponDetails`).
  static Future<({List<FdbRow> rows, bool complete, bool supported})> _pairs(
    SnmpV2c snmp,
    String portOid,
    String statusOid, {
    required bool withFdbId,
    required Stopwatch clock,
    required Duration budget,
    bool Function()? isCancelled,
  }) async {
    final rows = <FdbRow>[];
    var portCursor = portOid;
    var statusCursor = statusOid;
    var complete = false;
    var sawAny = false;
    try {
      for (var page = 0; page < 200 && clock.elapsed < budget; page++) {
        if (isCancelled?.call() == true) break;
        final vbs = await snmp.getBulkColumns([portCursor, statusCursor], maxRepetitions: 12);
        if (vbs.isEmpty || vbs.length.isOdd) break;
        var portDone = false;
        var statusDone = false;
        var malformed = false;
        var nextPort = portCursor;
        var nextStatus = statusCursor;
        for (var i = 0; i < vbs.length; i += 2) {
          final p = vbs[i];
          final st = vbs[i + 1];
          final hasP = p.oid.startsWith('$portOid.') && !p.isAbsent;
          final hasS = st.oid.startsWith('$statusOid.') && !st.isAbsent;
          if (!hasP) portDone = true;
          if (!hasS) statusDone = true;
          if (hasP) nextPort = p.oid;
          if (hasS) nextStatus = st.oid;
          if (hasP != hasS) malformed = true;
          if (!hasP || !hasS) continue;
          final pi = p.oid.substring(portOid.length + 1);
          final si = st.oid.substring(statusOid.length + 1);
          if (pi != si) {
            malformed = true;
            continue;
          }
          final row = rowFromIndex(pi, withFdbId: withFdbId, bridgePort: p.asInt, status: st.asInt);
          if (row != null) {
            rows.add(row);
            sawAny = true;
          }
        }
        if (malformed) break;
        if (portDone && statusDone) {
          complete = true;
          break;
        }
        if (nextPort == portCursor || nextStatus == statusCursor) break;
        portCursor = nextPort;
        statusCursor = nextStatus;
      }
    } catch (_) {/* الناقص لا يُقدَّم كاملاً */}
    // جدولٌ فارغٌ تماماً منذ أوّل ردّ = الجهاز لا يدعم هذا الـMIB.
    return (rows: rows, complete: complete && sawAny, supported: sawAny);
  }

  // ═══════════════════════════════════════════════════════════
  // التحليل — خالصٌ وقابلٌ للاختبار
  // ═══════════════════════════════════════════════════════════

  /// صفٌّ من لاحقة الـOID: ‏`<fdbId>.<m1..m6>` ‏(Q-BRIDGE) أو `<m1..m6>`.
  @visibleForTesting
  static FdbRow? rowFromIndex(String suffix, {required bool withFdbId, required int bridgePort, required int status}) {
    final parts = suffix.split('.');
    if (parts.length != (withFdbId ? 7 : 6)) return null;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null || n < 0 || n > (1 << 31))) return null;
    final macBytes = nums.sublist(withFdbId ? 1 : 0).cast<int>();
    if (macBytes.any((b) => b > 255)) return null;
    final mac = macBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
    return FdbRow(fdbId: withFdbId ? nums.first! : 0, mac: mac, bridgePort: bridgePort, status: status);
  }

  static bool _isDeviceMac(String mac) {
    final b = mac.split(':').map((h) => int.parse(h, radix: 16)).toList();
    if (b.every((v) => v == 0) || b.every((v) => v == 0xff)) return false;
    return b.first & 1 == 0; // الجماعيّ ليس جهازاً
  }

  /// الإسناد: متعلَّمٌ وحده، عبر جدول الربط، إلى ONU من [targets] وحدها،
  /// بلا ملتبس، وبلا تكرارٍ داخل ONU واحدة. والترتيب ثابت (أبجديّ).
  static FdbSnapshot build({
    required Map<int, int> bridgePortToIfIndex,
    required List<FdbRow> rows,
    required Set<int> targets,
    required bool complete,
  }) {
    final owners = <String, Set<int>>{};
    for (final r in rows) {
      if (r.status != learned) continue;
      if (!_isDeviceMac(r.mac)) continue;
      final ifIndex = bridgePortToIfIndex[r.bridgePort];
      if (ifIndex == null || !targets.contains(ifIndex)) continue;
      owners.putIfAbsent(r.mac, () => <int>{}).add(ifIndex);
    }
    final byIf = <int, List<String>>{};
    for (final e in owners.entries) {
      if (e.value.length != 1) continue; // ملتبس: رآه المسح على ONU‏َين
      byIf.putIfAbsent(e.value.single, () => []).add(e.key);
    }
    for (final l in byIf.values) {
      l.sort();
    }
    return FdbSnapshot(
      macsByIfIndex: {for (final e in byIf.entries) e.key: List.unmodifiable(e.value)},
      complete: complete,
      supported: true,
    );
  }
}

@immutable
class FdbRow {
  const FdbRow({required this.fdbId, required this.mac, required this.bridgePort, required this.status});
  final int fdbId;
  final String mac;
  final int bridgePort;
  final int status;
}

@immutable
class FdbSnapshot {
  const FdbSnapshot({required this.macsByIfIndex, required this.complete, required this.supported});

  /// الجهاز لا يكشف جدول الجسر أو جدول ربط المنافذ — «غير متوفّر» لا «لا أجهزة».
  static const unsupported = FdbSnapshot(macsByIfIndex: {}, complete: false, supported: false);

  final Map<int, List<String>> macsByIfIndex;
  final bool complete;
  final bool supported;
}
