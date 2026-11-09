import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../print_output.dart';
import 'escpos.dart';
import 'printer_bridge.dart';
import 'receipt_printer_prefs.dart';
import 'thermal_render.dart';

/// مرحلة الوصل الجاري — سطر الحالة في «طابعة الوصولات» وإشعار «جاري الطباعة».
enum ReceiptJobPhase { preparing, connecting, checking, sending, confirming }

@immutable
class ReceiptJobStatus {
  const ReceiptJobStatus(this.phase, {required this.printer, this.progress = 0, this.quiet = false});

  final ReceiptJobPhase phase;
  final String printer;

  /// ٠..١ أثناء الإرسال.
  final double progress;

  /// الطباعة التجريبيّة من الإعدادات: حالتها في الورقة نفسها، بلا إشعارٍ فوقها.
  final bool quiet;
}

/// ما تجده الإعدادات حين تبحث عن الطابعات.
@immutable
class PrinterDiscovery {
  const PrinterDiscovery(this.devices, {this.issue});

  final List<BtDevice> devices;

  /// لماذا لا تظهر الطابعات (البلوتوث مطفأ، الإذن…) — null = القائمة كما هي.
  final PrintIssue? issue;
}

/// «طابعة الوصولات» بالهاتف (٩ نوفمبر — المالك: «هذا كودكس فحصنه اجهزه طباعه… اندرويد وايفون ماتطبع»):
/// طابعة كاشير حراريّة عبر البلوتوث (ESC/POS)، أو طابعة الجهاز المدمجة (SUNMI). اختياريّة من الإعدادات؛ نافذة الطباعة
/// و«صورة» والحاسبة كما كانت.
///
/// • الوصل نفسه (PDF «قوالب الطباعة») صورةً بعرض رأس الطابعة ([ThermalRender]) — العربيّ متّصلٌ كما يُرى.
/// • وصلٌ واحدٌ في كلّ مرّة؛ النقر المكرّر على الوصل نفسه لا يطبعه مرّتين (أثناءه وبعده بلحظات).
/// • الاتّصال والإرسال في الطبقة الأصليّة خارج خيط الواجهة، والصورة في عزلةٍ مستقلّة — الشاشة لا تتجمّد.
/// • «أُرسل» (الطابعة صامتة) غير «تأكّدت الطباعة» (الطابعة أجابت بعد الوصل، أو SUNMI أكّدت)، وانقطاعٌ في
///   منتصف الإرسال «غير مؤكَّد» مع إعادة طباعةٍ يدويّة.
class ReceiptPrinter {
  ReceiptPrinter._();

  static final ReceiptPrinter instance = ReceiptPrinter._();

  @visibleForTesting
  PrinterBridge bridge = const MethodChannelPrinterBridge();

  @visibleForTesting
  BtPermissionGate permission = const PlatformBtPermission();

  @visibleForTesting
  Future<MonoImage> Function(PrintDoc doc, ReceiptPaper paper) render = ThermalRender.receipt;

  /// الانتظار بين الشرائط وقبل الإغلاق — صفرٌ في الاختبارات.
  @visibleForTesting
  Future<void> Function(Duration d) pause = (d) => Future<void>.delayed(d);

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// النقر المكرّر على الوصل نفسه خلال هذه المدّة بعد طباعته لا يطبعه ثانيةً.
  static const dupWindow = Duration(seconds: 4);

  static const connectTimeout = Duration(seconds: 12);

  /// صفوف كلّ شريط: البلوتوث أصغر (ذاكرة الطابعات الرخيصة)، وطابعة الجهاز تستقبل من خدمةٍ في الجهاز نفسه.
  static const int bluetoothBandRows = 64;
  static const int builtinBandRows = 128;

  /// الوصل الجاري — null حين لا شيء.
  final ValueNotifier<ReceiptJobStatus?> status = ValueNotifier<ReceiptJobStatus?>(null);

  final Map<String, Future<PrintResult>> _inflight = {};
  final Map<String, ({DateTime at, bool ok, String? printer})> _recent = {};
  Future<void> _tail = Future<void>.value();

  /// ينسى ما طُبع (منع التكرار) — للاختبار.
  @visibleForTesting
  void forget() {
    _inflight.clear();
    _recent.clear();
    _tail = Future<void>.value();
    status.value = null;
  }

  /// يطبع [doc] على طابعة الوصولات المختارة. [force] = «إعادة الطباعة»: بلا منع التكرار.
  Future<PrintResult> send(PrintDoc doc, {bool force = false, bool quiet = false}) async {
    final t = _Target.current();
    if (t == null) {
      return const PrintResult.failed('receipt printer: not configured', issue: PrintIssue.notConfigured);
    }
    final key = '${t.key}|${doc.name}';
    final now = clock();
    _recent.removeWhere((_, v) => now.difference(v.at) >= dupWindow);
    if (!force) {
      final running = _inflight[key];
      if (running != null) {
        // نقرٌ ثانٍ والوصل نفسه يُطبع: لا نسخة ثانية؛ والنتيجة يعرضها الطلب الأوّل.
        final r = await running;
        return r.ok ? PrintResult.printed(printer: r.printer, ack: PrintAck.duplicate) : const PrintResult.cancelled();
      }
      final last = _recent[key];
      if (last != null && last.ok) return PrintResult.printed(printer: last.printer, ack: PrintAck.duplicate);
    }
    final job = _serial(() => _run(t, doc, quiet: quiet));
    _inflight[key] = job;
    try {
      final r = await job;
      _recent[key] = (at: clock(), ok: r.ok, printer: r.printer);
      return r;
    } finally {
      if (identical(_inflight[key], job)) _inflight.remove(key);
    }
  }

  /// الطابعات للاختيار: أندرويد المقترنة بالهاتف، والآيفون بحثٌ عن BLE ([scanFor]).
  Future<PrinterDiscovery> discover({Duration scanFor = const Duration(seconds: 8)}) async {
    final permit = await permission.ensure();
    if (permit == BtPermit.blocked) return const PrinterDiscovery([], issue: PrintIssue.permissionBlocked);
    if (permit == BtPermit.denied) return const PrinterDiscovery([], issue: PrintIssue.permission);
    try {
      final st = await bridge.btState();
      if (!st.supported) return const PrinterDiscovery([], issue: PrintIssue.btUnsupported);
      if (!st.authorized) return const PrinterDiscovery([], issue: PrintIssue.permission);
      if (!st.enabled) return const PrinterDiscovery([], issue: PrintIssue.btOff);
      final list = ReceiptPrinterPrefs.isIos ? await bridge.btScan(scanFor) : await bridge.btPaired();
      final named = [for (final d in list) if (d.id.isNotEmpty) d];
      // الطابعات أوّلاً ثمّ الأقرب (الآيفون) ثمّ بالاسم.
      named.sort((a, b) {
        if (a.printer != b.printer) return a.printer ? -1 : 1;
        final ra = a.rssi ?? -999, rb = b.rssi ?? -999;
        if (ra != rb) return rb.compareTo(ra);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return PrinterDiscovery(named);
    } on PrinterFailure catch (f) {
      return PrinterDiscovery(const [], issue: issueOf(f.code));
    }
  }

  /// إعدادات التطبيق في الهاتف — حين يُرفض إذن البلوتوث دائماً.
  Future<void> openAppSettings() async {
    try {
      await permission.openSettings();
    } catch (_) {}
  }

  /// إعدادات البلوتوث في الهاتف (الإقران والتشغيل) — الآيفون: إعدادات التطبيق.
  Future<void> openBluetoothSettings() async {
    try {
      await bridge.btSettings();
    } catch (_) {}
  }

  /// طابعة الجهاز المدمجة: موجودةٌ وجاهزة؟ (null على فشل القناة).
  Future<BuiltinInfo?> builtinInfo() async {
    try {
      return await bridge.builtinInfo();
    } on PrinterFailure {
      return null;
    }
  }

  // ─── داخليّ ──────────────────────────────────

  Future<T> _serial<T>(Future<T> Function() task) {
    final run = _tail.then((_) => task());
    _tail = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  void _phase(ReceiptJobPhase p, String printer, bool quiet, [double progress = 0]) =>
      status.value = ReceiptJobStatus(p, printer: printer, progress: progress, quiet: quiet);

  Future<PrintResult> _run(_Target t, PrintDoc doc, {required bool quiet}) async {
    Future<PrintResult> retry() => send(doc, force: true, quiet: quiet);
    final label = t.mode == ReceiptPrinterMode.bluetooth ? t.device!.name : 'SUNMI';
    _phase(ReceiptJobPhase.preparing, label, quiet);
    try {
      final MonoImage img;
      try {
        img = await render(doc, t.paper);
      } catch (e) {
        return PrintResult.failed('render: $e', printer: label, issue: PrintIssue.render, retry: retry);
      }
      return t.mode == ReceiptPrinterMode.builtin
          ? await _builtin(t, img, retry, quiet)
          : await _bluetooth(t, img, retry, quiet);
    } finally {
      status.value = null;
    }
  }

  Future<PrintResult> _bluetooth(
      _Target t, MonoImage img, Future<PrintResult> Function() retry, bool quiet) async {
    final name = t.device!.name;
    PrintResult fail(PrintIssue issue, Object why) =>
        PrintResult.failed('bt: $why', printer: name, issue: issue, retry: retry);

    final permit = await permission.ensure();
    if (permit == BtPermit.blocked) return fail(PrintIssue.permissionBlocked, 'permission blocked');
    if (permit == BtPermit.denied) return fail(PrintIssue.permission, 'permission denied');

    _phase(ReceiptJobPhase.connecting, name, quiet);
    try {
      final st = await bridge.btState();
      if (!st.supported) return fail(PrintIssue.btUnsupported, 'no bluetooth');
      if (!st.authorized) return fail(PrintIssue.permission, 'unauthorized');
      if (!st.enabled) return fail(PrintIssue.btOff, 'bluetooth off');
      await bridge.btConnect(t.device!.id, connectTimeout);
    } on PrinterFailure catch (f) {
      return fail(issueOf(f.code), f);
    }

    var printedSome = false;
    try {
      _phase(ReceiptJobPhase.checking, name, quiet);
      await bridge.btRead(const Duration(milliseconds: 60)); // بقايا اتّصالٍ سابق
      // الورق قبل الإرسال — إن أجابت الطابعة (كثيرٌ منها صامت فيُرسل الوصل كما هو).
      final paper = await _ask(4, const Duration(milliseconds: 700));
      final talks = paper != null;
      if (paper?.paperOut == true) return fail(PrintIssue.paperOut, 'paper end (DLE EOT 4)');
      if (talks) {
        final why = await _ask(2, const Duration(milliseconds: 500));
        if (why?.coverOpen == true) return fail(PrintIssue.coverOpen, 'cover open (DLE EOT 2)');
        if (why?.paperOut == true) return fail(PrintIssue.paperOut, 'paper end (DLE EOT 2)');
      }

      final chunks = EscPos.job(img, bandRows: bluetoothBandRows, cut: t.paper == ReceiptPaper.mm80);
      for (var i = 0; i < chunks.length; i++) {
        _phase(ReceiptJobPhase.sending, name, quiet, i / chunks.length);
        await bridge.btWrite(chunks[i]);
        // بعد «ESC @» كلّ قطعةٍ قد تُطبع — الانقطاع بعدها «غير مؤكَّد».
        if (i > 0) printedSome = true;
        // لا نسبق الطابعة كثيراً: بعضها بلا تحكّمٍ بالتدفّق يفيض ويخرج الوصل مشوّهاً.
        if (i > 0 && i < chunks.length - 1) await pause(bandPause(bluetoothBandRows));
      }

      if (talks) {
        _phase(ReceiptJobPhase.confirming, name, quiet, 1);
        // «GS r 1» يُجاب بالدور: ردّه = الطابعة أنهت ما قبله.
        await bridge.btWrite(EscPos.paperStatusInSequence());
        final s = EscPos.parsePaperStatus(await bridge.btRead(confirmTimeout(img.height)));
        if (s == null) return PrintResult.printed(printer: name, ack: PrintAck.sent);
        if (s.paperOut) return fail(PrintIssue.paperOutMidway, 'paper end after the receipt (GS r 1)');
        return PrintResult.printed(printer: name, ack: PrintAck.confirmed);
      }
      // طابعةٌ صامتة: مهلةٌ قصيرة حتى يخرج آخر ما في ذاكرة البلوتوث قبل الإغلاق.
      await pause(const Duration(milliseconds: 1500));
      return PrintResult.printed(printer: name, ack: PrintAck.sent);
    } on PrinterFailure catch (f) {
      if (printedSome) return fail(PrintIssue.disconnectedMidway, f);
      return fail(f.code == 'io' ? PrintIssue.disconnected : issueOf(f.code), f);
    } finally {
      try {
        await bridge.btClose();
      } catch (_) {}
    }
  }

  /// سؤال حالةٍ فوريّ «DLE EOT [n]» — null إن لم تُجب الطابعة.
  Future<PrinterSignal?> _ask(int n, Duration wait) async {
    await bridge.btWrite(EscPos.realtimeStatus(n));
    return EscPos.parseRealtime(n, await bridge.btRead(wait));
  }

  Future<PrintResult> _builtin(_Target t, MonoImage img, Future<PrintResult> Function() retry, bool quiet) async {
    var name = 'SUNMI';
    PrintResult fail(PrintIssue issue, Object why) =>
        PrintResult.failed('builtin: $why', printer: name, issue: issue, retry: retry);

    _phase(ReceiptJobPhase.connecting, name, quiet);
    BuiltinInfo info;
    try {
      info = await bridge.builtinInfo();
      if (info.available && info.status == 2) {
        // «تتهيّأ» — لحظةً ثمّ نسأل ثانيةً.
        await pause(const Duration(milliseconds: 1500));
        info = await bridge.builtinInfo();
      }
    } on PrinterFailure catch (f) {
      return fail(f.code == 'unsupported' ? PrintIssue.builtinMissing : PrintIssue.builtinFault, f);
    }
    if (!info.available) return fail(PrintIssue.builtinMissing, 'no built-in printer');
    if (info.model.isNotEmpty) name = info.model;
    final issue = builtinIssue(info.status);
    if (issue != null) return fail(issue, 'status ${info.status}');

    _phase(ReceiptJobPhase.sending, name, quiet);
    final chunks = EscPos.job(img, bandRows: builtinBandRows, cut: t.paper == ReceiptPaper.mm80);
    try {
      final ack = await bridge.builtinPrint(chunks, confirmTimeout(img.height) + const Duration(seconds: 10));
      if (!ack.done) return fail(PrintIssue.builtinUnconfirmed, 'no result in time');
      if (!ack.transaction) return PrintResult.printed(printer: name, ack: PrintAck.sent);
      if (ack.code == 0) return PrintResult.printed(printer: name, ack: PrintAck.confirmed);
      return fail(PrintIssue.builtinRejected, 'result ${ack.code} ${ack.message}');
    } on PrinterFailure catch (f) {
      // انقطاعٌ مع خدمة الطابعة بعد بدء الإرسال ⇒ غير مؤكَّد؛ غيره لم يُرسل شيء.
      return fail(f.code == 'io' ? PrintIssue.builtinUnconfirmed : PrintIssue.builtinFault, f);
    }
  }

  /// حالة طابعة SUNMI ⇒ ما يمنع الطباعة (null = تُطبع؛ ٠ = لم تُعرف فلا تُمنع).
  static PrintIssue? builtinIssue(int status) => switch (status) {
        0 || 1 || 8 => null,
        2 => PrintIssue.builtinBusy,
        4 => PrintIssue.paperOut,
        5 => PrintIssue.overheated,
        6 => PrintIssue.coverOpen,
        505 => PrintIssue.builtinMissing,
        _ => PrintIssue.builtinFault,
      };

  /// رمز الطبقة الأصليّة ⇒ السبب.
  @visibleForTesting
  static PrintIssue issueOf(String code) => switch (code) {
        'unsupported' => PrintIssue.btUnsupported,
        'off' => PrintIssue.btOff,
        'permission' => PrintIssue.permission,
        'not_found' => PrintIssue.notFound,
        'connect_failed' => PrintIssue.connectFailed,
        'timeout' => PrintIssue.timeout,
        'no_write' => PrintIssue.noWriteChannel,
        'io' => PrintIssue.disconnected,
        _ => PrintIssue.unknown,
      };

  /// مهلة شريطٍ بقدر ما تطبعه طابعةٌ متوسّطة (~٨٠٠ صفّ في الثانية = ١٠٠ ملم/ث).
  @visibleForTesting
  static Duration bandPause(int rows) => Duration(milliseconds: (rows * 1000 / 800).round());

  /// كم ننتظر ردّ الطابعة بعد الوصل: زمن طباعته (~٤٠٠ صفّ/ث = ٥٠ ملم/ث) + ٣ ثوانٍ، بين ٤ و٣٠ ثانية.
  @visibleForTesting
  static Duration confirmTimeout(int rows) =>
      Duration(milliseconds: math.min(30000, math.max(4000, (rows * 1000 / 400).round() + 3000)));
}

/// الطابعة المختارة لحظة الطلب.
@immutable
class _Target {
  const _Target(this.mode, this.device, this.paper);

  final ReceiptPrinterMode mode;
  final SavedReceiptPrinter? device;
  final ReceiptPaper paper;

  String get key => '${mode.name}|${device?.id ?? ''}|${paper.mm}';

  static _Target? current() {
    if (!ReceiptPrinterPrefs.enabled) return null;
    return _Target(ReceiptPrinterPrefs.mode.value, ReceiptPrinterPrefs.device.value, ReceiptPrinterPrefs.paper.value);
  }
}
