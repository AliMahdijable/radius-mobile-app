import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../api/device_probe_api.dart';
import '../../core/util/format.dart';
import '../../core/util/server_time.dart';
import '../../models/device_health.dart';
import '../../models/merged_company.dart';
import '../../models/subscriber.dart';
import '../agent_net_presence.dart';
import '../connection_alerts.dart';
import '../merged_mode.dart';
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
/// ١. حاله من القائمة فوراً: فعّال/منتهي، متّصل/غير متّصل الآن (أو مطفي).
/// ٢. متّصلٌ وفعّال ⇒ جهازه: فحصٌ طازج من شبكتك ([DeviceProbeApi.probe] بشركته)، وإلّا آخر قراءةٍ عبر VPN شركته (٣٠ د)، وإلّا
///    فحصٌ عبر VPN شركته الآن (نفق الشركة يقرأ ضوء الأولت كذلك). والإشارة وCCQ والكيبل/الضوء بحدود «تنبيه المشترك».
/// ٣. جهازٌ لا يُقرأ بأيّ طريق ⇒ قسمه بكلمات «الفحص العامّ» وسببه (١٠ نوفمبر — كان «بلا إدارة»): «جهازه ما ردّ — لا يستجيب»،
///    «لم يُفحص — «ايرث لنك» تحتاج VPN»، «بلا مقاييس — …»؛ وغير المتّصل «غير متّصل الآن» كقسمه هناك.
class SubscriberVoiceCheck extends ChangeNotifier {
  SubscriberVoiceCheck(this.sub, {this.company});

  final Subscriber sub;

  /// «كل الشركات»: شركته (لنطاق فحص الـVPN وحدوده) — null خارج الوضع.
  final MergedCompany? company;

  VoiceCheckPhase phase = VoiceCheckPhase.ready;

  /// القراءة ومشاكلها بحدود المدير — null حتى تُقرأ أو إن لم تُقرأ.
  SubsCheckRow? row;

  /// قسمه حين لا قراءة لجهازه ([phase] done و[row] null) — كـ«الفحص العامّ»: «جهازه ما ردّ» · «بلا مقاييس» · «لم يُفحص».
  SubsCheckCat? cat;

  /// وسببه بعد اسم القسم.
  String? note;

  /// فحص الـVPN لشركته لم يكتمل حين انتهت المهلة (جارٍ أو شركته بالدور) ⇒ «لم يُفحص بعد — بانتظار الفحص» كصفّه في
  /// «الفحص العامّ»، والجواب يتحدّث وحده حين يكتمل (المراجعة ١٠ نوفمبر: كان «جهازه ما ردّ» والفحص لم يبلغه).
  bool waitingVpn = false;

  bool _disposed = false;

  // فحص الهاتف لهذا الجواب كما جرى: سُئل جهازه من شبكتك أم لا — يُحفظ عند البدء (بعد انتظار الـVPN قد تتغيّر حال
  // الشبكة أو «وضع VPN»، وكان يُعاد تقديره فيُقال «ما ردّ من شبكتك» لجهازٍ لم يسأله الهاتف) — وشركته تُقرأ من شبكتك،
  // وردّ بلا مقاييس.
  bool _localTried = false;
  bool _localWitness = true;
  bool _localNoMetrics = false;

  /// وقت قراءة الـVPN التي جاء منها الجواب — null لجوابٍ من فحص الهاتف أو بلا قراءة.
  DateTime? _vpnFrom;

  // انتظار فحص الـVPN: المهلة أو الإغلاق ⇒ يتوقّف ولا يبدأ فحصاً بعدها؛ ومتابعة الجاري حتى يكتمل.
  bool _gaveUp = false;
  Completer<void>? _wait;
  VoidCallback? _follow;

  // بدائل الاختبار
  @visibleForTesting
  static Future<DeviceHealthSnapshot?> Function(Subscriber s)? debugProbe;
  @visibleForTesting
  static Future<void> Function(Subscriber s, MergedCompany? c)? debugVpnRun;
  @visibleForTesting
  static bool Function()? debugLocalAllowed;
  @visibleForTesting
  static bool Function()? debugVpnAllowed;
  @visibleForTesting
  static Future<bool> Function(MergedCompany c)? debugIsOpen;
  @visibleForTesting
  static DateTime Function()? debugNow;

  static const probeTimeout = Duration(seconds: 15);
  static const vpnTimeout = Duration(minutes: 3);

  bool get expired => sub.isExpired;
  bool get online => sub.isOnline;
  bool get disabled => sub.isDisabled;

  /// يُقرأ جهازه: متّصلٌ وفعّال وغير مطفي.
  bool get wantsDevice => online && !expired && !disabled;

  ConnectionAlertThresholds get limits =>
      (sub.companyKey == null ? null : VpnNow.limitsOf(sub.companyKey!)) ?? ConnectionAlertSettings.current.value;

  /// «فعّال ومتّصل» · «منتهي وغير متّصل الآن» · «مطفي (معطّل)» — غير المتّصل بكلمة قسمه في «الفحص العامّ».
  String get headline {
    if (disabled) return 'مطفي (معطّل)${online ? ' — ومتّصل' : ''}';
    return '${expired ? 'منتهي' : 'فعّال'} و${online ? 'متّصل' : SubsCheckCat.offline.label}';
  }

  /// «باقي ١٢ يوم» / «منتهي منذ ٣ أيّام».
  String? get daysLine {
    final d = sub.remainingDays;
    if (d == null) return null;
    if (d < 0 || expired) return d == 0 ? 'انتهى اليوم' : 'منتهي منذ ${arDays(d.abs())}';
    if (d == 0) return 'ينتهي اليوم';
    return 'باقي ${arDays(d)}';
  }

  /// سطر الجهاز بأقسام «الفحص العامّ»: «بمشكلة — مشاكله» بحدود المدير، أو «… سليمة»، أو قسم من لم يُقرأ وسببه — والجواب كلّه
  /// بجملة ([spoken]).
  String? get deviceLine {
    if (!wantsDevice) return null;
    final r = row;
    if (r == null) {
      final c = cat;
      final label = c?.labelFor(running: waitingVpn);
      final n = note;
      return switch (phase) {
        VoiceCheckPhase.probing => 'يُقرأ جهازه من شبكتك…',
        VoiceCheckPhase.vpn => 'يُقرأ جهازه عبر VPN الشركة…',
        // سببٌ يبدأ باسم قسمه يُقال مرّةً كصفّه: «لم يُفحص بعد عبر VPN» لا «لم يُفحص — لم يُفحص…» (المراجعة الثانية)
        _ => label == null ? null : (n == null ? label : (n.startsWith(label) ? n : '$label — $n')),
      };
    }
    if (r.problems.isNotEmpty) return '${SubsCheckCat.problems.label} — ${r.problems.map((p) => p.label).join(' · ')}';
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

  /// الجواب بجملةٍ واحدة (للنسخ ولردٍّ صوتيٍّ لاحقاً) — وقراءة الـVPN القديمة بعمرها.
  String get spoken {
    final age = vpnAge;
    return [headline, daysLine, deviceLine, if (age != null) 'عبر VPN الشركة · $age'].whereType<String>().join(' · ');
  }

  /// عمر قراءة الـVPN التي جاء منها الجواب بكلمات «الفحص العامّ» («منذ 12 دقيقة») — null لفحص الهاتف الطازج أو
  /// لقراءةٍ من هذه الدقيقة (المراجعة ١٠ نوفمبر: آخر قراءةٍ عبر الـVPN — حتى ٣٠ د — كانت تُعرض بلا عمر كأنّها الآن).
  String? get vpnAge {
    final at = _vpnFrom;
    final now = debugNow?.call() ?? DateTime.now();
    if (at == null || now.difference(at).inMinutes < 1) return null;
    return timeAgoAr(at, now: now);
  }

  bool get _localAllowed =>
      debugLocalAllowed?.call() ?? (!VpnNow.mode.value && !AgentNetPresence.isOff && PermissionsService.subsCheckNet);

  bool get _vpnAllowed => debugVpnAllowed?.call() ?? PermissionsService.subsCheckVpn;

  /// لا قراءة: قسمه وسببه.
  void _miss(SubsCheckCat c, String? why) {
    cat = c;
    note = why;
  }

  /// قراءة الـVPN بلا مقاييس كسطرها في «الفحص العامّ»: البنك وحده ⇒ «جهازه ما ردّ» بسببه، وجهازٌ قُرئ بلا أرقام ⇒ «بلا مقاييس».
  void _unmeasured(VpnSubReading v) {
    final m = SubscribersCheck.unmeasured(sub, v);
    _miss(SubscribersCheck.catOf(m.why), m.why == SubsMissWhy.noMetrics ? _noMetricsWhy : SubscribersCheck.missText(m));
    _vpnFrom = _vpnAt();
  }

  static const _noMetricsWhy = 'جهازه ليس نانو ولا وحدةً ضوئيّة';

  /// «كل الشركات»: سبب شركته بكلمات صفّه في «الفحص العامّ» ([SubscribersCheck.missText]: «شركته تحتاج VPN»، «لم تُفحص
  /// شركته») — المراجعة الثالثة: كان ««ايرث لنك» تحتاج VPN» في الجواب. وخارجه السبب كما هو.
  String _companyWhy(String why) =>
      company == null ? why : SubscribersCheck.missText((sub: sub, why: SubsMissWhy.company, note: why));

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
    _vpnFrom = row?.reading?.vpn == true ? row!.reading!.at : null;
  }

  Future<void> run() async {
    if (!wantsDevice) {
      _set(VoiceCheckPhase.done);
      return;
    }
    // ١) من شبكتك: فحصٌ طازج لجهازه — وهل سُئل منها يُحفظ الآن ([_localTried])
    _localTried = _localAllowed;
    // فشله شهادةٌ على جهازه لشركةٍ تُقرأ من شبكتك وحدها (خارج «كل الشركات»، أو المفتوحة) — غيرها طريقه VPN شركته، كـ«الفحص
    // العامّ» (١٠ نوفمبر). والقراءة الناجحة قراءةٌ من أيّ شركة.
    if (_localTried) {
      final c = company;
      if (c != null) _localWitness = await (debugIsOpen?.call(c) ?? MergedMode.isOpenKey(c.key));
      if (_disposed) return;
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
      // ردّ جهازه بلا مقاييس (ليس نانو ولا ضوئيّاً) — يُقال إن لم يُقرأ عبر الـVPN
      _localNoMetrics = snap != null;
    }
    // ٢) آخر قراءةٍ عبر VPN شركته (٣٠ د) — والبنك وحده (يردّ بلا مقاييس) جوابٌ بسببه لا «سليم» (٩ نوفمبر). وشركته ما
    //    زالت تُفحص ⇒ الجواب منها يتحدّث حين يكتمل دورها (المراجعة الثالثة: كان يبقى «سليمة» وصفّه «لا يستجيب»)
    final v = VpnNow.readingFor(sub.username, company: sub.companyKey);
    if (v != null && !v.dead) {
      if (!v.measured) {
        _unmeasured(v);
        if (_vpnPending) _followVpn();
        return _set(VoiceCheckPhase.done);
      }
      _apply(vpn: v, vpnAt: _vpnAt());
      if (row != null) {
        if (_vpnPending) _followVpn();
        return _set(VoiceCheckPhase.done);
      }
    }
    // ٣) فحصٌ عبر VPN شركته الآن
    if (!_vpnAllowed) {
      if (!_localTried) {
        _miss(SubsCheckCat.unchecked, _companyWhy('الفحص عبر VPN غير مفعّل لك'));
      } else if (_localNoMetrics) {
        _miss(SubsCheckCat.noMetrics, _noMetricsWhy);
      } else if (_localWitness) {
        _miss(SubsCheckCat.noReply, 'من شبكتك');
      } else {
        _miss(SubsCheckCat.unchecked, _companyWhy('الفحص عبر VPN غير مفعّل لك'));
      }
      return _set(VoiceCheckPhase.done);
    }
    _set(VoiceCheckPhase.vpn);
    try {
      await (debugVpnRun?.call(sub, company) ?? _vpnRun()).timeout(vpnTimeout);
    } catch (_) {}
    // المهلة: الانتظار يتوقّف ولا يبدأ فحصاً بعدها (كان يبدأ فحصاً لم يطلبه أحد بعد ظهور الجواب)
    _stopWaiting();
    if (_disposed) return;
    _vpnAnswer();
    _set(VoiceCheckPhase.done);
  }

  /// الجواب بعد فحص الـVPN بقواعد «الفحص العامّ» ([SubscribersCheck.mixed]): قراءته، أو قسمه وسببه. فحص شركته لم
  /// يكتمل (جارٍ أو بالدور) ⇒ «لم يُفحص بعد — بانتظار الفحص» لا «ما ردّ»؛ ولا فحص مكتمل لشركته (أُلغي أو لم يجرِ) ⇒
  /// «لم يُفحص بعد عبر VPN» ([SubscribersCheck.vpnNotYetNote]) لا «لم يُقرأ عبر VPN» (المراجعة ١٠ نوفمبر). وما دام فحص
  /// شركته لم يكتمل يُتابَع — والجواب من قراءةٍ سابقة («لا يستجيب»…) كصفّه الآن يُستبدل بنتيجته حين يكتمل (المراجعة
  /// الثانية: كان يبقى «جهازه ما ردّ» والفحص قرأه سليماً).
  void _vpnAnswer() {
    row = null;
    cat = null;
    note = null;
    _vpnFrom = null;
    waitingVpn = false;
    final v = VpnNow.readingFor(sub.username, company: sub.companyKey);
    final pending = _vpnPending;
    if (v != null && !v.dead && !v.measured) {
      _unmeasured(v);
    } else if (v != null && !v.dead) {
      _apply(vpn: v, vpnAt: _vpnAt());
    } else if (v?.dead == true) {
      _miss(SubsCheckCat.noReply, 'لا يستجيب');
      _vpnFrom = _vpnAt();
    } else if (pending) {
      waitingVpn = true;
      _miss(SubsCheckCat.unchecked,
          SubscribersCheck.missText((sub: sub, why: SubsMissWhy.unchecked, note: null), running: true));
    } else {
      // لا قراءة له بأيّ طريق: شركته بلا طريق أو الفحص تعذّر ⇒ لم يُفحص؛ وفحصٌ مكتمل بلا قراءةٍ له ⇒ الخادم لم يسأل جهازه
      // (يوبيكويتي وحدها، والمؤجَّل) ⇒ «لم يُفحص» — إلّا إن سُئل من شبكتك وما ردّ (١٠ نوفمبر: كان «لا من شبكتك ولا عبر VPN»)
      // «كل الشركات»: سبب شركته كصفّه — والمفتوحة سُئل جهازها من شبكتها فلا سبب شركةٍ لها، وسطر الفحص المتعذّر لا يخصّه
      final cn = company == null || (_localTried && _localWitness) ? null : VpnNow.noteOf(company!.key);
      final why = cn != null
          ? _companyWhy(cn)
          : (company == null && VpnNow.subscribers.phase == VpnBarPhase.failed ? VpnNow.subscribers.line : null);
      if (why != null) {
        _miss(SubsCheckCat.unchecked, why);
      } else if (_localNoMetrics) {
        _miss(SubsCheckCat.noMetrics, _noMetricsWhy);
      } else if (_localTried && _localWitness) {
        _miss(SubsCheckCat.noReply, 'من شبكتك');
      } else {
        final checked = VpnNow.readingsAtFor(sub.companyKey) != null;
        _miss(SubsCheckCat.unchecked, checked ? SubscribersCheck.vpnUnreadNote : SubscribersCheck.vpnNotYetNote);
      }
    }
    if (pending) _followVpn();
  }

  /// فحص الـVPN لشركته لم يكتمل بعد: «كل الشركات» ⇒ شركته في الفحص الجاري ولم يُنتهَ منها (الحاليّة أو بالدور)؛ وخارجه
  /// ⇒ الفحص جارٍ (فحص المفتوحة نفسها).
  bool get _vpnPending {
    final c = company;
    return c == null ? VpnNow.subscribers.busy : VpnNow.subscribers.waits(c.key);
  }

  /// الجواب «لم يُفحص بعد» يُتابع الفحص الجاري: يكتمل لشركته ⇒ الجواب من نتيجته (بلا فحصٍ جديد).
  void _followVpn() {
    if (_follow != null) return;
    final job = VpnNow.subscribers;
    void l() {
      if (_disposed || _vpnPending) return;
      _unfollow();
      _vpnAnswer();
      notifyListeners();
    }

    _follow = l;
    job.addListener(l);
  }

  void _unfollow() {
    final l = _follow;
    if (l != null) VpnNow.subscribers.removeListener(l);
    _follow = null;
  }

  DateTime? _vpnAt() =>
      sub.companyKey == null ? VpnNow.readingsAt : (VpnNow.readingsAtFor(sub.companyKey) ?? VpnNow.readingsAt);

  /// فحص الـVPN لشركته وحدها (أو للمفتوحة خارج «كل الشركات») — وفحصٌ جارٍ يشملها يُنتظر لا يُكرَّر: «كل الشركات» ⇒
  /// دور شركته وحده (لا الفحص كلّه)، ونتيجته — قراءةٌ أو لا — هي الجواب؛ وفحصٌ جارٍ لغيرها يُنتظر ثمّ تُفحص هي. بعد
  /// المهلة أو الإغلاق لا يبدأ فحصاً.
  Future<void> _vpnRun() async {
    final job = VpnNow.subscribers;
    final c = company;
    if (job.busy) {
      final covered = c == null || job.queue.contains(c.key);
      await _until(() => c != null && covered ? !job.waits(c.key) : !job.busy);
      if (covered) return;
    }
    if (_gaveUp || _disposed) return;
    await (c != null ? job.run(only: [(key: c.key, name: c.name)]) : job.run());
  }

  /// ينتظر [ok] مع كلّ تغيّرٍ في فحص المشتركين — و[_stopWaiting] يقطعه.
  Future<void> _until(bool Function() ok) async {
    if (ok()) return;
    final job = VpnNow.subscribers;
    final done = _wait = Completer<void>();
    void l() {
      if (ok() && !done.isCompleted) done.complete();
    }

    job.addListener(l);
    try {
      await done.future;
    } finally {
      job.removeListener(l);
    }
  }

  void _stopWaiting() {
    _gaveUp = true;
    final w = _wait;
    if (w != null && !w.isCompleted) w.complete();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWaiting();
    _unfollow();
    super.dispose();
  }
}
