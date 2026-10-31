import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/kit_fiber_card.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

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

  test('shownFor: شركةٌ مُضافة خارج «كل الشركات» وحدها', () {
    expect(KitFiberCard.shownFor(sub()), isTrue);
    ProviderService.debugSet(null);
    expect(KitFiberCard.shownFor(sub()), isFalse, reason: 'ساس');
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

  testWidgets('شركةٌ لا تقرؤها (409) أو خطأ ⇒ لا كرت بعد التحميل', (t) async {
    KitFiberCard.fetch = (_) async => null;
    await t.pumpWidget(host(KitFiberCard(sub: sub())));
    await t.pump();
    expect(find.text('الليف والموقع'), findsNothing);
  });
}
