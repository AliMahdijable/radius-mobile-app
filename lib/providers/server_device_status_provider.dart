import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/dio_client.dart';
import '../models/device_config.dart';
import '../models/subscriber_model.dart';
import 'device_provider.dart' show DeviceHealthSnapshot;
import '../models/ont_info.dart';
import '../models/ubiquiti_info.dart';

/// Polling refresh window — short enough that the admin perceives the
/// list as "live", but long enough that we don't flood the backend or
/// burn battery on stationary screens. The server-side stagger worker
/// already keeps each row at most ~30s stale, so a 5s poll is just
/// enough overlap to surface a new probe within one tick.
const _pollInterval = Duration(seconds: 5);

/// State held by [serverDeviceStatusProvider] — keyed by lowercase
/// subscriber username so callers can look up a row's snapshot in O(1).
class ServerDeviceStatusState {
  /// Snapshot per subscriber (lower-cased username key).
  final Map<String, DeviceHealthSnapshot> byUsername;

  /// "When was this row probed by the server?" — used to render the
  /// "آخر فحص قبل Xs" timestamp on the row + the global banner.
  final Map<String, DateTime> probedAt;

  /// Latest error message per subscriber (timeout, auth-fail, no-ip).
  final Map<String, String?> errors;

  /// When the last successful GET /api/devices/status returned.
  final DateTime? lastFetchedAt;

  /// True while a `/sync` or first `/status` is still in flight.
  final bool initializing;

  const ServerDeviceStatusState({
    this.byUsername = const {},
    this.probedAt = const {},
    this.errors = const {},
    this.lastFetchedAt,
    this.initializing = false,
  });

  ServerDeviceStatusState copyWith({
    Map<String, DeviceHealthSnapshot>? byUsername,
    Map<String, DateTime>? probedAt,
    Map<String, String?>? errors,
    DateTime? lastFetchedAt,
    bool? initializing,
  }) {
    return ServerDeviceStatusState(
      byUsername: byUsername ?? this.byUsername,
      probedAt: probedAt ?? this.probedAt,
      errors: errors ?? this.errors,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
      initializing: initializing ?? this.initializing,
    );
  }
}

class ServerDeviceStatusNotifier extends StateNotifier<ServerDeviceStatusState> {
  ServerDeviceStatusNotifier(this._ref)
      : super(const ServerDeviceStatusState());

  final Ref _ref;
  Timer? _pollTimer;
  bool _disposed = false;
  bool _syncInFlight = false;
  // Hash of the last list we synced — avoids hammering /sync when the
  // subscriber list is unchanged across rebuilds.
  String _lastSyncHash = '';

  /// Registers the admin's subscriber list with the backend stagger
  /// worker. Idempotent — call it whenever the list shape changes
  /// (filter chip, search, pull-to-refresh). Includes off-line subs so
  /// the server can still probe whichever ones have a known IP.
  Future<void> syncSubs(List<SubscriberModel> subs) async {
    if (_syncInFlight) return; // dedup overlapping calls
    final payload = <Map<String, String>>[];
    for (final s in subs) {
      final ip = (s.ipAddress ?? '').trim();
      if (ip.isEmpty) continue;
      payload.add({'username': s.username, 'ip': ip});
    }
    // Skip the round-trip when the visible list shape is unchanged.
    final hash = '${payload.length}|${payload.isEmpty ? '' : payload.first['username']}|${payload.isEmpty ? '' : payload.last['username']}';
    if (hash == _lastSyncHash && state.lastFetchedAt != null) {
      _ensurePolling();
      return;
    }
    _lastSyncHash = hash;
    _syncInFlight = true;

    if (!state.initializing) {
      state = state.copyWith(initializing: true);
    }
    final dio = _ref.read(backendDioProvider);
    try {
      await dio.post('/api/devices/sync', data: {'subscribers': payload});
    } catch (_) {
      // Sync failure is recoverable — the next poll will still fetch
      // whatever the server already has cached for this admin.
    }
    await _fetchOnce();
    _ensurePolling();
    _syncInFlight = false;
  }

  /// Force-probes one subscriber immediately. Called by the per-row
  /// refresh icon. Returns the new snapshot or null on failure so the
  /// caller can show a transient error.
  Future<DeviceHealthSnapshot?> forceProbe(String username, String ip) async {
    final dio = _ref.read(backendDioProvider);
    try {
      final res = await dio.post(
        '/api/devices/probe/$username',
        data: {'ip': ip},
      );
      final data = res.data;
      if (data is! Map || data['success'] != true) return null;
      final status = data['status'];
      if (status is! Map) return null;
      _ingestOne(Map<String, dynamic>.from(status));
      return state.byUsername[username.toLowerCase()];
    } catch (_) {
      return null;
    }
  }

  /// Clears local cache. Useful when admin signs out / switches admins.
  void reset() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _lastSyncHash = '';
    state = const ServerDeviceStatusState();
  }

  void _ensurePolling() {
    if (_disposed) return;
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _fetchOnce();
    });
  }

  Future<void> _fetchOnce() async {
    if (_disposed) return;
    final dio = _ref.read(backendDioProvider);
    try {
      final res = await dio.get('/api/devices/status');
      final data = res.data;
      if (data is! Map || data['success'] != true) return;
      final list = data['statuses'];
      if (list is! List) return;

      final byUsername = <String, DeviceHealthSnapshot>{};
      final probedAt = <String, DateTime>{};
      final errors = <String, String?>{};
      for (final item in list) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final username = (m['username'] ?? '').toString().toLowerCase();
        if (username.isEmpty) continue;
        final snap = _parseSnapshot(m);
        if (snap != null) byUsername[username] = snap;
        final probedStr = m['probedAt']?.toString();
        if (probedStr != null && probedStr.isNotEmpty) {
          final dt = DateTime.tryParse(probedStr);
          if (dt != null) probedAt[username] = dt;
        }
        final err = m['error']?.toString();
        if (err != null && err.isNotEmpty && err != 'null') {
          errors[username] = err;
        }
      }

      if (_disposed) return;
      state = state.copyWith(
        byUsername: byUsername,
        probedAt: probedAt,
        errors: errors,
        lastFetchedAt: DateTime.now(),
        initializing: false,
      );
    } catch (_) {
      if (_disposed) return;
      // Keep stale data; just clear the "initializing" flag so UI can
      // exit the spinner state instead of hanging on a flapping
      // network.
      if (state.initializing) {
        state = state.copyWith(initializing: false);
      }
    }
  }

  void _ingestOne(Map<String, dynamic> m) {
    final username = (m['username'] ?? '').toString().toLowerCase();
    if (username.isEmpty) return;
    final snap = _parseSnapshot(m);
    final probedStr = m['probedAt']?.toString();
    final probedAt = probedStr != null
        ? DateTime.tryParse(probedStr) ?? DateTime.now()
        : DateTime.now();
    final err = m['error']?.toString();

    final newByUsername = Map<String, DeviceHealthSnapshot>.from(state.byUsername);
    final newProbedAt = Map<String, DateTime>.from(state.probedAt);
    final newErrors = Map<String, String?>.from(state.errors);
    if (snap != null) {
      newByUsername[username] = snap;
    } else {
      newByUsername.remove(username);
    }
    newProbedAt[username] = probedAt;
    if (err != null && err.isNotEmpty && err != 'null') {
      newErrors[username] = err;
    } else {
      newErrors.remove(username);
    }
    state = state.copyWith(
      byUsername: newByUsername,
      probedAt: newProbedAt,
      errors: newErrors,
    );
  }

  /// Builds a [DeviceHealthSnapshot] from one wire-format row. Returns
  /// null when the row doesn't carry a probe result (e.g. error or
  /// "pending" while the worker hasn't reached this sub yet).
  DeviceHealthSnapshot? _parseSnapshot(Map<String, dynamic> m) {
    final kindStr = (m['kind'] ?? '').toString();
    if (kindStr.isEmpty) return null;
    final kind = kindStr == 'ont' ? DeviceKind.ont
              : kindStr == 'ubiquiti' ? DeviceKind.ubiquiti
              : DeviceKind.other;

    OntOpticalInfo? ont;
    if (kind == DeviceKind.ont) {
      final rx = (m['ontRxPower'] ?? '').toString();
      final tx = (m['ontTxPower'] ?? '').toString();
      final temp = (m['ontTemperature'] ?? '').toString();
      if (rx.isNotEmpty || tx.isNotEmpty || temp.isNotEmpty) {
        ont = OntOpticalInfo(
          txPower: tx,
          rxPower: rx,
          voltage: '',
          temperature: temp,
          bias: '',
          sendStatus: '--',
        );
      }
    }

    UbiquitiStatus? ubnt;
    if (kind == DeviceKind.ubiquiti) {
      final lanSpeed = m['lanSpeed']?.toString();
      final lanUp = m['lanUp'] == true || m['lanUp'] == 1;
      final port = lanSpeed != null && lanSpeed.isNotEmpty
          ? LanPort(name: 'eth0', speed: lanSpeed, plugged: lanUp)
          : null;
      ubnt = UbiquitiStatus(
        hostname: '',
        firmware: '',
        uptimeSeconds: null,
        ssid: '',
        mode: '',
        signalDbm: m['signalDbm'] is int ? m['signalDbm'] as int
                  : (m['signalDbm'] != null ? int.tryParse(m['signalDbm'].toString()) : null),
        noiseFloorDbm: null,
        ccqPercent: m['ccqPercent'] is int ? m['ccqPercent'] as int
                  : (m['ccqPercent'] != null ? int.tryParse(m['ccqPercent'].toString()) : null),
        distanceMeters: null,
        txRateKbps: null,
        rxRateKbps: null,
        lanPorts: port == null ? const [] : [port],
        peerMac: null,
        peerCount: null,
        baseUrl: '',
      );
    }

    return DeviceHealthSnapshot(
      kind: kind,
      headlineLabel: m['headlineLabel']?.toString(),
      headlineValue: m['headlineValue']?.toString(),
      headlineHealth: (m['headlineHealth'] ?? 'unknown').toString(),
      secondaryLabel: m['secondaryLabel']?.toString(),
      secondaryValue: m['secondaryValue']?.toString(),
      secondaryHealth: (m['secondaryHealth'] ?? 'unknown').toString(),
      tertiaryLabel: m['tertiaryLabel']?.toString(),
      tertiaryValue: m['tertiaryValue']?.toString(),
      tertiaryHealth: (m['tertiaryHealth'] ?? 'unknown').toString(),
      ont: ont,
      ubiquiti: ubnt,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    super.dispose();
  }
}

/// Provider — polls the backend cache while at least one widget watches
/// it. autoDispose's tiny grace window already absorbs short rebuild
/// flicker, so we don't pin manually; when the subscribers screen pops
/// the notifier disposes and the polling timer cancels.
final serverDeviceStatusProvider =
    StateNotifierProvider.autoDispose<ServerDeviceStatusNotifier, ServerDeviceStatusState>(
  (ref) => ServerDeviceStatusNotifier(ref),
);

/// Convenience selector for one row's snapshot. Returns null when the
/// server hasn't probed the device yet (or the probe is pending).
final subDeviceStatusProvider =
    Provider.family.autoDispose<DeviceHealthSnapshot?, String>((ref, username) {
  final state = ref.watch(serverDeviceStatusProvider);
  return state.byUsername[username.toLowerCase()];
});

/// Convenience selector for the row's last-probed timestamp.
final subDeviceProbedAtProvider =
    Provider.family.autoDispose<DateTime?, String>((ref, username) {
  final state = ref.watch(serverDeviceStatusProvider);
  return state.probedAt[username.toLowerCase()];
});
