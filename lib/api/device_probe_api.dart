import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/net/huawei_ont_service.dart';
import '../core/net/tenda_service.dart';
import '../core/net/zte_ont_service.dart';
import '../core/net/tplink_agile_service.dart';
import '../core/net/tplink_classic_service.dart';
import '../core/net/tplink_pharos_service.dart';
import '../core/net/ubiquiti_service.dart';
import '../core/net/tcp_reachability.dart';
import '../core/net/windows_icmp.dart';
import '../models/device_health.dart';
import '../services/client_diag.dart';
import 'company_route.dart';
import 'device_config_api.dart';

/// لماذا لا قراءة لجهاز المشترك — يقوله الكرت بدل «لم يُتمكّن من الوصول» لكلّ شيء.
enum ProbeIssue {
  /// الجهاز ما يجاوب (أو ليس ONT/UBNT معروفاً).
  unreachable,

  /// الجهاز جاوب ورفض اليوزر أو الباسورد.
  loginRejected,

  /// اعتماداتٌ دخلت قبل ورُفضت الآن: صفحة الجهاز مفتوحة بمكانٍ ثانٍ.
  busy,

  /// قافلٌ دقيقة بعد ثلاث محاولاتٍ خاطئة.
  locked,

  /// دخلنا وما رجعت صفحة الضوء.
  readFailed,

  /// دخلنا والصفحات تُجاب، ولا ضوء فيها بصيغةٍ نعرفها — طرازٌ جديد (أثره يُبلَّغ بلا قيم).
  unknownFormat,

  /// جهاز ZTE أو TP-Link ولا يوزر له من الوكيل — لا نجرّب افتراضاً من عندنا.
  needsCredentials,

  /// TP-Link عدّ محاولات دخولٍ غلط كثيرة (دون القفل) — لا نزيدها حتى لا ينقفل.
  tooManyFails,

  /// TP-Link جديد لم يُضبط، أو يطلب تغيير كلمة سرّه من صفحته أوّلاً.
  needsSetup,
}

/// Device probe API — 3-tier credential fallback (per-sub → admin → library)
/// with a stack of caches:
///
///   [_snapCache]     IP → snapshot, 5-min TTL. الأساسي.
///   [_snapByUser]    username → snapshot (نفس entry، فهرس ثاني للـUI).
///   [_kindByIp]      IP → آخر kind ناجح (ONT/UBNT). يجعل الـprobe التالي
///                    يذهب مباشرة للنوع الصحيح بدلاً من parallel race.
///                    مطلب المستخدم 2026-07-12 (تسريع ~50%).
///   [_deadCache]     IP → آخر وقت فشل. IPs الميتة تُتَجاهل 2 دقيقة قبل
///                    إعادة المحاولة (مطلب 2026-07-12، توفير bandwidth
///                    على silent refresh).
///   [_persistPrefs]  SharedPreferences يحفظ _snapCache على القرص بين
///                    الجلسات (مطلب 2026-07-12، "instant load").
///
/// Waves تدعم priority queue: الـpriorityUsernames تُفحص أوّلاً، الباقي
/// يلحق. يُستعمل مع viewport-visible subs في list view.
///
/// «كل الشركات» (٢٢ أكتوبر): كلّ نداءٍ يأخذ `company` (مفتاح شركة الصفّ، null في الوضع العاديّ). الفحص نفسه من الهاتف
/// إلى الجهاز كما هو؛ إعداد المشترك وافتراضات المدير من شركته (موجَّهة)، وكلّ مفاتيح الكاش بها
/// ([DeviceConfigApi.scoped]) — والوضع العاديّ بمفاتيحه القديمة حرفاً.
class DeviceProbeApi {
  static final _snapCache = <String, _Cached>{};
  static final _snapByUser = <String, _Cached>{};
  static final _kindByIp = <String, DeviceKind>{};
  static final _deadCache = <String, DateTime>{};

  /// الفحوص الجارية الآن، مفهرسة بالعنوان الفعّال. تمنع فحصين
  /// متوازيين لجهاز واحد حين تتزامن موجة القائمة مع فتح كارت.
  static final _inFlight = <String, Future<DeviceHealthSnapshot?>>{};

  /// سبب آخر فشلٍ بمفتاح العنوان وبمفتاح المشترك (العنوان الفعّال قد يكون مخصّصاً لا يعرفه الكرت).
  /// [vendor] من سجّل السبب (`zte` · `tplink`) — الكرت يصوغ جملته بحسبه (قفل ZTE دقيقة، وTP-Link ساعتان).
  static final _issueByKey = <String, ({ProbeIssue issue, int? lockLeft, DateTime at, String? vendor})>{};
  static final _issueByUser = <String, ({ProbeIssue issue, int? lockLeft, DateTime at, String? vendor})>{};

  /// عناوين بُلِّغ أثر «دخلنا ولم نقرأ الضوء» لها في هذه الجلسة.
  static final _readReported = <String>{};

  /// طول جزء رسالة التشخيص (الخادم يقصّ عند ٣٠٠)، وأقصى عدد أجزاء (أسماء صفحات جهازٍ جديد قد تبلغ ألف حرف).
  static const _diagChunk = 290;
  static const _diagParts = 5;

  /// ما سجّله فرع ZTE في الفحص الجاري (بالعنوان) — يُقرأ بعد انتهائه.
  static final _zteIssue = <String, ({ProbeIssue issue, int? lockLeft, DateTime at, String trace})>{};

  /// ما سجّله فرع TP-Link في الفحص الجاري (بالعنوان) — كفرع ZTE: يُقرأ بعد انتهائه.
  static final _tplinkIssue = <String, ({ProbeIssue issue, int? lockLeft, DateTime at, String trace})>{};

  /// مراحل فرع ZTE في الفحص الجاري بأوقاتها (تعرّف ← دخول ← قراءة): فحصٌ انتهت مهلته يُعرف أين وقف، ويُمدَّد ما دام ZTE
  /// في منتصف عمله (صفحاته ~١٤٠ ك.ب وواجهته بطيئة).
  static final _zteSteps = <String, List<({String stage, DateTime at})>>{};

  /// مهلةٌ إضافيّة لجهاز ZTE تجاوز [_probeCap] وهو يعمل — لا تُمنح لجهازٍ لا يجاوب (موجة القائمة لا تنتظره).
  /// ٢٧ أكتوبر على MH80: أوّل «حفظ وفحص» انتهى عند ١٥ ثانية بلا سبب، والثاني قرأ الضوء.
  static Duration _zteExtra = const Duration(seconds: 15);

  /// للاختبار: مهلتان قصيرتان بدل ١٥+١٥ ثانية.
  @visibleForTesting
  static void debugCaps({required Duration probe, required Duration zteExtra}) {
    _probeCap = probe;
    _zteExtra = zteExtra;
  }

  static void _zteMark(String ip, String stage) =>
      (_zteSteps[ip] ??= []).add((stage: stage, at: DateTime.now()));
  static Future<AdminDeviceDefaults>? _adminFetch;

  /// افتراضات كلّ شركةٍ من «كل الشركات» — النجاح يُحفظ للجلسة كالوضع العاديّ، والفشل لا (يُعاد بعد قاطع الدقيقة).
  static final _adminFetchBy = <String, Future<AdminDeviceDefaults?>>{};

  static String _k(String? company, String s) =>
      DeviceConfigApi.scoped(company, s);

  static const _ttl = Duration(minutes: 5);

  /// عمر القراءة الطازجة: ما دونه لا تعيده الموجة ([needsProbe]) — «الفحص العامّ» يعدّه من موجته.
  static const ttl = _ttl;
  // يطابق v1: 15s cap على probe واحد.
  static Duration _probeCap = const Duration(seconds: 15);

  /// عدد العمّال المتزامنين في موجة الفحص.
  ///
  /// ── لماذا هذا الرقم بالذات ──────────────────────────────────────
  /// زمن الموجة محكومٌ بمعادلةٍ واحدة:
  ///
  ///     (عدد غير القابلين للوصول × ١٥ ثانية) ÷ عدد العمّال
  ///
  /// والخمس عشرة ثابتةٌ لا تُخفَّض: هي `_probeCap`، وتساوي مهلة
  /// `HuaweiOntService` تماماً — وقد رُفعت إلى هذا الحدّ بطلب صاحب
  /// المشروع (٢٠٢٦-٠٧-١٢) بعد أن كانت أربعاً «تفشل مبكراً». فالمتغيّر
  /// الوحيد المتاح هو المقام.
  ///
  /// ورُفع من ٢٥ إلى ٤٠ (٢٠٢٦-٠٩-١٤): يحذف ٣٧٪ من زمن الموجة. وعلى
  /// قائمةٍ فيها ٤٧ جهازاً غير قابلٍ للوصول: ٢٨ ثانية ← ١٨.
  ///
  /// ⚠️ ولم يُرفع إلى ٥٠ رغم أنّها تُنصّف الزمن: الفحص يخرج من الهاتف
  /// **مباشرةً إلى الشبكة المحلّيّة** لا عبر خادمنا، وكلّ فحصٍ يفتح
  /// سلسلتين متوازيتين (Huawei وUBNT). فأربعون عاملاً حِملٌ محسوس على
  /// شبكةٍ متواضعة، والخمسون أكثر. وهذه خطوةٌ تُقاس قبل الزيادة.
  ///
  /// وإن ظهر أثرٌ على الشبكة فالعودة سطرٌ واحد هنا.
  static const _defaultWorkers = 40;

  /// عمّال الموجة على خطٍّ بعيد (VPN من خارج شبكة الوكيل).
  ///
  /// 🐛 ٢٩ أكتوبر (المالك على الماك: «الاشارات مال اجهزه مجاي تظهر شي مثل التطبيق حتى بعد اكمال الفحص»): الحاسبة
  /// تصل أجهزة المشتركين عبر VPN — ذهابٌ وإيابٌ ٢١١–٣٠٠٠ ملّي ث (الوسيط ٥٦٥) بدل بضعٍ على شبكة الوكيل. أربعون عاملاً
  /// يفتح كلٌّ ثلاثة اتّصالاتٍ معاً خنقت النفق: نصف الاتّصالات بلا ردّ في دقيقة الموجة، والفحوص تجاوزت سقفها فلا قراءة؛
  /// وفتح المشترك وحده (فحصٌ واحد) يقرأ. فالموجة تقيس بُعد الخطّ أوّلاً ([_workersForLink]) وتنزل إلى هذا العدد عليه.
  static const _slowLinkWorkers = 8;

  /// وسيط زمن فتح الاتّصال فوق هذا = خطٌّ بعيد.
  static const _slowLinkConnect = Duration(milliseconds: 150);

  /// للاختبار: زمن فتح الاتّصال بدل الشبكة.
  @visibleForTesting
  static Future<Duration?> Function(String address)? debugConnectTime;

  /// للاختبار: فحصٌ وهميّ بدل الشبكة (العنوان ⇒ اللقطة).
  @visibleForTesting
  static Future<DeviceHealthSnapshot?> Function(String ip)? debugRunProbe;

  /// عمّال آخر موجة — للاختبار.
  @visibleForTesting
  static int? lastWaveWorkers;

  /// موجاتٌ يراها المستخدم الآن (قائمة المشتركين) — فحص الخلفيّة (DeviceWarmService) يتنحّى ما دامت > ٠ (الأولويّة للأمام).
  static int foregroundWaves = 0;

  /// للاختبار: نتيجة المشترك و/أو العنوان أقدم بـ[by].
  @visibleForTesting
  static void debugBackdate({String? username, String? ip, String? company, required Duration by}) {
    void back(Map<String, _Cached> m, String key) {
      final c = m[key];
      if (c != null) m[key] = _Cached(c.snap, c.at.subtract(by));
    }

    if (username != null) back(_snapByUser, _k(company, username));
    if (ip != null) back(_snapCache, _k(company, ip.trim()));
  }

  /// يُنادى حين تصل قراءةٌ بعد أن تخلّى عنها فحصها (تجاوز سقفه) فتُحفظ — يوقظ من يقرأ الكاش (الجدول والبطاقات عبر
  /// `DeviceProbeBus`)؛ هذه الطبقة لا تعرف الواجهة.
  static void Function()? onLateResult;

  // IPs الميتة نتجاهلها 2د قبل إعادة المحاولة (يُلغى بـforce أو نجاح جديد).
  static const _deadTtl = Duration(minutes: 2);

  static const _prefsKey = 'device_probe.cache.v1';
  static bool _hydrated = false;
  static Timer? _persistDebounce;

  // Library defaults — last-resort. Matches v1.
  static const _kOntUser = 'telecomadmin';
  static const _kOntPass = 'admintelecom';
  static const _kUbntUser = 'ubnt';
  static const _kUbntPass = 'ubnt';

  /// يُستدعى مرّة واحدة عند boot لاستعادة snapshots من الجلسة السابقة.
  /// آمن للاستدعاء المتكرّر (idempotent).
  static Future<void> hydrateFromPrefs() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final now = DateTime.now();
      for (final entry in data.entries) {
        final v = entry.value;
        if (v is! Map) continue;
        final at = DateTime.tryParse(v['at']?.toString() ?? '');
        if (at == null) continue;
        // نتجاهل entries أقدم من TTL — بيانات بائتة ما تفيد.
        if (now.difference(at) >= _ttl) continue;
        final snapJson = v['snap'];
        if (snapJson is! Map) continue;
        final snap =
            DeviceHealthSnapshot.fromJson(Map<String, dynamic>.from(snapJson));
        if (snap == null) continue;
        _snapCache[entry.key.toString()] = _Cached(snap, at);
        _kindByIp[entry.key.toString()] = snap.kind;
        final vendor = snap.ubnt?.vendor;
        if (vendor != null) _radioVendorByKey[entry.key.toString()] = vendor;
        // ملاحظة: _snapByUser لا يُستعاد لأن key الـpersist بـIP فقط.
        // الجلسة الجديدة رح تُعبّئ _snapByUser مع أوّل probe.
      }
    } catch (_) {
      // Corrupt data — امسحه بدل ما نبقى نفشل كل boot.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsKey);
      } catch (_) {}
    }
  }

  /// مسح كل الـcaches عند logout. Admin جديد قد يكون له defaults مختلفة
  /// وما نريد نلصق snapshots على IPs قد تنتمي لشبكة admin سابق.
  static Future<void> clearAllCaches() async {
    _snapCache.clear();
    _snapByUser.clear();
    _kindByIp.clear();
    _deadCache.clear();
    _reachCache.clear();
    _ontWinner.clear();
    _ubntWinner.clear();
    _tplinkWinner.clear();
    _radioVendorByKey.clear();
    _tplinkSeen.clear();
    _tpClassicSeen.clear();
    _tpAgileSeen.clear();
    TplinkPharosService.reset();
    TplinkClassicService.reset();
    TplinkAgileService.reset();
    TendaService.reset();
    _adminFetch = null;
    _adminFetchBy.clear();
    _persistDebounce?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  // ── فحص وصولٍ سريع (بنگ) ─────────────────────────────────────────
  // لمسة شبكة على عنوان الجهاز وحده — لا دخول ولا قراءة — تُظهر «واصل/لا»
  // خلال ~ثانية، قبل أن يكمل الفحص الكامل (دخولٌ وقراءةٌ ~٤ث). لا تنتظر جلسة
  // الساس: customIp المخزَّن يكفي، وإلّا عنوان الساس المتوفّر. ويندوز: ICMP من
  // النظام؛ غيره: اتّصال TCP على 80/443/8080.
  static final Map<String, ({bool ok, DateTime at})> _reachCache = {};
  static const _reachTtl = Duration(seconds: 20);

  /// `true` واصل · `false` لا يردّ · `null` لا عنوان بعد (فلا حكم).
  static Future<bool?> reachable({
    required String fallbackIp,
    String? subscriberUsername,
    String? company,
    bool force = false,
  }) async {
    var ip = fallbackIp.trim();
    if (subscriberUsername != null && subscriberUsername.isNotEmpty) {
      // peek فقط — لا جلبٌ شبكيّ: الفحص الكامل يجلب الإعداد، وهذا البنگ لا
      // يضيف طلباً. إن لم يكن customIp مخزَّناً بعد نُبنگ عنوان الساس، ويُعاد
      // البنگ من نهاية [_runInner] بعد أن يُعرف الإعداد.
      final custom = DeviceConfigApi.peekConfig(subscriberUsername, company: company)
          ?.customIp
          ?.trim();
      if (custom != null && custom.isNotEmpty) ip = custom;
    }
    if (ip.isEmpty) return null;
    final key = _k(company, ip);
    if (!force) {
      final hit = _reachCache[key];
      if (hit != null && DateTime.now().difference(hit.at) < _reachTtl) {
        return hit.ok;
      }
    }
    bool ok;
    try {
      // عنوانٌ بمنفذ (IP مخصّص خلف تحويل منفذ) ⇒ اتّصالٌ بذلك المنفذ نفسه على كلّ منصّة.
      ok = Platform.isWindows && TcpReachability.split(ip).port == null
          ? (await WindowsIcmp.ping(ip, count: 2, timeout: const Duration(seconds: 1)))
              .isNotEmpty
          : await TcpReachability.isReachable(ip);
    } catch (_) {
      ok = false;
    }
    _reachCache[key] = (ok: ok, at: DateTime.now());
    return ok;
  }

  /// Resolves credentials + probes the device.
  ///
  /// * [fallbackIp] — SAS4 IP لو موجود.
  /// * [subscriberUsername] — يُستعمل لجلب DeviceConfig (customIp override).
  /// * [force=true] — يتخطّى snapshot + dead caches (زر تحديث يدوي).
  /// * [company] — صفٌّ من «كل الشركات»: إعداده وافتراضاته من شركته، وكاشه بها.
  /// [retryLogin]: الوكيل حفظ إعداد الجهاز للتوّ ⇒ اعتماداتٌ رُفضت قبل تُجرَّب مرّةً أخرى، ولا يُشارَك فحصٌ جارٍ بإعدادٍ
  /// قديم، والنتيجة تُبلَّغ تشخيصاً (مرحلة الفشل بلا اعتمادات).
  static Future<DeviceHealthSnapshot?> probe({
    required String fallbackIp,
    String? subscriberUsername,
    bool force = false,
    bool retryLogin = false,
    String? company,
  }) async {
    final ip = fallbackIp.trim();

    // ⚠️ فحص كاش الـusername **قبل** `fetchConfig` لا بعده.
    //
    // كان الترتيب معكوساً: كلّ استدعاء يجلب DeviceConfig أوّلاً ثمّ
    // يفحص الكاش. فمَن يملك نتيجة طازجة أصلاً كان يدفع رحلة شبكيّة
    // قبل أن يُقال له «موجودة عندك». وهذا ما جعل فتح كارت مشترك يبدو
    // فحصاً ثانياً بعد فحص القائمة.
    //
    // الكاش بالـusername وحده آمن للاختصار المبكّر: الكاش بالـIP
    // مفهرس بالـIP **الفعّال** بعد تطبيق customIp، فقراءته بـfallbackIp
    // قد تُرجع نتيجة جهاز آخر لمشترك له تجاوز عنوان.
    final userKey = subscriberUsername == null || subscriberUsername.isEmpty
        ? null
        : _k(company, subscriberUsername);
    if (!force && userKey != null) {
      final byUser = _snapByUser[userKey];
      if (byUser != null && DateTime.now().difference(byUser.at) < _ttl) {
        return byUser.snap;
      }
    }

    DeviceConfig? cfg;
    String effectiveIp = ip;

    if (subscriberUsername != null && subscriberUsername.isNotEmpty) {
      cfg = await DeviceConfigApi.fetchConfig(subscriberUsername,
          company: company);
      final custom = cfg?.customIp?.trim();
      if (custom != null && custom.isNotEmpty) effectiveIp = custom;
    }
    if (effectiveIp.isEmpty) return null;
    final ipKey = _k(company, effectiveIp);
    // 🐛 ٢٧ أكتوبر: الحفظ يُبطل الـIP المخصّص وحده — ومشتركٌ على IP الساس (الحقل فارغ) بقي رفضه القديم محفوظاً، فـ«حفظ
    // وفحص الجهاز» لا يحاول أصلاً.
    if (retryLogin) {
      ZteOntService.forget(effectiveIp);
      TplinkPharosService.forget(effectiveIp, manual: true);
      TplinkClassicService.forget(effectiveIp);
      TplinkAgileService.forget(effectiveIp, manual: true);
      TendaService.forget(effectiveIp);
    }

    // Dead-IP short-circuit — إلا لو force. الـUI zاليدوي يتخطّى هذا.
    if (!force) {
      final deadAt = _deadCache[ipKey];
      if (deadAt != null && DateTime.now().difference(deadAt) < _deadTtl) {
        return null;
      }
    }

    // Snapshot cache
    if (!force) {
      final cached = _snapCache[ipKey];
      if (cached != null && DateTime.now().difference(cached.at) < _ttl) {
        // كمان نُثبّت _snapByUser لو مو موجود (hydrate case).
        if (userKey != null) {
          _snapByUser[userKey] ??= cached;
        }
        return cached.snap;
      }
    }

    // ⚠️ إلغاء ازدواج الفحوص الجارية على العنوان نفسه.
    //
    // بدونه: موجة القائمة تفحص جهازاً، وفي أثنائها يفتح المستخدم كارته
    // — فينطلق فحص ثانٍ متوازٍ لنفس العنوان لأنّ الكاش لا يمتلئ إلّا
    // بعد انتهاء الأوّل. جهاز واحد، فحصان، وضِعف الاستهلاك.
    final pending = _inFlight[ipKey];
    if (pending != null) {
      if (!retryLogin) return pending;
      await pending; // فحصٌ بإعدادٍ قديم: ننتظره ثمّ نفحص بالجديد.
    }

    final future = _probeAndStore(effectiveIp, cfg, userKey, company, report: retryLogin);
    _inFlight[ipKey] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(ipKey);
    }
  }

  /// الفحص الفعلي + تخزين النتيجة. مفصولة عن `probe` ليتمكّن
  /// `_inFlight` من مشاركة المستقبَل الواحد بين كلّ الطالبين.
  /// [userKey] مفتاح المشترك في الكاش (بشركته)، والعنوان نفسه يُفحص كما هو.
  static Future<DeviceHealthSnapshot?> _probeAndStore(
    String effectiveIp,
    DeviceConfig? cfg,
    String? userKey,
    String? company, {
    bool report = false,
  }) async {
    var reportNow = report;
    final ipKey = _k(company, effectiveIp);
    final defaults = await _loadAdminDefaults(company);
    final started = DateTime.now();
    _zteSteps.remove(effectiveIp);
    final run = debugRunProbe?.call(effectiveIp) ?? _runProbe(effectiveIp, cfg, defaults, ipKey);
    Future<({DeviceHealthSnapshot? snap, bool done})> within(Duration d) =>
        run.then((s) => (snap: s, done: true)).timeout(d, onTimeout: () => (snap: null, done: false));
    var r = await within(_probeCap);
    // ZTE في منتصف الدخول أو القراءة ⇒ نمهله بدل أن نقطعه بلا سبب.
    final zteBusy = (_zteSteps[effectiveIp] ?? const []).any((e) => e.stage != 'detect');
    if (!r.done && zteBusy) r = await within(_zteExtra);
    final snap = r.snap;
    final timedOut = !r.done;
    final now = DateTime.now();
    final entry = _Cached(snap, now);
    _snapCache[ipKey] = entry;
    if (userKey != null) {
      _snapByUser[userKey] = entry;
    }
    // السبب: ما سجّله فرع ZTE أو TP-Link في هذا الفحص نفسه (الجهاز أحدهما لا كلاهما)، وإلّا «ما يجاوب».
    final z = _zteIssue[effectiveIp];
    final t = _tplinkIssue[effectiveIp];
    final freshT = t != null && !t.at.isBefore(started) ? t : null;
    final fresh = freshT ?? (z != null && !z.at.isBefore(started) ? z : null);
    // فرع Tenda يكتب في سجلّ TP-Link نفسه (بأثرٍ يبدأ بـ«tplink tenda») — جملة الكرت باسمه لا باسم TP-Link.
    final vendor = fresh == null ? null : (freshT != null ? (freshT.trace.startsWith('tplink tenda') ? 'tenda' : 'tplink') : 'zte');
    if (snap == null) {
      final issue = (issue: fresh?.issue ?? ProbeIssue.unreachable, lockLeft: fresh?.lockLeft, at: now, vendor: vendor);
      _issueByKey[ipKey] = issue;
      if (userKey != null) _issueByUser[userKey] = issue;
    } else {
      _issueByKey.remove(ipKey);
      if (userKey != null) _issueByUser.remove(userKey);
    }
    // جهازٌ دخلناه ولم نقرأ ضوءه = صيغةٌ لا نعرفها (D401، ٢٧ أكتوبر) ⇒ أثره يُبلَّغ مرّةً لكلّ عنوانٍ بالجلسة ولو بلا «حفظ وفحص».
    final readMiss = fresh?.issue == ProbeIssue.readFailed || fresh?.issue == ProbeIssue.unknownFormat;
    if (!reportNow && snap == null && readMiss && _readReported.add(ipKey)) reportNow = true;
    if (reportNow) {
      // مرحلة الفشل بلا اعتمادات ولا عنوان — تصل سجلّ الخادم فيُعرف السبب بالدليل.
      final code = snap != null ? 'ok' : (fresh?.issue ?? ProbeIssue.unreachable).name;
      final text = snap != null
          ? 'kind=${snap.kind.name} vendor=${snap.ont?.vendor ?? '-'}'
          : 'type=${cfg?.deviceType?.name ?? 'auto'} ${fresh?.trace ?? (timedOut ? 'timeout' : 'no-zte-trace')}'
              ' steps=${_steps(effectiveIp, started)} ms=${now.difference(started).inMilliseconds}';
      // السجلّ يقصّ الرسالة عند ٣٠٠ حرف ⇒ أثر الصفحات الطويل يُرسل أجزاءً (ما بعد الأوّل يبدأ بـ«+»).
      for (var i = 0; i < text.length && i < _diagParts * _diagChunk; i += _diagChunk) {
        ClientDiag.report('device_probe',
            code: code, message: '${i == 0 ? '' : '+'}${text.substring(i, (i + _diagChunk).clamp(0, text.length))}');
      }
    }
    if (snap != null) {
      _kindByIp[ipKey] = snap.kind;
      final v = snap.ubnt?.vendor;
      if (v != null) _radioVendorByKey[ipKey] = v;
      _deadCache.remove(ipKey); // نجاح → ما هو ميت
    } else {
      // فشل — نضيف لـdead cache حتى نوفّر محاولات متكرّرة قريبة.
      _deadCache[ipKey] = now;
      // Kind cache قد يكون قديم ونحن جربنا الـkind المخزّن وفشل — نمسحه
      // حتى المحاولة القادمة تفجّر parallel وتلقّط لو الجهاز اتبدّل.
      _kindByIp.remove(ipKey);
      // TP-Link المعروف يبقى معروفاً (فرعه يمسحه حين لا يعود الجهاز يعرّف نفسه): فشله بسببه — رفضٌ أو مشغول — لا يُرجع
      // طلبات هواوي وUBNT إليه كلّ موجة.
      if (_radioVendorByKey[ipKey] != 'tplink') _radioVendorByKey.remove(ipKey);
    }
    _schedulePersist();
    if (timedOut) _keepLate(run, entry, ipKey, userKey);
    return snap;
  }

  /// قراءةٌ وصلت بعد سقف الفحص — كانت تُرمى: مستقبَلات Dart لا تُلغى، فالفحص يُكمل بعد أن نتخلّى عنه (على خطٍّ بعيد
  /// يُكمل كثيراً). تُحفظ ما دامت نتيجة الفشل التي كتبناها هي الأحدث — فحصٌ أحدث أو إبطالٌ بعدنا لا يُغطّى.
  static void _keepLate(Future<DeviceHealthSnapshot?> run, _Cached failed, String ipKey, String? userKey) {
    unawaited(run.then((late) {
      if (late == null || !identical(_snapCache[ipKey], failed)) return;
      final e = _Cached(late, DateTime.now());
      _snapCache[ipKey] = e;
      if (userKey != null && (_snapByUser[userKey] == null || identical(_snapByUser[userKey], failed))) {
        _snapByUser[userKey] = e;
      }
      _kindByIp[ipKey] = late.kind;
      final v = late.ubnt?.vendor;
      if (v != null) _radioVendorByKey[ipKey] = v;
      _deadCache.remove(ipKey);
      _issueByKey.remove(ipKey);
      if (userKey != null) _issueByUser.remove(userKey);
      _schedulePersist();
      onLateResult?.call();
    }, onError: (_) {}));
  }

  /// Drop one IP's cached snapshot — call after editing per-sub
  /// config so the next render re-probes with new credentials.
  static void invalidateIp(String ip, {String? company}) {
    final k = _k(company, ip.trim());
    _snapCache.remove(k);
    _kindByIp.remove(k);
    _deadCache.remove(k);
    _ontVendorByKey.remove(k);
    _ontWinner.remove(k);
    _ubntWinner.remove(k);
    _tplinkWinner.remove(k);
    _radioVendorByKey.remove(k);
    _tplinkSeen.remove(ip.trim());
    _tpClassicSeen.remove(ip.trim());
    _tpAgileSeen.remove(ip.trim());
    // اعتماداتٌ جديدة تُجرَّب: الرفض السابق على هذا العنوان يُنسى (لا يُعاد إلّا المرفوض نفسه بلا تغيير).
    ZteOntService.forget(ip.trim());
    TplinkPharosService.forget(ip.trim());
    TplinkClassicService.forget(ip.trim());
    TplinkAgileService.forget(ip.trim());
    TendaService.forget(ip.trim());
    _schedulePersist();
  }

  /// Read-only peek بالـIP.
  /// لماذا فشل آخر فحصٍ لهذا المشترك (بالمشترك أوّلاً ثمّ بالعنوان) — null: نجح أو لم يُفحص. [lockLeft] ما بقي من القفل الآن.
  /// [vendor] من سجّل السبب (`zte` · `tplink`) أو null — لصياغة الجملة.
  static ({ProbeIssue issue, int? lockLeft, String? vendor})? issueFor({String? username, required String ip, String? company}) {
    final byUser = username == null || username.isEmpty ? null : _issueByUser[_k(company, username)];
    final e = byUser ?? _issueByKey[_k(company, ip.trim())];
    if (e == null) return null;
    final left = e.lockLeft == null ? null : e.lockLeft! - DateTime.now().difference(e.at).inSeconds;
    return (issue: e.issue, lockLeft: left == null || left <= 0 ? null : left, vendor: e.vendor);
  }

  /// مراحل ZTE بأوقاتها من بدء الفحص: `detect+0 login+340 read+1200` — لتشخيصٍ بلا محتوى.
  static String _steps(String ip, DateTime started) {
    final list = _zteSteps[ip];
    if (list == null || list.isEmpty) return '-';
    return list.map((e) => '${e.stage}+${e.at.difference(started).inMilliseconds}').join(',');
  }

  static DeviceHealthSnapshot? cached(String ip, {String? company}) {
    final c = _snapCache[_k(company, ip.trim())];
    if (c == null) return null;
    if (DateTime.now().difference(c.at) >= _ttl) return null;
    return c.snap;
  }

  /// Read-only peek بالـusername.
  static DeviceHealthSnapshot? cachedForUser(String username,
      {String? company}) {
    if (username.isEmpty) return null;
    final c = _snapByUser[_k(company, username)];
    if (c == null) return null;
    if (DateTime.now().difference(c.at) >= _ttl) return null;
    return c.snap;
  }

  /// Peek يتجاهل المهلة: يُرجع آخر نتيجة معروفة مهما قدُمت، مع عمرها.
  ///
  /// للواجهات التي تفضّل عرض نتيجة قديمة فوراً على إظهار دوّارة: الجهاز
  /// الذي فُحص مرّة لا ينبغي أن يبدو مجهولاً بعدها أبداً. المتصل بها
  /// يعرض القيمة ثمّ يُحدّث في الخلفيّة إن كانت `stale`.
  /// [at] وقت التقاط اللقطة — يحتاجه الكرت ليقول «آخر تحديث قبل كذا»
  /// بدل ثنائيّة «حديث/قديم» التي لا تُخبر المستخدم متى قُرئت البيانات.
  static ({DeviceHealthSnapshot? snap, bool stale, DateTime at})? peek({
    String? username,
    String? ip,
    String? company,
  }) {
    _Cached? c;
    if (username != null && username.isNotEmpty) {
      c = _snapByUser[_k(company, username)];
    }
    if (c == null && ip != null && ip.trim().isNotEmpty) {
      c = _snapCache[_k(company, ip.trim())];
    }
    if (c == null) return null;
    return (
      snap: c.snap,
      stale: DateTime.now().difference(c.at) >= _ttl,
      at: c.at,
    );
  }

  /// تحتاج الموجة (غير المُجبَرة) فحص هذا الهدف؟ لا نتيجة له، أو نتيجته أقدم من [_ttl].
  ///
  /// 🐛 ٢٩ أكتوبر: كان الترشيح «لا نتيجة أصلاً» — فالمفحوص مرّةً لا تعيده الموجة ولو بعد ساعة، وقراءته تُعامَل منتهيةً
  /// بعد خمس دقائق ولا تتجدّد إلّا بـ«فحص الأجهزة».
  static bool needsProbe({String? username, String? ip, String? company}) {
    final p = peek(username: username, ip: ip, company: company);
    return p == null || p.stale;
  }

  /// عدد عمّال الموجة بحسب بُعد الخطّ: فتح اتّصالٍ بأوّل خمسة عناوين (الظاهرون أوّلاً) معاً — جولةٌ واحدة. وسيطٌ فوق
  /// [_slowLinkConnect] ⇒ [_slowLinkWorkers]؛ وإلّا — أو لم يردّ اثنان — [_defaultWorkers] كما كان (شبكة الوكيل لا تتغيّر).
  static Future<int> _workersForLink(List<ProbeTarget> ordered) async {
    final sample = <String>[];
    for (final t in ordered) {
      final custom = DeviceConfigApi.peekConfig(t.username, company: t.company)?.customIp?.trim();
      final ip = custom != null && custom.isNotEmpty ? custom : t.ip.trim();
      if (ip.isNotEmpty && !sample.contains(ip)) sample.add(ip);
      if (sample.length == 5) break;
    }
    if (sample.isEmpty) return _defaultWorkers;
    final measure = debugConnectTime ?? TcpReachability.connectTime;
    final times = (await Future.wait(sample.map(measure))).whereType<Duration>().toList()..sort();
    if (times.length < 2) return _defaultWorkers;
    return times[times.length ~/ 2] > _slowLinkConnect ? _slowLinkWorkers : _defaultWorkers;
  }

  /// Wave batched probe.
  ///
  /// * [priorityUsernames] — تُفحص أوّلاً. للـviewport-visible subs،
  ///   يمنح إحساس بأن الفحص "فوري" حتى مع قوائم كبيرة.
  /// * [concurrency] — عدد العمّال المتزامنين. حوضٌ منزلق لا دفعاتٌ
  ///   متتابعة: من فرغ أخذ الهدف التالي فوراً. راجع [_defaultWorkers]
  ///   لسبب الرقم. null ⇒ بحسب بُعد الخطّ ([_workersForLink]).
  /// * [onProgress] — يُنادى بعد **كلّ هدف** لا بعد كلّ دفعة. فليكن
  ///   رخيصاً؛ لا `setState` على شاشةٍ كاملة فيه.
  /// * `company` في الهدف — شركة الصفّ في «كل الشركات» (null في الوضع العاديّ): دفعة إعدادات لكلّ شركة، وحوضٌ واحد للكلّ.
  /// * [force] — «فحص الأجهزة»: كلّ هدفٍ يُفحص من جديد. 🐛 ٢٩ أكتوبر: كان الفحص المُجبَر يُبطل كاش العنوان وحده ثمّ يسأل
  ///   [probe] بلا force — فنتيجة المشترك المحفوظة (فشلٌ عمره دون خمس دقائق) تعود كما هي: «اكتمل الفحص» ولا جديد.
  static Future<void> warmProbe(
    List<ProbeTarget> targets, {
    Set<String>? priorityUsernames,
    int? concurrency,
    bool force = false,
    void Function(int done, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    if (targets.isEmpty) {
      onProgress?.call(0, 0);
      return;
    }
    // Priority ordering — الـpriority أوّلاً، الباقي بعده.
    List<ProbeTarget> ordered;
    if (priorityUsernames != null && priorityUsernames.isNotEmpty) {
      final priority = <ProbeTarget>[];
      final rest = <ProbeTarget>[];
      for (final t in targets) {
        if (priorityUsernames.contains(t.username)) {
          priority.add(t);
        } else {
          rest.add(t);
        }
      }
      ordered = [...priority, ...rest];
    } else {
      ordered = targets;
    }

    // Prime DeviceConfig cache بـbatch endpoint (لو الـbackend يدعمه).
    // يمنع 500 fetch منفصلة عند أوّل wave.
    //
    // «كل الشركات»: دفعةٌ لكلّ شركة (موجَّهةٌ لها)، والكاش مرجعٌ لشركةٍ نجحت دفعتها وحدها.
    final byCompany = <String?, List<String>>{};
    for (final t in ordered) {
      (byCompany[t.company] ??= <String>[]).add(t.username);
    }
    final authoritative = <String?, bool>{};
    await Future.wait(byCompany.entries.map((e) async {
      try {
        authoritative[e.key] =
            await DeviceConfigApi.warmBatch(e.value, company: e.key);
      } catch (_) {
        authoritative[e.key] = false;
      }
    }));
    // شركةٌ تعذّرت دفعتها وقاطعها مفتوح: ما لا عنوان له لا يُعرف عنوانه المحفوظ الآن ولا يُسأل عنه (طلبٌ موجَّه لكلّ مشترك
    // يُنفق ميزانيّة الحساب) ⇒ يُترك لموجةٍ بعد القاطع؛ وما له عنوانٌ يُفحص بلا أيّ طلب.
    final configsAuthoritative = authoritative.values.any((ok) => ok) ||
        authoritative.keys.any(DeviceConfigApi.routedDown);

    // ── إسقاط ما لا عنوان له أصلاً ────────────────────────────────
    //
    // ⚠️ **ليس ترشيحاً على «متّصل»**: المشترك المطفأ يُفحص كما كان —
    // فقد يكون جهاز وصوله (ONT/UBNT) حيّاً وله عنوانٌ وبيانات دخولٍ
    // محفوظة، وخطّ الراديوس وحده هو المقطوع. هذا مطلبٌ صريح لصاحب
    // المشروع، ونقضُه يُعمي أهمّ حالةٍ تشخيصيّة عنده.
    //
    // إنّما نُسقط من **لا عنوان له في أيّ مكان**: لا عنوان راديوس ولا
    // `customIp` محفوظ. وهؤلاء لا يُفحصون أصلاً — `probe` يخرج عندهم
    // بـ`null` عند `effectiveIp.isEmpty`. لكنّه يخرج **بعد** أن يحجز
    // عاملاً وينتظر `fetchConfig`. فإسقاطهم هنا يُحرّر عمّالاً لمن
    // يستحقّ الفحص فعلاً.
    //
    // ⚠️ و**الفشل إلى الأمان**: لا نُرشّح إلّا إذا أكّد `warmBatch` أنّ
    // الكاش مرجعٌ موثوق. فلو سقطت الشبكة أو غابت نقطة الدفعات، صار
    // «لا إعداد في الكاش» يعني «لم نسأل» لا «لا يوجد» — والترشيح
    // عندها يُسقط بالضبط من له إعدادٌ محفوظ. نفحص الجميع حينها كما
    // كنّا: بطءٌ أهون من عمى.
    if (configsAuthoritative) {
      final before = ordered.length;
      ordered = ordered.where((t) {
        if (t.ip.trim().isNotEmpty) return true; // عنوان من الراديوس
        if (authoritative[t.company] != true) {
          // لم نعرف ⇒ نفحص — إلّا شركةً قاطعها مفتوح (لا عنوان ولا طريق لمعرفته الآن)
          return !DeviceConfigApi.routedDown(t.company);
        }
        final cfg = DeviceConfigApi.peekConfig(t.username, company: t.company);
        return (cfg?.customIp?.trim().isNotEmpty ?? false); // أو محفوظ
      }).toList();
      // ⚠️ `onProgress(0,0)` لا مجرّد `return`: المستدعي يُطفئ دوّارة
      //    الزرّ في `whenComplete`، لكنّ خروجاً صامتاً هنا يترك حالةً
      //    لا تُبلَّغ. والصفر/صفر يقول «لا شيء يُفحص» صراحةً.
      if (ordered.isEmpty) {
        onProgress?.call(0, 0);
        return;
      }
      // (`before` محفوظ للتشخيص عند الحاجة — لا طباعة هنا: الملفّ لا
      //  يستورد `foundation`، واستيرادٌ كامل لأجل سطرٍ تشخيصيّ مبالغة.)
      assert(before >= ordered.length);
    }

    // ── حوض عمّالٍ منزلق، لا دفعاتٍ متتابعة ───────────────────────
    //
    // ⚠️ البنية السابقة كانت `Future.wait` على كلّ ٢٥ ثمّ الانتقال —
    // أي أنّ **كلّ دفعةٍ تنتظر أبطأ عضوٍ فيها**.
    //
    // وتصحيحٌ لما كُتب هنا أوّلاً: المهل الداخليّة **ليست ثانيتين**.
    // الثانيتان مهلةُ فحص الوصول (ICMP/TCP/SNMP) في
    // `network_devices_api`. أمّا مسار HTTP فمهلته أطول بكثير:
    // Huawei ONT **١٥ ثانية** اتّصالاً واستقبالاً
    // (`huawei_ont_service.dart`)، وUBNT ٥/٨. ومهلةُ Huawei تساوي
    // `_probeCap` تماماً — ولذلك يكلّف الجهاز الصامت خمس عشرة ثانية
    // بالضبط، لا أقلّ.
    //
    // فجهازٌ صامتٌ واحد كان يُجمّد أربعةً وعشرين فحصاً انتهت سلفاً،
    // وهو ينتظر مهلته وحده. واليوم يحجز عاملاً واحداً لا خمسةً وعشرين.
    //
    // ⚠️ ولا يُخفَّض السقف: ١٥ ثانية مضبوطةٌ بطلب صاحب المشروع
    // (٢٠٢٦-٠٧-١٢) بعد أن كانت ٤ ثوانٍ «تفشل مبكراً» — والتحذير مكتوبٌ
    // في `huawei_ont_service` نفسه. وجهازٌ حيٌّ يُعلَن ميّتاً أسوأ من
    // فحصٍ بطيء.
    //
    // على ١١٢ هدفاً ذلك خمسة حواجز. ومع توزيعٍ واقعيّ (أغلبها يردّ في
    // جزءٍ من الثانية وبعضها ميّت) يصير الزمن الكلّيّ ≈ خمسة أضعاف
    // المهلة، بينما العمل الفعليّ أقلّ من ذلك بكثير.
    //
    // وهنا `concurrency` عاملاً يسحبون من مؤشّرٍ مشترك: من فرغ أخذ
    // التالي فوراً. فالزمن الكلّيّ يصير محكوماً بمجموع العمل مقسوماً
    // على عدد العمّال، لا بأبطأ عضوٍ في كلّ دفعة.
    //
    // ⚠️ والترتيب محفوظ: العمّال يسحبون بالتسلسل من `ordered`، فأهداف
    // الأولويّة (المرئيّون على الشاشة) تُلتقط أوّلاً كما كانت.
    var next = 0;
    var done = 0;
    var canceled = false;

    Future<void> worker() async {
      while (true) {
        if (canceled) return;
        // ⚠️ الفحص هنا لا بين الدفعات: بلا حواجز لم يعد ثمّة «بين».
        //    وبدونه تُكمل الموجة بعد إغلاق الشاشة.
        if (isCanceled?.call() ?? false) {
          canceled = true;
          return;
        }
        // ⚠️ السحب والزيادة في نفس الخطوة المتزامنة. ومحرّك Dart أحاديّ
        //    الخيط فلا سباق هنا ما دام بينهما لا `await`.
        final i = next++;
        if (i >= ordered.length) return;
        final t = ordered[i];
        try {
          await probe(
              fallbackIp: t.ip,
              subscriberUsername: t.username,
              force: force,
              company: t.company);
        } catch (_) {}
        done++;
        // ⚠️ يُنادى الآن **لكلّ هدف** لا لكلّ دفعة. وهذا آمنٌ لأنّ
        //    المستدعي لم يعد يستدعي `setState` فيه — يوقظ بطاقات
        //    الأجهزة المرئيّة وحدها. ولو أُعيد `setState` يوماً فهذا
        //    الموضع هو ما يجب خنقه.
        onProgress?.call(done, ordered.length);
      }
    }

    final wanted = concurrency ?? await _workersForLink(ordered);
    lastWaveWorkers = wanted;
    final workers = wanted < ordered.length ? wanted : ordered.length;
    await Future.wait(List.generate(workers, (_) => worker()));
  }

  static void invalidateAdminDefaults() {
    _adminFetch = null;
    _adminFetchBy.clear();
    _snapCache.clear();
    _snapByUser.clear();
    _kindByIp.clear();
    _deadCache.clear();
    // اعتماداتٌ جديدة ⇒ الفائز القديم قد لا يكون بينها.
    _ontWinner.clear();
    _ubntWinner.clear();
    _tplinkWinner.clear();
    _schedulePersist();
  }

  static Future<AdminDeviceDefaults> _loadAdminDefaults([String? company]) async {
    if (company == null) return _adminFetch ??= AdminDeviceDefaultsApi.fetch();
    if (DeviceConfigApi.routedDown(company)) return AdminDeviceDefaults.empty;
    final f = _adminFetchBy[company] ??=
        CompanyRoute.run(company, AdminDeviceDefaultsApi.tryFetch);
    final d = await f;
    if (d != null) return d;
    // تعذّرت ⇒ لا تُحفظ للجلسة (جلسة الشركة قد تعود)، وقاطع الدقيقة يمنع إعادتها مع كلّ هدف.
    if (identical(_adminFetchBy[company], f)) _adminFetchBy.remove(company);
    DeviceConfigApi.noteRoutedFailure(company);
    return AdminDeviceDefaults.empty;
  }

  /// [kindKey] مفتاح العنوان في كاش النوع (بشركته في «كل الشركات»)، و[ip] نفسه يُفحص.
  static Future<DeviceHealthSnapshot?> _runProbe(
    String ip,
    DeviceConfig? cfg,
    AdminDeviceDefaults defaults,
    String kindKey,
  ) async {
    if (ip.isEmpty) return null;

    final overridesOnt = cfg?.deviceType == DeviceKind.ont;
    final overridesUbnt = cfg?.deviceType == DeviceKind.ubiquiti;
    // ⑦: مرشّحو الاعتماد لكلّ نوع (الأوّل ثمّ إضافيّا المدير) — بالترتيب، والفائز يُحفظ لهذا العنوان.
    final c = candidatesFor(cfg, defaults);

    // Admin pinned kind → probe واحد فقط. «Ubiquiti» = جهاز المشترك اللاسلكيّ: يوبيكويتي أو TP-Link ([_probeRadio]).
    if (overridesOnt) return _probeOntAny(ip, c.ont, kindKey, factory: c.ontFactory);
    if (overridesUbnt) return _probeRadio(ip, c.ubnt, c.tplink, c.tprouter, kindKey);

    // جهازٌ عُرف أنّه TP-Link (ولو فشل دخوله: رفضٌ أو مشغول) ⇒ فرعه وحده — لا تطرقه طلبات هواوي وUBNT كلّ موجة.
    if (_radioVendorByKey[kindKey] == 'tplink') return _probeTplinkAny(ip, c.tplink, kindKey);
    // راوتر TP-Link كلاسيكيّ (١١ نوفمبر) — كذلك فرعه وحده.
    if (_radioVendorByKey[kindKey] == 'tpclassic') return _probeTpClassicAny(ip, c.tplink, kindKey);
    // راوتر TP-Link الحديث Agile (١١ نوفمبر) — كذلك فرعه وحده.
    if (_radioVendorByKey[kindKey] == 'tpagile') return _probeTpAgileAny(ip, c.tprouter, kindKey);
    // راوتر Tenda (١٢ نوفمبر) — كذلك فرعه وحده (كلمة سرٍّ وحدها).
    if (_radioVendorByKey[kindKey] == 'tenda') return _probeTendaAny(ip, c.tprouter, kindKey);

    // Kind cache — لو نعرف من probe سابق إن IP هذا ONT (أو UBNT)،
    // نفجّر النوع الصحيح فقط. توفير ~5s متوسط. مطلب المستخدم 2026-07-12.
    // احتياط: لو الـkind المخزّن فشل، نمسحه (فوق) والمحاولة القادمة
    // ترجع parallel لتتلاقط تغيير الجهاز.
    final knownKind = _kindByIp[kindKey];
    if (knownKind == DeviceKind.ont) {
      return _probeOntAny(ip, c.ont, kindKey, factory: c.ontFactory);
    }
    if (knownKind == DeviceKind.ubiquiti) {
      return _probeRadio(ip, c.ubnt, c.tplink, c.tprouter, kindKey);
    }

    // First-time أو kind cache cleared — parallel race.
    final ont = _probeOntAny(ip, c.ont, kindKey, factory: c.ontFactory);
    final ubnt = _probeUbntAny(ip, c.ubnt, kindKey, unlessOther: true);
    final others = _firstNonNull<DeviceHealthSnapshot>([ont, ubnt]);
    // TP-Link يعرّف نفسه بطلبٍ واحد بلا دخول: إن كان هو فنتيجة فرعه هي الجواب — ولو فشلاً بسببه — ولا يُنتظر فرعا هواوي
    // وUBNT على جهازٍ ليس لهما؛ وإن لم يكن فالجواب جوابهما كما كان. والأسبق من (نجاح أحدهما · معرفة أنّه TP-Link) يحسم.
    // والراوتر الكلاسيكيّ (١١ نوفمبر) كذلك يعرّف نفسه بطلبٍ بلا دخول (401 + realm) — بعد أن يقول تعرّف Pharos «ليس أنا».
    final hello = _helloTplink(ip);
    final classic = _helloTpClassic(ip);
    final agile = _helloTpAgile(ip);
    final tenda = _helloTenda(ip);
    final done = Completer<DeviceHealthSnapshot?>();
    var othersDone = false;
    var helloDone = false;
    var classicDone = false;
    var agileDone = false;
    var tendaDone = false;
    void noneYet() {
      if (!done.isCompleted && othersDone && helloDone && classicDone && agileDone && tendaDone) done.complete(null);
    }
    others.then((snap) {
      othersDone = true;
      if (done.isCompleted) return;
      if (snap != null) {
        done.complete(snap);
      } else {
        noneYet();
      }
    });
    hello.then((h) {
      helloDone = true;
      if (done.isCompleted) return;
      if (h != null) {
        done.complete(_probeTplinkAny(ip, c.tplink, kindKey, hello: h));
      } else {
        noneYet();
      }
    });
    classic.then((h) {
      classicDone = true;
      if (done.isCompleted) return;
      if (h != null) {
        done.complete(_probeTpClassicAny(ip, c.tplink, kindKey, hello: h));
      } else {
        noneYet();
      }
    });
    agile.then((yes) {
      agileDone = true;
      if (done.isCompleted) return;
      if (yes) {
        done.complete(_probeTpAgileAny(ip, c.tprouter, kindKey));
      } else {
        noneYet();
      }
    });
    tenda.then((yes) {
      tendaDone = true;
      if (done.isCompleted) return;
      if (yes) {
        done.complete(_probeTendaAny(ip, c.tprouter, kindKey));
      } else {
        noneYet();
      }
    });
    return done.future;
  }

  /// تعرّف Tenda الجاري لكلّ عنوان (صفحة الدخول وحدها) — نصف دقيقة كغيره. **بعد** أن يقول تعرّف Pharos «ليس أنا» (طلبٌ على Pharos قد
  /// يُبدّل الـnonce الذي حفظه تعرّفه).
  static final _tendaHello = <String, Future<bool>>{};
  static final _tendaSeen = <String, ({bool yes, DateTime at})>{};

  static Future<bool> _helloTenda(String ip) {
    final running = _tendaHello[ip];
    if (running != null) return running;
    final seen = _tendaSeen[ip];
    if (seen != null && DateTime.now().difference(seen.at) < _tplinkSeenFor) return Future.value(seen.yes);
    final f = (() async {
      if (await _isTplink(ip)) return false;
      return TendaService.detect(ip);
    })()
        .catchError((Object _) => false);
    _tendaHello[ip] = f;
    f.then((y) => _tendaSeen[ip] = (yes: y, at: DateTime.now()));
    f.whenComplete(() => _tendaHello.remove(ip));
    return f;
  }

  static Future<bool> _isTenda(String ip) => _helloTenda(ip);

  /// راوتر Tenda: كلمات السرّ وحدها (قائمة «باسورد فقط»: كلمة سرّ المشترك ثمّ المدير ثمّ TP-Link احتياطاً) — دخولٌ ⇒ الحالة والمتّصلون ⇒
  /// خروج ([TendaService.readOnce]). المرفوضة لا تُعاد، والتالية بعد رفضٍ صريحٍ وحده؛ «حتى ٤ مدراء» ⇒ مشغول بلا تجربة غيرها.
  static Future<DeviceHealthSnapshot?> _probeTendaAny(String ip, List<DeviceCred> cands, String kindKey) async {
    _radioVendorByKey[kindKey] = 'tenda';
    if (cands.isEmpty) {
      _tplinkNote(ip, ProbeIssue.needsCredentials, 'tenda no-creds');
      return null;
    }
    final list = _winnerFirst(cands, _tplinkWinner[kindKey]);
    for (var i = 0; i < list.length; i++) {
      UbiquitiStatus? status;
      try {
        status = await TendaService.readOnce(ip, list[i].password);
      } catch (_) {
        _tplinkNote(ip, ProbeIssue.unreachable, 'tenda error');
        break;
      }
      if (status != null) {
        _tplinkWinner[kindKey] = list[i];
        return DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: ip, ubnt: status);
      }
      final why = TendaService.lastIssue(ip);
      _tplinkNote(
        ip,
        switch (why?.issue) {
          TendaIssue.rejected => ProbeIssue.loginRejected,
          TendaIssue.busy => ProbeIssue.busy,
          TendaIssue.readFailed => ProbeIssue.readFailed,
          _ => ProbeIssue.unreachable,
        },
        'tenda ${why?.trace ?? '?'}',
      );
      if (why?.issue == TendaIssue.unreachable) {
        _radioVendorByKey.remove(kindKey);
        break;
      }
      if (why?.issue != TendaIssue.rejected) break;
    }
    return null;
  }

  /// تعرّف الراوتر الكلاسيكيّ الجاري لكلّ عنوان — فرعه وفرع Ubiquiti يتشاركانه (طلبٌ واحد).
  static final _tpClassicHello = <String, Future<TpClassicHello?>>{};

  /// نتيجة آخر تعرّفٍ كلاسيكيّ لكلّ عنوان (نصف دقيقة كـPharos): الإيجاب يحمل التعرّف نفسه، والسلب null.
  static final _tpClassicSeen = <String, ({TpClassicHello? hello, DateTime at})>{};

  /// تعرّفٌ كلاسيكيّ — **بعد** أن يقول تعرّف Pharos إنّ العنوان ليس Pharos: طلب «/» على Pharos قد يُبدّل الـnonce الذي حفظه تعرّفه
  /// (الجهاز يحفظ آخر nonce طلبه أيّ عميل). على الكلاسيكيّ نفسه يجيب طلب Pharos بـ401 سريعاً، فلا يزيد الانتظار إلّا ~٠٫٤ث.
  static Future<TpClassicHello?> _helloTpClassic(String ip) {
    final running = _tpClassicHello[ip];
    if (running != null) return running;
    final seen = _tpClassicSeen[ip];
    if (seen != null && DateTime.now().difference(seen.at) < _tplinkSeenFor) return Future.value(seen.hello);
    final f = (() async {
      if (await _isTplink(ip)) return null;
      return TplinkClassicService.detect(ip);
    })()
        .catchError((Object _) => null);
    _tpClassicHello[ip] = f;
    f.then((h) => _tpClassicSeen[ip] = (hello: h, at: DateTime.now()));
    f.whenComplete(() => _tpClassicHello.remove(ip));
    return f;
  }

  static Future<bool> _isTpClassic(String ip) async => (await _helloTpClassic(ip)) != null;

  /// راوتر TP-Link الكلاسيكيّ: مرشّحو قائمة TP-Link (الفائز المحفوظ أوّلاً) — قراءةٌ بمصادقة Basic بلا جلسة
  /// ([TplinkClassicService.readOnce]). لا افتراض مصنّع (قفله بعد الخطأ لم يُجرَّب)، والتالي لا يُجرَّب إلّا بعد رفضٍ صريح (401).
  /// رفضٌ ⇒ يبقى معروفاً «كلاسيكيّاً» (فلا تطرقه طلبات هواوي وUBNT كلّ موجة)؛ لا يجاوب ⇒ يُنسى فيُعاد التعرّف.
  static Future<DeviceHealthSnapshot?> _probeTpClassicAny(
      String ip, List<DeviceCred> cands, String kindKey, {TpClassicHello? hello}) async {
    _radioVendorByKey[kindKey] = 'tpclassic';
    final model = hello?.model ?? '';
    if (cands.isEmpty) {
      _tplinkNote(ip, ProbeIssue.needsCredentials, 'classic no-creds $model');
      return null;
    }
    final list = _winnerFirst(cands, _tplinkWinner[kindKey]);
    for (var i = 0; i < list.length; i++) {
      UbiquitiStatus? status;
      try {
        status = await TplinkClassicService.readOnce(ip, list[i].username, list[i].password, realmModel: model, hello: hello);
      } catch (_) {
        _tplinkNote(ip, ProbeIssue.unreachable, 'classic $model error');
        break;
      }
      if (status != null) {
        _tplinkWinner[kindKey] = list[i];
        return DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: ip, ubnt: status);
      }
      final why = TplinkClassicService.lastIssue(ip);
      _tplinkNote(
        ip,
        switch (why?.issue) {
          TpClassicIssue.rejected => ProbeIssue.loginRejected,
          TpClassicIssue.readFailed => ProbeIssue.readFailed,
          TpClassicIssue.busy => ProbeIssue.busy,
          TpClassicIssue.locked => ProbeIssue.locked,
          _ => ProbeIssue.unreachable,
        },
        'classic $model ${why?.trace ?? '?'}',
      );
      if (why?.issue == TpClassicIssue.unreachable) {
        _radioVendorByKey.remove(kindKey);
        break;
      }
      if (why?.issue != TpClassicIssue.rejected) break;
    }
    return null;
  }

  /// تعرّف الراوتر الحديث Agile (HTTPS، مصافحة keys العامّة) الجاري لكلّ عنوان — نصف دقيقة كغيره. مستقلٌّ عن تعرّف Pharos (HTTPS لا
  /// يمسّ nonce الـHTTP).
  static final _tpAgileHello = <String, Future<bool>>{};
  static final _tpAgileSeen = <String, ({bool yes, DateTime at})>{};

  static Future<bool> _helloTpAgile(String ip) {
    final running = _tpAgileHello[ip];
    if (running != null) return running;
    final seen = _tpAgileSeen[ip];
    if (seen != null && DateTime.now().difference(seen.at) < _tplinkSeenFor) return Future.value(seen.yes);
    final f = TplinkAgileService.detect(ip).catchError((Object _) => false);
    _tpAgileHello[ip] = f;
    f.then((y) => _tpAgileSeen[ip] = (yes: y, at: DateTime.now()));
    f.whenComplete(() => _tpAgileHello.remove(ip));
    return f;
  }

  static Future<bool> _isTpAgile(String ip) => _helloTpAgile(ip);

  /// راوتر TP-Link الحديث Agile: مرشّحو قائمة TP-Link (الباسورد المحلّيّ؛ اليوزر يُمرَّر لمن تطلبه فيرموَيره، والافتراضيّ فارغ) —
  /// دخولٌ RSA+AES ثمّ قراءة `/admin/status` ([TplinkAgileService.readOnce]). لا افتراض مصنّع، والمرفوض لا يُعاد.
  static Future<DeviceHealthSnapshot?> _probeTpAgileAny(String ip, List<DeviceCred> cands, String kindKey) async {
    _radioVendorByKey[kindKey] = 'tpagile';
    if (cands.isEmpty) {
      _tplinkNote(ip, ProbeIssue.needsCredentials, 'agile no-creds');
      return null;
    }
    final list = _winnerFirst(cands, _tplinkWinner[kindKey]);
    for (var i = 0; i < list.length; i++) {
      UbiquitiStatus? status;
      try {
        status = await TplinkAgileService.readOnce(ip, list[i].password, username: list[i].username);
      } catch (_) {
        _tplinkNote(ip, ProbeIssue.unreachable, 'agile error');
        break;
      }
      if (status != null) {
        _tplinkWinner[kindKey] = list[i];
        return DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: ip, ubnt: status);
      }
      final why = TplinkAgileService.lastIssue(ip);
      _tplinkNote(
        ip,
        switch (why?.issue) {
          AgileIssue.rejected => ProbeIssue.loginRejected,
          AgileIssue.busy => ProbeIssue.busy,
          AgileIssue.locked => ProbeIssue.locked,
          AgileIssue.readFailed => ProbeIssue.readFailed,
          _ => ProbeIssue.unreachable,
        },
        'agile ${why?.trace ?? '?'}',
      );
      if (why?.issue == AgileIssue.unreachable) {
        _radioVendorByKey.remove(kindKey);
        break;
      }
      if (why?.issue != AgileIssue.rejected) break;
    }
    return null;
  }

  /// تعرّف TP-Link الجاري لكلّ عنوان — فرعه وفرع Ubiquiti يتشاركانه (طلبٌ واحد).
  static final _tplinkHello = <String, Future<PharosHello?>>{};

  /// نتيجة آخر تعرّفٍ لكلّ عنوان، لنصف دقيقة. الجهاز يحفظ **آخر** nonce طلبه أيّ عميلٍ وحده (قِيس): تعرّفٌ ثانٍ والأوّل لم
  /// يدخل بعدُ يُبطل nonce الأوّل — فمن يسأل «أهو TP-Link؟» فقط (فرع Ubiquiti بين مرشّحٍ وآخر) يُجاب من هنا بلا طلب.
  static final _tplinkSeen = <String, ({bool yes, DateTime at})>{};
  static const _tplinkSeenFor = Duration(seconds: 30);

  static ({bool yes, DateTime at})? _tplinkRecent(String ip) {
    final seen = _tplinkSeen[ip];
    return seen != null && DateTime.now().difference(seen.at) < _tplinkSeenFor ? seen : null;
  }

  /// تعرّفٌ جديد (بـnonce دخوله). null بلا طلبٍ حين عُرف للتوّ أنّ العنوان ليس TP-Link.
  static Future<PharosHello?> _helloTplink(String ip) {
    final running = _tplinkHello[ip];
    if (running != null) return running;
    if (_tplinkRecent(ip)?.yes == false) return Future.value(null);
    final f = TplinkPharosService.hello(ip).catchError((Object _) => null);
    _tplinkHello[ip] = f;
    f.then((h) => _tplinkSeen[ip] = (yes: h != null, at: DateTime.now()));
    f.whenComplete(() => _tplinkHello.remove(ip));
    return f;
  }

  /// أهو TP-Link؟ من آخر تعرّفٍ قريب، وإلّا تعرّفٌ واحد.
  static Future<bool> _isTplink(String ip) async =>
      _tplinkRecent(ip)?.yes ?? (await _helloTplink(ip)) != null;

  /// آخر مورّد راديو نجح لكلّ عنوان (بمفتاح كاش النوع): `ubnt` أو `tplink` — الفحص التالي يذهب إليه وحده.
  static final _radioVendorByKey = <String, String>{};

  /// جهاز المشترك اللاسلكيّ (النوع «Ubiquiti» مثبَّتاً أو معروفاً من قبل): يوبيكويتي أو TP-Link. المورّد المحفوظ وحده —
  /// يوبيكويتي كما كان حرفاً بلا أيّ طلبٍ زائد — وإلّا التعرّف أوّلاً (طلبٌ بلا دخول) ثمّ فرعٌ واحد.
  static Future<DeviceHealthSnapshot?> _probeRadio(
      String ip, List<DeviceCred> ubnt, List<DeviceCred> tplink, List<DeviceCred> tprouter, String kindKey) async {
    final known = _radioVendorByKey[kindKey];
    if (known == 'ubnt') return _probeUbntAny(ip, ubnt, kindKey);
    if (known == 'tplink') return _probeTplinkAny(ip, tplink, kindKey);
    if (known == 'tpclassic') return _probeTpClassicAny(ip, tplink, kindKey);
    // راوترات «كلمة السرّ وحدها» بقائمتها (كانت Agile هنا تأخذ قائمة اليوزر+الباسورد).
    if (known == 'tpagile') return _probeTpAgileAny(ip, tprouter, kindKey);
    if (known == 'tenda') return _probeTendaAny(ip, tprouter, kindKey);
    final hello = await _helloTplink(ip);
    if (hello != null) return _probeTplinkAny(ip, tplink, kindKey, hello: hello);
    final classic = await _helloTpClassic(ip);
    if (classic != null) return _probeTpClassicAny(ip, tplink, kindKey, hello: classic);
    if (await _helloTpAgile(ip)) return _probeTpAgileAny(ip, tprouter, kindKey);
    if (await _helloTenda(ip)) return _probeTendaAny(ip, tprouter, kindKey);
    return _probeUbntAny(ip, ubnt, kindKey);
  }

  static void _tplinkNote(String ip, ProbeIssue issue, String trace, {int? lockLeft}) =>
      _tplinkIssue[ip] = (issue: issue, lockLeft: lockLeft, at: DateTime.now(), trace: 'tplink $trace');

  /// TP-Link: تعرّفٌ بلا دخول، ثمّ مرشّحو الوكيل بالترتيب (الفائز المحفوظ أوّلاً) — دخولٌ ← قراءةٌ ← خروج لكلٍّ
  /// ([TplinkPharosService.readOnce]). لا افتراض مصنّع: الجهاز يعدّ المحاولات الغلط ويقفل صفحته عند عشر. والتالي لا
  /// يُجرَّب إلّا بعد «رفض» صريح (مشغولٌ/قافلٌ/لا يجاوب ⇒ قف).
  static Future<DeviceHealthSnapshot?> _probeTplinkAny(
      String ip, List<DeviceCred> cands, String kindKey, {PharosHello? hello}) async {
    // جلسة الكرت الحيّة قائمة ⇒ القراءة بها: لا تعرّف ولا دخول (طلبٌ واحد خفيف كلّ نبضة).
    final live = TplinkPharosService.hasLive(ip);
    final first = hello ?? (live ? null : await _helloTplink(ip));
    if (first == null && !live) {
      // لم يعد يعرّف نفسه (تبدّل الجهاز أو لا يجاوب) ⇒ الفحص التالي يبحث من جديد.
      _radioVendorByKey.remove(kindKey);
      return null;
    }
    final model = first?.model ?? '';
    PharosHello? h = first;
    _radioVendorByKey[kindKey] = 'tplink';
    if (cands.isEmpty) {
      _tplinkNote(ip, ProbeIssue.needsCredentials, 'no-creds $model');
      return null;
    }
    final list = _winnerFirst(cands, _tplinkWinner[kindKey]);
    for (var i = 0; i < list.length; i++) {
      UbiquitiStatus? status;
      try {
        status = await TplinkPharosService.readOnce(ip, list[i].username, list[i].password, hello: h);
      } catch (_) {
        // خطأٌ غير متوقَّع في القراءة لا يُسقط الفحص كلّه (الكرت ينتظر جوابه): «ما يجاوب» ونقف.
        _tplinkNote(ip, ProbeIssue.unreachable, '$model error');
        break;
      }
      if (status != null) {
        _tplinkWinner[kindKey] = list[i];
        return DeviceHealthSnapshot(kind: DeviceKind.ubiquiti, ip: ip, ubnt: status);
      }
      final why = TplinkPharosService.lastIssue(ip);
      _tplinkNote(
        ip,
        switch (why?.issue) {
          PharosLoginIssue.rejected => ProbeIssue.loginRejected,
          PharosLoginIssue.busy => ProbeIssue.busy,
          PharosLoginIssue.locked => ProbeIssue.locked,
          PharosLoginIssue.tooManyFails => ProbeIssue.tooManyFails,
          PharosLoginIssue.needsSetup => ProbeIssue.needsSetup,
          PharosLoginIssue.readFailed => ProbeIssue.readFailed,
          _ => ProbeIssue.unreachable,
        },
        '$model ${why?.issue.name ?? '?'} ${why?.trace ?? ''}',
        lockLeft: why?.lockLeft,
      );
      if (why?.issue != PharosLoginIssue.rejected || i == list.length - 1) break;
      // رفضٌ ⇒ الاعتماد التالي بتعرّفٍ جديد: الـnonce استُهلك، وعدّاد الفشل زاد فيُعاد فحص حدّه.
      h = await _helloTplink(ip);
      if (h == null) break;
    }
    return null;
  }

  /// تعرّف ZTE الجاري لكلّ عنوان — فرع الـONT وفرع Ubiquiti يتشاركانه (طلبٌ واحد).
  static final _zteDetecting = <String, Future<bool>>{};

  static Future<bool> _isZte(String ip) {
    final running = _zteDetecting[ip];
    if (running != null) return running;
    final f = ZteOntService.detect(ip);
    _zteDetecting[ip] = f;
    f.whenComplete(() => _zteDetecting.remove(ip));
    return f;
  }

  /// اعتمادات الفحص: ما ضبطه الوكيل لهذا المشترك أوّلاً، ثمّ افتراضات المدير، ثمّ افتراض المصنّع.
  ///
  /// 🐛 ٢٧ أكتوبر (المالك على ZTE MH80: «خليت يوزر وباسورد وميجلب شي»): كانت اعتمادات المشترك تُهمل ما بقي النوع
  /// «تلقائي» — لا تُستعمل إلّا إن اختار «ONT» أو «UBNT» صراحةً — فيُجرَّب الافتراض ويُرفض. الآن «تلقائي» يستعملها للنوعين:
  /// كلّ فرعٍ لا يدخل إلّا على واجهته (ZTE بعد التعرّف، وهواوي عند صفحة رمزه، وUBNT على airOS).
  /// [ontSet]: يوزر الـONT من الوكيل (للمشترك أو افتراضات المدير) لا افتراض مصنّع هواوي — ZTE لا يُجرَّب عليه افتراضٌ من
  /// عندنا (كلّ رفضٍ يقرّب قفله، وكلمة سرّه على ظهر كلّ جهاز).
  @visibleForTesting
  static ({String ontUser, String ontPass, String ubntUser, String ubntPass, bool ontSet}) credsFor(
    DeviceConfig? cfg,
    AdminDeviceDefaults defaults,
  ) {
    final kind = cfg?.deviceType;
    final ownForOnt = kind == null || kind == DeviceKind.ont;
    final ownForUbnt = kind == null || kind == DeviceKind.ubiquiti;
    final user = cfg?.username?.trim() ?? '';
    final pass = cfg?.password ?? '';
    String pick(bool own, String mine, String? admin, String factory) =>
        own && mine.isNotEmpty ? mine : (admin?.isNotEmpty == true ? admin! : factory);
    return (
      ontUser: pick(ownForOnt, user, defaults.ontUsername, _kOntUser),
      ontPass: pick(ownForOnt, pass, defaults.ontPassword, _kOntPass),
      ubntUser: pick(ownForUbnt, user, defaults.ubntUsername, _kUbntUser),
      ubntPass: pick(ownForUbnt, pass, defaults.ubntPassword, _kUbntPass),
      ontSet: (ownForOnt && user.isNotEmpty) || defaults.ontUsername?.isNotEmpty == true,
    );
  }

  /// ⑦ (٢٩ أكتوبر — المالك: «مرات عدهم أكثر من يوزر وباسورد موحّد»): مرشّحو الاعتماد لكلّ نوع بالترتيب. اعتماد
  /// المشترك ⇒ هو وحده (ضبطه الوكيل لهذا الجهاز)؛ وإلّا الخانة الأولى للمدير ثمّ إضافيّاه بلا تكرار. والخانة الأولى
  /// فارغة ⇒ افتراض المصنّع **آخراً** — هواوي وUBNT يجرّبانه كما كانا (لا يتوقّف جهازٌ يعمل به لأنّ الوكيل أضاف
  /// إضافيّاً)، و[ontFactory] يدلّ عليه فيُجرَّب بلا ontSet: جهاز ZTE لا يدخل به أبداً (افتراضٌ من عندنا يقرّب قفله).
  ///
  /// [tplink] (١٠ نوفمبر): اعتماد المشترك وحده، وإلّا خانة المدير الأولى ثمّ إضافيّاه — **بلا افتراض مصنّع أبداً**: جهاز
  /// TP-Link يعدّ المحاولات الغلط من كلّ الهواتف ويقفل صفحته عند عشر.
  @visibleForTesting
  static ({List<DeviceCred> ont, List<DeviceCred> ubnt, DeviceCred? ontFactory, List<DeviceCred> tplink, List<DeviceCred> tprouter}) candidatesFor(
    DeviceConfig? cfg,
    AdminDeviceDefaults defaults,
  ) {
    final c = credsFor(cfg, defaults);
    final kind = cfg?.deviceType;
    final user = cfg?.username?.trim() ?? '';
    final ontOwn = (kind == null || kind == DeviceKind.ont) && user.isNotEmpty;
    final ubntOwn = (kind == null || kind == DeviceKind.ubiquiti) && user.isNotEmpty;
    // [first] = اختيار credsFor نفسه: اعتماد المشترك، وإلّا الخانة الأولى للمدير، وإلّا افتراض المصنّع.
    ({List<DeviceCred> list, DeviceCred? factory}) chain(DeviceCred first,
        {required bool own, required bool adminSet, required List<DeviceCred> extra}) {
      if (own) return (list: [first], factory: null);
      final out = <DeviceCred>[if (adminSet) first];
      for (final e in extra) {
        if (!out.contains(e)) out.add(e);
      }
      if (!adminSet && !out.contains(first)) {
        out.add(first);
        return (list: out, factory: first);
      }
      return (list: out, factory: null);
    }

    final ont = chain(DeviceCred(c.ontUser, c.ontPass),
        own: ontOwn, adminSet: defaults.ontUsername?.isNotEmpty == true, extra: defaults.ontExtra);
    final ubnt = chain(DeviceCred(c.ubntUser, c.ubntPass),
        own: ubntOwn, adminSet: defaults.ubntUsername?.isNotEmpty == true, extra: defaults.ubntExtra);
    final tplink = <DeviceCred>[];
    if (ubntOwn) {
      tplink.add(DeviceCred(user, cfg?.password ?? ''));
    } else {
      final first = defaults.tplinkUsername?.trim() ?? '';
      if (first.isNotEmpty) tplink.add(DeviceCred(first, defaults.tplinkPassword ?? ''));
      for (final e in defaults.tplinkExtra) {
        if (!tplink.contains(e)) tplink.add(e);
      }
    }
    // راوتر TP-Link الحديث (Agile): كلمات سرٍّ فقط، يوزرٌ فارغٌ دائماً (يوزرٌ غير فارغٍ يفسد هاش الدخول). اعتماد المشترك أوّلاً
    // (إن كان من عائلة الراديو)، ثمّ كلمات سرّ المدير المخصّصة، ثمّ باسوردات قائمة TP-Link العاديّة احتياطاً (لو أُدخلت هناك قبل الفصل).
    final tprouter = <DeviceCred>[];
    void addRouterPass(String p) {
      if (p.isEmpty || tprouter.any((e) => e.password == p)) return;
      tprouter.add(DeviceCred('', p));
    }

    // راوترات «كلمة السرّ وحدها» (Agile، Tenda): كلمة سرّ المشترك تكفي بلا يوزر (١٢ نوفمبر — المالك حفظ لمشتركَي Tenda كلمة سرٍّ
    // وحدها، وكانت تُهمَل لأنّ «اعتماد المشترك» كان مشروطاً باليوزر).
    final subPass = cfg?.password ?? '';
    if ((kind == null || kind == DeviceKind.ubiquiti) && subPass.isNotEmpty) addRouterPass(subPass);
    addRouterPass(defaults.tprouterPassword ?? '');
    for (final p in defaults.tprouterExtra) {
      addRouterPass(p);
    }
    addRouterPass(defaults.tplinkPassword ?? '');
    for (final e in defaults.tplinkExtra) {
      addRouterPass(e.password);
    }
    return (ont: ont.list, ubnt: ubnt.list, ontFactory: ont.factory, tplink: tplink, tprouter: tprouter);
  }

  /// ⑦: الاعتماد الذي دخل على كلّ عنوان (بمفتاح كاش النوع) — الفحص التالي يبدأ به، وجلسة الترافيك وإعادة التشغيل
  /// تستعملانه ([resolveOntCreds]/[resolveUbntCreds]).
  static final _ontWinner = <String, DeviceCred>{};
  static final _ubntWinner = <String, DeviceCred>{};
  static final _tplinkWinner = <String, DeviceCred>{};

  static List<DeviceCred> _winnerFirst(List<DeviceCred> c, DeviceCred? w) =>
      (w == null || !c.contains(w)) ? c : [w, ...c.where((x) => x != w)];

  /// ⑦: يجرّب مرشّحي ONT بالترتيب (الفائز المحفوظ أوّلاً)، ويقف حين لا يكون الاعتماد هو السبب ([_nextCredWorth]).
  /// [factory] افتراض المصنّع إن كان بالقائمة: يُجرَّب بلا ontSet ⇒ ZTE يردّ «يحتاج اعتمادات» بلا أيّ محاولة دخول.
  static Future<DeviceHealthSnapshot?> _probeOntAny(
      String ip, List<DeviceCred> cands, String kindKey, {DeviceCred? factory}) async {
    final list = _winnerFirst(cands, _ontWinner[kindKey]);
    for (var i = 0; i < list.length; i++) {
      final started = DateTime.now();
      final snap = await _probeOnt(ip, list[i].username, list[i].password, kindKey, ontSet: list[i] != factory);
      if (snap != null) {
        _ontWinner[kindKey] = list[i];
        return snap;
      }
      if (i == list.length - 1 || !await _nextCredWorth(ip, started, nextIsFactory: list[i + 1] == factory)) break;
    }
    return null;
  }

  /// ⑦: مثل [_probeOntAny] لـUbiquiti.
  static Future<DeviceHealthSnapshot?> _probeUbntAny(
      String ip, List<DeviceCred> cands, String kindKey, {bool unlessOther = false}) async {
    final list = _winnerFirst(cands, _ubntWinner[kindKey]);
    for (var i = 0; i < list.length; i++) {
      final started = DateTime.now();
      final snap = await _probeUbnt(ip, list[i].username, list[i].password, unlessOther: unlessOther);
      if (snap != null) {
        _ubntWinner[kindKey] = list[i];
        return snap;
      }
      if (i == list.length - 1 || !await _nextCredWorth(ip, started)) break;
    }
    return null;
  }

  /// يستحقّ الاعتمادُ التالي المحاولة؟ ZTE سجّل سببه في هذه الجولة ⇒ «مرفوض» وحده، ولا يُنتقل منه إلى افتراض المصنّع
  /// ([nextIsFactory]) — فيبقى سبب الكرت «رفض اليوزر أو الباسورد» لا «يحتاج اعتمادات» (قفلٌ/مشغولٌ/لا يجاوب ⇒ قف، فلا
  /// يُطرَق جهازٌ يقترب من قفله)؛ هواوي وUBNT لا يقولان سببهما ⇒ التالي فقط إن كان الجهاز واصلاً (بنگ) — فلا ينتظر
  /// جهازٌ مطفأ مهلةً لكلّ اعتماد.
  static Future<bool> _nextCredWorth(String ip, DateTime started, {bool nextIsFactory = false}) async {
    final z = _zteIssue[ip];
    if (z != null && !z.at.isBefore(started)) return z.issue == ProbeIssue.loginRejected && !nextIsFactory;
    return (await reachable(fallbackIp: ip)) == true;
  }

  /// آخر مورّد ONT نجح لكلّ عنوان (بمفتاح كاش النوع) — الفحص التالي يذهب إليه وحده.
  static final _ontVendorByKey = <String, String>{};

  /// ONT: هواوي (الأصل) أو ZTE (ZXIC MH80، ٢٥ أكتوبر). أوّل مرّة الاثنان معاً والأسبق نجاحاً — فرع ZTE لا يدخل إلّا على
  /// واجهة ZTE ([ZteOntService.detect])، وهواوي على جهاز ZTE يقف عند صفحة رمزه (لا محاولة دخول)؛ فلا محاولةٌ خاطئة تقفل
  /// جهازاً. بعدها المورّد المحفوظ وحده، ويُنسى إن فشل (جهازٌ تبدّل).
  static Future<DeviceHealthSnapshot?> _probeOnt(
      String ip, String user, String pass, String kindKey, {bool ontSet = true}) async {
    final known = _ontVendorByKey[kindKey];
    if (known != null) {
      final snap = known == 'zte'
          ? await _probeZte(ip, user, pass, ontSet: ontSet)
          : await _probeHuawei(ip, user, pass);
      if (snap == null) _ontVendorByKey.remove(kindKey);
      return snap;
    }
    // التعرّف أوّلاً (صفحةٌ بلا دخول) ثمّ فرعٌ واحد: هواوي لا يطرق جهاز ZTE بطلباته وهو يدخل، ولا العكس.
    _zteMark(ip, 'detect');
    final zte = _isZte(ip);
    Future<DeviceHealthSnapshot?> huawei() async => await zte ? null : _probeHuawei(ip, user, pass);
    Future<DeviceHealthSnapshot?> zteBranch() async =>
        await zte ? _probeZte(ip, user, pass, detected: true, ontSet: ontSet) : null;
    final snap = await _firstNonNull<DeviceHealthSnapshot>([huawei(), zteBranch()]);
    if (snap != null) _ontVendorByKey[kindKey] = snap.ont?.vendor ?? 'huawei';
    return snap;
  }

  /// ZTE: تعرّفٌ بلا دخول، ثمّ دخولٌ باعتمادات الوكيل وحدها (المرفوضة لا تُعاد)، والضوء، والخروج — الواجهة
  /// قد ترفض دخولاً ثانياً وجلسةٌ مفتوحة، فلا تبقى جلسة الفحص تزاحم جلسة الترافيك. سبب الفشل يُسجَّل للكرت.
  static Future<DeviceHealthSnapshot?> _probeZte(
      String ip, String user, String pass, {bool detected = false, bool ontSet = true}) async {
    if (!detected) {
      _zteMark(ip, 'detect');
      if (!await _isZte(ip)) return null;
    }
    if (!ontSet) {
      _zteIssue[ip] = (issue: ProbeIssue.needsCredentials, lockLeft: null, at: DateTime.now(), trace: 'zte no-creds');
      return null;
    }
    _zteMark(ip, 'login');
    final session = await ZteOntService.loginConfigured(ip, user, pass);
    if (session == null) {
      final z = ZteOntService.lastIssue(ip);
      _zteIssue[ip] = (
        issue: switch (z?.issue) {
          ZteLoginIssue.rejected => ProbeIssue.loginRejected,
          ZteLoginIssue.busy => ProbeIssue.busy,
          ZteLoginIssue.locked => ProbeIssue.locked,
          _ => ProbeIssue.unreachable,
        },
        lockLeft: z?.lockLeft,
        at: DateTime.now(),
        trace: 'zte login ${z?.issue.name ?? '?'} ${z?.trace ?? ''}',
      );
      return null;
    }
    try {
      _zteMark(ip, 'read');
      final optical = await ZteOntService.fetchOptical(session);
      _zteMark(ip, 'readDone');
      if (optical == null) {
        final info = ZteOntService.lastPageInfo(session);
        _zteIssue[ip] = (
          issue: ZteOntService.lastReadUnknown(session) ? ProbeIssue.unknownFormat : ProbeIssue.readFailed,
          lockLeft: null,
          at: DateTime.now(),
          trace: 'zte read ${ZteOntService.lastPageTrace(session) ?? 'no-rx'}${info == null ? '' : ' | $info'}',
        );
        return null;
      }
      return DeviceHealthSnapshot(kind: DeviceKind.ont, ip: ip, ont: optical);
    } finally {
      await ZteOntService.logout(session);
    }
  }

  static Future<DeviceHealthSnapshot?> _probeHuawei(
      String ip, String user, String pass) async {
    // ⚠️ ميزانيّةٌ تساوي سقف الفحص: المستدعي يتخلّى عنّا عند
    //    `_probeCap`، و`.timeout` لا يُلغي عملنا. فبلا هذه الميزانيّة
    //    نُكمل ثلاث محاولاتٍ أُخَر (٤٥ ثانية) لا يقرأ نتيجتها أحد —
    //    سلاسل يتيمة تتراكم وتضغط المقابس، فيُفشل الضغطُ جهازاً حيّاً
    //    بطيئاً ويُعلَن ميّتاً.
    final session =
        await HuaweiOntService.login(ip, user, pass, budget: _probeCap);
    if (session == null) return null;
    final optical = await HuaweiOntService.fetchOptical(session);
    if (optical == null) return null;
    return DeviceHealthSnapshot(kind: DeviceKind.ont, ip: ip, ont: optical);
  }

  /// بيانات دخول Ubiquiti لجهاز مشترك + عنوانه الفعّال.
  ///
  /// حلّ الاعتمادات يعيش هنا لا في الواجهة: نفس ترتيب أفضليّة الفحص
  /// (تجاوز المشترك ← افتراضات المدير ← ubnt/ubnt)، فلا يتفرّع منطقان
  /// يختلفان بصمت فيعمل الفحص ويفشل القياس على الجهاز نفسه.
  static Future<({String ip, String user, String pass})?> resolveUbntCreds({
    required String fallbackIp,
    String? subscriberUsername,
    String? company,
  }) async {
    final ip = fallbackIp.trim();
    DeviceConfig? cfg;
    String effectiveIp = ip;
    if (subscriberUsername != null && subscriberUsername.isNotEmpty) {
      cfg = await DeviceConfigApi.fetchConfig(subscriberUsername,
          company: company);
      final custom = cfg?.customIp?.trim();
      if (custom != null && custom.isNotEmpty) effectiveIp = custom;
    }
    if (effectiveIp.isEmpty) return null;
    // ⑦: الاعتماد الذي دخل به الفحص على هذا العنوان — الترافيك وإعادة التشغيل بالاعتماد العامل نفسه.
    final won = _ubntWinner[_k(company, effectiveIp)];
    if (won != null) return (ip: effectiveIp, user: won.username, pass: won.password);
    final defaults = await _loadAdminDefaults(company);
    final overrides = (cfg?.username?.isNotEmpty ?? false) ||
        (cfg?.password?.isNotEmpty ?? false);
    final user = overrides && (cfg?.username?.isNotEmpty ?? false)
        ? cfg!.username!
        : (defaults.ubntUsername?.isNotEmpty == true
            ? defaults.ubntUsername!
            : _kUbntUser);
    final pass = overrides && (cfg?.password?.isNotEmpty ?? false)
        ? cfg!.password!
        : (defaults.ubntPassword?.isNotEmpty == true
            ? defaults.ubntPassword!
            : _kUbntPass);
    return (ip: effectiveIp, user: user, pass: pass);
  }

  /// بيانات دخول TP-Link لجهاز مشترك + عنوانه الفعّال — لجلسة الكرت الحيّة: الاعتماد الذي دخل به الفحص على هذا العنوان،
  /// وإلّا أوّل مرشّحي الوكيل ([candidatesFor])؛ null حين لا اعتماد له (لا افتراض من عندنا).
  static Future<({String ip, String user, String pass})?> resolveTplinkCreds({
    required String fallbackIp,
    String? subscriberUsername,
    String? company,
  }) async {
    final ip = fallbackIp.trim();
    DeviceConfig? cfg;
    String effectiveIp = ip;
    if (subscriberUsername != null && subscriberUsername.isNotEmpty) {
      cfg = await DeviceConfigApi.fetchConfig(subscriberUsername, company: company);
      final custom = cfg?.customIp?.trim();
      if (custom != null && custom.isNotEmpty) effectiveIp = custom;
    }
    if (effectiveIp.isEmpty) return null;
    final won = _tplinkWinner[_k(company, effectiveIp)];
    if (won != null) return (ip: effectiveIp, user: won.username, pass: won.password);
    final cands = candidatesFor(cfg, await _loadAdminDefaults(company)).tplink;
    if (cands.isEmpty) return null;
    return (ip: effectiveIp, user: cands.first.username, pass: cands.first.password);
  }

  /// بيانات دخول ONT لجهاز مشترك + عنوانه الفعّال — بنفس ترتيب
  /// أفضليّة [resolveUbntCreds] حرفاً بحرف، كي لا يعمل الفحص ويفشل
  /// أمرُ إعادة التشغيل على الجهاز نفسه.
  static Future<({String ip, String user, String pass})?> resolveOntCreds({
    required String fallbackIp,
    String? subscriberUsername,
    String? company,
  }) async {
    final ip = fallbackIp.trim();
    DeviceConfig? cfg;
    String effectiveIp = ip;
    if (subscriberUsername != null && subscriberUsername.isNotEmpty) {
      cfg = await DeviceConfigApi.fetchConfig(subscriberUsername,
          company: company);
      final custom = cfg?.customIp?.trim();
      if (custom != null && custom.isNotEmpty) effectiveIp = custom;
    }
    if (effectiveIp.isEmpty) return null;
    // ⑦: الاعتماد الذي دخل به الفحص على هذا العنوان (انظر [resolveUbntCreds]).
    final won = _ontWinner[_k(company, effectiveIp)];
    if (won != null) return (ip: effectiveIp, user: won.username, pass: won.password);
    final defaults = await _loadAdminDefaults(company);
    final overrides = (cfg?.username?.isNotEmpty ?? false) ||
        (cfg?.password?.isNotEmpty ?? false);
    final user = overrides && (cfg?.username?.isNotEmpty ?? false)
        ? cfg!.username!
        : (defaults.ontUsername?.isNotEmpty == true
            ? defaults.ontUsername!
            : _kOntUser);
    final pass = overrides && (cfg?.password?.isNotEmpty ?? false)
        ? cfg!.password!
        : (defaults.ontPassword?.isNotEmpty == true
            ? defaults.ontPassword!
            : _kOntPass);
    return (ip: effectiveIp, user: user, pass: pass);
  }

  /// [unlessOther]: جهازٌ نوعه غير معروف بعد — دخول Ubiquiti لا يُرسل على جهاز ZTE (اعتماداتٌ لغير جهازها، و٢٧ أكتوبر
  /// صار يسبق فرع ZTE إليه حين طالت قراءته) ولا على TP-Link (١٠ نوفمبر). التعرّفان معاً — لا يزيد الثاني انتظاراً.
  static Future<DeviceHealthSnapshot?> _probeUbnt(
      String ip, String user, String pass, {bool unlessOther = false}) async {
    if (unlessOther) {
      // والراوتر الكلاسيكيّ (١١ نوفمبر): لا دخول airOS على جهازٍ ليس لها.
      final other = await Future.wait([_isZte(ip), _isTplink(ip), _isTpClassic(ip), _isTpAgile(ip), _isTenda(ip)]);
      if (other.contains(true)) return null;
    }
    final session =
        await UbiquitiService.login(ip, user, pass, budget: _probeCap);
    if (session == null) return null;
    final status = await UbiquitiService.fetchStatus(session);
    if (status == null) return null;
    return DeviceHealthSnapshot(
        kind: DeviceKind.ubiquiti, ip: ip, ubnt: status);
  }

  static Future<T?> _firstNonNull<T>(List<Future<T?>> futures) {
    final completer = Completer<T?>();
    var pending = futures.length;
    for (final f in futures) {
      f.then((v) {
        if (completer.isCompleted) return;
        if (v != null) {
          completer.complete(v);
        } else if (--pending == 0) {
          completer.complete(null);
        }
      }).catchError((_) {
        if (completer.isCompleted) return;
        if (--pending == 0) completer.complete(null);
      });
    }
    return completer.future;
  }

  /// Debounced persist — نكتب على القرص كل ~3s بدل بعد كل probe.
  /// يمنع I/O ثقيل أثناء waves كبيرة.
  static void _schedulePersist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(seconds: 3), _persist);
  }

  static Future<void> _persist() async {
    try {
      final now = DateTime.now();
      final map = <String, Map<String, dynamic>>{};
      for (final e in _snapCache.entries) {
        final snap = e.value.snap;
        if (snap == null) continue;
        if (now.difference(e.value.at) >= _ttl) continue;
        map[e.key] = {
          'at': e.value.at.toIso8601String(),
          'snap': snap.toJson(),
        };
      }
      final prefs = await SharedPreferences.getInstance();
      if (map.isEmpty) {
        await prefs.remove(_prefsKey);
      } else {
        await prefs.setString(_prefsKey, jsonEncode(map));
      }
    } catch (_) {
      // فشل الكتابة على القرص لا يجب أن يعطّل الـUI. تجاهل.
    }
  }
}

/// هدفٌ في موجة الفحص: المشترك وعنوانه من الراديوس، و[company] شركة صفّه في «كل الشركات» (null في الوضع العاديّ).
typedef ProbeTarget = ({String username, String ip, String? company});

class _Cached {
  const _Cached(this.snap, this.at);
  final DeviceHealthSnapshot? snap;
  final DateTime at;
}
