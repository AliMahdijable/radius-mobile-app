import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/voice/desktop_voice_session.dart';
import 'package:rad_mysvcs/services/voice/voice_command.dart';

class Capture implements VoiceCapture {
  var stream = StreamController<Uint8List>(sync: true);
  bool permission = true;
  bool disposed = false;
  int starts = 0;
  Completer<bool>? permissionWait;
  @override
  Future<bool> hasPermission() => permissionWait?.future ?? Future.value(permission);
  @override
  Future<Stream<Uint8List>> start() async {
    if (stream.isClosed) stream = StreamController<Uint8List>(sync: true);
    starts++; return stream.stream;
  }
  @override
  Future<void> stop() async {
    if (!stream.isClosed) {
      final listening = stream.hasListener;
      final closed = stream.close();
      if (listening) await closed;
    }
  }
  @override
  Future<void> dispose() async { disposed = true; await stop(); }
}

/// مسجّلٌ إغلاقه يتأخّر (كأندرويد) — ويسلّم [tail] عند الإغلاق.
class _SlowStop extends Capture {
  final gate = Completer<void>();
  bool stopping = false;
  Uint8List? tail;
  @override
  Future<void> stop() async {
    stopping = true;
    if (!gate.isCompleted) await gate.future;
    final t = tail;
    if (t != null && !stream.isClosed) stream.add(t);
    tail = null;
    await super.stop();
  }
}

Uint8List speech([int length = 6400]) {
  final bytes = Uint8List(length);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i + 1 < length; i += 2) data.setInt16(i, i % 4 == 0 ? 800 : -800, Endian.little);
  return bytes;
}

void main() {
  test('Arabic transcription becomes an Arabic command, target and amount', () async {
    final c = Capture();
    final texts = <String>[];
    final errors = <String>[];
    final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => 'owner:1',
      onText: texts.add, onError: errors.add, transcribe: (wav, cancel) async {
        expect(String.fromCharCodes(wav.take(4)), 'RIFF');
        expect(ByteData.sublistView(wav).getUint32(24, Endian.little), 16000);
        expect(wav.length, 6444);
        return 'سدّد دين أحمد خمسة وعشرين ألف.';
      });
    await s.start(); c.stream.add(speech()); await s.stop();
    expect(errors, isEmpty);
    expect(texts, ['سدّد دين أحمد خمسة وعشرين ألف']);
    final intent = VoiceCommand.parse(texts.single);
    expect(intent.action, VoiceAction.payDebt);
    expect(intent.amount, 25000);
    expect(intent.query, 'احمد');
    expect(s.phase, DesktopVoicePhase.idle);
    s.dispose();
  });

  test('silence and denied permission never send recordings', () async {
    for (final denied in [false, true]) {
      final c = Capture()..permission = !denied;
      var sent = 0;
      final errors = <String>[];
      final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1',
        onText: (_) => fail('no text expected'), onError: errors.add,
        transcribe: (wav, cancel) async { sent++; return ''; });
      await s.start();
      if (!denied) { c.stream.add(Uint8List(6400)); await s.stop(); }
      expect(sent, 0); expect(errors, hasLength(1));
      expect(c.starts, denied ? 0 : 1);
      s.dispose();
    }
  });

  test('closing during permission prevents microphone startup', () async {
    final c = Capture()..permissionWait = Completer<bool>();
    final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1',
      onText: (_) => fail('disposed'), onError: (_) => fail('disposed'));
    final start = s.start();
    await Future<void>.delayed(Duration.zero);
    s.dispose(); c.permissionWait!.complete(true); await start;
    expect(c.starts, 0); expect(c.disposed, isTrue);
  });

  test('closing during transcription cancels and ignores the late Arabic response', () async {
    final c = Capture(); final reply = Completer<String>();
    final requested = Completer<void>();
    var cancelled = false;
    final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1',
      onText: (_) => fail('late response'), onError: (_) => fail('disposed'),
      transcribe: (_, token) { token.whenCancel.then((_) => cancelled = true); requested.complete(); return reply.future; });
    await s.start(); c.stream.add(speech()); final stop = s.stop();
    await requested.future; s.dispose(); reply.complete('فعل علي حسين'); await stop;
    expect(cancelled, isTrue);
  });

  test('company switch discards the recording before sending', () async {
    final c = Capture(); var company = '1'; var sent = false;
    final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => company,
      onText: (_) => fail('wrong company'), onError: (_) => fail('no error'),
      transcribe: (wav, cancel) async { sent = true; return ''; });
    await s.start(); c.stream.add(speech()); company = '2'; await s.stop();
    expect(sent, isFalse); s.dispose();
  });

  test('late cancelled response cannot erase a new recording', () async {
    final c = Capture(); final oldReply = Completer<String>();
    final requested = Completer<void>(); var calls = 0;
    final texts = <String>[];
    final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1',
      onText: texts.add, onError: (_) => fail('unexpected'), transcribe: (wav, cancel) {
        calls++;
        if (calls == 1) { requested.complete(); return oldReply.future; }
        expect(wav.length, 6444);
        return Future.value('فعل علي حسين');
      });
    await s.start(); c.stream.add(speech()); final oldStop = s.stop();
    await requested.future; await s.cancel();
    await s.start(); c.stream.add(speech());
    oldReply.complete('نص قديم'); await oldStop;
    expect(s.phase, DesktopVoicePhase.listening);
    await s.stop(); expect(texts, ['فعل علي حسين']); s.dispose();
  });

  test('audio is capped at 15 seconds even when the native stream sends too much', () async {
    final c = Capture(); final received = Completer<int>();
    final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1',
      onText: (_) {}, onError: (_) => fail('unexpected'),
      transcribe: (wav, _) async { received.complete(wav.length); return 'فعل علي حسين'; });
    await s.start(); c.stream.add(speech(DesktopVoiceSession.maxBytes + 6400));
    expect(await received.future, DesktopVoiceSession.maxBytes + 44);
    await Future<void>.delayed(Duration.zero); s.dispose();
  });

  test('١٠ نوفمبر: اللغة المطلوبة تُرسل، ولغة ما فُهم وبدائله تصل نظيفةً بلا تكرار — والأوّل ما يُكتب', () async {
    final c = Capture();
    final heard = <VoiceTranscript>[];
    final asked = <String>[];
    final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => 'owner:1', language: 'auto',
      onText: (_) => fail('onTranscript يُنادى بدله'), onTranscript: heard.add, onError: (e) => fail(e),
      transcribeFull: (wav, cancel, language) async {
        asked.add(language);
        return const VoiceTranscript('Activate Ali Hassan.', lang: 'en',
            alts: ['Activate Ali Hassan.', 'Activate Ali Hussein', '  ', 'Activate Ali Hussein.']);
      });
    await s.start(); c.stream.add(speech()); await s.stop();
    expect(asked, ['auto']);
    expect(heard.single.text, 'Activate Ali Hassan');
    expect(heard.single.lang, 'en');
    expect(heard.single.alts, ['Activate Ali Hassan', 'Activate Ali Hussein']);
    final intent = VoiceCommand.parse(heard.single.alts.last);
    expect([intent.action, intent.query, intent.lang], [VoiceAction.activate, 'ali hussein', 'en']);
    // اللغة تُقرأ لحظة الإرسال — تبديلها بين تسجيلين يسري على التالي
    s.language = 'ar';
    await s.start(); c.stream.add(speech()); await s.stop();
    expect(asked, ['auto', 'ar']);
    s.dispose();
  });

  test('في الضجيج ينتهي التسجيل بسكوت المتكلّم لا بسقفه — وفرقعةٌ واحدة لا تقطع كلاماً عاديّاً', () async {
    Uint8List level(int amplitude) {
      final bytes = Uint8List(640); // ٢٠ مث
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i + 1 < 640; i += 2) data.setInt16(i, i % 4 == 0 ? amplitude : -amplitude, Endian.little);
      return bytes;
    }

    // محلٌّ صاخب: ضجيج ٦٠٠ (فوق عتبة الهدوء ٢٥٠) ثمّ كلام ٦٠٠٠ ثمّ الضجيج نفسه
    var c = Capture();
    var sent = 0;
    var s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1', onText: (_) {}, onError: (e) => fail(e),
      transcribe: (wav, _) async { sent = wav.length; return 'فعل علي حسين'; });
    await s.start();
    for (var i = 0; i < 25; i++) c.stream.add(level(600));
    for (var i = 0; i < 100; i++) c.stream.add(level(6000));
    expect(s.phase, DesktopVoicePhase.listening);
    for (var i = 0; i < 90 && s.phase == DesktopVoicePhase.listening; i++) c.stream.add(level(600));
    await Future<void>.delayed(Duration.zero);
    expect(sent, greaterThan(0), reason: 'سكت المتكلّم ⇒ أُرسل بعد ثانيةٍ ونصف من ضجيج المكان');
    expect(sent, lessThan(DesktopVoiceSession.maxBytes), reason: 'لا انتظار للسقف (١٥ث)');
    s.dispose();

    // فرقعةٌ عالية أوّل التسجيل ثمّ كلامٌ عاديّ طويل: لا يُقطع
    c = Capture();
    sent = 0;
    s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1', onText: (_) {}, onError: (e) => fail(e),
      transcribe: (wav, _) async { sent = wav.length; return 'فعل علي حسين'; });
    await s.start();
    c.stream.add(level(20000));
    for (var i = 0; i < 200; i++) c.stream.add(level(3000)); // ٤ث كلام
    expect(s.phase, DesktopVoicePhase.listening, reason: 'الكلام ليس «صمتاً» لأنّ فرقعةً سبقته');
    expect(sent, 0);
    for (var i = 0; i < 80 && s.phase == DesktopVoicePhase.listening; i++) c.stream.add(level(0));
    await Future<void>.delayed(Duration.zero);
    expect(sent, greaterThan(0));
    s.dispose();
  });

  group('١١ نوفمبر — «الاوامر الصوتيه صار يتاخر هواي… بالأخص بوضع التلقائي»', () {
    Uint8List level(int amplitude) {
      final bytes = Uint8List(640); // ٢٠ مث
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i + 1 < 640; i += 2) data.setInt16(i, i % 4 == 0 ? amplitude : -amplitude, Endian.little);
      return bytes;
    }

    /// كم قطعة صمتٍ (٢٠ مث) بعد [speechChunks] قطعة كلام حتى يُنهى التسجيل.
    Future<int> silenceUntilStop(int speechChunks) async {
      final c = Capture();
      final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1', onText: (_) {}, onError: (e) => fail(e),
        transcribe: (wav, _) async => 'فعل علي حسين');
      await s.start();
      for (var i = 0; i < speechChunks; i++) c.stream.add(level(3000));
      var n = 0;
      while (s.phase == DesktopVoicePhase.listening && n < 400) { c.stream.add(level(0)); n++; }
      await Future<void>.delayed(Duration.zero);
      s.dispose();
      return n;
    }

    test('بعد جملةٍ قيلت (≥ ثانية كلام) يكفي ١٫١ث سكوت — ومن قال كلمةً وسكت يُمهَل ١٫٥ث كما كان', () async {
      expect(await silenceUntilStop(60), 55, reason: '١٫٢ث كلام ⇒ ١٫١ث (٥٥ × ٢٠ مث)');
      expect(await silenceUntilStop(20), 75, reason: '٠٫٤ث كلام («فعّل…» ويفكّر بالاسم) ⇒ ١٫٥ث');
      expect(DesktopVoiceSession.hangAfterPhrase, lessThan(DesktopVoiceSession.hangAfterWord));
    });

    test('ما يُرفع هو الكلام بهامشه — انتظار البداية وسكوت النهاية لا يُرسلان', () async {
      final c = Capture();
      var sent = 0;
      final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1', onText: (_) {}, onError: (e) => fail(e),
        transcribe: (wav, _) async {
          sent = wav.length;
          expect(ByteData.sublistView(wav).getUint32(40, Endian.little), wav.length - 44, reason: 'ترويسة WAV بطول المقصوص');
          return 'فعل علي حسين';
        });
      await s.start();
      for (var i = 0; i < 50; i++) c.stream.add(level(0)); // ثانية انتظار قبل الكلام
      for (var i = 0; i < 100; i++) c.stream.add(level(3000)); // ثانيتا كلام
      while (s.phase == DesktopVoicePhase.listening) c.stream.add(level(0));
      await Future<void>.delayed(Duration.zero);
      // ٦٤٠٠٠ كلام + ٠٫٣٥ث قبله وبعده (١١٢٠٠ × ٢) — لا الـ١٣١٢٠٠ كلّها
      expect(sent, 44 + 64000 + 22400);
      s.dispose();
    });

    test('تسجيلٌ قصير كلّه كلام لا يُقصّ (لا شيء يُكسب)', () async {
      final c = Capture();
      var sent = 0;
      final s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1', onText: (_) {}, onError: (e) => fail(e),
        transcribe: (wav, _) async { sent = wav.length; return 'فعل علي حسين'; });
      await s.start();
      for (var i = 0; i < 40; i++) c.stream.add(level(3000));
      await s.stop();
      expect(sent, 44 + 40 * 640);
      s.dispose();
    });

    test('السكوت أنهاه ⇒ يُرسل فوراً والمسجّل يُغلق معه؛ إنهاءٌ باليد ينتظر آخر ما بالمسجّل', () async {
      // السكوت: الإرسال لا ينتظر إغلاق المسجّل
      var c = _SlowStop();
      var sent = 0;
      var s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1', onText: (_) {}, onError: (e) => fail(e),
        transcribe: (wav, _) async { sent = wav.length; return 'فعل علي حسين'; });
      await s.start();
      for (var i = 0; i < 60; i++) c.stream.add(level(3000));
      while (s.phase == DesktopVoicePhase.listening) c.stream.add(level(0));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.stopping, isTrue);
      expect(sent, greaterThan(0), reason: 'أُرسل والمسجّل لم يُغلق بعد');
      expect(s.phase, DesktopVoicePhase.transcribing, reason: 'لا تسجيل جديد قبل إغلاق المسجّل');
      c.gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(s.phase, DesktopVoicePhase.idle);
      s.dispose();

      // باليد: ينتظر الإغلاق ليصل آخر ما قيل
      c = _SlowStop();
      sent = 0;
      s = DesktopVoiceSession(captureFactory: () => c, scope: () async => '1', onText: (_) {}, onError: (e) => fail(e),
        transcribe: (wav, _) async { sent = wav.length; return 'فعل علي حسين'; });
      await s.start();
      for (var i = 0; i < 30; i++) c.stream.add(level(3000));
      final stopping = s.stop();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sent, 0, reason: 'لم يُرسل قبل أن يسلّم المسجّل آخر ما فيه');
      c.tail = level(3000); // آخر ما بالمسجّل يصل عند الإغلاق
      c.gate.complete();
      await stopping;
      expect(sent, 44 + 31 * 640);
      s.dispose();
    });
  });

  test('ردّ الخادم: الجديد بلغته وبدائله، والأقدم (نصٌّ وحده) كما كان', () {
    final now = transcriptOf({
      'success': true, 'text': ' فعّل علي حسين ', 'lang': 'ar',
      'alts': [{'lang': 'ar', 'text': 'فعّل علي حسين'}, {'lang': 'en', 'text': 'Fail Ali Hussein'}, {'lang': 'ar', 'text': ''}, 7],
    });
    expect([now.text, now.lang, now.alts], ['فعّل علي حسين', 'ar', ['فعّل علي حسين', 'Fail Ali Hussein']]);
    final old = transcriptOf({'success': true, 'text': 'فعّل علي حسين'});
    expect([old.text, old.lang, old.alts], ['فعّل علي حسين', null, <String>[]]);
    expect(transcriptOf({'success': true, 'text': 'x', 'lang': 'fr'}).lang, isNull, reason: 'لغةٌ غير العربيّة والإنكليزيّة لا تُعتمد');
  });

  test('typed Arabic and ASR Arabic use the same parser', () {
    for (final phrase in ['فعّل علي حسين', 'فعل علي حسين', 'فعّل، علي، حسين.']) {
      final intent = VoiceCommand.parse(phrase);
      expect(intent.action, VoiceAction.activate); expect(intent.query, 'علي حسين');
    }
    for (final phrase in ['سدّد دين أحمد ٢٥ ألف', 'سدد دين أحمد خمسة وعشرين ألف', 'سدّد دين أحمد 25 ألف.']) {
      final intent = VoiceCommand.parse(phrase);
      expect(intent.action, VoiceAction.payDebt); expect(intent.amount, 25000); expect(intent.query, 'احمد');
    }
    for (final phrase in ['افحص سكتر الشمال', 'افحص سكتر الشمال.']) {
      final intent = VoiceCommand.parse(phrase);
      expect(intent.action, VoiceAction.checkDevice);
      expect(intent.query, 'الشمال');
      expect(intent.deviceKind, 'sector');
    }
  });
}
