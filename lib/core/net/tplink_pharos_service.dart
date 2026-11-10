import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/device_health.dart';

/// جهاز المشترك اللاسلكيّ TP-Link Pharos (CPE/WBS — واجهة PharOS) — طلب المالك ١٠ نوفمبر: «صنف جديد من النانوات tplink يحتاج
/// نضيفه ضمن الاعتمادات… يجلب نفس المعلومات مال النانوات».
///
/// مستكشَفٌ حيّاً على CPE610 v2.0 (PharOS 2.2.99) للقراءة فقط — كلّ سطرٍ هنا مَقيسٌ على الجهاز لا مُخمَّن:
/// - **التعرّف بلا دخول:** GET `/data/version.json` ⇒ JSON فيه `devInfo`/`devVer`/`mode`/`status`/`failedCount`/`lockTime`،
///   وكوكي `COOKIE=<nonce>` — هو nonce الدخول. الطلب لا يمسّ جلسةً قائمة.
/// - **الدخول:** POST `/data/version.json` بـ`encoded=<user>:MD5(MD5(pass)↑:nonce)↑` و`nonce` ⇒ `status`: 0 نجاح (ويصفّر
///   عدّاد الفشل) · 1 رفض (`failedCount` يزيد، وعشرٌ تقفل الواجهة ساعتين) · 4 مستخدمٌ آخر داخل من عنوانٍ ثانٍ · 3 الجلسات
///   ممتلئة · 5 يطلب تغيير كلمة السرّ · ‎-1 الـnonce قديم (طلبه عميلٌ آخر بيننا) — لا يُحسب محاولةً ويُعاد بالكوكي الجديد.
/// - **جلسةٌ واحدة للجهاز كلّه:** دخولٌ ثانٍ من العنوان نفسه يطرد الأوّل بصمت؛ خروجٌ بكوكي قديم لا يمسّ الجلسة القائمة.
/// - **القراءة:** GET `/data/info.json` (كلّ شيء) و`/data/progressBar.json` (الحيّ: ترافيك kbps + الإشارة) — POST يردّ فارغاً.
///   جلسةٌ منتهية تردّ `{"success":true,"timeout":true}` بلا `data`.
/// - **الخروج:** GET `/data/version.json?option=logout`.
/// - المنفذ 80 يخدم `/data/*` ولو كان HTTPS مفعّلاً (الجذر وحده يُحوَّل 303)؛ وHTTPS بمفتاح RSA 1024 وتبادل RSA وحده —
///   مكدّس Dart يصله (جُرِّب). الجلسة بالكوكي لا بالمخطّط: nonce أُخذ بـHTTP يُقبل دخولاً بـHTTPS، والقراءة بعده بأيّهما.
/// - كلّ طلب قراءةٍ يحتاج ترويسة `Referer` (بلاها يردّ الجهاز جسماً فارغاً والجلسة سليمة).
///
/// **الدخول مشفّر حين يتيحه الجهاز:** بصمة كلمة السرّ (MD5 بتحدٍّ — كلمةٌ قصيرة تُكسر منها بثوانٍ) لا تمرّ مكشوفةً على
/// وصلة لاسلكيّة مفتوحة مع كلّ موجة فحص: طلب الدخول وحده يُرسل بـHTTPS إن جاوب منفذه (يُتذكَّر لكلّ جهاز)، وإلّا بـHTTP كما
/// تفعل صفحة الجهاز نفسها. التعرّف والقراءات بـHTTP (لا سرّ فيها، وهي أسرع بثلاثة أرباع الثانية لكلّ طلب).
class TplinkPharosService {
  TplinkPharosService._();

  static const _connect = Duration(seconds: 4);
  static const _receive = Duration(seconds: 8);

  /// مهلة فتح الاتّصال المشفّر للدخول: منفذٌ مغلق يردّ فوراً، ومحجوبٌ بصمت لا يُنتظر عليه طويلاً (مرّةً لكلّ جهاز بالجلسة).
  static const _secureConnect = Duration(seconds: 3);

  /// هل جاوب منفذ الجهاز المشفّر على الدخول؟ (true يعمل · false لا يجاوب ⇒ لا يُجرَّب ثانيةً حتى [forget]/[reset]).
  static final _secureLogin = <String, bool>{};

  /// دخل [host] مشفّراً؟ (null: لم يُجرَّب بعد) — للتشخيص والاختبار.
  @visibleForTesting
  static bool? secureLoginWorked(String host) => _secureLogin[host];

  /// عنوان الدخول المشفّر لـ[host] — null لعنوانٍ بمنفذٍ مكتوب (تحويل منفذ: لا يُعرف منفذه المشفّر). يُحقن في الاختبار.
  @visibleForTesting
  static String? Function(String host) secureBaseFor = defaultSecureBase;
  static String? defaultSecureBase(String host) => RegExp(r':\d{1,5}$').hasMatch(host) ? null : 'https://$host';

  /// لا محاولة دخولٍ تلقائيّة والجهاز عدّ هذا القدر من المحاولات الغلط: القفل عند عشر (ساعتان بلا صفحة الجهاز للوكيل)،
  /// وعدّاد الجهاز يجمع محاولات كلّ الهواتف. فنقف عند النصف ونترك الباقي لصاحب الجهاز.
  static const autoFailLimit = 5;

  /// «حفظ وفحص الجهاز»: الوكيل صحّح الاعتماد بيده ⇒ يُسمح له حتى هذا الحدّ — ولا نبلغ العاشرة أبداً.
  static const manualFailLimit = 8;

  /// مستخدمٌ آخر داخل (من عنوانٍ ثانٍ) ⇒ لا محاولة قبل دقيقة.
  static const busyCooldown = Duration(seconds: 60);

  /// جلستنا الحيّة طُردت (دخل أحدٌ من عنواننا نفسه — متصفّحٌ على الجهاز ذاته، أو أُعيد تشغيل الجهاز): دخولنا ثانيةً يطرده هو،
  /// فننتظر. مرّتان متقاربتان ⇒ أحدٌ يعمل على صفحة الجهاز فعلاً ⇒ انتظارٌ أطول.
  static const kickCooldown = Duration(minutes: 2);
  static const kickCooldownLong = Duration(minutes: 10);
  static const _kickMemory = Duration(minutes: 30);

  /// اعتماداتٌ رفضها جهازٌ (عنوان ⇒ يوزر+باسورد): لا يُعاد أيٌّ منها عليه حتى تتغيّر أو يطلب الوكيل («حفظ وفحص»).
  static final _rejected = <String, Set<String>>{};
  static final _busyUntil = <String, DateTime>{};
  static final _kicks = <String, ({int count, DateTime at})>{};
  static final _manualOnce = <String>{};
  static final _issues = <String, ({PharosLoginIssue issue, int? lockLeft, String trace})>{};

  /// جلسات الكرت الحيّة القائمة (بالعنوان) — الفحص يقرأ بها بدل دخولٍ ثانٍ يطردها.
  static final _active = <String, PharosSession>{};

  /// تسلسل العمل على الجهاز الواحد: دخولان متزامنان من التطبيق نفسه يطرد أحدهما الآخر.
  static final _locks = <String, Future<void>>{};

  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  /// كم مرّةً يُعاد الدخول حين يردّ الجهاز «nonce قديم» (الردّ نفسه يحمل الجديد، ولا يُحسب محاولةً غلط).
  ///
  /// الجهاز يحفظ آخر nonce طلبه **أيّ** عميلٍ وحده: هاتفان يفحصان الجهاز نفسه باللحظة نفسها يُبطل كلٌّ منهما nonce الآخر.
  /// قِيس حيّاً (١٠ نوفمبر): إعادةٌ واحدة لم تكفِ حين تداخل فحصان — فثلاث محاولات بينها مهلةٌ عشوائيّة قصيرة تكسر التناوب.
  static const _staleRounds = 3;
  static final _rng = math.Random();

  @visibleForTesting
  static Duration Function() staleBackoff = () => Duration(milliseconds: 150 + _rng.nextInt(450));

  static Future<T> _serial<T>(String host, Future<T> Function() fn) {
    final prev = _locks[host] ?? Future<void>.value();
    final done = Completer<void>();
    _locks[host] = done.future;
    return prev.then((_) => fn()).whenComplete(() {
      done.complete();
      if (identical(_locks[host], done.future)) _locks.remove(host);
    });
  }

  static Future<_Reply> _send(String base, String method, String path, {String? cookie, String? form, Duration? connect}) async {
    final client = HttpClient()
      ..connectionTimeout = connect ?? _connect
      ..badCertificateCallback = (_, __, ___) => true;
    try {
      final HttpClientRequest req;
      try {
        req = await client.openUrl(method, Uri.parse('$base$path'));
      } catch (e) {
        // لم يُفتح الاتّصال (منفذٌ مغلق، مهلة، مصافحة TLS) — لم يُرسل شيء: يفرّقه المستدعي عن طلبٍ أُرسل ولم يُجَب.
        throw _NoConnection(e);
      }
      req.followRedirects = false;
      // طلبٌ لكلّ اتّصال: خادم الجهاز صغير، وإعادة استعمال اتّصالٍ أغلقه تُفشل الطلب التالي بلا سبب.
      req.persistentConnection = false;
      req.headers.set(HttpHeaders.acceptHeader, 'application/json, text/javascript, */*; q=0.01');
      req.headers.set('X-Requested-With', 'XMLHttpRequest');
      req.headers.set(HttpHeaders.refererHeader, '$base/');
      if (cookie != null && cookie.isNotEmpty) req.headers.set(HttpHeaders.cookieHeader, 'COOKIE=$cookie');
      if (form != null) {
        final bytes = utf8.encode(form);
        req.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded; charset=UTF-8');
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(_receive);
      final body = await res.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(_receive);
      return (
        status: res.statusCode,
        body: body,
        cookie: TplinkPharosParse.cookie(res.headers[HttpHeaders.setCookieHeader]),
        server: res.headers.value(HttpHeaders.serverHeader),
      );
    } finally {
      client.close(force: true);
    }
  }

  static String _errName(Object e) => e is _NoConnection
      ? 'connect:${_errName(e.cause)}'
      : e is TimeoutException
      ? 'timeout'
      : e is SocketException
          ? 'socket'
          : e is HandshakeException
              ? 'tls'
              : e.runtimeType.toString();

  /// هل في [host] واجهة Pharos؟ طلبٌ واحد بلا دخول يردّ هويّة الجهاز وحال الدخول والـnonce — null: ليس Pharos أو لا يجاوب.
  ///
  /// HTTP أوّلاً (أخفّ على معالج الجهاز، ويخدم `/data` ولو كان HTTPS مفعّلاً)؛ وHTTPS حين يدلّ الردّ على واجهة TP-Link تحوّل
  /// إليه. عنوانٌ ميّت لا تُعاد عليه المحاولة بالمنفذ الآخر (واجهة Pharos تسمع على HTTP دائماً) — إلّا عنواناً بمنفذٍ مكتوب.
  static Future<PharosHello?> hello(String host) async {
    final h = host.trim();
    if (h.isEmpty) return null;
    final explicitPort = RegExp(r':\d{1,5}$').hasMatch(h);
    for (final base in ['http://$h', 'https://$h']) {
      final _Reply r;
      try {
        r = await _send(base, 'GET', '/data/version.json');
      } catch (_) {
        if (explicitPort && base.startsWith('http://')) continue;
        return null;
      }
      final hello = TplinkPharosParse.hello(r.body, base: base, cookie: r.cookie);
      if (hello != null) return hello;
      if (!explicitPort && !TplinkPharosParse.worthHttps(r.server)) return null;
    }
    return null;
  }

  /// محاولة دخولٍ واحدة بسببها إن فشلت. [hello] تعرّفٌ جرى للتوّ (الـnonce فيه)؛ وإلّا يُطلب.
  ///
  /// لا تُرسل أصلاً على جهازٍ قافل، أو جديدٍ يطلب ضبطه، أو عدّ [failLimit] محاولاتٍ غلط — كلّ محاولةٍ هناك تُحسب عليه.
  static Future<PharosLoginOutcome> attempt(
    String host,
    String user,
    String pass, {
    PharosHello? hello,
    int failLimit = autoFailLimit,
  }) async {
    final h = hello ?? await TplinkPharosService.hello(host);
    if (h == null) return (session: null, issue: PharosLoginIssue.unreachable, lockLeft: null, trace: 'hello:none');
    if (h.lockMinutes > 0) {
      return (session: null, issue: PharosLoginIssue.locked, lockLeft: h.lockMinutes * 60, trace: 'hello:locked ${h.lockMinutes}m');
    }
    if (h.firstLogin) return (session: null, issue: PharosLoginIssue.needsSetup, lockLeft: null, trace: 'hello:first-login');
    if (h.failedCount >= failLimit) {
      return (session: null, issue: PharosLoginIssue.tooManyFails, lockLeft: null, trace: 'hello:fails ${h.failedCount}');
    }
    var nonce = h.cookie;
    if (nonce.isEmpty) return (session: null, issue: PharosLoginIssue.unreachable, lockLeft: null, trace: 'hello:no-nonce');
    for (var round = 0; round < _staleRounds; round++) {
      final form = 'encoded=${Uri.encodeQueryComponent('$user:${TplinkPharosParse.digest(pass, nonce)}')}'
          '&nonce=${Uri.encodeQueryComponent(nonce)}';
      _Reply? sent;
      // الدخول مشفّراً حين يجاوب منفذه (الجلسة بالكوكي: التعرّف والقراءات تبقى على مخطّطها).
      final secure = h.base.startsWith('http://') && _secureLogin[host] != false ? secureBaseFor(host) : null;
      if (secure != null) {
        try {
          sent = await _send(secure, 'POST', '/data/version.json', cookie: nonce, form: form, connect: _secureConnect);
          _secureLogin[host] = true;
        } on _NoConnection {
          // لا منفذ مشفّر (HTTPS مطفأ بالجهاز أو محجوب): لم يُرسل شيء ⇒ الدخول كما تفعل صفحة الجهاز.
          _secureLogin[host] = false;
        } catch (e) {
          // أُرسل ولم يُجَب: لا نعيده على المنفذ الآخر (قد يكون الجهاز عالجه) — «ما يجاوب»، والفحص التالي يحاول.
          return (session: null, issue: PharosLoginIssue.unreachable, lockLeft: null, trace: 'post-tls:${_errName(e)}');
        }
      }
      final _Reply r;
      if (sent != null) {
        r = sent;
      } else {
        try {
          r = await _send(h.base, 'POST', '/data/version.json', cookie: nonce, form: form);
        } catch (e) {
          return (session: null, issue: PharosLoginIssue.unreachable, lockLeft: null, trace: 'post:${_errName(e)}');
        }
      }
      final j = TplinkPharosParse.json(r.body);
      final status = TplinkPharosParse.intOf(j?['status']);
      final lock = TplinkPharosParse.intOf(j?['lockTime']) ?? 0;
      final trace = 'post${sent != null ? '-tls' : ''}:${r.status} st:${status ?? '-'}'
          ' fc:${TplinkPharosParse.intOf(j?['failedCount']) ?? '-'} len:${r.body.length}';
      switch (status) {
        case 0:
          return (
            session: PharosSession._(host: host, base: h.base, cookie: r.cookie ?? nonce, model: h.model, mode: h.mode),
            issue: null,
            lockLeft: null,
            trace: trace,
          );
        case 1:
          // العاشرة تقفل: الردّ نفسه يحمل وقت القفل.
          return lock > 0
              ? (session: null, issue: PharosLoginIssue.locked, lockLeft: lock * 60, trace: trace)
              : (session: null, issue: PharosLoginIssue.rejected, lockLeft: null, trace: trace);
        case 4:
          // مستخدمٌ آخر داخل: الصفحة تسأل «أكمل؟» — الإكمال يطرده، فنلغي ونتركه.
          unawaited(_quiet(() => _send(h.base, 'POST', '/data/version.json', cookie: r.cookie ?? nonce, form: 'option=cancel')));
          return (session: null, issue: PharosLoginIssue.busy, lockLeft: null, trace: trace);
        case 3:
          return (session: null, issue: PharosLoginIssue.busy, lockLeft: null, trace: trace);
        case 5:
          // دخلنا والجهاز يطلب تغيير كلمة السرّ قبل أيّ شيء — لا نغيّر شيئاً، ونخرج.
          unawaited(_quiet(() => _send(h.base, 'GET', '/data/version.json?option=logout', cookie: r.cookie ?? nonce)));
          return (session: null, issue: PharosLoginIssue.needsSetup, lockLeft: null, trace: trace);
        case -1 || 2:
          // الـnonce قديم: عميلٌ آخر (هاتفٌ أو متصفّح) طلب واحداً بيننا — الجهاز لا يعدّها محاولة، والردّ يحمل الجديد.
          final fresh = r.cookie;
          if (round < _staleRounds - 1 && fresh != null && fresh.isNotEmpty && fresh != nonce) {
            nonce = fresh;
            await Future<void>.delayed(staleBackoff());
            continue;
          }
          return (session: null, issue: PharosLoginIssue.unreachable, lockLeft: null, trace: '$trace stale x${round + 1}');
        default:
          return (session: null, issue: PharosLoginIssue.unreachable, lockLeft: null, trace: trace);
      }
    }
    return (session: null, issue: PharosLoginIssue.unreachable, lockLeft: null, trace: 'post:stale');
  }

  static Future<void> _quiet(Future<Object?> Function() fn) async {
    try {
      await fn();
    } catch (_) {}
  }

  /// جلسة كرتٍ حيّة قائمة على [host]؟ — الفحص يقرأ بها بلا تعرّفٍ ولا دخول.
  static bool hasLive(String host) => _active[host]?.lost == false;

  /// آخر سبب فشلٍ على [host] (null: آخر دخولٍ نجح أو لا محاولة).
  static ({PharosLoginIssue issue, int? lockLeft, String trace})? lastIssue(String host) => _issues[host];

  /// اعتماداتٌ جديدة ضُبطت لهذا العنوان، أو طلب الوكيل إعادة المحاولة: الرفض والانتظار السابقان يُنسيان. [manual] («حفظ
  /// وفحص الجهاز»): المحاولة التالية بحدّ الوكيل ([manualFailLimit]) لا الحدّ التلقائيّ.
  static void forget(String host, {bool manual = false}) {
    _rejected.remove(host);
    _busyUntil.remove(host);
    _kicks.remove(host);
    _issues.remove(host);
    _secureLogin.remove(host);
    if (manual) _manualOnce.add(host);
  }

  /// خروج المدير / تبديل الحساب: لا شيء من جلسة الحساب السابق يبقى.
  static void reset() {
    _rejected.clear();
    _busyUntil.clear();
    _kicks.clear();
    _manualOnce.clear();
    _issues.clear();
    _secureLogin.clear();
    for (final s in _active.values.toList()) {
      unawaited(logout(s));
    }
    _active.clear();
  }

  /// دخولٌ بالاعتمادات التي ضبطها الوكيل وحدها — لا تجربة كلمات مرورٍ من عندنا. المرفوض على هذا العنوان لا يُعاد حتى يتغيّر
  /// (أو [forget])، و«مشغول» ينتظر مهلته.
  static Future<PharosSession?> loginConfigured(String host, String user, String pass, {PharosHello? hello}) async {
    final key = '$user\u0000$pass';
    if (user.isEmpty) {
      _issues[host] = (issue: PharosLoginIssue.rejected, lockLeft: null, trace: 'no-user');
      return null;
    }
    final manual = _manualOnce.remove(host);
    if (_rejected[host]?.contains(key) ?? false) {
      _issues[host] = (issue: PharosLoginIssue.rejected, lockLeft: null, trace: 'remembered');
      return null;
    }
    final until = _busyUntil[host];
    if (until != null && clock().isBefore(until)) {
      _issues[host] = (issue: PharosLoginIssue.busy, lockLeft: null, trace: 'cooldown');
      return null;
    }
    final r = await attempt(host, user, pass, hello: hello, failLimit: manual ? manualFailLimit : autoFailLimit);
    final s = r.session;
    if (s != null) {
      _rejected[host]?.remove(key);
      _busyUntil.remove(host);
      _issues.remove(host);
      return s;
    }
    final issue = r.issue ?? PharosLoginIssue.unreachable;
    if (issue == PharosLoginIssue.rejected) (_rejected[host] ??= <String>{}).add(key);
    if (issue == PharosLoginIssue.busy) _busyUntil[host] = clock().add(busyCooldown);
    _issues[host] = (issue: issue, lockLeft: r.lockLeft, trace: r.trace);
    return null;
  }

  static Future<Map<String, dynamic>?> _data(PharosSession s, String path) async {
    final _Reply r;
    try {
      r = await _send(s.base, 'GET', path, cookie: s.cookie);
    } catch (e) {
      s._trace = '$path:${_errName(e)}';
      return null;
    }
    final j = TplinkPharosParse.json(r.body);
    final data = j?['data'];
    if (j != null && data is! Map && j['timeout'] == true) {
      // الجلسة انتهت: دخل أحدٌ غيرنا (جلسةٌ واحدة للجهاز) أو أُعيد تشغيله.
      s._lost = true;
      s._trace = '$path:${r.status} session-timeout';
      return null;
    }
    if (data is! Map) {
      s._trace = '$path:${r.status} len:${r.body.length} no-data';
      return null;
    }
    return Map<String, dynamic>.from(data);
  }

  /// القراءة الكاملة (الإشارة، الجودة، المعدّلات، المنافذ، الاسم والإصدار) — null: الجلسة انتهت أو تعذّر الطلب.
  static Future<UbiquitiStatus?> fetchStatus(PharosSession s) async {
    final d = await _data(s, '/data/info.json');
    if (d == null) return null;
    final st = TplinkPharosParse.status(d, base: s.base, model: s.model);
    if (st == null) s._trace = 'info:unknown-shape ${d.length}';
    return st;
  }

  /// القراءة الحيّة الخفيفة (~٠٫٨ ك.ب): ترافيك الجهاز الآن مع الإشارة والجودة والمنافذ.
  static Future<PharosLive?> fetchLive(PharosSession s) async {
    final d = await _data(s, '/data/progressBar.json');
    return d == null ? null : TplinkPharosParse.live(d);
  }

  static Future<void> logout(PharosSession s) =>
      _quiet(() => _send(s.base, 'GET', '/data/version.json?option=logout', cookie: s.cookie));

  /// جلسةٌ حيّة انتهت عند الجهاز: تخرج من السجلّ ويُسجَّل الطرد مرّةً واحدة لها (الفحص والكرت كلاهما قد يكتشفه).
  static void _dropLost(PharosSession s) {
    if (identical(_active[s.host], s)) _active.remove(s.host);
    if (s._kickNoted) return;
    s._kickNoted = true;
    _noteKicked(s.host);
  }

  static void _noteKicked(String host) {
    final now = clock();
    final prev = _kicks[host];
    final count = prev != null && now.difference(prev.at) < _kickMemory ? prev.count + 1 : 1;
    _kicks[host] = (count: count, at: now);
    _busyUntil[host] = now.add(count >= 2 ? kickCooldownLong : kickCooldown);
    _issues[host] = (issue: PharosLoginIssue.busy, lockLeft: null, trace: 'kicked x$count');
  }

  /// قراءةٌ واحدة لجهاز المشترك: جلسة الكرت الحيّة إن كانت قائمة (دخولٌ ثانٍ من عنواننا يطردها)، وإلّا دخولٌ ← قراءةٌ ← خروج
  /// — فلا تبقى جلسةٌ لنا تمنع الوكيل عن صفحة جهازه. سبب الفشل في [lastIssue].
  ///
  /// القراءة تُسلَّم فور وصولها، والخروج يكتمل بعدها **داخل تسلسل الجهاز**: طلب الخروج يبدّل nonce الجهاز، فلو سبقه دخولنا
  /// التالي (جلسة الكرت بعد الفحص مباشرةً) لأُبطل nonce ذلك الدخول وأُعيد.
  static Future<UbiquitiStatus?> readOnce(String host, String user, String pass, {PharosHello? hello}) {
    final out = Completer<UbiquitiStatus?>();
    unawaited(_serial(host, () async {
      PharosSession? opened;
      try {
        final live = _active[host];
        if (live != null) {
          final st = live.lost ? null : await fetchStatus(live);
          if (st != null) {
            _issues.remove(host);
          } else if (live.lost) {
            _dropLost(live);
          } else {
            // تعثّرٌ عابر والجلسة قائمة: لا دخول ثانٍ يطردها.
            _issues[host] = (issue: PharosLoginIssue.unreachable, lockLeft: null, trace: live._trace ?? 'live-read');
          }
          out.complete(st);
          return;
        }
        opened = await loginConfigured(host, user, pass, hello: hello);
        if (opened == null) {
          out.complete(null);
          return;
        }
        final st = await fetchStatus(opened);
        if (st == null) {
          _issues[host] = (issue: PharosLoginIssue.readFailed, lockLeft: null, trace: opened._trace ?? 'info:none');
        }
        out.complete(st);
      } catch (e, trace) {
        if (!out.isCompleted) out.completeError(e, trace);
      } finally {
        if (opened != null) await logout(opened);
      }
    }));
    return out.future;
  }

  /// إعادة تشغيل الجهاز — الأمر الذي ترسله صفحته نفسها: `GET /data/configReboot.json` (يردّ `wholeTime` ثواني الإقلاع).
  /// ⚠️ جاره `/data/configReset.json` **إعادة ضبط مصنع** — لا يُلمس أبداً.
  ///
  /// مُجرَّب حيّاً على CPE610 v2.0 بإذن المالك (١٠ نوفمبر): الجهاز ردّ `wholeTime: 80`، انطفأ بعد ~١٣ث، ورجع يجاوب على الشبكة
  /// بعد ~دقيقتين بمدّة تشغيلٍ مصفَّرة. وكصفحة الجهاز لا نفحص `configState.json` قبله: علم «تعديلات غير محفوظة» كان `true`
  /// قبل الإقلاع **وبقي `true` بعده** على ذلك الجهاز — لا يدلّ على شيءٍ يُبنى عليه تحذير.
  ///
  /// جلسة الكرت الحيّة إن كانت قائمة تُستعمل (لا دخول ثانٍ)، وتموت مع إقلاع الجهاز بلا أن تُحسب «طرداً».
  static Future<PharosRebootOutcome> reboot(String host, String user, String pass) => _serial(host, () async {
        final live = _active[host];
        final reuse = live != null && !live.lost;
        final s = reuse ? live : await loginConfigured(host, user, pass);
        if (s == null) {
          final why = _issues[host];
          return (sent: false, seconds: null, issue: why?.issue ?? PharosLoginIssue.unreachable, trace: why?.trace ?? 'login');
        }
        try {
          int? seconds;
          try {
            final r = await _send(s.base, 'GET', '/data/configReboot.json', cookie: s.cookie);
            final j = TplinkPharosParse.json(r.body);
            if (j != null && j['timeout'] == true && j['success'] == true && j['wholeTime'] == null && j['data'] == null) {
              // الجلسة انتهت بين الدخول والأمر (دخل غيرنا): لم يُنفَّذ.
              s._lost = true;
              return (sent: false, seconds: null, issue: PharosLoginIssue.busy, trace: 'reboot:${r.status} session-timeout');
            }
            if (j == null || j['success'] != true) {
              return (sent: false, seconds: null, issue: PharosLoginIssue.readFailed, trace: 'reboot:${r.status} len:${r.body.length}');
            }
            final data = j['data'];
            seconds = TplinkPharosParse.intOf(j['wholeTime']) ?? (data is Map ? TplinkPharosParse.intOf(data['wholeTime']) : null);
          } on _NoConnection catch (e) {
            return (sent: false, seconds: null, issue: PharosLoginIssue.unreachable, trace: 'reboot:${_errName(e)}');
          } catch (_) {
            // أُرسل الأمر وانقطع الاتّصال قبل الردّ: الجهاز بدأ يقلع غالباً — أُرسل، بلا مدّة.
          }
          // الجهاز يقلع: جلستنا تموت معه — ليست «طرداً» ولا مهلة عليها.
          s._lost = true;
          s._kickNoted = true;
          if (identical(_active[host], s)) _active.remove(host);
          return (sent: true, seconds: seconds, issue: null, trace: 'reboot:sent');
        } finally {
          if (!reuse && !s.lost) await logout(s);
        }
      });

  static Future<PharosSession?> _openLive(String host, String user, String pass) => _serial(host, () async {
        final cur = _active[host];
        if (cur != null && !cur.lost) {
          cur._refs++;
          return cur;
        }
        if (cur != null) _dropLost(cur);
        final s = await loginConfigured(host, user, pass);
        if (s == null) return null;
        s._refs = 1;
        _active[host] = s;
        return s;
      });

  static Future<void> _closeLive(PharosSession s) async {
    if (s.lost) {
      _dropLost(s);
      return;
    }
    if (--s._refs > 0) return;
    if (identical(_active[s.host], s)) _active.remove(s.host);
    await logout(s);
  }
}

typedef _Reply = ({int status, String body, String? cookie, String? server});

/// الاتّصال لم يُفتح أصلاً (لم يُرسل الطلب).
class _NoConnection implements Exception {
  const _NoConnection(this.cause);
  final Object cause;
}

/// ما ردّ به الجهاز على التعرّف (بلا دخول).
class PharosHello {
  const PharosHello({
    required this.base,
    required this.cookie,
    required this.status,
    required this.failedCount,
    required this.lockMinutes,
    required this.devInfo,
    required this.devVer,
    required this.mode,
    required this.firstLogin,
  });

  /// `http://host` أو `https://host` — المخطّط الذي جاوب.
  final String base;

  /// nonce الدخول (كوكي `COOKIE`).
  final String cookie;
  final int status;

  /// محاولات الدخول الغلط المتراكمة على الجهاز (من كلّ العملاء) — تُصفَّر بدخولٍ ناجح.
  final int failedCount;

  /// دقائق باقية على قفل الدخول (0: غير قافل).
  final int lockMinutes;

  /// الطراز («CPE610») ونسخته العتاديّة («2.0»).
  final String devInfo;
  final String devVer;

  /// وضع التشغيل كما يسمّيه الجهاز (`apClientRouter`، `client`، `ap`…).
  final String mode;
  final bool firstLogin;

  String get model => devVer.isEmpty ? devInfo : '$devInfo v$devVer';
}

/// جلسة دخولٍ قائمة على الجهاز.
class PharosSession {
  PharosSession._({required this.host, required this.base, required this.cookie, required this.model, required this.mode});
  final String host;
  final String base;
  final String cookie;
  final String model;
  final String mode;
  bool _lost = false;
  bool _kickNoted = false;
  int _refs = 0;
  String? _trace;

  /// الجلسة انتهت عند الجهاز (دخل غيرنا أو أُعيد تشغيله).
  bool get lost => _lost;
}

/// لماذا لم ندخل — ما يقوله الكرت للوكيل.
enum PharosLoginIssue {
  /// لا جواب (مهلة، اتّصالٌ مرفوض، ردٌّ غريب) — لا يُحفظ رفضاً، والفحص التالي يحاول.
  unreachable,

  /// الجهاز رفض اليوزر أو الباسورد — يُحفظ فلا يُعاد حتى يتغيّر الاعتماد.
  rejected,

  /// مستخدمٌ آخر داخل على صفحة الجهاز (أو طُردت جلستنا) — لا نطرده.
  busy,

  /// قافلٌ بعد عشر محاولاتٍ غلط — لا نرسل عليه.
  locked,

  /// عدّ محاولاتٍ غلط كثيرة (دون القفل) — لا نزيدها.
  tooManyFails,

  /// جهازٌ جديد لم يُضبط، أو يطلب تغيير كلمة السرّ من صفحته أوّلاً.
  needsSetup,

  /// دخلنا وما رجعت القراءات.
  readFailed,
}

typedef PharosLoginOutcome = ({PharosSession? session, PharosLoginIssue? issue, int? lockLeft, String trace});

/// نتيجة طلب إعادة التشغيل: [sent] أُرسل الأمر (و[seconds] مدّة الإقلاع كما يقولها الجهاز)؛ وإلّا [issue] لماذا لم يُرسل.
typedef PharosRebootOutcome = ({bool sent, int? seconds, PharosLoginIssue? issue, String trace});

/// قراءةٌ حيّة واحدة: ترافيك المشترك الآن (بت/ث) وما يتغيّر من حال الوصلة.
class PharosLive {
  const PharosLive({
    this.downBps,
    this.upBps,
    this.signalDbm,
    this.noiseFloorDbm,
    this.ccqPercent,
    this.txRateKbps,
    this.rxRateKbps,
    this.uptimeSeconds,
    this.lanPorts,
  });
  final int? downBps;
  final int? upBps;
  final int? signalDbm;
  final int? noiseFloorDbm;
  final int? ccqPercent;
  final int? txRateKbps;
  final int? rxRateKbps;
  final int? uptimeSeconds;
  final List<LanPort>? lanPorts;

  /// [old] بهذه القراءة الأحدث — ما لم يصل يبقى كما هو.
  UbiquitiStatus applyTo(UbiquitiStatus old) => old.withLive(
        signalDbm: signalDbm,
        noiseFloorDbm: noiseFloorDbm,
        ccqPercent: ccqPercent,
        txRateKbps: txRateKbps,
        rxRateKbps: rxRateKbps,
        uptimeSeconds: uptimeSeconds,
        lanPorts: lanPorts,
      );
}

/// جلسة الكرت الحيّة: دخولٌ واحد لعمر الكرت ثمّ قراءةٌ خفيفة كلّ نبضة (الترافيك والإشارة معاً)، وخروجٌ عند الإغلاق.
///
/// للجهاز جلسةٌ واحدة: ما دامت هذه قائمة يقرأ الفحص بها ([TplinkPharosService.readOnce])، ومن يدخل صفحة الجهاز من عنوانٍ
/// آخر يُسأل «أكمل؟» فإن أكمل طُردنا ⇒ [sample] تردّ null و[lost] صحيحة ⇒ نُغلق وننتظر، لا نطارده.
class PharosLiveSession {
  PharosLiveSession._(this._s);
  final PharosSession _s;
  bool _closed = false;
  int _misses = 0;

  static Future<PharosLiveSession?> open({required String ip, required String user, required String pass}) async {
    final s = await TplinkPharosService._openLive(ip.trim(), user, pass);
    return s == null ? null : PharosLiveSession._(s);
  }

  /// الجلسة انتهت عند الجهاز — أغلقها ولا تعد الدخول فوراً.
  bool get lost => _s.lost;

  /// تعثّراتٌ عابرة متتالية (طلبٌ لم يُجَب والجلسة قائمة).
  int get misses => _misses;

  Future<PharosLive?> sample() async {
    if (_closed || _s.lost) return null;
    final live = await TplinkPharosService.fetchLive(_s);
    _misses = live == null ? _misses + 1 : 0;
    return live;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await TplinkPharosService._closeLive(_s);
  }
}

/// تحليل ردود Pharos — نصٌّ ⇒ قيم (نقيّ، يُختبر بلا جهاز). الصيغ من CPE610 v2.0 الحيّ.
class TplinkPharosParse {
  TplinkPharosParse._();

  static Map<String, dynamic>? json(String body) {
    final t = body.trim();
    if (!t.startsWith('{')) return null;
    try {
      final j = jsonDecode(t);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  /// كوكي الجلسة/الـnonce من ترويسات `Set-Cookie` (`COOKIE=0000000006107906; PATH=/; MAXAGE=9999; VERSION=1`).
  static String? cookie(List<String>? setCookie) {
    for (final line in setCookie ?? const <String>[]) {
      final m = RegExp(r'(?:^|[;,\s])COOKIE=([^;,\s]+)', caseSensitive: false).firstMatch(line);
      if (m != null) return m.group(1);
    }
    return null;
  }

  static int? intOf(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static bool truthy(Object? v) => v == true || v == 1 || v == '1' || v == 'true';

  static String text(Object? v) => v == null ? '' : v.toString().trim();

  /// «N/A» والفارغ ليسا قيمة.
  static bool blank(String v) => v.isEmpty || v.toUpperCase() == 'N/A';

  /// ردّ التعرّف ⇒ [PharosHello]؛ null حين ليس واجهة Pharos (جهازٌ آخر، صفحة، تحويل).
  static PharosHello? hello(String body, {required String base, String? cookie}) {
    final j = json(body);
    if (j == null) return null;
    final dev = j['devInfo'];
    final status = intOf(j['status']);
    if (dev is! String || dev.trim().isEmpty || status == null) return null;
    return PharosHello(
      base: base,
      cookie: cookie ?? '',
      status: status,
      failedCount: intOf(j['failedCount']) ?? 0,
      lockMinutes: intOf(j['lockTime']) ?? 0,
      devInfo: dev.trim(),
      devVer: text(j['devVer']),
      mode: text(j['mode']),
      firstLogin: j['firstLogin'] == true,
    );
  }

  /// ردّ HTTP ليس تعرّفاً: نجرّب HTTPS فقط إن كان الخادم خادم TP-Link (ترويسته `TP-LINK HTTPD` على كلّ ردّ، حتى التحويل)
  /// — لا على كلّ جهازٍ يحوّل إلى HTTPS: أجهزة airOS 8 كلّها تفعل، وطلبٌ ثانٍ على كلٍّ منها يؤخّر قراءتها بلا فائدة.
  static bool worthHttps(String? server) => (server ?? '').toLowerCase().contains('tp-link');

  static String _md5Upper(String s) => md5.convert(utf8.encode(s)).toString().toUpperCase();

  /// كما تحسبها صفحة الجهاز: `MD5( MD5(pass)↑ + ":" + nonce )↑`.
  static String digest(String pass, String nonce) => _md5Upper('${_md5Upper(pass)}:$nonce');

  /// «-41 dBm» · «-83dBm» ⇒ ‎-41 / ‎-83. null لما ليس رقماً سالباً (0 ليست إشارة).
  static int? dbm(String v) {
    final m = RegExp(r'^\s*(-\d+(?:\.\d+)?)\s*dBm?\s*$', caseSensitive: false).firstMatch(v);
    final n = m == null ? null : double.tryParse(m.group(1)!);
    return n == null || n >= 0 ? null : n.round();
  }

  /// الإشارة المجمَّعة: الحقل الجاهز («-41 dBm») وإلّا مجموع قدرة السلاسل («-45/-43 dBm» ⇒ ‎-41) — كما يحسبها الجهاز
  /// (قِيس: ‎-45/-43 ⇒ ‎-41 و‎-46/-45 ⇒ ‎-42).
  static int? signal(String combined, String chains) {
    final ready = dbm(combined);
    if (ready != null) return ready;
    final m = RegExp(r'^\s*(-?\d+(?:\.\d+)?(?:\s*/\s*-?\d+(?:\.\d+)?)*)\s*dBm?\s*$', caseSensitive: false).firstMatch(chains);
    if (m == null) return null;
    var mw = 0.0;
    var n = 0;
    for (final part in m.group(1)!.split('/')) {
      final v = double.tryParse(part.trim());
      // سلسلةٌ بلا إشارة تُقرأ 0 أو أدنى من أرضيّة الضجيج — لا تدخل المجموع.
      if (v == null || v >= 0 || v < -110) continue;
      mw += math.pow(10, v / 10).toDouble();
      n++;
    }
    if (n == 0) return null;
    return (10 * math.log(mw) / math.ln10).round();
  }

  /// «78.0Mbps» ⇒ 78000 ك.ب/ث؛ null لغير الرقم.
  static int? kbps(String v) {
    final m = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*Mbps\s*$', caseSensitive: false).firstMatch(v);
    final n = m == null ? null : double.tryParse(m.group(1)!);
    return n == null ? null : (n * 1000).round();
  }

  /// «4 days 14:31:49» ⇒ ثوانٍ.
  static int? uptime(String v) {
    final m = RegExp(r'^\s*(?:(\d+)\s*days?\s*)?(\d{1,2}):(\d{2}):(\d{2})\s*$', caseSensitive: false).firstMatch(v);
    if (m == null) return null;
    return (int.tryParse(m.group(1) ?? '0') ?? 0) * 86400 +
        int.parse(m.group(2)!) * 3600 +
        int.parse(m.group(3)!) * 60 +
        int.parse(m.group(4)!);
  }

  /// «0.221km» ⇒ 221 متراً.
  static int? meters(String v) {
    final m = RegExp(r'^\s*(\d+(?:\.\d+)?)\s*km\s*$', caseSensitive: false).firstMatch(v);
    final n = m == null ? null : double.tryParse(m.group(1)!);
    return n == null ? null : (n * 1000).round();
  }

  /// «24-A4-3C-9C-FC-E1» ⇒ «24:A4:3C:9C:FC:E1»؛ null للفارغ و«N/A» والأصفار.
  static String? mac(String v) {
    final hex = v.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (hex.length != 12 || hex == '000000000000') return null;
    return [for (var i = 0; i < 12; i += 2) hex.substring(i, i + 2)].join(':');
  }

  /// «2.2.99 Build 20200715 Rel. 59670 (0000)» ⇒ «2.2.99 Build 20200715».
  static String firmware(String v) {
    if (blank(v)) return '';
    return RegExp(r'^(\S+(?:\s+Build\s+\d+)?)', caseSensitive: false).firstMatch(v)?.group(1) ?? v;
  }

  /// منفذ LAN: «100Mbps - FD» ⇒ ‎100Mbps-Full · «10Mbps - HD» ⇒ ‎10Mbps-Half · «Unplugged» ⇒ مفصول. null لما لا يُفهم
  /// («N/A»، فارغ) — «لا أعرف» ليست «مفصول».
  static LanPort? port(String name, String v) {
    if (blank(v)) return null;
    if (v.toLowerCase().contains('unplug')) return LanPort(name: name, speed: null, plugged: false);
    final m = RegExp(r'(\d+)\s*Mbps(?:\s*-\s*(FD|HD))?', caseSensitive: false).firstMatch(v);
    if (m == null) return null;
    final duplex = switch (m.group(2)?.toUpperCase()) { 'FD' => '-Full', 'HD' => '-Half', _ => '' };
    return LanPort(name: name, speed: '${m.group(1)}Mbps$duplex', plugged: true);
  }

  /// منافذ الجهاز: الأوّل دائماً، والثاني حين يكون موصولاً وحده — الطرازات بمنفذٍ واحد (CPE610، CPE510 v2/v3…) تردّ ثانياً
  /// «Unplugged» لا وجود له (صفحة الجهاز تخفيه بجدول طرازات)، وعرضه «مفصول» يرسل الفنّيّ لكيبلٍ غير موجود.
  static List<LanPort> ports(Map<String, dynamic> d) {
    final p0 = port('lan0', text(d['lanPort0']));
    final p1 = port('lan1', text(d['lanPort1']));
    return [
      if (p0 != null) p0,
      if (p1 != null && p1.plugged) p1,
    ];
  }

  static ({bool station, bool ap, String? bssid}) _link(Map<String, dynamic> d) {
    final bssid = mac(text(d['rootApBssid']));
    final stations = text(d['apConnectedStations']);
    // القراءة الحيّة بلا clientEnable/apEnable: BSSID الجذر يدلّ على المحطّة، وعدد المتّصلين على نقطة الوصول.
    final station = d.containsKey('clientEnable') ? truthy(d['clientEnable']) : bssid != null;
    final ap = d.containsKey('apEnable') ? truthy(d['apEnable']) : !blank(stations);
    return (station: station, ap: ap, bssid: bssid);
  }

  /// `info.json` ⇒ قراءة النانو الموحَّدة. null حين الشكل ليس صفحة المعلومات.
  ///
  /// ⚠️ لا أرقام كاذبة: محطّةٌ غير مرتبطة (لا BSSID) بلا إشارةٍ ولا جودةٍ ولا معدّل؛ ونقطة وصولٍ بلا «إشارة وصلة».
  static UbiquitiStatus? status(Map<String, dynamic> d, {required String base, String model = ''}) {
    if (!d.containsKey('deviceName') && !d.containsKey('rssiValue') && !d.containsKey('lanPort0')) return null;
    final l = _link(d);
    final linked = l.station && l.bssid != null;
    final hard = text(d['hardVersion']);
    String ssidOf(String k) => blank(text(d[k])) ? '' : text(d[k]);
    final ssid = l.station
        ? (ssidOf('rootApSsid').isNotEmpty ? ssidOf('rootApSsid') : ssidOf('clientSsid'))
        : ssidOf('apSsid');
    return UbiquitiStatus(
      hostname: blank(text(d['deviceName'])) ? '' : text(d['deviceName']),
      firmware: firmware(text(d['firmVersion'])),
      uptimeSeconds: uptime(text(d['sysRunTime'])),
      ssid: ssid,
      mode: l.station ? 'sta' : (l.ap ? 'ap' : ''),
      signalDbm: linked ? signal(text(d['rssiValueCombined']), text(d['rssiValue'])) : null,
      noiseFloorDbm: dbm(text(d['noiseValue'])),
      ccqPercent: linked ? _percent(d['transmitCcq']) : null,
      distanceMeters: meters(text(d['ackTimeout'])),
      txRateKbps: linked ? kbps(text(d['clientTxRate'])) : null,
      rxRateKbps: linked ? kbps(text(d['clientRxRate'])) : null,
      lanPorts: ports(d),
      peerMac: l.station ? l.bssid : null,
      peerCount: l.ap && !l.station ? intOf(d['apConnectedStations']) : null,
      baseUrl: base,
      vendor: 'tplink',
      model: blank(hard) ? model : hard,
    );
  }

  static int? _percent(Object? v) {
    final n = intOf(v);
    return n == null || n < 0 || n > 100 ? null : n;
  }

  static int? _bps(Object? list, String key) {
    if (list is! List || list.isEmpty || list.first is! Map) return null;
    final v = (list.first as Map)[key];
    // الجهاز يعدّها ك.ب/ث (صفحته تكتب Kbps).
    return v is num && v >= 0 ? (v * 1000).round() : null;
  }

  /// `progressBar.json` ⇒ القراءة الحيّة. تحميل المشترك = ما يستقبله الراديو من البرج (محطّة)، وما يرسله لعملائه (نقطة وصول).
  static PharosLive live(Map<String, dynamic> d) {
    final l = _link(d);
    final linked = l.station && l.bssid != null;
    final rx = _bps(d['wireless'], 'deviceRx');
    final tx = _bps(d['wireless'], 'deviceTx');
    final asAp = l.ap && !l.station;
    final lan = ports(d);
    return PharosLive(
      downBps: asAp ? tx : rx,
      upBps: asAp ? rx : tx,
      signalDbm: linked ? signal(text(d['rssiValueCombined']), text(d['rssiValue'])) : null,
      noiseFloorDbm: dbm(text(d['noiseValue'])),
      ccqPercent: linked ? _percent(d['transmitCcq']) : null,
      txRateKbps: linked ? kbps(text(d['clientTxRate'])) : null,
      rxRateKbps: linked ? kbps(text(d['clientRxRate'])) : null,
      uptimeSeconds: uptime(text(d['sysRunTime'])),
      lanPorts: lan.isEmpty ? null : lan,
    );
  }
}
