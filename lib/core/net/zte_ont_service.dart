import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../../models/device_health.dart';

/// جهاز المشترك الضوئيّ ZTE (شريحة ZXIC، واجهة `.gch`) — طلب المالك ٢٥ أكتوبر: «عدنا نوع اجهزه جديد… نريد هم نعرض
/// المعلومات مال جهاز الضوئي للمشتركين وكذلك الترفك».
///
/// مستكشَفٌ حيّاً على MH80 (EPON، XPONV4.2.2M16) للقراءة فقط:
/// - التعرّف: ترويسة `Server: Mini web server 1.0 ZTE corp 2005.` أو صفحة دخولٍ فيها `fLogin` و`Frm_Logintoken`.
/// - الدخول: نموذجٌ عاديّ إلى `/` (frashnum · action=login · Frm_Logintoken · username · Password) ⇒ 302 إلى `/start.ghtml`
///   وكوكي الجلسة. ثلاث محاولاتٍ خاطئة تقفل الواجهة دقيقة ⇒ الاعتمادات المرفوضة لا تُعاد ([loginConfigured]).
/// - الصفحات `getpage.gch?pid=1002&nextpage=<x>.gch` (~١٣٠–١٤٥ ك.ب لكلٍّ: القالب كاملاً معها، ~١ث).
/// - الخروج: POST `/` بـ`logout=1` — واجهةٌ قد ترفض دخولاً ثانياً وجلسةٌ مفتوحة، فالفحص يخرج بعد القراءة.
class ZteOntService {
  ZteOntService._();

  /// اعتماداتٌ رفضها جهازٌ (عنوان ⇒ يوزر+باسورد): لا تُعاد عليه حتى تتغيّر — كلّ رفضٍ يقرّب قفل الواجهة (ثلاثٌ ⇒ دقيقة).
  static final _rejected = <String, String>{};

  /// اعتماداتٌ دخلت على هذا العنوان مرّةً: رفضها بعدها ليس غلطاً بها بل جلسةٌ أخرى مفتوحة (جلسة الترافيك، أو صفحة الجهاز
  /// بمتصفّح) — فلا تُحفظ مرفوضةً، وإلّا قفلنا الوكيل عن جهازه باعتماداتٍ صحيحة.
  static final _good = <String, String>{};

  /// «مشغول» ⇒ لا محاولة قبل هذا الوقت: جلسة الترافيك تعيد الدخول كلّ ١٢ ثانية حين تُطرد، وكلّ رفضٍ قد يُحسب على قفل
  /// الجهاز — فمرّةٌ بالدقيقة على الأكثر.
  static final _busyUntil = <String, DateTime>{};
  static const busyCooldown = Duration(seconds: 60);

  /// آخر سبب فشلٍ لكلّ عنوان — يُعرض للوكيل بدل «لم يُتمكّن من الوصول» العامّة.
  static final _issues = <String, ({ZteLoginIssue issue, int? lockLeft, String trace})>{};

  /// آخر صفحةٍ تعذّرت لكلّ جهاز — أثرٌ مختصر بلا محتوى للتشخيص.
  static final _pageTrace = <String, String>{};

  static Dio _dio(String base) {
    final dio = Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (_) => true,
      followRedirects: false,
      responseType: ResponseType.plain,
      headers: {'Accept': 'text/html,application/xhtml+xml,*/*'},
    ));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final c = HttpClient();
      c.badCertificateCallback = (_, __, ___) => true;
      return c;
    };
    return dio;
  }

  /// هل في [host] واجهة ZTE هذه؟ صفحةٌ أولى بلا دخول (~٠٫٥ث) — لا محاولة دخولٍ على جهازٍ آخر أبداً.
  static Future<bool> detect(String host) async {
    try {
      final res = await _dio('http://$host').get<String>('/');
      return ZteOntParse.isZte(res.headers.value('server'), res.data ?? '');
    } catch (_) {
      return false;
    }
  }

  /// دخولٌ بـ[user]/[pass]. null: ليست واجهة ZTE، أو رُفضت الاعتمادات، أو تعذّر الاتّصال — السبب في [attempt].
  static Future<ZteOntSession?> login(String host, String user, String pass) async => (await attempt(host, user, pass)).session;

  /// محاولة دخولٍ واحدة بسببها إن فشلت.
  ///
  /// 🐛 ٢٧ أكتوبر (المالك على MH80: «خليت يوزر وباسورد وميجلب شي»): كان كلّ فشلٍ — حتى مهلةٌ أو اتّصالٌ مقطوع — يُحفظ
  /// «اعتماداتٍ مرفوضة» فلا تُعاد أبداً في الجلسة، والكرت يقول «لم يُتمكّن من الوصول» أيّاً كان السبب. الآن: الرفض وحده
  /// يُحفظ، والقفل يُقرأ من الصفحة فلا نرسل عليه، والدخول الناجح لا يشترط كوكي (جلسةٌ بالعنوان على بعض البرامج).
  static Future<ZteLoginOutcome> attempt(String host, String user, String pass) async {
    final base = 'http://$host';
    final dio = _dio(base);
    final Response<String> first;
    try {
      first = await dio.get<String>('/');
    } catch (e) {
      return (session: null, issue: ZteLoginIssue.unreachable, lockLeft: null, trace: 'get:${_errName(e)}');
    }
    final page = first.data ?? '';
    if (!ZteOntParse.isZte(first.headers.value('server'), page)) {
      return (session: null, issue: ZteLoginIssue.notZte, lockLeft: null, trace: 'get:${first.statusCode} notZte');
    }
    // قافلٌ بعد ثلاث محاولاتٍ خاطئة ⇒ لا نرسل: كلّ محاولةٍ عليه تُحسب.
    final lock = ZteOntParse.lockLeft(page);
    if (lock != null) return (session: null, issue: ZteLoginIssue.locked, lockLeft: lock, trace: 'get:locked $lock');
    final token = ZteOntParse.loginToken(page);
    final jar = <String, String>{}..addAll(_cookies(first));
    final Response<String> res;
    try {
      res = await dio.post<String>(
        '/',
        data: 'frashnum=&action=login&Frm_Logintoken=${Uri.encodeQueryComponent(token)}'
            '&username=${Uri.encodeQueryComponent(user)}&Password=${Uri.encodeQueryComponent(pass)}',
        options: Options(headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': '$base/',
          if (jar.isNotEmpty) 'Cookie': _cookieHeader(jar),
        }),
      );
    } catch (e) {
      return (session: null, issue: ZteLoginIssue.unreachable, lockLeft: null, trace: 'post:${_errName(e)}');
    }
    jar.addAll(_cookies(res));
    final code = res.statusCode ?? 0;
    final location = res.headers.value('location') ?? '';
    final body = res.data ?? '';
    final trace = 'tok:${token.isEmpty ? '-' : 'ok'} post:$code'
        ' loc:${location.isEmpty ? '-' : Uri.tryParse(location)?.path ?? '?'} ck:${jar.length} len:${body.length}';
    final redirect = code == 302 || code == 303;
    if (redirect && location.contains('start.ghtml')) {
      return (session: ZteOntSession(baseUrl: base, cookie: _cookieHeader(jar)), issue: null, lockLeft: null, trace: trace);
    }
    // صفحة الدخول عادت (أو تحويلٌ إليها) ⇒ رُفض؛ وإن عادت قافلةً فهو القفل.
    final relogin = ZteOntParse.isLoginPage(body) || (redirect && (Uri.tryParse(location)?.path ?? '') == '/');
    if (relogin) {
      final l = ZteOntParse.lockLeft(body);
      return (session: null, issue: l == null ? ZteLoginIssue.rejected : ZteLoginIssue.locked, lockLeft: l, trace: trace);
    }
    return (session: null, issue: ZteLoginIssue.unreachable, lockLeft: null, trace: trace);
  }

  static String _errName(Object e) => e is DioException ? e.type.name : e.runtimeType.toString();

  /// اعتماداتٌ جديدة ضُبطت لهذا العنوان، أو طلب الوكيل إعادة المحاولة: الرفض السابق يُنسى.
  static void forget(String host) {
    _rejected.remove(host);
    _busyUntil.remove(host);
    _scanMissAt.remove('http://$host');
  }

  /// آخر سبب فشلٍ على [host] (null: آخر دخولٍ نجح أو لا محاولة).
  static ({ZteLoginIssue issue, int? lockLeft, String trace})? lastIssue(String host) => _issues[host];

  /// آخر صفحةٍ تعذّرت على [s] — أثرٌ مختصر (حالة وطول) للتشخيص.
  static String? lastPageTrace(ZteOntSession s) => _pageTrace[s.baseUrl];

  /// دخولٌ بالاعتمادات التي ضبطها الوكيل وحدها (المشترك ثمّ افتراضات المدير) — لا تجربة كلمات مرورٍ من عندنا. اعتماداتٌ
  /// رُفضت على هذا العنوان لا تُعاد حتى تتغيّر (أو يطلب الوكيل إعادتها: [forget]).
  static Future<ZteOntSession?> loginConfigured(String host, String user, String pass) async {
    final key = '$user\u0000$pass';
    if (user.isEmpty) {
      _issues[host] = (issue: ZteLoginIssue.rejected, lockLeft: null, trace: 'no-user');
      return null;
    }
    if (_rejected[host] == key) {
      _issues[host] = (issue: ZteLoginIssue.rejected, lockLeft: null, trace: 'remembered');
      return null;
    }
    final until = _busyUntil[host];
    if (until != null && DateTime.now().isBefore(until) && _good[host] == key) {
      _issues[host] = (issue: ZteLoginIssue.busy, lockLeft: null, trace: 'cooldown');
      return null;
    }
    final r = await attempt(host, user, pass);
    final s = r.session;
    if (s != null) {
      _rejected.remove(host);
      _busyUntil.remove(host);
      _issues.remove(host);
      _good[host] = key;
      return s;
    }
    var issue = r.issue ?? ZteLoginIssue.unreachable;
    if (issue == ZteLoginIssue.rejected) {
      if (_good[host] == key) {
        issue = ZteLoginIssue.busy;
        _busyUntil[host] = DateTime.now().add(busyCooldown);
      } else {
        _rejected[host] = key;
      }
    }
    _issues[host] = (issue: issue, lockLeft: r.lockLeft, trace: r.trace);
    return null;
  }

  /// صفحة حالة. null: الجلسة انتهت (صفحة الدخول عادت) أو تعذّر الطلب.
  static Future<String?> page(ZteOntSession s, String name) async {
    try {
      final res = await _dio(s.baseUrl).get<String>(
        '/getpage.gch',
        queryParameters: {'pid': '1002', 'nextpage': name},
        options: Options(headers: {
          if (s.cookie.isNotEmpty) 'Cookie': s.cookie,
          'Referer': '${s.baseUrl}/start.ghtml',
        }),
      );
      final html = res.data ?? '';
      final login = ZteOntParse.isLoginPage(html);
      if (res.statusCode != 200 || login) {
        _pageTrace[s.baseUrl] = 'page:${res.statusCode} login:${login ? 1 : 0} len:${html.length}';
        return null;
      }
      return html;
    } catch (e) {
      _pageTrace[s.baseUrl] = 'page:${_errName(e)}';
      return null;
    }
  }

  /// قراءة الضوء — أسماء صفحة الضوء المعروفة بالترتيب (MH80 = EPON)، ثمّ ما تسمّيه قائمة الجهاز نفسه. الطراز من عنوان الصفحة.
  ///
  /// 🐛 ٢٧ أكتوبر (D401 عند المالك: «دخلنا للجهاز بس ما قرينا الضوء»): كان أوّل اسمٍ غائب يوقف البحث فلا يُجرَّب
  /// الباقي. الآن صفحةٌ لا تُجاب ⇒ التالية، وصفحة الدخول (الجلسة انتهت) وحدها توقف. ما جُرِّب يبقى أثراً مختصراً للتشخيص
  /// (الحالة والطول وشكل قيمة الضوء — بلا قيمة).
  ///
  /// 🐛 وبعده (أثر D401: `epon:200/- gpon:200/- pon:200/-`): الأسماء الثلاثة تُجاب ولا ذكر للضوء فيها — صفحته باسمٍ آخر.
  /// فأوّلاً `start.ghtml` كما يفتحها المتصفّح بعد الدخول، ثمّ صفحات الضوء المحتملة من أسماء الصفحات التي يذكرها الجهاز نفسه
  /// (صفحات حالةٍ فيها pon/opt/power — [ZteOntParse.opticalCandidates]، ثلاثٌ على الأكثر). وما لم يُقرأ يُعرف أهو صفحةٌ
  /// لم ترجع أم صيغةٌ لا نعرفها ([lastReadUnknown]).
  ///
  /// 🐛 ثمّ (أثر D401 الثاني: صفحة EPON ٩٦ ك.ب بلا ضوء، والمرشّحتان صفحتا خطأٍ صغيرتان، و٤٩ صفحةً في قائمته): بعد
  /// المرشّحة تُجرَّب صفحات الحالة الأخرى في قائمته (قراءةٌ فقط — [ZteOntParse.statusPages]) حتى ثمانٍ، والتي يوجد فيها الضوء
  /// تُحفظ للجهاز فتبدأ بها القراءة التالية. والأثر يحمل أسماء صفحاته كلّها (`p=`) — أسماءٌ بلا قيم.
  static Future<OntOpticalInfo?> fetchOptical(ZteOntSession s) async {
    _pageTrace.remove(s.baseUrl);
    _pageInfo.remove(s.baseUrl);
    _unknownFormat.remove(s.baseUrl);
    final tried = <String>[];
    final menu = <String>{};
    final names = <String>{};
    var title = '';
    var answered = false;
    var richest = ''; // أطول صفحةٍ أجابت — فيها الضوء غالباً (D401: صفحة EPON ٩٦ ك.ب وحدها، والباقي صفحات خطأ).
    final missAt = _scanMissAt[s.baseUrl];
    final scan = missAt == null || DateTime.now().difference(missAt) >= scanQuiet;
    void finish() {
      if (!scan) tried.add('scan:later');
      _pageTrace[s.baseUrl] = tried.join(' ');
      final c = ZteOntParse.opticalCandidates(menu);
      final hints = ZteOntParse.opticalHints(richest);
      // صفحات الحالة فقط (لا كلّ ٤٩ صفحة): هي ما قد يحمل الضوء، فالأثر يبقى قصيراً.
      final statusList = {..._opticalPages, ...ZteOntParse.statusPages(menu)}.map(ZteOntParse.stem).toList()..sort();
      _pageInfo[s.baseUrl] = [
        't=${title.isEmpty ? '-' : title}',
        'm=${menu.length}',
        if (hints.isNotEmpty) 'g=${hints.join(',')}',
        if (c.isNotEmpty) 'c=${c.take(6).map(ZteOntParse.stem).join(',')}',
        if (names.isNotEmpty) 'n=${names.take(8).join(',')}',
        if (statusList.isNotEmpty) 's=${statusList.join(',')}',
      ].join(' ');
      if (answered) _unknownFormat.add(s.baseUrl);
      if (answered && scan) _scanMissAt[s.baseUrl] = DateTime.now();
    }

    final st = await _getRaw(s, '/start.ghtml', referer: '${s.baseUrl}/');
    tried.add('st:${st.code}${st.login ? 'L' : ''}${st.html == null ? '' : '/${ZteOntParse.kb(st.html!)}'}');
    if (st.login) {
      finish();
      return null;
    }
    if (st.html != null) menu.addAll(ZteOntParse.pageNames(st.html!));
    final remembered = _opticalPageOf[s.baseUrl];
    final queue = <String>[if (remembered != null) remembered, ..._opticalPages.where((p) => p != remembered)];
    final budget = queue.length + _maxExtraPages;
    for (var i = 0; i < queue.length; i++) {
      final name = queue[i];
      var r = await _pageRaw(s, name);
      // صفحةٌ معروفةٌ رجعت 200 صغيرةً جدّاً (القالب الكامل ~٩٦ ك.ب على D401): خطأٌ عابر، الجلسة لم تُقبل بعد — إعادةٌ
      // واحدة قبل الحكم (أوّل صفحةٍ وحدها، لئلّا نضاعف على صفحاتٍ صغيرةٍ أصلاً).
      if (i == 0 && r.html != null && !r.login && r.html!.length < _tinyPageBytes && ZteOntParse.optical(r.html!) == null) {
        final retry = await _pageRaw(s, name);
        if (retry.html != null && retry.html!.length >= r.html!.length) r = retry;
        tried.add('retry:${ZteOntParse.kb(retry.html ?? '')}');
      }
      final html = r.html;
      final pageTitle = html == null ? '' : ZteOntParse.model(html);
      final otherTitle = pageTitle.isNotEmpty && title.isNotEmpty && pageTitle != title;
      tried.add('${ZteOntParse.shortPage(name)}:${r.code}${r.login ? 'L' : ''}'
          '${html == null ? '' : '/${ZteOntParse.rxForm(html)}/${ZteOntParse.kb(html)}'}'
          '${otherTitle ? '/t:${ZteOntParse.traceWord(pageTitle)}' : ''}');
      if (r.login) break;
      if (html == null) continue;
      answered = true;
      final o = ZteOntParse.optical(html);
      if (o != null) {
        _opticalPageOf[s.baseUrl] = name;
        _scanMissAt.remove(s.baseUrl);
        return o;
      }
      if (title.isEmpty) title = pageTitle;
      if (html.length > richest.length) richest = html;
      menu.addAll(ZteOntParse.pageNames(html));
      names.addAll(ZteOntParse.powerNames(html));
      // ما بقي بالترتيب: الأسماء المعروفة، ثمّ المرشّحة للضوء، ثمّ صفحات الحالة — بلا تكرارٍ وضمن الميزانيّة.
      final done = queue.sublist(0, i + 1).toSet();
      final rest = queue.sublist(i + 1);
      final next = <String>{
        ...rest.where(_opticalPages.contains),
        ...ZteOntParse.opticalCandidates(menu),
        ...rest,
        if (scan) ...ZteOntParse.statusPages(menu),
      }.where((p) => !done.contains(p)).take(budget - done.length).toList();
      queue
        ..removeRange(i + 1, queue.length)
        ..addAll(next);
    }
    finish();
    return null;
  }

  /// أسماء صفحة الضوء المعروفة بالترتيب.
  static const _opticalPages = ['epon_status_link_info_t.gch', 'gpon_status_link_info_t.gch', 'pon_status_link_info_t.gch'];

  /// صفحاتٌ إضافيّة من قائمة الجهاز على الأكثر (~٠٫٦–١ث لكلٍّ) — والبحث يقف عند أوّل صفحةٍ فيها الضوء.
  static const _maxExtraPages = 8;

  /// صفحةٌ أصغر من هذا (200) = خطأٌ عابر لا صفحة حالة (القالب الكامل عشرات الكيلوبايت) ⇒ إعادةٌ واحدة.
  static const _tinyPageBytes = 4096;

  /// صفحة الضوء التي وُجدت لكلّ جهازٍ في هذه الجلسة — القراءة التالية تبدأ بها بلا بحث.
  static final _opticalPageOf = <String, String>{};

  /// بحثٌ في صفحات الحالة لم يجد الضوء ⇒ لا يُعاد قبل [scanQuiet] (الفحص يتكرّر كلّ دقيقتين والصفحات ثمانٍ)، إلّا بـ«حفظ
  /// وفحص» ([forget]).
  static final _scanMissAt = <String, DateTime>{};
  static const scanQuiet = Duration(minutes: 30);

  /// ما عرفناه عن صفحات آخر قراءةٍ لم تنجح: العنوان وعدد الصفحات التي يذكرها الجهاز والمرشّحة للضوء وأسماء متغيّراتٍ
  /// تشبه الضوء — أسماءٌ بلا قيم.
  static final _pageInfo = <String, String>{};

  /// أجهزةٌ أجابت صفحاتها ولم نجد فيها ضوءاً بصيغةٍ نعرفها (لا صفحةٌ لم ترجع).
  static final _unknownFormat = <String>{};

  static String? lastPageInfo(ZteOntSession s) => _pageInfo[s.baseUrl];

  /// آخر قراءةٍ على [s] أجابت صفحاتها ولم يُعرف الضوء فيها — طرازٌ بصيغةٍ جديدة، لا صفحةٌ تأخّرت.
  static bool lastReadUnknown(ZteOntSession s) => _unknownFormat.contains(s.baseUrl);

  static Future<({String? html, String code, bool login})> _getRaw(ZteOntSession s, String path,
      {Map<String, String>? query, String? referer}) async {
    try {
      final res = await _dio(s.baseUrl).get<String>(
        path,
        queryParameters: query,
        options: Options(headers: {
          if (s.cookie.isNotEmpty) 'Cookie': s.cookie,
          'Referer': referer ?? '${s.baseUrl}/start.ghtml',
        }),
      );
      final body = res.data ?? '';
      final login = ZteOntParse.isLoginPage(body);
      final ok = res.statusCode == 200 && !login;
      return (html: ok ? body : null, code: '${res.statusCode}', login: login);
    } catch (e) {
      return (html: null, code: _errName(e), login: false);
    }
  }

  /// صفحة حالةٍ بحالتها: html (null حين لم تُجب 200)، والرمز، وهل عادت صفحة الدخول.
  static Future<({String? html, String code, bool login})> _pageRaw(ZteOntSession s, String name) =>
      _getRaw(s, '/getpage.gch', query: {'pid': '1002', 'nextpage': name});

  static Future<void> logout(ZteOntSession s) async {
    try {
      await _dio(s.baseUrl).post<String>(
        '/',
        data: 'logout=1',
        options: Options(headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          if (s.cookie.isNotEmpty) 'Cookie': s.cookie,
          'Referer': '${s.baseUrl}/start.ghtml',
        }),
      );
    } catch (_) {/* خروجٌ أفضل جهد */}
  }

  static Map<String, String> _cookies(Response res) {
    final out = <String, String>{};
    for (final line in res.headers.map['set-cookie'] ?? const <String>[]) {
      final nameVal = line.split(';').first;
      final eq = nameVal.indexOf('=');
      if (eq > 0) out[nameVal.substring(0, eq).trim()] = nameVal.substring(eq + 1).trim();
    }
    return out;
  }

  static String _cookieHeader(Map<String, String> jar) => jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

class ZteOntSession {
  const ZteOntSession({required this.baseUrl, required this.cookie});
  final String baseUrl;

  /// فارغٌ حين تحفظ الواجهة الجلسة بالعنوان لا بكوكي.
  final String cookie;
}

/// لماذا لم ندخل — ما يقوله الكرت للوكيل.
enum ZteLoginIssue {
  /// لا جواب (مهلة، اتّصالٌ مرفوض، حالةٌ غريبة) — لا يُحفظ رفضاً، والفحص التالي يحاول.
  unreachable,

  /// العنوان ليس واجهة ZTE.
  notZte,

  /// صفحة الدخول عادت: اليوزر أو الباسورد غلط — يُحفظ فلا يُعاد حتى تتغيّر الاعتمادات.
  rejected,

  /// اعتماداتٌ دخلت قبل ورُفضت الآن: جلسةٌ أخرى مفتوحة على الجهاز (متصفّح أو جلسة ترافيك) — لا يُحفظ.
  busy,

  /// قافلٌ بعد ثلاث محاولاتٍ خاطئة — لا نرسل عليه.
  locked,
}

typedef ZteLoginOutcome = ({ZteOntSession? session, ZteLoginIssue? issue, int? lockLeft, String trace});

/// تحليل صفحات ZTE — نصٌّ ⇒ قيم (نقيّ، يُختبر بلا جهاز).
class ZteOntParse {
  ZteOntParse._();

  static bool isZte(String? server, String html) => (server ?? '').toLowerCase().contains('zte') || isLoginPage(html);

  /// صفحة الدخول — في البداية وحين تنتهي الجلسة (الصفحة المطلوبة تعود دخولاً).
  static bool isLoginPage(String html) => html.contains('fLogin') && html.contains('Frm_Logintoken');

  /// رمز النموذج كما يضعه سكربت الصفحة (`getObj("Frm_Logintoken").value = "3";`) — «3» في الطراز المفحوص.
  static String loginToken(String html) =>
      RegExp(r'getObj\("Frm_Logintoken"\)\.value\s*=\s*"([^"]*)"').firstMatch(html)?.group(1) ?? '';

  /// ثوانٍ باقية على قفل الدخول، أو null حين لا قفل. الصفحة تحسب العدّاد بنفسها: `maxtime = Math.min(60, <وقت القفل> + 60 -
  /// <الآن>)` — وقت القفل صفرٌ ما لم يُقفل (MH80 ٢٧ أكتوبر: `0 + 60 - 402930`).
  static int? lockLeft(String html) {
    final m = RegExp(r'Math\.min\(\s*60\s*,\s*(\d+)\s*\+\s*60\s*-\s*(\d+)\s*\)').firstMatch(html);
    if (m == null) return null;
    final left = int.parse(m.group(1)!) + 60 - int.parse(m.group(2)!);
    return left > 0 && left <= 60 ? left : null;
  }

  /// `var <name> = "…"` — بتنصيصٍ مزدوج أو مفرد أو بلا، وبأيّ حالة أحرف.
  static String? _var(String html, String name) =>
      RegExp('var\\s+$name\\s*=\\s*["\']?\\s*(-?\\d+(?:\\.\\d+)?)', caseSensitive: false).firstMatch(html)?.group(1);

  /// خليّةٌ بمعرّفها، وقد تتبع القيمةَ «dBm».
  static String? _cell(String html, String id) =>
      RegExp('id\\s*=\\s*["\']?$id(?!\\w)["\']?[^>]*>\\s*(-?\\d+(?:\\.\\d+)?)\\s*(?:dBm)?\\s*<', caseSensitive: false)
          .firstMatch(html)
          ?.group(1);

  static String _fixed(num v, int digits) => v.toStringAsFixed(digits);

  /// الضوء بوحدات هواوي نفسها ([OntOpticalInfo]): dBm · mV · mA · °C. الخام: القدرة بـ١/١٠٠٠٠ dBm، والجهد µV، والتيّار µA.
  /// `LosInfo = "1"` ⇒ لا ضوء: القدرتان «--» وحالة الليف «LOS». null: ليست صفحة ضوء (لا قدرة استقبال فيها).
  /// قيمةٌ باسمها بأيّ صيغةٍ تكتبها واجهات ZXIC: `var RxPower = "…"` (MH80)، و`Transfer_meaning('RxPower','…')`،
  /// وخليّة `id="Frm_RxPower"`.
  static String? _val(String html, String name) =>
      _var(html, name) ??
      RegExp('Transfer_meaning\\(\\s*[\'"]$name[\'"]\\s*,\\s*[\'"](-?\\d+(?:\\.\\d+)?)[\'"]', caseSensitive: false)
          .firstMatch(html)
          ?.group(1) ??
      _cell(html, 'Frm_$name');

  /// شكل قيمة الضوء في الصفحة للتشخيص (بلا القيمة): var/tm/frm بأرقامٍ مقنّعة، أو «rx?» يتبعه ما بعد الاسم مباشرةً
  /// بأرقامٍ مقنّعة حين يُذكر بغير صيغةٍ معروفة (شكل الصيغة لا قيمتها)، أو «-» حين لا يُذكر.
  static String rxForm(String html) {
    String mask(String v) => v.replaceAll(RegExp(r'\d'), '9');
    final v = _var(html, 'RxPower');
    if (v != null) return 'var:${mask(v)}';
    final t = RegExp('Transfer_meaning\\(\\s*[\'"]RxPower[\'"]\\s*,\\s*[\'"]([^\'"]{0,16})', caseSensitive: false)
        .firstMatch(html)
        ?.group(1);
    if (t != null) return 'tm:${mask(t)}';
    final c = _cell(html, 'Frm_RxPower');
    if (c != null) return 'frm:${mask(c)}';
    final i = html.toLowerCase().indexOf('rxpower');
    if (i < 0) return '-';
    final after = html.substring(i + 7, (i + 7 + 24).clamp(0, html.length));
    return 'rx?${mask(after).replaceAll(RegExp(r'\s+'), '_')}';
  }

  /// طول الصفحة بالكيلوبايت للأثر: القالب الكامل ~١٣٠ ك.ب على MH80 (~٩٦ على D401)، وصفحة خطأٍ أو دخولٍ أقصر بكثير —
  /// بكسرٍ عشريّ تحت ١٠ ك.ب فتتميّز الصغيرة بعضها من بعض.
  static String kb(String html) {
    final k = html.length / 1024;
    return k < 10 ? '${k.toStringAsFixed(1)}k' : '${k.round()}k';
  }

  /// كلمةٌ قصيرة للأثر (عنوان صفحة): بلا فراغاتٍ ولا فواصل الأثر، ١٦ حرفاً على الأكثر.
  static String traceWord(String s) {
    final w = s.replaceAll(RegExp(r'[\s|/=,:]+'), '_');
    return w.length > 16 ? w.substring(0, 16) : w;
  }

  /// اسم الصفحة بلا `_t.gch` — المرشّحة تُذكر به كاملاً فتُضاف بعينها.
  static String stem(String name) => name.replaceAll(RegExp(r'(_t)?\.gch$'), '');

  /// اسم صفحةٍ مختصرٌ لأثر ما جُرِّب: بلا `_t.gch` ولا «status/info» (`epon_status_link_info_t.gch` ⇒ `epon_link`).
  static String shortPage(String name) {
    final parts = stem(name).split('_').where((p) => p != 'status' && p != 'info').toList();
    return parts.isEmpty ? stem(name) : parts.join('_');
  }

  /// أسماء الصفحات التي يذكرها الجهاز في صفحته (قائمته وروابطه) — أسماءٌ فقط.
  static Set<String> pageNames(String html) => {
        for (final m in RegExp(r'\b([A-Za-z0-9_]{3,60}\.gch)\b').allMatches(html))
          if (m.group(1)!.toLowerCase() != 'getpage.gch') m.group(1)!,
      };

  static const _knownOptical = {'epon_status_link_info_t.gch', 'gpon_status_link_info_t.gch', 'pon_status_link_info_t.gch'};

  /// صفحة حالةٍ أو معلومات، لا إعدادات ولا أوامر — فتحها قراءةٌ فقط.
  static bool _readOnlyPage(String n) {
    final l = n.toLowerCase();
    return (l.contains('status') || l.contains('info')) &&
        !RegExp(r'conf|set|upgrade|update|reboot|restart|restore|reset|factory|backup|manag|mgr|auth|pass|pwd|user|del|add|save|'
                r'apply|ping|trace|diag|log|test')
            .hasMatch(l);
  }

  /// صفحات الضوء المحتملة من أسماء [names]: صفحة حالةٍ أو معلومات (لا إعدادات ولا أوامر) فيها opt/power أوّلاً ثمّ pon.
  static List<String> opticalCandidates(Iterable<String> names) {
    int score(String n) {
      final l = n.toLowerCase();
      return (l.contains('opt') || l.contains('power') ? 4 : 0) + (l.contains('pon') ? 2 : 0) + (l.contains('link') ? 1 : 0);
    }

    final out = [
      for (final n in {...names})
        if (score(n) >= 2 && _readOnlyPage(n) && !_knownOptical.contains(n)) n,
    ];
    out.sort((a, b) {
      final d = score(b) - score(a);
      return d != 0 ? d : a.compareTo(b);
    });
    return out;
  }

  /// صفحات الحالة الأخرى في قائمة الجهاز — يُبحث فيها حين لا تحمل الضوءَ صفحةٌ باسمه (D401). معلومات الجهاز أوّلاً (بعض
  /// البرامج تعرض الضوء فيها)، ثمّ ما فيه pon ثمّ wan، ثمّ الباقي أبجديّاً.
  static List<String> statusPages(Iterable<String> names) {
    final optical = opticalCandidates(names).toSet();
    int score(String n) {
      final l = n.toLowerCase();
      return (l.contains('dev') ? 4 : 0) + (l.contains('pon') ? 2 : 0) + (l.contains('wan') ? 1 : 0);
    }

    final out = [
      for (final n in {...names})
        if (_readOnlyPage(n) && !_knownOptical.contains(n) && !optical.contains(n)) n,
    ];
    out.sort((a, b) {
      final d = score(b) - score(a);
      return d != 0 ? d : a.compareTo(b);
    });
    return out;
  }

  /// أسماء متغيّراتٍ وخلايا تشبه الضوء في الصفحة (`var X =`، `Transfer_meaning('X'`، `id="X"`) — الأسماء بلا قيمها،
  /// لمعرفة صيغة طرازٍ جديد.
  static List<String> powerNames(String html) {
    final out = <String>{};
    final ident = RegExp('(?:var\\s+(\\w{2,32})\\s*=|Transfer_meaning\\(\\s*[\'"](\\w{2,32})[\'"]|id\\s*=\\s*[\'"]?(\\w{2,32}))');
    final like = RegExp(r'power|pwr|optic|dbm|rx|tx', caseSensitive: false);
    final counter = RegExp(r'byte|pkt|packet|frame|cnt|count|err|drop|ctx|text', caseSensitive: false);
    for (final m in ident.allMatches(html)) {
      final n = m.group(1) ?? m.group(2) ?? m.group(3)!;
      if (like.hasMatch(n) && !counter.hasMatch(n)) out.add(n);
      if (out.length >= 12) break;
    }
    return out.toList();
  }

  /// أسماءٌ (بلا قيم) مرشّحةٌ لحمل الضوء في صفحةٍ لا نعرف صيغتها: متغيّرٌ أو خليّةٌ أو وسيط دالّةٍ قيمتُه رقمٌ سالب — قدرة
  /// الاستقبال بالـdBm سالبةٌ دائماً، فأيّ طرازٍ جديد (D401) يحملها في حقلٍ سالب ولو باسمٍ لا rx/tx/power فيه. القيم تُترك،
  /// الأسماء فقط، اثنا عشر على الأكثر. `v:` متغيّر، `t:` Transfer_meaning، `c:` خليّة، `f:` دالّةٌ وسيطها سالب.
  static List<String> opticalHints(String html) {
    final out = <String>{};
    void add(String s) {
      if (out.length < 12) out.add(s);
    }

    // قيمةٌ سالبةٌ غير «‎-1» (الأخيرة قيمةٌ افتراضيّة شائعة).
    bool real(String? v) => v != null && v != '-1' && v != '-1.0';
    for (final m in RegExp('var\\s+(\\w{2,40})\\s*=\\s*[\'"]?(-\\d+(?:\\.\\d+)?)').allMatches(html)) {
      if (real(m.group(2))) add('v:${m.group(1)}');
    }
    for (final m in RegExp('Transfer_meaning\\(\\s*[\'"](\\w{2,40})[\'"]\\s*,\\s*[\'"](-\\d+(?:\\.\\d+)?)').allMatches(html)) {
      if (real(m.group(2))) add('t:${m.group(1)}');
    }
    for (final m in RegExp('id\\s*=\\s*[\'"]?(\\w{2,40})[\'"]?[^>]*>\\s*(-\\d+(?:\\.\\d+)?)').allMatches(html)) {
      if (real(m.group(2))) add('c:${m.group(1)}');
    }
    // استدعاءٌ وسيطه رقمٌ سالبٌ كسريّ (`AddRow(..,'-25.10',..)`) — بعض البرامج تبني جدول الضوء بدالّة.
    const skip = {'Math', 'parseInt', 'parseFloat', 'Number', 'toFixed', 'substr', 'substring', 'slice', 'charAt'};
    for (final m in RegExp('(\\w{3,40})\\s*\\([^;{)]*?-\\d+\\.\\d+').allMatches(html)) {
      final n = m.group(1)!;
      if (!skip.contains(n)) add('f:$n');
    }
    return out.toList();
  }

  static OntOpticalInfo? optical(String html) {
    final rx = _val(html, 'RxPower');
    if (rx == null) return null;
    final tx = _val(html, 'TxPower');
    final current = _val(html, 'Current');
    final volt = _cell(html, 'Frm_Volt');
    final temp = _cell(html, 'Frm_Temp');
    final los = _var(html, 'LosInfo') == '1';
    // MH80 يكتب القدرة بـ١/١٠٠٠٠ dBm (‎-186300)؛ وقيمةٌ في مدى dBm نفسه (‎-31.20) تُقرأ كما هي.
    String dbm(String? raw) {
      final v = num.tryParse(raw ?? '');
      if (v == null) return '--';
      return _fixed(v.abs() > 100 ? v / 10000 : v, 1);
    }

    final mv = num.tryParse(volt ?? '');
    final ua = num.tryParse(current ?? '');
    return OntOpticalInfo(
      rxPower: los ? '--' : dbm(rx),
      txPower: los ? '--' : dbm(tx),
      voltage: mv == null ? '' : _fixed(mv / 1000, 0),
      temperature: temp ?? '',
      bias: (los || ua == null) ? '' : _fixed(ua / 1000, 1),
      sendStatus: los ? 'LOS' : '',
      vendor: 'zte',
      model: model(html),
    );
  }

  /// الطراز من عنوان الصفحة (`<title>MH80</title>`) — كلّ صفحةٍ تحمل القالب كاملاً.
  static String model(String html) {
    final t = RegExp(r'<title>\s*([^<]{1,40}?)\s*</title>').firstMatch(html)?.group(1) ?? '';
    return t.trim();
  }

  static Iterable<Map<int, String>> _rows(String html, String table) sync* {
    final cells = RegExp('getObj\\("${table}_"\\+\\s*RowNum[a-z_]*\\s*\\+"_(\\d+)_table"\\)\\.innerHTML\\s*=\\s*"([^"]*)"')
        .allMatches(html);
    var row = <int, String>{};
    for (final m in cells) {
      final c = int.parse(m.group(1)!);
      if (c == 1 && row.isNotEmpty) {
        yield row;
        row = <int, String>{};
      }
      row[c] = m.group(2)!;
    }
    if (row.isNotEmpty) yield row;
  }

  /// شبكات الواي فاي (`Table_wlanstat`): الخليّة 1 الفهرس · 3 بايتات مستلَمة من العملاء (رفعهم) · 5 بايتات مرسَلة إليهم (تحميلهم).
  static Map<String, ({int sent, int received})> wifi(String html) => {
        for (final r in _rows(html, 'Table_wlanstat'))
          if (int.tryParse(r[3] ?? '') != null && int.tryParse(r[5] ?? '') != null)
            'wlan${r[1]}': (sent: int.parse(r[5]!), received: int.parse(r[3]!)),
      };

  /// المنافذ (`Table_laninterface`): 1 الاسم · 4 الحالة · 5 بايتات مستلَمة · 7 مرسَلة. [linked]: منفذٌ موصول.
  static ({Map<String, ({int sent, int received})> counters, bool linked}) lan(String html) {
    final out = <String, ({int sent, int received})>{};
    var linked = false;
    for (final r in _rows(html, 'Table_laninterface')) {
      final rx = int.tryParse(r[5] ?? '');
      final tx = int.tryParse(r[7] ?? '');
      if (rx == null || tx == null) continue;
      out['lan:${r[1] ?? out.length}'] = (sent: tx, received: rx);
      final state = (r[4] ?? '').toLowerCase();
      if (state.isNotEmpty && !state.contains('disconnect')) linked = true;
    }
    return (counters: out, linked: linked);
  }
}
