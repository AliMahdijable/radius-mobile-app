import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/connection_auto_api.dart';
import '../api/device_probe_api.dart';
import '../models/device_health.dart';
import '../models/subscriber.dart';
import 'connection_alerts.dart';

/// يرفع قراءات أجهزة المشتركين الخام لـ«تنبيه المشترك» التلقائيّ (٣ نوفمبر) بعد كلّ موجة فحص في قائمة المشتركين.
///
/// * الخادم يقرّر (بحدود الوكيل) ويؤكّد ويمنع التكرار بين الأجهزة — هنا قياسٌ فقط، فلا كشف ولا رسالة.
/// * لا رفع إلّا لحسابٍ فتحه الخادم وتنبيهه مفعّل ووضعه غير يدويّ ([ConnAutoStatus.collects]).
/// * مشتركو الحساب نفسه وحدهم (لا صفوف شركةٍ أخرى في «كل الشركات» — حدودها وقوالبها عندها).
/// * لكلّ مشترك قراءةٌ كلّ [minGap] على الأكثر (التأكيد بالخادم يحتاج قراءتين بينهما ٣٠ د افتراضاً)، ودفعاتٌ ≤ [_batch].
/// * «لم نقرأ» لا تُرفع: جهازٌ لم يُفحص أو فشل فحصه لا يقول شيئاً.
class ConnectionReadingsUploader {
  ConnectionReadingsUploader._();

  static const minGap = Duration(minutes: 15);
  static const _batch = 300;
  static final Map<String, DateTime> _lastSent = {};
  static bool _busy = false;

  /// الاختبار: لقطة المشترك بدل كاش [DeviceProbeApi].
  @visibleForTesting
  static DeviceHealthSnapshot? Function(String username)? debugSnapshotOf;

  @visibleForTesting
  static void debugReset() {
    _lastSent.clear();
    _busy = false;
    debugSnapshotOf = null;
  }

  /// قراءة جهازٍ واحد كما يفهمها الخادم (normReading)، أو null إن لم يُقرأ شيء.
  @visibleForTesting
  static Map<String, dynamic>? readingFor(Subscriber s, DeviceHealthSnapshot snap) {
    final m = <String, dynamic>{
      if ((s.idx ?? '').trim().isNotEmpty) 'idx': s.idx!.trim(),
      'username': s.username,
      'name': s.fullName.trim(),
      if ((s.phone ?? '').trim().isNotEmpty) 'phone': s.phone!.trim(),
      'active': s.isActive && s.isEnabled,
    };
    var any = false;
    if (snap.kind == DeviceKind.ubiquiti && snap.ubnt != null) {
      final u = snap.ubnt!;
      m['device'] = 'ubnt';
      final lan = ConnectionAlerts.lanState(u);
      if (lan == ConnectionAlerts.lanUnplugged) {
        m['lan'] = 'unplugged';
        any = true;
      } else if (lan == ConnectionAlerts.lan10) {
        m['lan'] = '10';
        any = true;
      } else if (u.primaryLan?.plugged == true) {
        m['lan'] = 'ok';
        any = true;
      }
      final sig = u.signalDbm;
      if (sig != null && sig < 0) {
        m['signal'] = sig;
        any = true;
      }
      final ccq = u.ccqPercent;
      if (ccq != null && ccq > 0) {
        m['ccq'] = ccq;
        any = true;
      }
    } else if (snap.kind == DeviceKind.ont && snap.ont != null) {
      final o = snap.ont!;
      m['device'] = 'ont';
      final rx = double.tryParse(o.rxPower.trim());
      if (rx != null && rx < 0) {
        m['rx'] = rx;
        any = true;
      }
      final t = double.tryParse(o.temperature.trim());
      if (t != null && t > 0) {
        m['temp'] = t;
        any = true;
      }
    }
    return any ? m : null;
  }

  /// بعد موجة الفحص: ما في الكاش من لقطاتٍ حديثة لمشتركي الحساب ⇒ الخادم. لا ينتظره أحد.
  static Future<void> collect(Iterable<Subscriber> subs) async {
    if (_busy) return;
    _busy = true;
    try {
      final st = await ConnectionAutoApi.load();
      if (!st.collects) return;
      final now = DateTime.now();
      final out = <Map<String, dynamic>>[];
      final keys = <String>[];
      for (final s in subs) {
        if (s.companyKey != null || s.username.isEmpty) continue;
        final last = _lastSent[s.username];
        if (last != null && now.difference(last) < minGap) continue;
        final snap = (debugSnapshotOf ?? (u) => DeviceProbeApi.cachedForUser(u))(s.username);
        if (snap == null) continue;
        final r = readingFor(s, snap);
        if (r == null) continue;
        out.add(r);
        keys.add(s.username);
      }
      for (var i = 0; i < out.length; i += _batch) {
        final end = i + _batch > out.length ? out.length : i + _batch;
        final ok = await ConnectionAutoApi.uploadReadings(out.sublist(i, end));
        if (!ok) break; // الشبكة/الخادم ⇒ الموجة التالية تعيدها
        for (final k in keys.sublist(i, end)) {
          _lastSent[k] = now;
        }
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 conn readings upload: $e');
    } finally {
      _busy = false;
    }
  }
}
