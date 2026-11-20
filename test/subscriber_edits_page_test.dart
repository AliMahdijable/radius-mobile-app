import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/edits_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/subscriber_table_row.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «سجلّ التعديلات» في صفحة المشترك (المالك ٢٠ نوفمبر): صفٌّ في «المزيد» بجانب «سجل الحركات» يفتح النافذة ويقرأ
/// GET /api/v2/subscribers/:idx/edits?username= — بصلاحيّة عرض المشترك نفسها (لا قفل للموظّف)، ولا صفّ لـFTTH القديم.
const _v = SimVariant(390, dark: false);
const _idx = '900007';
const _path = '/api/v2/subscribers/$_idx/edits';

final Map<String, dynamic> _contract =
    jsonDecode(File('test/subscriber_edits/server_contract.json').readAsStringSync()) as Map<String, dynamic>;

/// الانتهاء بعد ١٩ يوماً من الآن (لا تاريخاً ثابتاً ينقلب «منتهياً» مع الأيّام).
String _expiry() {
  final d = DateTime.now().add(const Duration(days: 19));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} 14:30:00';
}

Subscriber _sub() => Subscriber.fromJson({
      'idx': _idx,
      'username': 'user7',
      'firstname': 'علي',
      'lastname': 'حسن',
      'phone': '07701234567',
      'profile_name': '10M',
      'expiration': _expiry(),
      'remaining_days': 19,
      'enabled': 1,
      'notes': '0',
    });

void main() {
  late SimServer server;
  setUpAll(simSetUpAll);
  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': 'supernet:12', 'auth.admin_username': 'mahdi'});
    SubscribersApi.clearAllCaches();
    ProviderService.debugSet(null);
    server.reply('GET', _path, 200, _contract['owner']);
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

  testWidgets('المالك: «سجلّ التعديلات» في «المزيد» يفتح النافذة ويقرأ برقم المشترك ويوزره', (t) async {
    PermissionsService.debugSet(isEmployee: false);
    await open(t);
    expect(server.calls('GET', _path), isEmpty, reason: 'لا نداء مع فتح الصفحة — حين تُفتح النافذة وحدها');
    await more(t);
    final row = find.text('سجلّ التعديلات');
    expect(row, findsOneWidget);
    await t.ensureVisible(row);
    await t.pump(const Duration(milliseconds: 300));
    expect(row.hitTestable(), findsOneWidget);
    await t.tap(row);
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.byType(SubscriberEditsSheet), findsOneWidget);
    final call = server.calls('GET', _path).single;
    expect(call.queryParameters['username'], 'user7');
    expect(find.byKey(const ValueKey('sub-edit-901')), findsOneWidget);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('الموظّف بعرض المشترك وحده: الصفّ مفتوحٌ بلا قفل (صلاحيّة الخادم subscribers.view)', (t) async {
    PermissionsService.debugSet(isEmployee: true, permissions: const {'subscribers.view': true});
    await open(t);
    await more(t);
    final label = find.text('سجلّ التعديلات');
    expect(label, findsOneWidget);
    await t.ensureVisible(label);
    await t.pump(const Duration(milliseconds: 300));
    expect(label.hitTestable(), findsOneWidget);
    final tile = find.ancestor(of: label, matching: find.byType(InkWell)).first;
    expect(find.descendant(of: tile, matching: find.byType(PermLockIcon)), findsNothing);
    await t.tap(label);
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(server.calls('GET', _path), hasLength(1));
    await close(t);
  });

  testWidgets('قائمة صفّ الجدول (الحاسبة): «سجلّ التعديلات» بعد «سجل الحركات» يفتح النافذة', (t) async {
    PermissionsService.debugSet(isEmployee: false);
    await pumpSim(t, _v,
        home: (_) => simLauncher((c) => showSubscriberRowMenu(c, _sub(), position: const Offset(40, 40), onOpenDetails: () {})));
    await simOpen(t);
    expect(find.text('سجل الحركات'), findsOneWidget, reason: 'القائمة مفتوحة');
    final item = find.text('سجلّ التعديلات');
    expect(item, findsOneWidget);
    expect(t.getTopLeft(item).dy, greaterThan(t.getTopLeft(find.text('سجل الحركات')).dy));
    await t.tap(item);
    await t.pump();
    await t.pump(const Duration(milliseconds: 800));
    expect(find.byType(SubscriberEditsSheet), findsOneWidget);
    expect(server.calls('GET', _path), hasLength(1));
    await close(t);
  });

  testWidgets('FTTH القديم: لا صفّ (بوّابته لا تمرّر المسار)', (t) async {
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('ftth');
    await open(t);
    await more(t);
    expect(find.text('سجلّ التعديلات'), findsNothing);
    await close(t);
    // ولا في قائمة صفّ الجدول
    await pumpSim(t, _v,
        home: (_) => simLauncher((c) => showSubscriberRowMenu(c, _sub(), position: const Offset(40, 40), onOpenDetails: () {})));
    await simOpen(t);
    expect(find.text('سجل الحركات'), findsOneWidget, reason: 'القائمة مفتوحة');
    expect(find.text('سجلّ التعديلات'), findsNothing);
    await close(t);
  });
}
