import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/services/expiry_push_service.dart';
import 'core/services/fcm_service.dart';
import 'core/utils/platform_utils.dart';

// سجلّ تشخيص الإقلاع — يُملأ خلال main() ويظهر في شاشة الخطأ القاتل فقط.
// لو الإقلاع ناجح نُمرّر التطبيق كما هو بلا أي تغيير في شجرة الـwidgets
// (لأن لفّ MaterialApp بـStack يكسر معالجة اللمس على iOS).
final List<String> _bootLog = <String>[];
String? _bootFatal;
StackTrace? _bootFatalStack;

void _log(String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  _bootLog.add('[$ts] $msg');
  debugPrint('🚀 [BOOT] $msg');
}

Future<void> _safeStep(String name, Future<void> Function() body,
    {Duration timeout = const Duration(seconds: 10)}) async {
  _log('$name …');
  try {
    await body().timeout(timeout);
    _log('$name ✓');
  } on TimeoutException {
    _log('$name ⏰ TIMEOUT (${timeout.inSeconds}s)');
  } catch (e) {
    _log('$name ✗ $e');
  }
}

Future<void> main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    _log('main start (${Platform.operatingSystem})');

    if (PlatformUtils.supportsPushNotifications) {
      // كل خطوة بـtimeout 10s — لو علقت أو كسرت، نكمل بدون تعطيل runApp.
      await _safeStep('FcmService.init', () => FcmService.init());
      await _safeStep(
          'ExpiryPushService.init', () => ExpiryPushService.init());
      await _safeStep('Workmanager.init',
          () => ExpiryPushService.ensureWorkmanagerInitialized());
    } else {
      _log('skip FCM/Workmanager (unsupported platform)');
    }

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ));
    }

    _log('runApp');
    // لو حصل fatal خلال main، اعرض شاشة الخطأ بدل MyApp (التطبيق ما يقدر
    // يكمل أصلاً). غير ذلك → MyApp مباشرة بلا أي Stack/GestureDetector
    // فوقه (الـStack يكسر اللمس على iOS).
    if (_bootFatal != null) {
      runApp(_BootErrorApp(error: _bootFatal!, stack: _bootFatalStack));
    } else {
      runApp(const ProviderScope(child: MyApp()));
    }
    _log('runApp returned');
  }, (error, stack) {
    _log('UNCAUGHT: $error');
    _bootFatal = '$error';
    _bootFatalStack = stack;
    debugPrint('🔥 [BOOT] UNCAUGHT: $error\n$stack');
  });
}

/// شاشة بديلة تُعرض **فقط** عند فشل قاتل أثناء main(). لا تُلفّ MaterialApp
/// الأساسي ولا تتدخّل في شجرة الـwidgets الاعتيادية — فما تأثير لها على
/// أداء/لمس التطبيق في المسار الناجح.
class _BootErrorApp extends StatelessWidget {
  final String error;
  final StackTrace? stack;
  const _BootErrorApp({required this.error, this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const Text('فشل تشغيل التطبيق',
                    style: TextStyle(
                        color: Colors.red,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.red.withValues(alpha: 0.15),
                  child: SelectableText(error,
                      style: const TextStyle(
                          color: Colors.red,
                          fontFamily: 'monospace',
                          fontSize: 12)),
                ),
                const SizedBox(height: 12),
                const Text('Boot log',
                    style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold)),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.white12,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _bootLog.join('\n'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'monospace',
                            fontSize: 11),
                      ),
                    ),
                  ),
                ),
                if (stack != null) ...[
                  const SizedBox(height: 8),
                  const Text('Stack',
                      style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold)),
                  Container(
                    height: 120,
                    padding: const EdgeInsets.all(8),
                    color: Colors.white10,
                    child: SingleChildScrollView(
                      child: SelectableText(
                        stack.toString(),
                        style: const TextStyle(
                            color: Colors.white70,
                            fontFamily: 'monospace',
                            fontSize: 10),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
