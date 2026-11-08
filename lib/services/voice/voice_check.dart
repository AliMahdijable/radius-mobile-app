import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/device_probe_api.dart';
import '../../core/util/format.dart';
import '../../models/device_health.dart';
import '../../models/merged_company.dart';
import '../../models/subscriber.dart';
import '../agent_net_presence.dart';
import '../connection_alerts.dart';
import '../permissions_service.dart';
import '../subscribers_check.dart';
import '../vpn_now.dart';

/// أين وصل جواب «افحص المشترك فلان».
enum VoiceCheckPhase {
  /// حاله من القائمة وحدها (طافي أو منتهي أو مطفي ⇒ لا جهاز يُقرأ).
  ready,

  /// يُقرأ جهازه من شبكتك (فحصٌ طازج).
  probing,

  /// يُفحص عبر VPN شركته.
  vpn,

  done,
}

/// جواب «افحص المشترك فلان» (٨ نوفمبر — المالك: «حتى لو فاتح اكثر من شركه او شركه فرديه، من يسوي مثلا فحص المشترك فلان… الكارت
/// مباشره يجاوبه قبل يا اما مخلص متصل ومخلص طافي اذا متصل وفعال شنو حاله السي سي كيو، حاله الاشاره اذا كان موجود مانجمنت»):
///
/// ١. حاله من القائمة فوراً: فعّال/منتهي، متّصل/طافي (أو مطفي).
/// ٢. متّصلٌ وفعّال ⇒ جهازه: فحصٌ طازج من شبكتك ([DeviceProbeApi.probe] بشركته)، وإلّا آخر قراءةٍ عبر VPN شركته (٣٠ د)، وإلّا
///    فحصٌ عبر VPN شركته الآن (نفق الشركة يقرأ ضوء الأولت كذلك). والإشارة وCCQ والكيبل/الضوء بحدود «تنبيه المشترك».
/// ٣. جهازٌ لا يُقرأ بأيّ طريق ⇒ «بلا إدارة» بسببه (لا يردّ، شركته تحتاج VPN، الفحص غير مفعّل لك).
class SubscriberVoiceCheck extends ChangeNotifier {
  SubscriberVoiceCheck(this.sub, {this.company});

  final Subscriber sub;

  /// «كل الشركات»: شركته (لنطاق فحص الـVPN وحدوده) — null خارج الوضع.
  final MergedCompany? company;

  VoiceCheckPhase phase = VoiceCheckPhase.ready;

  /// القراءة ومشاكلها بحدود المدير — null حتى تُقرأ أو إن لم تُقرأ.
  SubsCheckRow? row;

  /// لماذا لا قراءة لجهازه (حين [phase] done و[row] null).
  String? note;

  bool _disposed = false;

  // بدائل الاختبار
  @visibleForTesting
  static Future<DeviceHealthSnapshot?> Function(Subscriber s)? debugProbe;
  @visibleForTesting
  static Future<void> Function(Subscriber s, MergedCompany? c)? debugVpnRun;
  @visibleForTesting
  static bool Function()? debugLocalAllowed;
  @visibleForTesting
  static bool Function()? debugVpnAllowed;

  static const probeTimeout = Duration(seconds: 15);
  static const vpnTimeout = Duration(minutes: 3);

  bool get expired => sub.isExpired;
  bool get online => sub.isOnline;
  bool get disabled => sub.isDisabled;

  /// يُقرأ جهازه: متّصلٌ وفعّال وغير مطفي.
  bool get wantsDevice => online && !expired && !disabled;

  ConnectionAlertThresholds get limits =>
      (sub.companyKey == null ? null : VpnNow.limitsOf(sub.companyKey!)) ?? ConnectionAlertSettings.current.value;

  /// «فعّال ومتّصل» · «منتهي وطافي» · «مطفي (معطّل)».
  String get headline {
    if (disabled) return 'مطفي (معطّل)${online ? ' — ومتّصل' : ''}';
    return '${expired ? 'منتهي' : 'فعّال'} و${online ? 'متّصل' : 'طافي'}';
  }

  /// «باقي ١٢ يوم» / «منتهي منذ ٣ أيّام».
  String? get daysLine {
    final d = sub.remainingDays;
    if (d == null) return null;
    if (d < 0 || expired) return d == 0 ? 'انتهى اليوم' : 'منتهي منذ ${arDays(d.abs())}';
    if (d == 0) return 'ينتهي اليوم';
    return 'باقي ${arDays(d)}';
  }

  /// سطر الجهاز: مشاكله بحدود المدير، أو «سليم»، أو لماذا لم يُقرأ — والجواب كلّه بجملة ([spoken]).
  String? get deviceLine {
    if (!wantsDevice) return null;
    final r = row;
    if (r == null) {
      return switch (phase) {
        VoiceCheckPhase.probing => 'يُقرأ جهازه من شبكتك…',
        VoiceCheckPhase.vpn => 'يُقرأ جهازه عبر VPN الشركة…',
        _ => note == null ? null : 'بلا إدارة — $note',
      };
    }
    if (r.problems.isNotEmpty) return r.problems.map((p) => p.label).join(' · ');
    final x = r.reading;
    final parts = <String>[
      if (x?.sig != null) 'الإشارة',
      if (x?.ccq != null) 'CCQ',
      if (x?.lan != null) 'الكيبل',
      if (x?.rx != null) 'الضوء',
    ];
    if (parts.isEmpty) return 'جهازه يردّ';
    return '${parts.length == 1 ? parts.first : '${parts.sublist(0, parts.length - 1).join('، ')} و${parts.last}'} سليمة';
  }

  /// الجواب بجملةٍ واحدة (للنسخ ولردٍّ صوتيٍّ لاحقاً).
  String get spoken => [headline, daysLine, deviceLine].whereType<String>().join(' · ');

  bool get _localAllowed =>
      debugLocalAllowed?.call() ??
      (!VpnNow.mode.value && !AgentNetPresence.isOff && PermissionsService.subsCheckNet);

  bool get _vpnAllowed => debugVpnAllowed?.call() ?? PermissionsService.subsCheckVpn;

  void _set(VoiceCheckPhase p) {
    if (_disposed) return;
    phase = p;
    notifyListeners();
  }

  /// القراءة ⇒ المشاكل بحدود المدير — كـ«الفحص العامّ» حرفاً ([SubscribersCheck.mixed]).
  void _apply({DeviceHealthSnapshot? snap, VpnSubReading? vpn, DateTime? vpnAt}) {
    final r = SubscribersCheck.mixed(
      [sub],
      (_) => limits,
      peek: (_) => snap == null ? null : (snap: snap, stale: false, at: DateTime.now()),
      reading: (_) => vpn,
      readAt: (_) => vpnAt,
    );
    row = [...r.rows, ...r.healthy].firstOrNull;
  }

  Future<void> run() async {
    if (!wantsDevice) {
      _set(VoiceCheckPhase.done);
      return;
    }
    // ١) من شبكتك: فحصٌ طازج لجهازه
    if (_localAllowed) {
      _set(VoiceCheckPhase.probing);
      DeviceHealthSnapshot? snap;
      try {
        snap = await (debugProbe?.call(sub) ??
                DeviceProbeApi.probe(
                  fallbackIp: (sub.ipAddress ?? '').trim(),
                  subscriberUsername: sub.username,
                  force: true,
                  company: sub.companyKey,
                ))
            .timeout(probeTimeout);
      } catch (_) {
        snap = null;
      }
      if (_disposed) return;
      if (snap != null && SubsReading.ofSnapshot(snap, DateTime.now()) != null) {
        _apply(snap: snap);
        if (row != null) return _set(VoiceCheckPhase.done);
      }
    }
    // ٢) آخر قراءةٍ عبر VPN شركته (٣٠ د)
    var v = VpnNow.readingFor(sub.username, company: sub.companyKey);
    if (v != null && !v.dead) {
      _apply(vpn: v, vpnAt: _vpnAt());
      if (row != null) return _set(VoiceCheckPhase.done);
    }
    // ٣) فحصٌ عبر VPN شركته الآن
    if (!_vpnAllowed) {
      note = _localAllowed ? 'جهازه ما ردّ من شبكتك' : 'الفحص عبر VPN غير مفعّل لك';
      return _set(VoiceCheckPhase.done);
    }
    _set(VoiceCheckPhase.vpn);
    try {
      await (debugVpnRun?.call(sub, company) ?? _vpnRun()).timeout(vpnTimeout);
    } catch (_) {}
    if (_disposed) return;
    v = VpnNow.readingFor(sub.username, company: sub.companyKey);
    if (v != null && !v.dead) {
      _apply(vpn: v, vpnAt: _vpnAt());
    } else {
      note = v?.dead == true
          ? 'جهازه ما يردّ'
          : (company != null ? VpnNow.noteOf(company!.key) : null) ??
              (VpnNow.subscribers.phase == VpnBarPhase.failed ? VpnNow.subscribers.line : null) ??
              'جهازه ما ردّ لا من شبكتك ولا عبر VPN';
    }
    _set(VoiceCheckPhase.done);
  }

  DateTime? _vpnAt() =>
      sub.companyKey == null ? VpnNow.readingsAt : (VpnNow.readingsAtFor(sub.companyKey) ?? VpnNow.readingsAt);

  /// فحص الـVPN لشركته وحدها (أو للمفتوحة خارج «كل الشركات») — وفحصٌ جارٍ يُنتظر لا يُكرَّر.
  Future<void> _vpnRun() async {
    final job = VpnNow.subscribers;
    if (job.busy) {
      final done = Completer<void>();
      void l() {
        if (!job.busy && !done.isCompleted) done.complete();
      }

      job.addListener(l);
      try {
        await done.future;
      } finally {
        job.removeListener(l);
      }
      if (VpnNow.readingFor(sub.username, company: sub.companyKey) != null) return;
    }
    final c = company;
    await (c != null ? job.run(only: [(key: c.key, name: c.name)]) : job.run());
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
