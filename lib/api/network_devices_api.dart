import 'dart:io' show Socket;

import 'package:dart_ping/dart_ping.dart';
import 'package:dio/dio.dart';

import 'snmp_client.dart';
import 'package:flutter/foundation.dart';

import '../models/device_region.dart';
import '../models/network_device.dart';
import 'api_client.dart';

/// نتيجة scan واحدة — تُستهلك من bulk_scan_screen.dart.
class ScanResult {
  final String ip;
  final int openPort;
  final int responseMs;
  final String guessBrand;
  final String guessProtocol;
  final int guessApiPort;
  const ScanResult({
    required this.ip,
    required this.openPort,
    required this.responseMs,
    required this.guessBrand,
    required this.guessProtocol,
    required this.guessApiPort,
  });
}

/// API client لميزة الأجهزة (Devices Monitoring) — راجع
/// project_devices_monitoring_plan في memory. Slice 1: CRUD + probe.
class NetworkDevicesApi {
  /// GET /api/v2/admin/devices?brand=X&type=Y&status=Z&region_id=N
  /// [regionId]: null = بلا فلتر، 0 = "بدون منطقة" (unassigned)، N>0 = تلك المنطقة.
  static Future<List<NetworkDevice>> list({
    String? brand,
    String? type,
    String? status,
    int? regionId,
  }) async {
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/admin/devices',
        queryParameters: {
          if (brand != null && brand.isNotEmpty) 'brand': brand,
          if (type != null && type.isNotEmpty) 'type': type,
          if (status != null && status.isNotEmpty) 'status': status,
          if (regionId == 0)
            'region_id': 'none'
          else if (regionId != null && regionId > 0)
            'region_id': regionId,
        },
      );
      final data = (r.data?['data'] as List?) ?? const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(NetworkDevice.fromJson)
          .toList();
    } on DioException catch (e) {
      if (kDebugMode) print('❌ NetworkDevicesApi.list: ${e.message}');
      rethrow;
    }
  }

  /// POST /api/v2/admin/devices
  static Future<NetworkDevice> create(Map<String, dynamic> body) async {
    final r = await ApiClient.dio.post<Map<String, dynamic>>(
      '/api/v2/admin/devices',
      data: body,
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل إضافة الجهاز');
    }
    return NetworkDevice.fromJson(r.data!['data'] as Map<String, dynamic>);
  }

  /// PUT /api/v2/admin/devices/:id
  static Future<NetworkDevice> update(int id, Map<String, dynamic> body) async {
    final r = await ApiClient.dio.put<Map<String, dynamic>>(
      '/api/v2/admin/devices/$id',
      data: body,
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل التعديل');
    }
    return NetworkDevice.fromJson(r.data!['data'] as Map<String, dynamic>);
  }

  /// DELETE /api/v2/admin/devices/:id
  static Future<void> delete(int id) async {
    final r = await ApiClient.dio.delete<Map<String, dynamic>>(
      '/api/v2/admin/devices/$id',
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل الحذف');
    }
  }

  /// POST /api/v2/admin/devices/bulk-create — يُنشئ مجموعة أجهزة بطلب واحد.
  /// طلب واحد بدل N (يحلّ Cloudflare 429 + سرعة أعلى) + transaction atomic
  /// (كل الأجهزة أو لا شي — لو أي واحد فشل validation → 400 قبل INSERT).
  /// 2026-08-18.
  ///
  /// Body: `{devices: [{...deviceFields}, ...]}` — max 300 لكل طلب.
  /// يُرجع `{created: List<NetworkDevice>, count: int}`.
  static Future<List<NetworkDevice>> bulkCreate(
      List<Map<String, dynamic>> devices) async {
    if (devices.isEmpty) return const [];
    final r = await ApiClient.dio.post<Map<String, dynamic>>(
      '/api/v2/admin/devices/bulk-create',
      data: {'devices': devices},
    );
    if (r.data?['success'] != true) {
      final msg = r.data?['message'] ?? 'فشل الإضافة الجماعيّة';
      final errs = r.data?['errors'];
      if (errs is List && errs.isNotEmpty) {
        throw Exception('$msg — ${errs.length} خطأ');
      }
      throw Exception(msg);
    }
    final list = (r.data?['created'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => NetworkDevice.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// POST /api/v2/admin/devices/bulk-delete — يحذف مجموعة بطلب واحد.
  /// طلب واحد بدل N → لا rate-limit من Cloudflare. 2026-08-18.
  /// يرجع `{deleted: int, requested: int}` — لو الاثنين مختلفان يعني
  /// بعض الـids ليست ملك المدير أو ما موجودة (تُتجاهل بصمت في backend).
  static Future<({int deleted, int requested})> bulkDelete(
      List<int> ids) async {
    if (ids.isEmpty) return (deleted: 0, requested: 0);
    final r = await ApiClient.dio.post<Map<String, dynamic>>(
      '/api/v2/admin/devices/bulk-delete',
      data: {'ids': ids},
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل الحذف الجماعي');
    }
    final deleted = (r.data?['deleted'] is int)
        ? r.data!['deleted'] as int
        : int.tryParse('${r.data?['deleted']}') ?? 0;
    final requested = (r.data?['requested'] is int)
        ? r.data!['requested'] as int
        : ids.length;
    return (deleted: deleted, requested: requested);
  }

  /// GET /api/v2/admin/devices/:id/credentials — يفكّ التشفير ويرجع credentials.
  ///
  /// 2026-08-18: **in-memory cache** (60s TTL) لتفادي مشاكل:
  /// - Live Panels تستدعيه كل 8-15s → 60+ req/min على /credentials وحدها
  /// - كل fetch = DB decrypt AES + TLS round-trip → استنزاف موارد + audit spam
  /// - الـcreds لا تتغيّر إلا عند edit → cache 60s آمن جداً
  ///
  /// [forceRefresh] يتخطّى الـcache — يُستعمل بعد edit form save.
  static final Map<int, ({Map<String, dynamic> creds, DateTime at})>
      _credsCache = {};
  static const _credsCacheTtl = Duration(seconds: 60);

  static Future<Map<String, dynamic>> getCredentials(int id,
      {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _credsCache[id];
      if (cached != null &&
          DateTime.now().difference(cached.at) < _credsCacheTtl) {
        return cached.creds;
      }
    }
    final r = await ApiClient.dio.get<Map<String, dynamic>>(
      '/api/v2/admin/devices/$id/credentials',
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل جلب المعلومات');
    }
    final creds = r.data!['credentials'];
    final result =
        (creds is Map<String, dynamic>) ? creds : <String, dynamic>{};
    _credsCache[id] = (creds: result, at: DateTime.now());
    return result;
  }

  /// يمسح cache creds لجهاز معيّن (بعد edit save) أو الكل (بعد logout).
  static void invalidateCredentialsCache([int? id]) {
    if (id == null) {
      _credsCache.clear();
    } else {
      _credsCache.remove(id);
    }
  }

  /// Local probe محلّي — يستعمل TCP كأولوية (أدقّ من ICMP على iOS)
  /// مع fallback على ICMP لو الـport مجهول.
  ///
  /// **iOS ICMP quirk**: dart_ping على iOS يرجع بيانات مزيّفة أحياناً
  /// (نفس latency=156ms لكل الأجهزة، أو "online" لأجهزة offline).
  /// السبب: iOS يمنع raw ICMP sockets بدون entitlement خاصّ، فالمكتبة
  /// تلجأ لـfallback غير موثوق.
  ///
  /// **الحل**: TCP connect probe:
  ///   - سريع (~1-100ms على LAN)
  ///   - دقيق (successful connect = server-side pipeline يستجيب)
  ///   - يعمل على iOS + Android بلا permissions
  ///
  /// نستعمل [tcpPort] لو متوفّر (Mikrotik=8728، UBNT=22، Mimosa=161).
  /// ICMP fallback فقط لأجهزة بلا port معروف.
  static Future<({String status, int? responseMs, double? packetLoss})>
      localIcmpPing({
    required String ip,
    int count = 3,
    Duration timeout = const Duration(seconds: 2),
    int? tcpPort, // نُفضّله على ICMP
    /// يُستعمل حين يكون [tcpPort] هو ١٦١. الافتراضيّ يكفي معظم الأجهزة،
    /// ومن غيّرها يُمرّر قيمته المخزَّنة.
    String snmpCommunity = 'public',
  }) async {
    // ── 1. SNMP probe (منفذ ١٦١) ──
    //
    // 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «كلّ الميموسات ما تشتغل». والسبب أنّ **١٦١
    // منفذ UDP**، وفحص TCP عليه يُردّ بـ`Connection refused` دائماً —
    // لا لأنّ الجهاز ساقط بل لأنّه لا يستمع بـTCP أصلاً.
    //
    // فكان ٣٠ جهازاً من ٣١ يُعرَض «غير متّصل» أبداً، وهي حالةٌ قائمة
    // منذ إضافة دعم SNMP لا عطلٌ جديد.
    //
    // والعلاج ليس ICMP: استعلام SNMP حقيقيّ يُثبت أنّ **الخدمة** حيّة
    // وأنّ الـcommunity صحيحة، لا أنّ العنوان يردّ فحسب.
    if (tcpPort == 161) {
      return _snmpProbe(
          ip: ip, port: tcpPort!, community: snmpCommunity, timeout: timeout);
    }
    // ── 2. TCP probe ──
    if (tcpPort != null && tcpPort > 0) {
      return _tcpProbe(ip: ip, port: tcpPort, timeout: timeout);
    }
    // ── 3. ICMP fallback (لو ما فيه port) ──
    return _icmpProbe(ip: ip, count: count, timeout: timeout);
  }

  /// يفحص جهازاً بالطريقة المناسبة **لبروتوكوله**.
  ///
  /// ⚠️ نقطة واحدة لاختيار طريقة الفحص. كانت الشاشتان تكتبان
  /// `tcpPort: d.apiPort ?? d.port` كلٌّ على حدة — فحين اتّضح أنّ ١٦١
  /// منفذ UDP لا TCP كان لا بدّ من إصلاح موضعين، وهو بالضبط ما يجعل
  /// أحدهما يُنسى.
  ///
  /// وأجهزة SNMP تحتاج الـcommunity المخزَّنة: `public` تكفي معظمها،
  /// لكنّ من غيّرها يبدو ساقطاً أبداً. والجلب مخزَّن ٦٠ ثانية فلا يكلّف
  /// طلباً في كلّ جولة.
  static Future<({String status, int? responseMs, double? packetLoss})>
      probeDevice(NetworkDevice d) async {
    final port = d.apiPort ?? d.port;
    var community = 'public';
    if (port == 161 && d.hasCredentials) {
      try {
        final creds = await getCredentials(d.id);
        final c = (creds['community'] ?? '').toString();
        if (c.isNotEmpty) community = c;
      } catch (_) {
        // فشل الجلب لا يمنع الفحص — نجرّب الافتراضيّة.
      }
    }
    return localIcmpPing(ip: d.ip, tcpPort: port, snmpCommunity: community);
  }

  /// `sysUpTime.0` — أخفّ استعلام قياسيّ، تدعمه كلّ أجهزة SNMP.
  static const _oidSysUpTime = '1.3.6.1.2.1.1.3.0';

  /// فحص SNMP على UDP — نجاحه يعني أنّ الخدمة تردّ والـcommunity صحيحة.
  ///
  /// ⚠️ لا نفرّق بين «الجهاز ساقط» و«الـcommunity خطأ»: كلاهما صمت على
  /// UDP. والنتيجة `offline` في الحالتين — وهو ما يراه المستخدم فعلاً.
  static Future<({String status, int? responseMs, double? packetLoss})>
      _snmpProbe({
    required String ip,
    required int port,
    required String community,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final snmp = SnmpV2c(
        host: ip,
        port: port,
        community: community,
        timeout: timeout,
      );
      final r = await snmp.get([_oidSysUpTime]);
      sw.stop();
      if (r.isEmpty) {
        return (status: 'offline', responseMs: null, packetLoss: 100.0);
      }
      return (
        status: 'online',
        responseMs: sw.elapsedMilliseconds,
        packetLoss: 0.0
      );
    } catch (e) {
      if (kDebugMode) print('⚠️ snmpProbe $ip:$port failed: $e');
      return (status: 'offline', responseMs: null, packetLoss: 100.0);
    }
  }

  /// TCP connect probe — أدقّ probe للأجهزة على LAN.
  /// نجاح = الجهاز يقبل connections على هذا الـport (بمعنى: online + السيرفس شغّال).
  /// فشل = timeout أو refused → offline.
  static Future<({String status, int? responseMs, double? packetLoss})>
      _tcpProbe({
    required String ip,
    required int port,
    required Duration timeout,
  }) async {
    final sw = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      sw.stop();
      socket.destroy();
      return (
        status: 'online',
        responseMs: sw.elapsedMilliseconds,
        packetLoss: 0.0
      );
    } catch (e) {
      if (kDebugMode) print('⚠️ tcpProbe $ip:$port failed: $e');
      try {
        socket?.destroy();
      } catch (_) {}
      return (status: 'offline', responseMs: null, packetLoss: 100.0);
    }
  }

  /// ICMP ping — fallback لو ما نعرف الـport.
  static Future<({String status, int? responseMs, double? packetLoss})>
      _icmpProbe({
    required String ip,
    required int count,
    required Duration timeout,
  }) async {
    try {
      final ping = Ping(ip, count: count, timeout: timeout.inSeconds);
      final times = <int>[];
      int received = 0;
      await for (final event in ping.stream) {
        if (event is PingResponse) {
          if (event.time != null) {
            times.add(event.time!.inMilliseconds);
            received++;
          }
        } else if (event is PingSummary) {
          break;
        }
      }
      if (received == 0) {
        return (status: 'offline', responseMs: null, packetLoss: 100.0);
      }
      final avg = (times.reduce((a, b) => a + b) / times.length).round();
      final loss = ((count - received) / count) * 100.0;
      return (status: 'online', responseMs: avg, packetLoss: loss);
    } catch (e) {
      if (kDebugMode) print('⚠️ icmpProbe $ip failed: $e');
      return (status: 'offline', responseMs: null, packetLoss: 100.0);
    }
  }

  /// POST /api/v2/admin/devices/:id/probe-result — يحفظ نتيجة الـprobe على السيرفر
  static Future<void> saveProbeResult({
    required int deviceId,
    required String status,
    int? responseMs,
  }) async {
    try {
      await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/admin/devices/$deviceId/probe-result',
        data: {'status': status, 'response_ms': responseMs},
      );
    } on DioException catch (e) {
      if (kDebugMode) print('⚠️ saveProbeResult: ${e.message}');
      // لا نـthrow — الفحص المحلّي نجح، حفظ النتيجة ثانوي
    }
  }

  /// يرسل نتائج جولة الفحص **كلّها** في طلب واحد.
  ///
  /// 🐛 ما يُصلحه: [saveProbeResult] أعلاه كانت تُستدعى مرّة لكلّ جهاز.
  /// بحساب ٨٠ جهازاً وجولة كلّ ٢٠ ثانية = **٢٤٠ طلباً في الدقيقة من
  /// هاتف واحد**، متواصلةً ما دامت الصفحة مفتوحة. وCloudflare سبق أن
  /// ردّ ٤٢٩ على هذا المشروع في الإنشاء الجماعيّ.
  ///
  /// يعيد `true` إن قبِلها الخادم — والاستدعاء يبقى ثانويّاً: الفحص
  /// المحلّيّ نجح أصلاً، وفشل الحفظ لا يُبطله.
  static Future<bool> saveProbeResults(
      List<({int id, String status, int? responseMs})> results) async {
    if (results.isEmpty) return true;
    try {
      await ApiClient.dio.post<Map<String, dynamic>>(
        '/api/v2/admin/devices/probe-results',
        data: {
          'results': [
            for (final r in results)
              {'id': r.id, 'status': r.status, 'response_ms': r.responseMs},
          ],
        },
      );
      return true;
    } on DioException catch (e) {
      if (kDebugMode) print('⚠️ saveProbeResults: ${e.message}');
      return false;
    }
  }

  /// نسبة التشغيل والتذبذب لآخر [hours] ساعة — من `device_status_history`.
  /// يعيد خريطة `deviceId → (onlinePct, flaps)`؛ الجهاز بلا تاريخ يغيب
  /// عن النتيجة (لا نُلفّق صفراً لجهاز لم نرصده بعد).
  static Future<Map<int, ({double onlinePct, int flaps})>> fetchUptime(
      List<int> ids, {int hours = 24}) async {
    if (ids.isEmpty) return {};
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
        '/api/v2/admin/devices/uptime',
        queryParameters: {'ids': ids.join(','), 'hours': hours},
      );
      final raw = r.data?['uptime'];
      if (raw is! Map) return {};
      return {
        for (final e in raw.entries)
          if (int.tryParse('${e.key}') != null && e.value is Map)
            int.parse('${e.key}'): (
              onlinePct: ((e.value as Map)['onlinePct'] as num?)?.toDouble() ?? 0,
              flaps: ((e.value as Map)['flaps'] as num?)?.toInt() ?? 0,
            ),
      };
    } on DioException catch (e) {
      if (kDebugMode) print('⚠️ fetchUptime: ${e.message}');
      return {};
    }
  }

  // ══════════════════════════════════════════════════════════
  // Bulk IP scan (2026-08-18)
  // TCP-connect probing لكل الـIPs في /24 على 6 ports شائعة.
  // نُشخّص البراند/البروتوكول من أول port يفتح.
  // ══════════════════════════════════════════════════════════

  /// Port fingerprints — أوّل port ينجح يحدّد التخمين المبدئي.
  /// الترتيب مهمّ: نجرّب المميّز أوّلاً (8728 قبل 22).
  static const List<int> scanPorts = [8728, 22, 443, 80, 161, 23];

  /// خمّن brand + protocol + apiPort من أوّل port فُتح.
  static ({String brand, String protocol, int apiPort}) guessDeviceFromPort(
      int port) {
    return switch (port) {
      8728 => (brand: 'mikrotik', protocol: 'api', apiPort: 8728),
      22 => (brand: 'ubnt', protocol: 'ssh', apiPort: 22),
      443 => (brand: 'mimosa', protocol: 'api', apiPort: 443),
      161 => (brand: 'other', protocol: 'snmp', apiPort: 161),
      80 => (brand: 'other', protocol: 'api', apiPort: 80),
      23 => (brand: 'other', protocol: 'telnet', apiPort: 23),
      _ => (brand: 'other', protocol: 'api', apiPort: port),
    };
  }

  /// ماسح subnet /24 — يستهلك [base] كـ`192.168.1` ويفحص [start].. [end].
  /// كل IP يُفحص على [ports] بالتوازي. أوّل port يُفتح → discovered.
  /// [concurrency] عدد الـIPs المفحوصة معاً (default 30 — سريع بلا إرهاق).
  ///
  /// [onProgress] يُستدعى بعد كل IP بـ(done, total).
  /// [onFound] يُستدعى فور اكتشاف جهاز — للـstreaming UI.
  ///
  /// يرجع القائمة الكاملة عند انتهاء الـscan.
  static Future<List<ScanResult>> bulkScanSubnet({
    required String base, // "192.168.1"
    int startOctet = 1,
    int endOctet = 254,
    List<int> ports = scanPorts,
    int concurrency = 30,
    Duration timeout = const Duration(milliseconds: 800),
    void Function(int done, int total)? onProgress,
    void Function(ScanResult result)? onFound,
  }) async {
    final base3 =
        base.endsWith('.') ? base.substring(0, base.length - 1) : base;
    final ips = <String>[
      for (var i = startOctet; i <= endOctet; i++) '$base3.$i',
    ];
    final total = ips.length;
    var done = 0;
    final results = <ScanResult>[];
    final queue = List<String>.from(ips);

    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final ip = queue.removeAt(0);
        for (final port in ports) {
          try {
            final sw = Stopwatch()..start();
            final socket = await Socket.connect(ip, port, timeout: timeout);
            sw.stop();
            socket.destroy();
            final guess = guessDeviceFromPort(port);
            final res = ScanResult(
              ip: ip,
              openPort: port,
              responseMs: sw.elapsedMilliseconds,
              guessBrand: guess.brand,
              guessProtocol: guess.protocol,
              guessApiPort: guess.apiPort,
            );
            results.add(res);
            onFound?.call(res);
            break; // أوّل port فُتح → لا نكمل باقي الـports لهذا الـIP
          } catch (_) {
            // continue للـport التالي
          }
        }
        done++;
        onProgress?.call(done, total);
      }
    }

    // spawn workers
    final workers = List.generate(
      concurrency.clamp(1, total),
      (_) => worker(),
    );
    await Future.wait(workers);
    // sort by last octet ascending
    results.sort((a, b) {
      final ai = int.tryParse(a.ip.split('.').last) ?? 0;
      final bi = int.tryParse(b.ip.split('.').last) ?? 0;
      return ai.compareTo(bi);
    });
    return results;
  }

  // ══════════════════════════════════════════════════════════
  // Regions CRUD (2026-08-18)
  // المدير يقسّم أجهزته لمناطق (كرخ/رصافة/شرق…) لسرعة الفلترة.
  // Delete = يُصفّر region_id على الأجهزة (لا يحذفها).
  // ══════════════════════════════════════════════════════════

  /// GET /api/v2/admin/devices/regions
  static Future<List<DeviceRegion>> listRegions() async {
    final r = await ApiClient.dio.get<Map<String, dynamic>>(
      '/api/v2/admin/devices/regions',
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل جلب المناطق');
    }
    final data = (r.data?['data'] as List?) ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(DeviceRegion.fromJson)
        .toList();
  }

  /// POST /api/v2/admin/devices/regions
  static Future<DeviceRegion> createRegion({
    required String name,
    String? color,
    int sortOrder = 0,
  }) async {
    final r = await ApiClient.dio.post<Map<String, dynamic>>(
      '/api/v2/admin/devices/regions',
      data: {
        'name': name,
        if (color != null) 'color': color,
        'sort_order': sortOrder,
      },
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل الإضافة');
    }
    return DeviceRegion.fromJson(r.data!['data'] as Map<String, dynamic>);
  }

  /// PUT /api/v2/admin/devices/regions/:id
  static Future<DeviceRegion> updateRegion(
    int id, {
    required String name,
    String? color,
    int sortOrder = 0,
  }) async {
    final r = await ApiClient.dio.put<Map<String, dynamic>>(
      '/api/v2/admin/devices/regions/$id',
      data: {
        'name': name,
        if (color != null) 'color': color,
        'sort_order': sortOrder,
      },
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل التعديل');
    }
    return DeviceRegion.fromJson(r.data!['data'] as Map<String, dynamic>);
  }

  /// DELETE /api/v2/admin/devices/regions/:id
  /// يرجع عدد الأجهزة التي أُلغيَ ربطها بالمنطقة (region_id=NULL).
  static Future<int> deleteRegion(int id) async {
    final r = await ApiClient.dio.delete<Map<String, dynamic>>(
      '/api/v2/admin/devices/regions/$id',
    );
    if (r.data?['success'] != true) {
      throw Exception(r.data?['message'] ?? 'فشل الحذف');
    }
    final n = r.data?['devices_unassigned'];
    return (n is int) ? n : int.tryParse('$n') ?? 0;
  }
}
