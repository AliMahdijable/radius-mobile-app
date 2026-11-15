// TP-Link — راوترات واجهة «$.act» القديمة **بلا تعمية** وبكوكي Authorization خام («rawbasic»):
// TL-WR840N v6 (فيرموير 0.9.1 4.16 Build 180614) وTL-WR845N وأشباههما.
//
// مقيسةٌ حيّاً ١٥ نوفمبر على WR840N v6 (قراءةٌ فقط، من سكربت صفحة الجهاز نفسها ثمّ بطلباتٍ حقيقيّة):
//  • `GET /` بلا كوكي ⇒ صفحة الدخول وفيها `authTimes` (محاولات غلط متتالية يعدّها الجهاز لكلّ من يدخل) و`forbidTime`
//    (ثوانٍ مضت من القفل) و`forbidAdminLogin` و`modelName`. **العاشرة الغلط تقفل الراوتر ٧٢٠٠ ث**، ومديرٌ واحد في وقتٍ واحد
//    (`forbidAdminLogin=1` لمن يدخل ومديرٌ آخر داخل).
//  • الدخول كما تفعله الصفحة: كوكي `Authorization=Basic base64(user:pass)` بكلمة سرٍّ **خام** ثمّ `GET /` ⇒ صفحة الإطارات، أو صفحة
//    الدخول ثانيةً (`authTimes` زاد = مرفوض).
//  • القراءة `POST /cgi?1&5&5&5&6` نصّاً خاماً بكائنات Archer C50 نفسها ([TplinkCgiService.readActions])، والكوكي في كلّ طلب —
//    بلاه `[error]71111`. المصادقة لكلّ طلبٍ لا جلسة: الخروج لا يُسقط متصفّحاً مفتوحاً من العنوان نفسه.
//  • الخروج `POST /cgi?8` `[/cgi/logout…]` ⇒ `[cgi]0` — يحرّر خانة المدير الواحد لمن يدخل بعدنا.
//
// ⛔ قراءةٌ وحدها: لا ACT_SET (2) ولا ACT_OP (7: ACT_REBOOT / ACT_FACTORY_RESET) من هذا الملفّ أبداً.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../models/device_health.dart';
import 'tplink_cgi_service.dart';
import 'tplink_classic_service.dart';

enum CgiPlainIssue { rejected, locked, tooManyFails, busy, unreachable, readFailed }

/// ما تقوله صفحة الدخول قبل أيّ إرسال.
class CgiPlainHello {
  const CgiPlainHello({required this.authTimes, required this.forbidTime, required this.adminBusy, required this.model});

  /// محاولات الدخول الغلط المتتالية كما يعدّها الجهاز (مشتركةٌ بين كلّ من يدخل).
  final int authTimes;

  /// ثوانٍ مضت من القفل (له معنى حين [locked]).
  final int forbidTime;

  /// مديرٌ آخر داخل الآن — الجهاز يرفض الثاني.
  final bool adminBusy;

  /// «TL-WR840N».
  final String model;

  static const lockAfter = 10;
  static const lockSeconds = 7200;

  bool get locked => authTimes >= lockAfter;
  int get lockLeft => (lockSeconds - forbidTime).clamp(0, lockSeconds);

  /// صفحة دخول هذه العائلة ⇒ متغيّراتها؛ غيرها ⇒ null.
  static CgiPlainHello? parse(String html) {
    if (!TplinkClassicService.isRawBasicLogin(html)) return null;
    final v = CgiParse.vars(html);
    int n(String k) => int.tryParse((v[k] ?? '').trim()) ?? 0;
    return CgiPlainHello(
      authTimes: n('authTimes'),
      forbidTime: n('forbidTime'),
      adminBusy: n('forbidAdminLogin') == 1,
      model: (v['modelName'] ?? '').trim(),
    );
  }
}

class TplinkCgiPlainService {
  TplinkCgiPlainService._();

  /// اسم المورّد في اللقطة وذاكرة النوع (المفتاح الذي حفظه 184 حين كان تعرّفاً بلا قراءة).
  static const vendor = 'tp845';

  static const _connect = Duration(seconds: 4);
  static const _read = Duration(seconds: 8);
  static const _helloFresh = Duration(seconds: 20);

  /// لا إرسال تلقائيّ من هذا العدد من المحاولات الغلط على الجهاز: العدّاد مشترك، والعاشرة تقفله ساعتين على صاحبه.
  static const autoStopAt = 5;

  /// بعد «حفظ وفحص الجهاز» (المدير صحّح الاعتماد بيده) نسمح حتى هذا الحدّ — ولا نبلغ العاشرة أبداً.
  static const manualStopAt = 8;

  /// مديرٌ آخر داخل الراوتر ⇒ لا نطرقه ثانيةً قبل هذه المدّة.
  static const busyCooldown = Duration(seconds: 60);

  @visibleForTesting
  static String Function(String host) baseFor = (h) => 'http://$h';

  static final _issues = <String, ({CgiPlainIssue issue, String trace, int? lockLeft, DateTime at})>{};
  static final _rejected = <String, Set<String>>{};
  static final _hello = <String, ({CgiPlainHello hello, DateTime at})>{};
  static final _busyUntil = <String, DateTime>{};
  static final _manual = <String>{};
  static final _locks = <String, Future<void>>{};

  /// لماذا فشلت آخر قراءة — [lockLeft] ما بقي من قفل الجهاز الآن (ثوانٍ).
  static ({CgiPlainIssue issue, String trace, int? lockLeft})? lastIssue(String host) {
    final i = _issues[host.trim()];
    if (i == null) return null;
    final left = i.lockLeft == null ? null : i.lockLeft! - DateTime.now().difference(i.at).inSeconds;
    return (issue: i.issue, trace: i.trace, lockLeft: left == null || left <= 0 ? null : left);
  }

  /// ينسى ما حُفظ عن العنوان (المرفوض، المشغول، آخر سبب). [manual]: «حفظ وفحص الجهاز» — القراءة التالية بحدّ [manualStopAt].
  static void forget(String host, {bool manual = false}) {
    final h = host.trim();
    _issues.remove(h);
    _rejected.remove(h);
    _hello.remove(h);
    _busyUntil.remove(h);
    if (manual) {
      _manual.add(h);
    } else {
      _manual.remove(h);
    }
  }

  static void reset() {
    _issues.clear();
    _rejected.clear();
    _hello.clear();
    _busyUntil.clear();
    _manual.clear();
  }

  static void _note(String h, CgiPlainIssue issue, String trace, {int? lockLeft}) =>
      _issues[h] = (issue: issue, trace: trace, lockLeft: lockLeft, at: DateTime.now());

  /// طلباتُ العنوان واحداً بعد واحد داخل التطبيق (موجة القائمة والكرت المفتوح معاً): دخولٌ ← قراءة ← خروج بلا تداخل.
  static Future<T> _serial<T>(String host, Future<T> Function() fn) {
    final prev = _locks[host] ?? Future<void>.value();
    final done = Completer<void>();
    _locks[host] = done.future;
    return prev.then((_) => fn()).whenComplete(() {
      done.complete();
      if (identical(_locks[host], done.future)) _locks.remove(host);
    });
  }

  /// طلبٌ واحد ⇒ (الحالة، النصّ). شبكةٌ/مهلة ⇒ null. لا إعادة أبداً (طلبٌ أُرسل ولم يُجَب لا يُكرَّر).
  static Future<({int status, String body})?> _send(
    String host,
    String method,
    String path, {
    String? cookie,
    String? body,
    Duration? timeout,
  }) async {
    final base = baseFor(host);
    final client = HttpClient()..connectionTimeout = _connect;
    try {
      final req = await client.openUrl(method, Uri.parse('$base$path')).timeout(_connect);
      req.followRedirects = false;
      // أسماء الترويسات كما يرسلها المتصفّح (خادم الجهاز صغير).
      if (cookie != null) req.headers.set('Cookie', cookie, preserveHeaderCase: true);
      // بلا Referer من الجهاز نفسه يرفض الطلب.
      req.headers.set('Referer', '$base/', preserveHeaderCase: true);
      if (body != null) {
        final bytes = utf8.encode(body);
        req.headers.set('Content-Type', 'text/plain', preserveHeaderCase: true);
        // طولٌ صريح: خادم الجهاز لا يقرأ chunked.
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(timeout ?? _read);
      final bytes = await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(timeout ?? _read);
      return (status: res.statusCode, body: utf8.decode(bytes, allowMalformed: true));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// أهو من هذه العائلة؟ `GET /` **بلا اعتماد** — لا يُحسب محاولة. يحفظ ما قالته الصفحة لقراءةٍ تليه خلال ثوانٍ.
  static Future<bool> detect(String host) async => (await _helloNow(host.trim())) != null;

  static Future<CgiPlainHello?> _helloNow(String h) async {
    final r = await _send(h, 'GET', '/', timeout: const Duration(seconds: 5));
    final hello = (r == null || r.status != 200) ? null : CgiPlainHello.parse(r.body);
    if (hello == null) {
      _hello.remove(h);
      return null;
    }
    _hello[h] = (hello: hello, at: DateTime.now());
    return hello;
  }

  static String _cookie(String user, String pass) => 'Authorization=Basic ${base64.encode(utf8.encode('$user:$pass'))}';

  /// قراءةٌ واحدة: حالة الصفحة (بلا اعتماد) ← دخول ← قراءة ← خروج. null ⇒ [lastIssue].
  ///
  /// لا يُرسَل الاعتماد حين: الزوج رُفض من قبل (حتى [forget])، الجهاز مقفل، عدّاد الغلط بلغ [autoStopAt]
  /// ([manualStopAt] بعد «حفظ وفحص»)، أو مديرٌ آخر داخل منذ أقلّ من [busyCooldown].
  static Future<UbiquitiStatus?> readOnce(String host, String user, String pass) {
    final h = host.trim();
    return _serial(h, () => _readOnce(h, user, pass));
  }

  static Future<UbiquitiStatus?> _readOnce(String h, String user, String pass) async {
    final cookie = _cookie(user, pass);
    if (_rejected[h]?.contains(cookie) ?? false) {
      _note(h, CgiPlainIssue.rejected, 'remembered');
      return null;
    }
    final until = _busyUntil[h];
    if (until != null && DateTime.now().isBefore(until)) {
      _note(h, CgiPlainIssue.busy, 'cooldown');
      return null;
    }
    final manual = _manual.remove(h);
    final seen = _hello[h];
    final hello = (seen != null && DateTime.now().difference(seen.at) < _helloFresh) ? seen.hello : await _helloNow(h);
    if (hello == null) {
      _note(h, CgiPlainIssue.unreachable, 'hello no-reply');
      return null;
    }
    if (hello.locked) {
      _note(h, CgiPlainIssue.locked, 'locked authTimes=${hello.authTimes}', lockLeft: hello.lockLeft);
      return null;
    }
    if (hello.authTimes >= (manual ? manualStopAt : autoStopAt)) {
      _note(h, CgiPlainIssue.tooManyFails, 'authTimes=${hello.authTimes}');
      return null;
    }
    // ما بعد هذا قد يغيّر العدّاد ⇒ القراءة التالية تسأل الصفحة من جديد.
    _hello.remove(h);

    final login = await _send(h, 'GET', '/', cookie: cookie);
    if (login == null) {
      _note(h, CgiPlainIssue.unreachable, 'login no-reply');
      return null;
    }
    final again = CgiPlainHello.parse(login.body);
    if (again != null) {
      // صفحة الدخول ثانيةً: لم ندخل — فلا خروج يُرسل.
      if (again.adminBusy) {
        _busyUntil[h] = DateTime.now().add(busyCooldown);
        _note(h, CgiPlainIssue.busy, 'another admin');
      } else if (again.locked) {
        _note(h, CgiPlainIssue.locked, 'locked authTimes=${again.authTimes}', lockLeft: again.lockLeft);
      } else if (again.authTimes > hello.authTimes) {
        (_rejected[h] ??= <String>{}).add(cookie);
        _note(h, CgiPlainIssue.rejected, 'authTimes ${hello.authTimes}>${again.authTimes}');
      } else {
        _note(h, CgiPlainIssue.readFailed, 'login page again');
      }
      return null;
    }
    if (login.status != 200) {
      _note(h, CgiPlainIssue.readFailed, 'login http ${login.status}');
      return null;
    }

    try {
      final plain = TplinkCgiService.readActions();
      final cut = plain.indexOf('\r\n');
      final r = await _send(h, 'POST', '/cgi?${plain.substring(0, cut)}', cookie: cookie, body: plain.substring(cut + 2));
      if (r == null) {
        _note(h, CgiPlainIssue.unreachable, 'read no-reply');
        return null;
      }
      final err = CgiParse.errorCode(r.body);
      final status = (r.status == 200 && err == 0) ? CgiParse.status(CgiParse.objects(r.body), baseUrl: baseFor(h), vendor: vendor) : null;
      if (status == null) {
        _note(h, CgiPlainIssue.readFailed, 'read http ${r.status} error ${err ?? '-'}');
        return null;
      }
      _issues.remove(h);
      return status;
    } finally {
      // يحرّر خانة المدير الواحد — نتيجته لا تغيّر القراءة.
      await _send(h, 'POST', '/cgi?8', cookie: cookie, body: '[/cgi/logout#0,0,0,0,0,0#0,0,0,0,0,0]0,0\r\n', timeout: const Duration(seconds: 4));
    }
  }
}
