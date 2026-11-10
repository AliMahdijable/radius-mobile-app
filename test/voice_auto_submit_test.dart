import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/widgets/voice_search_button.dart';

const _channel = MethodChannel('plugin.csdcorp.com/speech_to_text');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late TextEditingController controller;
  late List<String> finalTexts;
  late List<bool> listening;
  var stops = 0;
  var cancels = 0;

  void native(String method, Object value) {
    binding.channelBuffers.push(
        _channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, value)),
        (_) {});
  }

  void words(String text, {bool finalResult = false}) {
    native(
        'textRecognition',
        jsonEncode({
          'alternates': [
            {'recognizedWords': text, 'confidence': 0.95}
          ],
          'resultType': finalResult ? 2 : 0,
        }));
  }

  setUp(() {
    controller = TextEditingController();
    finalTexts = [];
    listening = [];
    stops = 0;
    cancels = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel,
        (call) async {
      if (call.method == 'locales') return ['ar-IQ:العربية العراقية'];
      if (call.method == 'stop') {
        stops++;
        native('notifyStatus', 'notListening');
        native('notifyStatus', 'done');
      }
      if (call.method == 'cancel') cancels++;
      return true;
    });
  });
  tearDown(() {
    controller.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  Future<void> start(WidgetTester tester, {bool command = true}) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: VoiceSearchButton(
      controller: controller,
      onFinal: command ? finalTexts.add : null,
      onListening: listening.add,
    ))));
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    native('notifyStatus', 'listening');
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets(
      'iOS partial Arabic command completes after a pause without Enter',
      (tester) async {
    await start(tester);
    words('سدّد دين علي');
    await tester.pump(const Duration(milliseconds: 1500));
    expect(finalTexts, isEmpty);
    expect(stops, 0);
    words('سدّد دين علي ٢٥ ألف.');
    await tester.pump(const Duration(milliseconds: 1500));
    expect(stops, 0, reason: 'new words extend the pause');
    await tester.pump(const Duration(seconds: 1));
    expect(stops, 1);
    // iOS can omit isFinal; the package final timeout must deliver the last text.
    await tester.pump(const Duration(seconds: 2));
    expect(finalTexts, ['سدّد دين علي ٢٥ ألف']);
    expect(listening.last, isFalse);
    words('سدّد دين علي ٢٥ ألف.', finalResult: true);
    await tester.pump(const Duration(seconds: 3));
    expect(finalTexts, hasLength(1));
    await close(tester);
  });

  testWidgets('closing with a partial command cancels without delivering it',
      (tester) async {
    await start(tester);
    words('فعّل علي حسين');
    await tester.pump(const Duration(milliseconds: 500));
    await close(tester);
    expect(cancels, 1);
    expect(finalTexts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first words have time to arrive and silence submits nothing',
      (tester) async {
    await start(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(stops, 0);
    await tester.pump(const Duration(seconds: 6));
    expect(stops, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(finalTexts, isEmpty);
    await close(tester);
  });

  testWidgets(
      'reopened command receives errors after another search used speech',
      (tester) async {
    await start(tester, command: false);
    await close(tester);
    await start(tester);
    native('notifyError',
        jsonEncode({'errorMsg': 'error_network', 'permanent': true}));
    await tester.pump();
    expect(listening.last, isFalse);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    expect(finalTexts, isEmpty);
    await close(tester);
  });

  testWidgets('English command mode listens with the English locale and delivers alternates once',
      (tester) async {
    final localeIds = <String?>[];
    final heard = <List<String>>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel,
        (call) async {
      if (call.method == 'locales') {
        return ['ar-IQ:العربية العراقية', 'en_GB:English (UK)', 'en_US:English (US)'];
      }
      if (call.method == 'listen') {
        localeIds.add((call.arguments as Map)['localeId'] as String?);
      }
      if (call.method == 'stop') {
        stops++;
        native('notifyStatus', 'notListening');
        native('notifyStatus', 'done');
      }
      if (call.method == 'cancel') cancels++;
      return true;
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: VoiceSearchButton(
      controller: controller,
      language: 'en',
      onFinal: (_) => fail('onFinalAlts replaces onFinal'),
      onFinalAlts: heard.add,
      onListening: listening.add,
    ))));
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    expect(localeIds, ['en_US'], reason: 'en-US preferred over en-GB, whatever the tag separator');
    native('notifyStatus', 'listening');
    await tester.pump();
    native(
        'textRecognition',
        jsonEncode({
          'alternates': [
            {'recognizedWords': 'Activate Ali Hassan.', 'confidence': 0.7},
            {'recognizedWords': 'Activate Ali Hussein', 'confidence': 0.6},
            {'recognizedWords': 'Activate Ali Hassan', 'confidence': 0.5},
          ],
          'resultType': 2,
        }));
    await tester.pump(const Duration(milliseconds: 300));
    expect(heard, [
      ['Activate Ali Hassan', 'Activate Ali Hussein']
    ]);
    expect(controller.text, 'Activate Ali Hassan');
    await close(tester);
  });

  testWidgets('ordinary voice search retains its continuous dictation behavior',
      (tester) async {
    await start(tester, command: false);
    words('علي حسين.');
    await tester.pump(const Duration(seconds: 5));
    expect(controller.text, 'علي حسين');
    expect(stops, 0);
    await close(tester);
  });
}
