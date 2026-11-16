import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show md5;
import 'package:flutter/foundation.dart';

import 'snmp_client.dart';

/// ONU كما تعرضها صفحة أولت HSGQ (`/onu_allow_list?port_id=N`).
@immutable
class HsgqWebOnu {
  const HsgqWebOnu({required this.pon, required this.onu, required this.online, this.mac, this.name});

  final int pon;
  final int onu;
  final bool online;

  /// «9C:28:EF:68:25:52».
  final String? mac;
  final String? name;
}

/// **أولت HSGQ ببرمجيّةٍ قديمة: قائمة الـONU من صفحته لا من SNMP.**
///
/// ١٦ نوفمبر — المالك: «اولتي HGSC… شوفلي كيف ممكن نضيفه للنظام» ثمّ «هو بي ssh وتنلنت… سوي قارئ ويب وشوف ياطريقة سريعه
/// وتفيدنا». أولت حساب 1674 (HSGQ-E04، 4 PON · 8 GE، برمجيّة `HSGQ-E04_I_V3.0.18_Rel` من 2021): الـSNMP يُعرف HSGQ
/// (`sysObjectID` 50224) ويعطي المنافذ وضوء الـONU المتّصلة بموضعها (`.3.3.3.1`)، لكنّ **جدول الـONU نفسه غائب**
/// (`.3.3.2.1.*` = noSuchObject، وIF-MIB ‏١٢ واجهة بلا ONU) — فلا ماك ولا اسم ولا حالة، وكان التطبيق يعرض أولتاً بلا مشتركين.
/// أولت المالك الآخر (V3.1.20C) فيه الجدول ويُقرأ كما كان.
///
/// المقاس على الجهاز نفسه عبر VPN ‏(١٤٥ مللي): الويب يعطي قائمة كلّ منفذ (الاسم، الماك، الحالة…) — ١٢٣ ONU في ٢٫٣ ث بعد دخولٍ
/// ‏٠٫٦ ث؛ وصفحة ضوء كلّ ONU بطيئة (٣١ ث — الأولت يسأل كلّ ONU لحظتها)، والـSNMP يقرأ الضوء نفسه أسرع (٥٩ ONU بخمسة أعمدة
/// في ٤ ث) ⇒ **القائمة من الويب والضوء من SNMP كما كان**. Telnet يحتاج ٨ ث للاتّصال وحده وأوامر الـONU في وضع الإعداد،
/// والـSSH مقفل — فلا يُستعملان.
///
/// **كيف يدخل بلا تغيير القرّاء:** [fill] خطّافٌ بعد كلّ GET ‏([SnmpV2c.afterGet]): ما ردّه الأولت «noSuchObject» تحت جدول
/// الـONU يُملأ من القائمة — الحالة (`.8` = 1/2) والماك (`.7`) والاسم (`.2`)، والموضع بلا ONU «noSuchInstance» كما يردّ الأولت
/// الأحدث. فاللوحة والنظرة وشبكة الألياف ووضع الفنّي تقرأ [HsgqOlt] نفسه. لا يعمل إلّا لعنوانٍ سُجّل له دخول ([register]).
///
/// الدخول من كود الصفحة نفسها: `POST /userlogin?form=login`
/// `{method:"set", param:{name, key: md5("name:pass"), value: base64(pass), captcha_v:"", captcha_f:""}}` ⇒ `code 1` وترويسة
/// `x-token`، وكلّ طلبٍ بعدها بترويسة `X-Token`. دخولان معاً لا يُخرج أحدهما الآخر (مقيس) — فالتطبيق لا يطرد من يفتح الصفحة.
///
/// ⛔ **قراءة وحدها**: في الصفحة نفسها طلبات GET تُعيد التشغيل (`/system_reboot`) وتمسح الإعداد (`/system_def_config`) وتحفظه
/// (`/system_save`) — لا يُطلب هنا إلّا ما في [_readPaths] والدخول.
class HsgqWeb {
  HsgqWeb._();

  /// جدول الـONU في تخطيط HSGQ ‏(NSCRTV-EPON-ONU-MIB تحت 50224).
  static const onuTable = '1.3.6.1.4.1.50224.3.3.2.1';

  static const _readPaths = {'/board?info=pon', '/onu_allow_list'};

  /// القائمة تُقرأ مرّةً لكلّ نافذةٍ قصيرة — دفعات GET المتتالية في القراءة الواحدة لا تعيد طلبها.
  @visibleForTesting
  static Duration tableTtl = const Duration(seconds: 15);

  /// دخولٌ رُفض لا يُعاد بالكلمة نفسها قبل هذا (لا قفلٌ على حساب الوكيل من محاولاتٍ متكرّرة).
  static const rejectedBackoff = Duration(minutes: 10);

  @visibleForTesting
  static Duration timeout = const Duration(seconds: 8);

  /// عنوان الطلب — للاختبار (خادمٌ محلّيّ بمنفذٍ آخر).
  @visibleForTesting
  static Uri Function(String host, String pathAndQuery) urlFor = (h, p) => Uri.parse('http://$h$p');

  static final _logins = <String, ({String user, String pass})>{};
  static final _tokens = <String, String>{};
  static final _tables = <String, ({DateTime at, Map<int, HsgqWebOnu> rows})>{};
  static final _fetching = <String, Future<Map<int, HsgqWebOnu>?>>{};
  static final _rejected = <String, ({String user, String pass, DateTime at})>{};

  /// آخر سببٍ تعذّرت به القائمة لعنوانٍ (للرسالة) — يُمسح بالنجاح.
  static final _issues = <String, String>{};

  /// عدد طلبات الدخول (للاختبار).
  @visibleForTesting
  static int logins = 0;

  /// يسجّل دخول صفحة أولتٍ لعنوانه — من بيانات الجهاز المحفوظة (`web_user` / `web_pass`). فارغٌ ⇒ يُنسى.
  static void register(String host, Object? user, Object? pass) {
    final u = (user ?? '').toString().trim();
    final p = (pass ?? '').toString();
    if (host.isEmpty) return;
    if (u.isEmpty || p.isEmpty) {
      _forget(host);
      return;
    }
    final old = _logins[host];
    if (old != null && old.user == u && old.pass == p) return;
    _forget(host);
    _logins[host] = (user: u, pass: p);
    SnmpV2c.afterGet ??= fill;
    SnmpV2c.beforeGet ??= answer;
  }

  /// من بيانات جهازٍ كما يُرجعها الخادم.
  static void registerFrom(String host, Map<String, dynamic> creds) => register(host, creds['web_user'], creds['web_pass']);

  static bool has(String host) => _logins.containsKey(host);

  /// لماذا لم تُقرأ القائمة آخر مرّة — `null` = لا مشكلة معروفة.
  static String? issueFor(String host) => _issues[host];

  static void _forget(String host) {
    _logins.remove(host);
    _tokens.remove(host);
    _tables.remove(host);
    _rejected.remove(host);
    _issues.remove(host);
    _failedAt.remove(host);
    _absentAt.remove(host);
  }

  @visibleForTesting
  static void resetForTest() {
    _logins.clear();
    _tokens.clear();
    _tables.clear();
    _fetching.clear();
    _rejected.clear();
    _issues.clear();
    _failedAt.clear();
    _absentAt.clear();
    logins = 0;
    timeout = const Duration(seconds: 8);
    tableTtl = const Duration(seconds: 15);
    urlFor = (h, p) => Uri.parse('http://$h$p');
    if (SnmpV2c.afterGet == fill) SnmpV2c.afterGet = null;
    if (SnmpV2c.beforeGet == answer) SnmpV2c.beforeGet = null;
  }

  // ═══════════════════════════════════════════════════════════
  // الخطّاف — يملأ جدول الـONU الغائب
  // ═══════════════════════════════════════════════════════════

  static bool _missing(Varbind vb) => vb.rawTag == 0x80 && vb.oid.startsWith('$onuTable.');

  /// بعد كلّ GET: noSuchObject تحت [onuTable] لعنوانٍ له دخول ⇒ من القائمة. فشلت القائمة ⇒ يبقى كما ردّ الأولت (فيقول
  /// القارئ «لا جدول» بسببه — [issueFor]) لا أرقامٌ مخترعة.
  static Future<List<Varbind>> fill(String host, List<Varbind> vbs) async {
    if (!_logins.containsKey(host) || !vbs.any(_missing)) return vbs;
    _absentAt[host] = DateTime.now();
    final rows = await table(host);
    if (rows == null) return vbs;
    return [for (final vb in vbs) _missing(vb) ? virtualOf(vb.oid, rows) : vb];
  }

  /// قبل الإرسال ([SnmpV2c.beforeGet]): أولتٌ عُرف أنّ جدول الـONU غائبٌ عنه (ردّ «noSuchObject» خلال [absentFor]) ودفعةٌ كلّها من
  /// ذلك الجدول ⇒ تُجاب من القائمة بلا رحلةٍ إلى الجهاز. غير ذلك (أوّل دفعة، أو دفعةٌ مختلطة، أو قائمةٌ تعذّرت) ⇒ `null`
  /// فيُرسل الطلب كما هو — وما يقوله الأولت حينها هو الحَكَم.
  static Future<List<Varbind>?> answer(String host, List<String> oids) async {
    final at = _absentAt[host];
    if (at == null || !_logins.containsKey(host) || DateTime.now().difference(at) > absentFor) return null;
    if (oids.isEmpty || !oids.every((o) => o.startsWith('$onuTable.'))) return null;
    final rows = await table(host);
    if (rows == null) return null;
    return [for (final o in oids) virtualOf(o, rows)];
  }

  /// كم يُصدَّق «الجدول غائب» قبل أن يُسأل الأولت نفسه من جديد (ترقيةٌ لبرمجيّته تُكتشف وحدها).
  static const absentFor = Duration(minutes: 10);
  static final _absentAt = <String, DateTime>{};

  static Varbind _absent(String oid) => Varbind(oid: oid, rawTag: 0x81, rawBytes: Uint8List(0));

  /// قيمة عمودٍ من جدول الـONU كما كان سيردّها أولتٌ فيه الجدول (نقيّ — للاختبار): الحالة 1 متّصل / 2 مفصول، والماك ستّة
  /// بايتات، والاسم نصّاً؛ الموضع بلا ONU أو عمودٌ لا تعرفه الصفحة (الصانع والطراز…) «noSuchInstance».
  @visibleForTesting
  static Varbind virtualOf(String oid, Map<int, HsgqWebOnu> rows) {
    final rest = oid.substring(onuTable.length + 1).split('.');
    if (rest.length != 2) return _absent(oid);
    final col = int.tryParse(rest[0]);
    final idx = int.tryParse(rest[1]);
    final row = idx == null ? null : rows[idx];
    if (row == null) return _absent(oid);
    switch (col) {
      case 8:
        return Varbind(oid: oid, rawTag: 0x02, rawBytes: Uint8List.fromList([row.online ? 1 : 2]));
      case 7:
        final b = macBytes(row.mac);
        return b == null ? _absent(oid) : Varbind(oid: oid, rawTag: 0x04, rawBytes: b);
      case 2:
        final n = row.name;
        return (n == null || n.isEmpty) ? _absent(oid) : Varbind(oid: oid, rawTag: 0x04, rawBytes: Uint8List.fromList(utf8.encode(n)));
      default:
        return _absent(oid);
    }
  }

  /// «9c:28:ef:68:25:52» ← ستّة بايتات؛ ماكٌ أصفارٌ كلّه أو مكسور `null`.
  @visibleForTesting
  static Uint8List? macBytes(String? mac) {
    if (mac == null) return null;
    final hex = mac.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (hex.length != 12) return null;
    final b = Uint8List(6);
    for (var i = 0; i < 6; i++) {
      b[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return b.every((x) => x == 0) ? null : b;
  }

  /// فهرس الـONU في جداول HSGQ: ‏`0x01000000 | منفذ<<8 | رقم` ([HsgqOlt.onuIndex] نفسه).
  static int indexOf(int pon, int onu) => 0x01000000 | (pon << 8) | onu;

  /// صفٌّ من `/onu_allow_list` ⇒ ONU (نقيّ — للاختبار). «Online» وحدها متّصلة؛ «Offline» و«Initial» (لم تكمل التسجيل) و
  /// غيرهما مفصولة.
  @visibleForTesting
  static HsgqWebOnu? onuFrom(Map<String, dynamic> r, int pon) {
    final id = int.tryParse('${r['onu_id'] ?? ''}');
    final port = int.tryParse('${r['port_id'] ?? pon}') ?? pon;
    if (id == null || id < 1 || id > 255 || port < 1 || port > 255) return null;
    final name = '${r['onu_name'] ?? ''}'.trim();
    final mac = '${r['macaddr'] ?? ''}'.trim();
    return HsgqWebOnu(
      pon: port,
      onu: id,
      online: '${r['status'] ?? ''}'.trim().toLowerCase() == 'online',
      mac: mac.isEmpty ? null : mac,
      name: name.isEmpty ? null : name,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // القائمة
  // ═══════════════════════════════════════════════════════════

  /// كلّ ONU بفهرسها — من النسخة المخبّأة إن كانت أحدث من [tableTtl]، وإلّا طلبٌ واحد لكلّ عنوانٍ مهما تزاحمت الدفعات.
  /// `null` = تعذّرت (السبب في [issueFor]).
  static Future<Map<int, HsgqWebOnu>?> table(String host) {
    final c = _tables[host];
    if (c != null && DateTime.now().difference(c.at) < tableTtl) return Future.value(c.rows);
    // فشلٌ قريب (مهلة، منفذٌ مغلق) لا يُعاد في القراءة نفسها — كلّ دفعة GET كانت ستنتظر مهلةً كاملة.
    final f = _failedAt[host];
    if (f != null && DateTime.now().difference(f) < failureBackoff) return Future.value(null);
    // ⚠️ جسمٌ لا يُرجع شيئاً: `() => _fetching.remove(host)` يُرجع هذا الوعد نفسه فينتظر `whenComplete` نفسه إلى الأبد
    // (القفل الذاتيّ نفسه الذي أوقف أوّل فحصٍ لكلّ راوتر — مهارة pro-subscriber-cpe §2).
    return _fetching[host] ??= _fetchTable(host).then((rows) {
      if (rows == null) {
        _failedAt[host] = DateTime.now();
      } else {
        _failedAt.remove(host);
      }
      return rows;
    }).whenComplete(() {
      _fetching.remove(host);
    });
  }

  /// بعد فشلٍ لا تُسأل الصفحة ثانيةً قبل هذا.
  static const failureBackoff = Duration(seconds: 30);
  static final _failedAt = <String, DateTime>{};

  static Future<Map<int, HsgqWebOnu>?> _fetchTable(String host) async {
    try {
      final pon = await _authed(host, '/board?info=pon');
      if (pon == null) return null;
      final ports = <int>[
        for (final p in (pon['data'] is List ? pon['data'] as List : const []))
          if (p is Map && int.tryParse('${p['port_id']}') != null) int.parse('${p['port_id']}'),
      ];
      if (ports.isEmpty) {
        _issues[host] = 'صفحة الأولت لم تذكر منافذ PON';
        return null;
      }
      final rows = <int, HsgqWebOnu>{};
      for (final port in ports) {
        final j = await _authed(host, '/onu_allow_list?port_id=$port');
        if (j == null) return null;
        for (final r in (j['data'] is List ? j['data'] as List : const [])) {
          if (r is! Map) continue;
          final o = onuFrom(r.cast<String, dynamic>(), port);
          if (o != null) rows[indexOf(o.pon, o.onu)] = o;
        }
      }
      _tables[host] = (at: DateTime.now(), rows: rows);
      _issues.remove(host);
      return rows;
    } on _WebIssue catch (e) {
      _issues[host] = e.message;
      return null;
    } catch (_) {
      // شكلٌ لم نره (حقلٌ بنوعٍ آخر…) — لا يُسقط القراءة ولا يُخترع منه شيء
      _issues[host] = 'صفحة الأولت ردّت بشيءٍ غير متوقّع';
      return null;
    }
  }

  /// يبدأ قراءة القائمة الآن ولا ينتظرها — القارئ يستدعيه أوّل القراءة فتتوازى الصفحة (~٣ ث) مع منافذ SNMP (~٣ ث) بدل أن
  /// تتتابعا. لعنوانٍ له دخولٌ محفوظ وحده (من حفظه أراده لهذا الأولت).
  static void prefetch(String host) {
    if (!_logins.containsKey(host)) return;
    unawaited(table(host).then((_) {}, onError: (_) {}));
  }

  /// GET بالرمز — رمزٌ منتهٍ («code» 0 أو ‎-1) ⇒ دخولٌ واحد ثمّ إعادة.
  static Future<Map<String, dynamic>?> _authed(String host, String path) async {
    assert(_readPaths.contains(path.split('?port_id=').first) || _readPaths.contains(path), path);
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = _tokens[host] ?? await _login(host);
      if (token == null) return null;
      final j = await _request(host, 'GET', path, token: token);
      final code = j.body['code'];
      if (code == 1) return j.body;
      _tokens.remove(host);
      if (code != 0 && code != -1) throw _WebIssue('ردّت صفحة الأولت برمز $code');
    }
    throw const _WebIssue('انتهت جلسة صفحة الأولت ولم يُقبل الدخول من جديد');
  }

  static Future<String?> _login(String host) async {
    final l = _logins[host];
    if (l == null) return null;
    final r = _rejected[host];
    if (r != null && r.user == l.user && r.pass == l.pass && DateTime.now().difference(r.at) < rejectedBackoff) {
      throw const _WebIssue('اسم المستخدم أو كلمة مرور صفحة الأولت غير صحيحة — عدّلها في إعدادات الجهاز');
    }
    logins++;
    final res = await _request(host, 'POST', '/userlogin?form=login', body: {
      'method': 'set',
      'param': {
        'name': l.user,
        'key': md5.convert(utf8.encode('${l.user}:${l.pass}')).toString(),
        'value': base64.encode(utf8.encode(l.pass)),
        'captcha_v': '',
        'captcha_f': '',
      },
    });
    final token = res.token;
    if (res.body['code'] == 1 && token != null && token.isNotEmpty) {
      _tokens[host] = token;
      _rejected.remove(host);
      return token;
    }
    _rejected[host] = (user: l.user, pass: l.pass, at: DateTime.now());
    throw const _WebIssue('اسم المستخدم أو كلمة مرور صفحة الأولت غير صحيحة — عدّلها في إعدادات الجهاز');
  }

  static Future<({Map<String, dynamic> body, String? token})> _request(
    String host,
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final req = await client.openUrl(method, urlFor(host, path)).timeout(timeout);
      req.headers.set(HttpHeaders.acceptHeader, 'application/json, text/plain, */*');
      if (token != null) req.headers.set('X-Token', token);
      if (body != null) {
        final bytes = utf8.encode(jsonEncode(body));
        req.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(timeout);
      final text = await res.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(text);
      if (decoded is! Map) throw const _WebIssue('صفحة الأولت ردّت بشيءٍ غير متوقّع');
      return (body: decoded.cast<String, dynamic>(), token: res.headers.value('x-token'));
    } on _WebIssue {
      rethrow;
    } on TimeoutException {
      throw const _WebIssue('صفحة الأولت لا تردّ (انتهت المهلة)');
    } on SocketException {
      throw const _WebIssue('صفحة الأولت لا تردّ (المنفذ 80 مغلق أو الجهاز بعيد)');
    } on FormatException {
      throw const _WebIssue('صفحة الأولت ردّت بشيءٍ غير متوقّع');
    } on HttpException {
      throw const _WebIssue('صفحة الأولت لا تردّ (قطعت الاتّصال)');
    } finally {
      client.close(force: true);
    }
  }
}

class _WebIssue implements Exception {
  const _WebIssue(this.message);
  final String message;
  @override
  String toString() => message;
}
