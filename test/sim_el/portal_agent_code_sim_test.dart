import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/portal_settings/portal_settings_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// محاكاة «رمز الوكيل» في «بوابة المشترك» — كما يراها المدير والموظّف،
/// بالعروض الثلاثة وبالوضعين. اللقطات في `shots/portal_agent/`. السلوك نفسه
/// مفحوصٌ في `test/portal_agent_code_test.dart`؛ هنا الرسم: لا فيضان، ولا نصّ
/// خام، والأرقام الستّة كبيرةٌ متباعدة حتى ٣٢٠.
const _shot = 'portal_agent';

/// المتغيّر حبّةٌ مقصودة في التلميح — الأقواس جزءٌ منه لا أثرٌ تقنيّ.
final _allowVariable = [RegExp(r'^\{agent_code\}$')];

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  Future<void> sas4() async {
    server = await simSetUp(secure: {'auth.admin_id': '2251'});
    ProviderService.debugSet(null);
  }

  Future<void> earthlink() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
  }

  void settings({bool enabled = true, Object? code = '402917'}) =>
      server.reply('GET', '/api/v2/portal/settings', 200,
          {'success': true, 'enabled': enabled, 'agent_code': code});

  void logins() {
    final now = DateTime.now().toUtc();
    String ago(Duration d) => now.subtract(d).toIso8601String();
    server.reply('GET', '/api/v2/portal/logins', 200, {
      'success': true,
      'data': [
        {'at': ago(const Duration(minutes: 4)), 'username_lc': 'ali.abbas@popq', 'via': 'qr', 'result': 'ok'},
        {'at': ago(const Duration(minutes: 38)), 'username_lc': 'noor.alhuda@popq', 'via': 'pw', 'result': 'bad_password'},
        {'at': ago(const Duration(hours: 5)), 'username_lc': 'hassan.k@popq', 'via': 'pw', 'result': 'ok'},
        // أطول حبّة («البوابة غير متاحة») بجانب يوزرٍ طويل — امتحان ٣٢٠.
        {'at': ago(const Duration(hours: 8)), 'username_lc': 'mustafa.alobaidi@popq', 'via': 'qr', 'result': 'portal_unavailable'},
        {'at': ago(const Duration(hours: 30)), 'username_lc': 'm.jawad@popq', 'via': 'pw', 'result': 'pw_unverifiable'},
        {'at': ago(const Duration(days: 3)), 'username_lc': 'sara', 'via': null, 'result': 'portal_disabled'},
      ],
    });
  }

  Future<void> open(WidgetTester t, SimVariant v) =>
      pumpSim(t, v, home: (_) => const PortalSettingsScreen());

  simCase(_shot, 'owner', (t, v) async {
    await sas4();
    PermissionsService.debugSet(isEmployee: false);
    settings();
    logins();
    await open(t, v);
    expect(find.text('تغيير الرمز'), findsOneWidget);
    await simCheck(t, v, _shot, 'owner', allow: _allowVariable);
  });

  simCase(_shot, 'owner_logins', (t, v) async {
    await sas4();
    PermissionsService.debugSet(isEmployee: false);
    settings();
    logins();
    await open(t, v);
    await t.drag(find.text('تفعيل بوابة مشتركيّ'), const Offset(0, -420));
    await t.pumpAndSettle();
    expect(simText('noor.alhuda@popq'), findsOneWidget);
    await simCheck(t, v, _shot, 'owner_logins', allow: _allowVariable);
  });

  simCase(_shot, 'paused', (t, v) async {
    await sas4();
    PermissionsService.debugSet(isEmployee: false);
    settings(enabled: false);
    server.reply('GET', '/api/v2/portal/logins', 200, {'success': true, 'data': []});
    await open(t, v);
    expect(find.text('البوابة موقوفة — مشتركوك ما يقدرون يدخلون'),
        findsOneWidget);
    await simCheck(t, v, _shot, 'paused', allow: _allowVariable);
  });

  simCase(_shot, 'employee', (t, v) async {
    await sas4();
    PermissionsService.debugSet(isEmployee: true);
    settings();
    await open(t, v);
    expect(find.text('تغيير الرمز'), findsNothing);
    expect(server.calls('GET', '/api/v2/portal/logins'), isEmpty);
    await simCheck(t, v, _shot, 'employee', allow: _allowVariable);
  });

  simCase(_shot, 'el_employee', (t, v) async {
    await earthlink();
    PermissionsService.debugSet(
        isEmployee: true, permissions: const {'subscribers.view': true});
    settings(code: '018342');
    logins();
    await open(t, v);
    expect(find.byType(TabBar), findsNothing);
    await simCheck(t, v, _shot, 'el_employee', allow: _allowVariable);
  });

  simCase(_shot, 'unavailable', (t, v) async {
    await sas4();
    PermissionsService.debugSet(isEmployee: false);
    settings(code: null);
    server.reply('GET', '/api/v2/portal/logins', 200, {'success': true, 'data': []});
    await open(t, v);
    expect(find.text('رمز الوكيل غير متاح لحسابك بعد'), findsOneWidget);
    await simCheck(t, v, _shot, 'unavailable');
  });

  simCase(_shot, 'load_failed', (t, v) async {
    await sas4();
    PermissionsService.debugSet(isEmployee: false);
    server.on('GET', '/api/v2/portal/settings', simTimeout);
    server.on('GET', '/api/v2/portal/logins', simTimeout);
    await open(t, v);
    expect(find.text('تعذّر تحميل رمز الوكيل — تحقّق من الاتصال'),
        findsOneWidget);
    await simCheck(t, v, _shot, 'load_failed');
  });

  simCase(_shot, 'rotate_confirm', (t, v) async {
    await sas4();
    PermissionsService.debugSet(isEmployee: false);
    settings();
    logins();
    await open(t, v);
    await t.tap(find.text('تغيير الرمز'));
    await t.pumpAndSettle();
    expect(find.text('تغيير رمز الوكيل؟'), findsOneWidget);
    await simCheck(t, v, _shot, 'rotate_confirm', allow: _allowVariable);
  });

  simCase(_shot, 'el_info_unsupported', (t, v) async {
    await earthlink();
    PermissionsService.debugSet(isEmployee: false);
    settings(code: '018342');
    logins();
    const safeEmpty = {
      'success': true,
      'data': null,
      'items': <Object>[],
      'value': null,
      'total': 0,
    };
    server.reply('GET', '/api/v2/admin/branding', 200, safeEmpty);
    await open(t, v);
    await t.tap(find.text('معلومات الشركة'));
    await t.pumpAndSettle();
    expect(find.text('تخصيص معلومات الشركة غير متوفّر لشركتك بعد'),
        findsOneWidget);
    await simCheck(t, v, _shot, 'el_info_unsupported');
  });
}
