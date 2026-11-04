import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/company_route.dart';
import '../api/connection_auto_api.dart';
import '../api/device_probe_api.dart';
import '../models/device_health.dart';
import '../models/subscriber.dart';
import 'connection_alerts.dart';

/// يرفع قراءات أجهزة المشتركين الخام لـ«تنبيه المشترك» التلقائيّ (٣ نوفمبر) بعد كلّ موجة فحص في قائمة المشتركين.
///
/// * الخادم يقرّر (بحدود الوكيل) ويؤكّد ويمنع التكرار بين الأجهزة — هنا قياسٌ فقط، فلا كشف ولا رسالة.
/// * لا رفع إلّا لحسابٍ فتحه الخادم وتنبيهه مفعّل ووضعه غير يدويّ ([ConnAutoStatus.collects]).
/// * «كل الشركات» (٤ نوفمبر): صفوف كلّ شركةٍ تُرفع لشركتها بطلبٍ موجَّه ([CompanyRoute]) وبحالتها هي
///   ([ConnectionAutoApi.statusOf]) — حدودها وقوالبها ومحاكاتها عندها؛ وصفٌّ بمفتاحٍ غير صالح لا يُرفع أبداً.
/// * لكلّ مشترك قراءةٌ كلّ [minGap] على الأكثر (التأكيد بالخادم يحتاج قراءتين بينهما ٣٠ د افتراضاً)، ودفعاتٌ ≤ [_batch].
/// * «لم نقرأ» لا تُرفع: جهازٌ لم يُفحص أو فشل فحصه لا يقول شيئاً.
class ConnectionReadingsUploader {
  ConnectionReadingsUploader._();

  static const minGap = Duration(minutes: 15);
  static const _batch = 300;

  /// مفاتيح [_lastSent] و[_recheck] و[_subs] كلّها بـ[_key]: اسم المستخدم للشركة المفتوحة، و«مفتاح الشركة|الاسم» لصفوف
  /// «كل الشركات» (الاسم نفسه قد يتكرّر بين شركتين).
  static final Map<String, DateTime> _lastSent = {};
  static bool _busy = false;

  /// «تحت المراقبة» (٣ نوفمبر): موعد إعادة قياس كلّ مشتركٍ كما ردّه الخادم (أوّل قراءةٍ سيّئة + مدّة التأكيد) — يُقاس وحده عندها
  /// ([runRechecks]) فيتأكّد في وقته (٣ دقائق مثلاً) لا مع الموجة العامّة كلّ ١٥ دقيقة.
  static final Map<String, DateTime> _recheck = {};
  static final Map<String, Subscriber> _subs = {};

  /// الاختبار: فحصٌ مُجبَر بدل [DeviceProbeApi.probe].
  @visibleForTesting
  static Future<DeviceHealthSnapshot?> Function(Subscriber s)? debugProbe;

  /// مواعيد إعادة القياس المعلّقة (للاختبار والخدمة) — بمفاتيح [_key].
  static Map<String, DateTime> get pendingRechecks => Map.unmodifiable(_recheck);

  static String _key(String? company, String username) => company == null ? username : '$company|$username';

  /// صفوف القائمة بشركاتها، المفتوحة (null) أوّلاً. بلا اسم مستخدم أو بمفتاحٍ غير صالح ⇒ تُترك.
  static Map<String?, List<Subscriber>> _byCompany(Iterable<Subscriber> subs) {
    final out = <String?, List<Subscriber>>{};
    for (final s in subs) {
      final c = s.companyKey;
      if (s.username.isEmpty || (c != null && !CompanyRoute.keyRe.hasMatch(c))) continue;
      (out[c] ??= <Subscriber>[]).add(s);
    }
    final open = out.remove(null);
    return open == null ? out : {null: open, ...out};
  }

  static DeviceHealthSnapshot? _snapOf(Subscriber s) =>
      debugSnapshotOf != null ? debugSnapshotOf!(s.username) : DeviceProbeApi.cachedForUser(s.username, company: s.companyKey);

  /// قراءات [subs] (بترتيب [out]) ⇒ شركتها [company] بدفعاتٍ ≤ [_batch]؛ بعد كلّ دفعةٍ مقبولة: آخر رفعٍ لأصحابها، ومواعيد إعادة
  /// القياس كما ردّها الخادم. null = تعذّر (الموجة التالية تعيدها)؛ وإلّا ما فعله الخادم.
  static Future<({int usable, int watching, int confirmed, int resolved})?> _upload(
      String? company, List<Map<String, dynamic>> out, List<Subscriber> subs, DateTime now) async {
    var usable = 0, watching = 0, confirmed = 0, resolved = 0;
    for (var i = 0; i < out.length; i += _batch) {
      final end = i + _batch > out.length ? out.length : i + _batch;
      final r = await ConnectionAutoApi.uploadReadingsStats(out.sublist(i, end), companyKey: company);
      if (r == null) return null;
      usable += r.usable;
      watching += r.watching;
      confirmed += r.confirmed;
      resolved += r.resolved;
      for (final s in subs.sublist(i, end)) {
        final k = _key(company, s.username);
        _lastSent[k] = now;
        if (!r.due.containsKey(s.username)) _recheck.remove(k);
      }
      r.due.forEach((u, d) => _recheck[_key(company, u)] = d);
    }
    return (usable: usable, watching: watching, confirmed: confirmed, resolved: resolved);
  }

  /// الاختبار: لقطة المشترك بدل كاش [DeviceProbeApi].
  @visibleForTesting
  static DeviceHealthSnapshot? Function(String username)? debugSnapshotOf;

  @visibleForTesting
  static void debugReset() {
    _lastSent.clear();
    _busy = false;
    debugSnapshotOf = null;
    debugProbe = null;
    _recheck.clear();
    _subs.clear();
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

  /// يقيس من حان موعد إعادة قياسه (فحصٌ مُجبَر لجهازه وحده) ويرفع قراءته فوراً لشركته — تجاوزاً لـ[minGap]. يُنادى من خدمة الخلفيّة.
  static Future<int> runRechecks({DateTime? now}) async {
    if (_busy || _recheck.isEmpty) return 0;
    final t = now ?? DateTime.now();
    final due = _recheck.entries.where((e) => !e.value.isAfter(t)).map((e) => e.key).take(40).toList();
    if (due.isEmpty) return 0;
    _busy = true;
    var n = 0;
    try {
      final groups = <String?, List<Subscriber>>{};
      for (final k in due) {
        _recheck.remove(k);
        final s = _subs[k];
        if (s != null) (groups[s.companyKey] ??= <Subscriber>[]).add(s);
      }
      for (final g in groups.entries) {
        final company = g.key;
        final st = await ConnectionAutoApi.statusOf(company);
        if (!st.collects) {
          // أُطفئ أو صار يدويّاً لهذه الشركة ⇒ لا مواعيد لها
          _recheck.removeWhere((k, _) => _subs[k]?.companyKey == company);
          continue;
        }
        final out = <Map<String, dynamic>>[];
        final sent = <Subscriber>[];
        for (final s in g.value) {
          DeviceHealthSnapshot? snap;
          try {
            snap = debugProbe != null
                ? await debugProbe!(s)
                : await DeviceProbeApi.probe(
                    fallbackIp: (s.ipAddress ?? '').trim(), subscriberUsername: s.username, force: true, company: company);
          } catch (_) {
            snap = null;
          }
          if (snap == null) continue; // لم نقرأ ⇒ لا شيء (الموجة التالية)
          final r = readingFor(s, snap);
          if (r == null) continue;
          out.add(r);
          sent.add(s);
        }
        if (out.isEmpty) continue;
        final again = await ConnectionAutoApi.uploadReadings(out, companyKey: company);
        if (again == null) continue;
        for (final s in sent) {
          _lastSent[_key(company, s.username)] = t;
        }
        // ما زال تحت المراقبة (الساعة سبقت بثوانٍ) ⇒ موعده الجديد بهامش
        again.forEach((u, d) => _recheck[_key(company, u)] = d.add(const Duration(seconds: 5)));
        n += out.length;
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 conn rechecks: $e');
    } finally {
      _busy = false;
    }
    return n;
  }

  /// «افحص الآن» من شبكة الوكيل (٤ نوفمبر): كلّ لقطةٍ حديثة لمشتركي الحساب ⇒ الخادم **الآن** (تجاوزاً لـ[minGap]) ويُنتظر الإحصاء.
  /// للشركة المفتوحة وحدها (زرّ قسمها، ونتيجته تُعرض فيه). ينتظر رفعاً خلفيّاً جارياً ثمّ يمسك القفل. null = التنبيه غير مفعّل/يدويّ،
  /// أو تعذّر الرفع.
  static Future<({int sent, int usable, int watching, int confirmed, int resolved})?> collectNow(Iterable<Subscriber> subs) async {
    for (var i = 0; i < 60 && _busy; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    _busy = true;
    try {
      final st = await ConnectionAutoApi.load(force: true);
      if (!st.collects) return null;
      final now = DateTime.now();
      final out = <Map<String, dynamic>>[];
      final sent = <Subscriber>[];
      for (final s in subs) {
        if (s.companyKey != null || s.username.isEmpty) continue;
        _subs[s.username] = s;
        final snap = _snapOf(s);
        if (snap == null) continue;
        final r = readingFor(s, snap);
        if (r == null) continue;
        out.add(r);
        sent.add(s);
      }
      final r = await _upload(null, out, sent, now);
      if (r == null) return null;
      return (sent: out.length, usable: r.usable, watching: r.watching, confirmed: r.confirmed, resolved: r.resolved);
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 conn readings now: $e');
      return null;
    } finally {
      _busy = false;
    }
  }

  /// بعد موجة الفحص: ما في الكاش من لقطاتٍ حديثة لمشتركي القائمة ⇒ الخادم، كلّ شركةٍ لشركتها. لا ينتظره أحد.
  static Future<void> collect(Iterable<Subscriber> subs) async {
    if (_busy) return;
    _busy = true;
    try {
      final now = DateTime.now();
      for (final g in _byCompany(subs).entries) {
        final company = g.key;
        final st = await ConnectionAutoApi.statusOf(company);
        if (!st.collects) continue;
        final out = <Map<String, dynamic>>[];
        final sent = <Subscriber>[];
        for (final s in g.value) {
          final k = _key(company, s.username);
          _subs[k] = s;
          final last = _lastSent[k];
          if (last != null && now.difference(last) < minGap) continue;
          final snap = _snapOf(s);
          if (snap == null) continue;
          final r = readingFor(s, snap);
          if (r == null) continue;
          out.add(r);
          sent.add(s);
        }
        await _upload(company, out, sent, now); // null = الشبكة/الخادم ⇒ الموجة التالية تعيدها
      }
    } catch (e) {
      if (!kReleaseMode) debugPrint('🔴 conn readings upload: $e');
    } finally {
      _busy = false;
    }
  }
}
