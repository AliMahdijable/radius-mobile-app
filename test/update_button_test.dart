// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/services/app_version.dart';
import 'package:rad_mysvcs/services/update_gate.dart';
import 'package:rad_mysvcs/widgets/update_glow.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'sim_el/sim_harness.dart';

/// «تحديث جديد» (٢٥ نوفمبر — المالك: «زر يمثل وجود تحديث للتطبيق… يظهر بشكل لامع» ثمّ «رمز احلى وماتاخذ مساحه… يطفو بشكل حركي»
/// و«لاتنسى لون الزر بالوضع الليلي»). العقد (`latest` في /api/app-gate لكلّ نظام، مستقلٌّ عن الإجبار)، متى يظهر ومتى يختفي، المهلة،
/// الدائرة الطافية بالنقر والوضعين و«تقليل الحركة»، ومكانها في الغلافين لا في الرؤوس.
class _FakeLauncher extends UrlLauncherPlatform with MockPlatformInterfaceMixin {
  final launched = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

const _store = 'https://play.google.com/store/apps/details?id=com.mysvcs.rad_mysvcs';
String get _p => AppPlatform.deviceLabel;

Map<String, dynamic> _gate({Map<String, Object?> latest = const {}, Map<String, Object?> min = const {}, bool enabled = false, Map<String, String>? store}) => {
      'success': true,
      'data': {
        'enabled': enabled,
        'min': min,
        'latest': latest,
        'store': store ?? {_p: _store},
        'message': 'حدّث',
      },
    };

void main() {
  setUp(() {
    UpdateGate.debugReset();
    UpdateFloatingBubble.debugPhase = null;
  });
  tearDown(() {
    UpdateGate.debugReset();
    AppVersion.debugSet();
  });

  group('متى يظهر ومتى يختفي', () {
    test('أقدم من آخر إصدارٍ لنظامه ⇒ يظهر برابط متجره؛ المساوي والأحدث وبلا رقمٍ معروف ⇒ لا', () {
      AppVersion.debugSet(version: '3.0.28', build: '196');
      UpdateGate.readLatest(_gate(latest: {_p: 197})['data'] as Map);
      expect(UpdateGate.available.value, const UpdateAvailable(storeUrl: _store, latestBuild: 197));
      AppVersion.debugSet(version: '3.0.29', build: '197');
      UpdateGate.readLatest(_gate(latest: {_p: 197})['data'] as Map);
      expect(UpdateGate.available.value, isNull, reason: 'حُدِّث ⇒ يختفي');
      AppVersion.debugSet(version: '3.0.30', build: '198');
      UpdateGate.readLatest(_gate(latest: {_p: 197})['data'] as Map);
      expect(UpdateGate.available.value, isNull);
      AppVersion.debugSet(version: '3.0.28', build: '');
      UpdateGate.readLatest(_gate(latest: {_p: 197})['data'] as Map);
      expect(UpdateGate.available.value, isNull, reason: 'رقم البناء غير معروف ⇒ لا تخمين');
    });

    test('بلا latest، أو لنظامٍ آخر وحده، أو معطوب ⇒ لا؛ وبلا رابط متجرٍ ⇒ الرابط الافتراضيّ', () {
      AppVersion.debugSet(version: '3.0.28', build: '196');
      final other = ['android', 'ios', 'windows', 'macos'].firstWhere((x) => x != _p);
      for (final latest in <Map<String, Object?>>[{}, {other: 999}, {_p: 'x'}, {_p: null}]) {
        UpdateGate.readLatest(_gate(latest: latest)['data'] as Map);
        expect(UpdateGate.available.value, isNull, reason: '$latest');
      }
      UpdateGate.readLatest({'latest': {_p: '197'}});
      expect(UpdateGate.available.value?.latestBuild, 197, reason: 'رقمٌ نصّيّ يُقبل');
      expect(UpdateGate.available.value?.storeUrl, startsWith('https://'), reason: 'الرابط الافتراضيّ لنظامه');
    });

    testWidgets('السؤال عند الإقلاع: latest يظهر والإجبار مطفأ؛ والمهلة ٦ ساعات (طلبٌ واحد)', (t) async {
      final server = await simSetUp();
      AppVersion.debugSet(version: '3.0.28', build: '196');
      server.reply('GET', '/api/app-gate', 200, _gate(latest: {_p: 197}));
      await t.runAsync(UpdateGate.check);
      expect(UpdateGate.available.value?.latestBuild, 197);
      expect(UpdateGate.required.value, isNull, reason: 'متاح لا مطلوب');
      await t.runAsync(UpdateGate.ensureFresh);
      await t.runAsync(UpdateGate.ensureFresh);
      expect(server.calls('GET', '/api/app-gate'), hasLength(1), reason: 'داخل المهلة لا سؤال');
      // نُشر 197 وحدّثه ⇒ يختفي عند السؤال التالي
      AppVersion.debugSet(version: '3.0.29', build: '197');
      await t.runAsync(UpdateGate.check);
      expect(UpdateGate.available.value, isNull);
      await simDrain(t);
    });

    testWidgets('الإجبار كما كان: min أكبر ⇒ شاشة «حدّث» (والدائرة متاحة أيضاً)؛ ردٌّ معطوب ⇒ لا شيء', (t) async {
      final server = await simSetUp();
      AppVersion.debugSet(version: '3.0.28', build: '196');
      server.reply('GET', '/api/app-gate', 200, _gate(enabled: true, min: {_p: 197}, latest: {_p: 197}));
      await t.runAsync(UpdateGate.check);
      expect(UpdateGate.required.value?.minBuild, 197);
      UpdateGate.debugReset();
      server.reply('GET', '/api/app-gate', 200, {'success': false});
      await t.runAsync(UpdateGate.check);
      expect([UpdateGate.required.value, UpdateGate.available.value], [null, null]);
      await simDrain(t);
    });
  });

  group('الدائرة الطافية', () {
    late _FakeLauncher fake;
    late UrlLauncherPlatform saved;
    setUp(() {
      saved = UrlLauncherPlatform.instance;
      fake = _FakeLauncher();
      UrlLauncherPlatform.instance = fake;
    });
    tearDown(() => UrlLauncherPlatform.instance = saved);

    Future<void> pump(WidgetTester t, {bool dark = false, bool still = false}) async {
      await pumpSim(t, SimVariant(390, dark: dark),
          home: (ctx) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(disableAnimations: still),
                child: const Scaffold(
                  body: Stack(children: [
                    Positioned(left: 16, bottom: 16, child: UpdateFloatingBubble()),
                  ]),
                ),
              ));
    }

    testWidgets('بلا نسخةٍ أحدث لا شيء؛ تظهر فتطفو، والنقر يفتح المتجر، وتختفي بعد التحديث', (t) async {
      await pump(t);
      expect(find.byKey(const ValueKey('update-glow')), findsNothing);
      UpdateGate.debugSetAvailable(const UpdateAvailable(storeUrl: _store, latestBuild: 197));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('update-glow')), findsOneWidget);
      expect(find.text('جديد'), findsOneWidget);
      // تطفو: موضعها يتغيّر مع الزمن
      final y0 = t.getCenter(find.byKey(const ValueKey('update-glow'))).dy;
      await t.pump(const Duration(milliseconds: 600));
      final y1 = t.getCenter(find.byKey(const ValueKey('update-glow'))).dy;
      expect((y0 - y1).abs(), greaterThan(1), reason: 'حركة الطفو');
      await t.tap(find.byKey(const ValueKey('update-glow')));
      await t.pump(const Duration(milliseconds: 100));
      expect(fake.launched, [_store]);
      UpdateGate.debugSetAvailable(null);
      // الخروج (تصغيرٌ ٣٢٠ م.ث) ثمّ يُزال القديم بالإطار التالي
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('update-float')), findsNothing, reason: 'الدائرة نفسها أُزيلت');
      expect(find.byKey(const ValueKey('update-glow')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('«تقليل الحركة» ⇒ ثابتة لامعة بلا طفو (ولا مؤقّت يبقى)؛ والوضع الليليّ بلا أخطاء', (t) async {
      UpdateGate.debugSetAvailable(const UpdateAvailable(storeUrl: _store, latestBuild: 197));
      await pump(t, still: true);
      await t.pump(const Duration(milliseconds: 400));
      final y0 = t.getCenter(find.byKey(const ValueKey('update-glow'))).dy;
      await t.pump(const Duration(milliseconds: 600));
      expect(t.getCenter(find.byKey(const ValueKey('update-glow'))).dy, y0);
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      // الوضع الليليّ: الغلاف يستقرّ أوّلاً ثمّ تظهر الدائرة (الطفو لا يستقرّ)
      UpdateGate.debugSetAvailable(null);
      await pump(t, dark: true);
      UpdateGate.debugSetAvailable(const UpdateAvailable(storeUrl: _store, latestBuild: 197));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('update-glow')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  });

  test('المكان: تطفو في الغلافين (الهاتف والحاسبة) ولا تأخذ مكاناً في رؤوس التبويبات', () {
    final shell = File('lib/screens/main_shell.dart').readAsStringSync();
    final desk = File('lib/screens/desktop/desktop_shell.dart').readAsStringSync();
    final top = File('lib/screens/top_actions.dart').readAsStringSync();
    expect(shell.contains('child: const UpdateFloatingBubble()'), isTrue);
    expect(desk.contains('child: UpdateFloatingBubble()'), isTrue);
    expect(top.contains('UpdateGlowButton(') || top.contains('UpdateFloatingBubble'), isFalse, reason: 'لا زرّ في الرأس (المالك: «ماتاخذ مساحه»)');
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('AppResumedSignal.tick.addListener(() => UpdateGate.ensureFresh().ignore());'), isTrue,
        reason: 'العودة للتطبيق تسأل بمهلتها — من الإقلاع لا من بناء الواجهة (لا طلب شبكةٍ في كلّ بناء)');
  });
}
