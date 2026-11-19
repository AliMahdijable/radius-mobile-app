import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/sas_ftth_api.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/sas_ftth/sas_ftth_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/fiber_filters.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'support/app_fonts.dart';

/// «المشروع الوطني» لساسات الوطني (١٩ نوفمبر — البصرة/الناصريّة) في التطبيق: فلاتر المنطقة/FDT/FAT (منطقها والنموذج)، طبقة
/// الاتّصال (الأقسام والنافذة والغلاف)، البطاقة في «قوائم أخرى»، والشاشة بمتصفّحٍ بديل — على ٣٩٠ و٣٢٠ بخطٍّ ١٫٢.

Subscriber sub(int i, String? zone, String? fdt, String? fat, {bool abandoned = false}) => Subscriber.fromJson({
      'idx': 700 + i,
      'username': 'sub$i.z',
      'firstname': 'مشترك$i',
      'lastname': 'تجربة',
      if (zone != null) 'ftth_zone': zone,
      if (fdt != null) 'ftth_fdt': fdt,
      if (fat != null) 'ftth_fat': fat,
    });

final rows = [
  sub(1, 'BSR-1', 'FDT-1', 'FAT-1'),
  sub(2, 'BSR-1', 'FDT-1', 'FAT-2'),
  sub(3, 'BSR-1', 'FDT-2', 'FAT-3'),
  sub(4, 'BSR-2', 'FDT-7', 'FAT-9'),
  sub(5, 'BSR-10', 'FDT-20', 'FAT-30'),
  sub(6, 'BSR-10', 'FDT-20', 'FAT-31'),
];

const sections = [
  SasFtthSection(key: 'tickets', title: 'التذاكر'),
  SasFtthSection(key: 'requests', title: 'الطلبات'),
  SasFtthSection(key: 'offers', title: 'عروض الاشتراك'),
  SasFtthSection(key: 'subscription_details', title: 'تفاصيل الاشتراك'),
];

class FakeSasEngine implements SasFtthWebEngine {
  FakeSasEngine(this.cb) {
    all.add(this);
  }

  static final all = <FakeSasEngine>[];
  final SasFtthWebCallbacks cb;
  final opened = <Uri>[];

  @override
  Widget view(BuildContext context) => SizedBox.expand(child: Text(opened.isEmpty ? '' : 'page:${opened.last.path}'));

  @override
  Future<void> open(Uri url) async {
    opened.add(url);
    cb.onLoaded();
  }
}

void main() {
  setUpAll(loadAppFonts);

  group('فلاتر المنطقة/FDT/FAT', () {
    test('الترتيب الطبيعيّ: BSR-2 قبل BSR-10', () {
      final l = ['BSR-10', 'BSR-2', 'bsr-1', 'FDT-9', 'FDT-10']..sort(naturalCompare);
      expect(l, ['bsr-1', 'BSR-2', 'BSR-10', 'FDT-9', 'FDT-10']);
    });
    test('الخيارات متسلسلة بأعدادها', () {
      var o = FiberOptions.of(rows, FiberFilter.none);
      expect(o.zones, [('BSR-1', 3), ('BSR-2', 1), ('BSR-10', 2)]);
      expect(o.fdts.length, 4);
      final f = FiberFilter.none.withZone('BSR-1');
      o = FiberOptions.of(rows, f);
      expect(o.fdts, [('FDT-1', 2), ('FDT-2', 1)]);
      expect(o.fats, [('FAT-1', 1), ('FAT-2', 1), ('FAT-3', 1)]);
      o = FiberOptions.of(rows, f.withFdt('FDT-1'));
      expect(o.fats, [('FAT-1', 1), ('FAT-2', 1)]);
    });
    test('اختيار ما فوق يمسح ما تحته، و«الكل» يمسح', () {
      const f = FiberFilter(zone: 'BSR-1', fdt: 'FDT-1', fat: 'FAT-1');
      expect(f.withZone('BSR-10'), const FiberFilter(zone: 'BSR-10'));
      expect(f.withFdt('FDT-2'), const FiberFilter(zone: 'BSR-1', fdt: 'FDT-2'));
      expect(f.withZone(null), FiberFilter.none);
      expect(f.withFat('  '), const FiberFilter(zone: 'BSR-1', fdt: 'FDT-1'));
    });
    test('المطابقة', () {
      final f = FiberFilter.none.withZone('BSR-1').withFdt('FDT-1');
      expect(rows.where(f.matches).map((s) => s.username), ['sub1.z', 'sub2.z']);
      expect(rows.where(FiberFilter.none.matches).length, rows.length);
    });
    test('شركةٌ بلا حقول الوطني ⇒ لا قوائم', () {
      expect(FiberOptions.available(rows), isTrue);
      expect(FiberOptions.available([sub(1, null, null, null), sub(2, null, null, null)]), isFalse);
    });
  });

  group('النموذج يحمل الحقول', () {
    test('من الخادم: نصٌّ مقصوص والفارغ null', () {
      final s = Subscriber.fromJson({'username': 'a', 'firstname': '', 'lastname': '', 'ftth_zone': ' BSR-1 ', 'ftth_fdt': '', 'ftth_fat': null});
      expect(s.ftthZone, 'BSR-1');
      expect(s.ftthFdt, isNull);
      expect(s.ftthFat, isNull);
    });
    test('كلّ نسخةٍ تُبنى حقلاً حقلاً تحملها (الإثراء، الشركة، الاتّصال، الموقع، الهاتف)', () {
      final s = rows.first;
      final copies = [
        s.withCompany('basra'),
        s.enrichWithPackages({'9': const PackageInfo(name: 'FIBER 35', price: 35000)}),
        Subscriber.fromJson({'username': 'b', 'firstname': '', 'lastname': '', 'profile_id': 9, 'ftth_zone': 'Z', 'ftth_fdt': 'D', 'ftth_fat': 'T'})
            .enrichWithPackages({'9': const PackageInfo(name: 'FIBER 35', price: 35000)}),
        s.copyWithOnline(online: true, ip: '10.0.0.1'),
        s.copyWithLocation(latitude: 30.5, longitude: 47.8),
        s.copyWithPhone('07700000000'),
      ];
      for (final c in copies) {
        expect(c.ftthZone, isNotNull, reason: 'zone');
        expect(c.ftthFdt, isNotNull, reason: 'fdt');
        expect(c.ftthFat, isNotNull, reason: 'fat');
      }
    });
  });

  group('طبقة الاتّصال', () {
    test('الأقسام وما يستطيعه الفاعل', () {
      final p = SasFtthProbe.fromJson(const {
        'success': true,
        'data': const {
          'sections': const [
            {'key': 'tickets', 'page': 'index', 'title': 'التذاكر'},
            {'key': '', 'title': 'x'},
            'bad',
          ],
          'can': const {'view': true, 'edit': false, 'add': true},
        },
      });
      expect(p.sections.map((s) => s.key), ['tickets']);
      expect(p.shown, isTrue);
      expect(p.canEdit, isFalse);
      expect(p.note, contains('تعديل المشترك'));
      expect(SasFtthProbe.fromJson(const {'data': const {'sections': const []}}).shown, isFalse);
      expect(const SasFtthProbe(sections: sections).note, isNull);
      expect(const SasFtthProbe(sections: sections, canEdit: false, canAdd: false).note, startsWith('تصفّحٌ فقط'));
    });
    test('الغلاف: مسار النافذة ⇒ /wrap?to=… على خادمنا، وغيره null', () {
      final id = 'a' * 32;
      final u = sasFtthWrapUri('/sas-ftth/f/$id/admin/api/index.php/api/ftth/page/index?pageSize=12&manager_id=54&lang=ar',
          base: 'https://pro.mysvcs.net');
      expect(u.toString(),
          'https://pro.mysvcs.net/sas-ftth/f/$id/wrap?to=%2Fadmin%2Fapi%2Findex.php%2Fapi%2Fftth%2Fpage%2Findex%3FpageSize%3D12%26manager_id%3D54%26lang%3Dar');
      for (final bad in [
        'https://evil.example/x',
        '/sas-ftth/f/$id/admin/api/index.php/api/user/1',
        '/sas-ftth/f/XYZ/admin/api/index.php/api/ftth/page/index',
        '/sas-ftth/f/$id/admin/api/index.php/api/ftth/page/index?a="><script>',
      ]) {
        expect(sasFtthWrapUri(bad), isNull, reason: bad);
      }
    });
    test('التنقّل داخل الـWebView لخادمنا وحده', () {
      expect(sasFtthKeepsInside('https://pro.mysvcs.net/sas-ftth/f/x/wrap', base: 'https://pro.mysvcs.net'), isTrue);
      expect(sasFtthKeepsInside('about:blank', base: 'https://pro.mysvcs.net'), isTrue);
      expect(sasFtthKeepsInside('https://basra.alwatani.co/x', base: 'https://pro.mysvcs.net'), isFalse);
      expect(sasFtthKeepsInside('http://pro.mysvcs.net/x', base: 'https://pro.mysvcs.net'), isFalse);
      expect(sasFtthKeepsInside('https://maps.google.com/?q=1', base: 'https://pro.mysvcs.net'), isFalse);
    });
  });

  group('«قوائم أخرى»', () {
    tearDown(() {
      SasFtthState.reset();
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });
    test('تظهر لساس فور بأقسام، وتغيب بلا أقسام أو لغير ساس فور', () {
      ProviderService.debugSet(null);
      PermissionsService.debugSet(isEmployee: false);
      SasFtthState.debugSet(const SasFtthProbe(sections: sections));
      var m = buildAppModules().where((x) => x.id == 'sas_ftth').toList();
      expect(m.length, 1);
      expect(m.single.locked, isFalse);
      expect(m.single.title, 'المشروع الوطني');
      SasFtthState.debugSet(SasFtthProbe.off);
      expect(buildAppModules().where((x) => x.id == 'sas_ftth'), isEmpty);
      SasFtthState.debugSet(const SasFtthProbe(sections: sections));
      ProviderService.debugSet('earthlink');
      expect(buildAppModules().where((x) => x.id == 'sas_ftth'), isEmpty);
    });
    test('موظّفٌ بلا «عرض المشتركين» يراها بمكانها مقفلة', () {
      ProviderService.debugSet(null);
      PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.edit': true});
      SasFtthState.debugSet(const SasFtthProbe(sections: sections, canView: false));
      final m = buildAppModules().where((x) => x.id == 'sas_ftth').toList();
      expect(m.length, 1);
      expect(m.single.locked, isTrue);
    });
  });

  group('الشاشة', () {
    late List<String> minted;
    late int n;
    setUp(() {
      FakeSasEngine.all.clear();
      minted = [];
      n = 0;
      AppPlatform.debugIsDesktop = false;
    });
    tearDown(() => AppPlatform.debugIsDesktop = null);

    Future<SasFtthFrameResult> mint(String s) async {
      minted.add(s);
      n += 1;
      final page = {'tickets': 'index', 'requests': 'requests', 'offers': 'calculate_price', 'subscription_details': 'subscription_details'}[s]!;
      return (
        url: '/sas-ftth/f/${n.toRadixString(16).padLeft(32, '0')}/admin/api/index.php/api/ftth/page/$page?pageSize=12&manager_id=54&lang=ar',
        message: null,
        code: null
      );
    }

    Future<void> pump(WidgetTester t, {double width = 390, double scale = 1, SasFtthProbe probe = const SasFtthProbe(sections: sections),
        Future<SasFtthFrameResult> Function(String)? m}) async {
      t.view.physicalSize = Size(width * 3, 844 * 3);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: MediaQueryData(size: Size(width, 844), textScaler: TextScaler.linear(scale)),
            child: SasFtthScreen(probe: probe, mint: m ?? mint, engineFactory: FakeSasEngine.new),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('الأقسام الأربعة، والأوّل يُفتح على غلاف الخادم', (t) async {
      await pump(t);
      for (final s in sections) {
        expect(find.byKey(ValueKey('sas-ftth-tab-${s.key}')), findsOneWidget);
      }
      expect(minted, ['tickets']);
      final e = FakeSasEngine.all.single;
      expect(e.opened.single.toString(), startsWith('https://pro.mysvcs.net/sas-ftth/f/'));
      expect(e.opened.single.path, endsWith('/wrap'));
      expect(e.opened.single.queryParameters['to'], startsWith('/admin/api/index.php/api/ftth/page/index?'));
      expect(find.text('جارٍ فتح القسم…'), findsNothing);
      expect(find.byKey(const ValueKey('sas-ftth-note')), findsNothing);
    });

    testWidgets('الانتقال: نافذةٌ للقسم الجديد، والعودة بلا نافذة، و«تحديث» نافذةٌ جديدة', (t) async {
      await pump(t);
      await t.tap(find.byKey(const ValueKey('sas-ftth-tab-requests')));
      await t.pumpAndSettle();
      expect(minted, ['tickets', 'requests']);
      expect(FakeSasEngine.all.length, 2, reason: 'القسم الأوّل يبقى حيّاً');
      await t.tap(find.byKey(const ValueKey('sas-ftth-tab-tickets')));
      await t.pumpAndSettle();
      expect(minted, ['tickets', 'requests']);
      await t.tap(find.byTooltip('تحديث'));
      await t.pumpAndSettle();
      expect(minted, ['tickets', 'requests', 'tickets']);
      expect(FakeSasEngine.all.first.opened.length, 2);
    });

    testWidgets('خطأ الخادم بالعربيّة و«إعادة المحاولة»', (t) async {
      var fail = true;
      await pump(t, m: (s) async {
        if (fail) {
          fail = false;
          return (url: null, message: 'انتهت جلسة الساس — أعد فتح الشركة', code: 'SAS_SESSION_EXPIRED');
        }
        return mint(s);
      });
      expect(find.text('تعذّر فتح القسم'), findsOneWidget);
      expect(find.text('انتهت جلسة الساس — أعد فتح الشركة'), findsOneWidget);
      await t.tap(find.text('إعادة المحاولة'));
      await t.pumpAndSettle();
      expect(find.text('تعذّر فتح القسم'), findsNothing);
      expect(FakeSasEngine.all.single.opened.length, 1);
    });

    testWidgets('الموظّف: سطرٌ بما ينقصه للكتابة', (t) async {
      await pump(t, probe: const SasFtthProbe(sections: sections, canEdit: false, canAdd: false));
      expect(find.byKey(const ValueKey('sas-ftth-note')), findsOneWidget);
      expect(find.textContaining('تصفّحٌ فقط'), findsOneWidget);
    });

    testWidgets('٣٢٠ بخطٍّ ١٫٢: لا فيض ولا عنوان مقصوص', (t) async {
      await pump(t, width: 320, scale: 1.2);
      expect(t.takeException(), isNull);
      for (final s in sections) {
        final r = t.renderObject<RenderParagraph>(find.text(s.title));
        expect(r.didExceedMaxLines, isFalse, reason: s.title);
      }
    });

    testWidgets('بلا أقسام: رسالةٌ لا شاشة فارغة', (t) async {
      await pump(t, probe: SasFtthProbe.off);
      expect(find.text('لا أقسام للمشروع الوطني'), findsOneWidget);
      expect(minted, isEmpty);
    });

    testWidgets('الحاسبة: «افتح في المتصفّح» بلا WebView', (t) async {
      AppPlatform.debugIsDesktop = true;
      await pump(t, width: 900);
      expect(find.text('افتح في المتصفّح'), findsOneWidget);
      expect(FakeSasEngine.all, isEmpty);
      expect(minted, isEmpty, reason: 'النافذة تُصدر عند النقر وحده');
    });
  });
}
