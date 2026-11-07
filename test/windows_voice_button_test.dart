import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rad_mysvcs/core/widgets/windows_voice_button.dart';
import 'package:rad_mysvcs/services/ai_consent.dart';

class PermissionRecorder extends RecordPlatform {
  int creates = 0;
  @override
  Future<void> create(String recorderId) async {
    creates++;
  }

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      false;
  @override
  Future<String?> stop(String recorderId) async => null;
  @override
  Future<void> dispose(String recorderId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late RecordPlatform original;
  late PermissionRecorder recorder;
  setUp(() {
    original = RecordPlatform.instance;
    recorder = PermissionRecorder();
    RecordPlatform.instance = recorder;
    AiConsent.debugActor = 'voice-owner';
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() {
    RecordPlatform.instance = original;
    AiConsent.debugReset();
  });

  Future<void> mount(WidgetTester tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: WindowsVoiceButton(
      controller: controller,
      onFinal: (_) => fail('no audio should be sent'),
    ))));
  }

  testWidgets('consent resolving in background cannot open the microphone',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    expect(find.text('ابدأ'), findsOneWidget);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.tap(find.text('ابدأ'));
    await tester.pumpAndSettle();
    expect(recorder.creates, 0);
    // Returning to the app also requires a fresh user tap.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(recorder.creates, 0);
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    if (find.text('ابدأ').evaluate().isNotEmpty) {
      await tester.tap(find.text('ابدأ'));
      await tester.pumpAndSettle();
    }
    expect(recorder.creates, 1);
    expect(
        find.text('فعّل صلاحية الميكروفون من إعدادات ويندوز'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('changing the person while consent is open cannot record',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    AiConsent.debugActor = 'another-owner';
    await tester.tap(find.text('ابدأ'));
    await tester.pumpAndSettle();
    expect(recorder.creates, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('declining consent never creates the recorder', (tester) async {
    await mount(tester);
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ليس الآن'));
    await tester.pumpAndSettle();
    expect(recorder.creates, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
