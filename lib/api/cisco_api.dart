import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

/// **Cisco IOS API** — CLI عبر SSH أو Telnet، قراءة فقط.
///
/// **لماذا جلسة تفاعليّة لا `client.run()`**:
/// قناة exec في SSH غير مضمونة على IOS (خصوصاً 12.2 على 2960 —
/// وهو ما بين أيدينا فعليّاً). الجلسة التفاعليّة `shell()` تعمل على
/// كلّ إصدار، وهي **نفسها دلاليّاً** في Telnet: اكتب أمراً، اقرأ حتّى
/// الـprompt. لذلك محرّك أوامر واحد فوق نقلَين، والمحلّلات لا تعرف
/// أيّهما جاء منه النصّ.
///
/// **خادم SSH عتيق**: الأجهزة المختبَرة تعرض `SSH-2.0-Cisco-1.25`
/// بـ`diffie-hellman-group1-sha1` و`aes*-cbc` فقط. OpenSSH الحديث
/// يرفضها، لكنّ `dartssh2` يدعمها ضمن قوائمه الافتراضيّة — فلا نضبط
/// خوارزميّات يدويّاً. (فشل `ssh` في الطرفيّة ليس دليلاً على فشل
/// التطبيق.)
///
/// **قراءة فقط**: `show ...` حصراً. لا `configure terminal` ولا
/// `write`. الاستثناء الوحيد `terminal length 0` — وهي إعداد طرفيّة
/// للجلسة الجارية لا يُكتَب في الإعدادات، ونتراجع إلى معالجة
/// `--More--` يدويّاً إن رفضها الجهاز.
class CiscoApi {
  // ── أوامر أساسيّة (لا تنجح اللقطة بدونها) ──
  static const _cmdVersion = 'show version';
  static const _cmdIfStatus = 'show interfaces status';
  static const _cmdIfDetail = 'show interfaces';

  // ── أوامر اختياريّة (فشلها لا يُسقط اللقطة) ──
  static const _cmdCpuPiped = 'show processes cpu | include utilization';
  static const _cmdCpuFull = 'show processes cpu';
  static const _cmdMemory = 'show memory statistics';

  /// كشف الموديل — `show version` وحده، والجلسة تُغلق في `finally`.
  ///
  /// يرجع `null` (لا يرمي) عند أيّ تعذّر، لأنّ نداءه من كاشف الموديل
  /// يجري ضمن مسحٍ جماعيّ لا يصحّ أن يتعطّل لجهازٍ واحد.
  static Future<String?> detectModel({
    required String host,
    required String user,
    required String pass,
    int? port,
    String protocol = 'ssh',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    _CiscoCli? cli;
    try {
      cli = await _CiscoCli.connect(
        host: host,
        user: user,
        pass: pass,
        port: port,
        protocol: protocol,
        timeout: timeout,
      );
      final out = await cli.run(_cmdVersion, timeout: timeout);
      return CiscoParse.version(out).model;
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Cisco detectModel($host) فشل: $e');
      return null;
    } finally {
      await cli?.close();
    }
  }

  /// **إعادة تشغيل السويتش** (`reload`) — العمليّة الوحيدة غير القرائيّة
  /// في هذه الطبقة.
  ///
  /// لا يوجد «إطفاء» على Catalyst: لا `poweroff` ولا `halt`. أقصى ما
  /// في IOS إعادةُ تشغيل، ويعود الجهاز وحده بعد دقيقة إلى دقيقتين.
  ///
  /// **النجاح يُعرَف بموت الجلسة** لا بردٍّ يصل — الجهاز يقطع كلّ شيء
  /// لحظة التنفيذ. ولا نحفظ الإعدادات عند السؤال (انظر [_CiscoCli.reload]).
  ///
  /// ولا نلمس المنافذ: `shutdown` تحتاج وضع الإعدادات، وهو خارج نطاق
  /// هذه الطبقة عمداً.
  static Future<void> rebootDevice({
    required String host,
    required String user,
    required String pass,
    int? port,
    String protocol = 'ssh',
    Duration timeout = const Duration(seconds: 20),
  }) async {
    _CiscoCli? cli;
    try {
      cli = await _CiscoCli.connect(
        host: host,
        user: user,
        pass: pass,
        port: port,
        protocol: protocol,
        timeout: timeout,
      );
      await cli.reload(timeout: timeout);
    } finally {
      await cli?.close();
    }
  }

  /// اللقطة الكاملة.
  ///
  /// [includeCounters] يشغّل `show interfaces` (≈٤٠ كيلوبايت على
  /// سويتش ٢٤ منفذاً). أطفئه في المسارات الجماعيّة؛ اتركه في اللوحة.
  static Future<CiscoStats> fetchStats({
    required String host,
    required String user,
    required String pass,
    int? port,
    String protocol = 'ssh',
    Duration timeout = const Duration(seconds: 25),
    bool includeCounters = true,
    void Function(CiscoStats partial)? onPartialReady,
  }) async {
    _CiscoCli? cli;
    try {
      cli = await _CiscoCli.connect(
        host: host,
        user: user,
        pass: pass,
        port: port,
        protocol: protocol,
        timeout: timeout,
      );

      // ═══ Tier 1: الهويّة — تكفي لرسم الرأس فوراً ═══
      final version =
          CiscoParse.version(await cli.run(_cmdVersion, timeout: timeout));
      var stats = CiscoStats(
        model: version.model,
        iosVersion: version.iosVersion,
        hostname: version.hostname ?? cli.hostname,
        serial: version.serial,
        uptime: version.uptime,
        mainMemKb: version.mainMemKb,
        ioMemKb: version.ioMemKb,
      );
      onPartialReady?.call(stats);

      // ═══ Tier 2: المنافذ وحالتها (صغير وسريع) ═══
      var ifaces = <CiscoInterface>[];
      try {
        ifaces = CiscoParse.interfacesStatus(
            await cli.run(_cmdIfStatus, timeout: timeout));
        stats = stats.copyWith(ifaces: ifaces);
        onPartialReady?.call(stats);
      } catch (e) {
        if (kDebugMode) debugPrint('⚠️ Cisco $_cmdIfStatus فشل: $e');
      }

      // ═══ Tier 3 (اختياريّ): CPU + الذاكرة ═══
      double? cpuPercent;
      try {
        var cpuOut = await cli.run(_cmdCpuPiped, timeout: timeout);
        // بعض الإصدارات لا تعرف الأنبوب — نعيدها كاملةً ونأخذ سطرها الأوّل.
        if (CiscoParse.isUnsupportedCommand(cpuOut)) {
          cpuOut = await cli.run(_cmdCpuFull, timeout: timeout);
        }
        cpuPercent = CiscoParse.cpuPercent(cpuOut);
      } catch (e) {
        if (kDebugMode) debugPrint('ℹ️ Cisco CPU غير متاح: $e');
      }

      CiscoMemory? memory;
      try {
        memory = CiscoParse.memory(await cli.run(_cmdMemory, timeout: timeout));
      } catch (e) {
        if (kDebugMode) debugPrint('ℹ️ Cisco memory غير متاحة: $e');
      }

      stats = stats.copyWith(cpuPercent: cpuPercent, memory: memory);
      onPartialReady?.call(stats);

      // ═══ Tier 4 (اختياريّ، الأثقل): العدّادات ═══
      if (includeCounters) {
        try {
          final detail = CiscoParse.interfacesDetail(
              await cli.run(_cmdIfDetail, timeout: timeout));
          stats = stats.copyWith(ifaces: CiscoParse.merge(ifaces, detail));
        } catch (e) {
          if (kDebugMode) debugPrint('⚠️ Cisco $_cmdIfDetail فشل: $e');
        }
      }

      // لقطةٌ بلا هويّةٍ ولا منافذ ليست نجاحاً: الجلسة قد تكون فتحت
      // ودخلت ثمّ لم يُقرأ منها شيء (محثٌّ عالق، صدى مُطفأ، صلاحيّات
      // ناقصة). إظهارها كبطاقةٍ فارغة يُخفي العطل بدل أن يُظهره.
      if (stats.model == null && stats.iosVersion == null &&
          stats.ifaces.isEmpty) {
        throw CiscoException(
            'تمّ الدخول إلى $host لكن لم تُقرأ أيّ مخرجات.\n'
            'قد يكون المستخدم بلا صلاحيّة تنفيذ أوامر show، '
            'أو المحثّ غير معتاد.');
      }

      if (kDebugMode) {
        debugPrint('══════ Cisco snapshot ($protocol) ══════');
        debugPrint('  model:  ${stats.model}  ios: ${stats.iosVersion}');
        debugPrint('  host:   ${stats.hostname}  up: ${stats.uptime}');
        debugPrint('  cpu:    ${stats.cpuPercent}  mem: ${stats.memPercent}');
        debugPrint('  ifaces: ${stats.ifaces.length}');
        debugPrint('═══════════════════════════════════════');
      }
      return stats;
    } finally {
      await cli?.close();
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Parsers — دوالّ صرفة، لا تعرف النقل، وهي المُختبَرة
// ═══════════════════════════════════════════════════════════

/// محلّلات مخرجات IOS. كلّها ثابتة وبلا حالة ولا إدخال/إخراج —
/// لذلك تُختبَر بنصٍّ ملتقَط من جهازٍ حقيقيّ بلا شبكة.
class CiscoParse {
  // ── تنظيف ──

  /// `--More--` يمحو نفسه بـbackspace ثمّ يُكمل **على السطر نفسه**:
  /// ```
  /// Internet address is 10.100.19.254/24
  ///  --More-- \b\b\b\b\b\b\b\b\b        \b\b\b\b\b\b\b\b\b  MTU 1500 bytes, BW ...
  /// ```
  /// لذلك الحذف على مستوى **النصّ** لا السطر — الحذف السطريّ يبتلع
  /// `MTU 1500` معه. ونقف عند آخر backspace كي لا نأكل مسافات
  /// المحتوى التالي (وهي ذات معنى في الأعمدة الثابتة).
  static final _moreErase =
      RegExp(r'[ \t]*--More--[ \t]*(?:\x08+[ \t]*)*\x08+');
  static final _morePlain = RegExp(r'[ \t]*--More--[ \t]*');

  static String stripPaging(String raw) {
    var t = raw.replaceAll('\r\n', '\n').replaceAll('\r', '');
    t = t.replaceAll(_moreErase, '');
    t = t.replaceAll(_morePlain, '');
    return t;
  }

  /// يزيل صدى الأمر وسطر الـprompt الأخير.
  static String clean(String raw, {String? command}) {
    final lines = stripPaging(raw).split('\n');
    if (command != null) {
      while (lines.isNotEmpty && lines.first.trim().isEmpty) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty && lines.first.trim() == command.trim()) {
        lines.removeAt(0);
      }
    }
    // سطر الـprompt الأخير (`name#` أو `name>`) ليس مخرجاً.
    while (lines.isNotEmpty) {
      final last = lines.last.trim();
      if (last.isEmpty || RegExp(r'^\S*[#>]$').hasMatch(last)) {
        lines.removeLast();
      } else {
        break;
      }
    }
    return lines.join('\n');
  }

  /// IOS يردّ بهذه عند أمرٍ لا يعرفه — ليست خطأ اتّصال.
  static bool isUnsupportedCommand(String out) {
    final t = out.toLowerCase();
    return t.contains('% invalid input') ||
        t.contains('% unknown command') ||
        t.contains('% incomplete command') ||
        t.contains('% ambiguous command');
  }

  // ── show version ──

  static final _reModelNumber =
      RegExp(r'^\s*Model number\s*:\s*(\S+)', multiLine: true);
  static final _reCiscoProcessor =
      RegExp(r'^cisco\s+(\S+)\s+\(.*?\)\s+processor', multiLine: true);
  static final _reMemPair = RegExp(r'with\s+(\d+)K/(\d+)K\s+bytes of memory');
  static final _reIosVersion =
      RegExp(r'IOS.*?Version\s+([^,\s]+)', caseSensitive: false);
  static final _reUptime = RegExp(r'^(\S+)\s+uptime is\s+(.+)$', multiLine: true);
  static final _reSerial =
      RegExp(r'^\s*System serial number\s*:\s*(\S+)', multiLine: true);
  static final _reBoardId = RegExp(r'Processor board ID\s+(\S+)');
  static final _reSwTable =
      RegExp(r'^\*?\s*\d+\s+\d+\s+(\S+)\s+(\S+)\s+\S+\s*$', multiLine: true);

  static CiscoVersionInfo version(String raw) {
    final t = clean(raw, command: CiscoApi._cmdVersion);

    // الموديل: «Model number» أسطع من سطر `cisco ... processor`، لأنّ
    // الثاني يحمل أحياناً اسم العائلة لا الطراز.
    String? model = _reModelNumber.firstMatch(t)?.group(1);
    model ??= _reCiscoProcessor.firstMatch(t)?.group(1);
    model ??= _reSwTable.firstMatch(t)?.group(1);

    // نسخة IOS: لا نأخذها من سطر BOOTLDR (يحمل نسخة المُحمِّل لا النظام).
    String? ios;
    for (final line in t.split('\n')) {
      if (line.startsWith('BOOTLDR') || line.contains('Boot Loader')) continue;
      final m = _reIosVersion.firstMatch(line);
      if (m != null) {
        ios = m.group(1);
        break;
      }
    }
    ios ??= _reSwTable.firstMatch(t)?.group(2);

    final up = _reUptime.firstMatch(t);
    final mem = _reMemPair.firstMatch(t);

    return CiscoVersionInfo(
      model: model,
      iosVersion: ios,
      hostname: up?.group(1),
      uptime: up == null ? null : parseUptime(up.group(2)!),
      serial: _reSerial.firstMatch(t)?.group(1) ??
          _reBoardId.firstMatch(t)?.group(1),
      mainMemKb: mem == null ? null : int.tryParse(mem.group(1)!),
      ioMemKb: mem == null ? null : int.tryParse(mem.group(2)!),
    );
  }

  /// «6 weeks, 1 day, 15 hours, 7 minutes» → Duration.
  static Duration? parseUptime(String s) {
    int unit(String name) {
      final m = RegExp(r'(\d+)\s+' + name).firstMatch(s);
      return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
    }

    final d = Duration(
      days: unit('year') * 365 + unit('week') * 7 + unit('day'),
      hours: unit('hour'),
      minutes: unit('minute'),
      seconds: unit('second'),
    );
    return d == Duration.zero ? null : d;
  }

  // ── show interfaces status ──

  /// أعمدة IOS هنا **ليست كلّها بمحاذاة يسار**: `Speed` يُحاذى يميناً،
  /// فـ`a-1000` (ستّة محارف) يبدأ قبل عمود العنوان بخانة، و`a-100`
  /// (خمسة) يبدأ عنده. تقطيعٌ ثابت للأعمدة يخلط `Duplex` بـ`Speed`:
  /// ```
  /// Duplex  Speed
  /// a-full a-1000     ← «a-full a» لو قطعنا بعرضٍ ثابت
  /// ```
  /// لذلك: عمودان ثابتان لـ`Port`/`Name` (يساريّان، و`Name` قد يحوي
  /// مسافات فلا يصحّ تقطيعه بالكلمات)، ثمّ تقطيعٌ بالكلمات لما بعد
  /// `Status` — فكلّها كلمةٌ واحدة عدا `Type` (قد تكون «Not Present»).
  static List<CiscoInterface> interfacesStatus(String raw) {
    final t = clean(raw, command: CiscoApi._cmdIfStatus);
    final out = <CiscoInterface>[];
    var nameStart = -1, statusStart = -1;

    for (final line in t.split('\n')) {
      if (line.trim().isEmpty) continue;

      // العنوان يتكرّر بعد كلّ كسر صفحة — نعيد ضبط الأعمدة منه لا نتخطّاه.
      if (line.contains('Port') && line.contains('Status')) {
        nameStart = line.indexOf('Name');
        statusStart = line.indexOf('Status');
        continue;
      }
      if (statusStart < 0 || line.length <= statusStart) continue;

      final port = nameStart > 0
          ? line.substring(0, nameStart).trim()
          : line.split(RegExp(r'\s+')).first.trim();
      if (port.isEmpty) continue;

      final desc = (nameStart > 0 && nameStart < statusStart)
          ? line.substring(nameStart, statusStart).trim()
          : '';
      final rest =
          line.substring(statusStart).trim().split(RegExp(r'\s+'));
      if (rest.isEmpty) continue;

      final status = rest[0];
      out.add(CiscoInterface(
        name: expandIfName(port),
        shortName: port,
        // `connected` وحدها تعني وصلةً قائمة. `notconnect` كبل مفصول،
        // `disabled` مُطفأ إداريّاً، `err-disabled` أوقفه الجهاز.
        up: status == 'connected',
        adminUp: status != 'disabled',
        status: status,
        description: desc.isEmpty ? null : desc,
        vlan: rest.length > 1 ? rest[1] : null,
        fullDuplex: rest.length > 2 ? _duplex(rest[2]) : null,
        speedMbps: rest.length > 3 ? _speed(rest[3]) : null,
        media: rest.length > 4 ? rest.sublist(4).join(' ') : null,
      ));
    }
    return out;
  }

  /// `a-full`/`full` → true، `a-half`/`half` → false، `auto` → null
  /// (لم يُتَّفق عليه بعد — وهو غير «نصف»).
  static bool? _duplex(String v) {
    final d = v.replaceFirst('a-', '').toLowerCase();
    if (d == 'full') return true;
    if (d == 'half') return false;
    return null;
  }

  /// `a-1000` → 1000، `a-100` → 100، `auto` → null.
  ///
  /// واللاحقة تُقرأ: منافذ العشرة جيجا تكتب `10G` في هذا العمود، ونزعُ
  /// غير الأرقام منها يعطي «١٠» — أي عُشر واحد بالمئة من سرعتها.
  static int? _speed(String v) {
    final m = RegExp(r'^(\d+)([gm]?)$')
        .firstMatch(v.replaceFirst('a-', '').trim().toLowerCase());
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    if (n == null) return null;
    return m.group(2) == 'g' ? n * 1000 : n;
  }

  // ── show interfaces (العدّادات) ──

  static final _reIfHead = RegExp(
      r'^(\S+) is ([A-Za-z ]+?), line protocol is (\w+)',
      multiLine: false);
  static final _reDescription = RegExp(r'^\s*Description:\s*(.+)$');
  static final _reBw = RegExp(r'BW\s+(\d+)\s+Kbit');
  static final _reRate =
      RegExp(r'(\d+)\s+minute\s+(input|output)\s+rate\s+(\d+)\s+bits/sec');
  static final _rePktsIn = RegExp(r'(\d+)\s+packets input,\s+(\d+)\s+bytes');
  static final _rePktsOut = RegExp(r'(\d+)\s+packets output,\s+(\d+)\s+bytes');
  static final _reInErr = RegExp(r'(\d+)\s+input errors');
  static final _reOutErr = RegExp(r'(\d+)\s+output errors');
  static final _reDuplexLine =
      RegExp(r'\b(Full|Half)-duplex\b', caseSensitive: false);
  static final _reSpeedLine =
      RegExp(r'\b(\d+)\s*([MG])b/s\b', caseSensitive: false);

  static List<CiscoInterface> interfacesDetail(String raw) {
    final t = clean(raw, command: CiscoApi._cmdIfDetail);
    final out = <CiscoInterface>[];

    String? name;
    var buf = <String>[];
    void flush() {
      if (name != null) out.add(_detailBlock(name, buf));
      buf = [];
    }

    for (final line in t.split('\n')) {
      final head = _reIfHead.firstMatch(line);
      // عنوان كتلةٍ جديدة يبدأ في العمود صفر — وأسطر التفاصيل مُزاحة،
      // فلا تلتبس كتلةٌ بسطرٍ داخليّ.
      if (head != null && !line.startsWith(' ')) {
        flush();
        name = head.group(1);
      }
      buf.add(line);
    }
    flush();
    return out;
  }

  static CiscoInterface _detailBlock(String name, List<String> lines) {
    final body = lines.join('\n');
    final head = _reIfHead.firstMatch(lines.isEmpty ? '' : lines.first);
    final adminState = head?.group(2) ?? '';
    final proto = head?.group(3) ?? '';

    int? rxBytes, txBytes, inErrors, outErrors, rxBps, txBps, speedMbps;
    String? description;
    bool? fullDuplex;

    for (final line in lines) {
      final d = _reDescription.firstMatch(line);
      if (d != null) description = d.group(1)!.trim();

      final pin = _rePktsIn.firstMatch(line);
      if (pin != null) rxBytes = int.tryParse(pin.group(2)!);
      final pout = _rePktsOut.firstMatch(line);
      if (pout != null) txBytes = int.tryParse(pout.group(2)!);

      // «0 input errors, 0 CRC» — لا تلتقطها من سطر الإخراج.
      if (line.contains('input errors')) {
        inErrors = int.tryParse(_reInErr.firstMatch(line)?.group(1) ?? '');
      }
      if (line.contains('output errors')) {
        outErrors = int.tryParse(_reOutErr.firstMatch(line)?.group(1) ?? '');
      }

      final r = _reRate.firstMatch(line);
      if (r != null) {
        final bps = int.tryParse(r.group(3)!);
        if (r.group(2) == 'input') {
          rxBps = bps;
        } else {
          txBps = bps;
        }
      }

      final dx = _reDuplexLine.firstMatch(line);
      if (dx != null) fullDuplex = dx.group(1)!.toLowerCase() == 'full';
      final sp = _reSpeedLine.firstMatch(line);
      if (sp != null) {
        final n = int.tryParse(sp.group(1)!) ?? 0;
        speedMbps = sp.group(2)!.toUpperCase() == 'G' ? n * 1000 : n;
      }
    }

    // BW هو عرض النطاق المُعلَن، احتياطيّ لسرعة الوصلة عند غيابها.
    if (speedMbps == null) {
      final bw = int.tryParse(_reBw.firstMatch(body)?.group(1) ?? '');
      if (bw != null && bw > 0) speedMbps = bw ~/ 1000;
    }

    return CiscoInterface(
      name: name,
      shortName: shortIfName(name),
      up: proto == 'up',
      adminUp: !adminState.contains('administratively down'),
      description: description,
      speedMbps: speedMbps,
      fullDuplex: fullDuplex,
      rxBytes: rxBytes,
      txBytes: txBytes,
      inErrors: inErrors,
      outErrors: outErrors,
      rxBps: rxBps,
      txBps: txBps,
    );
  }

  /// يدمج `status` (الـVLAN والوسط والسرعة المتَّفق عليها) مع `detail`
  /// (العدّادات). المفتاح هو الاسم المبسوط، لأنّ الأوّل يختصر
  /// (`Fa0/1`) والثاني يُطوّل (`FastEthernet0/1`).
  static List<CiscoInterface> merge(
      List<CiscoInterface> status, List<CiscoInterface> detail) {
    if (status.isEmpty) return detail;
    final byName = {for (final d in detail) d.name: d};
    final merged = <CiscoInterface>[];
    for (final s in status) {
      merged.add(s.mergedWith(byName.remove(s.name)));
    }
    // منافذ لا تظهر في `status` (Vlan‏/Port-channel) — نُلحقها بعدها.
    merged.addAll(byName.values);
    return merged;
  }

  // ── CPU + الذاكرة ──

  static final _reCpu = RegExp(
      r'CPU utilization for five seconds:\s*(\d+)%', caseSensitive: false);

  static double? cpuPercent(String raw) {
    if (isUnsupportedCommand(raw)) return null;
    final m = _reCpu.firstMatch(stripPaging(raw));
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  /// ```
  ///                 Head    Total(b)     Used(b)     Free(b) ...
  /// Processor    14DEA70    41031056     6365984    34665072 ...
  /// ```
  /// نأخذ صفّ `Processor` وحده — صفّ `I/O` ذاكرةُ مخازن لا ذاكرةُ نظام.
  static final _reMemProcessor = RegExp(
      r'^\s*Processor\s+\S+\s+(\d+)\s+(\d+)\s+(\d+)',
      multiLine: true);

  static CiscoMemory? memory(String raw) {
    if (isUnsupportedCommand(raw)) return null;
    final m = _reMemProcessor.firstMatch(stripPaging(raw));
    if (m == null) return null;
    final total = int.tryParse(m.group(1)!);
    final used = int.tryParse(m.group(2)!);
    final free = int.tryParse(m.group(3)!);
    if (total == null || used == null || total <= 0) return null;
    return CiscoMemory(
        totalBytes: total, usedBytes: used, freeBytes: free ?? total - used);
  }

  // ── أسماء المنافذ ──

  static const _prefixes = <String, String>{
    'Fa': 'FastEthernet',
    'Gi': 'GigabitEthernet',
    'Te': 'TenGigabitEthernet',
    'Tw': 'TwoGigabitEthernet',
    'Eth': 'Ethernet',
    'Po': 'Port-channel',
    'Vl': 'Vlan',
    'Se': 'Serial',
    'Lo': 'Loopback',
  };

  /// `Fa0/1` → `FastEthernet0/1`. الاسم المبسوط هو مفتاح الدمج.
  static String expandIfName(String short) {
    final m = RegExp(r'^([A-Za-z-]+)(.*)$').firstMatch(short.trim());
    if (m == null) return short.trim();
    final prefix = m.group(1)!;
    final rest = m.group(2)!;
    // اسمٌ مطوّلٌ أصلاً.
    for (final full in _prefixes.values) {
      if (prefix.toLowerCase() == full.toLowerCase()) return short.trim();
    }
    for (final e in _prefixes.entries) {
      if (prefix.toLowerCase() == e.key.toLowerCase()) return '${e.value}$rest';
    }
    return short.trim();
  }

  /// `FastEthernet0/1` → `Fa0/1` — للعرض في صفٍّ ضيّق.
  static String shortIfName(String full) {
    for (final e in _prefixes.entries) {
      if (full.toLowerCase().startsWith(e.value.toLowerCase())) {
        return '${e.key}${full.substring(e.value.length)}';
      }
    }
    return full;
  }
}

// ═══════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════

/// ما يُستخلَص من `show version` وحده.
class CiscoVersionInfo {
  final String? model;
  final String? iosVersion;
  final String? hostname;
  final String? serial;
  final Duration? uptime;

  /// من «with 61440K/4088K bytes of memory» — الذاكرة الرئيسة وذاكرة
  /// الإدخال/الإخراج كما يعلنهما الإقلاع. ليست استهلاكاً لحظيّاً؛
  /// الاستهلاك في [CiscoMemory].
  final int? mainMemKb;
  final int? ioMemKb;

  const CiscoVersionInfo({
    this.model,
    this.iosVersion,
    this.hostname,
    this.serial,
    this.uptime,
    this.mainMemKb,
    this.ioMemKb,
  });
}

class CiscoMemory {
  final int totalBytes;
  final int usedBytes;
  final int freeBytes;
  const CiscoMemory(
      {required this.totalBytes,
      required this.usedBytes,
      required this.freeBytes});

  double get usedPercent => totalBytes <= 0 ? 0 : (usedBytes / totalBytes) * 100;
}

/// منفذ.
///
/// كلّ عدّاد `int?` **لا `0`**: الصفر يعني «صفرٌ فعلاً»، و`null` يعني
/// «الجهاز لم يُعطِها». خلطهما يجعل منفذاً بلا عدّادات يبدو سليماً.
class CiscoInterface {
  final String name;
  final String? shortName;
  final bool up;
  final bool adminUp;

  /// كما قالها الجهاز: `connected` / `notconnect` / `disabled` /
  /// `err-disabled` — أدقّ من ثنائيّة up/down.
  final String? status;
  final String? description;
  final String? vlan;
  final String? media;
  final int? speedMbps;
  final bool? fullDuplex;
  final int? rxBytes, txBytes;
  final int? inErrors, outErrors;

  /// معدّل الخمس دقائق كما يحسبه الجهاز — يغنينا عن حساب الفروق
  /// بين جولتين، ويصحّ من أوّل لقطة.
  final int? rxBps, txBps;

  const CiscoInterface({
    required this.name,
    this.shortName,
    this.up = false,
    this.adminUp = true,
    this.status,
    this.description,
    this.vlan,
    this.media,
    this.speedMbps,
    this.fullDuplex,
    this.rxBytes,
    this.txBytes,
    this.inErrors,
    this.outErrors,
    this.rxBps,
    this.txBps,
  });

  /// واجهةٌ منطقيّة لا يقابلها قابسٌ في اللوحة.
  static const _logical = [
    'vlan', 'port-channel', 'loopback', 'tunnel', 'null', 'bdi'
  ];

  bool get isPhysical {
    final n = name.toLowerCase();
    return !_logical.any(n.startsWith);
  }

  /// يضمّ العدّادات القادمة من `show interfaces` إلى صفٍّ من
  /// `show interfaces status`، مع تفضيل ما جاء من الأوّل عند التعارض
  /// في الحقول التي يعرفها وحده.
  CiscoInterface mergedWith(CiscoInterface? d) {
    if (d == null) return this;
    return CiscoInterface(
      name: name,
      shortName: shortName ?? d.shortName,
      up: up,
      adminUp: adminUp && d.adminUp,
      status: status,
      description: description ?? d.description,
      vlan: vlan,
      media: media,
      speedMbps: speedMbps ?? d.speedMbps,
      fullDuplex: fullDuplex ?? d.fullDuplex,
      rxBytes: d.rxBytes,
      txBytes: d.txBytes,
      inErrors: d.inErrors,
      outErrors: d.outErrors,
      rxBps: d.rxBps,
      txBps: d.txBps,
    );
  }
}

class CiscoStats {
  final String? model;
  final String? iosVersion;
  final String? hostname;
  final String? serial;
  final Duration? uptime;
  final int? mainMemKb;
  final int? ioMemKb;
  final double? cpuPercent;
  final CiscoMemory? memory;
  final List<CiscoInterface> ifaces;

  const CiscoStats({
    this.model,
    this.iosVersion,
    this.hostname,
    this.serial,
    this.uptime,
    this.mainMemKb,
    this.ioMemKb,
    this.cpuPercent,
    this.memory,
    this.ifaces = const [],
  });

  double? get memPercent => memory?.usedPercent;

  /// منافذ اللوحة وحدها — عدّ `Vlan90` أو `Port-channel1` ضمن
  /// «المنافذ العاملة» يعطي رقماً لا يقابل ما يراه الواقف أمام الجهاز.
  int get portsUp => physicalPorts.where((i) => i.up).length;

  int get portsTotal => physicalPorts.length;

  List<CiscoInterface> get physicalPorts =>
      ifaces.where((i) => i.isPhysical).toList();

  CiscoStats copyWith({
    double? cpuPercent,
    CiscoMemory? memory,
    List<CiscoInterface>? ifaces,
  }) =>
      CiscoStats(
        model: model,
        iosVersion: iosVersion,
        hostname: hostname,
        serial: serial,
        uptime: uptime,
        mainMemKb: mainMemKb,
        ioMemKb: ioMemKb,
        cpuPercent: cpuPercent ?? this.cpuPercent,
        memory: memory ?? this.memory,
        ifaces: ifaces ?? this.ifaces,
      );
}

/// انقطاع الجلسة — علامةٌ داخليّة. في الأوامر العاديّة عطل، وفي
/// `reload` **هو الدليل على النجاح**.
class _SessionClosed implements Exception {
  const _SessionClosed();
}

class CiscoException implements Exception {
  final String message;
  CiscoException(this.message);
  @override
  String toString() => 'CiscoException: $message';
}

// ═══════════════════════════════════════════════════════════
// Transport — SSH shell أو Telnet خام، بواجهةٍ واحدة
// ═══════════════════════════════════════════════════════════

abstract class _Transport {
  void write(List<int> data);
  Future<void> close();

  /// نهاية السطر التي يفهمها هذا النقل — وهي **ليست واحدة**:
  /// في طرفيّة SSH يُقرأ CR وLF **مُنهيَين اثنين**، فيُنفَّذ الأمر ثمّ
  /// يُنفَّذ سطرٌ فارغ بعده فيُطبَع محثٌّ زائد يسبق مخرجات الأمر
  /// التالي ويُنهيه قبل أن يبدأ. Telnet يبتلع CRLF كمُنهٍ واحد.
  String get eol;
}

/// SSH عبر قناة shell تفاعليّة (لا exec — انظر توثيق [CiscoApi]).
class _SshTransport implements _Transport {
  final SSHClient _client;
  final SSHSocket _socket;
  final SSHSession _session;

  _SshTransport(this._client, this._socket, this._session);

  static Future<_SshTransport> connect({
    required String host,
    required int port,
    required String user,
    required String pass,
    required Duration timeout,
    required void Function(List<int>) onData,
    required void Function() onClosed,
  }) async {
    SSHSocket? socket;
    SSHClient? client;
    try {
      socket = await SSHSocket.connect(host, port, timeout: timeout);
      client = SSHClient(
        socket,
        username: user,
        onPasswordRequest: () => pass,
      );
      // عرضٌ واسع كي لا يلتفّ جدول `show interfaces status` فتضيع
      // الأعمدة. الارتفاع يبقى قياسيّاً — الترقيم نعالجه بأنفسنا.
      final session = await client
          .shell(pty: const SSHPtyConfig(type: 'vt100', width: 200, height: 24))
          .timeout(timeout);
      // موت القناة إشارةٌ لا عطل: `reload` ينجح بقطع الجلسة لا بردٍّ يصل.
      session.stdout.listen(onData, onError: (_) {}, onDone: onClosed);
      session.stderr.listen(onData, onError: (_) {});
      unawaited(session.done.then((_) => onClosed()).catchError((_) {}));
      return _SshTransport(client, socket, session);
    } catch (e) {
      try {
        client?.close();
        socket?.close();
      } catch (_) {}
      throw CiscoException(_sshError(e, host, port));
    }
  }

  static String _sshError(Object e, String host, int port) {
    final s = e.toString();
    if (s.contains('refused') || s.contains('SocketException')) {
      return 'تعذّر فتح SSH على $host:$port.\n'
          'إن كان الجهاز يقبل Telnet فقط، بدّل البروتوكول إلى Telnet '
          'من إعدادات الجهاز — لا نبدّله تلقائيّاً.';
    }
    if (s.contains('auth') || s.contains('Auth')) {
      return 'رُفض اسم المستخدم أو كلمة السرّ على $host.';
    }
    if (s.contains('algorithm') || s.contains('kex')) {
      return 'تعذّر الاتّفاق على خوارزميّات SSH مع $host.';
    }
    return 'فشل اتّصال SSH بـ$host:$port — $s';
  }

  @override
  String get eol => '\r';

  @override
  void write(List<int> data) =>
      _session.stdin.add(Uint8List.fromList(data));

  @override
  Future<void> close() async {
    try {
      _session.close();
    } catch (_) {}
    try {
      _client.close();
    } catch (_) {}
    try {
      _socket.close();
    } catch (_) {}
  }
}

/// Telnet خام — تفاوض IAC بأيدينا، فلا حاجة لحزمةٍ جديدة في pubspec.
class _TelnetTransport implements _Transport {
  static const _iac = 255, _dont = 254, _doo = 253, _wont = 252, _will = 251;
  static const _sb = 250, _se = 240;
  static const _optEcho = 1, _optSga = 3;

  final Socket _socket;
  final void Function(List<int>) _onData;

  // حالة مُفكِّك IAC — الأوامر قد تنقسم بين مقطعَي TCP.
  int _state = 0;
  int _verb = 0;

  _TelnetTransport(this._socket, this._onData);

  static Future<_TelnetTransport> connect({
    required String host,
    required int port,
    required Duration timeout,
    required void Function(List<int>) onData,
    required void Function() onClosed,
  }) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      final t = _TelnetTransport(socket, onData);
      socket.listen(t._feed,
          onError: (_) => onClosed(), onDone: onClosed, cancelOnError: false);
      return t;
    } catch (e) {
      throw CiscoException('تعذّر فتح Telnet على $host:$port — '
          '${e is SocketException ? e.osError?.message ?? 'لا استجابة' : e}');
    }
  }

  /// يفصل أوامر IAC عن البيانات ويردّ عليها، فلا تتسرّب بايتات
  /// التفاوض إلى المحلّلات.
  void _feed(List<int> chunk) {
    final data = <int>[];
    for (final b in chunk) {
      switch (_state) {
        case 0:
          if (b == _iac) {
            _state = 1;
          } else {
            data.add(b);
          }
          break;
        case 1: // بعد IAC
          if (b == _iac) {
            data.add(_iac); // ٢٥٥ مُهرَّب = بايت بيانات
            _state = 0;
          } else if (b == _sb) {
            _state = 3;
          } else if (b == _will || b == _wont || b == _doo || b == _dont) {
            _verb = b;
            _state = 2;
          } else {
            _state = 0; // أمرٌ بلا معامل (NOP/AYT…)
          }
          break;
        case 2: // بعد الفعل — هذا رقم الخيار
          _respond(_verb, b);
          _state = 0;
          break;
        case 3: // داخل subnegotiation — نتخطّاها حتّى IAC SE
          if (b == _iac) _state = 4;
          break;
        case 4:
          _state = (b == _se) ? 0 : 3;
          break;
      }
    }
    if (data.isNotEmpty) _onData(data);
  }

  /// نقبل ECHO وSGA (بهما تعمل جلسة IOS سطراً بسطر)، ونرفض ما عداهما.
  /// الرفض أأمن من القبول: كلّ خيارٍ نقبله يصير علينا أن نُحسن تنفيذه.
  void _respond(int verb, int option) {
    int reply;
    if (verb == _will) {
      reply = (option == _optEcho || option == _optSga) ? _doo : _dont;
    } else if (verb == _doo) {
      reply = (option == _optSga) ? _will : _wont;
    } else if (verb == _dont) {
      reply = _wont;
    } else {
      reply = _dont;
    }
    try {
      _socket.add([_iac, reply, option]);
    } catch (_) {}
  }

  @override
  String get eol => '\r\n';

  @override
  void write(List<int> data) => _socket.add(data);

  @override
  Future<void> close() async {
    try {
      await _socket.flush().timeout(const Duration(seconds: 1));
    } catch (_) {}
    try {
      await _socket.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      _socket.destroy();
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════
// Session — محرّك الأوامر فوق أيّ نقل
// ═══════════════════════════════════════════════════════════

class _Hit {
  final int index;
  final String text;
  const _Hit(this.index, this.text);
}

class _CiscoCli {
  final String host;

  /// قابل لـnull عمداً: إن فشل فتح النقل نفسه بقي غير مُسنَد، وإغلاقٌ
  /// أعمى عليه يرمي LateInitializationError فيحجب الخطأ الأصليّ.
  _Transport? _t;
  _Transport get _io => _t!;

  String _acc = '';
  Completer<void>? _wake;

  String hostname = '';
  RegExp _promptRe = RegExp(r'[^\s]*[#>]\s*$');

  /// محثٌّ ينتهي بـ`#` = مستوى امتياز (١٥ عادةً)؛ و`>` = user exec
  /// الذي لا يملك `reload` أصلاً.
  bool privileged = false;

  final Completer<void> _closedSignal = Completer<void>();

  _CiscoCli._(this.host);

  // مُدخَلات تفاعليّة يعرفها IOS.
  static final _reUser = RegExp(r'(?:[Uu]sername|[Ll]ogin)\s*:\s*$');
  static final _rePass = RegExp(r'[Pp]assword\s*:\s*$');
  // المحثّ يبدأ سطراً — بلا هذا القيد يطابق أيّ سطرٍ ينتهي بـ`#`.
  static final _rePrompt = RegExp(r'(?:^|\n)[ \t]*[^\s\r\n]*[#>][ \t]*$');
  static final _reAuthFail = RegExp(
      r'%\s*(Login invalid|Bad (passwords|secrets)|Authentication failed|Access denied)',
      caseSensitive: false);
  static final _reMore = RegExp(r'--More--');

  static Future<_CiscoCli> connect({
    required String host,
    required String user,
    required String pass,
    int? port,
    String protocol = 'ssh',
    required Duration timeout,
  }) async {
    // بلا downgrade تلقائيّ: ما يطلبه المستخدم هو ما نستعمله، وإن فشل
    // قلنا له لماذا بدل أن نبدّل النقل من تحته.
    final telnet = protocol.trim().toLowerCase() == 'telnet';
    final p = port ?? (telnet ? 23 : 22);
    final cli = _CiscoCli._(host);
    try {
      if (telnet) {
        cli._t = await _TelnetTransport.connect(
            host: host,
            port: p,
            timeout: timeout,
            onData: cli._onData,
            onClosed: cli._onClosed);
        await cli._loginTelnet(user, pass, timeout);
      } else {
        // SSH يتكفّل بالمصادقة قبل فتح القناة؛ يبقى انتظار الـprompt.
        cli._t = await _SshTransport.connect(
            host: host,
            port: p,
            user: user,
            pass: pass,
            timeout: timeout,
            onData: cli._onData,
            onClosed: cli._onClosed);
        final hit =
            await cli._expect([_rePrompt], timeout, what: 'محثّ الدخول');
        cli._adoptPrompt(hit.text);
      }
      await cli._disablePaging(timeout);
      return cli;
    } catch (_) {
      // الفشل بعد فتح المقبس يترك جلسةً معلّقة على الجهاز (وvty
      // محدودة العدد) — والمستدعي لم يستلم `cli` بعدُ ليغلقها.
      await cli.close();
      rethrow;
    }
  }

  void _onClosed() {
    if (!_closedSignal.isCompleted) _closedSignal.complete();
    final w = _wake;
    _wake = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  void _onData(List<int> d) {
    // latin1 لا يرمي على بايتٍ شاذّ — ومخرجات IOS ASCII، عدا بايتات
    // المسح (\x08) وهي ذات معنى فلا نُسقطها.
    _acc += latin1.decode(d, allowInvalid: true);
    final w = _wake;
    _wake = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<_Hit> _expect(List<RegExp> pats, Duration timeout,
      {String? what}) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      for (var i = 0; i < pats.length; i++) {
        final m = pats[i].firstMatch(_acc);
        if (m != null) {
          final text = _acc.substring(0, m.end);
          _acc = _acc.substring(m.end);
          return _Hit(i, text);
        }
      }
      // الانقطاع بعد استنفاد الأنماط: لا جدوى من انتظار المهلة كاملةً.
      if (_closedSignal.isCompleted) throw const _SessionClosed();
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        throw CiscoException(
            'انتهت مهلة انتظار ${what ?? 'ردّ الجهاز'} من $host.');
      }
      _wake = Completer<void>();
      try {
        await _wake!.future.timeout(left);
      } on TimeoutException {
        // نعود للحلقة — فحصُ المهلة في أعلاها هو الحَكَم.
      }
    }
  }

  Future<void> _loginTelnet(String user, String pass, Duration timeout) async {
    // ثلاثة مداخل ممكنة: حسابٌ محلّيّ (Username ثمّ Password)، أو كلمة
    // سطرٍ وحدها (Password مباشرةً)، أو محثٌّ جاهز بلا مصادقة.
    //
    // ⚠️ الفهارس هنا تخصّ كلّ قائمةٍ على حدة — لا تُقارَن عبر نداءين.
    final hit = await _expect([_reUser, _rePass, _rePrompt], timeout,
        what: 'محثّ الدخول');

    if (hit.index == 0) {
      _io.write(latin1.encode('$user${_io.eol}'));
      final after = await _expect([_rePass, _rePrompt, _reAuthFail], timeout,
          what: 'طلب كلمة السرّ');
      if (after.index == 1) return _adoptPrompt(after.text); // بلا كلمة سرّ
      if (after.index == 2) throw _rejected();
      return _sendPassword(pass, timeout);
    }

    if (hit.index == 1) return _sendPassword(pass, timeout);

    _adoptPrompt(hit.text);
  }

  Future<void> _sendPassword(String pass, Duration timeout) async {
    _io.write(latin1.encode('$pass${_io.eol}'));
    // إعادة طلب كلمة السرّ = رفضٌ صامت، وهو ردّ IOS المعتاد.
    final hit = await _expect([_rePrompt, _reAuthFail, _rePass], timeout,
        what: 'نتيجة الدخول');
    if (hit.index != 0) throw _rejected();
    _adoptPrompt(hit.text);
  }

  CiscoException _rejected() => CiscoException(
      'رُفض الدخول إلى $host — تحقّق من اسم المستخدم وكلمة السرّ.');

  /// يلتقط المحثّ الفعليّ («cisco-alsudany#») ليصير علامة نهاية كلّ
  /// أمر. المطابقة العامّة `[#>]$` وحدها تُخطئ مع أيّ سطرٍ ينتهي بها.
  void _adoptPrompt(String matched) {
    final lines = matched
        .replaceAll('\r', '')
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty) return;
    final prompt = lines.last.trim();
    if (prompt.isEmpty || !RegExp(r'[#>]$').hasMatch(prompt)) return;
    hostname = prompt.substring(0, prompt.length - 1).trim();
    privileged = prompt.endsWith('#');
    _promptRe = RegExp('(?:^|\\n)[ \\t]*${RegExp.escape(prompt)}[ \\t]*\$');
  }

  /// `terminal length 0` إعدادُ جلسةٍ لا إعدادُ جهاز — لا يُكتَب في
  /// startup-config. وإن رفضه الجهاز فلا ضرر: معالجة `--More--` في
  /// [run] تعمل في الحالتين.
  Future<void> _disablePaging(Duration timeout) async {
    try {
      await run('terminal length 0', timeout: timeout);
    } catch (_) {}
  }

  Future<String> run(String cmd, {required Duration timeout}) async {
    await _settle();
    final out = StringBuffer();
    _io.write(latin1.encode('$cmd${_io.eol}'));

    final deadline = DateTime.now().add(timeout);

    // انتظر **صدى الأمر** قبل البحث عن المحثّ. أيّ محثٍّ عالقٍ من أمرٍ
    // سابق يقع قبل الصدى فيُستهلَك معه، فلا يُنهي هذا الأمر قبل أن
    // تبدأ مخرجاته — وهو ما كان يُرجع لقطةً فارغةً بالكامل عبر SSH.
    try {
      var window = deadline.difference(DateTime.now());
      if (window > const Duration(seconds: 3)) {
        window = const Duration(seconds: 3);
      }
      if (window > Duration.zero) {
        await _expect([RegExp(RegExp.escape(cmd))], window,
            what: 'صدى «$cmd»');
      }
    } on CiscoException {
      // صدى مُطفأ على هذا الجهاز — نُكمل على المحثّ وحده.
    }

    while (true) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        throw CiscoException('انتهت مهلة تنفيذ «$cmd» على $host.');
      }
      final _Hit hit;
      try {
        hit = await _expect([_promptRe, _reMore], left, what: 'مخرجات «$cmd»');
      } on _SessionClosed {
        throw CiscoException('انقطع الاتّصال بـ$host أثناء تنفيذ «$cmd».');
      }
      out.write(hit.text);
      if (hit.index == 0) break;
      // مسافة = الصفحة التالية. (ENTER يعطي سطراً واحداً — أبطأ بكثير.)
      _io.write([0x20]);
    }
    return out.toString();
  }

  /// يُفرغ ما تبقّى من الأمر السابق قبل إرسال التالي؛ المهلة القصيرة
  /// تلتقط ما كان «في الطريق» لحظة التفريغ الأوّل.
  Future<void> _settle() async {
    _acc = '';
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _acc = '';
  }

  // أسئلة `reload` التفاعليّة.
  static final _reSaveQuestion =
      RegExp(r'\[yes/no\]', caseSensitive: false);
  static final _reConfirm = RegExp(r'\[confirm\]', caseSensitive: false);
  // يلتقط **السطر كاملاً** لا الكلمة المفتاحيّة وحدها: رسالةٌ مبتورة
  // عند «% Reload» تُخفي سبب الرفض وهو بيت القصيد.
  static final _reRefused = RegExp(
      r'%[ \t]*(?:Reload|Invalid|Incomplete|Unknown|Ambiguous|Not|Permission)'
      r'[^\r\n]*',
      caseSensitive: false);

  /// يُرسل `reload` ويُجيب أسئلته حتّى تموت الجلسة.
  ///
  /// **لا نحفظ الإعدادات أبداً.** سؤال «Save? [yes/no]» يعني أنّ
  /// `running-config` تخالف `startup-config`، والإجابة بـ`yes` تُثبّت
  /// تغييراً لم يطلبه أحد — وقد يكون تغييراً عابراً وضعه فنّيٌّ عمداً
  /// ليزول بإعادة التشغيل. جوابنا `n` دائماً.
  Future<void> reload({required Duration timeout}) async {
    if (!privileged) {
      throw CiscoException(
          'الحساب على $host بمستوى user exec (المحثّ «>»), و`reload` '
          'تحتاج مستوى امتياز. استعمل حساباً بمستوى ١٥.');
    }

    _acc = '';
    _io.write(latin1.encode('reload${_io.eol}'));
    final deadline = DateTime.now().add(timeout);

    // سقفٌ للدورات: جهازٌ يعيد السؤال بلا نهاية لا يُعلّقنا.
    for (var i = 0; i < 8; i++) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) break;
      try {
        final hit = await _expect(
            [_reSaveQuestion, _reConfirm, _reRefused, _promptRe], left,
            what: 'ردّ reload');
        switch (hit.index) {
          case 0:
            _io.write(latin1.encode('n${_io.eol}'));
          case 1:
            _io.write(latin1.encode(_io.eol));
          case 2:
            throw CiscoException('رفض $host الأمر: '
                '${_reRefused.firstMatch(hit.text)?.group(0)?.trim() ?? hit.text.trim()}');
          case 3:
            // عاد المحثّ سالماً — الجهاز لم يُعِد التشغيل.
            throw CiscoException(
                'لم يُنفَّذ reload على $host — عاد المحثّ دون إعادة تشغيل.');
        }
      } on _SessionClosed {
        return; // ← ماتت الجلسة: الجهاز يُعيد التشغيل الآن
      }
    }
    throw CiscoException(
        'أُرسل reload إلى $host لكن لم تنقطع الجلسة — لم يتأكّد التنفيذ.');
  }

  Future<void> close() async {
    final t = _t;
    if (t == null) return;
    _t = null; // إغلاقٌ مرّتين لا يرمي
    try {
      t.write(latin1.encode('exit${t.eol}'));
    } catch (_) {}
    await t.close();
  }
}
