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

// سجلّ تشخيص الإقلاع — يُملأ خلال main() ويُعرض على شاشة الـoverlay لو
// التطبيق ظهر بدون UI ("شاشة بيضاء") — حتى نشخّص بدون Mac/Xcode على iOS.
final List<String> _bootLog = <String>[];
String? _bootFatal;

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
    _log('main start (platform=${Platform.operatingSystem})');

    if (PlatformUtils.supportsPushNotifications) {
      // كل خطوة معزولة بـtimeout و try/catch — لو علقت أو كسرت، نكمل.
      // هذا يضمن أن runApp يُستدعى دائماً (لا شاشة بيضاء بسبب init).
      await _safeStep('FcmService.init', () => FcmService.init());
      await _safeStep('ExpiryPushService.init',
          () => ExpiryPushService.init());
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
    runApp(const ProviderScope(child: _RootGuard()));
    _log('runApp returned');
  }, (error, stack) {
    _log('UNCAUGHT: $error');
    _bootFatal = '$error\n\n$stack';
    debugPrint('🔥 [BOOT] UNCAUGHT: $error\n$stack');
  });
}

/// يلفّ التطبيق ويفتح overlay تشخيصياً (5 ضغطات على الزاوية اليمنى العلوية)
/// — مفيد جداً على iOS بدون Mac: لو الشاشة بيضاء، اضغط الزاوية اليمنى
/// العلوية 5 مرات بسرعة وراح يظهر لوغ الإقلاع وأي أخطاء fatal.
class _RootGuard extends StatefulWidget {
  const _RootGuard();
  @override
  State<_RootGuard> createState() => _RootGuardState();
}

class _RootGuardState extends State<_RootGuard> {
  int _taps = 0;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);
  bool _showDiag = false;

  @override
  void initState() {
    super.initState();
    // لو حصل fatal خلال main، اعرض overlay تلقائياً.
    if (_bootFatal != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showDiag = true);
      });
    }
  }

  void _onCornerTap() {
    final now = DateTime.now();
    if (now.difference(_lastTap).inSeconds > 2) _taps = 0;
    _lastTap = now;
    _taps++;
    if (_taps >= 5) {
      setState(() {
        _showDiag = !_showDiag;
        _taps = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const MyApp(),
        // زر شفّاف بالزاوية اليمنى العلوية — 5 ضغطات يفتح اللوغ.
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _onCornerTap,
            child: const SizedBox(width: 60, height: 60),
          ),
        ),
        if (_showDiag) _DiagOverlay(onClose: () => setState(() => _showDiag = false)),
      ],
    );
  }
}

class _DiagOverlay extends StatelessWidget {
  final VoidCallback onClose;
  const _DiagOverlay({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Text('Boot Diagnostics',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: onClose,
                ),
              ]),
              if (_bootFatal != null) ...[
                const Text('FATAL',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  color: Colors.red.withValues(alpha: 0.2),
                  child: Text(_bootFatal!,
                      style: const TextStyle(color: Colors.red, fontSize: 11, fontFamily: 'monospace')),
                ),
              ],
              const Text('Boot log',
                  style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.white.withValues(alpha: 0.05),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _bootLog.join('\n'),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
