import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/login_screen.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/services/device_warm_service.dart';

import 'visual_perm/visual_perm_harness.dart';

/// مراجعة الإصدار 179 (للإصدار 180): فحص الأجهزة الخلفيّ ملكٌ لغلافه.
///
/// استبدال الغلاف بغلافٍ جديد (البصمة، تبديل الشركة، المدير الفرعيّ، صفحة الموظّف — كلّها pushAndRemoveUntil) يُنهي القديم
/// **بعد** أن يبدأ الجديد: كان `stop()` القديم يُطفئ فحص الجديد بقيّة الجلسة (`start()` عاد مبكّراً وهو يعمل) — وسرعة قسم
/// الأجهزة أهمّ معيارٍ عند المالك. الآن `start(owner)`/`stop(owner)`: يعمل ما دام له مالك، وإيقاف مالكٍ لا يمسّ غيره.
void main() {
  setUpAll(visualSetUpAll);
  tearDown(DeviceWarmService.debugReset);

  test('الملكيّة: الجديد يبدأ ثمّ القديم يتوقّف ⇒ يبقى يعمل؛ إيقافٌ مكرّر أو من غير مالك لا يمسّه؛ آخر مالكٍ يوقفه', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    DeviceWarmService.debugOnStep = () {};
    final oldShell = Object();
    final newShell = Object();
    DeviceWarmService.start(oldShell);
    expect(DeviceWarmService.debugRunning, isTrue);
    DeviceWarmService.start(newShell); // الغلاف الجديد بعد أوّل إطار
    DeviceWarmService.stop(oldShell); // ثمّ يُنهى القديم بعد انتقاله
    expect(DeviceWarmService.debugRunning, isTrue, reason: 'الغلاف القديم أطفأ فحص الجديد');
    DeviceWarmService.stop(oldShell);
    DeviceWarmService.stop(Object());
    expect(DeviceWarmService.debugRunning, isTrue, reason: 'إيقافٌ من غير مالكٍ قائم لا يمسّه');
    DeviceWarmService.stop(newShell);
    expect(DeviceWarmService.debugRunning, isFalse, reason: 'لا مالك ⇒ يتوقّف (الخروج من الحساب)');
    // والترتيب المعكوس (القديم يتوقّف قبل أن يبدأ الجديد) كما كان
    DeviceWarmService.start(oldShell);
    DeviceWarmService.stop(oldShell);
    expect(DeviceWarmService.debugRunning, isFalse);
    DeviceWarmService.start(newShell);
    expect(DeviceWarmService.debugRunning, isTrue);
  });

  testWidgets('البصمة فوق غلافٍ قائم ⇒ الغلاف الجديد يبقى بفحصه الخلفيّ بعد إنهاء القديم (موجاتٌ تتوالى)، والخروج يوقفه',
      (t) async {
    await visualSetUp(s1bSasOwner);
    var steps = 0;
    DeviceWarmService.debugOnStep = () => steps++;
    // البصمة تنجح (منصّة local_auth الافتراضيّة على قناتها)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/local_auth'), (call) async => call.method == 'authenticate' ? true : false);
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/local_auth'), null));
    final nav = GlobalKey<NavigatorState>();
    try {
      await pumpVisual(t, const VisualDevice('', Size(390, 900), 1), navigatorKey: nav, home: (_) => const MainShell());
      await settle(t, seconds: 2);
      expect(DeviceWarmService.debugRunning, isTrue, reason: 'الغلاف الأوّل بدأ الفحص');
      final first = t.state(find.byType(MainShell));

      // «تبديل الحساب» ⇒ شاشة الدخول فوق الغلاف ⇒ البصمة ⇒ غلافٌ جديد يزيل ما تحته
      unawaited(nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const LoginScreen(fromCompanies: true))));
      await settle(t, seconds: 2);
      final finger = find.byIcon(Icons.fingerprint_rounded);
      await t.ensureVisible(finger);
      await t.pump();
      await t.tap(finger);
      await settle(t, seconds: 3);
      expect(find.byType(MainShell), findsOneWidget);
      expect(identical(t.state(find.byType(MainShell)), first), isFalse, reason: 'غلافٌ جديد');
      expect(first.mounted, isFalse, reason: 'الغلاف القديم أُنهي');
      expect(DeviceWarmService.debugRunning, isTrue, reason: 'إنهاء الغلاف القديم أطفأ فحص الجديد بقيّة الجلسة');

      // الموجات تتوالى (كلّ ٣٠ث خطوة) — لا مؤقّتٌ ملغى
      steps = 0;
      await t.pump(const Duration(seconds: 31));
      await t.pump(const Duration(seconds: 31));
      expect(steps, greaterThanOrEqualTo(2), reason: 'الفحص الخلفيّ متوقّف بعد البصمة');

      // الخروج من الحساب: لا غلاف ⇒ يتوقّف، ولا خطوة بعده
      unawaited(nav.currentState!
          .pushAndRemoveUntil(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('login'))), (_) => false));
      await settle(t, seconds: 2);
      expect(find.byType(MainShell), findsNothing);
      expect(DeviceWarmService.debugRunning, isFalse, reason: 'لا غلاف ⇒ لا فحص');
      steps = 0;
      await t.pump(const Duration(seconds: 31));
      expect(steps, 0);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 25));
      await visualTearDown();
    }
  });
}
