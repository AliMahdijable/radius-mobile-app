import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

/// طبقة قراءةٍ لسويتشات **Ubiquiti EdgeSwitch** عبر واجهة REST الرسميّة.
///
/// لماذا REST لا SSH — وقد كتبنا سسكو على SSH؟
/// EdgeSwitch يفتح `/api/v1.0/` كاملةً بصيغة JSON، وهي مصدر واجهته
/// الرسوميّة نفسها. فلا داعي لمحاكاة طرفيّةٍ ولا لملاحقة موجّهاتٍ ولا
/// لضخّ `--More--` كما في IOS. الاستطلاع أثبت المسارات من حزمة الواجهة
/// نفسها لا من التوثيق:
///   POST /api/v1.0/user/login     → رأس `x-auth-token`
///   GET  /api/v1.0/device         → الطراز والإصدار والـMAC
///   GET  /api/v1.0/system         → اسم المضيف والعنوان والبوّابة
///   GET  /api/v1.0/statistics     → المعالج والذاكرة والحرارة ومدّة التشغيل
///   GET  /api/v1.0/interfaces     → حالة المنافذ وسرعتها وPoE
///   POST /api/v1.0/system/reboot  → إعادة التشغيل
///
/// ⚠️ **`Referer` شرطٌ لا خيار.** فحصتُ الرؤوس واحداً واحداً على جهازٍ
/// فعليّ: بلا `Referer` يردّ lighttpd **403** قبل أن يقرأ الجسم أصلاً —
/// لا 401 ولا رسالة، فيبدو العطل كأنّه خطأ اعتماد. و`Origin` وحده لا
/// يكفي، ولا `X-Requested-With`، ولا وكيل متصفّح. هذا حارس CSRF في
/// EdgeSwitch وليس مصادقة.
///
/// وكلّ ما هنا **قراءةٌ فقط** عدا [reboot] — لا كتابة إعدادات ولا حفظ.
class EdgeSwitchApi {
  EdgeSwitchApi._();

  /// المنفذ الافتراضيّ. الجهاز يحوّل 80 إلى 443 بـ301، فنبدأ من المشفَّر.
  static const int defaultPort = 443;

  static Dio _dio(String host, int port) {
    // ⚠️ المنفذ الافتراضيّ يُحذف من الأصل عمداً.
    //
    // 🐛 الجهاز يقارن `Referer` بأصله **نصّيّاً** لا دلاليّاً. فحصتُه:
    //   Referer: https://10.64.100.3/      → 200
    //   Referer: https://10.64.100.3:443/  → 403
    // وهما المنفذ نفسه. فكتابة `:443` صراحةً تُفشل كلّ دخول، والعطل
    // يظهر كأنّه اعتمادٌ خاطئ لأنّ الردّ 403 بلا رسالة.
    final base = port == 443 ? 'https://$host' : 'https://$host:$port';
    final dio = Dio(BaseOptions(
      baseUrl: base,
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 12),
      validateStatus: (_) => true,
      headers: {
        'Accept': 'application/json, text/plain, */*',
        // انظر الشرح أعلاه — بدونه 403 دائماً.
        'Referer': '$base/',
      },
    ));
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final c = HttpClient();
      // شهادة الجهاز موقَّعةٌ ذاتيّاً — كحال كلّ معدّات الشبكة المحلّيّة.
      c.badCertificateCallback = (_, __, ___) => true;
      return c;
    };
    return dio;
  }

  /// يسجّل الدخول ويُعيد التوكن، أو `null` إن رُفض.
  ///
  /// التوكن يبقى في الذاكرة فقط — لا يُكتب في تخزينٍ ولا سجلّ.
  static Future<String?> login({
    required String host,
    required String user,
    required String pass,
    int port = defaultPort,
    Dio? dio,
  }) async {
    final d = dio ?? _dio(host, port);
    try {
      final r = await d.post<dynamic>(
        '/api/v1.0/user/login',
        data: {'username': user, 'password': pass},
        options: Options(contentType: Headers.jsonContentType),
      );
      if (r.statusCode != 200) return null;
      final tok = r.headers.value('x-auth-token');
      return (tok == null || tok.isEmpty) ? null : tok;
    } catch (e) {
      if (kDebugMode) debugPrint('EdgeSwitch.login: $e');
      return null;
    }
  }

  /// لقطةٌ كاملة. `null` يعني تعذّر الدخول أو انقطاع الاتّصال.
  static Future<EdgeSwitchStats?> fetchStats({
    required String host,
    required String user,
    required String pass,
    int port = defaultPort,
  }) async {
    final d = _dio(host, port);
    String? token;
    try {
      token = await login(host: host, user: user, pass: pass, port: port, dio: d);
      if (token == null) return null;
      final auth = Options(headers: {'x-auth-token': token});

      // الأربعة مستقلّة — نطلبها معاً فيصير الزمن أبطأها لا مجموعها.
      final res = await Future.wait([
        d.get<dynamic>('/api/v1.0/device', options: auth),
        d.get<dynamic>('/api/v1.0/system', options: auth),
        d.get<dynamic>('/api/v1.0/statistics', options: auth),
        d.get<dynamic>('/api/v1.0/interfaces', options: auth),
      ]);
      if (res.any((r) => r.statusCode != 200)) return null;

      return EdgeSwitchParse.stats(
        device: res[0].data,
        system: res[1].data,
        statistics: res[2].data,
        interfaces: res[3].data,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('EdgeSwitch.fetchStats: $e');
      return null;
    } finally {
      // نُنهي الجلسة على الجهاز بدل تركها تنتهي بالمهلة — الجهاز يحدّ
      // الجلسات المتزامنة، وفحصٌ دوريٌّ كلّ بضع ثوانٍ يستنزفها بسرعة.
      if (token != null) {
        try {
          await d.post<dynamic>('/api/v1.0/user/logout',
              options: Options(headers: {'x-auth-token': token}));
        } catch (_) {/* أفضل جهد */}
      }
      d.close(force: true);
    }
  }

  /// الطراز وحده — لكشف النوع عند إضافة الجهاز، بأقلّ تكلفة.
  static Future<String?> detectModel({
    required String host,
    required String user,
    required String pass,
    int port = defaultPort,
  }) async {
    final d = _dio(host, port);
    String? token;
    try {
      token = await login(host: host, user: user, pass: pass, port: port, dio: d);
      if (token == null) return null;
      final r = await d.get<dynamic>('/api/v1.0/device',
          options: Options(headers: {'x-auth-token': token}));
      if (r.statusCode != 200) return null;
      return EdgeSwitchParse.model(r.data);
    } catch (e) {
      if (kDebugMode) debugPrint('EdgeSwitch.detectModel: $e');
      return null;
    } finally {
      if (token != null) {
        try {
          await d.post<dynamic>('/api/v1.0/user/logout',
              options: Options(headers: {'x-auth-token': token}));
        } catch (_) {}
      }
      d.close(force: true);
    }
  }

  /// هل هذا العنوان EdgeSwitch أصلاً — بلا اعتماد.
  ///
  /// صفحة الجذر تحمل `<title>Ubiquiti EdgeSwitch</title>` قبل أيّ دخول.
  /// نستعملها للتمييز عن airOS الذي يشترك معه في المنفذ نفسه والعلامة
  /// نفسها (`ubnt`) لكنّه لا يعرف `/api/v1.0` إطلاقاً.
  static Future<bool> probe({
    required String host,
    int port = defaultPort,
  }) async {
    final d = _dio(host, port);
    try {
      final r = await d.get<dynamic>('/');
      if (r.statusCode != 200) return false;
      return EdgeSwitchParse.looksLikeEdgeSwitch(r.data?.toString() ?? '');
    } catch (_) {
      return false;
    } finally {
      d.close(force: true);
    }
  }

  /// إعادة تشغيل. **الكتابة الوحيدة في هذا الملفّ.**
  static Future<bool> reboot({
    required String host,
    required String user,
    required String pass,
    int port = defaultPort,
  }) async {
    final d = _dio(host, port);
    String? token;
    try {
      token = await login(host: host, user: user, pass: pass, port: port, dio: d);
      if (token == null) return false;
      final r = await d.post<dynamic>('/api/v1.0/system/reboot',
          options: Options(headers: {'x-auth-token': token}));
      // 200 أو 204 — الجهاز يقطع الاتّصال فوراً أحياناً قبل أن يردّ.
      return r.statusCode == 200 || r.statusCode == 204;
    } on DioException catch (e) {
      // انقطاعٌ بعد إرسال الأمر = الجهاز بدأ يُقلع فعلاً. نعدّه نجاحاً
      // لأنّ البديل إظهار خطأٍ لعمليّةٍ تمّت.
      final started = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.receiveTimeout;
      if (kDebugMode) debugPrint('EdgeSwitch.reboot: ${e.type}');
      return started;
    } catch (e) {
      if (kDebugMode) debugPrint('EdgeSwitch.reboot: $e');
      return false;
    } finally {
      d.close(force: true);
    }
  }
}

/// محلّلاتٌ **خالصة** — لا شبكة ولا حالة. كلّ ما هنا قابلٌ للاختبار
/// بلقطات JSON حقيقيّة بلا جهازٍ ولا اعتماد.
class EdgeSwitchParse {
  EdgeSwitchParse._();

  static bool looksLikeEdgeSwitch(String html) {
    final h = html.toLowerCase();
    return h.contains('ubiquiti edgeswitch') || h.contains('edgeswitch');
  }

  static String? model(dynamic device) {
    final id = _map(device)['identification'];
    if (id is! Map) return null;
    // `model` هو الرمز القصير (ES-24-250W) و`product` هو الاسم الطويل.
    // نُفضّل القصير لأنّ مطابقة الصور في `DeviceImage` تقوم عليه.
    final m = id['model']?.toString().trim();
    if (m != null && m.isNotEmpty) return m;
    final p = id['product']?.toString().trim();
    return (p == null || p.isEmpty) ? null : p;
  }

  static EdgeSwitchStats? stats({
    required dynamic device,
    required dynamic system,
    required dynamic statistics,
    required dynamic interfaces,
  }) {
    final dev = _map(device);
    final sys = _map(system);
    final id = dev['identification'] is Map
        ? dev['identification'] as Map
        : const {};

    // `statistics` مصفوفةٌ من لقطة واحدة — لا سلسلة زمنيّة. نأخذ الأولى.
    final snap = (statistics is List && statistics.isNotEmpty)
        ? _map(statistics.first)
        : const <String, dynamic>{};
    final d = snap['device'] is Map ? snap['device'] as Map : const {};

    // عدّادات المنافذ تأتي في `statistics` لا في `interfaces` — نفهرسها
    // بالمعرّف ثمّ ندمجها مع الحالة أدناه.
    final byId = <String, Map>{};
    final si = snap['interfaces'];
    if (si is List) {
      for (final e in si) {
        final m = _map(e);
        final k = m['id']?.toString();
        if (k != null) byId[k] = m;
      }
    }

    final ports = <EdgeSwitchPort>[];
    if (interfaces is List) {
      for (final e in interfaces) {
        final p = _port(_map(e), byId);
        if (p != null) ports.add(p);
      }
    }
    ports.sort(_byPortIndex);

    return EdgeSwitchStats(
      model: id['model']?.toString(),
      product: id['product']?.toString(),
      firmware: id['firmwareVersion']?.toString(),
      mac: id['mac']?.toString(),
      hostname: sys['hostname']?.toString(),
      address: _mgmtAddress(sys),
      gateway: _gateway(sys),
      uptimeSeconds: _int(d['uptime']),
      cpuPercent: _cpu(d['cpu']),
      ramPercent: _num(_map(d['ram'])['usage']),
      ramFreeBytes: _int(_map(d['ram'])['free']),
      ramTotalBytes: _int(_map(d['ram'])['total']),
      temperatureC: _topTemp(d['temperatures']),
      fanSpeeds: _fans(d['fanSpeeds']),
      ports: ports,
    );
  }

  /// يبني منفذاً واحداً، أو `null` لما ليس منفذاً فيزيائيّاً.
  ///
  /// الجهاز يُرجع ٣٢ مدخلاً لسويتشٍ ذي ٢٤ منفذاً: المنافذ، ومجموعات
  /// LAG، وواجهات VLAN. عرضها كلّها في «خريطة المنافذ» يجعل اللوحة
  /// تكذب على العين — فنُبقي `type == 'port'` وحدها.
  static EdgeSwitchPort? _port(Map e, Map<String, Map> byId) {
    final ident = _map(e['identification']);
    if (ident['type']?.toString() != 'port') return null;
    final pid = ident['id']?.toString();
    if (pid == null || pid.isEmpty) return null;

    final st = _map(e['status']);
    final pr = _map(e['port']);
    final sx = _map(byId[pid]?['statistics']);

    // `plugged` هو الكابل، و`enabled` هو الإدارة. منفذٌ مُعطَّلٌ إداريّاً
    // وفيه كابل ليس «يعمل» — والعكس كذلك. نحتاجهما منفصلَين ليُقرأ
    // سبب الانقطاع من اللوحة بلا فتح الجهاز.
    return EdgeSwitchPort(
      id: pid,
      name: (ident['name']?.toString().trim().isEmpty ?? true)
          ? null
          : ident['name'].toString().trim(),
      enabled: st['enabled'] == true,
      plugged: st['plugged'] == true,
      speed: _speed(st['currentSpeed']?.toString()),
      speedRaw: st['currentSpeed']?.toString(),
      description: (st['description']?.toString().trim().isEmpty ?? true)
          ? null
          : st['description'].toString().trim(),
      poe: pr['poe']?.toString(),
      poeWatts: _num(sx['poePower']),
      txRate: _int(sx['txRate']),
      rxRate: _int(sx['rxRate']),
      txBytes: _int(sx['txBytes']),
      rxBytes: _int(sx['rxBytes']),
      errors: _int(sx['errors']),
    );
  }

  /// «1000-full» → 1000. و«10000-full» → 10000 — لا 10.
  ///
  /// 🐛 المصيدة نفسها التي وقعنا فيها مع سسكو: أخذُ أوّل رقمين يحوّل
  /// جيجابت عشرةً إلى عشرة ميجابت، فيظهر منفذٌ سليم كأنّه منهار.
  static int? _speed(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final m = RegExp(r'^(\d+)').firstMatch(raw);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  static int _byPortIndex(EdgeSwitchPort a, EdgeSwitchPort b) {
    // المعرّف «0/1» … «0/24» — الترتيب النصّيّ يضع ١٠ قبل ٢، فنرتّب رقميّاً.
    int idx(String s) {
      final m = RegExp(r'(\d+)\s*$').firstMatch(s);
      return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
    }

    return idx(a.id).compareTo(idx(b.id));
  }

  static String? _mgmtAddress(Map sys) {
    final mg = _map(sys['management']);
    final addrs = mg['addresses'];
    if (addrs is! List) return null;
    for (final a in addrs) {
      final m = _map(a);
      if (m['version'] == 'v4') return m['cidr']?.toString();
    }
    return null;
  }

  static String? _gateway(Map sys) {
    final g = sys['defaultGateway'];
    if (g is! List) return null;
    for (final e in g) {
      final m = _map(e);
      if (m['version'] == 'v4') return m['address']?.toString();
    }
    return null;
  }

  static num? _cpu(dynamic cpu) {
    if (cpu is! List || cpu.isEmpty) return null;
    // متعدّد النوى ممكن — نأخذ الأعلى لأنّ نواةً مختنقةً تُبطئ الجهاز
    // ولو كان المتوسّط هادئاً.
    num? top;
    for (final c in cpu) {
      final u = _num(_map(c)['usage']);
      if (u != null && (top == null || u > top)) top = u;
    }
    return top;
  }

  /// أعلى حرارةٍ مقيسة. الجهاز يُرجع مجسّاتٍ كثيرة (لوحة + كلّ زوج PoE)،
  /// والرقم الذي يهمّ المشغّل هو الأسخن لا المتوسّط.
  static num? _topTemp(dynamic temps) {
    if (temps is! List) return null;
    num? top;
    for (final t in temps) {
      final v = _num(_map(t)['value']);
      if (v != null && (top == null || v > top)) top = v;
    }
    return top;
  }

  static List<int> _fans(dynamic fans) {
    if (fans is! List) return const [];
    final out = <int>[];
    for (final f in fans) {
      final v = _int(_map(f)['value']);
      if (v != null) out.add(v);
    }
    return out;
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : const <String, dynamic>{};

  static int? _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  static num? _num(dynamic v) {
    if (v is num) return v;
    return num.tryParse(v?.toString() ?? '');
  }
}

/// منفذٌ فيزيائيّ واحد.
@immutable
class EdgeSwitchPort {
  const EdgeSwitchPort({
    required this.id,
    this.name,
    required this.enabled,
    required this.plugged,
    this.speed,
    this.speedRaw,
    this.description,
    this.poe,
    this.poeWatts,
    this.txRate,
    this.rxRate,
    this.txBytes,
    this.rxBytes,
    this.errors,
  });

  final String id;
  final String? name;

  /// مُفعَّلٌ إداريّاً.
  final bool enabled;

  /// فيه كابلٌ حيّ.
  final bool plugged;

  /// ميجابت/ثانية.
  final int? speed;
  final String? speedRaw;
  final String? description;

  /// «off» / «active» / «passive24v» … حسب قدرات الجهاز.
  final String? poe;
  final num? poeWatts;

  final int? txRate;
  final int? rxRate;
  final int? txBytes;
  final int? rxBytes;
  final int? errors;

  /// «يعمل» = مُفعَّلٌ إداريّاً **و** فيه كابل.
  bool get up => enabled && plugged;

  /// الرقم وحده للعرض المختصر: «0/12» → «12».
  String get shortLabel {
    final m = RegExp(r'(\d+)\s*$').firstMatch(id);
    return m?.group(1) ?? id;
  }

  bool get poeActive => poe != null && poe != 'off' && (poeWatts ?? 0) > 0;
}

/// لقطةٌ كاملة للسويتش.
@immutable
class EdgeSwitchStats {
  const EdgeSwitchStats({
    this.model,
    this.product,
    this.firmware,
    this.mac,
    this.hostname,
    this.address,
    this.gateway,
    this.uptimeSeconds,
    this.cpuPercent,
    this.ramPercent,
    this.ramFreeBytes,
    this.ramTotalBytes,
    this.temperatureC,
    this.fanSpeeds = const [],
    this.ports = const [],
  });

  final String? model;
  final String? product;
  final String? firmware;
  final String? mac;
  final String? hostname;
  final String? address;
  final String? gateway;
  final int? uptimeSeconds;
  final num? cpuPercent;
  final num? ramPercent;
  final int? ramFreeBytes;
  final int? ramTotalBytes;
  final num? temperatureC;
  final List<int> fanSpeeds;
  final List<EdgeSwitchPort> ports;

  int get portsUp => ports.where((p) => p.up).length;
  int get portsTotal => ports.length;

  /// مجموع طاقة PoE المسحوبة — الرقم الذي يقرّر إن كان مصدر الطاقة
  /// على وشك التشبّع.
  num get poeTotalWatts =>
      ports.fold<num>(0, (s, p) => s + (p.poeWatts ?? 0));

  int get poePorts => ports.where((p) => p.poeActive).length;

  int get txRateTotal =>
      ports.fold<int>(0, (s, p) => s + (p.txRate ?? 0));
  int get rxRateTotal =>
      ports.fold<int>(0, (s, p) => s + (p.rxRate ?? 0));

  /// «١٠ أيّام و٣ ساعات» — لا «١٠ س ٣».
  ///
  /// نكتبها كما تُقرأ بالعربيّة لأنّ الاختصار خلط اليوم بالساعة في
  /// كارت المشترك من قبل، وأبلغ عنه المستخدم.
  String? get uptimeText {
    final s = uptimeSeconds;
    if (s == null || s <= 0) return null;
    final d = s ~/ 86400;
    final h = (s % 86400) ~/ 3600;
    final m = (s % 3600) ~/ 60;
    if (d > 0) {
      return h > 0 ? '$d ${_days(d)} و$h ${_hours(h)}' : '$d ${_days(d)}';
    }
    if (h > 0) return m > 0 ? '$h ${_hours(h)} و$m د' : '$h ${_hours(h)}';
    return '$m دقيقة';
  }

  static String _days(int n) =>
      n == 1 ? 'يوم' : (n == 2 ? 'يومان' : (n <= 10 ? 'أيّام' : 'يوماً'));
  static String _hours(int n) =>
      n == 1 ? 'ساعة' : (n == 2 ? 'ساعتان' : (n <= 10 ? 'ساعات' : 'ساعة'));
}
