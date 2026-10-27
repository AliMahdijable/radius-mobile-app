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
  static Future<ZteOntSession?> login(String host, String user, String pass) async =>
      (await attempt(host, user, pass)).session;

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

  /// قراءة الضوء — صفحة EPON ثمّ أسماء GPON المحتملة (الطراز المفحوص EPON). الطراز من عنوان الصفحة نفسها.
  static Future<OntOpticalInfo?> fetchOptical(ZteOntSession s) async {
    _pageTrace.remove(s.baseUrl);
    for (final name in const ['epon_status_link_info_t.gch', 'gpon_status_link_info_t.gch', 'pon_status_link_info_t.gch']) {
      final html = await page(s, name);
      if (html == null) return null;
      final o = ZteOntParse.optical(html);
      if (o != null) return o;
    }
    return null;
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
}

typedef ZteLoginOutcome = ({ZteOntSession? session, ZteLoginIssue? issue, int? lockLeft, String trace});

/// تحليل صفحات ZTE — نصٌّ ⇒ قيم (نقيّ، يُختبر بلا جهاز).
class ZteOntParse {
  ZteOntParse._();

  static bool isZte(String? server, String html) =>
      (server ?? '').toLowerCase().contains('zte') || isLoginPage(html);

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

  static String? _var(String html, String name) =>
      RegExp('var\\s+$name\\s*=\\s*"(-?\\d+(?:\\.\\d+)?)"').firstMatch(html)?.group(1);

  static String? _cell(String html, String id) =>
      RegExp('id="$id"[^>]*>\\s*(-?\\d+(?:\\.\\d+)?)\\s*<').firstMatch(html)?.group(1);

  static String _fixed(num v, int digits) => v.toStringAsFixed(digits);

  /// الضوء بوحدات هواوي نفسها ([OntOpticalInfo]): dBm · mV · mA · °C. الخام: القدرة بـ١/١٠٠٠٠ dBm، والجهد µV، والتيّار µA.
  /// `LosInfo = "1"` ⇒ لا ضوء: القدرتان «--» وحالة الليف «LOS». null: ليست صفحة ضوء (لا قدرة استقبال فيها).
  static OntOpticalInfo? optical(String html) {
    final rx = _var(html, 'RxPower');
    if (rx == null) return null;
    final tx = _var(html, 'TxPower');
    final current = _var(html, 'Current');
    final volt = _cell(html, 'Frm_Volt');
    final temp = _cell(html, 'Frm_Temp');
    final los = _var(html, 'LosInfo') == '1';
    String dbm(String? raw) {
      final v = num.tryParse(raw ?? '');
      return v == null ? '--' : _fixed(v / 10000, 1);
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
