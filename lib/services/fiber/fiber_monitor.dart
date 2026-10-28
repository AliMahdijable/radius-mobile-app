import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/bdcom_epon.dart';
import '../../api/bridge_fdb.dart';
import '../../api/broadcast_api.dart';
import '../../api/fiber_api.dart';
import '../../api/hsgq_olt.dart';
import '../../api/network_devices_api.dart';
import '../../api/olt_fiber_reads.dart';
import '../../api/olt_profile.dart';
import '../../api/snmp_client.dart';
import '../../api/vsol_gpon_details.dart';
import '../../api/vsol_olt_api.dart';
import '../../models/fiber_network.dart';
import '../../models/network_device.dart';
import '../device_stats_cache.dart';
import '../olt_name_cache.dart';
import 'fiber_band.dart';
import 'fiber_onu.dart';
import 'fiber_outage.dart';
import 'fiber_store.dart';
import 'fiber_text.dart';

/// مصدر قراءة الأولت — SNMP الحقيقيّ، وللاختبار بديلٌ يعيد لقطاتٍ جاهزة.
class FiberBackend {
  const FiberBackend();

  Future<String?> community(NetworkDevice d) async {
    final c = await NetworkDevicesApi.getCredentials(d.id);
    final v = (c['community'] ?? c['pass'] ?? '').toString().trim();
    return v.isEmpty ? null : v;
  }

  SnmpV2c snmp(NetworkDevice d, String community) => SnmpV2c(host: d.ip, port: d.apiPort ?? 161, community: community);

  /// البنية: الأسماء والحالة — أو الحالة وحدها إن أُعطيت أسماءٌ محفوظة ([knownNames]) ولم تظهر واجهةٌ جديدة.
  Future<VsolOltStats> structure(NetworkDevice d, String community, OltProfile p, {Map<int, String>? knownNames}) =>
      VsolOltApi.fetchStats(
        host: d.ip,
        port: d.apiPort ?? 161,
        community: community,
        structureOnly: true,
        withCounters: false,
        withGponDetails: false,
        profile: p,
        knownNames: knownNames,
      );

  /// الحالة وحدها فوق آخر بنية.
  Future<({VsolOltStats stats, int unknown})?> status(NetworkDevice d, String community, VsolOltStats prev) =>
      VsolOltApi.refreshStatus(host: d.ip, port: d.apiPort ?? 161, community: community, previous: prev);

  Future<VsolOltStats> hot(NetworkDevice d, String community, VsolOltStats prev) =>
      VsolOltApi.refreshHotCounters(host: d.ip, port: d.apiPort ?? 161, community: community, previous: prev);
}

/// مراقب أولتٍ واحد لشبكة الألياف — لكلّ أولت (VSOL وBDCOM، EPON وGPON).
///
/// ⚡ **الأهمّ أوّلاً** (٢٧ أكتوبر، المالك: «كلش يتاخر… سرعة الاستجابة وعرض المعلومات مهمّة جداً»). كانت الدورة الأولى
/// على «Moh» (‏٣٠٢ جهاز، رحلة ~٢٥٠ مللي، وكيلٌ يعالج ~١٠٠ قيمة/ث) تطلب كلّ شيءٍ قبل أن تعرض شيئاً: ~٢٣٥٠ قيمة و٩٠ ثانية.
/// الآن مراحل، وبعد كلّ مرحلةٍ عرض:
///   ٠. لقطةٌ محفوظة من الفتحة السابقة تُعرض فوراً ([stale] — الشاشة تقول «محفوظة من …»)
///   ١. الحالة: عمود ifOperStatus فوق آخر بنية (الأسماء محفوظة) — عدد المتّصلين لكلّ منفذ
///   ٢. لحظة السقوط وسببه للمفصولة وحدها، بالتوازي ⇒ كشف الأعطال
///   ٣. الضوء: عمود الاستقبال وحده (الإرسال والحرارة لجهازٍ يُفتح)
///   ٤. أسماء الوكيل كلّ نصف ساعة، والأجهزة خلف كلّ ONU حين تُطلب ([wantDevices])
///
/// يعمل ما دام له مستخدم ([acquire]/[release]): شاشات الألياف على الهاتف، والحاسبة بالخلفيّة ([background]، إيقاعٌ أبطأ
/// وبلا عدّادات المنافذ). لا يكتب الحمولة الخام في [DeviceStatsCache] (لقطةٌ بلا عدّادات تُفقر لوحة الأولت) — يقرأ منه
/// بذرةً فقط؛ وخانات بطاقة الجدار الثلاث تصله عبر [onLiveStats].
class FiberMonitor extends ChangeNotifier {
  FiberMonitor._(this.device) : profile = OltProfile.fromDevice(device);

  static final Map<int, FiberMonitor> _all = {};

  /// للاختبار: مصدرٌ وساعة بديلان.
  static FiberBackend backend = const FiberBackend();
  static DateTime Function() clock = DateTime.now;

  static FiberMonitor of(NetworkDevice d) {
    final m = _all.putIfAbsent(d.id, () => FiberMonitor._(d));
    m.device = d;
    return m;
  }

  static FiberMonitor? existing(int deviceId) => _all[deviceId];

  /// بعد كلّ قراءة حالةٍ حيّة (لا لقطةٍ محفوظة) — جسر قسم الأجهزة ([bridgeFiberVitals]) يكتبها بخانات بطاقة الجدار.
  static void Function(int oltId, VsolOltStats stats)? onLiveStats;
  static Iterable<FiberMonitor> get all => _all.values;

  /// من [SessionManager] عند الخروج: تتوقّف كلّها ولا يرث أحدٌ قراءات سابقه.
  static void resetAll() {
    for (final m in _all.values) {
      m._stop();
      m._users = 0;
      m._bgUsers = 0;
    }
    _all.clear();
  }

  static const _statusEvery = Duration(seconds: 15);
  static const _bgStatusEvery = Duration(seconds: 30);
  static const _opticsEvery = Duration(seconds: 60);
  static const _bgOpticsEvery = Duration(minutes: 3);
  static const _namesEvery = Duration(minutes: 30);
  static const _devicesEvery = Duration(minutes: 5);

  /// ماك أجهزة VSOL EPON — لا تتغيّر إلّا باستبدال جهاز، فنصف ساعة (ومحفوظة مع اللقطة).
  static const _macsEvery = Duration(minutes: 30);
  static const _rxUploadEvery = Duration(minutes: 10);
  static const _snapshotEvery = Duration(minutes: 1);

  NetworkDevice device;
  OltProfile profile;

  VsolOltStats? stats;
  DateTime? statsAt;
  final Map<String, VsolTraffic> ponRates = {};

  /// ترفك منافذ الأبلنك (نحو السيرفر) — «مخطّط الشبكة» يكتبه على خطّ السيرفر ⇐ الأولت. rx = النازل للمشتركين.
  final Map<String, VsolTraffic> uplinkRates = {};

  /// آخر لقطةٍ تحرّكت عدّاداتها — مرجعيّة معدّل المنافذ (انظر [VsolTraffic.frozenBetween]).
  VsolOltStats? _ctrRef;
  DateTime? _ctrRefAt;
  List<FiberOnuLive> onus = const [];
  List<FiberOutage> outages = const [];
  FiberOltCaps? caps;
  String? error;
  bool busy = false;
  DateTime? lastOkAt;

  /// المعروض لقطةٌ محفوظة من فتحةٍ سابقة ([lastOkAt] وقتها) — الحيّة في الطريق.
  bool stale = false;

  /// شاشة الربط/التشخيص تطلب الأجهزة خلف كلّ ONU (ثقيلة — لا تُقرأ بلا طلب).
  bool wantDevices = false;

  /// آخر الأجهزة التي فُتحت بوضع الفنّي (الأحدث أوّلاً) — اختصارٌ للفنّي بالموقع، يزول مع الجلسة.
  final List<String> techRecent = [];

  final Map<int, BdcomOnuReading> _optics = {};
  DateTime? _opticsAt;
  final Map<int, FiberDropReason> _reasons = {};
  final Map<int, DateTime> _changes = {};
  final Map<int, String> _names = {};
  DateTime? _namesAt;
  OltEponDetails _epon = const OltEponDetails();
  VsolGponSnapshot? _gpon;
  DateTime? _gponAt, _devicesAt, _macsAt;
  final Map<String, bool> _wasOnline = {};
  bool _first = true;
  bool _needStructure = false;
  DateTime? _rxUploadAt, _snapAt;
  bool _capsDone = false;
  Future<void>? _snapLoading;

  /// حالات اللقطة المحفوظة ووقتها: لقطةٌ حديثة (< نصف ساعة) ⇒ الدورة الأولى تقرأ لحظة السقوط وسببه لما تغيّر منذها وحده.
  Map<String, bool>? _snapStates;
  DateTime? _snapTakenAt;

  /// الأعطال المبلَّغة: مكانها ← سجلّها على الخادم (أو محلّيّ بلا رقم).
  final Map<String, ({FiberEventRecord? record, Set<String> keys, DateTime startedAt})> _open = {};

  int _users = 0;
  int _bgUsers = 0;
  Timer? _timer;
  Duration _cost = Duration.zero;

  bool get running => _users > 0 || _bgUsers > 0;
  bool get background => _users == 0 && _bgUsers > 0;
  int get oltId => device.id;
  FiberOltSettings get settings => FiberStore.layout.value.settingsOf(oltId);

  void acquire({bool background = false}) {
    final was = running;
    if (background) {
      _bgUsers++;
    } else {
      _users++;
    }
    if (!was) {
      _seed();
      if (stats == null) _snapLoading ??= _loadSnapshot();
      _schedule(Duration.zero);
    } else if (!background && _users == 1) {
      // شاشةٌ فُتحت على مراقبٍ خلفيّ: قراءةٌ فوريّة بإيقاع الشاشة.
      _schedule(Duration.zero);
    }
  }

  void release({bool background = false}) {
    if (background) {
      if (_bgUsers > 0) _bgUsers--;
    } else {
      if (_users > 0) _users--;
    }
    if (!running) _stop();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _schedule(Duration d) {
    _timer?.cancel();
    if (!running) return;
    _timer = Timer(d, () async {
      await tick();
      if (!running) return;
      final base = background ? _bgStatusEvery : _statusEvery;
      final paced = _cost * 2;
      _schedule(paced > base ? paced : base);
    });
  }

  /// بذرةٌ من لوحة الأولت إن قرأته قبل دقائق — الشاشة لا تبدأ فارغة.
  void _seed() {
    if (stats != null) return;
    final s = DeviceStatsCache.instance.seedFor<VsolOltStats>(device.id);
    if (s == null || s.isEmpty) return;
    stats = s;
    statsAt = clock();
    if (s.profile.identified) profile = s.profile;
    _rebuild();
  }

  /// قراءةٌ الآن (زرّ التحديث، أو أوّل فتح).
  Future<void> refreshNow() => tick(force: true);

  @visibleForTesting
  Future<void> tick({bool force = false}) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    final clockStart = DateTime.now();
    try {
      await _snapLoading;
      final community = await backend.community(device);
      if (community == null) {
        error = 'أدخل الـcommunity من إعدادات الجهاز';
        return;
      }
      final snmp = backend.snmp(device, community);
      final now = clock();

      // ── ١. الحالة: عمود الحالة فوق آخر بنية؛ البنية حين لا بنية، أو ظهرت واجهةٌ جديدة/غابت واجهة.
      final prev = stats;
      final prevAt = statsAt;
      VsolOltStats? s;
      if (prev != null && prev.ifNames.isNotEmpty && !_needStructure) {
        final r = await backend.status(device, community, prev);
        if (r != null) {
          s = r.stats;
          if (r.unknown > 0) _needStructure = true;
        }
      }
      if (s == null) {
        // أسماءٌ محفوظة (هنا أو من لوحة الأولت) ⇒ الحالة وحدها، إلّا إن طُلبت البنية لواجهةٍ جديدة.
        final known = _needStructure
            ? null
            : (prev != null && prev.ifNames.isNotEmpty ? prev.ifNames : await OltNameCache.get(device.id));
        s = await backend.structure(device, community, profile, knownNames: known);
        if (s.profile.identified) profile = s.profile;
        if (s.isEmpty) {
          error = 'الأولت لم يُجب بجدوله كاملاً — نعيد بعد قليل';
          return;
        }
        _needStructure = false;
        unawaited(OltNameCache.put(device.id, s.ifNames));
      }
      var cur = s;
      if (_first && _snapStates != null && _snapTakenAt != null && now.difference(_snapTakenAt!) < const Duration(minutes: 30)) {
        // ما بقي مفصولاً منذ اللقطة يحمل لحظته وسببه منها — لا يُعاد سؤاله.
        _wasOnline.addAll(_snapStates!);
        _first = false;
      }
      _snapStates = null;
      final changed = <VsolOnu>[];
      final offlineNow = <VsolOnu>[];
      for (final o in cur.onus) {
        final was = _wasOnline[o.label];
        if (was != null && was != o.online) changed.add(o);
        if (!o.online) offlineNow.add(o);
      }
      final firstPass = _first;
      _first = false;
      for (final o in cur.onus) {
        _wasOnline[o.label] = o.online;
      }
      for (final o in changed) {
        if (o.online) _reasons.remove(o.ifIndex);
      }
      stats = cur;
      statsAt = now;
      lastOkAt = now;
      error = null;
      stale = false;
      _rebuild();
      notifyListeners(); // ⚡ أوّل عرضٍ حيّ: المتّصل/المفصول لكلّ منفذ
      try {
        onLiveStats?.call(oltId, cur); // بطاقة الجدار بالأرقام نفسها
      } catch (_) {}

      // عدّادات المنافذ (ترفك PON) بعد أوّل عرض — للشاشة وحدها، الخلفيّة لا ترسمها.
      if (!background) {
        try {
          cur = await backend.hot(device, community, cur);
        } catch (_) {/* بلا عدّادات هذه المرّة */}
        // المرجعيّة آخر عدّاداتٍ **تحرّكت** — أولتٌ يُحدّثها دوريّاً (HSGQ كلّ ~٣١ث) يُرجعها كما هي بين دورتين، فالفرق
        // صفرٌ «لم يُحدَّث» لا «لا ترفك»؛ ولغيره هي لقطة الدورة السابقة كما كانت.
        final ref = _ctrRef ?? prev;
        final refAt = _ctrRefAt ?? prevAt;
        // مرجعيّةٌ أقدم من دقيقتين (عودةٌ من الخلفيّة) لا يُقاس عليها: عدّاد ٣٢ بت قد التفّ أكثر من مرّة بينهما.
        final recent = refAt != null && now.difference(refAt) <= const Duration(minutes: 2);
        if (ref != null && refAt != null && recent && ref.hasCounters && cur.hasCounters) {
          if (!VsolTraffic.frozenBetween(profile, ref, cur, now.difference(refAt))) {
            final fresh = VsolTraffic.between(ref, cur, now.difference(refAt));
            for (final p in cur.ponPorts) {
              final v = fresh[p.label];
              if (v != null && v.known) ponRates[p.label] = v;
            }
            for (final u in cur.uplinks) {
              final v = fresh[u.name];
              if (v != null && v.known) uplinkRates[u.name] = v;
            }
            _ctrRef = cur;
            _ctrRefAt = now;
          }
        } else if (cur.hasCounters) {
          _ctrRef = cur;
          _ctrRefAt = now;
        }
        if (cur.hasCounters) {
          stats = cur;
          notifyListeners();
        }
      }

      // ── ٢. لحظة السقوط وسببه — للمفصولة وحدها (أوّل مرّة كلّها، بعدها ما تغيّر)، بالتوازي.
      final changeTargets = firstPass ? offlineNow : changed;
      final reasonTargets = firstPass ? offlineNow : [for (final o in changed) if (!o.online) o];
      if (changeTargets.isNotEmpty || reasonTargets.isNotEmpty) {
        final got = await Future.wait<Object>([
          // HSGQ لا يعطي اللحظة (فهرس الـONU فهرس جدول المصنّع لا IF-MIB) ⇒ لا يُسأل؛ لحظة رصدنا وحدها تحت.
          changeTargets.isEmpty || profile.readsHsgqTables
              ? Future.value(const <int, DateTime>{})
              : OltFiberReads.lastChanges(snmp, changeTargets.map((o) => o.ifIndex), now: now),
          reasonTargets.isEmpty
              ? Future.value(const <int, FiberDropReason>{})
              : OltFiberReads.dropReasons(snmp, profile, reasonTargets),
        ]);
        final ch = got[0] as Map<int, DateTime>;
        for (final o in changeTargets) {
          final t = ch[o.ifIndex];
          if (t != null) {
            _changes[o.ifIndex] = t;
          } else if (!firstPass) {
            // الأولت لا يعطي اللحظة: لحظة رصدنا (دقّة الإيقاع) — فتتجمّع أجهزة الدورة الواحدة عطلاً واحداً.
            _changes[o.ifIndex] = now;
          }
        }
        _reasons.addAll(got[1] as Map<int, FiberDropReason>);
        _rebuild();
        notifyListeners();
      }
      await _syncOutages(now);

      // ── ٣. الضوء: عمود الاستقبال وحده، بإيقاعه.
      // VSOL: جدول الضوء يُحسب جهازاً جهازاً (~٠٫٣٥ث للقيمة على V1600D) ⇒ شريحةٌ كلّ دورة تتناوب حتى تكتمل، بدل
      // سؤال الكلّ كلّ دقيقة (٧٠ث لـ٢٠٠ متّصل يخنق الوكيل فتسقط الحالة والماك معه).
      final slices = profile.readsVsolTables;
      final opticsEvery = background ? _bgOpticsEvery : _opticsEvery;
      if (force || slices || _opticsAt == null || now.difference(_opticsAt!) >= opticsEvery) {
        final allOnline = [for (final o in cur.onus) if (o.online) o];
        final online = slices ? _rxSlice(allOnline) : allOnline;
        final rx = await OltFiberReads.rxColumn(snmp, profile, online);
        _opticsAt = now;
        if (rx != null) {
          for (final o in online) {
            final old = _optics[o.ifIndex];
            final v = rx[o.ifIndex];
            if (v == null && old == null) continue;
            // الإرسال والحرارة والفولتيّة من آخر قراءةٍ كاملة لهذا الجهاز (تُجدَّد حين يُفتح) — الاستقبال من هذه.
            _optics[o.ifIndex] = BdcomOnuReading(
              rxDbm: v,
              txDbm: old?.txDbm,
              tempC: old?.tempC,
              voltV: old?.voltV,
              vendor: old?.vendor,
              module: old?.module,
            );
          }
          final book = await FiberStore.loadBook(oltId, now: now);
          for (final o in online) {
            final v = rx[o.ifIndex];
            if (FiberBands.plausible(v)) book.record(o.label, v!, now);
          }
          _rebuild();
          notifyListeners();
        }
      }

      // ── ٤. أسماء الوكيل (بطيئة التغيّر، ومحفوظة مع اللقطة).
      if (_namesAt == null || now.difference(_namesAt!) >= _namesEvery) {
        final n = await OltFiberReads.names(snmp, profile, cur.onus);
        _namesAt = now;
        if (n != null) {
          _names
            ..clear()
            ..addAll(n);
          _rebuild();
          notifyListeners();
        }
      }

      // ── ٥. ماك أجهزة VSOL EPON: بها يطابق «ربط المشتركين» جلسة الساس ويظهر «ماك الـONU» (BDCOM تُقرأ مع الأجهزة).
      if (profile.readsVsolTables && (_macsAt == null || now.difference(_macsAt!) >= _macsEvery)) {
        final epon = {for (final o in cur.onus) if (o.technology == VsolPonTechnology.epon) o.ifIndex};
        if (epon.isNotEmpty) {
          final m = await OltFiberReads.vsolEponMacs(snmp, epon);
          if (m != null) {
            _macsAt = now;
            if (m.isNotEmpty) {
              _epon = _epon.copyWith(onuMacs: {..._epon.onuMacs, ...m}, macsAt: now);
              _rebuild();
              notifyListeners();
            }
          }
        }
      }

      // الأجهزة خلف كلّ ONU (للربط) — بطلب.
      if (wantDevices && (force || _devicesAt == null || now.difference(_devicesAt!) >= _devicesEvery)) {
        await _readDevices(snmp, cur);
        _devicesAt = now;
        _rebuild();
      }

      // القدرات مرّةً بالجلسة، والضوء للخادم كلّ عشر دقائق، واللقطة على الجهاز كلّ دقيقة.
      if (!_capsDone) {
        _capsDone = true;
        unawaited(_probeCaps(snmp, cur, now));
      }
      if (_rxUploadAt == null || now.difference(_rxUploadAt!) >= _rxUploadEvery) {
        _rxUploadAt = now;
        unawaited(_uploadRx(now));
      }
      if (_snapAt == null || now.difference(_snapAt!) >= _snapshotEvery) {
        _snapAt = now;
        unawaited(_saveSnapshot());
      }
    } on VsolException catch (e) {
      error = e.message;
    } on SnmpException catch (e) {
      error = 'تعذّر الاتّصال بالأولت: $e';
    } catch (e) {
      error = 'تعذّرت القراءة: $e';
    } finally {
      _cost = DateTime.now().difference(clockStart);
      busy = false;
      notifyListeners();
    }
  }

  // ── اللقطة المحفوظة ───────────────────────────────────────────────────────────────────

  /// ما يُرسم فوراً في الفتحة القادمة: البنية والحالة والأسماء والضوء ولحظات السقوط وأسبابها — لا عدّادات ولا ماكات
  /// أجهزة المشتركين خلف الـONU.
  Map<String, dynamic>? snapshotJson() {
    final s = stats;
    final at = statsAt;
    if (s == null || at == null || s.isEmpty) return null;
    return {
      'v': 1,
      'at': at.toUtc().toIso8601String(),
      'vendor': profile.vendor.name,
      'model': profile.model,
      'pons': [
        for (final p in s.ponPorts) [p.index, p.slot, p.port, p.up ? 1 : 0, p.technology.index, p.onuTotal, p.onuOnline],
      ],
      'ups': [
        for (final u in s.uplinks) [u.index, u.name, u.up ? 1 : 0, u.speedMbps],
      ],
      'onus': [
        for (final o in s.onus) [o.ifIndex, o.slot, o.ponPort, o.onuId, o.online ? 1 : 0, o.technology.index, o.mac, o.serial, o.name],
      ],
      'ifn': {for (final e in s.ifNames.entries) '${e.key}': e.value},
      'names': {for (final e in _names.entries) '${e.key}': e.value},
      'macs': {for (final e in _epon.onuMacs.entries) '${e.key}': e.value},
      'rx': {
        for (final e in _optics.entries)
          if (e.value.rxDbm != null) '${e.key}': e.value.rxDbm,
      },
      'ch': {for (final e in _changes.entries) '${e.key}': e.value.toUtc().toIso8601String()},
      'rs': {for (final e in _reasons.entries) '${e.key}': e.value.name},
      if (_namesAt != null) 'namesAt': _namesAt!.toUtc().toIso8601String(),
    };
  }

  Future<void> _saveSnapshot() async {
    final j = snapshotJson();
    if (j != null) await FiberStore.saveSnapshot(oltId, j);
  }

  Future<void> _loadSnapshot() async {
    final j = await FiberStore.loadSnapshot(oltId);
    if (j == null || stats != null) return;
    try {
      applySnapshot(j);
    } catch (_) {/* لقطةٌ تالفة تُترك — القراءة الحيّة في الطريق */}
  }

  /// يرسم لقطةً محفوظة ([stale] حتى تصل الحيّة).
  @visibleForTesting
  void applySnapshot(Map<String, dynamic> j) {
    if (stats != null || j['v'] != 1) return;
    final at = DateTime.parse(j['at'] as String);
    int i(Object? v) => (v as num).toInt();
    Map<int, T> byIdx<T>(Object? m, T? Function(Object?) f) => {
          for (final e in ((m as Map?) ?? const {}).entries)
            if (int.tryParse('${e.key}') != null && f(e.value) != null) int.parse('${e.key}'): f(e.value) as T,
        };
    final vendor = OltVendor.values.where((v) => v.name == j['vendor']).firstOrNull ?? OltVendor.unknown;
    final s = VsolOltStats(
      profile: OltProfile(vendor: vendor, model: j['model'] as String?, identified: vendor != OltVendor.unknown, oltLikely: true),
      ponPorts: [
        for (final p in (j['pons'] as List))
          VsolPonPort(
            index: i(p[0]),
            slot: i(p[1]),
            port: i(p[2]),
            up: p[3] == 1,
            rxBytes: 0,
            txBytes: 0,
            technology: VsolPonTechnology.values[i(p[4])],
            onuTotal: i(p[5]),
            onuOnline: i(p[6]),
          ),
      ],
      uplinks: [
        for (final u in (j['ups'] as List))
          VsolUplink(index: i(u[0]), name: u[1] as String, up: u[2] == 1, speedMbps: i(u[3]), rxBytes: 0, txBytes: 0),
      ],
      onus: [
        for (final o in (j['onus'] as List))
          VsolOnu(
            ifIndex: i(o[0]),
            slot: i(o[1]),
            ponPort: i(o[2]),
            onuId: i(o[3]),
            online: o[4] == 1,
            technology: VsolPonTechnology.values[i(o[5])],
            mac: o[6] as String?,
            serial: o[7] as String?,
            name: o[8] as String?,
          ),
      ],
      ifNames: Map.unmodifiable(byIdx<String>(j['ifn'], (v) => v is String ? v : null)),
    );
    if (s.isEmpty) return;
    stats = s;
    statsAt = at;
    lastOkAt = at;
    stale = true;
    if (s.profile.identified) profile = s.profile;
    // لقطةٌ قديمة قد تحمل «NULL» لكلّ جهاز (قبل تنظيف الأسماء) — تُنظَّف هنا أيضاً.
    _names.addAll(OltFiberReads.cleanNames(byIdx<String>(j['names'], (v) => v is String ? v : null)));
    final macs = byIdx<String>(j['macs'], (v) => v is String && v.length == 17 ? v : null);
    if (macs.isNotEmpty) {
      _epon = _epon.copyWith(onuMacs: macs, macsAt: at);
      _macsAt = at;
    }
    // المعقول وحده يُخزَّن (كمسار القراءة الحيّ): لقطةٌ تالفة أو قديمة لا تحقن rx غير معقول يرمي عنده `FiberBands.of(rx)!`.
    for (final e in byIdx<double>(j['rx'], (v) => v is num && FiberBands.plausible(v.toDouble()) ? v.toDouble() : null).entries) {
      _optics[e.key] = BdcomOnuReading(rxDbm: e.value);
    }
    _changes.addAll(byIdx<DateTime>(j['ch'], (v) => v is String ? DateTime.tryParse(v) : null));
    _reasons.addAll(
        byIdx<FiberDropReason>(j['rs'], (v) => FiberDropReason.values.where((r) => r.name == v).firstOrNull));
    // أسماء الوكيل قُرئت قبل أقلّ من نصف ساعة ⇒ لا تُعاد في الدورة الأولى.
    final namesAt = j['namesAt'] is String ? DateTime.tryParse(j['namesAt'] as String) : null;
    if (namesAt != null) _namesAt = namesAt; // ولو بلا أسماء: أولتٌ لا يسمّي أجهزته لا يُمسح كلّ فتحة
    _snapStates = {for (final o in s.onus) o.label: o.online};
    _snapTakenAt = at;
    _rebuild();
    notifyListeners();
  }

  /// لحظة اتّصال جهازٍ واحد حين يُفتح (التشخيص/الفنّي) — الدورة الأولى تقرؤها للمفصولة وحدها.
  Future<void> ensureChangedAt(VsolOnu o) async {
    if (_changes.containsKey(o.ifIndex) || profile.readsHsgqTables) return;
    final community = await backend.community(device);
    if (community == null) return;
    final r = await OltFiberReads.lastChanges(backend.snmp(device, community), [o.ifIndex], now: clock());
    final t = r[o.ifIndex];
    if (t == null) return;
    _changes[o.ifIndex] = t;
    _rebuild();
    notifyListeners();
  }

  Future<void> _readDevices(SnmpV2c snmp, VsolOltStats s) async {
    VsolGponSnapshot? vsolTable;
    final epon = s.onus.where((o) => o.technology == VsolPonTechnology.epon).toList();
    // HSGQ: لا جدول جسر — «غير متوفّر» صريحاً (لا «لا أجهزة»)، وماك الـONU جاء مع البنية.
    if (epon.isNotEmpty && profile.readsHsgqTables) {
      _epon = _epon.copyWith(fdb: FdbSnapshot.unsupported, fdbAt: clock());
      return;
    }
    if (epon.isNotEmpty && profile.vendor != OltVendor.unknown) {
      final known = {for (final o in epon) o.ifIndex};
      var next = _epon;
      if (profile.readsBdcomEponTables) {
        final macs = await BdcomEpon.onuMacs(snmp, known);
        next = next.copyWith(onuMacs: {...next.onuMacs, ...macs}, macsAt: clock());
      }
      final FdbSnapshot f;
      if (profile.readsVsolTables) {
        // 🐛 ٢٧ أكتوبر (المالك على V1600D: «مجاي يقره لابورات ولامكات ويطابقه وي المتصلين»): BRIDGE-MIB على VSOL لا ينسب
        // الماك لجهاز، فلم يكن خلف أيّ ONU شيء. جدول الماك الخاصّ بـVSOL يسمّي المنفذ والجهاز صراحةً (مثبتٌ على GPON) —
        // يُقرأ لـEPON أيضاً، ويُعاد استعماله لـGPON تحت.
        final t = vsolTable = await VsolGponDetails.fetch(snmp);
        final byKey = {for (final o in epon) if (o.slot == 0) '${o.ponPort}/${o.onuId}': o.ifIndex};
        f = FdbSnapshot(
          macsByIfIndex: {
            for (final e in t.learnedMacs.entries)
              if (byKey[e.key] != null) byKey[e.key]!: e.value,
          },
          complete: t.macsComplete,
          supported: t.macsComplete || t.learnedMacs.isNotEmpty,
        );
      } else {
        f = await BridgeFdb.fetch(snmp, targets: known);
      }
      final keep = !f.complete && _epon.fdb.complete && f.supported;
      next = keep ? next.copyWith(fdbAt: _epon.fdbAt) : next.copyWith(fdb: f, fdbAt: clock());
      _epon = next;
    }
    if (profile.readsVsolTables && s.onus.any((o) => o.technology == VsolPonTechnology.gpon)) {
      _gpon = vsolTable ?? await VsolGponDetails.fetch(snmp);
      _gponAt = clock();
    }
  }

  /// شريحة ضوء VSOL لهذه الدورة: [_rxSliceSize] جهازاً متّصلاً بعد آخر شريحة (بترتيب الفهرس)، وتعود للأوّل حين تنتهي.
  static const _rxSliceSize = 24;
  int _rxCursor = 0;

  List<VsolOnu> _rxSlice(List<VsolOnu> online) {
    if (online.length <= _rxSliceSize) return online;
    final sorted = [...online]..sort((a, b) => a.ifIndex.compareTo(b.ifIndex));
    final start = sorted.indexWhere((o) => o.ifIndex >= _rxCursor);
    final from = start < 0 ? 0 : start;
    final slice = [for (var k = 0; k < _rxSliceSize; k++) sorted[(from + k) % sorted.length]];
    _rxCursor = slice.last.ifIndex + 1;
    return slice;
  }

  /// يدمج القراءات كلّها فوق آخر بنية.
  void _rebuild() {
    final s = stats;
    if (s == null) return;
    var merged = s.withEponDetails(_epon);
    final g = _gpon;
    if (g != null && _gponAt != null) merged = merged.withGponDetails(g, _gponAt!);
    onus = List.unmodifiable([
      for (final o in merged.onus)
        FiberOnuLive(
          onu: _withNameAndOptics(o),
          reason: o.online ? null : _reasons[o.ifIndex],
          changedAt: _changes[o.ifIndex],
        ),
    ]);
  }

  VsolOnu _withNameAndOptics(VsolOnu o) {
    final r = o.online ? _optics[o.ifIndex] : null;
    final name = _names[o.ifIndex];
    if (r == null && (name == null || (o.name?.isNotEmpty ?? false))) return o;
    return VsolOnu(
      ifIndex: o.ifIndex,
      slot: o.slot,
      ponPort: o.ponPort,
      onuId: o.onuId,
      online: o.online,
      mac: o.mac,
      technology: o.technology,
      name: (o.name?.isNotEmpty ?? false) ? o.name : name,
      serial: o.serial,
      learnedMacs: o.learnedMacs,
      learnedMacsReadAt: o.learnedMacsReadAt,
      learnedMacsComplete: o.learnedMacsComplete,
      speedMbps: o.speedMbps,
      rxBytes: o.rxBytes,
      txBytes: o.txBytes,
      reading: r ?? o.reading,
      readingAt: r != null ? _opticsAt : o.readingAt,
      vendor: o.vendor,
      module: o.module,
    );
  }

  // ── الأعطال ───────────────────────────────────────────────────────────────────────────

  Future<void> _syncOutages(DateTime now) async {
    final layout = FiberStore.layout.value;
    final found = FiberOutageDetector.detect(oltId: oltId, layout: layout, onus: onus, now: now);
    outages = List.unmodifiable(found);
    final online = {for (final o in onus) o.key: o.online};

    // جديد ⇒ تبليغ الخادم (يدمجه مع ما رآه جهازٌ آخر، ويُشعر).
    for (final e in found) {
      if (_open.containsKey(e.scopeKey)) {
        final cur = _open[e.scopeKey]!;
        _open[e.scopeKey] = (record: cur.record, keys: {...cur.keys, ...e.onuKeys}, startedAt: cur.startedAt);
        continue;
      }
      final started = e.startedAt ?? now;
      _open[e.scopeKey] = (record: null, keys: e.onuKeys.toSet(), startedAt: started);
      final text = FiberText.outagePush(e, layout, device.name);
      final r = await FiberApi.reportEvent(
        oltId: oltId,
        kind: e.kind.name,
        scope: e.scope.name,
        scopeKey: e.scopeKey,
        pon: e.pon,
        // صندوقٌ لم يصل الخادم بعد (رقمٌ سالب، على الجهاز وحده) لا يُرسل رقمه — الخادم يرفضه.
        boxId: (e.boxId ?? 0) > 0 ? e.boxId : null,
        onus: e.onuKeys,
        startedAt: started,
        title: text.title,
        body: text.body,
      );
      if (r.event != null) {
        _open[e.scopeKey] = (record: r.event, keys: e.onuKeys.toSet(), startedAt: started);
        FiberStore.applyEvent(r.event!);
      }
    }

    // انتهى ⇒ رجع ٨٠٪ من أجهزته.
    final ended = <String>[];
    for (final entry in _open.entries) {
      final keys = entry.value.keys;
      if (keys.isEmpty) continue;
      final back = keys.where((k) => online[k] == true).length;
      final stillDetected = found.any((f) => f.scopeKey == entry.key);
      if (!stillDetected && back >= (keys.length * 0.8).ceil()) ended.add(entry.key);
    }
    for (final k in ended) {
      final cur = _open.remove(k)!;
      final rec = cur.record;
      if (rec == null) continue;
      final text = FiberText.backPush(rec, layout, device.name);
      final r = await FiberApi.endEvent(rec.id, now, title: text.title, body: text.body);
      final done = r.event ?? rec.copyWith(endedAt: now);
      FiberStore.applyEvent(done);
      if (done.autoBack && done.backSentAt == null) await _sendBack(done);
    }
  }

  /// «رجع النت» للمشتركين المربوطين بأجهزة العطل — مرّةً واحدة بين كلّ الأجهزة (الخادم يحجز الإرسال لأوّل من يطلبه).
  Future<void> _sendBack(FiberEventRecord e) async {
    final users = FiberText.linkedUsers(FiberStore.layout.value, oltId, e.onuKeys, onus);
    if (users.isEmpty) return;
    if (!await FiberApi.claimBack(e.id)) return;
    await BroadcastApi.broadcast(intent: MessageIntent.general, message: settings.backMessage, targetUsernames: users);
  }

  Future<void> _probeCaps(SnmpV2c snmp, VsolOltStats s, DateTime now) async {
    try {
      final c = await OltFiberReads.probe(snmp, profile, s.onus, now: now);
      caps = c;
      final js = c.toJson();
      FiberStore.applyCaps(oltId, js);
      await FiberApi.reportCaps(oltId, js);
      notifyListeners();
    } catch (_) {/* أفضل جهد */}
  }

  Future<void> _uploadRx(DateTime now) async {
    final book = FiberStore.bookOf(oltId);
    await FiberStore.persistBook(oltId, now: now);
    if (!FiberStore.serverReady || !book.hasDirty) return;
    final rows = book.takeDirty();
    if (!await FiberApi.uploadRx(oltId, rows)) book.restoreDirty(rows);
  }

  /// ONU واحدة حيّة الآن — قراءة الضوء وحدها بلا مسح.
  Future<BdcomOnuReading?> readOne(VsolOnu o) async {
    final community = await backend.community(device);
    if (community == null || !o.online) return null;
    return _readOptics(backend.snmp(device, community), o);
  }

  /// وضع الفنّي كلّ ثانيتين: حالة ONU واحدة من ifOperStatus (مصدر المسح نفسه) ثمّ ضوؤها إن كانت متّصلة — فيظهر
  /// رجوعها بعد التنظيف خلال ثانيتين لا بعد دورة المسح. `online: null` = الأولت لم يُجب.
  Future<({bool? online, BdcomOnuReading? reading})> probeOne(VsolOnu o) async {
    final community = await backend.community(device);
    if (community == null) return (online: null, reading: null);
    final snmp = backend.snmp(device, community);
    bool? up;
    try {
      if (profile.readsHsgqTables) {
        // HSGQ: حالة الـONU من جدول المصنّع — صفّها في IF-MIB لا يطابق موضعها.
        up = (await HsgqOlt.statusOf(snmp.get, [o.ifIndex]))?[o.ifIndex];
      } else {
        final vb = await snmp.get(['${OltFiberReads.ifOperStatusOid}.${o.ifIndex}']);
        final v = vb.isEmpty ? null : vb.first.asIntOrNull;
        if (v != null) up = v == 1;
      }
    } catch (_) {/* لا جواب — نجرّب الضوء على آخر حالةٍ معروفة */}
    if (up == false || (up == null && !o.online)) return (online: up, reading: null);
    final reading = await _readOptics(snmp, o.online ? o : o.copyWith(online: true));
    return (online: up ?? (reading != null ? true : null), reading: reading);
  }

  /// «التقط بالفصل» (وضع الفنّي): الفنّي يفصل ليف الجهاز اللي قدّامه فنعرفه بلا كتابة. عمود الحالة وحده (ifOperStatus —
  /// مصدر المسح نفسه، GETBULK خفيف) كلّ [every] حتى [window]، ويُقارن بأوّل قراءة: أوّل دورةٍ تغيّر فيها جهاز (انفصل،
  /// أو اختفى صفّه، أو رجع) تُرجع أجهزتها — أكثر من واحد بنفس اللحظة = عطل، والشاشة تخيّر. فارغ = لم يتغيّر شيء أو أُلغي.
  Future<List<({VsolOnu onu, bool nowOnline})>> catchChange({
    Duration window = const Duration(seconds: 90),
    Duration every = const Duration(seconds: 2),
    bool Function()? cancelled,
    void Function(int watched)? onStart,
  }) async {
    final s = stats;
    if (s == null || s.onus.isEmpty) return const [];
    final community = await backend.community(device);
    if (community == null) return const [];
    final snmp = backend.snmp(device, community);
    final byIf = {for (final o in s.onus) o.ifIndex: o};
    const base = OltFiberReads.ifOperStatusOid;
    Future<Map<int, bool>?> read() async {
      // HSGQ: عمود الحالة في جدول المصنّع بالـGET لكلّ ONU معروفة (~٧ دفعات لمئة، ~١٥٠ مللي) — لا مسح.
      if (profile.readsHsgqTables) {
        try {
          final got = await HsgqOlt.statusOf(snmp.get, byIf.keys);
          return got == null || got.isEmpty ? null : got;
        } catch (_) {
          return null;
        }
      }
      try {
        final rows = await snmp.walk(base, chunkSize: 50, maxIterations: 60);
        final out = <int, bool>{};
        for (final vb in rows) {
          if (!vb.oid.startsWith('$base.')) continue;
          final i = int.tryParse(vb.oid.substring(base.length + 1));
          final v = vb.asIntOrNull;
          if (i != null && v != null && byIf.containsKey(i)) out[i] = v == 1;
        }
        return out.isEmpty ? null : out;
      } catch (_) {
        return null;
      }
    }

    Map<int, bool>? first;
    final end = clock().add(window);
    while (clock().isBefore(end)) {
      if (cancelled?.call() == true) return const [];
      final now = await read();
      if (cancelled?.call() == true) return const [];
      if (now != null) {
        if (first == null) {
          first = now;
          onStart?.call(now.length);
        } else {
          final changed = [
            for (final e in first.entries)
              if ((now[e.key] ?? false) != e.value) (onu: byIf[e.key]!, nowOnline: now[e.key] ?? false),
          ];
          if (changed.isNotEmpty) {
            unawaited(refreshNow()); // المسح يلحق: لحظة السقوط وسببه
            return changed;
          }
        }
      }
      await Future<void>.delayed(every);
    }
    return const [];
  }

  Future<BdcomOnuReading?> _readOptics(SnmpV2c snmp, VsolOnu o) async {
    final Map<int, BdcomOnuReading> r = profile.readsBdcomEponTables
        ? await BdcomEpon.readings(snmp, [o.ifIndex])
        : profile.readsHsgqTables
            ? await HsgqOlt.readings(snmp.get, [o.ifIndex])
            : await OltFiberReads.vsolOptics(snmp, [o]);
    final reading = r[o.ifIndex];
    if (reading != null) {
      _optics[o.ifIndex] = reading;
      final rx = reading.rxDbm;
      if (FiberBands.plausible(rx)) FiberStore.bookOf(oltId).record(o.label, rx!, clock());
      _rebuild();
      notifyListeners();
    }
    return reading;
  }

  @visibleForTesting
  static void debugReset() {
    resetAll();
    backend = const FiberBackend();
    clock = DateTime.now;
  }
}
