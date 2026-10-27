import 'snmp_client.dart';

/// V-SOL vendor tables, verified against V1600G0B. The switch MAC table
/// identifies PON and ONU explicitly; IF-MIB and BRIDGE-MIB do not on this OLT.
class VsolGponDetails {
  static const serialOid = '1.3.6.1.4.1.37950.1.1.6.1.1.4.1.5';
  static const macOid = '1.3.6.1.4.1.37950.1.1.5.10.3.2.1.3';
  static const portOid = '1.3.6.1.4.1.37950.1.1.5.10.3.2.1.5';

  static Future<VsolGponSnapshot> fetch(
    SnmpV2c snmp, {
    bool Function()? isCancelled,
  }) async {
    final serials = <String, String>{};
    try {
      for (final vb in await snmp.walk(serialOid, chunkSize: 25)) {
        if (!vb.oid.startsWith('$serialOid.') || vb.isAbsent) continue;
        final key = pairKey(vb.oid.substring(serialOid.length + 1));
        final serial = vb.asString.trim();
        if (key != null && serial.isNotEmpty) serials[key] = serial;
      }
    } catch (_) {/* Optional identity; base IF-MIB data remains useful. */}

    final owners = <String, Set<String>>{};
    var macCursor = macOid;
    var portCursor = portOid;
    var complete = false;
    final clock = Stopwatch()..start();
    try {
      // Two interleaved columns in each response. Never join two full walks by
      // row index: a newly learned/aged-out MAC can shift the entire table.
      for (var page = 0; page < 160 && clock.elapsed.inSeconds < 45; page++) {
        if (isCancelled?.call() == true) break;
        final rows = await snmp.getBulkColumns(
          [macCursor, portCursor],
          maxRepetitions: 12,
        );
        if (rows.isEmpty || rows.length.isOdd) break;
        var macDone = false;
        var portDone = false;
        var malformed = false;
        var nextMac = macCursor;
        var nextPort = portCursor;
        for (var i = 0; i < rows.length; i += 2) {
          final mac = rows[i];
          final port = rows[i + 1];
          if (mac.isNoSuchObject ||
              mac.isNoSuchInstance ||
              port.isNoSuchObject ||
              port.isNoSuchInstance) {
            malformed = true;
          }
          final hasMac = mac.oid.startsWith('$macOid.') && !mac.isAbsent;
          final hasPort = port.oid.startsWith('$portOid.') && !port.isAbsent;
          if (!hasMac) macDone = true;
          if (!hasPort) portDone = true;
          if (hasMac) nextMac = mac.oid;
          if (hasPort) nextPort = port.oid;
          if (hasMac != hasPort) malformed = true;
          if (!hasMac || !hasPort) continue;
          final macIndex = mac.oid.substring(macOid.length + 1);
          final portIndex = port.oid.substring(portOid.length + 1);
          if (macIndex != portIndex) {
            malformed = true;
            continue;
          }
          final address = macAddress(mac.rawBytes);
          final key = portKey(port.asString);
          if (address != null && key != null) {
            owners.putIfAbsent(address, () => <String>{}).add(key);
          }
        }
        if (malformed) break;
        if (macDone && portDone) {
          complete = true;
          break;
        }
        if (nextMac == macCursor || nextPort == portCursor) break;
        macCursor = nextMac;
        portCursor = nextPort;
      }
    } catch (_) {/* A partial table must not be presented as complete. */}
    final byOnu = <String, List<String>>{};
    if (complete) {
      for (final entry in owners.entries) {
        // A MAC observed moving between ONUs during this scan is ambiguous.
        if (entry.value.length != 1) continue;
        byOnu.putIfAbsent(entry.value.single, () => []).add(entry.key);
      }
      for (final macs in byOnu.values) {
        macs.sort();
      }
    }
    return VsolGponSnapshot(serials, byOnu, complete);
  }

  static String? pairKey(String suffix) {
    final match = RegExp(r'^([1-9]\d*)\.([1-9]\d*)$').firstMatch(suffix);
    return match == null ? null : '${match[1]}/${match[2]}';
  }

  /// منفذ جدول الماك ⇒ «منفذ/جهاز». GPON على V1600G0B: `PON1:ONU5`. وEPON على V1600D (٢٧ أكتوبر، أسماء واجهاته
  /// `EPON01ONU1`): نقبل `EPON01ONU1` و`EPON0/1:1` أيضاً — الصفر البادئ لا يغيّر الرقم.
  static String? portKey(String name) {
    final n = name.trim();
    final m = RegExp(r'^PON(\d+):ONU(\d+)$', caseSensitive: false).firstMatch(n) ??
        RegExp(r'^[EG]PON(\d+)ONU(\d+)$', caseSensitive: false).firstMatch(n) ??
        RegExp(r'^[EG]PON\d+/(\d+):(\d+)$', caseSensitive: false).firstMatch(n);
    if (m == null) return null;
    final pon = int.parse(m[1]!), onu = int.parse(m[2]!);
    return pon < 1 || onu < 1 ? null : '$pon/$onu';
  }

  static String? macAddress(List<int> bytes) {
    if (bytes.length != 6 || bytes.every((b) => b == 0) || bytes.first.isOdd) {
      return null;
    }
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
  }
}

class VsolGponSnapshot {
  const VsolGponSnapshot(this.serials, this.learnedMacs, this.macsComplete);
  final Map<String, String> serials;
  final Map<String, List<String>> learnedMacs;
  final bool macsComplete;
}
