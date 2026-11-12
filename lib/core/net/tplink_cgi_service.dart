import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../models/device_health.dart';
import 'tplink_agile_service.dart' show AgileCrypto;

/// راوتر TP-Link بواجهة CGI القديمة مع تعمية GDPR (Archer C50 وأخواته — HTTP على 80؛ قِيس من كود الجهاز نفسه ١٢ نوفمبر):
///
/// * التعرّف: «/» 200 بصفحة دخولٍ فيها `INCLUDE_LOGIN_GDPR_ENCRYPT` و`/cgi/getParm` (بلا اعتماد).
/// * المعاملات: `POST /cgi?8` بجسم `[/cgi/getParm#0,0,0,0,0,0#0,0,0,0,0,0]0,0\r\n` ⇒ `var ee/nn/seq` (RSA ‏512 بت).
/// * التعمية: AES-128-CBC (مفتاح وIV ستّة عشر حرفاً) + توقيع RSA **بلا حشو** (النصّ في أعلى البايتات ثمّ أصفار، قطعٌ ٦٤ حرفاً،
///   كلّ قطعة ١٢٨ هكس): الدخول `key=..&iv=..&h=<md5(user+pass)>&s=<seq+طول المعمّى>`، وغيره `h=..&s=..`. الجسم
///   `sign=..\r\ndata=..\r\n` إلى `/cgi_gdpr`، والردّ AES.
/// * الطلب المفكوك: أنواع العمليّات `8&1&5…` ثمّ لكلٍّ `[OID#مكدّس#مكدّس الأب]فهرس,عدد\r\n` وأسماء الحقول (أو `اسم=قيمة`).
///   الردّ أسطر `[مكدّس]فهرس` ثمّ `اسم=قيمة`، و`[error]رمز` آخراً (0 نجاح).
/// * الدخول `[/cgi/login…]` بـusername/password، والخروج `[/cgi/logout…]`. عشر محاولاتٍ غلط ⇒ قفلٌ ساعتين (صفحة الجهاز).

enum CgiIssue { rejected, locked, busy, unreachable, readFailed }

/// اتّصال HTTP/1.1 محفوظ (keep-alive) لجلسةٍ كاملة — كالمتصفّح: المعاملات والدخول والقراءات والخروج على المقبس نفسه. يقرأ الردّ
/// بطوله أو بقطعه، وتقطيعٌ معطوب (الجهاز يعلنه ويرسل صفحةً خاماً) يُقرأ حتى يسكت المقبس ثمّ يُغلق. انقطع ⇒ يُفتح غيره للطلب التالي.
class _KaConn {
  _KaConn(this.host, this.port);
  final String host;
  final int port;
  Socket? _sock;
  StreamSubscription<List<int>>? _sub;
  final _buf = <int>[];
  bool _done = true;
  Completer<void>? _wait;

  Future<void> _open() async {
    await close();
    final s = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    _sock = s;
    _done = false;
    _buf.clear();
    _sub = s.listen(
      (d) {
        _buf.addAll(d);
        _poke();
      },
      onDone: () {
        _done = true;
        _poke();
      },
      onError: (Object _) {
        _done = true;
        _poke();
      },
      cancelOnError: true,
    );
  }

  void _poke() {
    final w = _wait;
    _wait = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  /// ينتظر بايتاتٍ أخرى ⇒ false حين أُغلق المقبس أو سكت [quiet].
  Future<bool> _more({Duration quiet = const Duration(seconds: 12)}) async {
    if (_done) return false;
    final c = _wait = Completer<void>();
    try {
      await c.future.timeout(quiet);
      return true;
    } on TimeoutException {
      return false;
    }
  }

  int _find(List<int> pat) {
    outer:
    for (var i = 0; i + pat.length <= _buf.length; i++) {
      for (var j = 0; j < pat.length; j++) {
        if (_buf[i + j] != pat[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  Future<({int status, Map<String, List<String>> headers, List<int> body})?> send(List<int> request) async {
    if (_sock == null || _done) await _open();
    _sock!.add(request);
    await _sock!.flush();
    int sep;
    while ((sep = _find(const [13, 10, 13, 10])) < 0) {
      if (!await _more()) return null;
    }
    final lines = latin1.decode(_buf.sublist(0, sep)).split('\r\n');
    _buf.removeRange(0, sep + 4);
    final parts = lines.first.split(' ');
    final status = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final headers = <String, List<String>>{};
    for (final l in lines.skip(1)) {
      final c = l.indexOf(':');
      if (c > 0) (headers[l.substring(0, c).trim().toLowerCase()] ??= []).add(l.substring(c + 1).trim());
    }
    final te = (headers['transfer-encoding'] ?? const []).join(',').toLowerCase();
    final cl = int.tryParse((headers['content-length'] ?? const ['']).first);
    List<int> body;
    if (te.contains('chunked')) {
      body = await _chunked();
    } else if (cl != null) {
      while (_buf.length < cl) {
        if (!await _more()) break;
      }
      body = _buf.sublist(0, min(cl, _buf.length));
      _buf.removeRange(0, body.length);
    } else {
      while (await _more(quiet: const Duration(seconds: 2))) {}
      body = List.of(_buf);
      _buf.clear();
      await close();
    }
    if ((headers['connection'] ?? const []).join(',').toLowerCase().contains('close')) await close();
    return (status: status, headers: headers, body: body);
  }

  Future<List<int>> _chunked() async {
    final out = <int>[];
    while (true) {
      int eol;
      while ((eol = _find(const [13, 10])) < 0) {
        if (!await _more()) return out;
      }
      final size = int.tryParse(latin1.decode(_buf.sublist(0, eol)).split(';').first.trim(), radix: 16);
      if (size == null) {
        // يعلن التقطيع ولا يقطّع (صفحة خطأ خام) ⇒ ما يصل حتى السكوت، والاتّصال لا يُعاد استعماله
        while (await _more(quiet: const Duration(milliseconds: 1500))) {}
        out.addAll(_buf);
        _buf.clear();
        await close();
        return out;
      }
      _buf.removeRange(0, eol + 2);
      if (size == 0) {
        while (_find(const [13, 10]) < 0) {
          if (!await _more(quiet: const Duration(seconds: 2))) return out;
        }
        _buf.removeRange(0, _find(const [13, 10]) + 2);
        return out;
      }
      while (_buf.length < size + 2) {
        if (!await _more()) {
          out.addAll(_buf);
          _buf.clear();
          return out;
        }
      }
      out.addAll(_buf.sublist(0, size));
      _buf.removeRange(0, size + 2);
    }
  }

  Future<void> close() async {
    await _sub?.cancel();
    _sub = null;
    _sock?.destroy();
    _sock = null;
    _done = true;
    _poke();
  }
}

class CgiParse {
  CgiParse._();

  /// `var ee="010001";` ⇒ القيم.
  static Map<String, String> vars(String text) {
    final out = <String, String>{};
    for (final m in RegExp(r'var\s+(\w+)\s*=\s*"?([^";\n]*)"?;').allMatches(text)) {
      out[m.group(1)!] = m.group(2)!;
    }
    return out;
  }

  /// رمز `[error]N` الأخير (null إن غاب).
  static int? errorCode(String text) {
    final all = RegExp(r'\[error\](\d+)').allMatches(text).toList();
    return all.isEmpty ? null : int.tryParse(all.last.group(1)!);
  }

  /// الردّ ⇒ لكلّ فهرس عمليّة قائمةُ كائناتٍ ({__stack, اسم: قيمة}).
  static Map<int, List<Map<String, String>>> objects(String text) {
    final out = <int, List<Map<String, String>>>{};
    Map<String, String>? cur;
    for (final raw in text.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      final m = RegExp(r'^\[([^\]]*)\](\d+)$').firstMatch(line);
      if (m != null) {
        final stack = m.group(1)!;
        if (stack == 'error' || stack == 'cgi') {
          cur = null;
          continue;
        }
        cur = {'__stack': stack};
        (out[int.parse(m.group(2)!)] ??= []).add(cur);
        continue;
      }
      if (cur == null) continue;
      final eq = line.indexOf('=');
      if (eq <= 0) continue;
      cur[line.substring(0, eq)] = line.substring(eq + 1);
    }
    return out;
  }

  static int? _i(String? v) => v == null ? null : int.tryParse(v.trim());

  /// قراءة الحالة (ترتيب [TplinkCgiService.readActions]) ⇒ لقطة الراوتر.
  static UbiquitiStatus? status(Map<int, List<Map<String, String>>> o, {required String baseUrl}) {
    final dev = (o[0] ?? const []).isNotEmpty ? o[0]!.first : const <String, String>{};
    final ppp = o[1] ?? const <Map<String, String>>[];
    final ipc = o[2] ?? const <Map<String, String>>[];
    final hosts = o[3] ?? const <Map<String, String>>[];
    final assoc = o[4] ?? const <Map<String, String>>[];
    if (dev.isEmpty && ppp.isEmpty && ipc.isEmpty) return null;
    Map<String, String>? up(List<Map<String, String>> l) {
      for (final c in l) {
        if ((c['connectionStatus'] ?? '').toLowerCase() == 'connected') return c;
      }
      return null;
    }

    final pc = up(ppp);
    final ic = pc == null ? up(ipc) : null;
    final conn = pc ?? ic;
    final byMac = <String, Map<String, String>>{
      for (final h in hosts)
        if ((h['MACAddress'] ?? '').isNotEmpty) h['MACAddress']!.toUpperCase(): h,
    };
    final clients = <RouterClient>[];
    for (final a in assoc) {
      final mac = (a['associatedDeviceMACAddress'] ?? '').toUpperCase();
      if (mac.isEmpty) continue;
      final h = byMac[mac];
      final n = (h?['hostName'] ?? '').trim();
      final ip = (h?['IPAddress'] ?? '').trim();
      clients.add(RouterClient(mac: mac, ip: ip.isEmpty ? null : ip, name: n.isEmpty || n == '--' ? null : n, wired: false));
    }
    final model = (dev['modelName'] ?? '').trim();
    final hw = (dev['hardwareVersion'] ?? '').trim();
    return UbiquitiStatus(
      hostname: '',
      firmware: (dev['softwareVersion'] ?? '').trim(),
      uptimeSeconds: _i(dev['upTime']),
      ssid: '',
      mode: 'router',
      signalDbm: null,
      noiseFloorDbm: null,
      ccqPercent: null,
      distanceMeters: null,
      txRateKbps: null,
      rxRateKbps: null,
      lanPorts: const [],
      peerMac: null,
      peerCount: o.containsKey(4) ? clients.length : null,
      baseUrl: baseUrl,
      vendor: 'tpcgi',
      model: hw.isNotEmpty ? hw.replaceAll(RegExp(r'\s+[0-9A-Fa-f]{6,}$'), '') : model,
      wanOnlineSeconds: _i(conn?['uptime']),
      dhcpCount: o.containsKey(3) ? hosts.length : null,
      wanType: pc != null ? 'PPPoE' : (ic != null ? (ic['addressingType'] == 'Static' ? 'Static IP' : 'Dynamic IP') : ''),
      clients: clients,
    );
  }
}

class TplinkCgiService {
  TplinkCgiService._();

  static const _connect = Duration(seconds: 5);
  static const _read = Duration(seconds: 12);

  @visibleForTesting
  static String Function(String host) baseFor = (h) => 'http://$h';

  static final _issues = <String, ({CgiIssue issue, String trace, DateTime at})>{};
  static final _rejected = <String, Set<String>>{};
  static final _rnd = Random.secure();

  static ({CgiIssue issue, String trace})? lastIssue(String host) {
    final i = _issues[host.trim()];
    return i == null ? null : (issue: i.issue, trace: i.trace);
  }

  static void forget(String host) {
    _issues.remove(host.trim());
    _rejected.remove(host.trim());
  }

  static void reset() {
    _issues.clear();
    _rejected.clear();
  }

  static void _note(String host, CgiIssue issue, String trace) => _issues[host] = (issue: issue, trace: trace, at: DateTime.now());

  /// للأدوات الحيّة: أثر الخطوات (حالة HTTP وأطوالٌ ورموز — بلا قيمٍ حسّاسة).
  @visibleForTesting
  static List<String>? trace;

  /// RSA بلا حشو كصفحة الجهاز (`nopadding`): قطعٌ [chunk] حرفاً، النصّ في أعلى البايتات ثمّ أصفار، كلّ قطعة هكسٌ بطول المفتاح.
  @visibleForTesting
  static String rsaNoPad(String text, String nHex, String eHex, {int chunk = 64}) {
    final n = BigInt.parse(nHex, radix: 16);
    final e = BigInt.parse(eHex, radix: 16);
    final keyLen = (n.bitLength + 7) >> 3;
    final sb = StringBuffer();
    for (var i = 0; i < text.length; i += chunk) {
      final part = utf8.encode(text.substring(i, min(i + chunk, text.length)));
      final bytes = List<int>.filled(keyLen, 0)..setRange(0, min(part.length, keyLen), part);
      var m = BigInt.zero;
      for (final b in bytes) {
        m = (m << 8) | BigInt.from(b);
      }
      sb.write(m.modPow(e, n).toRadixString(16).padLeft(keyLen * 2, '0'));
    }
    return sb.toString();
  }

  /// مفتاح/IV كما يولّدهما الجهاز (ستّة عشر حرفاً من الوقت وعشوائيّ) — أرقامٌ هنا.
  static String _k16() => List.generate(16, (_) => _rnd.nextInt(10)).join();

  /// طلبٌ على اتّصال الجلسة ([conn]) كالمتصفّح حرفاً (سُجّل حيّاً بواجهة الجهاز نفسها: HTTP/1.1 keep-alive + Origin/Referer/Accept/
  /// User-Agent). حيّاً: التعمية والتوقيع مطابقان بايتاً لصفحة الجهاز ومع ذلك القراءة 500 على اتّصالٍ جديدٍ لكلّ طلب — الجهاز يربط الجلسة
  /// المعمّاة بالاتّصال. وقد يعلن `chunked` ثمّ يرسل صفحة خطأٍ بلا أطوال (HttpClient يرمي ويضيع الخروج) — [_KaConn] يتحمّلها.
  static Future<({int status, Map<String, List<String>> headers, String body})?> _post(String host, String path, String body,
      {String? cookie, String method = 'POST', _KaConn? conn}) async {
    final base = Uri.parse(baseFor(host));
    final c = conn ?? _KaConn(base.host, base.hasPort ? base.port : 80);
    try {
      final bytes = method == 'GET' ? const <int>[] : utf8.encode(body);
      final head = StringBuffer()
        ..write('$method $path HTTP/1.1\r\n')
        ..write('Host: ${base.authority}\r\n')
        ..write('Accept: */*\r\n')
        ..write('User-Agent: Mozilla/5.0\r\n')
        ..write('Referer: ${base.scheme}://${base.authority}/\r\n');
      if (method != 'GET') {
        head
          ..write('Origin: ${base.scheme}://${base.authority}\r\n')
          ..write('Content-Type: text/plain\r\n')
          ..write('Content-Length: ${bytes.length}\r\n');
      }
      if (cookie != null && cookie.isNotEmpty) head.write('Cookie: $cookie\r\n');
      head.write('Connection: ${conn == null ? 'close' : 'keep-alive'}\r\n\r\n');
      final r = await c.send([...utf8.encode(head.toString()), ...bytes]);
      if (r == null) return null;
      return (status: r.status, headers: r.headers, body: utf8.decode(r.body, allowMalformed: true));
    } catch (e) {
      trace?.add('post $path error ${e.runtimeType}: ${e.toString().split('\n').first}');
      await c.close();
      return null;
    } finally {
      if (conn == null) await c.close();
    }
  }

  static Future<bool> detect(String host) async {
    final base = baseFor(host.trim());
    final client = HttpClient()..connectionTimeout = _connect;
    try {
      final req = await client.getUrl(Uri.parse('$base/')).timeout(_connect);
      req.followRedirects = false;
      final res = await req.close().timeout(_read);
      final body = utf8.decode(await res.fold<List<int>>(<int>[], (a, b) => a..addAll(b)).timeout(_read), allowMalformed: true);
      return res.statusCode == 200 && body.contains('INCLUDE_LOGIN_GDPR_ENCRYPT') && body.contains('/cgi/getParm');
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// طلبٌ واحد معمّى ⇒ النصّ المفكوك، وإلّا null.
  static Future<({String text, String cookie})?> _gdpr(
      String host, String plain, ({String nn, String ee, int seq, String key, String iv, String hash}) k, {required bool login, String cookie = '', _KaConn? conn}) async {
    final data = AgileCrypto.aesEncrypt(plain, k.key, k.iv);
    final sigPlain = login ? 'key=${k.key}&iv=${k.iv}&h=${k.hash}&s=${k.seq + data.length}' : 'h=${k.hash}&s=${k.seq + data.length}';
    final sign = rsaNoPad(sigPlain, k.nn, k.ee);
    final r = await _post(host, '/cgi_gdpr', 'sign=$sign\r\ndata=$data\r\n', cookie: cookie, conn: conn);
    trace?.add('gdpr login=$login http=${r?.status} len=${r?.body.length} setCookie=${r?.headers['set-cookie']?.length ?? 0} sentCookie=${cookie.isNotEmpty}');
    if (r == null) return null;
    final jar = mergeCookies(cookie, r.headers['set-cookie'] ?? const <String>[]);
    trace?.add('cookies ${(r.headers['set-cookie'] ?? const []).map((c) => '${c.split('=').first}${RegExp(r'expires=[^;]*1970|max-age=0', caseSensitive: false).hasMatch(c) ? '(expired)' : ''}').join(',')} ⇒ ${jar.isEmpty ? '-' : jar.split(';').map((p) => p.split('=').first.trim()).join(',')}');
    var text = r.body.trim();
    try {
      text = AgileCrypto.aesDecrypt(text, k.key, k.iv);
    } catch (_) {
      // ردٌّ صريح (خطأ قبل التعمية)
    }
    return (text: text, cookie: jar);
  }

  /// جرّة كوكي صغيرة كالمتصفّح: Set-Cookie منتهٍ (Expires 1970 / Max-Age=0 — الجهاز يمسح بها الجلسة) يحذف الاسم، وغيره يضعه.
  /// حيّاً: الجهاز يرسل `JSESSIONID=…; Expires=Thu, 01 Jan 1970` حذفاً — إرساله ثانيةً كان يجعل كلّ قراءةٍ 500.
  @visibleForTesting
  static String mergeCookies(String current, List<String> setCookies) {
    final jar = <String, String>{};
    for (final p in current.split(';')) {
      final kv = p.trim();
      final eq = kv.indexOf('=');
      if (eq > 0) jar[kv.substring(0, eq)] = kv.substring(eq + 1);
    }
    for (final c in setCookies) {
      final parts = c.split(';');
      final kv = parts.first.trim();
      final eq = kv.indexOf('=');
      if (eq <= 0) continue;
      final name = kv.substring(0, eq);
      final attrs = parts.skip(1).map((a) => a.trim().toLowerCase()).toList();
      final expired = attrs.any((a) => a == 'max-age=0' || (a.startsWith('expires=') && a.contains('1970')));
      if (expired) {
        jar.remove(name);
      } else {
        jar[name] = kv.substring(eq + 1);
      }
    }
    return jar.entries.map((e) => '${e.key}=${e.value}').join('; ');
  }

  static String _act(String types, List<String> blocks) => '$types\r\n${blocks.join()}';

  static String block(String oid, int index, List<String> attrs, {String stack = '0,0,0,0,0,0', String pStack = '0,0,0,0,0,0'}) =>
      '[$oid#$stack#$pStack]$index,${attrs.length}\r\n${attrs.map((a) => '$a\r\n').join()}';

  /// الحالة: الجهاز (GET)، اتّصالات PPP وIP (قائمة)، مضيفو LAN (قائمة)، محطّات الوايرلس (عبر كلّ الشبكات).
  static String readActions() => _act('1&5&5&5&6', [
        block('IGD_DEV_INFO', 0, ['modelName', 'hardwareVersion', 'softwareVersion', 'upTime']),
        block('WAN_PPP_CONN', 1, ['enable', 'connectionStatus', 'uptime', 'externalIPAddress']),
        block('WAN_IP_CONN', 2, ['enable', 'connectionStatus', 'uptime', 'externalIPAddress', 'addressingType']),
        block('LAN_HOST_ENTRY', 3, ['IPAddress', 'MACAddress', 'hostName', 'leaseTimeRemaining']),
        block('LAN_WLAN_ASSOC_DEV', 4, ['associatedDeviceMACAddress']),
      ]);

  /// دخول ⇒ [fn] ⇒ خروجٌ دائماً. null ⇒ السبب في [lastIssue].
  static Future<T?> _withSession<T>(String host, String user, String pass, Future<T?> Function(Future<String?> Function(String plain) send) fn) async {
    final h = host.trim();
    final remembered = '${user.hashCode}:${pass.hashCode}';
    if (_rejected[h]?.contains(remembered) ?? false) {
      _note(h, CgiIssue.rejected, 'remembered');
      return null;
    }
    final base = Uri.parse(baseFor(h));
    final conn = _KaConn(base.host, base.hasPort ? base.port : 80);
    try {
      return await _session<T>(h, user, pass, remembered, conn, fn);
    } finally {
      await conn.close();
    }
  }

  static Future<T?> _session<T>(String h, String user, String pass, String remembered, _KaConn conn,
      Future<T?> Function(Future<String?> Function(String plain) send) fn) async {
    final p = await _post(h, '/cgi?8', '[/cgi/getParm#0,0,0,0,0,0#0,0,0,0,0,0]0,0\r\n', conn: conn);
    if (p == null) {
      _note(h, CgiIssue.unreachable, 'getParm no-reply');
      return null;
    }
    final v = CgiParse.vars(p.body);
    final seq = int.tryParse(v['seq'] ?? '');
    if ((v['nn'] ?? '').isEmpty || (v['ee'] ?? '').isEmpty || seq == null) {
      _note(h, CgiIssue.readFailed, 'getParm without key');
      return null;
    }
    final k = (nn: v['nn']!, ee: v['ee']!, seq: seq, key: _k16(), iv: _k16(), hash: crypto.md5.convert(utf8.encode('$user$pass')).toString());
    final login = await _gdpr(h, _act('8', [block('/cgi/login', 0, ['username=$user', 'password=$pass'])]), k, login: true, conn: conn);
    if (login == null) {
      _note(h, CgiIssue.unreachable, 'login no-reply');
      return null;
    }
    final err = CgiParse.errorCode(login.text);
    trace?.add('login err=$err textLen=${login.text.length} head=${login.text.length > 12 ? login.text.substring(0, 12) : login.text}');
    if (err != 0) {
      if (err == null) {
        _note(h, CgiIssue.readFailed, 'login reply unreadable');
      } else {
        (_rejected[h] ??= <String>{}).add(remembered);
        _note(h, CgiIssue.rejected, 'login error $err');
      }
      return null;
    }
    var cookie = login.cookie;
    // المتصفّح بعد الدخول يفتح «/» بالكوكي قبل أيّ قراءة (حيّاً: القراءة بدونه 500) — كذلك نحن.
    final landing = await _post(h, '/', '', cookie: cookie, method: 'GET', conn: conn);
    trace?.add('landing http=${landing?.status} len=${landing?.body.length}');
    Future<String?> send(String plain) async {
      final r = await _gdpr(h, plain, k, login: false, cookie: cookie, conn: conn);
      if (r == null) return null;
      cookie = r.cookie;
      return r.text;
    }

    try {
      return await fn(send);
    } finally {
      try {
        await send(_act('8', [block('/cgi/logout', 0, const [])]));
      } catch (_) {
        // أفضل جهد
      }
    }
  }

  @visibleForTesting
  static Future<String?> debugRead(String host, String user, String pass, String plain) =>
      _withSession<String>(host, user, pass, (send) => send(plain));

  static Future<UbiquitiStatus?> readOnce(String host, String user, String pass) =>
      _withSession<UbiquitiStatus>(host, user, pass, (send) async {
        final h = host.trim();
        final text = await send(readActions());
        if (text == null) {
          _note(h, CgiIssue.unreachable, 'read no-reply');
          return null;
        }
        final snap = CgiParse.status(CgiParse.objects(text), baseUrl: baseFor(h));
        if (snap == null) {
          _note(h, CgiIssue.readFailed, 'read error ${CgiParse.errorCode(text)}');
          return null;
        }
        _issues.remove(h);
        return snap;
      });
}
