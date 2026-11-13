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
///
/// 🆕 ١٤ نوفمبر — H.T.M HS8546V2 (EPON، XPONV4.2.1M19؛ المالك: «راوتر ضوئي جديد»): الواجهة نفسها وصفحة الضوء والعدّادات
/// بصيغة MH80 حرفاً، والفرق بالدخول وحده — **رمز جلسة** يضعه سكربت الصفحة في الحقل `_SESSION_TOKEN` وفي كوكي
/// `session_cookie` معاً ([ZteOntParse.sessionToken]). بلا أحدهما يردّ الجهاز «User information is error» كأنّ الباسورد
/// غلط (جُرِّب كلٌّ وحده حيّاً)، فكان الكرت يتّهم اعتماداتٍ صحيحة. والجلسة عنده بعنوان الطالب لا بكوكي، وصفحةٌ تُطلب بلا
/// جلسة تعود «Session timeout» قصيرةً (~٠٫٦ ك.ب) لا صفحة دخول ([ZteOntParse.isSessionGone]).
class ZteOntService {
  ZteOntService._();

  /// اعتماداتٌ رفضها جهازٌ (عنوان ⇒ مجموعة يوزر+باسورد): لا يُعاد أيٌّ منها عليه حتى تتغيّر — كلّ رفضٍ يقرّب قفل الواجهة
  /// (ثلاثٌ ⇒ دقيقة). مجموعةٌ لا مفردة (⑦، ٢٩ أكتوبر): مع اعتماداتٍ إضافيّة كان الرفض الثاني يمسح تذكّر الأوّل، فتعيده
  /// الدورة التالية غلطاً — ثالثةٌ تقفل الجهاز.
  static final _rejected = <String, Set<String>>{};

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
    // برنامجٌ برمز جلسة (HS8546V2): الحقل والكوكي كما يضعهما سكربت الصفحة نفسه — بلا الرمز يُردّ الدخول كأنّ الباسورد غلط.
    final st = ZteOntParse.sessionToken(page);
    if (st == null && ZteOntParse.wantsSessionToken(page)) {
      // النموذج يطلب رمزاً لا نعرف من أين يأخذه ⇒ لا نرسل: دخولٌ بلا رمزه يُرفض ويُحسب محاولةً غلط، ويُتّهم الباسورد زوراً.
      return (
        session: null,
        issue: ZteLoginIssue.unknownForm,
        lockLeft: null,
        trace: 'get:${first.statusCode} stok:? ${ZteOntParse.submitShape(page)}',
      );
    }
    final jar = <String, String>{}..addAll(_cookies(first));
    final stCookie = st?.cookie;
    if (st != null && stCookie != null) jar[stCookie] = st.value;
    final Response<String> res;
    try {
      res = await dio.post<String>(
        '/',
        data: 'frashnum=&action=login&Frm_Logintoken=${Uri.encodeQueryComponent(token)}'
            '${st == null ? '' : '&_SESSION_TOKEN=${Uri.encodeQueryComponent(st.value)}'}'
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
    final trace = 'tok:${token.isEmpty ? '-' : 'ok'}${st == null ? '' : ' stok:${stCookie == null ? 'f' : 'fc'}'} post:$code'
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
    _downloadUncountedAt.remove('http://$host');
  }

  /// أجهزةٌ ثبت أنّ عدّادات واجهاتها لا ترى تحميل المشترك (حكم [OntTrafficSession] بالقياس) ⇒ لا جلسة ترافيك عليها قبل
  /// [uncountedQuiet] — لا دخول كلّ بضع ثوانٍ على جهازٍ لا يعطي الرقم — إلّا بـ«حفظ وفحص» ([forget]).
  static final _downloadUncountedAt = <String, DateTime>{};
  static const uncountedQuiet = Duration(minutes: 30);

  static void markDownloadUncounted(ZteOntSession s) => _downloadUncountedAt[s.baseUrl] = DateTime.now();

  static bool downloadUncounted(String host) {
    final at = _downloadUncountedAt['http://$host'];
    if (at == null) return false;
    if (DateTime.now().difference(at) < uncountedQuiet) return true;
    _downloadUncountedAt.remove('http://$host');
    return false;
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
    if (_rejected[host]?.contains(key) ?? false) {
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
      // هذا الاعتماد وحده يخرج من المرفوضات؛ المرفوض غيره يبقى لا يُعاد (لا يقرّب القفل ثانيةً).
      _rejected[host]?.remove(key);
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
        (_rejected[host] ??= <String>{}).add(key);
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
      final login = ZteOntParse.sessionEnded(html);
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
    final names = <String>{};
    final pageFields = <String>[]; // لكلّ صفحةٍ أجابت بلا ضوء: اسمٌ#حجم:حقولٌ مرشّحة — أسماءٌ بلا قيم.
    var title = '';
    var answered = false;

    // صفحة الضوء بحالتها: null حين لم تُجب، وإلّا تُحلَّل. تُسجَّل في الأثر والتشخيص.
    OntOpticalInfo? read(String name, ({String? html, String code, bool login}) r) {
      final html = r.html;
      final pageTitle = html == null ? '' : ZteOntParse.model(html);
      final otherTitle = pageTitle.isNotEmpty && title.isNotEmpty && pageTitle != title;
      tried.add('${ZteOntParse.shortPage(name)}:${r.code}${r.login ? 'L' : ''}'
          '${html == null ? '' : '/${ZteOntParse.rxForm(html)}/${ZteOntParse.kb(html)}'}'
          '${otherTitle ? '/t:${ZteOntParse.traceWord(pageTitle)}' : ''}');
      if (html == null) return null;
      answered = true;
      final o = ZteOntParse.optical(html);
      if (o != null) return o;
      if (title.isEmpty) title = pageTitle;
      // حقول صفحةٍ أجابت بلا ضوءٍ نعرفه — للتشخيص بلا قيم (طرازٌ جديد).
      final digest = ZteOntParse.opticalHints(html).isNotEmpty ? ZteOntParse.opticalHints(html) : ZteOntParse.numericNames(html);
      if (digest.isNotEmpty && pageFields.length < 6) {
        pageFields.add('${ZteOntParse.shortPage(name)}#${ZteOntParse.kb(html)}:${digest.take(6).join('|')}');
      }
      names.addAll(ZteOntParse.powerNames(html));
      return null;
    }

    OntOpticalInfo? found(String name, OntOpticalInfo o) {
      _opticalPageOf[s.baseUrl] = name;
      _scanMissAt.remove(s.baseUrl);
      _pageTrace[s.baseUrl] = tried.join(' ');
      return o;
    }

    // ١) الصفحة المحفوظة لهذا الجهاز (وُجد فيها الضوء قبل، فهي موجودةٌ وآمنة الطلب): مسارٌ سريع بطلبٍ واحد.
    final remembered = _opticalPageOf[s.baseUrl];
    if (remembered != null) {
      final r = await _pageRaw(s, remembered);
      final o = read(remembered, r);
      if (o != null) return found(remembered, o);
      if (r.login) {
        _finishUnknown(s, tried, const <String>{}, names, pageFields, title, answered, true);
        return null;
      }
    }

    // ٢) قائمة الجهاز الحقيقيّة من الإطارين: صفحةٌ ليست فيها (كـepon على D401) تُدخل بعض الطُرُز حالة خطأٍ تُرجع كلّ ما
    //    بعدها فارغاً (~٠٫٧ ك.ب) — فلا نطلب إلّا صفحةً مذكورةً في القائمة.
    final menu = <String>{};
    final missAt = _scanMissAt[s.baseUrl];
    final scan = missAt == null || DateTime.now().difference(missAt) >= scanQuiet;
    for (final frame in const ['/start.ghtml', '/template.gch']) {
      final r = await _getRaw(s, frame, referer: '${s.baseUrl}/');
      tried.add('${frame.substring(1).split('.').first}:${r.code}${r.login ? 'L' : ''}'
          '${r.html == null ? '' : '/${ZteOntParse.kb(r.html!)}'}');
      if (r.login) {
        _finishUnknown(s, tried, menu, names, pageFields, title, answered, scan);
        return null;
      }
      if (r.html != null) menu.addAll(ZteOntParse.pageNames(r.html!));
    }

    // زرّ «Reboot» لهذا الحساب: صفحة إدارة الجهاز في قائمته (تُعرف هنا، والكرت يُظهر زرّه بها — [canReboot]).
    if (menu.isNotEmpty) {
      final rb = ZteOntParse.rebootPage(menu);
      rb == null ? _rebootPageOf.remove(s.baseUrl) : _rebootPageOf[s.baseUrl] = rb;
    }

    // المرشّحات من القائمة فقط: المعروفة، ثمّ ما يسمّيه الجهاز حالةً فيها pon/opt/power، ثمّ باقي صفحات الحالة (بالفحص).
    // 🛡️ احتياطٌ لغير D401: جهازٌ تعذّرت قراءة قائمته (إطارٌ مختلف) ⇒ القائمة فارغة، فنجرّب الأسماء المعروفة مباشرةً كما
    //    كان (MH80 يشتغل بالحالتين). D401 قائمته تُقرأ دائماً فلا يصل هنا، فلا يُطلب epon الذي يفسد جلسته.
    final known = _opticalPages.where((p) => menu.isEmpty || menu.contains(p));
    final queue = <String>{
      ...known,
      ...ZteOntParse.opticalCandidates(menu),
      if (scan) ...ZteOntParse.statusPages(menu),
    }.where((p) => p != remembered).take(_maxExtraPages).toList();
    for (final name in queue) {
      final r = await _pageRaw(s, name);
      final o = read(name, r);
      if (o != null) return found(name, o);
      if (r.login) break; // الجلسة انتهت ⇒ لا جدوى من بقيّة الصفحات
    }

    _finishUnknown(s, tried, menu, names, pageFields, title, answered, scan);
    return null;
  }

  /// يكتب أثر القراءة الفاشلة وتشخيصها (أسماءٌ بلا قيم)، ويعلّم «صيغةٌ جديدة» و«بحثٌ لم يجد» للتهدئة.
  static void _finishUnknown(ZteOntSession s, List<String> tried, Set<String> menu, Set<String> names, List<String> pageFields,
      String title, bool answered, bool scan) {
    if (!scan) tried.add('scan:later');
    _pageTrace[s.baseUrl] = tried.join(' ');
    final c = ZteOntParse.opticalCandidates(menu);
    final statusList = {..._opticalPages.where(menu.contains), ...ZteOntParse.statusPages(menu)}.map(ZteOntParse.stem).toList()
      ..sort();
    _pageInfo[s.baseUrl] = [
      't=${title.isEmpty ? '-' : title}',
      'm=${menu.length}',
      if (pageFields.isNotEmpty) 'pg=${pageFields.join(' ')}',
      if (c.isNotEmpty) 'c=${c.take(6).map(ZteOntParse.stem).join(',')}',
      if (names.isNotEmpty) 'n=${names.take(8).join(',')}',
      if (statusList.isNotEmpty) 's=${statusList.join(',')}',
    ].join(' ');
    if (answered) _unknownFormat.add(s.baseUrl);
    if (answered && scan) _scanMissAt[s.baseUrl] = DateTime.now();
  }

  /// أسماء صفحة الضوء المعروفة بالترتيب (MH80 = epon، D401 = pon). تُطلب فقط إن كانت في قائمة الجهاز.
  static const _opticalPages = ['epon_status_link_info_t.gch', 'gpon_status_link_info_t.gch', 'pon_status_link_info_t.gch'];

  /// صفحاتٌ من القائمة على الأكثر (~٠٫٦–١ث لكلٍّ) — والبحث يقف عند أوّل صفحةٍ فيها الضوء.
  static const _maxExtraPages = 8;

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

  /// صفحة الرابط/الضوء التي وُجدت لهذا الجهاز في آخر فحص (فيها أيضاً عدّادات حزم الـPON) — null: لم تُعرف بعد.
  static String? opticalPageOf(ZteOntSession s) => _opticalPageOf[s.baseUrl];

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
      final login = ZteOntParse.sessionEnded(body);
      final ok = res.statusCode == 200 && !login;
      return (html: ok ? body : null, code: '${res.statusCode}', login: login);
    } catch (e) {
      return (html: null, code: _errName(e), login: false);
    }
  }

  /// صفحة حالةٍ بحالتها: html (null حين لم تُجب 200)، والرمز، وهل عادت صفحة الدخول. كلّ الصفحات بمجموعةٍ واحدة
  /// `pid=1002` (مُتحقَّق حيّاً على MH80 وD401) — ما يُفرّق هو اسم الصفحة، وطلب اسمٍ ليس في القائمة يفسد الجلسة.
  static Future<({String? html, String code, bool login})> _pageRaw(ZteOntSession s, String name) =>
      _getRaw(s, '/getpage.gch', query: {'pid': '1002', 'nextpage': name});

  /// أسماء صفحات الجهاز الحقيقيّة من الإطارين (start.ghtml + template.gch) — لاختيار صفحات الترافيك الموجودة فعلاً
  /// (D401 ≠ MH80) وتجنّب تسميم الجلسة بطلب اسمٍ غير موجود. فارغةٌ حين انتهت الجلسة أو تعذّرت القراءة.
  static Future<Set<String>> menuPages(ZteOntSession s) async {
    final menu = <String>{};
    for (final frame in const ['/start.ghtml', '/template.gch']) {
      final r = await _getRaw(s, frame, referer: '${s.baseUrl}/');
      if (r.login) break;
      if (r.html != null) menu.addAll(ZteOntParse.pageNames(r.html!));
    }
    return menu;
  }

  /// صفحة إدارة الجهاز (فيها زرّ «Reboot») في قائمة الحساب الذي دخلنا به — لكلّ جهازٍ في هذه الجلسة.
  static final _rebootPageOf = <String, String>{};

  /// كم ننتظر ردّ الجهاز على أمر إعادة التشغيل قبل أن نعدّ سكوته قبولاً: صفحاته تجيب بأقلّ من ثانيتين، والجهاز المجرَّب لا
  /// يردّ على هذا الأمر أبداً — فلا يبقى الوكيل ينتظر مهلة القراءة الكاملة (١٥ث). يُضبط بالاختبارات.
  static Duration rebootReplyWait = const Duration(seconds: 6);

  /// في قائمة هذا الحساب صفحة إعادة التشغيل التي نعرفها — يُسأل بعد [fetchOptical] (القائمة تُقرأ فيها أوّل مرّة).
  static bool canReboot(ZteOntSession s) => _rebootPageOf.containsKey(s.baseUrl);

  /// إعادة تشغيل الجهاز بزرّ «Reboot» في صفحة «Device Management» نفسها — جُرِّب حيّاً على H.T.M HS8546V2 بإذن المالك
  /// (١٤ نوفمبر): نموذج الصفحة `fSubmit` إلى الصفحة نفسها بـ`IF_ACTION=devrestart` و`flag=1`، وبقيّة حقوله كما ملأتها
  /// الصفحة، ورمز جلستها ([ZteOntParse.rebootForm]) — لا نرسل إلّا ما يرسله سكربت الصفحة، وعلى صفحةٍ تعلن الأمر بنفسها.
  ///
  /// ⛔ جاره في السكربت نفسه `devrestore`/`devrestoreAll` = **ضبط المصنع** (يمسح إعدادات المشترك والـPPPoE) — لا يُرسَل
  /// أبداً، واختبارٌ يثبّت أنّه لا يخرج منّا.
  ///
  /// [sent]: الجهاز قبل الأمر، أو سكت بعد أن وصله (بدأ يقلع). الجلسة تموت مع الإقلاع فلا خروج بعده.
  ///
  /// القياس الحيّ (HS8546V2): الجهاز **لا يردّ** على الأمر أصلاً — يسكت ويقلع (انقطع عن الشبكة خلال ~١٩ث، ورجعت صفحته تجاوب
  /// عند +٧٢ث بمدّة تشغيلٍ ٥٦ث، ثمّ الدخول والضوء كما كانا). فسكوته بعد وصول الطلب هو القبول ([rebootReplyWait])، وصفحةٌ
  /// تعود بـ`flag=1` (برنامجٌ يردّ) قبولٌ أيضاً ([ZteOntParse.rebootAccepted]).
  static Future<ZteRebootOutcome> reboot(String host, String user, String pass) async {
    final s = await loginConfigured(host, user, pass);
    if (s == null) {
      final i = lastIssue(host);
      return (sent: false, issue: i?.issue ?? ZteLoginIssue.unreachable, trace: 'login ${i?.trace ?? ''}');
    }
    var leave = true;
    try {
      var name = _rebootPageOf[s.baseUrl];
      if (name == null) {
        name = ZteOntParse.rebootPage(await menuPages(s));
        if (name != null) _rebootPageOf[s.baseUrl] = name;
      }
      if (name == null) return (sent: false, issue: null, trace: 'no-page');
      final page = await _pageRaw(s, name);
      final html = page.html;
      if (html == null) return (sent: false, issue: null, trace: 'page:${page.code}${page.login ? 'L' : ''}');
      final body = ZteOntParse.rebootForm(html);
      if (body == null) return (sent: false, issue: null, trace: 'no-form ${ZteOntParse.kb(html)}');
      final Response<String> res;
      try {
        res = await _dio(s.baseUrl).post<String>(
          '/getpage.gch',
          queryParameters: {'pid': '1002', 'nextpage': name},
          data: body,
          options: Options(receiveTimeout: rebootReplyWait, headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            if (s.cookie.isNotEmpty) 'Cookie': s.cookie,
            'Referer': '${s.baseUrl}/getpage.gch?pid=1002&nextpage=$name',
          }),
        );
      } on DioException catch (e) {
        // لم يتّصل أصلاً ⇒ لم يُرسَل. أُرسل وانقطع الجواب ⇒ الجهاز بدأ يقلع غالباً — لا يُعاد الأمر.
        final never = e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError;
        leave = never;
        return (sent: !never, issue: null, trace: 'post:${e.type.name}');
      }
      final out = res.data ?? '';
      final ok = res.statusCode == 200 && ZteOntParse.rebootAccepted(out);
      leave = !ok;
      return (
        sent: ok,
        issue: null,
        trace: 'post:${res.statusCode} ${ZteOntParse.kb(out)}${ZteOntParse.sessionEnded(out) ? ' ended' : ''}',
      );
    } finally {
      if (leave) await logout(s);
    }
  }

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

  /// نموذج الدخول يطلب رمز جلسةٍ لا نعرف من أين يأخذه (برنامجٌ جديد) — لا نرسل: الدخول بلا رمزه يُرفض ويُحسب محاولةً
  /// غلط. لا يُحفظ رفضاً، وشكل سكربت الصفحة يُبلَّغ بلا قيم.
  unknownForm,
}

typedef ZteLoginOutcome = ({ZteOntSession? session, ZteLoginIssue? issue, int? lockLeft, String trace});

/// نتيجة أمر إعادة التشغيل: [sent] أُرسل وقُبل (أو انقطع الجواب بعد الإرسال)؛ [issue] سبب فشل الدخول إن لم ندخل.
typedef ZteRebootOutcome = ({bool sent, ZteLoginIssue? issue, String trace});

/// تحليل صفحات ZTE — نصٌّ ⇒ قيم (نقيّ، يُختبر بلا جهاز).
class ZteOntParse {
  ZteOntParse._();

  static bool isZte(String? server, String html) => (server ?? '').toLowerCase().contains('zte') || isLoginPage(html);

  /// صفحة الدخول — في البداية وحين تنتهي الجلسة (الصفحة المطلوبة تعود دخولاً).
  static bool isLoginPage(String html) => html.contains('fLogin') && html.contains('Frm_Logintoken');

  /// رمز النموذج كما يضعه سكربت الصفحة (`getObj("Frm_Logintoken").value = "3";`) — «3» في الطراز المفحوص.
  static String loginToken(String html) =>
      RegExp(r'getObj\("Frm_Logintoken"\)\.value\s*=\s*"([^"]*)"').firstMatch(html)?.group(1) ?? '';

  /// صفحة إدارة الجهاز التي فيها زرّ «Reboot» من أسماء قائمة الحساب — الاسم المجرَّب حيّاً وحده (حساب user على HS8546V2).
  /// null: ليست في قائمته ⇒ لا زرّ في الكرت (لا زرّ يَعِد بما لم يُجرَّب).
  static String? rebootPage(Iterable<String> menu) =>
      menu.contains('manager_dev_conf_t_user.gch') ? 'manager_dev_conf_t_user.gch' : null;

  /// آخر قيمةٍ تضعها الصفحة لحقل [name] (`Transfer_meaning('name','value')` — الأخيرة تغلب كما في المتصفّح)، بفكّ `\xHH`.
  static String? _lastMeaning(String html, String name) {
    final all = RegExp('Transfer_meaning\\(\\s*[\'"]$name[\'"]\\s*,\\s*[\'"]([^\'"]*)[\'"]').allMatches(html);
    if (all.isEmpty) return null;
    return all.last.group(1)!.replaceAllMapped(
        RegExp(r'\\x([0-9a-fA-F]{2})'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
  }

  /// جسم طلب «Reboot» كما يرسله نموذج الصفحة `fSubmit` حرفاً: حقوله المخفيّة بترتيبها وقيمها التي ملأتها الصفحة، مع
  /// `IF_ACTION=devrestart` و`flag=1` (ما يضعه `msgCallback()` قبل الإرسال)، ثمّ رمز جلسة الصفحة (`session_token` الذي
  /// يضيفه سكربتها لكلّ نموذج). null — فلا نرسل شيئاً — حين لا تعلن الصفحة أمر `devrestart` بنفسها، أو لا نموذج، أو تطلب
  /// رمزاً لم نجده. ⛔ لا يكتب إلّا `devrestart`: جاره `devrestore` ضبطُ مصنع.
  static String? rebootForm(String html) {
    if (!RegExp('[\'"]devrestart[\'"]').hasMatch(html)) return null;
    final form = RegExp('<form[^>]*\\bname\\s*=\\s*[\'"]?fSubmit\\b.*?</form>', caseSensitive: false, dotAll: true)
        .firstMatch(html)
        ?.group(0);
    if (form == null) return null;
    final names = [
      for (final m in RegExp('<input[^>]*\\bname\\s*=\\s*[\'"]?([\\w.]+)', caseSensitive: false).allMatches(form)) m.group(1)!,
    ];
    if (!names.contains('IF_ACTION') || !names.contains('flag')) return null;
    final token = RegExp('var\\s+session_token\\s*=\\s*[\'"]([^\'"]+)[\'"]').firstMatch(html)?.group(1);
    if (token == null && html.contains('_SESSION_TOKEN')) return null;
    String pair(String n, String v) => '${Uri.encodeQueryComponent(n)}=${Uri.encodeQueryComponent(v)}';
    return [
      for (final n in names)
        pair(n, switch (n) { 'IF_ACTION' => 'devrestart', 'flag' => '1', _ => _lastMeaning(html, n) ?? '' }),
      if (token != null) pair('_SESSION_TOKEN', token),
    ].join('&');
  }

  /// ردّ الجهاز على أمر «Reboot»: الصفحة نفسها تعود و`flag` فيها «1» والخطأ `SUCC` — عندها تعرض «Device restarting will
  /// take about 2~3 minutes» (سكربتها `pageLoad`).
  static bool rebootAccepted(String html) =>
      !sessionEnded(html) && _lastMeaning(html, 'flag') == '1' && _lastMeaning(html, 'IF_ERRORSTR') == 'SUCC';

  /// النموذج فيه حقل رمز الجلسة — برامج ZXIC الأحدث (HS8546V2). MH80 وD401 بلا هذا الحقل.
  static bool wantsSessionToken(String html) => html.contains('_SESSION_TOKEN');

  /// رمز الجلسة الذي يرسله سكربت الدخول مع النموذج (HS8546V2، XPONV4.2.1M19 — من صفحته الحيّة):
  /// `var token = "A36…"; getObj("_SESSION_TOKEN").value = token; … setCookie("session_cookie",token);` — الحقل والكوكي
  /// معاً شرط (جُرِّب كلٌّ وحده حيّاً فرُدّ الدخول). نفعل ما يفعله سكربت الصفحة: القيمة من `var token`، والكوكي بالاسم الذي
  /// يضعه `setCookie` (null حين لا يضع كوكي)؛ أو قيمة الحقل نفسها إن ملأها الخادم (يرسلها المتصفّح كما هي، بلا كوكي).
  /// null: برنامجٌ بلا رمز، أو صيغةٌ لا نعرفها ([wantsSessionToken] يفرّق بينهما).
  static ({String value, String? cookie})? sessionToken(String html) {
    if (!wantsSessionToken(html)) return null;
    final v = RegExp('var\\s+token\\s*=\\s*["\']([^"\']+)["\']').firstMatch(html)?.group(1);
    if (v != null) {
      final cookie = RegExp('setCookie\\(\\s*["\']([\\w.-]+)["\']\\s*,\\s*token\\s*\\)').firstMatch(html)?.group(1);
      return (value: v, cookie: cookie);
    }
    final input = RegExp('<input[^>]*_SESSION_TOKEN[^>]*>', caseSensitive: false).firstMatch(html)?.group(0) ?? '';
    final filled = RegExp('\\svalue\\s*=\\s*["\']([^"\']+)["\']', caseSensitive: false).firstMatch(input)?.group(1);
    return filled == null ? null : (value: filled, cookie: null);
  }

  /// شكل سكربت الإرسال في صفحة دخولٍ لا نعرف من أين تأخذ رمزها — للتشخيص بلا قيم: الأرقام مقنّعة، ١٤٠ حرفاً على الأكثر.
  static String submitShape(String html) {
    final i = html.indexOf('function dosubmit');
    final from = i >= 0 ? i : html.indexOf('_SESSION_TOKEN');
    if (from < 0) return '-';
    final s = html
        .substring(from, (from + 400).clamp(0, html.length))
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\d'), '9');
    return s.length > 140 ? s.substring(0, 140) : s;
  }

  /// صفحة «انتهت الجلسة» القصيرة التي تردّ بها بعض البرامج بدل صفحة الدخول لأيّ صفحةٍ تُطلب بلا جلسة (HS8546V2: ٦٢٧ بايتاً
  /// — `logout_redirect()` و«Session timeout, please login again.»). بالطول أيضاً: صفحة محتوى لا تقلّ عن عشرات الكيلوبايتات.
  static bool isSessionGone(String html) => html.length < 4096 && html.contains('logout_redirect');

  /// الجلسة ليست قائمة: صفحة الدخول عادت، أو صفحة «انتهت الجلسة».
  static bool sessionEnded(String html) => isLoginPage(html) || isSessionGone(html);

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

  /// أسماء الصفحات التي يذكرها الجهاز في صفحته (قائمته وروابطه) — أسماءٌ فقط. تُستبعد ملفّات الهيكل (getpage/الإطارات)
  /// فلا تُحسب صفحة محتوى: `start.ghtml` يُشير إلى `template.gch`/`top.gch` فلولا استبعادها لظنّنا القائمة غير فارغة.
  static const _frameFiles = {'getpage.gch', 'template.gch', 'top.gch', 'start.ghtml', 'frame.gch'};
  static Set<String> pageNames(String html) => {
        for (final m in RegExp(r'\b([A-Za-z0-9_]{3,60}\.(?:gch|ghtml))\b').allMatches(html))
          if (!_frameFiles.contains(m.group(1)!.toLowerCase()) && m.group(1)!.endsWith('.gch')) m.group(1)!,
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

  /// مفردات الحقول الرقميّة في صفحةٍ لا نعرف صيغتها (D401: لا رقمٌ سالبٌ ولا اسم ضوء) — أسماء كلّ `var X="<رقم>"`
  /// و`Transfer_meaning('X','<رقم>')` وخليّةٍ `id="X">رقم`، بعد استبعاد أسماء الشبكة/الإعدادات/العدّادات المعروفة
  /// (vlan/port/mac/ip/count…). أسماءٌ فقط (القيم تُترك)، أربعٌ وعشرون على الأكثر — منها يُعرف ما يسمّيه الطراز ضوءه
  /// (قد تكون قيمته موجبةً باسمٍ لا يشبه الضوء).
  static List<String> numericNames(String html) {
    final out = <String>{};
    final noise = RegExp(
        r'vlan|port|mac|ipv|^ip|_ip|addr|route|dns|dhcp|prefix|igmp|multicast|bpdu|firewall|filter|loopback|mirror|'
        r'led|loid|ratelimit|flowctl|isolate|byte|pkt|packet|frame|cnt|count|num|index|^idx|mtu|time|date|id$|_id|'
        r'enable|flag|mode|type|status|state|total|page|row|col|width|height|size|len|version|ver$|year|month|day|hour',
        caseSensitive: false);
    void scan(RegExp re, String tag) {
      for (final m in re.allMatches(html)) {
        if (out.length >= 24) return;
        final n = m.group(1)!;
        if (!noise.hasMatch(n)) out.add('$tag$n');
      }
    }

    scan(RegExp('var\\s+(\\w{2,40})\\s*=\\s*[\'"]?(-?\\d+(?:\\.\\d+)?)[\'"]?\\s*;'), 'v:');
    scan(RegExp('Transfer_meaning\\(\\s*[\'"](\\w{2,40})[\'"]\\s*,\\s*[\'"](-?\\d+(?:\\.\\d+)?)[\'"]'), 't:');
    scan(RegExp('id\\s*=\\s*[\'"]?(\\w{2,40})[\'"]?[^>]*>\\s*(-?\\d+(?:\\.\\d+)?)\\s*<'), 'c:');
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

  /// مجموع **إطارات** الواي فاي على كلّ الشبكات (`Table_wlanstat`: الخليّة 4 إطاراتٌ مستلَمة من العملاء · 6 مرسَلة إليهم).
  /// null: لا جدول. تُقارَن بحزم الـPON لمعرفة هل ترى عدّادات الواي فاي تحميل المشترك فعلاً ([OntTrafficSession]).
  static ({int sent, int received})? wifiFrames(String html) {
    var sent = 0;
    var received = 0;
    var rows = 0;
    for (final r in _rows(html, 'Table_wlanstat')) {
      final rx = int.tryParse(r[4] ?? '');
      final tx = int.tryParse(r[6] ?? '');
      if (rx == null || tx == null) continue;
      received += rx;
      sent += tx;
      rows++;
    }
    return rows == 0 ? null : (sent: sent, received: received);
  }

  /// مجموع **الحزم** المرسَلة إلى أجهزة المشترك على المنافذ (`Table_laninterface`: الخليّة 8). null: لا جدول بهذه الصيغة.
  static int? lanSentPackets(String html) {
    int? sum;
    for (final r in _rows(html, 'Table_laninterface')) {
      final tx = int.tryParse(r[8] ?? '');
      if (tx != null) sum = (sum ?? 0) + tx;
    }
    return sum;
  }

  /// حزم الـPON المستقبَلة من البرج للمشترك (صفحة الرابط: `Transfer_meaning('UniPacketRecv','…')`، وإلّا `PacketRecv`) — ما
  /// دخل للجهاز فعلاً، حزماً لا بايتات. null: الصفحة لا تذكرها.
  static int? ponReceivedPackets(String html) => _tmInt(html, 'UniPacketRecv') ?? _tmInt(html, 'PacketRecv');

  static int? _tmInt(String html, String name) => int.tryParse(
      RegExp('Transfer_meaning\\(\\s*[\'"]$name[\'"]\\s*,\\s*[\'"](\\d{1,19})[\'"]').firstMatch(html)?.group(1) ?? '');

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

  /// منافذ D401 (جدول خلايا ثابتة لا سكربت): لكلّ منفذٍ «Bytes Received» (ما استقبله الـONU من المشترك = رفعُه) ثمّ
  /// «Bytes Sent» (ما أرسله إليه = تنزيلُه)، القيمة في الخليّة التالية مباشرةً. يُرجَع كـMH80: (sent = تنزيل، received =
  /// رفع). [linked]: منفذٌ حالته «Up». العدّادات ٣٢-بت كبقيّة ZTE فيلتقطها [OntTrafficMeter] عند الالتفاف.
  static ({Map<String, ({int sent, int received})> counters, bool linked}) lanLabels(String html) {
    final hits = RegExp(r'>\s*Bytes\s+(Received|Sent)\s*<[^>]*>\s*<[^>]*>\s*(\d{1,19})', caseSensitive: false)
        .allMatches(html)
        .toList();
    final out = <String, ({int sent, int received})>{};
    var port = 0;
    int? rx;
    for (final m in hits) {
      final isRecv = m.group(1)!.toLowerCase() == 'received';
      final val = int.tryParse(m.group(2)!);
      if (val == null) continue;
      if (isRecv) {
        rx = val;
      } else if (rx != null) {
        out['lan:${++port}'] = (sent: val, received: rx);
        rx = null;
      }
    }
    final linked = RegExp(r'(Up|Full Duplex|\d+\s*Mbps)', caseSensitive: false).hasMatch(html);
    return (counters: out, linked: linked);
  }
}
