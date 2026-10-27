import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart' show authExpiredSignal;
import 'package:rad_mysvcs/screens/account/account_gate_screen.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';

import 'visual_perm/visual_perm_harness.dart';

/// المالك ٢٧ أكتوبر (نسخة الماك): بعد انتهاء الجلسة «اكثر من ٢٠ مرّة انتهت الجلسة» والشاشات متداخلة لا تكتمل.
/// إشاراتٌ متلاحقة كانت تبدأ انتقالاً فوق انتقال (لا يُزال الغلاف أبداً) وطابوراً من الرسائل. الآن: مغادرةٌ
/// واحدة ورسالةٌ واحدة مهما تلاحقت الإشارات.
void main() {
  setUpAll(visualSetUpAll);

  testWidgets('🚨 عشرون إشارة متلاحقة ⇒ شاشة حسابٍ واحدة ورسالةٌ واحدة، والغلاف يُزال', (t) async {
    await visualSetUp(s1bSasOwner);
    try {
      await pumpVisual(t, phone, home: (_) => const MainShell());
      await settle(t, seconds: 2);
      expect(find.byType(MainShell), findsOneWidget);

      for (var i = 0; i < 20; i++) {
        authExpiredSignal.value = authExpiredSignal.value + 1;
        await t.pump(const Duration(milliseconds: 30));
      }
      await settle(t, seconds: 2);

      expect(find.byType(MainShell), findsNothing, reason: 'الغلاف أُزيل ولا يطلب شيئاً بعد');
      expect(find.byType(AccountGateScreen), findsOneWidget);
      expect(find.byType(SnackBar).evaluate().length, lessThanOrEqualTo(1));

      // الرسالة تذهب بعد مدّتها ولا يتبعها طابور.
      await settle(t, seconds: 6);
      expect(find.byType(SnackBar), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 25));
    } finally {
      await visualTearDown();
    }
  });
}
