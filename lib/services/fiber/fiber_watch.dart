import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/network_devices_api.dart';
import '../../api/olt_profile.dart';
import '../../models/network_device.dart';
import '../permissions_service.dart';
import 'fiber_monitor.dart';
import 'fiber_store.dart';

/// مراقبة الأعطال بالخلفيّة على الحاسبة: أولتات الحساب التي بدأ الوكيل يرتّب شبكتها (صندوق أو ربط أو إعداد) وتنبيهاتها
/// شغّالة تُقرأ بإيقاعٍ هادئ ما دام البرنامج مفتوحاً ([FiberMonitor.acquire] بالخلفيّة) — فيصل إشعار العطل لهاتف الوكيل وهو
/// بعيد عن الشبكة. الهاتف لا يراقب بالخلفيّة: يقرأ وشاشاته مفتوحة فقط.
///
/// أولتٌ لم يُفتح قسم الألياف له قطّ لا يُقرأ — لا حِمل SNMP مفاجئ على حسابٍ لا يستعمل الميزة.
class FiberWatch {
  FiberWatch._();

  static const _every = Duration(minutes: 10);
  static final Set<int> _held = {};
  static Timer? _timer;
  static bool _running = false;

  /// للاختبار: قائمة الأجهزة.
  @visibleForTesting
  static Future<List<NetworkDevice>> Function() devices = NetworkDevicesApi.list;

  static Set<int> get held => Set.unmodifiable(_held);

  /// من غلاف الحاسبة عند تركيبه.
  static void start() {
    if (_running) return;
    _running = true;
    unawaited(sync());
    _timer = Timer.periodic(_every, (_) => unawaited(sync()));
  }

  /// عند إزالة الغلاف والخروج.
  static void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
    for (final id in _held) {
      FiberMonitor.existing(id)?.release(background: true);
    }
    _held.clear();
  }

  /// يطابق ما يُراقَب مع التخطيط الآن (يُستدعى أيضاً بعد حفظ الإعدادات).
  static Future<void> sync() async {
    if (!_running) return;
    if (!Perms.has('devices.monitor')) {
      _releaseAll();
      return;
    }
    await FiberStore.ensureLoaded();
    final l = FiberStore.layout.value;
    final engaged = <int>{
      for (final b in l.boxes.values) b.oltId,
      for (final r in l.onus.values) r.oltId,
      ...l.settings.keys,
    }..removeWhere((id) {
        final s = l.settingsOf(id);
        return !s.notifyOutages && !s.notifyPower;
      });
    if (engaged.isEmpty) {
      _releaseAll();
      return;
    }
    List<NetworkDevice> list;
    try {
      list = await devices();
    } catch (_) {
      return; // نعيد بالدورة القادمة — لا نُسقط ما يُراقَب الآن
    }
    if (!_running) return;
    final want = {
      for (final d in list)
        if (engaged.contains(d.id) && OltProfile.fromDevice(d).opensOltPanel) d.id: d,
    };
    for (final id in _held.toList()) {
      if (!want.containsKey(id)) {
        FiberMonitor.existing(id)?.release(background: true);
        _held.remove(id);
      }
    }
    for (final e in want.entries) {
      if (_held.add(e.key)) FiberMonitor.of(e.value).acquire(background: true);
    }
  }

  static void _releaseAll() {
    for (final id in _held) {
      FiberMonitor.existing(id)?.release(background: true);
    }
    _held.clear();
  }

  @visibleForTesting
  static void debugReset() {
    stop();
    devices = NetworkDevicesApi.list;
  }
}
