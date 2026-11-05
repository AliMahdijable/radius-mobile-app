// معاينة «تنبيه المشترك» تذكر كلّ الأسطر (٦ نوفمبر — المالك: «والمعاينه اذكر كلشي بيها»): الكيبل والإشارة وCCQ والضوئيّ والحرارة،
// بأمثلةٍ تتجاوز حدود الوكيل (فولتيّة موديول الضوء أُخرجت ٦ نوفمبر)؛ واسم المشترك يتبع «الاسم بالعربي / اليوزر / الاثنين معاً».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/whatsapp/connection_alerts_screen.dart';

import 'support/ai_status_overlay.dart';
import 'visual_perm/visual_perm_harness.dart';

void main() {
  setUpAll(visualSetUpAll);

  testWidgets('المعاينة: الأسطر الخمسة كلّها بلا فولتيّة، والاسم بالعربي ثمّ اليوزر ثمّ الاثنين معاً', (t) async {
    final inner = await visualSetUp(s1bSasOwner);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner, status: aiStatusOff, routes: {
      'GET /api/v2/connection-alerts/settings': {
        'success': true,
        'data': {'enabled': true, 'signal_dbm': -60, 'ccq_pct': 50, 'fiber_rx_dbm': -27, 'fiber_temp_c': 70, 'name_mode': 'name', 'is_default': false},
      },
    });
    await pumpVisual(t, phone, home: (_) => const ConnectionAlertsScreen());
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final preview = find.byKey(const ValueKey('ca-preview-text'));
    await t.scrollUntilVisible(preview, 300, scrollable: find.byType(Scrollable).first);
    String text() => (t.widget<Text>(preview).data ?? '');
    for (final line in [
      'يوجد خلل بكيبل الإنترنت',
      'الإشارة ضعيفة',
      'جودة الربط منخفضة',
      'الإشارة الضوئيّة ضعيفة',
      'حرارة جهاز الفايبر مرتفعة',
    ]) {
      expect(text(), contains(line), reason: line);
    }
    expect(text(), isNot(contains('فولتيّة')), reason: 'لا سطر لفولتيّة موديول الضوء');
    expect(text(), contains('محمد علي'));
    final user = find.byKey(const ValueKey('ca-name-username'));
    await t.ensureVisible(user);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(user);
    await t.pump();
    expect(t.widget<ChoiceChip>(user).selected, isTrue);
    await t.scrollUntilVisible(preview, 300, scrollable: find.byType(Scrollable).first);
    expect(text(), contains('mohammed.ali'), reason: 'اليوزر بدل الاسم');
    expect(text(), isNot(contains('محمد علي')));
    final both = find.byKey(const ValueKey('ca-name-both'));
    await t.ensureVisible(both);
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(both);
    await t.pump();
    expect(t.widget<ChoiceChip>(both).selected, isTrue);
    await t.scrollUntilVisible(preview, 300, scrollable: find.byType(Scrollable).first);
    expect(text(), contains('محمد علي (mohammed.ali)'), reason: 'الاثنين معاً');
    await t.pumpWidget(const SizedBox());
    await visualTearDown();
  });
}
