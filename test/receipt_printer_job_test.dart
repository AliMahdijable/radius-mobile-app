import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:rad_mysvcs/services/print_output.dart';
import 'package:rad_mysvcs/services/receipt_printer/escpos.dart';
import 'package:rad_mysvcs/services/receipt_printer/printer_bridge.dart';
import 'package:rad_mysvcs/services/receipt_printer/receipt_printer.dart';
import 'package:rad_mysvcs/services/receipt_printer/receipt_printer_prefs.dart';

import 'support/fake_receipt_printer.dart';

/// «طابعة الوصولات» (٩ نوفمبر) — الوصل من الطلب إلى الطابعة، بطابعةٍ وهميّة على القناة الأصليّة:
///   ١. بلوتوث صامتة ⇒ «أُرسل»؛ تجيب أسئلة الحالة ⇒ «تأكّدت الطباعة» بعد ردّ «GS r 1» على الوصل.
///   ٢. الورق نفد / الغطاء مفتوح قبل الإرسال ⇒ لا يُرسل شيء، والسبب مع «حاول ثانيةً».
///   ٣. انقطاعٌ أثناء الإرسال ⇒ «غير مؤكَّد» مع «إعادة الطباعة» (بلا منع التكرار)؛ قبل أيّ شريط ⇒ لم يُطبع شيء.
///   ٤. الإذن والبلوتوث المطفأ والطابعة البعيدة ⇒ أسبابها، ولا اتّصال بلا إذن.
///   ٥. النقر المكرّر: وصلٌ واحد أثناءه وبعده بلحظات؛ وصلان مختلفان بالدور لا متداخلَين.
///   ٦. SUNMI: الحالة قبل الطباعة، و«المعاملة» تؤكّد أو «غير مؤكَّد».
///   ٧. ٥٨/٨٠ ملم يصلان الرسم والقصّ؛ وبلا طابعة مختارة لا شيء.
PrintDoc _doc(String name) => PrintDoc(Uint8List.fromList(const [1, 2, 3]), PdfPageFormat.roll80, name: name);

void main() {
  late ReceiptPrinterHarness h;

  setUp(() => h = ReceiptPrinterHarness());
  tearDown(() => h.restore());

  ReceiptPrinter p() => h.printer;

  group('١ بلوتوث: أُرسل / تأكّدت', () {
    test('طابعةٌ صامتة: سؤال الورق بلا ردّ ⇒ الوصل كلّه ثمّ «أُرسل» والاتّصال يُغلق', () async {
      h.useBluetooth();
      final r = await p().send(_doc('activation-ahmed01'));
      expect(r.outcome, PrintOutcome.printed);
      expect(r.ack, PrintAck.sent);
      expect(r.printer, 'MPT-II');
      expect(h.bridge.calls.first, 'state');
      expect(h.bridge.calls, contains('connect:AA:BB:CC:DD:EE:01'));
      // سؤالٌ واحد عن الورق (لم تُجب فلا ثانٍ)، ثمّ ESC @ والشرائط والتغذية، ولا «GS r 1»
      expect(h.bridge.writes.first, EscPos.realtimeStatus(4));
      expect(h.bridge.writes.where((w) => w.length == 3 && w[0] == EscPos.dle).length, 1);
      final job = h.bridge.receiptWrites;
      expect(job.first, EscPos.initialize());
      expect(job.last, [0x1B, 0x64, 4], reason: '٥٨ ملم بلا قصّ');
      expect(job.length, 1 + 3 + 1, reason: '١٣٠ صفّاً ⇒ ٣ شرائط من ٦٤');
      expect(h.bridge.writes.any((w) => w.length == 3 && w[0] == EscPos.gs && w[1] == 0x72), isFalse);
      expect(h.bridge.calls.last, 'close');
    });

    test('طابعةٌ تجيب: الورق سليم ثمّ ردّ «GS r 1» بعد الوصل ⇒ «تأكّدت الطباعة»', () async {
      h.useBluetooth();
      h.bridge
        ..replyRealtime4 = [0x12]
        ..replyRealtime2 = [0x12]
        ..replyPaperInSequence = [0x00];
      final r = await p().send(_doc('activation-ahmed01'));
      expect(r.ack, PrintAck.confirmed);
      // السؤال عن الورق قبل الوصل، و«GS r 1» بعد آخر قطعة
      final iInit = h.bridge.writes.indexWhere((w) => w.length == 2 && w[0] == 0x1B && w[1] == 0x40);
      final iGsR = h.bridge.writes.indexWhere((w) => w.length == 3 && w[0] == EscPos.gs && w[1] == 0x72);
      expect(iInit, greaterThan(0));
      expect(iGsR, h.bridge.writes.length - 1);
    });

    test('ردّ «GS r 1» يقول نفد الورق ⇒ «غير مؤكَّد» (قد يكون الوصل ناقصاً) مع إعادة الطباعة', () async {
      h.useBluetooth();
      h.bridge
        ..replyRealtime4 = [0x12]
        ..replyRealtime2 = [0x12]
        ..replyPaperInSequence = [0x0C];
      final r = await p().send(_doc('activation-ahmed01'));
      expect(r.issue, PrintIssue.paperOutMidway);
      expect(r.uncertain, isTrue);
      expect(r.retry, isNotNull);
    });

    test('تجيب قبل الوصل وتصمت بعده ⇒ «أُرسل» لا «تأكّدت»', () async {
      h.useBluetooth();
      h.bridge
        ..replyRealtime4 = [0x12]
        ..replyRealtime2 = [0x12];
      final r = await p().send(_doc('x'));
      expect(r.ack, PrintAck.sent);
    });
  });

  group('٢ قبل الإرسال', () {
    test('الطابعة تقول نفد الورق ⇒ لا يُرسل من الوصل شيء، والسبب مع «حاول ثانيةً»', () async {
      h.useBluetooth();
      h.bridge.replyRealtime4 = [0x72];
      final r = await p().send(_doc('x'));
      expect(r.outcome, PrintOutcome.failed);
      expect(r.issue, PrintIssue.paperOut);
      expect(r.uncertain, isFalse);
      expect(r.retry, isNotNull);
      expect(h.bridge.receiptWrites, isEmpty);
      expect(h.bridge.closes, 1);
    });

    test('الغطاء مفتوح ⇒ سببه، ولا وصل', () async {
      h.useBluetooth();
      h.bridge
        ..replyRealtime4 = [0x12]
        ..replyRealtime2 = [0x16];
      final r = await p().send(_doc('x'));
      expect(r.issue, PrintIssue.coverOpen);
      expect(h.bridge.receiptWrites, isEmpty);
    });
  });

  group('٣ الانقطاع', () {
    test('بعد شريطٍ مُرسل ⇒ «غير مؤكَّد»، و«إعادة الطباعة» تطبعه كاملاً ولو بعد لحظة', () async {
      h.useBluetooth();
      // الكتابات: ١ سؤال الورق · ٢ ESC @ · ٣ الشريط الأوّل · ٤ الثاني ← ينقطع هنا
      h.bridge.dropAtWrite = 4;
      final r = await p().send(_doc('activation-ahmed01'));
      expect(r.outcome, PrintOutcome.failed);
      expect(r.issue, PrintIssue.disconnectedMidway);
      expect(r.uncertain, isTrue);
      expect(h.bridge.closes, 1);
      h.bridge.writes.clear();
      final again = await r.retry!();
      expect(again.ack, PrintAck.sent);
      expect(h.bridge.receiptWrites.length, 5, reason: 'الوصل كاملاً من جديد');
      expect(h.bridge.connects, 2);
    });

    test('ينقطع على «ESC @» (لم يُرسل شريط) ⇒ «لم يُطبع شيء» لا «غير مؤكَّد»', () async {
      h.useBluetooth();
      h.bridge.dropAtWrite = 2;
      final r = await p().send(_doc('x'));
      expect(r.issue, PrintIssue.disconnected);
      expect(r.uncertain, isFalse);
    });

    test('ينقطع أثناء **الشريط الأوّل** ⇒ «غير مؤكَّد» (قد خرج جزءٌ منه) لا «لم يُطبع شيء» — مراجعة 179', () async {
      h.useBluetooth();
      // الكتابات: ١ سؤال الورق · ٢ ESC @ · ٣ الشريط الأوّل ← ينقطع أثناء كتابته
      h.bridge.dropAtWrite = 3;
      final r = await p().send(_doc('x'));
      expect(r.issue, PrintIssue.disconnectedMidway);
      expect(r.uncertain, isTrue);
      expect(r.retry, isNotNull);
    });
  });

  group('٤ الإذن والبلوتوث والطابعة', () {
    test('الإذن مرفوض ⇒ لا اتّصال؛ مرفوضٌ دائماً ⇒ «فتح الإعدادات»', () async {
      h.useBluetooth();
      h.permission.permit = BtPermit.denied;
      expect((await p().send(_doc('a'))).issue, PrintIssue.permission);
      h.permission.permit = BtPermit.blocked;
      expect((await p().send(_doc('b'))).issue, PrintIssue.permissionBlocked);
      expect(h.bridge.connects, 0);
    });

    test('البلوتوث مطفأ ⇒ سببه بلا محاولة اتّصال؛ جهازٌ بلا بلوتوث ⇒ سببه', () async {
      h.useBluetooth();
      h.bridge.state = const BtState(supported: true, enabled: false);
      expect((await p().send(_doc('a'))).issue, PrintIssue.btOff);
      h.bridge.state = const BtState(supported: false, enabled: false);
      expect((await p().send(_doc('b'))).issue, PrintIssue.btUnsupported);
      expect(h.bridge.connects, 0);
    });

    test('الآيفون: البلوتوث مرفوضٌ للتطبيق ⇒ «مرفوضٌ دائماً» (فتح الإعدادات) لا «حاول ثانيةً»؛ أندرويد كما كان', () async {
      h.useBluetooth();
      ReceiptPrinterPrefs.debugIos = true;
      h.bridge.state = const BtState(supported: true, enabled: true, authorized: false);
      expect((await p().send(_doc('a'))).issue, PrintIssue.permissionBlocked);
      expect((await p().discover()).issue, PrintIssue.permissionBlocked);
      // رُفض بين السؤال والاتّصال (الطبقة الأصليّة: permission)
      h.bridge.state = const BtState(supported: true, enabled: true);
      h.bridge.connectFailure = 'permission';
      expect((await p().send(_doc('b'))).issue, PrintIssue.permissionBlocked);
      expect(h.bridge.receiptWrites, isEmpty);
      // أندرويد يسأل ثانيةً: «permission» كما كان
      ReceiptPrinterPrefs.debugIos = false;
      expect((await p().send(_doc('c'))).issue, PrintIssue.permission);
      h.bridge.connectFailure = null;
      h.bridge.state = const BtState(supported: true, enabled: true, authorized: false);
      expect((await p().send(_doc('d'))).issue, PrintIssue.permission);
    });

    test('رموز الاتّصال ⇒ أسبابها (لا تردّ · بعيدة/مشغولة · غير مقترنة · بلا قناة BLE)', () async {
      h.useBluetooth();
      for (final (code, issue) in const [
        ('timeout', PrintIssue.timeout),
        ('connect_failed', PrintIssue.connectFailed),
        ('not_found', PrintIssue.notFound),
        ('no_write', PrintIssue.noWriteChannel),
        ('permission', PrintIssue.permission),
      ]) {
        h.bridge.connectFailure = code;
        final r = await p().send(_doc('doc-$code'));
        expect(r.issue, issue, reason: code);
        expect(r.uncertain, isFalse);
        expect(r.retry, isNotNull);
      }
      expect(h.bridge.receiptWrites, isEmpty);
    });
  });

  group('٥ النقر المكرّر', () {
    test('نقرتان على الوصل نفسه أثناء طباعته ⇒ وصلٌ واحد، والثانية «مكرّر»', () async {
      h.useBluetooth();
      h.bridge.gate = Completer<void>();
      final a = p().send(_doc('activation-ahmed01'));
      final b = p().send(_doc('activation-ahmed01'));
      await Future<void>.delayed(Duration.zero);
      h.bridge.gate!.complete();
      final ra = await a;
      final rb = await b;
      expect(ra.ack, PrintAck.sent);
      expect(rb.ack, PrintAck.duplicate);
      expect(h.bridge.connects, 1);
    });

    test('بعده بلحظات (< ٤ ث) ⇒ لا يُرسل ثانيةً؛ بعد ٤ ث يُطبع؛ و«إعادة الطباعة» تتجاوز المنع', () async {
      h.useBluetooth();
      await p().send(_doc('activation-ahmed01'));
      h.now = h.now.add(const Duration(seconds: 2));
      final dup = await p().send(_doc('activation-ahmed01'));
      expect(dup.ack, PrintAck.duplicate);
      expect(h.bridge.connects, 1);
      final forced = await p().send(_doc('activation-ahmed01'), force: true);
      expect(forced.ack, PrintAck.sent);
      expect(h.bridge.connects, 2);
      h.now = h.now.add(const Duration(seconds: 5));
      final later = await p().send(_doc('activation-ahmed01'));
      expect(later.ack, PrintAck.sent);
      expect(h.bridge.connects, 3);
    });

    test('الفشل لا يمنع المحاولة التالية (لا «مكرّر» بعد وصلٍ لم يُطبع)', () async {
      h.useBluetooth();
      h.bridge.state = const BtState(supported: true, enabled: false);
      expect((await p().send(_doc('x'))).ok, isFalse);
      h.bridge.state = const BtState(supported: true, enabled: true);
      expect((await p().send(_doc('x'))).ack, PrintAck.sent);
    });

    test('وصلان مختلفان معاً ⇒ كلاهما يُطبع، بالدور لا متداخلَين', () async {
      h.useBluetooth();
      final a = p().send(_doc('Sale-1'));
      final b = p().send(_doc('Sale-2'));
      final rs = await Future.wait([a, b]);
      expect(rs.map((r) => r.ack), [PrintAck.sent, PrintAck.sent]);
      final seq = h.bridge.calls.where((c) => c.startsWith('connect') || c == 'close').toList();
      expect(seq, ['connect:AA:BB:CC:DD:EE:01', 'close', 'connect:AA:BB:CC:DD:EE:01', 'close']);
    });
  });

  group('٦ طابعة الجهاز (SUNMI)', () {
    test('جاهزة ⇒ الوصل بوضع المعاملة والطابعة تؤكّد ⇒ «تأكّدت» باسم الجهاز', () async {
      h.useBuiltin();
      h.bridge.builtin = const BuiltinInfo(available: true, vendor: 'sunmi', status: 1, paperMm: 58, model: 'SUNMI V2s');
      final r = await p().send(_doc('activation-ahmed01'));
      expect(r.ack, PrintAck.confirmed);
      expect(r.printer, 'SUNMI V2s');
      final job = h.bridge.builtinJobs.single;
      expect(job.first, EscPos.initialize());
      expect(job[1].sublist(0, 4), [0x1D, 0x76, 0x30, 0x00]);
      expect(job[1][6] + job[1][7] * 256, 128, reason: 'شرائط ١٢٨ صفّاً لطابعة الجهاز');
    });

    test('الحالة قبل الطباعة: نفد الورق · الغطاء · ساخنة · لا طابعة ⇒ أسبابها ولا إرسال', () async {
      h.useBuiltin();
      for (final (status, issue) in const [
        (4, PrintIssue.paperOut),
        (6, PrintIssue.coverOpen),
        (5, PrintIssue.overheated),
        (505, PrintIssue.builtinMissing),
        (3, PrintIssue.builtinFault),
      ]) {
        h.bridge.builtin = BuiltinInfo(available: true, status: status);
        final r = await p().send(_doc('s$status'));
        expect(r.issue, issue, reason: '$status');
      }
      expect(h.bridge.builtinJobs, isEmpty);
    });

    test('لا خدمة SUNMI ⇒ «لم نجد طابعةً مدمجة»', () async {
      h.useBuiltin();
      final r = await p().send(_doc('x'));
      expect(r.issue, PrintIssue.builtinMissing);
    });

    test('هاتفٌ بلا طابعةٍ مدمجة أصلاً ⇒ بلا «حاول ثانيةً»، و«نافذة الطباعة» تعود للوصل التالي (لا تبقى مختارة)', () async {
      h.useBuiltin();
      // الوهميّة افتراضاً: available:false بلا شركة = لا خدمة طابعةٍ مدمجة في الجهاز
      final r = await p().send(_doc('x'));
      expect(r.issue, PrintIssue.builtinMissing);
      expect(r.retry, isNull, reason: 'لن يتغيّر بإعادة');
      expect(ReceiptPrinterPrefs.builtinPresent.value, isFalse);
      expect(ReceiptPrinterPrefs.mode.value, ReceiptPrinterMode.system);
      expect(ReceiptPrinterPrefs.enabled, isFalse);
      expect(h.bridge.builtinJobs, isEmpty);
    });

    test('خدمة SUNMI موجودةٌ ولم تُربط بعد (الشركة معروفة) ⇒ «حاول ثانيةً» والطريقة تبقى', () async {
      h.useBuiltin();
      h.bridge.builtin = const BuiltinInfo(available: false, vendor: 'sunmi');
      final r = await p().send(_doc('x'));
      expect(r.issue, PrintIssue.builtinMissing);
      expect(r.retry, isNotNull);
      expect(ReceiptPrinterPrefs.mode.value, ReceiptPrinterMode.builtin);
      expect(ReceiptPrinterPrefs.enabled, isTrue);
    });

    test('بلا ردٍّ في المهلة أو «لم تُكمل» ⇒ غير مؤكَّد؛ بلا معاملة ⇒ «أُرسل»؛ انقطاع الخدمة ⇒ غير مؤكَّد', () async {
      h.useBuiltin();
      h.bridge.builtin = const BuiltinInfo(available: true, status: 1);
      h.bridge.builtinAck = const BuiltinAck(transaction: true, done: false);
      expect((await p().send(_doc('a'))).issue, PrintIssue.builtinUnconfirmed);
      h.bridge.builtinAck = const BuiltinAck(transaction: true, done: true, code: 1, message: 'out of paper');
      final rej = await p().send(_doc('b'));
      expect(rej.issue, PrintIssue.builtinRejected);
      expect(rej.uncertain, isTrue);
      h.bridge.builtinAck = const BuiltinAck(transaction: false, done: true, code: 0);
      expect((await p().send(_doc('c'))).ack, PrintAck.sent);
      h.bridge.builtinFailure = const PrinterFailure('io');
      expect((await p().send(_doc('d'))).uncertain, isTrue);
    });

    test('ترجمة الحالة: ٠ (لم تُعرف) و١ و٨ لا تمنع، ٢ «تتهيّأ»', () {
      expect(ReceiptPrinter.builtinIssue(0), isNull);
      expect(ReceiptPrinter.builtinIssue(1), isNull);
      expect(ReceiptPrinter.builtinIssue(8), isNull);
      expect(ReceiptPrinter.builtinIssue(2), PrintIssue.builtinBusy);
      expect(ReceiptPrinter.builtinIssue(507), PrintIssue.builtinFault);
    });
  });

  group('٧ الورق والإعداد والحالة', () {
    test('٨٠ ملم: الرسم بعرض ٥٧٦ والقصّ آخر الوصل', () async {
      h.useBluetooth(paper: ReceiptPaper.mm80);
      await p().send(_doc('x'));
      expect(h.renders.single, ReceiptPaper.mm80);
      expect(h.bridge.receiptWrites.last, [0x1B, 0x64, 4, 0x1D, 0x56, 0x42, 0x00]);
      expect(h.bridge.receiptWrites[1].sublist(4, 6), [72, 0]);
    });

    test('بلا طابعةٍ مختارة ⇒ «لم تُختر» بلا قناة', () async {
      final r = await p().send(_doc('x'));
      expect(r.issue, PrintIssue.notConfigured);
      expect(h.bridge.calls, isEmpty);
      ReceiptPrinterPrefs.mode.value = ReceiptPrinterMode.bluetooth; // بلوتوث بلا طابعة
      expect((await p().send(_doc('y'))).issue, PrintIssue.notConfigured);
    });

    test('تعذّر رسم الوصل ⇒ سببه مع «حاول ثانيةً» ولا اتّصال', () async {
      h.useBluetooth();
      h.printer.render = (doc, paper) async => throw StateError('raster');
      final r = await p().send(_doc('x'));
      expect(r.issue, PrintIssue.render);
      expect(r.retry, isNotNull);
      expect(h.bridge.connects, 0);
    });

    test('الحالة تمرّ بالمراحل وتنتهي null', () async {
      h.useBluetooth();
      final phases = <ReceiptJobPhase>[];
      void listen() {
        final s = p().status.value;
        if (s != null && (phases.isEmpty || phases.last != s.phase)) phases.add(s.phase);
      }

      p().status.addListener(listen);
      h.bridge
        ..replyRealtime4 = [0x12]
        ..replyRealtime2 = [0x12]
        ..replyPaperInSequence = [0x00];
      await p().send(_doc('x'), quiet: true);
      p().status.removeListener(listen);
      expect(phases, [
        ReceiptJobPhase.preparing,
        ReceiptJobPhase.connecting,
        ReceiptJobPhase.checking,
        ReceiptJobPhase.sending,
        ReceiptJobPhase.confirming,
      ]);
      expect(p().status.value, isNull);
    });

    test('المهلات: شريط ٦٤ صفّاً ٨٠ م.ث؛ انتظار التأكيد بين ٤ و٣٠ ث', () {
      expect(ReceiptPrinter.bandPause(64), const Duration(milliseconds: 80));
      expect(ReceiptPrinter.confirmTimeout(100), const Duration(seconds: 4));
      expect(ReceiptPrinter.confirmTimeout(2400), const Duration(seconds: 9));
      expect(ReceiptPrinter.confirmTimeout(100000), const Duration(seconds: 30));
      expect(ReceiptPrinter.issueOf('off'), PrintIssue.btOff);
      expect(ReceiptPrinter.issueOf('weird'), PrintIssue.unknown);
    });
  });
}
