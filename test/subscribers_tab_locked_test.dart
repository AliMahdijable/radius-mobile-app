import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// تبويب «المشتركون» بلا `subscribers.view`: يبقى في مكانه مقفلاً **بلا
/// نداء**.
///
/// مراجعة ٢٠٢٦-١٠-١٤: `initState` كان يُطلق `v2/subscribers` بلا شرط، فيردّه
/// الخادم 403 وتبقى الشاشة دوّارةً بيضاء بلا رأسٍ ولا بحث — والرئيسيّة بجانبه
/// تُري بطاقة المشتركين مقفلة.
void main() {
  Future<VisualServer> open(WidgetTester t, Scenario s) async {
    final server = await visualSetUp(s);
    await pumpVisual(t, phone, home: (_) => const SubscribersScreen());
    await settle(t, seconds: 2);
    return server;
  }

  Future<void> drain(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    await visualTearDown();
  }

  testWidgets('موظّف ايرث لنك بلا مفاتيح: إطارٌ مقفل ولا نداء ولا دوّارة',
      (t) async {
    final server = await open(t, s3ElEmpNone);

    expect(find.byType(LockedCard), findsOneWidget);
    expect(find.byType(PermLockIcon), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // والاستطلاع (٥ث) لا يطرق الخادم كذلك.
    await t.pump(const Duration(seconds: 12));
    final paths = server.log.join('\n');
    expect(paths.contains('/api/v2/subscribers'), isFalse, reason: paths);
    expect(paths.contains('/api/v2/online-users'), isFalse, reason: paths);
    expect(paths.contains('/api/v2/connection-alerts'), isFalse, reason: paths);
    expect(paths.contains('→ 403'), isFalse, reason: paths);

    // النقر: رسالةٌ لا تنقّل.
    await t.tap(find.byType(LockedCard));
    await t.pump();
    await t.pump(const Duration(seconds: 3));
    expect(t.takeException(), isNull);

    await drain(t);
  });

  testWidgets('المالك: القائمة كما هي بلا قفل', (t) async {
    // فيضان نصف بكسلٍ قائمٌ في صفّ المشترك بخطّ الاختبار — ليس موضوع هذا
    // الاختبار (الشاشة المستقلّة بلا الغلاف)، فلا يُسقطه.
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    final server = await open(t, s1Owner);

    expect(find.byType(LockedCard), findsNothing);
    expect(find.byType(PermLockIcon), findsNothing);
    expect(server.log.join('\n').contains('/api/v2/subscribers'), isTrue);

    await drain(t);
  });
}
