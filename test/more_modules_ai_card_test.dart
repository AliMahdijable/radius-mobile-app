import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/self_deposit_api.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/screens/top_actions.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/ai_consent.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «كيف أسوّي؟» صار زرّاً في الأعلى بكلّ التبويبات (TopActions — test/top_actions_test.dart)، فـ«قوائم أخرى»
/// لا تحمل بطاقته بأيّ حال (المالك ٢٠ أكتوبر: «ماله لزوم ليش مخليها بالقوائم الاخرى احنه ضفناها بالاعلى»)،
/// والمساعد فيها زرّ الأعلى وحده (رأس التبويب) بسؤال حالةٍ واحد.
void main() {
  const v = SimVariant(390, dark: false);
  const statusPath = '/api/v2/ai/status';
  late SimServer server;

  setUpAll(simSetUpAll);

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
    SelfDepositState.reset();
    AiAssistantState.reset();
    AiConsent.debugReset();
  });

  Future<void> setUpActor(
      {String adminId = '2251',
      String? provider,
      bool employee = false}) async {
    server = await simSetUp(secure: {'auth.admin_id': adminId});
    ProviderService.debugSet(provider);
    PermissionsService.debugSet(isEmployee: employee);
    SelfDepositState.reset();
    AiAssistantState.reset();
    AiConsent.debugAccepted = true;
  }

  const on = {
    'success': true,
    'enabled': true,
    'can_use': true,
    'explain': true,
    'ask': true,
    'quota': {'left': 7, 'limit': 10},
    'suggestions': ['شلون أفعّل مشترك بالكارت؟'],
  };
  const locked = {
    'success': true,
    'enabled': true,
    'can_use': false,
    'reason': 'no_permission',
    'locked_text': 'ما عندك صلاحيّة المساعد — اطلبها من مديرك',
  };
  const off = {'success': true, 'enabled': false};

  for (final c in [
    ('مفتوح', '2251', null, false, on),
    ('مالك ايرث لنك', 'earthlink:5', 'earthlink', false, on),
    ('موظّفٌ بلا الصلاحيّة', '2251', null, true, locked),
    ('مطفأ', '2251', null, false, off),
  ]) {
    testWidgets(
        '${c.$1} ⇒ لا بطاقة «كيف أسوّي؟» في «قوائم أخرى» — المساعد زرّ الأعلى وحده',
        (t) async {
      await setUpActor(adminId: c.$2, provider: c.$3, employee: c.$4);
      server.reply('GET', statusPath, 200, c.$5);
      await pumpSim(t, v, home: (_) => const MoreModulesScreen());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('كيف أسوّي؟', skipOffstage: false), findsNothing,
          reason: 'لا بطاقة «كيف أسوّي؟» بين البطاقات');
      // المساعد وحده زرّ الأعلى (TopActions في رأس التبويب) — لا أيقونة مساعدٍ خارجه.
      final all = find.byIcon(LucideIcons.sparkles, skipOffstage: false);
      final top = find.descendant(
          of: find.byType(TopActions, skipOffstage: false),
          matching: find.byIcon(LucideIcons.sparkles, skipOffstage: false));
      expect(all.evaluate().length, top.evaluate().length,
          reason: 'لا مساعد خارج زرّ الأعلى');
      expect(server.calls('GET', statusPath).length, lessThanOrEqualTo(1),
          reason: 'سؤال حالةٍ واحد على الأكثر — زرّ الأعلى يملكه');
    });
  }
}
