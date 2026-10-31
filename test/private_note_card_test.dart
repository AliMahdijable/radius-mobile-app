import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/private_note_card.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «ملاحظة» خاصّة بكرت المشترك (المالك ٣١ أكتوبر: «زر ملاحظات خاص بنظامنا… تنعرض بكارت المشترك فقط، لكل الساسات»):
/// الملاحظة تُقرأ وتظهر بنصّها ومن كتب، و«تعديل» يحفظها (PUT)، والنصّ الفارغ أو «حذف» يحذفها (DELETE)، و«إضافة ملاحظة» حين لا
/// ملاحظة، والموظّف بلا subscribers.private_note يرى الزرّ مقفلاً بمكانه.
const _v = SimVariant(390, dark: false);
const _path = '/api/v2/subscribers/900003/private-note';

Subscriber _sub() => Subscriber.fromJson({
      'idx': '900003',
      'username': 'fiber3@ftth',
      'firstname': 'علي حسين',
      'expiration': '2026-11-12 18:00:00',
      'remaining_days': 12,
    });

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'nabd:myservices', 'auth.admin_username': 'myservices'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('nabd', label: 'نبض');
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Future<void> open(WidgetTester t) async {
    await pumpSim(t, _v, home: (_) => Scaffold(body: SingleChildScrollView(child: PrivateNoteCard(sub: _sub()))));
  }

  testWidgets('ملاحظةٌ قائمة: نصّها ومن كتب، و«تعديل» يحفظ النصّ الجديد', (t) async {
    server.reply('GET', _path, 200, {
      'success': true,
      'data': {'note': 'يدفع آخر الشهر', 'updated_at': '2026-10-31T13:20:00.000Z', 'updated_by': 'cashier1'},
    });
    server.on('PUT', _path, (o) => SimReply(200, {
          'success': true,
          'data': {'note': (o.data as Map)['note'], 'updated_at': '2026-10-31T14:00:00.000Z', 'updated_by': 'myservices'},
        }));
    await open(t);
    expect(find.text('يدفع آخر الشهر'), findsOneWidget);
    expect(find.textContaining('cashier1'), findsOneWidget);

    await t.tap(find.text('تعديل'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'غيّر الراوتر');
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(server.bodies('PUT', _path).single, {'note': 'غيّر الراوتر'});
    expect(find.text('غيّر الراوتر'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('بلا ملاحظة: «إضافة ملاحظة»، وحذفٌ من الورقة يُرسل DELETE', (t) async {
    var note = '';
    server.on('GET', _path, (_) => SimReply(200, {'success': true, 'data': note.isEmpty ? null : {'note': note}}));
    server.on('PUT', _path, (o) {
      note = (o.data as Map)['note'] as String;
      return SimReply(200, {'success': true, 'data': {'note': note}});
    });
    server.on('DELETE', _path, (_) {
      note = '';
      return const SimReply(200, {'success': true, 'data': null, 'removed': 1});
    });
    await open(t);
    expect(find.text('إضافة ملاحظة'), findsOneWidget);

    await t.tap(find.text('إضافة ملاحظة'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'اتّصل قبل الزيارة');
    await t.pumpAndSettle();
    await t.tap(find.text('حفظ'));
    await t.pumpAndSettle();
    expect(find.text('اتّصل قبل الزيارة'), findsOneWidget);
    // إشعار «حُفظت» يزول قبل فتح الورقة ثانيةً (يغطّي أسفلها)
    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();

    await t.tap(find.text('تعديل'));
    await t.pumpAndSettle();
    await t.tap(find.byIcon(LucideIcons.trash2));
    await t.pumpAndSettle();
    expect(server.calls('DELETE', _path), hasLength(1));
    expect(find.text('إضافة ملاحظة'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('الموظّف بلا مفتاحها: الزرّ بمكانه مقفلاً ولا ورقة', (t) async {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
    server.reply('GET', _path, 200, {'success': true, 'data': null});
    await open(t);
    expect(find.text('إضافة ملاحظة — لا صلاحيّة'), findsOneWidget);
    await t.tap(find.text('إضافة ملاحظة — لا صلاحيّة'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await simDrain(t);
  });

  testWidgets('تعذّر الجلب (الجدول قيد التجهيز): لا قسمٌ يوهم بملاحظةٍ فارغة', (t) async {
    server.reply('GET', _path, 503, {'success': false, 'code': 'PRIVATE_NOTES_UNAVAILABLE', 'message': 'الملاحظات قيد التجهيز'});
    await open(t);
    expect(find.text('إضافة ملاحظة'), findsNothing);
    expect(find.text('ملاحظة'), findsNothing);
    await simDrain(t);
  });
}
