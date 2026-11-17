import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/portal_services_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/portal_settings/portal_settings_screen.dart';
import 'package:rad_mysvcs/screens/portal_settings/widgets/services_tab.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «خدماتنا» في «بوابة المشترك» (١٦ نوفمبر ٢٠٢٦ — المالك: «خدماتنا او تطبيقاتنا حقل اسم وحقل رابط التطبيق وحقل صورة التطبيق النظام
/// يضغطها قدر الامكان… بالنقر ع التطبيق يوديهم للرابط»)، أمام خادمٍ وهميّ بعقد server/portalServices.js (1c052aa):
///
///   GET /api/v2/portal/services → {success, available, services:[{id,name,url,image}], limit}
///   POST /api/v2/portal/services {name, url, image?: data URL} → 201 {success, service}
///   PUT /api/v2/portal/services/:id {name?, url?, image?: data URL | null} → {success, service}
///   DELETE /api/v2/portal/services/:id → {success}
///   PUT /api/v2/portal/services/order {ids} → {success, services}
const _list = '/api/v2/portal/services';
const _settings = '/api/v2/portal/settings';
const _logins = '/api/v2/portal/logins';

Map<String, dynamic> _svc(int id, String name, String url, {String? image}) =>
    {'id': id, 'name': name, 'url': url, 'image': image};

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2251'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
    server.reply('GET', _settings, 200, {'success': true, 'enabled': true, 'agent_code': '402917'});
    server.reply('GET', _logins, 200, {'success': true, 'data': []});
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  void mockPlatform(WidgetTester t) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  }

  /// الشاشة ثمّ تبويب «خدماتنا» (الرابع) بعرض [w].
  Future<void> openServices(WidgetTester t, {double w = 360}) async {
    mockPlatform(t);
    await pumpSim(t, SimVariant(w, dark: false), home: (_) => const PortalSettingsScreen());
    t.view.physicalSize = Size(w, 2000);
    await t.pumpAndSettle();
    await t.tap(find.text('خدماتنا').first);
    await t.pumpAndSettle();
  }

  group('العقد والضغط', () {
    test('PortalService: الصورة النسبيّة تُكمَّل بعنوان الخادم، والمضيف بلا www، والحرف الأوّل', () {
      final s = PortalService.fromJson(_svc(3, 'تطبيق الأفلام', 'https://www.example.com/app', image: '/api/portal/svc-img/3-0123456789ab.png'))!;
      expect(s.image, endsWith('/api/portal/svc-img/3-0123456789ab.png'));
      expect(s.image, startsWith('https://'));
      expect(s.host, 'example.com');
      expect(s.initial, 'ت');
      expect(PortalService.fromJson({'id': 'x', 'name': 'A', 'url': 'https://a.com'}), isNull);
      expect(PortalService.fromJson({'id': 1, 'name': ' ', 'url': 'https://a.com'}), isNull);
    });

    test('validateService كالخادم: الاسم ١–٤٠، والرابط http(s) بمضيفٍ فيه نقطة (بلا بروتوكولٍ ⇒ https)', () {
      expect(validateService('A', 'play.google.com/store/apps/details?id=x'), isNull);
      expect(validateService('', 'https://a.com'), 'اكتب اسم الخدمة');
      expect(validateService('x' * 41, 'https://a.com'), contains('طويل'));
      expect(validateService('A', ''), contains('الصق'));
      expect(validateService('A', 'javascript:alert(1)'), contains('غير صالح'));
      expect(validateService('A', 'https://a .com'), contains('مسافات'));
      expect(validateService('A', 'localhost'), contains('غير صالح'));
    });

    test('ضغط الصورة: مربّعٌ من الوسط بضلع 256، PNG للشفّاف وJPEG للمعتم — تحت 300 ك.ب وبلا EXIF', () {
      final opaque = img.Image(width: 1200, height: 800);
      img.fill(opaque, color: img.ColorRgb8(200, 30, 30));
      final r1 = prepareServiceIcon(Uint8List.fromList(img.encodeJpg(opaque, quality: 95)));
      expect(r1.mime, 'image/jpeg');
      final d1 = img.decodeImage(r1.bytes)!;
      expect([d1.width, d1.height], [256, 256]);
      expect(r1.bytes.length, lessThan(serviceIconMaxBytes));
      final alpha = img.Image(width: 300, height: 300, numChannels: 4);
      img.fill(alpha, color: img.ColorRgba8(0, 120, 255, 0));
      img.fillCircle(alpha, x: 150, y: 150, radius: 100, color: img.ColorRgba8(0, 120, 255, 255));
      final r2 = prepareServiceIcon(Uint8List.fromList(img.encodePng(alpha)));
      expect(r2.mime, 'image/png');
      expect(img.decodeImage(r2.bytes)!.width, 256);
      final small = img.Image(width: 64, height: 40);
      final r3 = prepareServiceIcon(Uint8List.fromList(img.encodePng(small)));
      expect([img.decodeImage(r3.bytes)!.width, img.decodeImage(r3.bytes)!.height], [40, 40], reason: 'لا تكبير للصغيرة');
      expect(() => prepareServiceIcon(Uint8List.fromList(List.filled(64, 7))), throwsA(isA<ServiceImageError>()));
      expect(r1.dataUrl, startsWith('data:image/jpeg;base64,'));
    });
  });

  group('المالك', () {
    testWidgets('التبويب الرابع «خدماتنا»: القائمة بالترتيب والاسم والمضيف كاملان، وبطاقة «كما يراها مشتركوك»', (t) async {
      server.reply('GET', _list, 200, {
        'success': true,
        'available': true,
        'limit': 12,
        'services': [
          _svc(1, 'تطبيق الأفلام', 'https://play.google.com/store/apps/details?id=com.movies'),
          _svc(2, 'واتساب الدعم الفنّي على مدار الساعة', 'https://wa.me/9647700000000'),
        ],
      });
      await openServices(t);
      expect(find.text('تطبيق الأفلام'), findsNWidgets(2), reason: 'القائمة + المعاينة');
      expect(find.text('play.google.com'), findsOneWidget);
      expect(find.text('كما يراها مشتركوك'), findsOneWidget);
      expect(find.textContaining('2/12'), findsOneWidget);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });

    testWidgets('🚨 الإضافة: الاسم والرابط والصورة المضغوطة data URL ⇒ POST ثمّ تُعاد القائمة', (t) async {
      var listed = <Map<String, dynamic>>[];
      server.on('GET', _list, (_) => SimReply(200, {'success': true, 'available': true, 'limit': 12, 'services': listed}));
      server.on('POST', _list, (req) {
        final b = req.data as Map;
        listed = [_svc(9, b['name'] as String, b['url'] as String, image: '/api/portal/svc-img/9-0123456789ab.png')];
        return SimReply(201, {'success': true, 'service': listed.first});
      });
      await openServices(t);
      expect(find.text('ما أضفت خدمات بعد'), findsOneWidget);
      await t.tap(find.textContaining('إضافة خدمة'));
      await t.pumpAndSettle();
      expect(find.text('خدمة جديدة'), findsOneWidget);
      // التحقّق قبل الإرسال
      await t.tap(find.text('إضافة'));
      await t.pumpAndSettle();
      expect(find.text('اكتب اسم الخدمة'), findsOneWidget);
      expect(server.calls('POST', _list), isEmpty);
      final fields = find.byType(TextField);
      await t.enterText(fields.at(0), 'IPTV البث المباشر');
      await t.enterText(fields.at(1), 'iptv.example.com');
      await t.tap(find.text('إضافة'));
      await t.pumpAndSettle();
      final body = server.bodies('POST', _list).single;
      expect(body['name'], 'IPTV البث المباشر');
      expect(body['url'], 'iptv.example.com', reason: 'الخادم يطبّعه https://');
      expect(body.containsKey('image'), isFalse, reason: 'بلا صورة');
      expect(find.text('IPTV البث المباشر'), findsWidgets);
      await simDrain(t);
    });

    testWidgets('التعديل: الحقل المتغيّر وحده يُرسل، وإزالة الصورة image:null؛ والحذف بتأكيد', (t) async {
      server.reply('GET', _list, 200, {
        'success': true,
        'available': true,
        'limit': 12,
        'services': [_svc(4, 'قناة التلغرام', 'https://t.me/example', image: '/api/portal/svc-img/4-0123456789ab.png')],
      });
      server.on('PUT', '$_list/4', (req) => SimReply(200, {'success': true, 'service': _svc(4, 'قناة التلغرام', 'https://t.me/example')}));
      server.on('DELETE', '$_list/4', (_) => const SimReply(200, {'success': true}));
      await openServices(t);
      await t.tap(find.text('قناة التلغرام').first);
      await t.pumpAndSettle();
      expect(find.text('تعديل الخدمة'), findsOneWidget);
      await t.tap(find.text('إزالة'));
      await t.pumpAndSettle();
      await t.tap(find.text('حفظ'));
      await t.pumpAndSettle();
      expect(server.bodies('PUT', '$_list/4').single, {'image': null});
      // الحذف
      await t.tap(find.text('قناة التلغرام').first);
      await t.pumpAndSettle();
      await t.tap(find.byIcon(LucideIcons.trash2));
      await t.pumpAndSettle();
      expect(find.text('حذف الخدمة؟'), findsOneWidget);
      await t.tap(find.text('حذف نهائياً'));
      await t.pumpAndSettle();
      expect(server.calls('DELETE', '$_list/4').length, 1);
      await simDrain(t);
    });

    testWidgets('الترتيب: السهم يرسل ids كلّها بالترتيب الجديد ويعرض ما ردّه الخادم', (t) async {
      final a = _svc(1, 'A1', 'https://a.com');
      final b = _svc(2, 'B2', 'https://b.com');
      server.reply('GET', _list, 200, {'success': true, 'available': true, 'limit': 12, 'services': [a, b]});
      server.on('PUT', '$_list/order', (req) => SimReply(200, {'success': true, 'services': [b, a]}));
      await openServices(t);
      await t.tap(find.byTooltip('تحريك للأسفل').first);
      await t.pumpAndSettle();
      expect(server.bodies('PUT', '$_list/order').single, {'ids': [2, 1]});
      double y(String s) => t.getTopLeft(find.text(s).first).dy;
      expect(y('B2'), lessThan(y('A1')));
      await simDrain(t);
    });

    for (final w in const [320.0, 480.0]) {
      testWidgets('بلا فيض @ $w: الاسم الطويل كاملاً، والتبويبات الأربعة بأسمائها', (t) async {
        server.reply('GET', _list, 200, {
          'success': true,
          'available': true,
          'limit': 12,
          'services': [_svc(1, 'واتساب الدعم الفنّي على مدار الساعة للطوارئ', 'https://subdomain.very-long-domain-example.com/path')],
        });
        await openServices(t, w: w);
        expect(t.takeException(), isNull);
        for (final tab in ['رمز الوكيل', 'معلومات الشركة', 'وصف الباقات', 'خدماتنا']) {
          expect(find.text(tab), findsWidgets, reason: tab);
        }
        await simDrain(t);
      });
    }
  });

  group('الموظّف', () {
    testWidgets('بلا settings.edit: التبويب بمكانه مقفلاً — بلا طلب', (t) async {
      PermissionsService.debugSet(isEmployee: true);
      await openServices(t);
      expect(find.byType(LockedNotice), findsWidgets);
      expect(server.calls('GET', _list), isEmpty);
      await simDrain(t);
    });
  });
}
