import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rad_mysvcs/api/balance_requests_api.dart';
import 'package:rad_mysvcs/api/renew_requests_api.dart';
import 'package:rad_mysvcs/screens/balance_requests/sub_balance_request_screen.dart';
import 'package:rad_mysvcs/screens/renew/pay_qr_field.dart';
import 'package:rad_mysvcs/screens/renew/renew_settings_card.dart';
import 'package:rad_mysvcs/services/pay_qr.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/widgets/pay_qr_tile.dart';

import 'sim_el/sim_harness.dart';

/// «باركود الدفع» بتطبيق المدير (٢٥ نوفمبر — المالك: «مكاتب الصيرفة ترفض الرقم وتطلب الباركود حصرا خاصة زين كاش… وتظهر بصف الرقم او
/// وحدها حسب اختيارنا» للمشترك بطلب التجديد وللمدير الفرعيّ بطلب الرصيد). العقد كما يكتبه الخادم (server/portalPayQr.js)، تجهيز الصورة
/// (خلفيّةٌ بيضاء، PNG ثمّ JPEG، الحدّ)، بطاقة الإعداد (الرفع، الظهور، الإزالة، وبلا المفتاح كما كانت)، و«ادفع لمديرك» (الرقم والباركود،
/// الباركود وحده، والصورة المكسورة ⇒ الرقم احتياطاً).
const _qr1 = 'https://pro.mysvcs.net/api/portal/pay-qr/41-0123456789ab.png';
const _qr2 = 'https://pro.mysvcs.net/api/portal/pay-qr/42-abcdef012345.jpg';
const _v = SimVariant(390, dark: false);

Uint8List _png(int w, int h, {bool transparent = false, bool noise = false}) {
  final im = img.Image(width: w, height: h, numChannels: transparent ? 4 : 3);
  if (transparent) img.fill(im, color: img.ColorRgba8(0, 0, 0, 0)); else img.fill(im, color: img.ColorRgb8(255, 255, 255));
  var seed = 7;
  for (var y = 0; y < h; y += 1) {
    for (var x = 0; x < w; x += 1) {
      if (noise) {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        // صورةٌ «مصوَّرة»: تدرّجٌ وضجيجٌ (٠–٦٣) — PNG ≈ ٣٠٠ ك.ب وJPEG ٩٢ ≈ ٢٠٠ ك.ب عند ٤٠٠×٤٠٠ (مقيس)
        final v = ((((x + y) ~/ 4) & 0xff) + (seed >> 16) % 64).clamp(0, 255);
        im.setPixelRgba(x, y, v, v, (v * 3) & 0xff, 255);
      } else if (((x ~/ 8) + (y ~/ 8)) % 3 == 0 && x > w ~/ 6 && x < w * 5 ~/ 6 && y > h ~/ 6 && y < h * 5 ~/ 6) {
        im.setPixelRgba(x, y, 0, 0, 0, 255);
      }
    }
  }
  return Uint8List.fromList(img.encodePng(im));
}

Map<String, dynamic> _settings({bool qr = true, String? zq, String? zs, String? mq, String? ms}) => {
      'success': true,
      'available': true,
      'can_use': true,
      'can_edit': true,
      'enabled': true,
      'zaincash': '07801234567',
      'master': null,
      'note': null,
      if (qr) ...{'qr_available': true, 'zaincash_qr': zq, 'zaincash_show': zs, 'master_qr': mq, 'master_show': ms} else 'qr_available': false,
    };

void main() {
  group('العقد والتجهيز', () {
    test('عنوان الباركود من خادمنا وحده، و«qr» = الباركود وحده (وغيرها مع الرقم)', () {
      expect(PayQr.of(_qr1, 'qr'), const PayQr(_qr1, qrOnly: true));
      expect(PayQr.of(_qr2, 'both'), const PayQr(_qr2));
      expect(PayQr.of(_qr2, 'zzz')!.qrOnly, isFalse);
      for (final bad in [
        'https://evil.example/api/portal/pay-qr/41-0123456789ab.png',
        'http://pro.mysvcs.net/api/portal/pay-qr/41-0123456789ab.png',
        'https://pro.mysvcs.net/api/portal/pkg-img/41-0123456789ab.png',
        'https://pro.mysvcs.net/api/portal/pay-qr/41-0123.png',
        'https://pro.mysvcs.net.evil.io/api/portal/pay-qr/41-0123456789ab.png',
        '',
        null,
        7,
      ]) {
        expect(PayQr.of(bad, 'qr'), isNull, reason: '$bad');
      }
    });

    test('الإعداد وطرق الدفع للفرعيّ يقرآن حقول الباركود (وغيابها كما كان)', () {
      final a = RenewAccess.fromJson(_settings(zq: _qr1, zs: 'qr', mq: _qr2, ms: 'both'));
      expect([a.qrAvailable, a.zaincashQr, a.zaincashQrOnly, a.masterQr, a.masterQrOnly], [true, _qr1, true, _qr2, false]);
      final old = RenewAccess.fromJson({'available': true, 'zaincash': '0780'});
      expect([old.qrAvailable, old.zaincashQr, old.masterQr], [false, null, null]);
      final p = BalanceReqPay.fromJson({'zaincash': null, 'master': null, 'note': null, 'zaincash_qr': _qr1, 'zaincash_show': 'qr'});
      expect([p.any, p.zaincashQr, p.masterQr], [true, const PayQr(_qr1, qrOnly: true), null], reason: 'الباركود وحده يكفي للقسم');
      expect(BalanceReqPay.fromJson({'zaincash': null, 'master': null, 'zaincash_qr': 'https://x.io/a.png'}).any, isFalse);
    });

    test('التجهيز: الشفّاف على خلفيّةٍ بيضاء PNG، والكبير يصغر ≤ ١٦٠٠، والضجيج ⇒ JPEG تحت الحدّ، والتالف ⇒ decode', () {
      final t = preparePayQr(_png(300, 300, transparent: true));
      expect(t.mime, 'image/png');
      final back = img.decodePng(t.bytes)!;
      expect(back.numChannels, 3, reason: 'بلا قناة شفافيّة');
      final corner = back.getPixel(0, 0);
      expect([corner.r, corner.g, corner.b], [255, 255, 255], reason: 'الشفّاف صار أبيض — الباركود يُقرأ بالوضع الداكن');
      final mid = back.getPixel(150, 150);
      expect(mid.r < 60 || back.getPixel(150 + 8, 150).r < 60, isTrue, reason: 'المربّعات السوداء باقية');
      final big = preparePayQr(_png(2000, 3200));
      expect([big.width <= payQrMaxSide && big.height <= payQrMaxSide, big.height], [true, 1600]);
      expect(big.length <= payQrMaxBytes, isTrue);
      // صورةٌ «مصوَّرة» (ضجيج) PNG أكبر من الحدّ ⇒ JPEG بجودةٍ عالية تحته
      final noisy = preparePayQr(_png(400, 400, noise: true), maxBytes: 250 * 1024);
      expect(noisy.mime, 'image/jpeg', reason: 'PNG الضجيج أكبر من الحدّ ⇒ JPEG');
      expect(noisy.length <= 250 * 1024, isTrue);
      expect(noisy.dataUrl.startsWith('data:image/jpeg;base64,'), isTrue);
      expect(() => preparePayQr(Uint8List.fromList(utf8.encode('not an image'))), throwsA(isA<PayQrError>().having((e) => e.reason, 'reason', 'decode')));
      expect(() => preparePayQr(_png(1500, 1500, noise: true), maxBytes: 2000), throwsA(isA<PayQrError>().having((e) => e.reason, 'reason', 'too-big')));
    });

    test('ما يُرسل بالحفظ: الجديدة data URL، الإزالة null، والظهور لمن بقيت له صورة — ولا شيء بلا تغيير', () {
      final img1 = PayQrImage(Uint8List.fromList([1, 2, 3]), 'image/png', 10, 10);
      const saved = {'zaincash': PayQrDraft(url: _qr1, qrOnly: true), 'master': PayQrDraft.empty};
      expect(payQrPatch(saved, saved), isEmpty);
      expect(payQrPatch({'zaincash': saved['zaincash']!.withQrOnly(false), 'master': PayQrDraft.empty}, saved), {'zaincash_show': 'both'});
      expect(payQrPatch({'zaincash': PayQrDraft.empty, 'master': PayQrDraft.empty}, saved), {'zaincash_qr': null});
      expect(payQrPatch({'zaincash': saved['zaincash']!, 'master': PayQrDraft.empty.withImage(img1)}, saved),
          {'master_qr': 'data:image/png;base64,AQID', 'master_show': 'both'});
      expect(payQrPatch({'zaincash': saved['zaincash']!.withImage(img1), 'master': PayQrDraft.empty}, saved),
          {'zaincash_qr': 'data:image/png;base64,AQID', 'zaincash_show': 'qr'}, reason: 'استبدال الصورة يُبقي «وحده»');
    });
  });

  group('بطاقة الإعداد', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      RenewRequestsState.reset();
      server = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@m'});
      PayQrTile.debugImage = (url) => Container(key: ValueKey('img:$url'), width: 60, height: 60, color: Colors.black12);
    });
    tearDown(() => PayQrTile.debugImage = null);

    final picked = PayQrImage(Uint8List.fromList(img.encodePng(img.Image(width: 12, height: 12))), 'image/png', 12, 12);
    Future<PayQrImage?> picker() async => picked;

    testWidgets('بلا المفتاح: لا رفع ولا سطر، والحفظ كما كان (الأرقام والملاحظة وحدها)', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings(qr: false));
      server.reply('PUT', '/api/v2/portal/renew-settings', 200, _settings(qr: false));
      await pumpSim(t, _v, home: (_) => Scaffold(body: SingleChildScrollView(child: RenewSettingsCard(qrPicker: picker))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-qr-add-zaincash')), findsNothing);
      expect(find.byKey(const ValueKey('pay-qr-where')), findsNothing);
      await t.enterText(find.byKey(const ValueKey('renew-note')), 'باسم علي');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('renew-settings-save')));
      await t.pumpAndSettle();
      expect(server.bodies('PUT', '/api/v2/portal/renew-settings').single, {'zaincash': '07801234567', 'master': '', 'note': 'باسم علي'});
      await simDrain(t);
    });

    testWidgets('الرفع ⇒ معاينة «جديدة» ⇒ «الباركود وحده» ⇒ الحفظ يرسل الصورة وظهورها مع الأرقام', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings());
      server.reply('PUT', '/api/v2/portal/renew-settings', 200, _settings(zq: _qr1, zs: 'qr'));
      await pumpSim(t, _v, home: (_) => Scaffold(body: SingleChildScrollView(child: RenewSettingsCard(qrPicker: picker))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-qr-where')), findsOneWidget);
      expect(find.byKey(const ValueKey('renew-settings-save')).hitTestable(), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('renew-settings-save'))).onPressed, isNull, reason: 'لا تغيير بعد');
      await t.tap(find.byKey(const ValueKey('pay-qr-add-zaincash')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-qr-preview-zaincash')), findsOneWidget);
      expect(find.textContaining('جديدة'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('pay-qr-show-zaincash-qr')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('renew-settings-save')));
      await t.pumpAndSettle();
      final body = server.bodies('PUT', '/api/v2/portal/renew-settings').single;
      expect(body['zaincash_qr'], picked.dataUrl);
      expect(body['zaincash_show'], 'qr');
      expect([body['zaincash'], body.containsKey('master_qr'), body.containsKey('master_show')], ['07801234567', false, false]);
      // بعد الحفظ: صورة الخادم المحفوظة، ولا «جديدة»، والحفظ معطّل
      expect(find.byKey(const ValueKey('img:$_qr1')), findsOneWidget);
      expect(find.textContaining('جديدة'), findsNothing);
      expect(t.widget<FilledButton>(find.byKey(const ValueKey('renew-settings-save'))).onPressed, isNull);
      await simDrain(t);
    });

    testWidgets('المحفوظ: «مع الرقم» يرسل الظهور وحده؛ «إزالة» يرسل null بلا ظهور ويرجع زرّ الرفع', (t) async {
      server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings(zq: _qr1, zs: 'qr'));
      server.reply('PUT', '/api/v2/portal/renew-settings', 200, _settings(zq: _qr1, zs: 'both'));
      await pumpSim(t, _v, home: (_) => Scaffold(body: SingleChildScrollView(child: RenewSettingsCard(qrPicker: picker))));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('img:$_qr1')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('pay-qr-show-zaincash-both')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('renew-settings-save')));
      await t.pumpAndSettle();
      final b1 = server.bodies('PUT', '/api/v2/portal/renew-settings').last;
      expect([b1['zaincash_show'], b1.containsKey('zaincash_qr')], ['both', false]);
      server.reply('PUT', '/api/v2/portal/renew-settings', 200, _settings());
      await t.tap(find.byKey(const ValueKey('pay-qr-remove-zaincash')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-qr-add-zaincash')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('renew-settings-save')));
      await t.pumpAndSettle();
      final b2 = server.bodies('PUT', '/api/v2/portal/renew-settings').last;
      expect(b2.containsKey('zaincash_qr') && b2['zaincash_qr'] == null, isTrue, reason: 'null صريح = إزالة');
      expect(b2.containsKey('zaincash_show'), isFalse);
      await simDrain(t);
    });

    for (final v in simVariants) {
      testWidgets('بلا فيضٍ ولا أخطاء @${v.tag}: البطاقة بصورتين وظهورين', (t) async {
        server.reply('GET', '/api/v2/portal/renew-settings', 200, _settings(zq: _qr1, zs: 'qr', mq: _qr2, ms: 'both'));
        await pumpSim(t, v, home: (_) => Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: RenewSettingsCard(qrPicker: picker))));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('pay-qr-field-zaincash')), findsOneWidget);
        expect(find.byKey(const ValueKey('pay-qr-field-master')), findsOneWidget);
        expect(t.takeException(), isNull);
        await simDrain(t);
      });
    }
  });

  group('«ادفع لمديرك»', () {
    setUpAll(simSetUpAll);
    tearDown(() {
      PermissionsService.debugReset();
      BalanceReqState.reset();
      PayQrTile.debugImage = null;
    });
    Map<String, dynamic> me(Map<String, Object?> pay) => {
          'enabled': true,
          'can_request': true,
          'parent': {'page': '2', 'username': 'abu.ali', 'network': 'شبكة النور', 'phone': '07801111111', 'whatsapp': '9647801111111'},
          'pay': pay,
          'pending': 0,
          'last_deposit': null,
          'requests': <Object>[],
        };
    Future<void> open(WidgetTester t, Map<String, Object?> pay, {SimVariant v = _v}) async {
      final s = await simSetUp(secure: {'auth.admin_id': '2251', 'auth.admin_username': 'ali.hasan'});
      PermissionsService.debugSet(isEmployee: false);
      s.reply('GET', '/api/v2/balance-requests/me', 200, {'success': true, 'data': me(pay)});
      s.reply('GET', '/api/v2/admin-widgets', 200, {'success': true, 'balance': 85000, 'points': 0});
      await pumpSim(t, v, home: (_) => SubBalanceRequestScreen(pickImage: ({required bool camera}) async => null));
      await t.pumpAndSettle();
    }

    testWidgets('الرقم والباركود معاً، والماستر بلا باركود ⇒ رقمه وحده؛ النقر يفتح الباركود بملء الشاشة', (t) async {
      PayQrTile.debugImage = (url) => Container(key: ValueKey('img:$url'), width: 120, height: 120, color: Colors.black12);
      await open(t, {'zaincash': '07801234567', 'master': '5222333344445555', 'note': null, 'zaincash_qr': _qr1, 'zaincash_show': 'both'});
      expect(find.byKey(const ValueKey('balreq-pay-zaincash')), findsOneWidget);
      expect(find.byKey(const ValueKey('balreq-pay-zaincash-qr')), findsOneWidget);
      expect(find.byKey(const ValueKey('balreq-pay-master')), findsOneWidget);
      expect(find.byKey(const ValueKey('balreq-pay-master-qr')), findsNothing);
      await t.ensureVisible(find.byKey(const ValueKey('balreq-pay-zaincash-qr')));
      await t.tap(find.byKey(const ValueKey('balreq-pay-zaincash-qr')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-qr-viewer')), findsOneWidget);
      expect(find.text('باركود زين كاش — باسم شبكة النور'), findsOneWidget);
      await t.tap(find.byType(CloseButton));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pay-qr-viewer')), findsNothing);
      await simDrain(t);
    });

    testWidgets('«الباركود وحده»: الرقم يغيب والباركود باسم المدير؛ وبلا أيّ رقم يظهر القسم بالباركود', (t) async {
      PayQrTile.debugImage = (url) => Container(key: ValueKey('img:$url'), width: 120, height: 120, color: Colors.black12);
      await open(t, {'zaincash': '07801234567', 'master': null, 'note': null, 'zaincash_qr': _qr1, 'zaincash_show': 'qr', 'master_qr': _qr2, 'master_show': 'qr'});
      expect(find.byKey(const ValueKey('balreq-pay-zaincash')), findsNothing);
      expect(find.byKey(const ValueKey('balreq-pay-zaincash-qr')), findsOneWidget);
      expect(find.text('زين كاش — باسم شبكة النور'), findsOneWidget);
      expect(find.byKey(const ValueKey('balreq-pay-master-qr')), findsOneWidget, reason: 'الماستر بالباركود وحده بلا رقم');
      await simDrain(t);
    });

    testWidgets('تعذّر تحميل الباركود ⇒ الرقم احتياطاً، وبلا رقمٍ رسالةٌ لا فراغ', (t) async {
      // بلا debugImage: الشبكة بالاختبار ترفض ⇒ errorBuilder ⇒ onBroken
      await open(t, {'zaincash': '07801234567', 'master': null, 'note': null, 'zaincash_qr': _qr1, 'zaincash_show': 'qr', 'master_qr': _qr2, 'master_show': 'qr'});
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('balreq-pay-zaincash')), findsOneWidget, reason: 'الرقم رجع');
      expect(find.byKey(const ValueKey('balreq-pay-zaincash-qr')), findsNothing);
      expect(find.text('تعذّر تحميل باركود ماستر كارد — اسأل مديرك عن الرقم'), findsOneWidget);
      await simDrain(t);
    });

    for (final v in simVariants) {
      testWidgets('بلا فيضٍ ولا أخطاء @${v.tag}: «ادفع لمديرك» بالباركود', (t) async {
        PayQrTile.debugImage = (url) => Container(key: ValueKey('img:$url'), width: 200, height: 200, color: Colors.black12);
        await open(t, {'zaincash': '07801234567', 'master': '5222333344445555', 'note': 'حوّل واكتب اسمك', 'zaincash_qr': _qr1, 'zaincash_show': 'both', 'master_qr': _qr2, 'master_show': 'qr'}, v: v);
        expect(t.takeException(), isNull);
        await simDrain(t);
      });
    }
  });
}
