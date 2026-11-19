import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/kit_fiber_card.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/screens/network_devices/fiber/fiber_widgets.dart';

/// «الليف والموقع» (المشروع الوطنيّ، ٣١ أكتوبر — «الباور والموقع مال مشترك مايظهر»): الكرت لشركةٍ مُضافة بقدرة شركتها، مطويٌّ
/// والضوء بقيمته ولونه بالعنوان، و«لا ضوء» صراحةً للمفصول، والمسار والجهاز والعنوان وزرّ الخريطة عند الفتح، ولا كرت بلا بيانات.
void main() {
  Subscriber sub() => Subscriber.fromJson({
        'idx': '900003',
        'username': 'fiber3@ftth',
        'firstname': 'علي حسين',
        'expiration': '2026-11-12 18:00:00',
        'remaining_days': 12,
      });

  const up = KitFiberInfo(
    rx: -22.52,
    ontStatus: 'Up',
    opticsAt: '2026-10-31 17:42:10',
    serial: 'HWTC4F1A2B3C',
    fdt: 'FDT-03',
    fat: 'FAT-12',
    fatPort: 4,
    lat: 33.3128,
    lng: 44.4314,
    address: 'بغداد، الكرادة، محلّة 905',
    nearest: 'جامع الكرادة',
    zone: 'Zone 7',
  );

  Widget host(Widget child) => MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: Scaffold(body: SingleChildScrollView(child: child))),
      );

  setUp(() {
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    PermissionsService.debugSet(isEmployee: false);
    // نافذة الجهاز (٢ نوفمبر): لا سؤال للخادم هنا — غير مفتوحة إلّا حيث يقول الاختبار
    KitFiberCard.beta = () async => null;
  });

  tearDown(() {
    KitFiberCard.debugReset();
    ProviderService.debugSet(null);
    PermissionsService.debugReset();
  });

  test('fromJson: حقول الخادم كما هي، والمسار «FDT ← FAT (منفذ)»', () {
    final d = KitFiberInfo.fromJson({
      'rxDbm': -18.9,
      'ontStatus': 'Up',
      'ontDown': false,
      'serial': 'X1',
      'fdt': 'FDT-1',
      'fat': 'FAT-2',
      'fatPort': 3,
      'location': {'lat': 33.1, 'lng': 44.2, 'text': 'عنوان', 'nearestPoint': 'نقطة', 'zone': 'Z'},
    });
    expect(d.rx, -18.9);
    expect(d.path, 'FDT-1 ← FAT-2 (منفذ 3)');
    expect(d.place, 'عنوان — قرب نقطة');
    expect(d.hasMap, isTrue);
    expect(KitFiberInfo.fromJson({'location': null}).hasMap, isFalse);
  });

  test('shownFor: شركةٌ مُضافة وساس فور (FTTH) خارج «كل الشركات» — لا ايرث لنك ولا الوطنيّ القديم ولا فايبر اكس', () {
    expect(KitFiberCard.shownFor(sub()), isTrue);
    // ساس فور (١٩ نوفمبر — ساسات FTTH): مديرٌ بلا قيود ⇒ يُسأل الخادم (ساسٌ بلا حقول FTTH يردّ 409 فلا كرت)
    ProviderService.debugSet(null);
    expect(KitFiberCard.shownFor(sub()), isTrue, reason: 'ساس فور — الخادم يحكم');
    // مديرٌ مقيَّد: خريطة ساسه تحكم (prm_ftth_device ⇐ subscribers.fiber_info)
    PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: const {'subscribers.fiber_info': false});
    expect(KitFiberCard.shownFor(sub()), isFalse, reason: 'ساسه لا يمنح جهاز المشترك');
    PermissionsService.debugSet(isEmployee: false, managerRestricted: true, managerCaps: const {'subscribers.fiber_info': true});
    expect(KitFiberCard.shownFor(sub()), isTrue);
    // الموظّف بعرض المشتركين (كالشركات المُضافة)
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
    expect(KitFiberCard.shownFor(sub()), isTrue);
    PermissionsService.debugSet(isEmployee: false);
    for (final p in ['earthlink', 'ftth', 'fiberx']) {
      ProviderService.debugSet(p);
      expect(KitFiberCard.shownFor(sub()), isFalse, reason: p);
    }
    // «كل الشركات»: صفُّ شركةٍ أخرى ⇒ لا كرت (كما كان)
    ProviderService.debugSet(null);
    expect(KitFiberCard.shownFor(sub().withCompany('c0123456789ab')), isFalse, reason: '«كل الشركات»');
    ProviderService.debugSet('watani');
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': false});
    expect(KitFiberCard.shownFor(sub()), isFalse, reason: 'موظّفٌ بلا عرض المشتركين');
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
    expect(KitFiberCard.shownFor(sub()), isTrue);
  });

  testWidgets('مطويٌّ والضوء بقيمته ولونه بالعنوان · الفتح: المسار والجهاز والمنطقة والعنوان والخريطة', (t) async {
    Uri? opened;
    KitFiberCard.fetch = (_) async => up;
    KitFiberCard.openMap = (u) async {
      opened = u;
      return true;
    };
    await t.pumpWidget(host(KitFiberCard(sub: sub())));
    expect(find.textContaining('يقرأ'), findsOneWidget); // الحبّة تعزل نصّها (iso)
    await t.pump();
    expect(find.text('الليف والموقع'), findsOneWidget);
    expect(find.textContaining('-22.5 dBm'), findsOneWidget);
    expect(find.text('المسار'), findsNothing);
    await t.tap(find.text('الليف والموقع'));
    await t.pumpAndSettle();
    expect(find.textContaining('FDT-03 ← FAT-12 (منفذ 4)'), findsOneWidget);
    expect(find.textContaining('HWTC4F1A2B3C'), findsOneWidget);
    expect(find.text('Zone 7'), findsOneWidget);
    expect(find.text('بغداد، الكرادة، محلّة 905 — قرب جامع الكرادة'), findsOneWidget);
    await t.tap(find.text('افتح الموقع على الخريطة'));
    await t.pump();
    expect(opened.toString(), 'https://www.google.com/maps?q=33.3128,44.4314');
  });

  testWidgets('المفصول: «لا ضوء» صراحةً لا رقم · بلا إحداثيّات لا زرّ خريطة', (t) async {
    KitFiberCard.fetch = (_) async => const KitFiberInfo(down: true, ontStatus: 'Down', fdt: 'FDT-03', fat: 'FAT-09', address: 'بغداد');
    await t.pumpWidget(host(KitFiberCard(sub: sub())));
    await t.pump();
    expect(find.textContaining('لا ضوء — مفصول'), findsOneWidget);
    expect(find.textContaining('dBm'), findsNothing);
    await t.tap(find.text('الليف والموقع'));
    await t.pumpAndSettle();
    expect(find.text('لا ضوء — الجهاز مفصول'), findsOneWidget);
    expect(find.text('افتح الموقع على الخريطة'), findsNothing);
  });

  // ═══ ساسات FTTH (١٩ نوفمبر — الوطني البصرة/الناصريّة): لا قياس ضوء، وحقول جهاز المشترك من المشروع ═══
  test('fromJson: optics/vendor/mac/ip/lockedMac/plan — وغيابها كما كان', () {
    final d = KitFiberInfo.fromJson({
      'rxDbm': null, 'optics': false, 'serial': 'ZTEGC0FFEE01', 'vendor': 'ZTE', 'mac': 'AA:BB:CC:DD:EE:01', 'ip': '10.20.30.40',
      'lockedMac': null, 'plan': 'FIBER 35', 'fdt': 'FDT101-1', 'fat': 'FAT12',
      'location': {'lat': 30.51234, 'lng': 47.81234, 'zone': 'BSR1001-1'},
    });
    expect(d.noOptics, isTrue);
    expect(d.vendor, 'ZTE');
    expect(d.mac, 'AA:BB:CC:DD:EE:01');
    expect(d.ip, '10.20.30.40');
    expect(d.lockedMac, isNull);
    expect(d.plan, 'FIBER 35');
    expect(d.serial, 'ZTEGC0FFEE01');
    final old = KitFiberInfo.fromJson({'rxDbm': -20.1, 'serial': 'X'});
    expect(old.optics, isNull);
    expect(old.noOptics, isFalse, reason: 'الشركات المُضافة: كما كان');
  });

  const ftth = KitFiberInfo(
    optics: false,
    serial: 'ZTEGC0FFEE01',
    vendor: 'ZTE',
    mac: 'AA:BB:CC:DD:EE:01',
    ip: '10.20.30.40',
    plan: 'FIBER 35',
    fdt: 'FDT101-1',
    fat: 'FAT12',
    lat: 30.51234,
    lng: 47.81234,
    zone: 'BSR1001-1',
  );

  testWidgets('ساس FTTH بلا قياس: الباقة بدل «لا قياس» · الفتح: الباقة والمسار والجهاز ونوعه والماك والآيبي والمنطقة', (t) async {
    ProviderService.debugSet(null);
    KitFiberCard.fetch = (_) async => ftth;
    await t.pumpWidget(host(KitFiberCard(sub: sub())));
    await t.pump();
    expect(find.text('الليف والموقع'), findsOneWidget);
    expect(find.textContaining('لا قياس'), findsNothing);
    expect(find.textContaining('dBm'), findsNothing);
    expect(find.textContaining('FIBER 35'), findsOneWidget, reason: 'حبّة العنوان');
    await t.tap(find.text('الليف والموقع'));
    await t.pumpAndSettle();
    expect(find.text('الإشارة'), findsNothing);
    expect(find.text('الباقة'), findsOneWidget);
    expect(find.textContaining('FDT101-1 ← FAT12'), findsOneWidget);
    expect(find.textContaining('ZTEGC0FFEE01'), findsOneWidget);
    expect(find.text('نوع الجهاز'), findsOneWidget);
    expect(find.text('ZTE'), findsOneWidget);
    expect(find.text('الماك'), findsOneWidget);
    expect(find.textContaining('AA:BB:CC:DD:EE:01'), findsOneWidget);
    expect(find.text('الآيبي'), findsOneWidget);
    expect(find.textContaining('10.20.30.40'), findsOneWidget);
    expect(find.text('الماك المقفول'), findsNothing);
    expect(find.text('BSR1001-1'), findsOneWidget);
    expect(find.text('افتح الموقع على الخريطة'), findsOneWidget);
  });

  testWidgets('ساس FTTH تعذّرت قراءة جهازه: الحبّة تقولها والسطر يشرحها، والبقيّة من صفّ الساس', (t) async {
    ProviderService.debugSet(null);
    KitFiberCard.fetch = (_) async => const KitFiberInfo(optics: false, ontError: 'failed', serial: 'ZTEGC0FFEE01', fdt: 'FDT101-1', fat: 'FAT12');
    await t.pumpWidget(host(KitFiberCard(sub: sub())));
    await t.pump();
    expect(find.textContaining('تعذّرت قراءة الجهاز'), findsOneWidget);
    await t.tap(find.text('الليف والموقع'));
    await t.pumpAndSettle();
    expect(find.text('تعذّرت قراءة الجهاز من المشروع'), findsOneWidget);
    expect(find.textContaining('ZTEGC0FFEE01'), findsOneWidget);
    expect(find.text('الماك'), findsNothing);
    expect(find.text('الباقة'), findsNothing);
  });

  testWidgets('ساس FTTH بلا قياس ولا باقة ولا عطل ⇒ لا حبّة (لا «لا قياس» لقراءةٍ لا تُطلب)', (t) async {
    ProviderService.debugSet(null);
    KitFiberCard.fetch = (_) async => const KitFiberInfo(optics: false, serial: 'ZTEGC0FFEE01');
    await t.pumpWidget(host(KitFiberCard(sub: sub())));
    await t.pump();
    expect(find.text('الليف والموقع'), findsOneWidget);
    expect(find.byType(FiberPill), findsNothing);
  });

  testWidgets('زرّا الخريطة: متجاوران حين يتّسع السطر، وكلٌّ بسطرٍ حين يضيق (٣٢٠ بخطّ ١٫٢) — بلا كلمةٍ تنكسر ولا فيضان', (t) async {
    ProviderService.debugSet(null);
    KitFiberCard.fetch = (_) async => ftth;
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
      t.platformDispatcher.clearTextScaleFactorTestValue();
    });
    Future<double> gap(Size size, double scale) async {
      t.view.devicePixelRatio = 3;
      t.view.physicalSize = size * 3;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      await t.pumpWidget(const SizedBox.shrink());
      await t.pumpWidget(host(KitFiberCard(sub: sub())));
      await t.pump();
      await t.tap(find.text('الليف والموقع'));
      await t.pumpAndSettle();
      final a = t.getRect(find.text('نسخ الإحداثيّات'));
      final b = t.getRect(find.text('إرسال الموقع'));
      // نصّ الزرّ سطرٌ واحد (لا انكسار): ارتفاعه سطرٌ بمقياس الخطّ
      expect(a.height, lessThan(14 * scale * 1.6));
      expect(b.height, lessThan(14 * scale * 1.6));
      return (a.top - b.top).abs();
    }
    expect(await gap(const Size(800, 1400), 1.0), lessThan(2), reason: 'متجاوران');
    expect(await gap(const Size(320, 1400), 1.2), greaterThan(20), reason: 'كلٌّ بسطر');
    expect(t.takeException(), isNull);
  });

  testWidgets('شركةٌ لا تقرؤها (409) أو خطأ ⇒ لا كرت بعد التحميل', (t) async {
    KitFiberCard.fetch = (_) async => null;
    await t.pumpWidget(host(KitFiberCard(sub: sub())));
    await t.pump();
    expect(find.text('الليف والموقع'), findsNothing);
  });
}
