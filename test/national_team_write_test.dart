import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_more_api.dart';
import 'package:rad_mysvcs/api/national_sheet_api.dart';
import 'package:rad_mysvcs/api/national_team_api.dart';
import 'package:rad_mysvcs/screens/national/national_team_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «فريقي» — الإضافة والتعديل والحذف في التطبيق (٢ نوفمبر — نسخة الموقع WataniTeamSheet/FtthTeam؛ الخادم teamAdd/Edit/Delete): لصاحب
/// الحساب حين تسمح البوّابة والكتابة؛ الاسم يُفحص، وكلمة السرّ بشروط البوّابة، والوظيفة والزونات وحدّ المحفظة؛ التعديل يرسل ما تغيّر
/// وحده؛ الحذف بتأكيدٍ وجسم {confirm:true}؛ والموظّف لا يرى الإدارة.
const _v = SimVariant(390, dark: false);
const _mid = '0a1b2c3d-1111-4222-8333-944455556666';
const _roleField = 'r-field';
const _roleCash = 'r-cash';
const _roleAll = 'r-all';

Map<String, Object?> _lookups({bool canWrite = true, String? teamLock}) => {
      'success': true,
      'data': {
        'beta': true,
        'can_write': canWrite,
        'caps': {},
        'portal_locks': {'team_manage': teamLock},
      },
    };

Map<String, Object?> _team() => {
      'success': true,
      'data': [
        {
          'id': _mid,
          'name': 'حيدر علي',
          'username': 'haider-1',
          'role': {'code': 'FieldWorker', 'label': 'عامل ميداني'},
          'is_main': false,
          'is_self': false,
          'wallet_limit': {'limited': false, 'amount': null},
          'last_login_at': '2026-11-01 10:00:00',
          'can_manage': true,
        },
        {
          'id': 'main-1',
          'name': 'المالك',
          'username': null,
          'username_masked': '•••4567',
          'role': {'code': 'Contractor', 'label': 'مشرف'},
          'is_main': true,
          'wallet_limit': null,
          'can_manage': false,
        },
      ],
      'total': 2,
      'page': 1,
      'size': 25,
      'page_count': 1,
    };

Map<String, Object?> _meta() => {
      'success': true,
      'data': {
        'roles': [
          {'id': _roleField, 'code': 'FieldWorker', 'label': 'عامل ميداني', 'description': 'العمل الميدانيّ', 'monetary': false, 'all_zones': false},
          {'id': _roleCash, 'code': 'Cash-Wallet', 'label': 'محفظة نقديّة', 'description': 'يدير التحويل بين المحافظ', 'monetary': true, 'all_zones': false},
          {'id': _roleAll, 'code': 'ZoneAdmin', 'label': 'مشرف منطقة', 'monetary': false, 'all_zones': true},
        ],
        'zones': [
          {'id': 'FBG2251-2', 'name': 'FBG2251-2'},
          {'id': 'FBG2260-5', 'name': 'FBG2260-5'},
        ],
        'password': {'min_length': 12, 'digits': 1, 'lower': 1, 'upper': 1, 'not_username': true},
        'password_assumed': false,
      },
    };

Future<void> _type(WidgetTester t, String label, String text) async {
  final f = find.descendant(of: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == label), matching: find.byType(TextField));
  await t.ensureVisible(f.first);
  await t.enterText(f.first, text);
  await t.pump();
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
  await t.pumpAndSettle();
}

void main() {
  test('الشروط والأرقام والعضو', () {
    const p = TeamPolicy(minLength: 12, digits: 1, lower: 1, upper: 1, notUsername: true);
    expect(p.ok('Abcdefgh1234', 'admin-54'), isTrue);
    expect(p.ok('abcdefgh1234', 'admin-54'), isFalse, reason: 'بلا حرفٍ كبير');
    expect(p.ok('Abcdefgh 1234', 'x'), isFalse, reason: 'بمسافة');
    expect(p.checks('Admin-54Admin', 'admin-54admin').last.ok, isFalse, reason: 'هي اسم المستخدم');
    expect(teamDigits('٠٧٧٠ ١٢٣-٤٥٦٧'), '07701234567');
    expect(teamPhoneOk.hasMatch('07701234567'), isTrue);
    final m = NationalTeamMember.fromJson(Map<String, dynamic>.from((_team()['data'] as List).first as Map));
    expect((m.id, m.canManage, m.isSelf, m.roleCode), (_mid, true, false, 'FieldWorker'));
    final meta = TeamMeta.fromJson(Map<String, dynamic>.from(_meta()['data'] as Map));
    expect((meta.roles.length, meta.roles[1].monetary, meta.roles[2].allZones, meta.zones.length, meta.policy.minLength), (3, true, true, 2, 12));
  });

  group('الشاشة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp(secure: {'auth.admin_id': 'watani:2963757', 'auth.admin_username': 'owner'});
      NationalSheetApi.debugReset();
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
    });
    tearDown(() {
      NationalSheetApi.debugReset();
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });

    void routes({bool canWrite = true, String? teamLock}) {
      server.reply('GET', '/api/v2/ftth/lookups', 200, _lookups(canWrite: canWrite, teamLock: teamLock));
      server.reply('GET', '/api/v2/ftth/team', 200, _team());
      server.reply('GET', '/api/v2/ftth/team/meta', 200, _meta());
      server.reply('GET', '/api/v2/ftth/team/username', 200, {'success': true, 'username': 'admin-54', 'taken': false});
      server.reply('POST', '/api/v2/ftth/team', 200, {'success': true, 'outcome': 'applied'});
      server.reply('PUT', '/api/v2/ftth/team/$_mid', 200, {'success': true, 'outcome': 'applied'});
      server.reply('DELETE', '/api/v2/ftth/team/$_mid', 200, {'success': true, 'outcome': 'applied'});
    }

    Future<void> open(WidgetTester t) async {
      await pumpSim(t, _v, home: (_) => const NationalTeamScreen());
      await _settle(t);
    }

    testWidgets('الإضافة: الاسم يُفحص، وكلمة السرّ بالشروط، والوظيفة والزون وحدّ المحفظة ⇒ POST واحد بجسمٍ بالضبط', (t) async {
      routes();
      await open(t);
      expect(find.text('إضافة عضو'), findsOneWidget);
      await t.tap(find.text('إضافة عضو'));
      await _settle(t);
      expect(find.text('إضافة عضو للفريق'), findsOneWidget);
      await _type(t, 'اسم المستخدم', 'admin-54');
      await t.pump(const Duration(milliseconds: 800));
      await _settle(t);
      expect(find.text('الاسم متاح'), findsOneWidget);
      await _type(t, 'رقم الهاتف', '07701234567');
      await _type(t, 'كلمة السرّ', 'Abcdefgh1234');
      await t.ensureVisible(find.text('محفظة نقديّة'));
      await t.tap(find.text('محفظة نقديّة'));
      await t.pumpAndSettle();
      expect(find.text('هذه الوظيفة تصرف مالاً من المحفظة'), findsOneWidget);
      await t.ensureVisible(find.text('FBG2260-5'));
      await t.tap(find.text('FBG2260-5'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('بحدّ'));
      await t.tap(find.text('بحدّ'));
      await t.pumpAndSettle();
      await _type(t, 'حدّ المحفظة بالدينار', '٢٠٠٠٠٠');
      await t.tap(find.text('إضافة العضو'));
      await _settle(t);
      expect(server.bodies('POST', '/api/v2/ftth/team').single, {
        'username': 'admin-54',
        'first_name': '',
        'last_name': '',
        'phone': '07701234567',
        'password': 'Abcdefgh1234',
        'role_id': _roleCash,
        'zone_ids': ['FBG2260-5'],
        'wallet': {'limited': true, 'amount': 200000},
      });
      expect(find.text('إضافة عضو للفريق'), findsNothing, reason: 'أُغلقت النافذة');
      await simDrain(t);
    });

    testWidgets('التعديل يرسل ما تغيّر وحده، والحذف بتأكيدٍ و{confirm:true}؛ والرئيسيّ بلا إدارة', (t) async {
      routes();
      await open(t);
      expect(find.byTooltip('إدارة العضو'), findsOneWidget, reason: 'الرئيسيّ بلا قائمة');
      await t.tap(find.byTooltip('إدارة العضو'));
      await t.pumpAndSettle();
      await t.tap(find.text('تعديل'));
      await _settle(t);
      expect(find.text('تعديل حيدر علي'), findsOneWidget);
      await _type(t, 'رقم الهاتف', '07709998877');
      await t.tap(find.text('حفظ التعديل'));
      await _settle(t);
      expect(server.bodies('PUT', '/api/v2/ftth/team/$_mid').single, {'phone': '07709998877'});
      await t.pump(const Duration(seconds: 5)); // إشعار «عُدّل العضو» يغطّي أسفل الشاشة حتى يختفي
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('إدارة العضو'));
      await t.pumpAndSettle();
      await t.tap(find.text('حذف'));
      await t.pumpAndSettle();
      expect(find.text('حذف «حيدر علي» من فريقك؟'), findsOneWidget);
      await t.tap(find.text('حذف').last);
      await _settle(t);
      expect(server.bodies('DELETE', '/api/v2/ftth/team/$_mid').single, {'confirm': true});
      await simDrain(t);
    });

    testWidgets('الموظّف، أو بلا كتابة، أو بلا صلاحيّة البوّابة: لا إضافة ولا إدارة', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: {'reports.financial': true});
      routes();
      await open(t);
      expect(find.text('إضافة عضو'), findsNothing);
      expect(find.byTooltip('إدارة العضو'), findsNothing);
      await simDrain(t);
    });

    testWidgets('صلاحيّة «إدارة أعضاء الفريق» مقفلةٌ بالبوّابة ⇒ لا إضافة', (t) async {
      routes(teamLock: 'لا صلاحيّة «إدارة أعضاء الفريق»');
      await open(t);
      expect(find.text('إضافة عضو'), findsNothing);
      await simDrain(t);
    });
  });
}
