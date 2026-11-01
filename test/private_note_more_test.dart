import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// المالك ١ نوفمبر: «اضافة الملاحظة حولها بالمزيد» — صفحة المشترك بلا زرّ «إضافة ملاحظة» العريض؛ الإضافة صفٌّ في «المزيد»
/// (و«تعديل الملاحظة» حين توجد، والكرت يبقى بنصّها)، والموظّف بلا مفتاحها يراه مقفلاً بمكانه.
const _v = SimVariant(390, dark: false);
const _idx = '900007';
const _path = '/api/v2/subscribers/$_idx/private-note';

Subscriber _sub() => Subscriber.fromJson({
      'idx': _idx,
      'username': 'user7',
      'firstname': 'علي',
      'lastname': 'حسن',
      'phone': '07701234567',
      'profile_name': '10M',
      'expiration': '2026-11-20 14:30:00',
      'remaining_days': 19,
      'enabled': 1,
      'notes': '0',
    });

void main() {
  late SimServer server;
  setUpAll(simSetUpAll);
  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'nabd:myservices', 'auth.admin_username': 'myservices'});
    SubscribersApi.clearAllCaches();
    ProviderService.debugSet('nabd', label: 'نبض');
  });
  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Future<void> open(WidgetTester t) async {
    await pumpSim(t, _v, home: (_) => SubscriberDetailScreen(sub: _sub()), settle: false);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
  }

  Future<void> more(WidgetTester t) async {
    await t.tap(find.byIcon(LucideIcons.ellipsis).first);
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  }

  testWidgets('بلا ملاحظة: لا زرّ في الصفحة، و«إضافة ملاحظة» في «المزيد» تفتح الورقة وتحفظ فيظهر الكرت', (t) async {
    PermissionsService.debugSet(isEmployee: false);
    var note = '';
    server.on('GET', _path, (_) => SimReply(200, {'success': true, 'data': note.isEmpty ? null : {'note': note}}));
    server.on('PUT', _path, (o) {
      note = (o.data as Map)['note'] as String;
      return SimReply(200, {'success': true, 'data': {'note': note}});
    });
    await open(t);
    expect(find.text('إضافة ملاحظة'), findsNothing, reason: 'لا زرّ عريض أعلى الصفحة');
    await more(t);
    expect(find.text('إضافة ملاحظة').hitTestable(), findsOneWidget);
    await t.tap(find.text('إضافة ملاحظة'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await t.enterText(find.byType(TextField), 'يدفع آخر الشهر');
    await t.pump();
    await t.tap(find.text('حفظ'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    await t.pump(const Duration(seconds: 1)); // الورقة تُغلق قبل عدّ النصّ (حقلها يحمل النصّ نفسه)
    expect(server.bodies('PUT', _path).single, {'note': 'يدفع آخر الشهر'});
    expect(find.text('يدفع آخر الشهر'), findsOneWidget, reason: 'الكرت يظهر بالملاحظة');
    await t.pump(const Duration(seconds: 5));
    await more(t);
    expect(find.text('تعديل الملاحظة').hitTestable(), findsOneWidget);
    await close(t);
  });

  testWidgets('الموظّف بلا مفتاحها: «إضافة ملاحظة» في «المزيد» مقفلة ولا ورقة', (t) async {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
    server.reply('GET', _path, 200, {'success': true, 'data': null});
    await open(t);
    await more(t);
    final row = find.ancestor(of: find.text('إضافة ملاحظة'), matching: find.byType(InkWell)).first;
    expect(find.descendant(of: row, matching: find.byType(PermLockIcon)), findsOneWidget);
    await t.tap(find.text('إضافة ملاحظة'));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(TextField), findsNothing);
    await close(t);
  });
}
