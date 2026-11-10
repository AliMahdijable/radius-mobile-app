// صفّارة «وضع الفنّي» (١٠ نوفمبر — المالك: «الصفاره… مابيها صوت»): كانت «صوت اللمس» للنظام (مطفأٌ بأغلب الهواتف) — الآن
// نغمةٌ بصوت الوسائط عبر قناة التطبيق، وتقول حين يكون الصوت على الصفر.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/tech_beep.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  Object? answer = true;

  setUp(() {
    calls.clear();
    answer = true;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(TechBeep.channel, (call) async {
      calls.add(call);
      return answer;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(TechBeep.channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('الهاتف (أندرويد وآيفون): النغمة من قناة التطبيق بمدّتها — وتعيد «مسموعة؟»', () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      calls.clear();
      answer = true;
      expect(await TechBeep.play(), isTrue);
      expect([calls.single.method, calls.single.arguments], ['beep', {'ms': 90}]);
      answer = false;
      expect(await TechBeep.play(ms: 120), isFalse, reason: 'صوت الوسائط صفر ⇒ يُقال للفنّي');
      expect(calls.last.arguments, {'ms': 120});
      answer = null;
      expect(await TechBeep.play(), isNull);
    }
    debugDefaultTargetPlatformOverride = null;
  });

  test('بلا القناة (نسخةٌ لم تُبنَ معها) لا يرمي — صوت اللمس كما كان', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(TechBeep.channel, null);
    final platform = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemSound.play') platform.add('${call.arguments}');
      return null;
    });
    addTearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    expect(await TechBeep.play(), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(platform, ['SystemSoundType.click']);
    debugDefaultTargetPlatformOverride = null;
  });

  test('الشاشة مضاءةٌ ما دامت الصفّارة شغّالة: للهاتف وحده، وبلا القناة لا يرمي', () async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      debugDefaultTargetPlatformOverride = platform;
      calls.clear();
      await TechBeep.keepAwake(true);
      await TechBeep.keepAwake(false);
      expect(calls.map((c) => [c.method, c.arguments]), [
        ['keepAwake', {'on': true}],
        ['keepAwake', {'on': false}],
      ]);
    }
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    calls.clear();
    await TechBeep.keepAwake(true);
    expect(calls, isEmpty, reason: 'الحاسبة لا تقفل شاشتها علينا');
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(TechBeep.channel, null);
    await TechBeep.keepAwake(true);
    debugDefaultTargetPlatformOverride = null;
  });

  test('الحاسبة: صوت تنبيه النظام (لا قناة)', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final platform = <String>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemSound.play') platform.add('${call.arguments}');
      return null;
    });
    addTearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    expect(await TechBeep.play(), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
    expect(platform, ['SystemSoundType.alert']);
    debugDefaultTargetPlatformOverride = null;
  });
}
