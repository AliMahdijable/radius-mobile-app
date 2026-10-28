import 'bdcom_epon.dart';
import 'cdata_olt.dart';
import 'hsgq_olt.dart';
import 'olt_profile.dart';
import 'snmp_client.dart';
import 'vsol_olt_api.dart';

/// طلب GET واحد — `SnmpV2c.get` في الإنتاج.
typedef OltGet = Future<List<Varbind>> Function(List<String> oids);

/// قارئ أولتٍ تُقرأ الـONU فيه من جدول المصنّع **بالـGET وحده** على فهارس محسوبة — HSGQ ‏([HsgqOlt]) وC-Data
/// ‏([CdataOlt]). اللوحة والنظرة وشبكة الألياف ووضع الفنّي تسأل [OltProfile.readsGetTables] ثمّ تأخذ قارئه من [of]،
/// فلا يتكرّر فرعٌ لكلّ مصنّع في كلّ موضع.
abstract class OltGetTables {
  const OltGetTables();

  static OltGetTables? of(OltProfile p) => switch (p.vendor) {
        OltVendor.hsgq => const _Hsgq(),
        OltVendor.cdata => const _Cdata(),
        _ => null,
      };

  Future<VsolOltStats> fetchStats(
    OltGet get, {
    required OltProfile profile,
    String? sysDescr,
    String? sysName,
    Duration? uptime,
    bool withCounters = false,
    void Function(VsolOltStats partial)? onPartialReady,
  });

  Future<({VsolOltStats stats, int unknown})?> refreshStatus(OltGet get, VsolOltStats previous);

  Future<Map<int, bool>?> statusOf(OltGet get, Iterable<int> idx, {bool Function()? isCancelled});

  Future<Map<int, String>?> names(OltGet get, Iterable<int> idx, {bool Function()? isCancelled});

  Future<Map<int, BdcomOnuReading>> identities(OltGet get, Iterable<int> idx, {bool Function()? isCancelled});

  Future<Map<int, BdcomOnuReading>> readings(OltGet get, Iterable<int> online, {bool Function()? isCancelled});

  Future<Map<int, double>?> rxOnly(OltGet get, Iterable<int> online, {bool Function()? isCancelled});

  Future<BdcomChassis> chassis(OltGet get);
}

class _Hsgq extends OltGetTables {
  const _Hsgq();

  @override
  Future<VsolOltStats> fetchStats(OltGet get,
          {required OltProfile profile,
          String? sysDescr,
          String? sysName,
          Duration? uptime,
          bool withCounters = false,
          void Function(VsolOltStats partial)? onPartialReady}) =>
      HsgqOlt.fetchStats(get,
          profile: profile,
          sysDescr: sysDescr,
          sysName: sysName,
          uptime: uptime,
          withCounters: withCounters,
          onPartialReady: onPartialReady);

  @override
  Future<({VsolOltStats stats, int unknown})?> refreshStatus(OltGet get, VsolOltStats previous) =>
      HsgqOlt.refreshStatus(get, previous);

  @override
  Future<Map<int, bool>?> statusOf(OltGet get, Iterable<int> idx, {bool Function()? isCancelled}) =>
      HsgqOlt.statusOf(get, idx, isCancelled: isCancelled);

  @override
  Future<Map<int, String>?> names(OltGet get, Iterable<int> idx, {bool Function()? isCancelled}) =>
      HsgqOlt.names(get, idx, isCancelled: isCancelled);

  @override
  Future<Map<int, BdcomOnuReading>> identities(OltGet get, Iterable<int> idx, {bool Function()? isCancelled}) =>
      HsgqOlt.identities(get, idx, isCancelled: isCancelled);

  @override
  Future<Map<int, BdcomOnuReading>> readings(OltGet get, Iterable<int> online, {bool Function()? isCancelled}) =>
      HsgqOlt.readings(get, online, isCancelled: isCancelled);

  @override
  Future<Map<int, double>?> rxOnly(OltGet get, Iterable<int> online, {bool Function()? isCancelled}) =>
      HsgqOlt.rxOnly(get, online, isCancelled: isCancelled);

  @override
  Future<BdcomChassis> chassis(OltGet get) => HsgqOlt.chassis(get);
}

class _Cdata extends OltGetTables {
  const _Cdata();

  @override
  Future<VsolOltStats> fetchStats(OltGet get,
          {required OltProfile profile,
          String? sysDescr,
          String? sysName,
          Duration? uptime,
          bool withCounters = false,
          void Function(VsolOltStats partial)? onPartialReady}) =>
      CdataOlt.fetchStats(get,
          profile: profile,
          sysDescr: sysDescr,
          sysName: sysName,
          uptime: uptime,
          withCounters: withCounters,
          onPartialReady: onPartialReady);

  @override
  Future<({VsolOltStats stats, int unknown})?> refreshStatus(OltGet get, VsolOltStats previous) =>
      CdataOlt.refreshStatus(get, previous);

  @override
  Future<Map<int, bool>?> statusOf(OltGet get, Iterable<int> idx, {bool Function()? isCancelled}) =>
      CdataOlt.statusOf(get, idx, isCancelled: isCancelled);

  @override
  Future<Map<int, String>?> names(OltGet get, Iterable<int> idx, {bool Function()? isCancelled}) =>
      CdataOlt.names(get, idx, isCancelled: isCancelled);

  @override
  Future<Map<int, BdcomOnuReading>> identities(OltGet get, Iterable<int> idx, {bool Function()? isCancelled}) =>
      CdataOlt.identities(get, idx, isCancelled: isCancelled);

  @override
  Future<Map<int, BdcomOnuReading>> readings(OltGet get, Iterable<int> online, {bool Function()? isCancelled}) =>
      CdataOlt.readings(get, online, isCancelled: isCancelled);

  @override
  Future<Map<int, double>?> rxOnly(OltGet get, Iterable<int> online, {bool Function()? isCancelled}) =>
      CdataOlt.rxOnly(get, online, isCancelled: isCancelled);

  @override
  Future<BdcomChassis> chassis(OltGet get) => CdataOlt.chassis(get);
}
