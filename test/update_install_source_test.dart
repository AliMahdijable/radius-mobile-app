// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/services/app_version.dart';
import 'package:rad_mysvcs/services/update_gate.dart';
import 'package:rad_mysvcs/widgets/update_glow.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'sim_el/sim_harness.dart';

/// رابط «حدّث» بمصدر التنصيب (٢٦ نوفمبر — المالك عبر 39: «من بلاي ⇒ بلاي مباشرة، غيره ⇒ الصفحة»). الخادم يرسل لأندرويد صفحة
/// /app/android (server/apkDist.js، app_gate.store.android = الصفحة)؛ التطبيق المنصَّب من Google Play يذهب للمتجر مباشرة، وغيره —
/// أجهزة الكاشير بلا خدمات كوكل، APK مباشر، متجرٌ آخر، أو لا يُعرف — للصفحة. شاشة «تحديثٌ مطلوب» ودائرة «تحديث جديد» من المصدر نفسه.
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

const _page = 'https://pro.mysvcs.net/app/android';
const _play = 'https://play.google.com/store/apps/details?id=com.mysvcs.rad_mysvcs';
const _fromPlay = 'com.android.vending';
const _apk = 'com.google.android.packageinstaller';

Map<String, Object> _force({Object? store = _page}) => {
      'success': false,
      'code': 'APP_FORCE_UPDATE',
      'message': 'حدّث',
      if (store != null) 'store_url': store,
      'min_build': 197,
    };

void main() {
  setUp(UpdateGate.debugReset);
  tearDown(() {
    UpdateGate.debugReset();
    AppVersion.debugSet();
    UpdateFloatingBubble.debugPhase = null;
  });

  group('القاعدة (storeUrlFor)', () {
    test('أندرويد من Google Play ⇒ بلاي مباشرة (لا صفحة)؛ ورابط بلاي من الخادم يُحترم', () {
      expect(UpdateGate.storeUrlFor('android', _page, installer: _fromPlay), _play);
      expect(UpdateGate.storeUrlFor('android', null, installer: _fromPlay), _play);
      expect(UpdateGate.storeUrlFor('android', '', installer: _fromPlay), _play);
      expect(UpdateGate.storeUrlFor('android', _page, installer: 'com.google.android.feedback'), _play, reason: 'مثبّت بلاي القديم');
      const hl = 'https://play.google.com/store/apps/details?id=com.mysvcs.rad_mysvcs&hl=ar';
      const market = 'market://details?id=com.mysvcs.rad_mysvcs';
      expect(UpdateGate.storeUrlFor('android', hl, installer: _fromPlay), hl);
      expect(UpdateGate.storeUrlFor('android', market, installer: _fromPlay), market);
    });

    test('أندرويد من غير بلاي أو لا يُعرف ⇒ رابط الخادم (الصفحة)؛ وبلا رابطٍ ⇒ الصفحة لا بلاي', () {
      const others = <String?>[
        null,
        '',
        _apk,
        'com.android.packageinstaller',
        'com.android.chrome',
        'com.huawei.appmarket',
        'woyou.market',
        'com.android.vending.x',
        'COM.ANDROID.VENDING',
      ];
      for (final i in others) {
        expect(UpdateGate.storeUrlFor('android', _page, installer: i), _page, reason: '$i');
        expect(UpdateGate.storeUrlFor('android', null, installer: i), _page, reason: '$i بلا رابط');
        expect(UpdateGate.storeUrlFor('android', '  ', installer: i), _page, reason: '$i رابطٌ فارغ');
      }
      expect(UpdateGate.storeUrlFor('android', ' $_page ', installer: null), _page, reason: 'مسافات حول الرابط');
      expect(UpdateGate.storeUrlFor('android', _play, installer: _apk), _play, reason: 'الخادم أعاد بلاي (store android=default) ⇒ قراره');
      expect(UpdateGate.directPageUrl, _page);
    });

    test('آيفون وويندوز والماك كما كانت — مصدر التنصيب لا يغيّرها', () {
      const apple = 'https://apps.apple.com/app/id6770731907';
      const ms = 'https://apps.microsoft.com/detail/9P56SZQKPLTC';
      for (final i in <String?>[null, _fromPlay, _apk]) {
        expect(UpdateGate.storeUrlFor('ios', 'https://apps.apple.com/iq/app/x', installer: i), 'https://apps.apple.com/iq/app/x');
        expect(UpdateGate.storeUrlFor('ios', null, installer: i), apple);
        expect(UpdateGate.storeUrlFor('macos', '', installer: i), apple);
        expect(UpdateGate.storeUrlFor('windows', null, installer: i), ms);
        expect(UpdateGate.storeUrlFor('windows', 'ms-windows-store://pdp/?productid=9P56SZQKPLTC', installer: i),
            'ms-windows-store://pdp/?productid=9P56SZQKPLTC');
      }
    });
  });

  group('المداخل الثلاثة تأخذ مصدر هذا الجهاز', () {
    test('الاختبار يجري بصفة أندرويد (FLUTTER_TEST)', () => expect(AppPlatform.deviceLabel, 'android'));

    test('ردّ 409 من أيّ طلب (fromResponse) — ومنه ردّ «ما يراه الموظّف»', () {
      AppVersion.debugSet(version: '3.0.28', build: '196', installer: _fromPlay);
      expect(UpdateGate.fromResponse(409, _force()), isTrue);
      expect(UpdateGate.required.value?.storeUrl, _play);
      AppVersion.debugSet(version: '3.0.28', build: '196', installer: _apk);
      UpdateGate.fromResponse(409, {..._force(), 'reason': 'employee_visibility'});
      expect(UpdateGate.required.value?.storeUrl, _page);
      AppVersion.debugSet(version: '3.0.28', build: '196');
      UpdateGate.fromResponse(409, _force(store: null));
      expect(UpdateGate.required.value?.storeUrl, _page, reason: 'بلا رابطٍ وبلا مصدرٍ معروف ⇒ الصفحة');
    });

    test('«تحديث جديد» (readLatest)', () {
      const d = {
        'latest': {'android': 197},
        'store': {'android': _page},
      };
      AppVersion.debugSet(version: '3.0.28', build: '196', installer: _fromPlay);
      UpdateGate.readLatest(d);
      expect(UpdateGate.available.value, const UpdateAvailable(storeUrl: _play, latestBuild: 197));
      AppVersion.debugSet(version: '3.0.28', build: '196', installer: _apk);
      UpdateGate.readLatest(d);
      expect(UpdateGate.available.value, const UpdateAvailable(storeUrl: _page, latestBuild: 197));
    });

    testWidgets('سؤال الإقلاع (check): الإجبار والدائرة معاً', (t) async {
      final server = await simSetUp();
      server.reply('GET', '/api/app-gate', 200, {
        'success': true,
        'data': {
          'enabled': true,
          'min': {'android': 197},
          'latest': {'android': 197},
          'store': {'android': _page},
          'message': 'حدّث',
        },
      });
      AppVersion.debugSet(version: '3.0.28', build: '196', installer: _fromPlay);
      await t.runAsync(UpdateGate.check);
      expect([UpdateGate.required.value?.storeUrl, UpdateGate.available.value?.storeUrl], [_play, _play]);
      UpdateGate.debugReset();
      AppVersion.debugSet(version: '3.0.28', build: '196');
      await t.runAsync(UpdateGate.check);
      expect([UpdateGate.required.value?.storeUrl, UpdateGate.available.value?.storeUrl], [_page, _page]);
      await simDrain(t);
    });
  });

  group('مصدر التنصيب يُقرأ مع النسخة قبل أوّل إطار', () {
    test('AppVersion.load يقرأ installerStore (وبلا مثبِّت ⇒ null)', () async {
      PackageInfo.setMockInitialValues(
          appName: 'MyServices Pro',
          packageName: 'com.mysvcs.rad_mysvcs',
          version: '3.0.29',
          buildNumber: '197',
          buildSignature: '',
          installerStore: _fromPlay);
      await AppVersion.load();
      expect([AppVersion.buildNumber, AppVersion.installerStore], ['197', _fromPlay]);
      PackageInfo.setMockInitialValues(
          appName: 'MyServices Pro', packageName: 'com.mysvcs.rad_mysvcs', version: '3.0.29', buildNumber: '197', buildSignature: '');
      await AppVersion.load();
      expect(AppVersion.installerStore, isNull, reason: 'APK بـadb أو لا يُعرف');
    });

    test('main.dart ينتظر AppVersion.load قبل runApp', () {
      final src = File('lib/main.dart').readAsStringSync();
      final load = src.indexOf('AppVersion.load()');
      expect(load, greaterThan(0));
      expect(load, lessThan(src.indexOf('runApp(')));
    });
  });

  group('الزرّان يفتحان الرابط المختار', () {
    late _FakeLauncher fake;
    late UrlLauncherPlatform saved;
    setUp(() {
      saved = UrlLauncherPlatform.instance;
      fake = _FakeLauncher();
      UrlLauncherPlatform.instance = fake;
    });
    tearDown(() => UrlLauncherPlatform.instance = saved);

    for (final (installer, want) in const [(_fromPlay, _play), (_apk, _page), (null, _page)]) {
      testWidgets('شاشة «تحديثٌ مطلوب» — ${installer ?? 'لا يُعرف'} ⇒ $want', (t) async {
        AppVersion.debugSet(version: '3.0.28', build: '196', installer: installer);
        UpdateGate.fromResponse(409, _force());
        await pumpSim(t, const SimVariant(390, dark: false), home: (_) => const UpdateGateOverlay(child: Scaffold(body: SizedBox())));
        await t.pumpAndSettle();
        await t.tap(find.text('حدّث الآن'));
        await t.pump(const Duration(milliseconds: 100));
        expect(fake.launched, [want]);
      });

      testWidgets('دائرة «تحديث جديد» — ${installer ?? 'لا يُعرف'} ⇒ $want', (t) async {
        AppVersion.debugSet(version: '3.0.28', build: '196', installer: installer);
        UpdateGate.readLatest({
          'latest': {'android': 197},
          'store': {'android': _page},
        });
        UpdateFloatingBubble.debugPhase = 0.25;
        await pumpSim(t, const SimVariant(390, dark: false),
            home: (_) => const Scaffold(body: Stack(children: [Positioned(left: 16, bottom: 16, child: UpdateFloatingBubble())])));
        await t.pump(const Duration(milliseconds: 400));
        await t.tap(find.byKey(const ValueKey('update-glow')));
        await t.pump(const Duration(milliseconds: 100));
        expect(fake.launched, [want]);
      });
    }
  });
}
