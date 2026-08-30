import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// UBNT airOS SSH client — يستعمل SSH لتشغيل `mca-status` وجلب المعلومات.
///
/// **لماذا SSH بدل HTTP**:
/// - يعمل على كل إصدارات airOS 5/6/7/8 بدون فروقات
/// - LibreNMS + Zabbix + كل ISPs يستعملون SSH
/// - HTTP في airOS 5/6 القديم يواجه cookie/session/redirect issues
/// - user/pass نفسها للـweb (لا شيء إضافي)
///
/// **الأمر الرئيسي**: `mca-status` يُرجع نصّاً بصيغة key=value يشمل كل شيء.
/// **fallbacks**: `ubntbox status`، `iwconfig`، `/proc/*`، `ifconfig`.
class UbntApi {
  /// جلب صورة كاملة عن حالة الجهاز عبر SSH.
  ///
  /// **fallback usernames**: لو الـuser المُعدّ فشل بالـauth، نجرّب `ubnt`
  /// (default airOS) ثمّ `admin` ثمّ `root` — يحلّ 90% من مشاكل الـauth
  /// بدون تعديل يدوي.
  ///
  /// **Progressive rendering**: [onPartialReady] يُطلق بعد mca-status/dump
  /// (~500ms-1s) — UI يعرض device name, CPU, RAM, temp, signal فوراً بدل
  /// انتظار wstalist + ifconfig + link speed (~1-2s إضافيّة).
  static Future<UbntStats> fetchStats({
    required String ip,
    int port = 22,
    required String user,
    required String pass,
    Duration timeout = const Duration(seconds: 10),
    void Function(UbntStats partial)? onPartialReady,
  }) async {
    final userList = _buildUserFallback(user);
    UbntException? lastAuthErr;
    for (final u in userList) {
      try {
        if (kDebugMode) {
          debugPrint('🔑 UBNT SSH try user="$u" pass_len=${pass.length} '
              'ip=$ip:$port');
        }
        return await _fetchWithUser(
            ip: ip,
            port: port,
            user: u,
            pass: pass,
            timeout: timeout,
            onPartialReady: onPartialReady);
      } on UbntException catch (e) {
        if (kDebugMode) debugPrint('   ❌ $e');
        // auth error → جرّب الـuser التالي
        if (e.message.contains('اسم المستخدم') ||
            e.message.contains('SSH auth')) {
          lastAuthErr = e;
          continue;
        }
        rethrow;
      }
    }
    // كل الـusernames فشلت — رسالة واضحة للمستخدم
    // الخطأ الفعلي كان يُلتقط في `lastAuthErr` ويُهمَل، فيرى المستخدم
    // إرشاداً عامّاً بدل السبب (رفض اتصال · مضيف غير قابل للوصول ·
    // فشل مصادقة). النظير `rebootDevice` يستعمله أصلاً — نوحّدهما.
    throw UbntException(
        'فشل SSH auth مع كل الـusernames (${userList.join(", ")}).\n'
        'تحقّق من:\n'
        '  • SSH مفعّل على الجهاز (Services → SSH Server)\n'
        '  • الـpassword المدخل صحيح (طول=${pass.length})\n'
        '  • بعض airFiber يستعمل SSH-user منفصل عن web-user'
        '${lastAuthErr != null ? '\n\nآخر خطأ: ${lastAuthErr.message}' : ''}');
  }

  /// إعادة تشغيل الجهاز عبر SSH `reboot` command (مدعوم على airMax + airFiber).
  /// نُجرّب نفس الـfallback usernames مثل fetchStats.
  /// **مهم**: SSH session تنقطع فوراً بعد استقبال reboot — نتوقّع I/O error
  /// طبيعي (يعني الأمر وصل).
  static Future<void> rebootDevice({
    required String ip,
    int port = 22,
    required String user,
    required String pass,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final userList = _buildUserFallback(user);
    UbntException? lastAuthErr;
    for (final u in userList) {
      try {
        await _rebootWithUser(
            ip: ip, port: port, user: u, pass: pass, timeout: timeout);
        return; // نجح
      } on UbntException catch (e) {
        if (e.message.contains('اسم المستخدم') ||
            e.message.contains('SSH auth')) {
          lastAuthErr = e;
          continue;
        }
        rethrow;
      }
    }
    throw lastAuthErr ?? UbntException('فشل SSH auth للـreboot');
  }

  static Future<void> _rebootWithUser({
    required String ip,
    required int port,
    required String user,
    required String pass,
    required Duration timeout,
  }) async {
    SSHClient? client;
    SSHSocket? socket;
    try {
      socket = await SSHSocket.connect(ip, port, timeout: timeout);
      client = SSHClient(
        socket,
        username: user,
        onPasswordRequest: () => pass,
        onUserInfoRequest: (req) async => req.prompts.map((_) => pass).toList(),
      );
      await client.authenticated.timeout(timeout);
      // نُنفّذ الأمر — الجهاز يقطع الاتصال تقريباً فوراً بعد وصول reboot
      try {
        await client.run('reboot &').timeout(const Duration(seconds: 3));
      } catch (e) {
        // Socket closure / timeout = الجهاز بدأ يُعيد التشغيل (متوقّع)
        final msg = e.toString().toLowerCase();
        if (msg.contains('closed') ||
            msg.contains('timeout') ||
            msg.contains('reset') ||
            msg.contains('eof')) {
          return;
        }
        // خطأ آخر — قد يكون permission denied أو command not found
        rethrow;
      }
    } on SSHAuthAbortError {
      throw UbntException('اسم المستخدم أو كلمة المرور خطأ (SSH auth failed)');
    } on SSHAuthFailError {
      throw UbntException('اسم المستخدم أو كلمة المرور خطأ (SSH auth failed)');
    } on TimeoutException {
      throw UbntException('انتهت مهلة الاتصال');
    } catch (e) {
      if (e is UbntException) rethrow;
      throw UbntException('فشل reboot: $e');
    } finally {
      try {
        client?.close();
      } catch (_) {}
      try {
        socket?.close();
      } catch (_) {}
    }
  }

  /// نُنشئ قائمة usernames مرتّبة: الحاليّ أوّلاً، ثمّ الـfallbacks.
  static List<String> _buildUserFallback(String user) {
    final base = user.trim();
    final list = <String>[];
    if (base.isNotEmpty) list.add(base);
    for (final f in const ['ubnt', 'admin', 'root']) {
      if (!list.contains(f)) list.add(f);
    }
    return list;
  }

  /// محاولة واحدة بـuser محدّد — يُستدعى من fetchStats داخل حلقة الـfallback.
  static Future<UbntStats> _fetchWithUser({
    required String ip,
    required int port,
    required String user,
    required String pass,
    required Duration timeout,
    void Function(UbntStats partial)? onPartialReady,
  }) async {
    SSHClient? client;
    SSHSocket? socket;
    try {
      socket = await SSHSocket.connect(ip, port, timeout: timeout);
      // ندعم البروتوكولين: password auth (airOS العادي) + keyboard-interactive
      // (بعض airFiber ومعظم Debian-based servers) — كل الـchallenges نُجيبها
      // بنفس الـpass. بدون هذا، السيرفرات الي تدعم keyboard-interactive فقط
      // ترجع SSHAuthFailError حتى مع الـcreds الصحيحة.
      client = SSHClient(
        socket,
        username: user,
        onPasswordRequest: () => pass,
        onUserInfoRequest: (req) async {
          return req.prompts.map((_) => pass).toList();
        },
      );

      // ننتظر الـauth handshake صراحة — يفشل سريعاً على الـcreds الغلط
      // بدل انتظار timeout الأمر الأوّل. لو auth تمّ، نُكمل بأمان.
      await client.authenticated.timeout(timeout);

      // نجرّب mca-dump أوّلاً (JSON منظّم، أوثق للأجهزة الحديثة airFiber/airMax AC)
      // ثمّ fallback إلى mca-status (key=value، للـXM/AC القديمة)
      String output = '';
      bool isJsonDump = false;

      try {
        final result = await client.run('mca-dump').timeout(timeout);
        output = utf8.decode(result, allowMalformed: true).trim();
        if (output.startsWith('{') || output.startsWith('[')) {
          isJsonDump = true;
        }
      } catch (_) {}

      if (!isJsonDump) {
        try {
          final result = await client.run('mca-status').timeout(timeout);
          output = utf8.decode(result, allowMalformed: true);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ mca-status failed: $e — trying ubntbox status');
          }
          final result = await client.run('ubntbox status').timeout(timeout);
          output = utf8.decode(result, allowMalformed: true);
        }
      }

      if (output.trim().isEmpty) {
        throw UbntException('لم نستلم بيانات — تحقّق من صلاحيّات المستخدم');
      }

      if (kDebugMode) {
        debugPrint(
            '══════ UBNT output (${isJsonDump ? "JSON" : "key=value"}) ══════');
        debugPrint(
            output.substring(0, output.length > 2000 ? 2000 : output.length));
        debugPrint('════════════════════════════════');
      }

      // لو JSON: نحوّله لـflat map key=value ليعمل مع نفس الـparser
      final parsed =
          isJsonDump ? _flattenMcaDump(output) : _parseMcaStatus(output);

      // airFiber 60: أوامر إضافيّة لجلب wireless info (يفشل بصمت لغير airFiber)
      try {
        final afOut = utf8
            .decode(
                await client
                    .run('af-status 2>/dev/null')
                    .timeout(const Duration(seconds: 4)),
                allowMalformed: true)
            .trim();
        if (afOut.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('🔵 af-status output (first 1500 chars):');
            debugPrint(
                afOut.substring(0, afOut.length > 1500 ? 1500 : afOut.length));
          }
          if (afOut.startsWith('{')) {
            _mergeFromJson(parsed, afOut);
          }
        }
      } catch (_) {}

      // ⚡ Tier 1 partial: mca-status + af-status جاهز.
      // UI يعرض device name/CPU/RAM/temp/signal فوراً بدل انتظار wstalist +
      // ifconfig + link speeds (~1-2s إضافيّة).
      if (onPartialReady != null) {
        try {
          final partial = UbntStats.fromMcaStatus(
              Map<String, String>.from(parsed), // نسخة عشان لا نعدّلها
              interfaces: const [],
              wstalistStations: const []);
          onPartialReady(partial);
        } catch (_) {}
      }

      // **Batched command** — بدل 4 SSH round-trips منفصلة (wstalist + uptime +
      // loadavg + iwconfig + ifconfig) الي كانت تستهلك ~15s على أجهزة بطيئة،
      // نجمعهم في shell command واحد مع فاصل مُميّز. RouterOS SSH يدعم `;`
      // لتسلسل الأوامر. الفاصل ==SECTION== يساعد الـparser يفصل الأقسام.
      //
      // fallback: لو الأمر المُجمَّع فشل (بعض airOS القديم يقفل shell)،
      // نرجع لسلوك القديم بأوامر منفصلة.
      String batchedOut = '';
      const marker = '===MYSVCS_SECTION===';
      try {
        final cmd = [
          'wstalist 2>/dev/null',
          'echo $marker',
          'cat /proc/uptime',
          'echo $marker',
          'cat /proc/loadavg',
          'echo $marker',
          'iwconfig 2>/dev/null',
          'echo $marker',
          'ifconfig',
        ].join(';');
        batchedOut = utf8.decode(
          await client.run(cmd).timeout(const Duration(seconds: 8)),
          allowMalformed: true,
        );
      } catch (_) {
        batchedOut = '';
      }

      String wstaOut = '', uptimeOut = '', loadOut = '', iwOut = '', ifOut = '';
      if (batchedOut.isNotEmpty) {
        final parts = batchedOut.split(marker);
        wstaOut = parts.isNotEmpty ? parts[0].trim() : '';
        uptimeOut = parts.length > 1 ? parts[1].trim() : '';
        loadOut = parts.length > 2 ? parts[2].trim() : '';
        iwOut = parts.length > 3 ? parts[3] : '';
        ifOut = parts.length > 4 ? parts[4] : '';
      }
      // 2026-08-20: wstalist recovery — إذا الأمر المُجمَّع نجح لكن wstaOut
      // فارغ أو مقطوع (بعض airOS firmware تدمج stdout للأوامر المتسلسلة
      // بشكل يخرّب parsing)، أعد جلب wstalist منفصلاً. بدون هذا: AP
      // بعملاء متصلين يعرض "لا يوجد عملاء" بلا سبب حقيقي.
      if (batchedOut.isNotEmpty && !wstaOut.startsWith('[')) {
        try {
          final r = utf8
              .decode(
                await client
                    .run('wstalist 2>/dev/null')
                    .timeout(const Duration(seconds: 5)),
                allowMalformed: true,
              )
              .trim();
          if (r.startsWith('[')) {
            wstaOut = r;
            if (kDebugMode) {
              debugPrint('🟢 [ubnt] wstalist recovered via fallback fetch');
            }
          }
        } catch (_) {}
      }
      if (batchedOut.isEmpty) {
        // fallback: أوامر منفصلة (سلوك قديم)
        try {
          wstaOut = utf8
              .decode(
                  await client
                      .run('wstalist 2>/dev/null')
                      .timeout(const Duration(seconds: 4)),
                  allowMalformed: true)
              .trim();
        } catch (_) {}
        try {
          uptimeOut = utf8
              .decode(
                  await client
                      .run('cat /proc/uptime')
                      .timeout(const Duration(seconds: 3)),
                  allowMalformed: true)
              .trim();
        } catch (_) {}
        try {
          loadOut = utf8
              .decode(
                  await client
                      .run('cat /proc/loadavg')
                      .timeout(const Duration(seconds: 3)),
                  allowMalformed: true)
              .trim();
        } catch (_) {}
        try {
          iwOut = utf8.decode(
              await client
                  .run('iwconfig 2>/dev/null')
                  .timeout(const Duration(seconds: 4)),
              allowMalformed: true);
        } catch (_) {}
        try {
          ifOut = utf8.decode(
              await client.run('ifconfig').timeout(const Duration(seconds: 4)),
              allowMalformed: true);
        } catch (_) {}
      }

      // wstalist — نحفظه أوّلاً للاستعمال في الـstations lookup (المكرّر السابق)
      List<Map<String, dynamic>> stations = const [];
      if (wstaOut.startsWith('[')) {
        _mergeStationsFromWstalist(parsed, wstaOut);
        try {
          final parsedJson = json.decode(wstaOut);
          if (parsedJson is List) {
            stations = parsedJson
                .whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList();
          }
        } catch (_) {}
      }

      // uptime
      if (parsed['uptime'] == null && uptimeOut.isNotEmpty) {
        parsed['uptime'] = uptimeOut.split(' ').first;
      }

      // loadavg → cpuload
      if (parsed['cpuload'] == null && loadOut.isNotEmpty) {
        final loadParts = loadOut.split(RegExp(r'\s+'));
        if (loadParts.isNotEmpty) {
          final load1 = double.tryParse(loadParts[0]) ?? 0;
          parsed['cpuload'] = (load1 * 100).round().toString();
        }
      }

      // iwconfig
      if (iwOut.isNotEmpty) _enrichFromIwconfig(iwOut, parsed);

      // ifconfig
      List<Map<String, String>> ifaceRaws = const [];
      if (ifOut.isNotEmpty) {
        ifaceRaws = _parseIfconfig(ifOut);
      }

      // link speed لكل ether — نجرّب عدّة مصادر (تختلف بين إصدارات airOS):
      //   1. /sys/class/net/eth0/speed (Linux حديث)
      //   2. mii-tool (airOS القديم — Atheros)
      //   3. ethtool (لو موجود)
      //   4. mca-status لو فيه wanSpeed
      for (final iface in ifaceRaws) {
        final name = iface['name'] ?? '';
        if (name.isEmpty || !name.startsWith('eth')) continue;

        // 1) /sys/class/net
        try {
          final r = utf8
              .decode(
                  await client
                      .run('cat /sys/class/net/$name/speed 2>/dev/null')
                      .timeout(const Duration(seconds: 2)),
                  allowMalformed: true)
              .trim();
          if (r.isNotEmpty && int.tryParse(r) != null && int.parse(r) > 0) {
            iface['speed'] = r;
            continue;
          }
        } catch (_) {}

        // 2) mii-tool — الأشهر على airOS 5/6 القديم
        try {
          final r = utf8
              .decode(
                  await client
                      .run('mii-tool $name 2>/dev/null')
                      .timeout(const Duration(seconds: 2)),
                  allowMalformed: true)
              .trim();
          // نموذج: "eth0: negotiated 100baseTx-FD flow-control, link ok"
          final m = RegExp(r'(\d+)base').firstMatch(r);
          if (m != null) {
            iface['speed'] = m.group(1)!;
            continue;
          }
        } catch (_) {}

        // 3) ethtool
        try {
          final r = utf8.decode(
              await client
                  .run('ethtool $name 2>/dev/null')
                  .timeout(const Duration(seconds: 2)),
              allowMalformed: true);
          // "Speed: 1000Mb/s"
          final m = RegExp(r'Speed:\s*(\d+)').firstMatch(r);
          if (m != null) {
            iface['speed'] = m.group(1)!;
            continue;
          }
        } catch (_) {}
      }

      // fallback: mca-status قد يعرض wanSpeed أو lanSpeed
      if (parsed['wanSpeed'] != null) {
        final s = int.tryParse(parsed['wanSpeed']!);
        if (s != null && s > 0) {
          final eth0 = ifaceRaws.where((i) => i['name'] == 'eth0').toList();
          if (eth0.isNotEmpty && eth0.first['speed'] == null) {
            eth0.first['speed'] = s.toString();
          }
        }
      }

      // wstalist سبق واستخرجناه أعلاه من الـbatched command (stations متغيّر
      // مُعبّأ فوق). لا نُكرّر الأمر — كان يستهلك 4s إضافيّة بلا فائدة.
      return UbntStats.fromMcaStatus(parsed,
          interfaces: ifaceRaws, wstalistStations: stations);
    } on SSHAuthAbortError {
      throw UbntException('اسم المستخدم أو كلمة المرور خطأ (SSH auth failed)');
    } on SSHAuthFailError {
      throw UbntException('اسم المستخدم أو كلمة المرور خطأ (SSH auth failed)');
    } on TimeoutException {
      throw UbntException('انتهت مهلة الاتصال — تأكّد من IP وأن SSH مفعّل');
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('SocketException')) {
        throw UbntException('الجهاز غير قابل للوصول — تحقّق من الشبكة والـIP');
      }
      if (msg.contains('Connection refused')) {
        throw UbntException('SSH port 22 مغلق — تأكّد أن SSH مفعّل على الجهاز');
      }
      if (msg.contains('Handshake') || msg.contains('SSH')) {
        throw UbntException('فشل SSH handshake: $msg');
      }
      throw UbntException('خطأ: $msg');
    } finally {
      try {
        client?.close();
      } catch (_) {}
      try {
        socket?.close();
      } catch (_) {}
    }
  }

  /// mca-dump JSON — للـairFiber والأجهزة الحديثة. نُسطّح لصيغة key=value
  /// بأسماء متوافقة مع _parseMcaStatus عشان نفس الـfactory يشتغل.
  /// airFiber 60 LR بنيته مختلفة — نغطّي عدّة variations.
  static Map<String, String> _flattenMcaDump(String jsonStr) {
    final map = <String, String>{};
    try {
      final data = json.decode(jsonStr);
      if (data is! Map) return map;
      final root = data as Map<String, dynamic>;

      if (kDebugMode) {
        debugPrint('🔵 UBNT mca-dump root keys: ${root.keys.toList()}');
      }

      // host section — الأكثر ثباتاً بين الأجهزة
      final host = (root['host'] as Map?)?.cast<String, dynamic>() ?? const {};
      _set(map, 'deviceName', host['hostname'] ?? host['device_id']);
      _set(
          map, 'firmwareVersion', host['fwversion'] ?? host['firmwareVersion']);
      _set(map, 'platform', host['devmodel'] ?? host['sysid']);
      _set(map, 'uptime', host['uptime']);
      _set(map, 'cpuload', host['cpuload'] ?? host['cpu_load']);
      // درجة الحرارة قد تكون في host أو في مواقع أخرى — نجرّب كلها
      _set(map, 'temperature',
          host['temperature'] ?? host['temp'] ?? root['temperature']);

      // wireless section (airMax/airOS 5-8)
      final w = (root['wireless'] as Map?)?.cast<String, dynamic>();
      if (w != null) {
        if (kDebugMode) debugPrint('🔵 wireless keys: ${w.keys.toList()}');
        _set(map, 'wlanEssid', w['essid'] ?? w['ssid']);
        _set(map, 'wlanMode', w['mode']);
        _set(map, 'wlanSignal', w['signal'] ?? w['rssi']);
        _set(map, 'wlanNoiseFloor', w['noisef'] ?? w['noise']);
        _set(map, 'wlanCcq', w['ccq']);
        _set(map, 'wlanTxRate', w['txrate'] ?? w['tx_rate']);
        _set(map, 'wlanRxRate', w['rxrate'] ?? w['rx_rate']);
        _set(map, 'wlanChan', w['channel']);
        _set(map, 'wlanFrequency', w['frequency'] ?? w['freq']);
        _set(map, 'wlanDistance', w['distance']);
        _set(map, 'wlanChanWidth', w['chanbw'] ?? w['chwidth']);
      }

      // airFiber-specific: 'radio' section
      final radio = (root['radio'] as Map?)?.cast<String, dynamic>();
      if (radio != null) {
        if (kDebugMode) debugPrint('🔵 radio keys: ${radio.keys.toList()}');
        // نستعمل radio لتكميل ما ينقص من wireless
        map['wlanSignal'] ??=
            (radio['signal'] ?? radio['rxlevel'] ?? radio['rx_level'])
                    ?.toString() ??
                '';
        map['wlanNoiseFloor'] ??=
            (radio['noise'] ?? radio['noise_level'])?.toString() ?? '';
        map['wlanFrequency'] ??=
            (radio['frequency'] ?? radio['freq'])?.toString() ?? '';
        // معدّلات النقل في radio.link_capacity أو radio.tx_capacity
        map['wlanTxRate'] ??=
            (radio['tx_capacity'] ?? radio['tx_rate'])?.toString() ?? '';
        map['wlanRxRate'] ??=
            (radio['rx_capacity'] ?? radio['rx_rate'])?.toString() ?? '';
        map['temperature'] ??=
            (radio['temperature'] ?? radio['temp'])?.toString() ?? '';
      }

      // airFiber 60: قد يكون فيه 'link' section
      final link = (root['link'] as Map?)?.cast<String, dynamic>();
      if (link != null) {
        if (kDebugMode) debugPrint('🔵 link keys: ${link.keys.toList()}');
        map['wlanTxRate'] ??=
            (link['tx_capacity'] ?? link['capacity'])?.toString() ?? '';
        map['wlanRxRate'] ??= (link['rx_capacity'])?.toString() ?? '';
      }

      // إزالة أي قيم فارغة
      map.removeWhere((k, v) => v.isEmpty);

      // stations: قد تكون في wireless.sta أو root.stations أو root.remote (airFiber)
      List sta = const [];
      if (w?['sta'] is List) {
        sta = w!['sta'] as List;
      } else if (root['stations'] is List) {
        sta = root['stations'] as List;
      } else if (root['peers'] is List) {
        sta = root['peers'] as List;
      }
      // airFiber remote peer
      final remote = (root['remote'] as Map?)?.cast<String, dynamic>();
      if (sta.isEmpty && remote != null) sta = [remote];

      for (int i = 0; i < sta.length; i++) {
        final s = sta[i];
        if (s is! Map) continue;
        final j = s.cast<String, dynamic>();
        final idx = i + 1;
        _set(map, 'station${idx}_mac',
            j['mac'] ?? j['mac_addr'] ?? j['mac_address']);
        _set(map, 'station${idx}_ip', j['lastip'] ?? j['ip'] ?? j['address']);
        _set(map, 'station${idx}_name',
            j['name'] ?? j['hostname'] ?? j['device_name']);
        _set(map, 'station${idx}_signal',
            j['signal'] ?? j['rssi'] ?? j['rx_level']);
        _set(map, 'station${idx}_noise', j['noisefloor'] ?? j['noise']);
        _set(map, 'station${idx}_ccq', j['ccq']);
        // tx/rx قد تكون بـKbps أو Mbps — نتركها كما هي والـUI يعرضها
        _set(map, 'station${idx}_tx',
            j['tx'] ?? j['tx_rate'] ?? j['tx_capacity']);
        _set(map, 'station${idx}_rx',
            j['rx'] ?? j['rx_rate'] ?? j['rx_capacity']);
        _set(map, 'station${idx}_uptime', j['uptime'] ?? j['conn_time']);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ mca-dump flatten error: $e');
    }
    return map;
  }

  /// دمج JSON من af-status (airFiber-specific) لتكميل ما ينقص في mca-dump
  static void _mergeFromJson(Map<String, String> map, String jsonStr) {
    try {
      final data = json.decode(jsonStr);
      if (data is! Map) return;
      final root = data as Map<String, dynamic>;
      if (kDebugMode) {
        debugPrint('🔵 af-status root keys: ${root.keys.toList()}');
      }

      // airFiber structure: radio/local/remote/link
      final local = (root['local'] as Map?)?.cast<String, dynamic>();
      if (local != null) {
        if (kDebugMode) {
          debugPrint('🔵 af-status.local keys: ${local.keys.toList()}');
        }
        map['wlanSignal'] ??= _asStr(
            local['rf']?['rxlevel'] ?? local['signal'] ?? local['rx_level']);
        map['wlanNoiseFloor'] ??=
            _asStr(local['rf']?['noise'] ?? local['noise']);
        map['temperature'] ??= _asStr(local['temperature'] ?? local['temp']);
      }
      final remote = (root['remote'] as Map?)?.cast<String, dynamic>();
      if (remote != null) {
        if (kDebugMode) {
          debugPrint('🔵 af-status.remote keys: ${remote.keys.toList()}');
        }
        // remote peer — لو ما فيه station من مكان آخر، نضيفه
        if (map['station1_mac'] == null) {
          _set(map, 'station1_mac', remote['mac']);
          _set(map, 'station1_ip', remote['ip']);
          _set(map, 'station1_name',
              remote['hostname'] ?? remote['device_name']);
          _set(map, 'station1_signal',
              remote['rf']?['rxlevel'] ?? remote['signal']);
          _set(map, 'station1_noise', remote['rf']?['noise']);
        }
      }
      final link = (root['link'] as Map?)?.cast<String, dynamic>();
      if (link != null) {
        if (kDebugMode) {
          debugPrint('🔵 af-status.link keys: ${link.keys.toList()}');
        }
        map['wlanTxRate'] ??= _asStr(link['tx_capacity'] ?? link['capacity']);
        map['wlanRxRate'] ??= _asStr(link['rx_capacity']);
      }
      final radio = (root['radio'] as Map?)?.cast<String, dynamic>();
      if (radio != null) {
        if (kDebugMode) {
          debugPrint('🔵 af-status.radio keys: ${radio.keys.toList()}');
        }
        map['wlanFrequency'] ??= _asStr(radio['frequency']);
      }
      map.removeWhere((k, v) => v.isEmpty);
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ af-status parse failed: $e');
    }
  }

  /// دمج stations من wstalist JSON — يدعم airMax و airFiber 60.
  /// airFiber 60 يستعمل prs_sta nested object فيه signal + capacity + snr.
  static void _mergeStationsFromWstalist(
      Map<String, String> map, String jsonStr) {
    try {
      final data = json.decode(jsonStr);
      // Debug: نطبع أسماء fields لأوّل station — يساعدنا نضبط CCQ للـAC
      if (kDebugMode && data is List && data.isNotEmpty && data[0] is Map) {
        final first = (data[0] as Map).cast<String, dynamic>();
        debugPrint('🔵 [wstalist] first station keys: ${first.keys.toList()}');
        if (first['airmax'] is Map) {
          debugPrint('🔵 [wstalist] airmax keys: '
              '${(first['airmax'] as Map).keys.toList()}');
          debugPrint('🔵 [wstalist] airmax full: ${first['airmax']}');
        }
      }
      if (data is! List) return;
      for (int i = 0; i < data.length; i++) {
        final s = data[i];
        if (s is! Map) continue;
        final j = s.cast<String, dynamic>();
        final prs = (j['prs_sta'] as Map?)?.cast<String, dynamic>();
        final idx = i + 1;

        _set(map, 'station${idx}_mac', j['mac']);
        _set(map, 'station${idx}_ip', j['lastip'] ?? j['ip']);
        _set(map, 'station${idx}_name', j['name'] ?? j['hostname']);
        _set(map, 'station${idx}_uptime', j['uptime'] ?? prs?['uptime']);

        // Signal: airFiber → prs_sta.rssi_data (-54)، airMax → j['signal']
        final signal = prs?['rssi_data'] ?? j['signal'] ?? j['rssi'];
        _set(map, 'station${idx}_signal', signal);

        // Noise
        _set(map, 'station${idx}_noise', j['noisefloor'] ?? j['noise']);

        // SNR (airFiber يعطيه صراحة، airMax نحسبه من signal-noise)
        _set(map, 'station${idx}_snr', prs?['snr']);

        // CCQ (airMax فقط، airFiber ما فيه) — أسماء متعدّدة حسب إصدار airOS:
        //   XM (5/6):  s['ccq']                = 95
        //   AC (7+):   s['airmax']['ccq']      = 95
        //              أو ['airmax']['quality']  (بعض AC firmware)
        //              أو ['airmax']['priority']
        //              أو top-level s['quality']
        //   airOS 8:   s['tx']['ccq']، s['rx']['ccq']
        dynamic ccqVal = j['ccq'] ?? j['quality'];
        if (ccqVal == null || _n(ccqVal) == 0) {
          final airmax = j['airmax'];
          if (airmax is Map) {
            ccqVal = airmax['ccq'] ?? airmax['quality'] ?? airmax['priority'];
          }
        }
        if (ccqVal == null || _n(ccqVal) == 0) {
          final txMap = j['tx'];
          if (txMap is Map) ccqVal = txMap['ccq'];
        }
        if (ccqVal == null || _n(ccqVal) == 0) {
          final rxMap = j['rx'];
          if (rxMap is Map) ccqVal = rxMap['ccq'];
        }
        if (ccqVal != null) _set(map, 'station${idx}_ccq', ccqVal);

        // tx/rx — الأولوية:
        //   1. prs_sta.dl_capacity/ul_capacity (airFiber، Kbps)
        //   2. prs_sta.tx_mcs/rx_mcs (airFiber MCS index)
        //   3. j['tx']/j['rx'] direct (airMax)
        //   4. j['tx']['rate'] nested
        final dlCap = prs?['dl_capacity']; // Kbps
        final ulCap = prs?['ul_capacity'];
        if (dlCap != null) {
          // Kbps → Mbps
          _set(map, 'station${idx}_rx', (_n(dlCap) ~/ 1000).toString());
          _set(map, 'station${idx}_rx_capacity', dlCap);
        }
        if (ulCap != null) {
          _set(map, 'station${idx}_tx', (_n(ulCap) ~/ 1000).toString());
          _set(map, 'station${idx}_tx_capacity', ulCap);
        }
        // fallback: direct tx/rx (airMax)
        if (dlCap == null) {
          final rxr = j['rx'];
          if (rxr is Map) {
            _set(map, 'station${idx}_rx', rxr['rate']);
          } else {
            _set(map, 'station${idx}_rx', rxr);
          }
        }
        if (ulCap == null) {
          final txr = j['tx'];
          if (txr is Map) {
            _set(map, 'station${idx}_tx', txr['rate']);
          } else {
            _set(map, 'station${idx}_tx', txr);
          }
        }

        // Distance (airFiber يعطي prs_sta.distance بالأمتار)
        if (prs?['distance'] != null) {
          _set(map, 'station${idx}_distance', prs!['distance']);
        }

        // airFiber 60 — حقول متقدّمة للـPtP link view
        if (prs != null) {
          _set(map, 'station${idx}_tx_mcs', prs['tx_mcs']);
          _set(map, 'station${idx}_rx_mcs', prs['rx_mcs']);
          _set(map, 'station${idx}_link_uptime', prs['uptime']);
          _set(map, 'station${idx}_dl_signal_expect', prs['dl_signal_expect']);
          _set(map, 'station${idx}_ul_signal_expect', prs['ul_signal_expect']);
          _set(map, 'station${idx}_dl_capacity_expect',
              prs['dl_capacity_expect']);
          _set(map, 'station${idx}_ul_capacity_expect',
              prs['ul_capacity_expect']);
          _set(map, 'station${idx}_tx_sector', prs['tx_sector']);
          _set(map, 'station${idx}_rx_sector', prs['rx_sector']);
        }
        // linked_60 = بيان اتّصال 60GHz (airFiber 60 فقط)
        if (j['linked_60'] == true) {
          _set(map, 'station${idx}_linked_60', 'true');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ wstalist parse failed: $e');
    }
  }

  static String _asStr(dynamic v) {
    if (v == null) return '';
    return v.toString().trim();
  }

  static void _set(Map<String, String> map, String key, dynamic value) {
    if (value == null) return;
    final s = value.toString().trim();
    if (s.isEmpty || s == 'null') return;
    map[key] = s;
  }

  /// mca-status output: أسطر key=value، بعض القيم متعدّدة (station1_ip=...)
  static Map<String, String> _parseMcaStatus(String output) {
    final map = <String, String>{};
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final eq = trimmed.indexOf('=');
      if (eq <= 0) continue;
      final key = trimmed.substring(0, eq).trim();
      final val = trimmed.substring(eq + 1).trim();
      map[key] = val;
    }
    return map;
  }

  /// iwconfig output فيه معلومات wireless
  /// نموذج:
  ///   ath0    IEEE 802.11an  ESSID:"MyWisp"  Mode:Master
  ///           Frequency:5.180 GHz  Access Point: AA:BB:CC:...
  ///           Bit Rate:270 Mb/s   Tx-Power:25 dBm
  ///           Link Quality=54/70  Signal level=-56 dBm  Noise level=-95 dBm
  static void _enrichFromIwconfig(String output, Map<String, String> map) {
    final essid =
        RegExp(r'ESSID:"?([^"\n]+)"?').firstMatch(output)?.group(1)?.trim();
    if (essid != null && essid.isNotEmpty && map['wlanEssid'] == null) {
      map['wlanEssid'] = essid;
    }
    final mode = RegExp(r'Mode:(\S+)').firstMatch(output)?.group(1)?.trim();
    if (mode != null && map['wlanMode'] == null) {
      map['wlanMode'] = mode;
    }
    final freq =
        RegExp(r'Frequency:([\d.]+)\s*GHz').firstMatch(output)?.group(1);
    if (freq != null && map['wlanFrequency'] == null) {
      // GHz → MHz
      final ghz = double.tryParse(freq);
      if (ghz != null) map['wlanFrequency'] = (ghz * 1000).round().toString();
    }
    final signal = RegExp(r'Signal level=(-?\d+)').firstMatch(output)?.group(1);
    if (signal != null && map['wlanSignal'] == null) {
      map['wlanSignal'] = signal;
    }
    final noise = RegExp(r'Noise level=(-?\d+)').firstMatch(output)?.group(1);
    if (noise != null && map['wlanNoiseFloor'] == null) {
      map['wlanNoiseFloor'] = noise;
    }
    final bitrate =
        RegExp(r'Bit Rate[:=]\s*([\d.]+)\s*Mb/s').firstMatch(output)?.group(1);
    if (bitrate != null) {
      final rate = double.tryParse(bitrate)?.round().toString();
      if (rate != null) {
        if (map['wlanTxRate'] == null) map['wlanTxRate'] = rate;
        if (map['wlanRxRate'] == null) map['wlanRxRate'] = rate;
      }
    }
  }

  /// ifconfig output → list of interface maps مع RX/TX bytes
  /// نموذج (busybox / Linux):
  ///   eth0      Link encap:Ethernet  HWaddr AA:BB:CC:...
  ///             UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
  ///             RX packets:12345 errors:0
  ///             RX bytes:1234567 (1.1 MB)  TX bytes:987654 (964.5 KB)
  static List<Map<String, String>> _parseIfconfig(String output) {
    final result = <Map<String, String>>[];
    // نقسّم على blocks بحيث كل block يبدأ باسم interface في العمود 0
    final lines = output.split('\n');
    Map<String, String>? current;
    for (final line in lines) {
      if (line.isEmpty) continue;
      // interface header (يبدأ بحرف في العمود 0، ليس space)
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        // نحفظ الـinterface السابق
        if (current != null && current['name'] != null) {
          result.add(current);
        }
        // اسم الـinterface هو أوّل token
        final name = line.split(RegExp(r'\s+')).first;
        current = {'name': name};
        // hwaddr قد يكون في نفس السطر
        final hw =
            RegExp(r'HWaddr\s+([0-9A-Fa-f:]+)').firstMatch(line)?.group(1);
        if (hw != null) current['hwaddr'] = hw;
        // flags
        final up = line.contains('UP') || line.contains('RUNNING');
        current['up'] = up ? 'true' : 'false';
      } else if (current != null) {
        // detail line
        if (current['hwaddr'] == null) {
          final hw = RegExp(r'HWaddr\s+([0-9A-Fa-f:]+)|ether\s+([0-9A-Fa-f:]+)')
              .firstMatch(line);
          if (hw != null) current['hwaddr'] = hw.group(1) ?? hw.group(2) ?? '';
        }
        final rxBytes =
            RegExp(r'RX\s+bytes:(\d+)|RX packets \d+\s+bytes\s+(\d+)')
                .firstMatch(line);
        if (rxBytes != null) {
          current['rx_bytes'] = rxBytes.group(1) ?? rxBytes.group(2) ?? '';
        }
        final txBytes =
            RegExp(r'TX\s+bytes:(\d+)|TX packets \d+\s+bytes\s+(\d+)')
                .firstMatch(line);
        if (txBytes != null) {
          current['tx_bytes'] = txBytes.group(1) ?? txBytes.group(2) ?? '';
        }
        // flags جميعاً في السطر الثاني عادة
        if (line.contains('UP') || line.contains('RUNNING')) {
          current['up'] = 'true';
        }
      }
    }
    if (current != null && current['name'] != null) {
      result.add(current);
    }
    return result;
  }
}

class UbntException implements Exception {
  final String message;
  UbntException(this.message);
  @override
  String toString() => message;
}

// ═══════════════════════════════════════════════════════════
// Models — mca-status parser
// ═══════════════════════════════════════════════════════════

class UbntStats {
  final int apiVersion; // 5 (SSH-based → نعتبرها 5+)
  final UbntHost host;
  final UbntWireless? wireless;
  final List<UbntInterface> interfaces;
  final List<UbntStation> stations;
  // ── airFiber 60 & LR extras ─────────────────────────
  final double? latitude;
  final double? longitude;
  final int? memTotalKb;
  final int? memFreeKb;
  final int? memBuffersKb;
  final String? lanSpeed; // "1000Mbps-Full" — من mca-status لـairFiber

  const UbntStats({
    this.apiVersion = 5,
    required this.host,
    this.wireless,
    this.interfaces = const [],
    this.stations = const [],
    this.latitude,
    this.longitude,
    this.memTotalKb,
    this.memFreeKb,
    this.memBuffersKb,
    this.lanSpeed,
  });

  // 2026-08-18: أقواس صريحة — `??` أدنى precedence من `||` فالكود الأصلي
  // كان يقرأ: `contains('ap') ?? (false || contains('master'))` → الـfallback
  // ما يعمل إلا لو wireless == null (مستحيل — الـgetters عبر ?.).
  bool get isAp {
    final m = wireless?.mode.toLowerCase();
    if (m == null) return false;
    return m.contains('ap') || m.contains('master');
  }

  bool get isStation {
    final m = wireless?.mode.toLowerCase();
    if (m == null) return false;
    return m.contains('sta') || m.contains('managed');
  }

  /// airFiber 60 (GP/LR) — يظهر عبر platform أو linked_60 من أي station.
  bool get isAirFiber60 {
    final model = host.devmodel.toLowerCase();
    if (model.contains('airfiber 60') || model.contains('af-60')) return true;
    return stations.any((s) => s.isLinked60);
  }

  /// نسبة الذاكرة المُستعملة (%)
  double? get memUsedPercent {
    final total = memTotalKb ?? 0;
    if (total <= 0) return null;
    final free = memFreeKb ?? 0;
    final buffers = memBuffersKb ?? 0;
    final used = total - free - buffers;
    if (used < 0) return 0;
    return (used / total * 100).clamp(0, 100);
  }

  /// كمية الرام المُستعملة بالميجابايت
  int? get memUsedMb {
    final total = memTotalKb ?? 0;
    if (total <= 0) return null;
    final free = memFreeKb ?? 0;
    final buffers = memBuffersKb ?? 0;
    return ((total - free - buffers) / 1024).round();
  }

  /// كمية الرام الكلّيّة بالميجابايت
  int? get memTotalMb {
    final t = memTotalKb ?? 0;
    return t > 0 ? (t / 1024).round() : null;
  }

  /// هل الإحداثيّات مُعرَّفة (غير 0,0)؟
  bool get hasLocation =>
      (latitude != null && latitude != 0) ||
      (longitude != null && longitude != 0);

  /// يبني من mca-status output map + interfaces + wstalist stations (اختياريّان)
  factory UbntStats.fromMcaStatus(
    Map<String, String> m, {
    List<Map<String, String>> interfaces = const [],
    List<Map<String, dynamic>> wstalistStations = const [],
  }) {
    // mca-status keys شائعة (تختلف قليلاً حسب الإصدار):
    // deviceId, firmwareVersion, deviceName, uptime,
    // cpuLoadAvg, temperature, memTotal, memFree, memBuffers, memCached,
    // wlanRxRate, wlanTxRate, wlanSignal, wlanNoiseFloor,
    // wlanChan, wlanChanWidth, wlanEssid, wlanMode, wlanFrequency, wlanCcq,
    // wlanConnections, wlanTxPower
    // + إذا AP: station1_mac, station1_signal, station1_ccq, station1_ip, ...

    // CPU:
    // - airOS 5/6/7/8 traditional: cpuload=12 (int) أو cpuLoadAvg=(0.05 0.03 0.00)
    // - airFiber 60 GP: cpuUsage=12.5 (float مباشرة كنسبة مئويّة)
    //   بينما loadavg=54 (نسبة مئويّة أيضاً، NOT decimal load)
    int cpuValue = 0;
    if (m['cpuUsage'] != null) {
      cpuValue = (double.tryParse(m['cpuUsage']!) ?? 0).round();
    } else if (m['cpuload'] != null) {
      cpuValue = _n(m['cpuload']);
    } else if (m['loadavg'] != null) {
      final la = double.tryParse(m['loadavg']!) ?? 0;
      // heuristic: لو > 10 فهي نسبة مئويّة، وإلا decimal load (×100)
      cpuValue = la > 10 ? la.round() : (la * 100).round();
    } else {
      cpuValue = _cpuFromLoadAvg(m['cpuLoadAvg']) ?? 0;
    }

    final host = UbntHost(
      hostname: m['deviceName'] ?? m['hostname'] ?? m['essid'] ?? '',
      devmodel: m['platform'] ?? m['deviceId'] ?? '',
      fwversion: m['firmwareVersion'] ?? m['fwVersion'] ?? '',
      uptime: _n(m['uptime']),
      cpuload: cpuValue,
      temperature: _n(m['temperature']),
    );

    // Wireless:
    // - airMax/airOS: wlanSignal/wlanEssid/wlanTxRate...
    // - airFiber 60 GP: signal/essid/wlanTxRate=0 (real rates from wstalist.prs_sta)
    // نتقبّل essid من أي مصدر
    final essid = m['wlanEssid'] ?? m['essid'] ?? '';
    UbntWireless? wireless;
    if (essid.isNotEmpty ||
        m.containsKey('wlanSignal') ||
        m.containsKey('signal')) {
      // signal الرئيسي: airFiber يعطي signal=-93 (WLAN إدارة) والحقيقي في prs_sta
      // نُفضّل signal من station لو موجود بقيمة معقولة
      int signal = _n(m['wlanSignal']);
      if (signal == 0 || signal == -93) {
        // fallback لـstation1 لو mca-status ما جاب signal معقول
        final stSig = _n(m['station1_signal']);
        if (stSig != 0 && stSig > -95) signal = stSig;
      }
      if (signal == 0) signal = _n(m['signal']);

      // rates: airFiber يعطي 0 في mca-status، الحقيقي في station.prs_sta.capacity
      int txRate = _n(m['wlanTxRate']);
      int rxRate = _n(m['wlanRxRate']);
      if (txRate == 0) {
        txRate = _n(m['station1_tx_capacity']) ~/ 1000; // Kbps → Mbps
      }
      if (rxRate == 0) rxRate = _n(m['station1_rx_capacity']) ~/ 1000;

      // CCQ: أسماء متعدّدة في mca-status حسب الإصدار
      int ccq = _n(m['wlanCcq']);
      if (ccq == 0) ccq = _n(m['ccq']);
      if (ccq == 0) ccq = _n(m['wlanTxCcq']);
      if (ccq == 0) ccq = _n(m['tx_ccq']);
      if (ccq == 0) ccq = _n(m['station1_ccq']);
      // AC firmware ما يعطي wlanCcq، لكن يعطي wlanDownlinkCapacity + wlanTxRate.
      // نحسب quality% من ratio: (currentRate / maxCapacity) * 100
      // مثال: TxRate=138 Mbps، DownlinkCapacity=106700 Kbps=106.7 Mbps
      //   ratio = min(138/106.7, 1.0) = 1.0 → 100%
      // ratio أقلّ من 100% يعني الجهاز مو يستغلّ السعة الكاملة → quality أقلّ.
      if (ccq == 0) {
        final txRateKbps =
            ((double.tryParse(m['wlanTxRate'] ?? '0') ?? 0) * 1000).round();
        final dlCapKbps = _n(m['wlanDownlinkCapacity']);
        if (txRateKbps > 0 && dlCapKbps > 0) {
          ccq = ((txRateKbps / dlCapKbps) * 100).clamp(0, 100).round();
        }
      }
      // بعض إصدارات airOS ترجع CCQ ×10 (مثل 961 يعني 96.1%)
      if (ccq > 100 && ccq <= 1000) ccq = (ccq / 10).round();
      if (ccq > 100) ccq = 100;

      wireless = UbntWireless(
        essid: essid,
        mode: _normalizeMode(m['wlanMode'] ?? m['wlanOpmode'] ?? ''),
        signal: signal,
        noise: _n(m['wlanNoiseFloor']) != 0
            ? _n(m['wlanNoiseFloor'])
            : _n(m['noise']),
        // explicit SNR من station لو موجود (airFiber 60 يعطي prs_sta.snr)
        explicitSnr: _n(m['station1_snr']),
        ccq: ccq,
        txRate: txRate,
        rxRate: rxRate,
        channel: _n(m['wlanChan']),
        frequency: _n(m['wlanFrequency']) != 0
            ? _n(m['wlanFrequency'])
            : _n(m['freq']),
        distance: _n(m['wlanDistance']) != 0
            ? _n(m['wlanDistance'])
            : _n(m['station1_distance']),
        chanbw: _n(m['wlanChanWidth']) != 0
            ? _n(m['wlanChanWidth'])
            : _n(m['chanbw']),
      );
    }

    // Stations: نُفضّل wstalist (JSON — أدقّ وأكمل) على mca-status
    final stations = <UbntStation>[];
    if (wstalistStations.isNotEmpty) {
      // wstalist format:
      // airMax: {"mac":"AA:BB:...", "lastip":"192.168.1.10", "name":"host1",
      //         "signal":-58, "noisefloor":-95, "ccq":100, "tx":150, "rx":135,
      //         "uptime":12345, "tx_bytes":..., "rx_bytes":..., "rssi":58}
      // airFiber 60: نفس المفاتيح + prs_sta nested فيه rssi_data/snr/capacity/mcs
      for (final s in wstalistStations) {
        final remote =
            (s['remote'] as Map?)?.cast<String, dynamic>() ?? const {};
        final prs = (s['prs_sta'] as Map?)?.cast<String, dynamic>();

        // إشارة: airFiber → prs_sta.rssi_data | airMax → s.signal
        final signal = _n(prs?['rssi_data'] ?? s['signal'] ?? s['rssi']);
        // TX signal (كيف العميل يستقبل منّا) — أسماء متعدّدة حسب الإصدار:
        //   airOS 5/6:  s['remote_signal'] أو s['ap_signal']
        //   airOS 7+:   s['tx']['signal'] أو s['tx_signal']
        //   airFiber:   prs_sta.dl_signal_expect (متوقّع، أقرب مؤشّر)
        int txSig = _n(s['remote_signal'] ?? s['ap_signal'] ?? s['tx_signal']);
        if (txSig == 0 && s['tx'] is Map) {
          txSig = _n((s['tx'] as Map)['signal']);
        }
        // معدّلات: airFiber → prs_sta.capacity Kbps → Mbps
        final dlCap =
            prs?['dl_capacity'] != null ? _n(prs!['dl_capacity']) : null;
        final ulCap =
            prs?['ul_capacity'] != null ? _n(prs!['ul_capacity']) : null;
        final txRateMbps =
            dlCap != null ? (dlCap / 1000).round() : _n(_extractRate(s['tx']));
        final rxRateMbps =
            ulCap != null ? (ulCap / 1000).round() : _n(_extractRate(s['rx']));

        // CCQ من أماكن متعدّدة — نفس منطق _mergeStationsFromWstalist
        // CCQ للـclients — أسماء متعدّدة حسب firmware:
        //   XM (5/6):  s['ccq']                      = 95
        //   AC (7+):   s['airmax']['ccq']            = 95
        //              أو s['airmax']['quality']     = 95 (اسم بديل شائع في AC)
        //              أو s['airmax']['priority']    = 95 (بعض إصدارات AC)
        //   airOS 8:   s['tx']['ccq']، s['rx']['ccq']
        //   airMax AC: أحياناً quality في top-level
        int ccqValue = _n(s['ccq']);
        if (ccqValue == 0) ccqValue = _n(s['quality']);
        if (ccqValue == 0 && s['airmax'] is Map) {
          final am = s['airmax'] as Map;
          ccqValue = _n(am['ccq']);
          if (ccqValue == 0) ccqValue = _n(am['quality']);
          if (ccqValue == 0) ccqValue = _n(am['priority']);
        }
        if (ccqValue == 0 && s['tx'] is Map) {
          ccqValue = _n((s['tx'] as Map)['ccq']);
        }
        if (ccqValue == 0 && s['rx'] is Map) {
          ccqValue = _n((s['rx'] as Map)['ccq']);
        }
        // بعض إصدارات airOS ترجع CCQ ×10 (961 → 96.1%)
        if (ccqValue > 100 && ccqValue <= 1000) {
          ccqValue = (ccqValue / 10).round();
        }
        if (ccqValue > 100) ccqValue = 100;

        // Debug (مرّة واحدة لأوّل station) — نعرف أسماء fields الحقيقيّة
        if (kDebugMode && ccqValue == 0 && wstalistStations.indexOf(s) == 0) {
          debugPrint('🔵 [ubnt CCQ] first station keys: ${s.keys.toList()}');
          if (s['airmax'] is Map) {
            debugPrint(
                '🔵 [ubnt CCQ] airmax keys: ${(s['airmax'] as Map).keys.toList()}');
          }
        }

        // Hostname resolution — تعقيدات firmware:
        //   - airFiber 60 PtP (station واحد): s['name'] = اسم الـpeer الحقيقي ("pola")
        //   - airMax AC PtMP (stations متعدّدة): s['name'] = ESSID للـAP نفسه!
        //     (كل الـclients يشتركون بنفس القيمة — مضلّل)
        // الحل: نُفضّل s['hostname'] (DHCP hostname الحقيقي).
        //   ثمّ remote.hostname / device_name.
        //   ثمّ s['name'] فقط لو الجهاز single-station (airFiber).
        //   وإلا نتركه null → الـUI يعرض MAC.
        final isSingleStation = wstalistStations.length == 1;
        final hostRaw = _strOrNull(s['hostname']) ??
            _strOrNull(remote['hostname']) ??
            _strOrNull(remote['device_name']) ??
            (isSingleStation ? _strOrNull(s['name']) : null);

        stations.add(UbntStation(
          mac: (s['mac'] ?? '').toString(),
          ip: _strOrNull(s['lastip']) ?? _strOrNull(remote['ip']),
          hostname: hostRaw,
          signal: signal,
          txSignal: txSig,
          noise: _n(s['noisefloor']),
          ccq: ccqValue,
          txRate: txRateMbps,
          rxRate: rxRateMbps,
          connTime: _n(s['uptime'] ?? s['conn_time']),
          explicitSnr: prs?['snr'] != null ? _n(prs!['snr']) : null,
          txMcs: prs?['tx_mcs'] != null ? _n(prs!['tx_mcs']) : null,
          rxMcs: prs?['rx_mcs'] != null ? _n(prs!['rx_mcs']) : null,
          distanceMeters:
              prs?['distance'] != null ? _n(prs!['distance']) : null,
          linkUptimeSec: prs?['uptime'] != null ? _n(prs!['uptime']) : null,
          dlSignalExpect: prs?['dl_signal_expect'] != null
              ? _n(prs!['dl_signal_expect'])
              : null,
          ulSignalExpect: prs?['ul_signal_expect'] != null
              ? _n(prs!['ul_signal_expect'])
              : null,
          dlCapacityKbps: dlCap,
          ulCapacityKbps: ulCap,
          dlCapacityExpectKbps: prs?['dl_capacity_expect'] != null
              ? _n(prs!['dl_capacity_expect'])
              : null,
          ulCapacityExpectKbps: prs?['ul_capacity_expect'] != null
              ? _n(prs!['ul_capacity_expect'])
              : null,
          txSector: prs?['tx_sector'] != null ? _n(prs!['tx_sector']) : null,
          rxSector: prs?['rx_sector'] != null ? _n(prs!['rx_sector']) : null,
          isLinked60: s['linked_60'] == true,
        ));
      }
    } else {
      // fallback: mca-status station1_*, station2_*, ...
      for (int i = 1; i <= 128; i++) {
        final mac = m['station${i}_mac'];
        if (mac == null || mac.isEmpty) break;
        stations.add(UbntStation(
          mac: mac,
          ip: m['station${i}_ip'],
          hostname: m['station${i}_name'] ?? m['station${i}_hostname'],
          signal: _n(m['station${i}_signal']),
          noise: _n(m['station${i}_noise']),
          ccq: _n(m['station${i}_ccq']),
          txRate: _n(m['station${i}_tx']),
          rxRate: _n(m['station${i}_rx']),
          connTime: _n(m['station${i}_uptime']),
        ));
      }
    }

    // Interfaces من ifconfig
    final ifs = interfaces
        .map((raw) {
          final speed = _n(raw['speed']);
          return UbntInterface(
            ifname: raw['name'] ?? '',
            hwaddr: raw['hwaddr'] ?? '',
            enabled: raw['up'] == 'true',
            plugged: raw['up'] == 'true',
            rxBytes: int.tryParse(raw['rx_bytes'] ?? ''),
            txBytes: int.tryParse(raw['tx_bytes'] ?? ''),
            speed: speed > 0 ? speed : null,
          );
        })
        .where((i) => i.ifname.isNotEmpty && i.ifname != 'lo')
        .toList();

    return UbntStats(
      host: host,
      wireless: wireless,
      interfaces: ifs,
      stations: stations,
      latitude: double.tryParse(m['latitude'] ?? ''),
      longitude: double.tryParse(m['longitude'] ?? ''),
      memTotalKb: _n(m['memTotal']) > 0 ? _n(m['memTotal']) : null,
      memFreeKb: _n(m['memFree']) > 0 ? _n(m['memFree']) : null,
      memBuffersKb: _n(m['memBuffers']) > 0 ? _n(m['memBuffers']) : null,
      lanSpeed: _strOrNull(m['lanSpeed']),
    );
  }

  /// helper: بعض airMax يعطي tx/rx كـMap {rate: 150} — نستخرج الـrate فقط
  static dynamic _extractRate(dynamic v) {
    if (v == null) return 0;
    if (v is Map) return v['rate'] ?? 0;
    return v;
  }

  static int? _cpuFromLoadAvg(String? loadAvg) {
    if (loadAvg == null || loadAvg.isEmpty) return null;
    // Format: "0.05 0.03 0.00" أو "(0.05 0.03 0.00)"
    final cleaned = loadAvg.replaceAll(RegExp(r'[()]'), '').trim();
    final parts = cleaned.split(RegExp(r'[,\s]+'));
    if (parts.isEmpty) return null;
    final load = double.tryParse(parts.first);
    return load == null ? null : (load * 100).round();
  }

  static String _normalizeMode(String raw) {
    final low = raw.toLowerCase();
    // mca-status: "master" = AP، "managed"/"station" = STA
    // نحوّل لصيغة موحّدة مثل airOS 8: ap-ptp/sta-ptp/ap-ptmp/sta-ptmp
    if (low.contains('master') || low.contains('ap')) return 'ap-ptmp';
    if (low.contains('managed') ||
        low.contains('station') ||
        low.contains('sta')) {
      return 'sta-ptp';
    }
    return raw;
  }
}

class UbntHost {
  final String hostname;
  final String devmodel;
  final String fwversion;
  final int uptime;
  final int cpuload;
  final int temperature;

  const UbntHost({
    required this.hostname,
    required this.devmodel,
    required this.fwversion,
    required this.uptime,
    required this.cpuload,
    required this.temperature,
  });
}

class UbntWireless {
  final String essid;
  final String mode;
  final int signal;
  final int noise; // 0 = غير متوفّر (airFiber 60GHz)
  final int explicitSnr; // من station.prs_sta.snr (0 = غير متوفّر)
  final int ccq; // 0 = غير متوفّر
  final int txRate;
  final int rxRate;
  final int channel;
  final int frequency;
  final int distance;
  final int chanbw;

  const UbntWireless({
    required this.essid,
    required this.mode,
    required this.signal,
    required this.noise,
    this.explicitSnr = 0,
    required this.ccq,
    required this.txRate,
    required this.rxRate,
    required this.channel,
    required this.frequency,
    required this.distance,
    required this.chanbw,
  });

  /// SNR — يُفضّل explicit من الجهاز (wstalist prs_sta.snr) على المحسوب
  int? get snr {
    if (explicitSnr > 0) return explicitSnr;
    if (noise != 0 && signal != 0) return (signal - noise).abs();
    return null; // غير متوفّر
  }

  bool get hasNoise => noise != 0;
  bool get hasCcq => ccq != 0;

  /// dBm → % — mapping خطّي: -95 dBm = 0% | -40 dBm = 100%
  /// مثال: -55 dBm = (40/55)*100 = 72.7%
  double get signalQualityPercent {
    if (signal >= -40) return 100.0;
    if (signal <= -95) return 0.0;
    return ((signal + 95) / 55 * 100).clamp(0.0, 100.0);
  }
}

class UbntInterface {
  final String ifname;
  final String hwaddr;
  final bool enabled;
  final bool plugged;
  final int? rxBytes;
  final int? txBytes;
  final int? speed;
  final bool duplex;

  const UbntInterface({
    required this.ifname,
    required this.hwaddr,
    required this.enabled,
    required this.plugged,
    this.rxBytes,
    this.txBytes,
    this.speed,
    this.duplex = false,
  });
}

class UbntStation {
  final String mac;
  final String? ip;
  final String? hostname;
  final int signal; // RX: كيف الـAP يستقبل من هذا العميل
  final int txSignal; // TX: كيف العميل يستقبل منّا. 0 = غير متوفّر
  final int noise;
  final int ccq;
  final int txRate;
  final int rxRate;
  final int connTime;
  // ── airFiber 60 & LR (PtP link view) ─────────────────
  final int? explicitSnr; // من prs_sta.snr
  final int? txMcs;
  final int? rxMcs;
  final int? distanceMeters; // prs_sta.distance
  final int? linkUptimeSec; // prs_sta.uptime (منفصل عن system uptime)
  final int? dlSignalExpect; // -47 مثلاً
  final int? ulSignalExpect;
  final int? dlCapacityKbps; // 1951000
  final int? ulCapacityKbps;
  final int? dlCapacityExpectKbps;
  final int? ulCapacityExpectKbps;
  final int? txSector;
  final int? rxSector;
  final bool isLinked60;

  const UbntStation({
    required this.mac,
    this.ip,
    this.hostname,
    required this.signal,
    this.txSignal = 0,
    required this.noise,
    required this.ccq,
    required this.txRate,
    required this.rxRate,
    required this.connTime,
    this.explicitSnr,
    this.txMcs,
    this.rxMcs,
    this.distanceMeters,
    this.linkUptimeSec,
    this.dlSignalExpect,
    this.ulSignalExpect,
    this.dlCapacityKbps,
    this.ulCapacityKbps,
    this.dlCapacityExpectKbps,
    this.ulCapacityExpectKbps,
    this.txSector,
    this.rxSector,
    this.isLinked60 = false,
  });

  /// عرض الإشارة بترتيب سكتر/عميل — أوّل رقم = ما يستقبله السكتر من
  /// هذا العميل (الأهمّ لمن يدير الشبكة)، وثاني رقم = ما يستقبله العميل
  /// من السكتر (مؤشّر جودة الوصل من طرف العميل).
  ///
  /// 2026-08-25: قُلبت الترتيب. كان "$txSignal/$signal" — أوّل رقم كان
  /// جهة العميل، وهذا كان مشوّشاً للمدير الذي يشاهد سكتر PtMP ويريد
  /// فوراً معرفة كيف *الجهاز* يستقبل من كل عميل. الآن sector-first.
  String get signalDisplay {
    if (txSignal != 0) return '$signal/$txSignal';
    return '$signal';
  }

  /// SNR — يُفضّل explicit من prs_sta على المحسوب
  int? get snr {
    if (explicitSnr != null && explicitSnr! > 0) return explicitSnr;
    if (noise != 0 && signal != 0) return (signal - noise).abs();
    return null;
  }

  /// هامش الإشارة عن المتوقّع (dB) — سالب = ضعف عن الأمثل
  int? get signalMargin {
    if (dlSignalExpect == null || signal == 0) return null;
    return signal - dlSignalExpect!;
  }

  /// نسبة استغلال السعة (0-100%) — كم % من max capacity المتوقّع نستعمله
  double? get capacityUtilization {
    final actual = dlCapacityKbps ?? 0;
    final expect = dlCapacityExpectKbps ?? 0;
    if (actual <= 0 || expect <= 0) return null;
    return (actual / expect * 100).clamp(0, 100);
  }

  /// أعلى capacity متوفّرة (Mbps) — نُفضّل dl على ul لو موجود
  int? get capacityMbps {
    final k = dlCapacityKbps ?? ulCapacityKbps ?? 0;
    return k > 0 ? (k / 1000).round() : null;
  }
}

// ── Utilities
String? _strOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

int _n(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  if (s.isEmpty) return 0;
  return int.tryParse(s) ?? (double.tryParse(s)?.toInt() ?? 0);
}

/// جلسة SSH معمَّرة لقياس الترافيك اللحظي على جهاز مشترك.
///
/// ⚠️ **لماذا صنف منفصل ولا نستعمل `UbntApi.fetchStats`**: تلك تفتح
/// جلسة وتُغلقها في كلّ نداء، وتُنفّذ 4-10 أوامر بسقف 8-10 ثوانٍ. عند
/// نبضة كلّ 3 ثوانٍ تعني مصافحة تشفير كاملة كلّ 3 ثوانٍ على معالج CPE
/// ضعيف وظيفته تمرير حزم المشترك — أداة القياس تُفسد ما تقيسه،
/// وتتراكب الدورات لأنّ سقفها أطول من الفاصل.
///
/// هنا: مصافحة **واحدة** لعمر الكارت، ثمّ أمر واحد يتيم في كلّ نبضة.
/// و`/proc/net/dev` لا `ifconfig`: صيغته ثابتة عبر كلّ نوى لينكس —
/// بينما `ifconfig` اختلف بين إصدارات airOS حتّى اضطُرّ المُحلِّل هنا
/// لتغطية صيغتين — وخرجه بضع مئات من البايتات.
class UbntTrafficSession {
  UbntTrafficSession._(this._client, this._socket);

  final SSHClient _client;
  final SSHSocket _socket;
  bool _closed = false;

  static Future<UbntTrafficSession?> open({
    required String ip,
    int port = 22,
    required String user,
    required String pass,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    SSHClient? client;
    SSHSocket? socket;
    try {
      socket = await SSHSocket.connect(ip, port, timeout: timeout);
      client = SSHClient(
        socket,
        username: user,
        onPasswordRequest: () => pass,
        onUserInfoRequest: (req) async => req.prompts.map((_) => pass).toList(),
      );
      await client.authenticated.timeout(timeout);
      return UbntTrafficSession._(client, socket);
    } catch (_) {
      // ⚠️ لا نجرّب أسماء مستخدمين احتياطيّة هنا خلافاً لـfetchStats:
      // أربع مصافحات فاشلة كلّ 3 ثوانٍ = 80 محاولة في الدقيقة، وdropbear
      // على airOS يُسجّلها وقد يحظر. فشل واحد صامت أفضل.
      try {
        client?.close();
        socket?.close();
      } catch (_) {}
      return null;
    }
  }

  /// مجموع البايتات على واجهات البيانات لحظة القراءة — تراكميّ لا معدّل.
  Future<({int down, int up})?> sample() async {
    if (_closed) return null;
    try {
      final out = utf8.decode(
        await _client
            .run('cat /proc/net/dev')
            .timeout(const Duration(seconds: 4)),
        allowMalformed: true,
      );
      return parseProcNetDev(out);
    } catch (_) {
      return null;
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _client.close();
      _socket.close();
    } catch (_) {}
  }

  /// يحلّل `/proc/net/dev` ويُرجع **تحميل ورفع المشترك**.
  ///
  /// ⚠️ واجهة واحدة لا مجموع الواجهات — وهذا جوهر الصحّة هنا:
  ///
  /// على CPE جسريّ، ما يدخل من الهواء على `ath0` يخرج على `eth0` إلى
  /// المشترك، والعكس. فجمعُ الواجهتين يجعل مجموع الاستقبال يساوي
  /// مجموع الإرسال **حتماً** — وهو ما ظهر للمستخدم: تحميل ورفع
  /// بالقيمة نفسها دائماً. (بلاغ 2026-08-30)
  ///
  /// والاتّجاه ينقلب بحسب الواجهة:
  /// · `ath0`/`wlan0` تواجه البرج → استقبالها = **تحميل** المشترك.
  /// · `eth0`/`br0` تواجه المشترك → استقبالها = **رفعه** (يرسل إلينا).
  ///
  /// خلط الاثنين يعطي رقمين معقولين تماماً ومقلوبين تماماً.
  static ({int down, int up})? parseProcNetDev(String out) {
    final byIface = <String, ({int rx, int tx})>{};
    for (final line in out.split('\n')) {
      final i = line.indexOf(':');
      if (i <= 0) continue;
      final name = line.substring(0, i).trim().toLowerCase();
      if (!_isDataIface(name)) continue;
      final f = line.substring(i + 1).trim().split(RegExp(r'\s+'));
      if (f.length < 9) continue;
      final r = int.tryParse(f[0]);
      final t = int.tryParse(f[8]);
      if (r == null || t == null) continue;
      byIface[name] = (rx: r, tx: t);
    }
    if (byIface.isEmpty) return null;

    // الأفضليّة للواجهة اللاسلكيّة: هي التي تحمل الحركة الحقيقيّة
    // للمشترك، وقياسها لا يتأثّر بحركة محلّيّة داخل شبكته.
    for (final n in byIface.keys) {
      if (n.startsWith('ath') || n.startsWith('wlan')) {
        final v = byIface[n]!;
        return (down: v.rx, up: v.tx);
      }
    }
    // وإلّا الواجهة السلكيّة — بالاتّجاه **مقلوباً**.
    for (final n in byIface.keys) {
      if (n.startsWith('eth') || n == 'br0') {
        final v = byIface[n]!;
        return (down: v.tx, up: v.rx);
      }
    }
    return null;
  }

  /// واجهات تحمل حركة المشترك. `lo` مستثناة، والواجهات الافتراضيّة
  /// كذلك لأنّها تُضاعف نفس البايتات.
  static bool _isDataIface(String n) =>
      n.startsWith('eth') ||
      n.startsWith('ath') ||
      n.startsWith('wlan') ||
      n == 'br0';
}
