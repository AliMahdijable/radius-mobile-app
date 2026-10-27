import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../core/util/dev_log.dart';
import 'mikrotik_binary_api.dart';

/// قناةٌ إلى RouterOS تُرجع **صفوف الـAPI نفسها** (مفتاح ← نصّ) — فيبني `MikrotikApi` الإحصاءات بالشيفرة ذاتها
/// أيّاً كان الطريق.
///
/// ٢٧ أكتوبر — المالك: «لازم نفعل ميزات ssh و snmp وويب للمايكروتيك اكو اجهزه هواي مقفول عليها». منفذ الـAPI
/// (8728) مقفولٌ في أجهزةٍ كثيرة، بينما الويب (REST في RouterOS 7) أو SSH مفتوحٌ بالحساب نفسه. SNMP قارئٌ مستقلّ
/// (`mikrotik_snmp.dart`) لأنّ بياناته أعمدة OID لا أوامر.
abstract class RouterOsChannel {
  /// للعرض في رأس اللوحة: «API» · «الويب» · «SSH».
  String get via;

  /// اتّصالٌ ودخول. يرمي إن تعذّر الوصول أو رُفضت البيانات.
  Future<void> open();

  /// أمرٌ بكلمات الـAPI الثنائيّ (`['/interface/print', '=.proplist=name']`) ← صفوفه.
  /// الخطأ `MikrotikBinaryException` بنصّ الجهاز — «no such command» حين لا يعرف الأمر.
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false});

  Future<void> close();
}

/// الـAPI الثنائيّ (8728/8729) — الطريق الأصليّ والأسرع.
class BinaryRouterOsChannel implements RouterOsChannel {
  BinaryRouterOsChannel(this.client);

  final MikrotikBinaryClient client;

  @override
  String get via => 'API';

  @override
  Future<void> open() async {
    await client.connect();
    await client.login();
  }

  @override
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false}) =>
      client.query(words, debugLog: debugLog);

  @override
  Future<void> close() => client.close();
}

/// كلمات الـAPI (`=k=v`) ← خريطة. كلمات الاستعلام (`?…`) لا تُستعمل في هذا التطبيق فتُهمَل.
Map<String, String> routerOsParams(List<String> words) {
  final out = <String, String>{};
  for (final w in words.skip(1)) {
    if (!w.startsWith('=')) continue;
    final eq = w.indexOf('=', 1);
    if (eq < 0) continue;
    out[w.substring(1, eq)] = w.substring(eq + 1);
  }
  return out;
}

/// REST فوق خدمة الويب — RouterOS 7.1+ على HTTPS (www-ssl)، و7.9+ على HTTP (www).
///
/// `print` ← GET على المسار، وأيّ أمرٍ آخر ← POST بجسم JSON من كلماته (`monitor` مع `"once":""` — لا أوامر مستمرّة
/// عبر REST). القيم كلّها نصوصٌ في الردّ كالـAPI الثنائيّ تماماً (التوثيق الرسميّ).
class RestRouterOsChannel implements RouterOsChannel {
  RestRouterOsChannel({
    required this.host,
    required this.port,
    required this.https,
    required this.user,
    required this.pass,
    this.timeout = const Duration(seconds: 6),
  });

  final String host;
  final int port;
  final bool https;
  final String user;
  final String pass;
  final Duration timeout;
  HttpClient? _http;

  @override
  String get via => 'الويب';

  @override
  Future<void> open() async {
    final h = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 5);
    // شهادة RouterOS الافتراضيّة موقّعةٌ ذاتيّاً — تُقبل لعنوان هذا الجهاز وحده.
    h.badCertificateCallback = (cert, h, p) => h == host;
    _http = h;
    // تحقّقٌ رخيص يميّز «لا REST هنا» (404 على RouterOS 6) و«بيانات خاطئة» (401) قبل أيّ قراءة.
    await query(['/system/identity/print']);
  }

  /// كلمات الأمر ← الطلب. مكشوفة للاختبار.
  @visibleForTesting
  static ({String method, String path, Map<String, String> query, Map<String, String> body}) requestFor(
      List<String> words) {
    final cmd = words.first;
    final params = routerOsParams(words);
    if (cmd.endsWith('/print')) {
      final pl = params['.proplist'];
      return (
        method: 'GET',
        path: '/rest${cmd.substring(0, cmd.length - '/print'.length)}',
        query: {if (pl != null) '.proplist': pl},
        body: const {},
      );
    }
    return (method: 'POST', path: '/rest$cmd', query: const {}, body: params);
  }

  /// JSON الردّ ← صفوف. القائمة صفوف، والكائن المفرد (`system/resource`) صفٌّ واحد.
  @visibleForTesting
  static List<Map<String, String>> rowsFrom(Object? json) {
    Map<String, String> row(Map m) => {
          for (final e in m.entries)
            if (e.value != null) '${e.key}': e.value is String ? e.value as String : '${e.value}',
        };
    if (json is List) return [for (final x in json) if (x is Map) row(x)];
    if (json is Map) return [row(json)];
    return const [];
  }

  /// رسالة الخطأ كما يكتبها RouterOS (`detail` ثمّ `message`) — 404 تُصاغ «no such command» كالـAPI.
  @visibleForTesting
  static MikrotikBinaryException errorFor(int status, String body) {
    String? detail;
    try {
      final j = jsonDecode(body);
      if (j is Map) detail = (j['detail'] ?? j['message'])?.toString();
    } catch (_) {}
    if (status == 401) return MikrotikBinaryException('اسم المستخدم أو كلمة المرور خاطئة', code: 'auth');
    if (status == 404) return MikrotikBinaryException('no such command (${detail ?? 'Not Found'})');
    return MikrotikBinaryException(detail ?? 'HTTP $status');
  }

  @override
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false}) async {
    final http = _http;
    if (http == null) throw MikrotikBinaryException('القناة مغلقة');
    final r = requestFor(words);
    final uri = Uri(
      scheme: https ? 'https' : 'http',
      host: host,
      port: port,
      path: r.path,
      queryParameters: r.query.isEmpty ? null : r.query,
    );
    if (kDebugMode && debugLog) DevLog.trace(() => '▶️ [mtk-rest] ${r.method} ${r.path}');
    final req = await (r.method == 'GET' ? http.getUrl(uri) : http.postUrl(uri)).timeout(timeout);
    req.headers.set(HttpHeaders.authorizationHeader, 'Basic ${base64.encode(utf8.encode('$user:$pass'))}');
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (r.method == 'POST') {
      // طولٌ صريح: بلاه يُرسل HttpClient الجسم مقطّعاً (chunked) فلا يقرؤه خادم RouterOS ويردّ «missing =.id=»
      // (جُرِّب حيّاً على netPower 16P بـ7.19.6 ٢٧ أكتوبر).
      final body = utf8.encode(jsonEncode(r.body));
      req.headers.contentType = ContentType.json;
      req.contentLength = body.length;
      req.add(body);
    }
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    if (res.statusCode >= 400) throw errorFor(res.statusCode, text);
    return rowsFrom(text.trim().isEmpty ? null : jsonDecode(text));
  }

  @override
  Future<void> close() async {
    _http?.close(force: true);
    _http = null;
  }
}

/// SSH — كلّ أمر سكربتٌ RouterOS يطبع الصفوف بصيغةٍ ثابتة (`START|k=v|…`) فتُقرأ كصفوف الـAPI.
///
/// يعمل على RouterOS 6 و7 (الصيغة نفسها أثبتت نفسها في `_fetchClientsViaSsh` على 6.49). `print` ← مسحٌ عامّ لكلّ
/// خصائص القائمة (`:foreach k,v`)، والقوائم المفردة (`system resource`) بـ`get` بلا رقم. أوامر `monitor` لا تُرجع
/// مصفوفةً في السكربت، فتُقرأ مخرجاتها «مفتاح: قيمة» كما تطبعها الطرفيّة.
class SshRouterOsChannel implements RouterOsChannel {
  SshRouterOsChannel({
    required this.host,
    this.port = 22,
    required this.user,
    required this.pass,
    this.timeout = const Duration(seconds: 6),
  });

  final String host;
  final int port;
  final String user;
  final String pass;
  final Duration timeout;
  SSHSocket? _socket;
  SSHClient? _client;

  /// أقصى منافذ يُسأل عن سرعتها في جلسةٍ واحدة — كلّ `monitor once` جولةٌ عند الجهاز.
  static const maxMonitored = 10;

  @override
  String get via => 'SSH';

  @override
  Future<void> open() async {
    final socket = await SSHSocket.connect(host, port, timeout: timeout);
    _socket = socket;
    final c = SSHClient(
      socket,
      username: user,
      onPasswordRequest: () => pass,
      onUserInfoRequest: (req) async => req.prompts.map((_) => pass).toList(),
    );
    _client = c;
    try {
      await c.authenticated.timeout(timeout);
    } on SSHAuthFailError {
      throw MikrotikBinaryException('اسم المستخدم أو كلمة المرور خاطئة', code: 'auth');
    }
  }

  static String _menu(String apiPath) => '/${apiPath.split('/').where((s) => s.isNotEmpty).join(' ')}';

  static String _quote(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll(r'$', r'\$')}"';

  /// كلمات الأمر ← سكربت RouterOS، أو null لأمرٍ لا يُترجَم. مكشوفة للاختبار.
  @visibleForTesting
  static String? scriptFor(List<String> words) {
    final cmd = words.first;
    // إعادة التشغيل: سطر سكربتٍ بلا سؤال تأكيد (كما في المجدوِل).
    if (cmd == '/system/reboot') return '/system reboot';
    if (cmd.endsWith('/print')) {
      final menu = _menu(cmd.substring(0, cmd.length - '/print'.length));
      // قائمةٌ ⇒ find/get لكلّ صفّ؛ مفردة ⇒ `find` يخطئ فـget بلا رقم؛ قائمةٌ لا يعرفها الجهاز ⇒ سطر ERR.
      return (r':local emit do={:local o "START"; :foreach k,v in=$1 do={:set o ($o . "|" . $k . "=" . [:tostr $v])}; :put $o}; '
              r':do {:foreach i in=[MENU find] do={$emit [MENU get $i]}} on-error={'
              r':do {$emit [MENU get]} on-error={:put "ERR|no such command"}}')
          .replaceAll('MENU', menu);
    }
    if (cmd.endsWith('/monitor')) {
      final menu = _menu(cmd.substring(0, cmd.length - '/monitor'.length));
      final names = (routerOsParams(words)['numbers'] ?? '').split(',').where((s) => s.trim().isNotEmpty).toList();
      if (names.isEmpty || names.length > maxMonitored) return null;
      return [for (final n in names) '$menu monitor ${_quote(n.trim())} once'].join('; ');
    }
    return null;
  }

  static final _key = RegExp(r'^\.?[a-z0-9][a-z0-9.\-]*=');

  /// مخرجات `START|k=v|…` ← صفوف. قيمةٌ فيها «|» (تعليقٌ مثلاً) تُلصق بما قبلها بدل أن تُفسد السطر.
  @visibleForTesting
  static List<Map<String, String>> parseRows(String out) {
    final rows = <Map<String, String>>[];
    for (final raw in out.split(RegExp(r'\r?\n'))) {
      final line = raw.trimRight();
      if (!line.startsWith('START')) continue;
      final row = <String, String>{};
      String? last;
      for (final piece in line.split('|').skip(1)) {
        if (_key.hasMatch(piece)) {
          final eq = piece.indexOf('=');
          last = piece.substring(0, eq);
          row[last] = normalizeValue(piece.substring(eq + 1));
        } else if (last != null) {
          row[last] = '${row[last]}|$piece';
        }
      }
      rows.add(row);
    }
    return rows;
  }

  /// مخرجات `monitor … once` («مفتاح: قيمة» مصفوفةً بمسافات) ← صفٌّ لكلّ واجهة؛ يبدأ صفٌّ جديد حين يتكرّر مفتاح.
  /// yes/no ← true/false كما يكتبها الـAPI.
  @visibleForTesting
  static List<Map<String, String>> parseMonitor(String out) {
    final rows = <Map<String, String>>[];
    var cur = <String, String>{};
    final kv = RegExp(r'^\s*([a-z0-9][a-z0-9.\-]*):\s?(.*)$');
    for (final raw in out.split(RegExp(r'\r?\n'))) {
      final m = kv.firstMatch(raw.trimRight());
      if (m == null) continue;
      final k = m.group(1)!;
      if (cur.containsKey(k)) {
        rows.add(cur);
        cur = <String, String>{};
      }
      final v = m.group(2)!.trim();
      cur[k] = switch (v) { 'yes' => 'true', 'no' => 'false', _ => v };
    }
    if (cur.isNotEmpty) rows.add(cur);
    return rows;
  }

  /// `:tostr` يكتب الزمن «1w2d03:04:05» والـAPI «1w2d3h4m5s» — وعلى الثاني تُبنى «يعمل منذ» ومدد العملاء.
  @visibleForTesting
  static String normalizeValue(String v) {
    final m = RegExp(r'^(?:(\d+)w)?(?:(\d+)d)?(\d{1,2}):(\d{2}):(\d{2})(?:\.\d+)?$').firstMatch(v);
    if (m == null) return v;
    final parts = <String>[];
    void add(String? n, String u) {
      final x = int.tryParse(n ?? '') ?? 0;
      if (x > 0) parts.add('$x$u');
    }
    add(m.group(1), 'w');
    add(m.group(2), 'd');
    add(m.group(3), 'h');
    add(m.group(4), 'm');
    add(m.group(5), 's');
    return parts.isEmpty ? '0s' : parts.join();
  }

  static final _cliError = RegExp(r'(no such command|bad command name|syntax error|expected end of command|no such item|not enough permissions)',
      caseSensitive: false);

  @override
  Future<List<Map<String, String>>> query(List<String> words, {bool debugLog = false}) async {
    final c = _client;
    if (c == null) throw MikrotikBinaryException('القناة مغلقة');
    final script = scriptFor(words);
    if (script == null) throw MikrotikBinaryException('no such command (SSH: ${words.first})');
    final out = utf8.decode(await c.run(script).timeout(timeout * 2), allowMalformed: true);
    if (kDebugMode && debugLog) {
      DevLog.trace(() => '📥 [mtk-ssh] ${words.first} → ${out.length > 300 ? out.substring(0, 300) : out}');
    }
    final monitor = words.first.endsWith('/monitor');
    final rows = monitor ? parseMonitor(out) : parseRows(out);
    if (rows.isEmpty) {
      final err = _cliError.firstMatch(out)?.group(0);
      if (err != null) throw MikrotikBinaryException(err.toLowerCase().contains('permission') ? err : 'no such command ($err)');
      if (out.contains('ERR|no such command')) throw MikrotikBinaryException('no such command');
    }
    final pl = routerOsParams(words)['.proplist'];
    if (pl == null) return rows;
    final keep = pl.split(',').toSet();
    return [for (final r in rows) {for (final e in r.entries) if (keep.contains(e.key)) e.key: e.value}];
  }

  @override
  Future<void> close() async {
    _client?.close();
    _client = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
