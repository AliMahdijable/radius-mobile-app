import 'dart:async';
import 'dart:typed_data';

import 'package:rad_mysvcs/services/print_output.dart';
import 'package:rad_mysvcs/services/receipt_printer/escpos.dart';
import 'package:rad_mysvcs/services/receipt_printer/printer_bridge.dart';
import 'package:rad_mysvcs/services/receipt_printer/receipt_printer.dart';
import 'package:rad_mysvcs/services/receipt_printer/receipt_printer_prefs.dart';

/// طابعةٌ وهميّة على القناة الأصليّة: تسجّل ما يُرسل، وتجيب أسئلة الحالة إن طُلب، وتنقطع عند قطعةٍ بعينها.
class FakePrinterBridge implements PrinterBridge {
  BtState state = const BtState(supported: true, enabled: true);
  List<BtDevice> paired = const [
    BtDevice(id: 'AA:BB:CC:DD:EE:01', name: 'MPT-II', printer: true),
    BtDevice(id: 'AA:BB:CC:DD:EE:02', name: 'Headset'),
  ];
  List<BtDevice> scanned = const [BtDevice(id: '6F1C2D3E-0000-0000-0000-000000000001', name: 'Printer001', rssi: -50)];

  /// رمز فشل الاتّصال (`timeout` · `connect_failed` · `not_found` …) — null = يتّصل.
  String? connectFailure;

  /// ردود أسئلة الحالة: أوّل بايتٍ في الأمر المكتوب ⇒ ما تجيب به (null = صامتة).
  List<int>? replyRealtime1;
  List<int>? replyRealtime2;
  List<int>? replyRealtime4;
  List<int>? replyPaperInSequence;

  /// تنقطع عند كتابة القطعة رقم [dropAtWrite] (من ١) — null = لا تنقطع.
  int? dropAtWrite;

  final writes = <Uint8List>[];
  final calls = <String>[];
  final _pending = <int>[];
  int connects = 0;
  int closes = 0;

  BuiltinInfo builtin = const BuiltinInfo(available: false);
  BuiltinAck builtinAck = const BuiltinAck(transaction: true, done: true, code: 0);
  PrinterFailure? builtinFailure;
  final builtinJobs = <List<Uint8List>>[];

  /// يؤخّر كلّ كتابة حتى يُكمل — لاختبار الطلبات المتزامنة.
  Completer<void>? gate;

  /// بايتات الوصل وحده (بلا أسئلة الحالة).
  List<Uint8List> get receiptWrites =>
      [for (final w in writes) if (!(w.length == 3 && (w[0] == EscPos.dle || (w[0] == EscPos.gs && w[1] == 0x72)))) w];

  @override
  Future<BtState> btState() async {
    calls.add('state');
    return state;
  }

  @override
  Future<List<BtDevice>> btPaired() async {
    calls.add('paired');
    return paired;
  }

  @override
  Future<List<BtDevice>> btScan(Duration timeout) async {
    calls.add('scan');
    return scanned;
  }

  @override
  Future<void> btConnect(String id, Duration timeout) async {
    calls.add('connect:$id');
    connects++;
    final f = connectFailure;
    if (f != null) throw PrinterFailure(f);
  }

  @override
  Future<void> btWrite(Uint8List data) async {
    if (gate != null) await gate!.future;
    if (dropAtWrite != null && writes.length + 1 == dropAtWrite) {
      dropAtWrite = null;
      throw const PrinterFailure('io', 'Broken pipe');
    }
    writes.add(Uint8List.fromList(data));
    calls.add('write:${data.length}');
    if (data.length == 3 && data[0] == EscPos.dle && data[1] == EscPos.eot) {
      final r = switch (data[2]) { 1 => replyRealtime1, 2 => replyRealtime2, 4 => replyRealtime4, _ => null };
      if (r != null) _pending.addAll(r);
    }
    if (data.length == 3 && data[0] == EscPos.gs && data[1] == 0x72 && replyPaperInSequence != null) {
      _pending.addAll(replyPaperInSequence!);
    }
  }

  @override
  Future<Uint8List> btRead(Duration timeout, {int max = 64}) async {
    calls.add('read');
    final out = Uint8List.fromList(_pending.take(max).toList());
    _pending.removeRange(0, out.length);
    return out;
  }

  @override
  Future<void> btClose() async {
    calls.add('close');
    closes++;
  }

  @override
  Future<void> btSettings() async => calls.add('settings');

  @override
  Future<BuiltinInfo> builtinInfo() async {
    calls.add('builtinInfo');
    return builtin;
  }

  @override
  Future<BuiltinAck> builtinPrint(List<Uint8List> chunks, Duration timeout) async {
    calls.add('builtinPrint');
    final f = builtinFailure;
    if (f != null) throw f;
    builtinJobs.add([for (final c in chunks) Uint8List.fromList(c)]);
    return builtinAck;
  }
}

class FakeBtPermission implements BtPermissionGate {
  BtPermit permit = BtPermit.granted;
  int asked = 0;
  int opened = 0;

  @override
  Future<BtPermit> ensure() async {
    asked++;
    return permit;
  }

  @override
  Future<bool> openSettings() async {
    opened++;
    return true;
  }
}

/// يركّب الوهميّات على [ReceiptPrinter.instance] ويعيدها كما كانت في [restore].
class ReceiptPrinterHarness {
  ReceiptPrinterHarness() {
    _bridge = printer.bridge;
    _permission = printer.permission;
    _render = printer.render;
    _pause = printer.pause;
    _clock = printer.clock;
    printer
      ..bridge = bridge
      ..permission = permission
      ..render = (doc, paper) async {
        renders.add(paper);
        return image ?? MonoImage.blank(paper.dots, 130);
      }
      ..pause = (_) async {}
      ..clock = () => now;
    printer.forget();
    ReceiptPrinterPrefs.debugSupported = true;
    ReceiptPrinterPrefs.debugBuiltinSupported = true;
    ReceiptPrinterPrefs.debugIos = false;
    ReceiptPrinterPrefs.reset();
  }

  final printer = ReceiptPrinter.instance;
  final bridge = FakePrinterBridge();
  final permission = FakeBtPermission();
  final renders = <ReceiptPaper>[];
  MonoImage? image;
  DateTime now = DateTime(2026, 11, 9, 12);

  late final PrinterBridge _bridge;
  late final BtPermissionGate _permission;
  late final Future<MonoImage> Function(PrintDoc, ReceiptPaper) _render;
  late final Future<void> Function(Duration) _pause;
  late final DateTime Function() _clock;

  /// طابعة بلوتوث مختارة.
  void useBluetooth({ReceiptPaper paper = ReceiptPaper.mm58}) {
    ReceiptPrinterPrefs.mode.value = ReceiptPrinterMode.bluetooth;
    ReceiptPrinterPrefs.device.value = const SavedReceiptPrinter(id: 'AA:BB:CC:DD:EE:01', name: 'MPT-II');
    ReceiptPrinterPrefs.paper.value = paper;
  }

  void useBuiltin({ReceiptPaper paper = ReceiptPaper.mm58}) {
    ReceiptPrinterPrefs.mode.value = ReceiptPrinterMode.builtin;
    ReceiptPrinterPrefs.paper.value = paper;
  }

  void restore() {
    printer
      ..bridge = _bridge
      ..permission = _permission
      ..render = _render
      ..pause = _pause
      ..clock = _clock;
    printer.forget();
    ReceiptPrinterPrefs.reset();
    ReceiptPrinterPrefs.debugSupported = null;
    ReceiptPrinterPrefs.debugBuiltinSupported = null;
    ReceiptPrinterPrefs.debugIos = null;
  }
}
