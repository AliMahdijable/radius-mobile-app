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
      encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
  @override
  Future<void> stop() async {
    await _recorder.stop();
  }

  @override
  Future<void> dispose() => _recorder.dispose();
}

typedef VoiceTranscribe = Future<String> Function(
    Uint8List wav, CancelToken cancel);

/// Windows records bounded PCM in memory; only our server receives it. No command
/// is executed here. Closing the sheet cancels capture and rejects late results.
class DesktopVoiceSession extends ChangeNotifier {
  DesktopVoiceSession(
      {VoiceCapture Function()? captureFactory,
      VoiceTranscribe? transcribe,
      Future<String> Function()? scope,
      required this.onText,
      required this.onError})
      : _captureFactory = captureFactory ?? RecordVoiceCapture.new,
        _transcribe = transcribe ?? _send,
        _scope = scope ?? _currentScope;

  static const maxBytes = 16000 * 2 * 15;
  final VoiceCapture Function() _captureFactory;
  final VoiceTranscribe _transcribe;
  final Future<String> Function() _scope;
  final ValueChanged<String> onText;
  final ValueChanged<String> onError;
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
  String _startedScope = '';

  static Future<String> _currentScope() async =>
      '${await AuthStorage.readAdminId()}:${await AuthStorage.readAdminUsername()}:${await AuthStorage.isEmployee()}';

  static Future<String> _send(Uint8List wav, CancelToken cancel) async {
    final r = await ApiClient.dio.post<dynamic>('/api/v2/ai/transcribe',
        data: wav,
        cancelToken: cancel,
        options: Options(
            contentType: 'audio/wav',
            receiveTimeout: const Duration(seconds: 50),
            headers: {'x-voice-consent': '1'}));
    final body = r.data;
    if (r.statusCode == 200 && body is Map && body['success'] == true) {
      return body['text'] is String ? (body['text'] as String).trim() : '';
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
    _phase(DesktopVoicePhase.starting);
    try {
      _startedScope = await _scope();
      if (_disposed || gen != _generation) return;
      final capture = _capture ??= _captureFactory();
      if (!await capture.hasPermission()) {
        throw const VoiceInputException(
            'فعّل صلاحية الميكروفون من إعدادات ويندوز');
      }
      if (_disposed || gen != _generation) return;
      final stream = await capture.start();
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
            : 'تعذّر تشغيل الميكروفون — تأكد من إعدادات ويندوز');
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
    if (n > 0) _audio.add(Uint8List.sublistView(chunk, 0, n));
    final data = ByteData.sublistView(chunk);
    var squareSum = 0.0;
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      final sample = data.getInt16(i, Endian.little).toDouble();
      squareSum += sample * sample;
    }
    final rms = math.sqrt(squareSum / math.max(1, chunk.length ~/ 2));
    if (rms >= 250) {
      _heardSpeech = true;
      _silentBytes = 0;
    } else if (_heardSpeech) {
      _silentBytes += chunk.length;
    }
    if (_audio.length >= maxBytes || (_heardSpeech && _silentBytes >= 48000)) {
      unawaited(stop());
    }
  }

  Future<void> stop() async {
    if (_disposed || phase != DesktopVoicePhase.listening) return;
    final gen = _generation;
    _limit?.cancel();
    _phase(DesktopVoicePhase.transcribing);
    try {
      await _capture?.stop();
      await _subscription?.cancel();
      _subscription = null;
      if (_disposed || gen != _generation) return;
      final pcm = _audio.takeBytes();
      if (!_heardSpeech || pcm.length < 3200) {
        throw const VoiceInputException('لم يُلتقط كلام — حاول مجدّداً');
      }
      if (await _scope() != _startedScope || _disposed || gen != _generation) {
        return;
      }
      final cancel = _cancel = CancelToken();
      final text = await _transcribe(pcmWave(pcm), cancel);
      if (_disposed || gen != _generation || await _scope() != _startedScope) {
        return;
      }
      if (text.isEmpty) {
        throw const VoiceInputException('لم يُلتقط كلام واضح — حاول مجدّداً');
      }
      onText(text.replaceAll(RegExp(r'''[.,;:!?،؛؟"']+$'''), '').trim());
    } catch (e) {
      if (!_disposed &&
          gen == _generation &&
          !(e is DioException && CancelToken.isCancel(e))) {
        onError(e is VoiceInputException
            ? e.message
            : 'تعذّر تحويل الصوت — تأكد من الإنترنت أو اكتب الأمر');
      }
    } finally {
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
