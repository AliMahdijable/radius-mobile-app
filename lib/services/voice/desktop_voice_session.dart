import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../../api/api_client.dart';
import '../auth_storage.dart';

enum DesktopVoicePhase { idle, starting, listening, transcribing }

abstract interface class VoiceCapture {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> start();
  Future<void> stop();
  Future<void> dispose();
}

class RecordVoiceCapture implements VoiceCapture {
  final AudioRecorder _recorder = AudioRecorder();
  @override
  Future<bool> hasPermission() => _recorder.hasPermission();
  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      // الهاتف (وضع «تلقائي»): مايك الجهاز نفسه — بلا توجيه سمّاعة البلوتوث (يحتاج إذناً لا نطلبه). ويندوز لا يقرؤه.
      androidConfig: AndroidRecordConfig(manageBluetooth: false)));
  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

typedef VoiceTranscribe = Future<String> Function(
    Uint8List wav, CancelToken cancel);

/// ما فهمه خادمنا من التسجيل: النصّ، لغته (ar/en — تُعرف من النطق)، وبدائل ما سُمع (الأوّل = [text]).
class VoiceTranscript {
  const VoiceTranscript(this.text, {this.lang, this.alts = const []});
  final String text;
  final String? lang;
  final List<String> alts;
}

typedef VoiceTranscribeFull = Future<VoiceTranscript> Function(
    Uint8List wav, CancelToken cancel, String language);

/// Windows records bounded PCM in memory; only our server receives it. No command
/// is executed here. Closing the sheet cancels capture and rejects late results.
///
/// ١٠ نوفمبر («الأمر الصوتي ٢»): الخادم يتعرّف العربيّة والإنكليزيّة من النطق ([language] = auto) أو يُلزم بإحداهما (ar/en)،
/// ويعيد لغة ما فهم وبدائله ([onTranscript]) — والهاتف يستعمل الجلسة نفسها في وضع «تلقائي».
class DesktopVoiceSession extends ChangeNotifier {
  DesktopVoiceSession(
      {VoiceCapture Function()? captureFactory,
      VoiceTranscribe? transcribe,
      VoiceTranscribeFull? transcribeFull,
      Future<String> Function()? scope,
      required this.onText,
      this.onTranscript,
      required this.onError,
      this.language = 'auto',
      this.settingsName = 'ويندوز'})
      : _captureFactory = captureFactory ?? RecordVoiceCapture.new,
        _transcribe = transcribeFull ??
            (transcribe == null
                ? _send
                : (wav, cancel, _) async => VoiceTranscript(await transcribe(wav, cancel))),
        _scope = scope ?? _currentScope;

  static const maxBytes = 16000 * 2 * 15;

  /// سكوتٌ ينهي التسجيل (١١ نوفمبر — المالك: «الاوامر الصوتيه صار يتاخر هواي… بالأخص بوضع التلقائي»): كان ١٫٥ث دائماً. بعد جملةٍ
  /// قيلت (≥ ثانية كلام) يكفي ١٫١ث؛ ومن قال كلمةً وسكت يفكّر بالاسم يُمهَل ١٫٥ث كما كان.
  static const hangAfterPhrase = 35200; // ١٫١ث
  static const hangAfterWord = 48000; // ١٫٥ث
  static const _phraseBytes = 32000; // ثانية كلام

  /// ما يُرسل: الكلام بهامش ٠٫٣٥ث قبله وبعده — انتظار البداية وسكوت النهاية لا يُرفعان (الرفع بشبكة الهاتف هو الأبطأ).
  static const _trimMargin = 11200;
  final VoiceCapture Function() _captureFactory;
  final VoiceTranscribeFull _transcribe;
  final Future<String> Function() _scope;
  final ValueChanged<String> onText;

  /// النصّ مع لغته وبدائله — يُنادى بدل [onText] حين يُعطى.
  final ValueChanged<VoiceTranscript>? onTranscript;
  final ValueChanged<String> onError;

  /// auto (يُعرف من النطق) أو ar أو en — تُقرأ لحظة الإرسال.
  String language;

  /// اسم المنصّة في رسالة صلاحيّة الميكروفون («إعدادات ويندوز» / «إعدادات الهاتف»).
  final String settingsName;
  DesktopVoicePhase phase = DesktopVoicePhase.idle;
  VoiceCapture? _capture;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _limit;
  CancelToken? _cancel;
  BytesBuilder _audio = BytesBuilder(copy: true);
  int _generation = 0;
  bool _disposed = false;
  bool _heardSpeech = false;
  int _silentBytes = 0;
  int _speechBytes = 0;

  /// حدّا الكلام بما جُمع (بايت): بداية أوّل قطعةٍ فوق العتبة ونهاية آخرها.
  int _speechFrom = -1;
  int _speechTo = 0;

  /// شدّة كلّ قطعةٍ سُمعت — منها عتبة الصمت في الضجيج ([_quietBelow]).
  final List<double> _levels = [];
  String _startedScope = '';

  static Future<String> _currentScope() async =>
      '${await AuthStorage.readAdminId()}:${await AuthStorage.readAdminUsername()}:${await AuthStorage.isEmployee()}';

  static Future<VoiceTranscript> _send(
      Uint8List wav, CancelToken cancel, String language) async {
    final r = await ApiClient.dio.post<dynamic>('/api/v2/ai/transcribe',
        data: wav,
        cancelToken: cancel,
        options: Options(
            contentType: 'audio/wav',
            receiveTimeout: const Duration(seconds: 50),
            headers: {
              'x-voice-consent': '1',
              // خادمٌ أقدم يتجاهلها ويردّ العربيّة كما كان
              'x-voice-lang': language == 'ar' || language == 'en' ? language : 'auto',
            }));
    final body = r.data;
    if (r.statusCode == 200 && body is Map && body['success'] == true) {
      return transcriptOf(body);
    }
    if (r.statusCode == 429 || r.statusCode == 503) {
      throw const VoiceInputException(
          'التعرّف الصوتي مشغول الآن — حاول بعد قليل');
    }
    if (r.statusCode == 403 || r.statusCode == 404) {
      throw const VoiceInputException('الأمر الصوتي غير متاح لهذا الحساب');
    }
    throw const VoiceInputException(
        'تعذّر تحويل الصوت — جرّب مجدّداً أو اكتب الأمر');
  }

  void _phase(DesktopVoicePhase value) {
    if (_disposed) return;
    phase = value;
    notifyListeners();
  }

  Future<void> start() async {
    if (_disposed || phase != DesktopVoicePhase.idle) return;
    final gen = ++_generation;
    _audio = BytesBuilder(copy: true);
    _heardSpeech = false;
    _silentBytes = 0;
    _speechBytes = 0;
    _speechFrom = -1;
    _speechTo = 0;
    _levels.clear();
    _phase(DesktopVoicePhase.starting);
    try {
      // هويّة الجلسة تُقرأ والمايك يفتح معاً: كانت قبله (ثلاث قراءاتٍ من التخزين الآمن) والوكيل يبدأ الكلام قبل أن يسمعه شيء
      final scope = _scope();
      unawaited(scope.catchError((Object _) => ''));
      final capture = _capture ??= _captureFactory();
      if (!await capture.hasPermission()) {
        throw VoiceInputException(
            'فعّل صلاحية الميكروفون من إعدادات $settingsName');
      }
      if (_disposed || gen != _generation) return;
      final stream = await capture.start();
      _startedScope = await scope;
      if (_disposed || gen != _generation) {
        try {
          await capture.stop();
        } catch (_) {/* already disposed */}
        return;
      }
      _phase(DesktopVoicePhase.listening);
      _subscription = stream.listen(_chunk, onError: (Object _) {
        if (!_disposed && gen == _generation) {
          unawaited(_fail('تعذّر التسجيل — تأكد من الميكروفون'));
        }
      }, onDone: () {
        if (!_disposed &&
            gen == _generation &&
            phase == DesktopVoicePhase.listening) {
          unawaited(stop());
        }
      });
      _limit = Timer(const Duration(seconds: 15), () => unawaited(stop()));
    } catch (e) {
      if (!_disposed && gen == _generation) {
        await _fail(e is VoiceInputException
            ? e.message
            : 'تعذّر تشغيل الميكروفون — تأكد من إعدادات $settingsName');
      }
    }
  }

  void _chunk(Uint8List chunk) {
    if (_disposed ||
        (phase != DesktopVoicePhase.listening &&
            phase != DesktopVoicePhase.transcribing)) {
      return;
    }
    final available = maxBytes - _audio.length;
    final n = math.min(chunk.length, available);
    final at = _audio.length;
    if (n > 0) _audio.add(Uint8List.sublistView(chunk, 0, n));
    final data = ByteData.sublistView(chunk);
    var squareSum = 0.0;
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final sample = data.getInt16(i, Endian.little).toDouble();
      squareSum += sample * sample;
    }
    final rms = math.sqrt(squareSum / math.max(1, chunk.length ~/ 2));
    _levels.add(rms);
    if (rms >= _quietBelow()) {
      _heardSpeech = true;
      _silentBytes = 0;
      _speechBytes += chunk.length;
      if (_speechFrom < 0) _speechFrom = at;
      _speechTo = at + n;
    } else if (_heardSpeech) {
      _silentBytes += chunk.length;
    }
    final hang = _speechBytes >= _phraseBytes ? hangAfterPhrase : hangAfterWord;
    if (_audio.length >= maxBytes) {
      unawaited(stop());
    } else if (_heardSpeech && _silentBytes >= hang) {
      // السكوت أنهاه ⇒ ما بقي بالمسجّل صمت: لا يُنتظر إغلاقه قبل الإرسال
      unawaited(stop(drain: false));
    }
  }

  /// [pcm] مقصوصاً على الكلام بهامشه — وكما هو إن لم يُعرف حدّاه أو كان القصّ لا يستحقّ (أقلّ من ربع ثانية).
  Uint8List _trimmed(Uint8List pcm) {
    if (_speechFrom < 0 || _speechTo <= _speechFrom) return pcm;
    var from = math.max(0, _speechFrom - _trimMargin);
    var to = math.min(pcm.length, _speechTo + _trimMargin);
    from -= from % 2;
    to -= to % 2;
    if (to - from < 3200 || pcm.length - (to - from) < 8000) return pcm;
    return Uint8List.sublistView(pcm, from, to);
  }

  /// ما دونه صمت. بمكانٍ هادئ ٢٥٠ كما كان؛ وفي الضجيج (محلّ، شارع — الهاتف بوضع «تلقائي») ضجيج المكان نفسه فوقها فلا ينتهي
  /// التسجيل إلّا بسقفه: حين يتّضح فرقٌ بين أهدأ عُشرٍ وأعلى عُشرٍ ممّا سُمع فالعتبة بينهما (وسطهما الهندسيّ). فرقعةٌ واحدة لا
  /// تحرّك العُشر الأعلى، وصوتٌ بمستوىً واحد (لا فرق) يبقى على ٢٥٠.
  double _quietBelow() {
    if (_levels.length < 12) return 250;
    final sorted = [..._levels]..sort();
    final low = sorted[(sorted.length * 0.1).floor()];
    final high = sorted[(sorted.length * 0.9).floor()];
    if (high < 250 || high < low * 2) return 250;
    return math.max(250, math.sqrt(low * high));
  }

  /// ينهي التسجيل ويرسله. [drain]: يُنتظر إغلاق المسجّل أوّلاً فيصل آخر ما فيه (إنهاءٌ باليد أو بالسقف — المتكلّم قد يكون
  /// ما زال يتكلّم)؛ وبلاه (السكوت أنهاه) يُرسل ما جُمع فوراً والمسجّل يُغلق معه — لا شيء فيه غير الصمت.
  Future<void> stop({bool drain = true}) async {
    if (_disposed || phase != DesktopVoicePhase.listening) return;
    final gen = _generation;
    _limit?.cancel();
    _phase(DesktopVoicePhase.transcribing);
    final scopeNow = _scope();
    unawaited(scopeNow.catchError((Object _) => ''));
    Future<void> close() async {
      try {
        await _capture?.stop();
      } catch (_) {/* ما جُمع يكفي */}
      await _subscription?.cancel();
      _subscription = null;
    }

    Future<void>? closing;
    try {
      if (drain) {
        await close();
      } else {
        closing = close();
      }
      if (_disposed || gen != _generation) return;
      final pcm = _audio.takeBytes();
      if (!_heardSpeech || pcm.length < 3200) {
        throw const VoiceInputException('لم يُلتقط كلام — حاول مجدّداً');
      }
      if (await scopeNow != _startedScope || _disposed || gen != _generation) {
        return;
      }
      final cancel = _cancel = CancelToken();
      final heard = await _transcribe(pcmWave(_trimmed(pcm)), cancel, language);
      if (_disposed || gen != _generation || await _scope() != _startedScope) {
        return;
      }
      String clean(String s) =>
          s.trim().replaceAll(RegExp(r'''[.,;:!?،؛؟"']+$'''), '').trim();
      final text = clean(heard.text);
      if (text.isEmpty) {
        throw const VoiceInputException('لم يُلتقط كلام واضح — حاول مجدّداً');
      }
      final full = onTranscript;
      if (full == null) {
        onText(text);
      } else {
        final alts = <String>[text];
        for (final a in heard.alts) {
          final t = clean(a);
          if (t.isNotEmpty && !alts.contains(t)) alts.add(t);
        }
        full(VoiceTranscript(text, lang: heard.lang, alts: alts));
      }
    } catch (e) {
      if (!_disposed &&
          gen == _generation &&
          !(e is DioException && CancelToken.isCancel(e))) {
        onError(e is VoiceInputException
            ? e.message
            : 'تعذّر تحويل الصوت — تأكد من الإنترنت أو اكتب الأمر');
      }
    } finally {
      // المسجّل يُغلق قبل أن يُسمح بتسجيلٍ جديد
      if (closing != null) await closing;
      if (gen == _generation) {
        _audio.clear();
        if (!_disposed) _phase(DesktopVoicePhase.idle);
      }
    }
  }

  Future<void> _fail(String message) async {
    _generation++;
    _phase(DesktopVoicePhase.transcribing);
    _limit?.cancel();
    await _subscription?.cancel();
    try {
      await _capture?.stop();
    } catch (_) {/* best effort */}
    _audio.clear();
    if (!_disposed) {
      _phase(DesktopVoicePhase.idle);
      onError(message);
    }
  }

  Future<void> cancel() async {
    if (_disposed || phase == DesktopVoicePhase.idle) return;
    final gen = ++_generation;
    _cancel?.cancel();
    _limit?.cancel();
    _phase(DesktopVoicePhase.transcribing);
    await _subscription?.cancel();
    try {
      await _capture?.stop();
    } catch (_) {/* already stopping */}
    _audio.clear();
    if (!_disposed && gen == _generation) _phase(DesktopVoicePhase.idle);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _limit?.cancel();
    _cancel?.cancel();
    unawaited(_subscription?.cancel());
    unawaited(_capture?.dispose().catchError((Object _) {}));
    _audio.clear();
    super.dispose();
  }
}

/// ردّ `/api/v2/ai/transcribe` ⇒ النصّ ولغته وبدائله. خادمٌ أقدم (نصٌّ وحده) ⇒ بلا لغةٍ ولا بدائل.
VoiceTranscript transcriptOf(Map<dynamic, dynamic> body) {
  final text = body['text'] is String ? (body['text'] as String).trim() : '';
  final lang = body['lang'];
  final alts = <String>[];
  final raw = body['alts'];
  if (raw is List) {
    for (final a in raw.take(4)) {
      final t = a is Map ? a['text'] : a;
      if (t is String && t.trim().isNotEmpty && t.length <= 300) alts.add(t.trim());
    }
  }
  return VoiceTranscript(text, lang: lang == 'ar' || lang == 'en' ? lang as String : null, alts: alts);
}

class VoiceInputException implements Exception {
  const VoiceInputException(this.message);
  final String message;
}

Uint8List pcmWave(Uint8List pcm) {
  final length = pcm.length - pcm.length % 2;
  final bytes = Uint8List(44 + length);
  final header = ByteData.sublistView(bytes);
  for (final entry in {0: 'RIFF', 8: 'WAVE', 12: 'fmt ', 36: 'data'}.entries) {
    bytes.setRange(entry.key, entry.key + 4, entry.value.codeUnits);
  }
  header.setUint32(4, length + 36, Endian.little);
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 16000, Endian.little);
  header.setUint32(28, 32000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  header.setUint32(40, length, Endian.little);
  bytes.setRange(44, 44 + length, pcm);
  return bytes;
}
