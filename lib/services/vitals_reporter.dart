import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/agent_alerts_api.dart';
import '../models/network_device.dart';
import '../screens/network_devices/device_vitals.dart';

/// «القراءات الحسّاسة» (٤ نوفمبر — المرحلة ٢ من «تنبيهات الوكيل»، الخادم server/agentVitals.js): ما يقرؤه التطبيق من أجهزة الوكيل
/// (البطاقات، التسخين، اللوحة، وإعادة القراءة كلّ ١٠ د) يُرفع للخادم دفعةً كلّ دقيقة — المعالج والحرارة والفولتيّة والإشارة وCCQ — والخادم
/// يقرّر الإنذار (قراءتان، ومعدّل الجهاز نفسه للكهرباء والإشارة).
///   • لا يُرفع شيء ما لم تكن الميزة مفتوحةً لهذه الشركة ومفعّلةً عند الوكيل ([AgentAlertsApi.vitalsCached]).
///   • ردّ «active:false» (أُطفئت بالخادم) يوقفه ١٠ د؛ تعذّر الشبكة يُبقي الدفعة للمرّة القادمة.
///   • آخر قراءةٍ لكلّ جهاز وحدها (القراءة الأحدث تغلب) — لا تكدّس.
class VitalsReporter {
  VitalsReporter._();
  static final VitalsReporter instance = VitalsReporter._();

  static const flushEvery = Duration(minutes: 1);
  static const pauseOnInactive = Duration(minutes: 10);
  static const maxBatch = 300;

  final Map<int, Map<String, dynamic>> _pending = {};
  Timer? _timer;
  DateTime? _pausedUntil;
  bool _sending = false;

  @visibleForTesting
  static DateTime Function() now = DateTime.now;

  @visibleForTesting
  Map<int, Map<String, dynamic>> get pending => _pending;

  /// قراءة جهازٍ بما يقيسه فعلاً (لا صفر لما لم يُقرأ) ⇒ null إن لم يحمل شيئاً من الخمسة.
  @visibleForTesting
  static Map<String, dynamic>? readingOf(int id, DeviceGlance g) {
    final m = <String, dynamic>{'id': id};
    if (g.cpu != null) m['cpu'] = g.cpu;
    if (g.temp != null) m['temp'] = g.temp;
    final v = g.voltage;
    if (v != null && v > 0) m['volt'] = double.parse(v.toStringAsFixed(1));
    final s = g.signal;
    if (s != null && s < 0) m['signal'] = s;
    final c = g.ccq;
    if (c != null && c > 0) m['ccq'] = c;
    return m.length > 1 ? m : null;
  }

  bool get _wanted {
    final st = AgentAlertsApi.vitalsCached;
    if (st == null || !st.available || !st.settings.enabled) return false;
    final p = _pausedUntil;
    return p == null || now().isAfter(p);
  }

  /// يُستدعى بعد كلّ قراءةٍ ناجحة ([DeviceVitals.fetch]).
  void record(NetworkDevice d, DeviceGlance g) {
    if (!_wanted) return;
    final r = readingOf(d.id, g);
    if (r == null) return;
    _pending[d.id] = r;
    _timer ??= Timer(flushEvery, flush);
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_sending || _pending.isEmpty) return;
    if (!_wanted) {
      _pending.clear();
      return;
    }
    _sending = true;
    final batch = _pending.values.take(maxBatch).toList();
    for (final r in batch) {
      _pending.remove(r['id']);
    }
    try {
      final active = await AgentAlertsApi.uploadVitals(batch);
      if (active == false) {
        _pausedUntil = now().add(pauseOnInactive);
        _pending.clear();
      } else if (active == null) {
        // تعذّر الإرسال: تعود الدفعة — والأحدث منها (إن قُرئ أثناء الإرسال) يغلب
        for (final r in batch) {
          _pending.putIfAbsent(r['id'] as int, () => r);
        }
      }
    } finally {
      _sending = false;
      if (_pending.isNotEmpty) _timer ??= Timer(flushEvery, flush);
    }
  }

  /// تبديل الشركة/الخروج — لا تُرفع قراءات شركةٍ لأخرى.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _pausedUntil = null;
  }
}
