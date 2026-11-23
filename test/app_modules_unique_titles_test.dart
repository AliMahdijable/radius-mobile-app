import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/tickets_api.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «قوائم أخرى» بلا بطاقتين باسمٍ واحد — لكلّ مزوّد، لصاحب الحساب وللموظّف (المالك ٢٣ نوفمبر: بصفحة الوطنيّ كانت «التذاكر»
/// مرّتين — دعم بوّابة الوطنيّ `national_tickets` وتذاكر المشتركين `tickets` — فصارت الثانية «تذاكر المشتركين»: «اي سمّيها
/// تذاكر المشتركين»). بطاقةٌ جديدة باسم بطاقةٍ موجودة تسقط هنا.
void main() {
  setUpAll(simSetUpAll);
  tearDown(() {
    ProviderService.debugSet(null);
    PermissionsService.debugReset();
    TicketsState.reset();
  });

  testWidgets('لا اسمان متطابقان في «قوائم أخرى» — كلّ مزوّد، المدير والموظّف', (t) async {
    await simSetUp(secure: {'auth.admin_id': 'x:1', 'auth.admin_username': 'boss'});
    await pumpSim(t, const SimVariant(390, dark: false), home: (_) => const Scaffold(body: SizedBox()));
    var checked = 0;
    for (final employee in [false, true]) {
      PermissionsService.debugSet(
          isEmployee: employee, permissions: employee ? const {'subscribers.view': true, 'tickets.view': true} : const <String, bool>{});
      for (final p in <String?>[null, 'sas4', 'earthlink', 'ftth', 'fiberx', 'watani', 'nabd']) {
        ProviderService.debugSet(p, label: p == 'watani' ? 'المشروع الوطني' : null);
        // قسم تذاكر المشتركين متاحٌ للحساب ⇒ بطاقته حاضرة (حيث يخدمها المزوّد)
        TicketsState.debugSet(TicketsAccess.fromJson(const {
          'success': true,
          'available': true,
          'can_view': true,
          'can_reply': true,
          'counts': {'open': 0, 'answered': 0, 'closed': 0, 'unread': 0, 'total': 0},
        }));
        final byTitle = <String, List<String>>{};
        for (final m in buildAppModules()) {
          (byTitle[m.title] ??= []).add(m.id);
        }
        final dups = {for (final e in byTitle.entries) if (e.value.length > 1) e.key: e.value};
        expect(dups, isEmpty, reason: 'المزوّد ${p ?? 'sas4 (الرئيسيّ)'} — ${employee ? 'موظّف' : 'صاحب الحساب'}');
        checked++;
      }
    }
    expect(checked, 14);
    // الوطنيّ نفسه: البطاقتان حاضرتان باسمين
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet('watani', label: 'المشروع الوطني');
    final ids = {for (final m in buildAppModules()) m.id: m.title};
    expect([ids['national_tickets'], ids['tickets']], ['التذاكر', 'تذاكر المشتركين']);
    await simDrain(t);
  });
}
