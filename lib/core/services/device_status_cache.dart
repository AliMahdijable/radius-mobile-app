import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/device_config.dart';
import '../../models/ont_info.dart';
import '../../models/ubiquiti_info.dart';
import '../../providers/device_provider.dart' show DeviceHealthSnapshot;

/// Persistent cache of CPE probe results, keyed by lowercase subscriber
/// username. Backed by SharedPreferences (already a dep) so cold-start
/// of the app immediately shows last-known status instead of a blank
/// screen while every probe runs from scratch.
///
/// On the next visit to the subscribers screen, the live probe wave
/// runs in the background and refreshes any rows that come back.
///
/// Persistence model:
///   - One JSON blob under [_kPrefsKey] holding the entire map
///   - Writes are debounced (300ms) so a probe wave that finishes 25
///     subs in 6s doesn't spam SharedPreferences with 25 disk writes.
class DeviceStatusCache {
  static const _kPrefsKey = 'device_status_cache_v1';
  static const _kStaleAfter = Duration(hours: 6);

  // Singleton — the screen and the providers all share one instance so
  // saves from the bulk probe wave reach the UI's lookups immediately
  // without waiting for the disk round-trip.
  static final DeviceStatusCache instance = DeviceStatusCache._();
  DeviceStatusCache._();

  final Map<String, _CachedEntry> _memory = {};
  bool _loaded = false;
  Timer? _saveTimer;
  Completer<void>? _loadCompleter;

  /// Loads the cache from disk into memory. Idempotent — subsequent
  /// calls await the same Future, so callers can `await ready` from
  /// anywhere without coordinating.
  Future<void> ready() async {
    if (_loaded) return;
    if (_loadCompleter != null) return _loadCompleter!.future;
    _loadCompleter = Completer<void>();
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_kPrefsKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (value is! Map) return;
            final entry = _CachedEntry.fromJson(Map<String, dynamic>.from(value));
            if (entry != null) {
              // Keys preserved verbatim — the screen's _probeCache and
              // the deviceStatusProvider both key by raw subscriber
              // username, so any normalization here would break the
              // filter/sort lookup against fresh probes.
              _memory[key.toString()] = entry;
            }
          });
          // Drop entries past the stale window so cold-start UI doesn't
          // show an answer from a week ago.
          final cutoff = DateTime.now().subtract(_kStaleAfter);
          _memory.removeWhere((_, e) => e.savedAt.isBefore(cutoff));
        }
      }
    } catch (_) {
      // Cache miss / parse failure is non-fatal — start with an empty
      // map and let the live probe re-populate.
    } finally {
      _loaded = true;
      _loadCompleter!.complete();
    }
  }

  /// Returns the cached snapshot for [username], or null if missing /
  /// not-yet-loaded. Callers should `await ready()` first to be sure.
  DeviceHealthSnapshot? get(String username) {
    final entry = _memory[username];
    return entry?.snap;
  }

  /// When the cached snapshot was probed — for "آخر فحص قبل Xs" UI.
  DateTime? probedAt(String username) {
    return _memory[username]?.savedAt;
  }

  /// Returns the entire map — useful for bulk seeding the screen's
  /// in-memory probe map on first frame.
  Map<String, DeviceHealthSnapshot> snapshotsByUsername() {
    return {
      for (final e in _memory.entries) e.key: e.value.snap,
    };
  }

  /// Stores [snap] for [username]. Persists to disk with a 300ms debounce
  /// so a probe-wave doesn't issue N back-to-back disk writes.
  void save(String username, DeviceHealthSnapshot snap) {
    _memory[username] = _CachedEntry(snap, DateTime.now());
    _scheduleSave();
  }

  /// Clears every cached row. Called on logout.
  Future<void> clear() async {
    _memory.clear();
    _saveTimer?.cancel();
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kPrefsKey);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _flush);
  }

  Future<void> _flush() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final e in _memory.entries) e.key: e.value.toJson(),
      });
      await sp.setString(_kPrefsKey, encoded);
    } catch (_) {
      // Disk pressure / quota issues — drop the write rather than
      // surface an error; the next save will succeed.
    }
  }
}

class _CachedEntry {
  final DeviceHealthSnapshot snap;
  final DateTime savedAt;
  _CachedEntry(this.snap, this.savedAt);

  Map<String, dynamic> toJson() {
    return {
      'savedAt': savedAt.toIso8601String(),
      'snap': _snapToJson(snap),
    };
  }

  static _CachedEntry? fromJson(Map<String, dynamic> j) {
    final savedAtStr = j['savedAt']?.toString();
    if (savedAtStr == null) return null;
    final savedAt = DateTime.tryParse(savedAtStr);
    if (savedAt == null) return null;
    final snapJson = j['snap'];
    if (snapJson is! Map) return null;
    final snap = _snapFromJson(Map<String, dynamic>.from(snapJson));
    if (snap == null) return null;
    return _CachedEntry(snap, savedAt);
  }
}

// ── Snapshot serialization ──────────────────────────────────────────
// We persist only the values the card actually displays + whatever the
// filter/sort logic needs to recompute. Anything optional (the full
// OntOpticalInfo, UbiquitiStatus baseUrl/peerMac) gets stripped because
// it's transient per-session and not worth a few KB on disk × 1000
// rows.

Map<String, dynamic> _snapToJson(DeviceHealthSnapshot s) {
  final Map<String, dynamic> base = {
    'kind': s.kind.toString(),
    'headlineLabel': s.headlineLabel,
    'headlineValue': s.headlineValue,
    'headlineHealth': s.headlineHealth,
    'secondaryLabel': s.secondaryLabel,
    'secondaryValue': s.secondaryValue,
    'secondaryHealth': s.secondaryHealth,
    'tertiaryLabel': s.tertiaryLabel,
    'tertiaryValue': s.tertiaryValue,
    'tertiaryHealth': s.tertiaryHealth,
  };
  if (s.ont != null) {
    base['ont'] = {
      'rxPower': s.ont!.rxPower,
      'txPower': s.ont!.txPower,
      'voltage': s.ont!.voltage,
      'temperature': s.ont!.temperature,
      'bias': s.ont!.bias,
      'sendStatus': s.ont!.sendStatus,
    };
  }
  if (s.ubiquiti != null) {
    base['ubnt'] = {
      'signalDbm': s.ubiquiti!.signalDbm,
      'ccqPercent': s.ubiquiti!.ccqPercent,
      'lanPorts': [
        for (final p in s.ubiquiti!.lanPorts)
          {'name': p.name, 'speed': p.speed, 'plugged': p.plugged},
      ],
    };
  }
  return base;
}

DeviceHealthSnapshot? _snapFromJson(Map<String, dynamic> j) {
  final kindStr = (j['kind'] ?? '').toString();
  final kind = kindStr.endsWith('ont')
      ? DeviceKind.ont
      : kindStr.endsWith('ubiquiti')
          ? DeviceKind.ubiquiti
          : DeviceKind.other;

  OntOpticalInfo? ont;
  final ontJson = j['ont'];
  if (ontJson is Map) {
    final m = Map<String, dynamic>.from(ontJson);
    ont = OntOpticalInfo(
      txPower: (m['txPower'] ?? '').toString(),
      rxPower: (m['rxPower'] ?? '').toString(),
      voltage: (m['voltage'] ?? '').toString(),
      temperature: (m['temperature'] ?? '').toString(),
      bias: (m['bias'] ?? '').toString(),
      sendStatus: (m['sendStatus'] ?? '--').toString(),
    );
  }

  UbiquitiStatus? ubnt;
  final ubntJson = j['ubnt'];
  if (ubntJson is Map) {
    final m = Map<String, dynamic>.from(ubntJson);
    final ports = <LanPort>[];
    final list = m['lanPorts'];
    if (list is List) {
      for (final p in list) {
        if (p is! Map) continue;
        final pm = Map<String, dynamic>.from(p);
        ports.add(LanPort(
          name: (pm['name'] ?? '').toString(),
          speed: pm['speed']?.toString(),
          plugged: pm['plugged'] == true,
        ));
      }
    }
    ubnt = UbiquitiStatus(
      hostname: '',
      firmware: '',
      uptimeSeconds: null,
      ssid: '',
      mode: '',
      signalDbm: m['signalDbm'] is int ? m['signalDbm'] as int : null,
      noiseFloorDbm: null,
      ccqPercent: m['ccqPercent'] is int ? m['ccqPercent'] as int : null,
      distanceMeters: null,
      txRateKbps: null,
      rxRateKbps: null,
      lanPorts: ports,
      peerMac: null,
      peerCount: null,
      baseUrl: '',
    );
  }

  return DeviceHealthSnapshot(
    kind: kind,
    headlineLabel: j['headlineLabel']?.toString(),
    headlineValue: j['headlineValue']?.toString(),
    headlineHealth: (j['headlineHealth'] ?? 'unknown').toString(),
    secondaryLabel: j['secondaryLabel']?.toString(),
    secondaryValue: j['secondaryValue']?.toString(),
    secondaryHealth: (j['secondaryHealth'] ?? 'unknown').toString(),
    tertiaryLabel: j['tertiaryLabel']?.toString(),
    tertiaryValue: j['tertiaryValue']?.toString(),
    tertiaryHealth: (j['tertiaryHealth'] ?? 'unknown').toString(),
    ont: ont,
    ubiquiti: ubnt,
  );
}
