import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/net/huawei_ont_service.dart';
import '../core/net/zte_ont_service.dart';
import '../core/net/ubiquiti_service.dart';
import '../models/device_health.dart';
import 'company_route.dart';
import 'device_config_api.dart';

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
  static Future<AdminDeviceDefaults>? _adminFetch;

  /// افتراضات كلّ شركةٍ من «كل الشركات» — النجاح يُحفظ للجلسة كالوضع العاديّ، والفشل لا (يُعاد بعد قاطع الدقيقة).
  static final _adminFetchBy = <String, Future<AdminDeviceDefaults?>>{};

  static String _k(String? company, String s) =>
      DeviceConfigApi.scoped(company, s);

  static const _ttl = Duration(minutes: 5);
  // يطابق v1: 15s cap على probe واحد.
  static const _probeCap = Duration(seconds: 15);

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
    _adminFetch = null;
    _adminFetchBy.clear();
    _persistDebounce?.cancel();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {}
  }

  /// Resolves credentials + probes the device.
  ///
  /// * [fallbackIp] — SAS4 IP لو موجود.
  /// * [subscriberUsername] — يُستعمل لجلب DeviceConfig (customIp override).
  /// * [force=true] — يتخطّى snapshot + dead caches (زر تحديث يدوي).
  /// * [company] — صفٌّ من «كل الشركات»: إعداده وافتراضاته من شركته، وكاشه بها.
  static Future<DeviceHealthSnapshot?> probe({
    required String fallbackIp,
    String? subscriberUsername,
    bool force = false,
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
    if (pending != null) return pending;

    final future = _probeAndStore(effectiveIp, cfg, userKey, company);
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
    String? company,
  ) async {
    final ipKey = _k(company, effectiveIp);
    final defaults = await _loadAdminDefaults(company);
    final snap = await _runProbe(effectiveIp, cfg, defaults, ipKey)
        .timeout(_probeCap, onTimeout: () => null);
    final now = DateTime.now();
    final entry = _Cached(snap, now);
    _snapCache[ipKey] = entry;
    if (userKey != null) {
      _snapByUser[userKey] = entry;
    }
    if (snap != null) {
      _kindByIp[ipKey] = snap.kind;
      _deadCache.remove(ipKey); // نجاح → ما هو ميت
    } else {
      // فشل — نضيف لـdead cache حتى نوفّر محاولات متكرّرة قريبة.
      _deadCache[ipKey] = now;
      // Kind cache قد يكون قديم ونحن جربنا الـkind المخزّن وفشل — نمسحه
      // حتى المحاولة القادمة تفجّر parallel وتلقّط لو الجهاز اتبدّل.
      _kindByIp.remove(ipKey);
    }
    _schedulePersist();
    return snap;
  }

  /// Drop one IP's cached snapshot — call after editing per-sub
  /// config so the next render re-probes with new credentials.
  static void invalidateIp(String ip, {String? company}) {
    final k = _k(company, ip.trim());
    _snapCache.remove(k);
    _kindByIp.remove(k);
    _deadCache.remove(k);
    _ontVendorByKey.remove(k);
    // اعتماداتٌ جديدة تُجرَّب: الرفض السابق على هذا العنوان يُنسى (لا يُعاد إلّا المرفوض نفسه بلا تغيير).
    ZteOntService.forget(ip.trim());
    _schedulePersist();
  }

  /// Read-only peek بالـIP.
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

  /// Wave batched probe.
  ///
  /// * [priorityUsernames] — تُفحص أوّلاً. للـviewport-visible subs،
  ///   يمنح إحساس بأن الفحص "فوري" حتى مع قوائم كبيرة.
  /// * [concurrency] — عدد العمّال المتزامنين. حوضٌ منزلق لا دفعاتٌ
  ///   متتابعة: من فرغ أخذ الهدف التالي فوراً. راجع [_defaultWorkers]
  ///   لسبب الرقم.
  /// * [onProgress] — يُنادى بعد **كلّ هدف** لا بعد كلّ دفعة. فليكن
  ///   رخيصاً؛ لا `setState` على شاشةٍ كاملة فيه.
  /// * `company` في الهدف — شركة الصفّ في «كل الشركات» (null في الوضع العاديّ): دفعة إعدادات لكلّ شركة، وحوضٌ واحد للكلّ.
  static Future<void> warmProbe(
    List<ProbeTarget> targets, {
    Set<String>? priorityUsernames,
    int concurrency = _defaultWorkers,
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

    final workers = concurrency < ordered.length ? concurrency : ordered.length;
    await Future.wait(List.generate(workers, (_) => worker()));
  }

  static void invalidateAdminDefaults() {
    _adminFetch = null;
    _adminFetchBy.clear();
    _snapCache.clear();
    _snapByUser.clear();
    _kindByIp.clear();
    _deadCache.clear();
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
    final c = credsFor(cfg, defaults);
    final ontUser = c.ontUser, ontPass = c.ontPass, ubntUser = c.ubntUser, ubntPass = c.ubntPass;

    // Admin pinned kind → probe واحد فقط.
    if (overridesOnt) return _probeOnt(ip, ontUser, ontPass, kindKey);
    if (overridesUbnt) return _probeUbnt(ip, ubntUser, ubntPass);

    // Kind cache — لو نعرف من probe سابق إن IP هذا ONT (أو UBNT)،
    // نفجّر النوع الصحيح فقط. توفير ~5s متوسط. مطلب المستخدم 2026-07-12.
    // احتياط: لو الـkind المخزّن فشل، نمسحه (فوق) والمحاولة القادمة
    // ترجع parallel لتتلاقط تغيير الجهاز.
    final knownKind = _kindByIp[kindKey];
    if (knownKind == DeviceKind.ont) {
      return _probeOnt(ip, ontUser, ontPass, kindKey);
    }
    if (knownKind == DeviceKind.ubiquiti) {
      return _probeUbnt(ip, ubntUser, ubntPass);
    }

    // First-time أو kind cache cleared — parallel race.
    final ont = _probeOnt(ip, ontUser, ontPass, kindKey);
    final ubnt = _probeUbnt(ip, ubntUser, ubntPass);
    return _firstNonNull<DeviceHealthSnapshot>([ont, ubnt]);
  }

  /// اعتمادات الفحص: ما ضبطه الوكيل لهذا المشترك أوّلاً، ثمّ افتراضات المدير، ثمّ افتراض المصنّع.
  ///
  /// 🐛 ٢٧ أكتوبر (المالك على ZTE MH80: «خليت يوزر وباسورد وميجلب شي»): كانت اعتمادات المشترك تُهمل ما بقي النوع
  /// «تلقائي» — لا تُستعمل إلّا إن اختار «ONT» أو «UBNT» صراحةً — فيُجرَّب الافتراض ويُرفض. الآن «تلقائي» يستعملها للنوعين:
  /// كلّ فرعٍ لا يدخل إلّا على واجهته (ZTE بعد التعرّف، وهواوي عند صفحة رمزه، وUBNT على airOS).
  @visibleForTesting
  static ({String ontUser, String ontPass, String ubntUser, String ubntPass}) credsFor(
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
    );
  }

  /// آخر مورّد ONT نجح لكلّ عنوان (بمفتاح كاش النوع) — الفحص التالي يذهب إليه وحده.
  static final _ontVendorByKey = <String, String>{};

  /// ONT: هواوي (الأصل) أو ZTE (ZXIC MH80، ٢٥ أكتوبر). أوّل مرّة الاثنان معاً والأسبق نجاحاً — فرع ZTE لا يدخل إلّا على
  /// واجهة ZTE ([ZteOntService.detect])، وهواوي على جهاز ZTE يقف عند صفحة رمزه (لا محاولة دخول)؛ فلا محاولةٌ خاطئة تقفل
  /// جهازاً. بعدها المورّد المحفوظ وحده، ويُنسى إن فشل (جهازٌ تبدّل).
  static Future<DeviceHealthSnapshot?> _probeOnt(
      String ip, String user, String pass, String kindKey) async {
    final known = _ontVendorByKey[kindKey];
    if (known != null) {
      final snap = known == 'zte'
          ? await _probeZte(ip, user, pass)
          : await _probeHuawei(ip, user, pass);
      if (snap == null) _ontVendorByKey.remove(kindKey);
      return snap;
    }
    final snap = await _firstNonNull<DeviceHealthSnapshot>([
      _probeHuawei(ip, user, pass),
      _probeZte(ip, user, pass),
    ]);
    if (snap != null) _ontVendorByKey[kindKey] = snap.ont?.vendor ?? 'huawei';
    return snap;
  }

  /// ZTE: تعرّفٌ بلا دخول، ثمّ دخولٌ باعتمادات الوكيل وحدها (المرفوضة لا تُعاد)، والضوء، والخروج — الواجهة
  /// قد ترفض دخولاً ثانياً وجلسةٌ مفتوحة، فلا تبقى جلسة الفحص تزاحم جلسة الترافيك.
  static Future<DeviceHealthSnapshot?> _probeZte(
      String ip, String user, String pass) async {
    if (!await ZteOntService.detect(ip)) return null;
    final session = await ZteOntService.loginConfigured(ip, user, pass);
    if (session == null) return null;
    try {
      final optical = await ZteOntService.fetchOptical(session);
      if (optical == null) return null;
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

  static Future<DeviceHealthSnapshot?> _probeUbnt(
      String ip, String user, String pass) async {
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
