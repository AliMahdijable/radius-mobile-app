// معاينة «تنبيه المشترك» تذكر كلّ الأسطر (٦ نوفمبر — المالك: «والمعاينه اذكر كلشي بيها»): الكيبل والإشارة وCCQ والضوئيّ والحرارة
// والفولتيّة، بأمثلةٍ تتجاوز حدود الوكيل؛ واسم المشترك بالمعاينة يتبع «الاسم بالعربي / اليوزر».
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/screens/whatsapp/connection_alerts_screen.dart';

import 'support/ai_status_overlay.dart';
import 'visual_perm/visual_perm_harness.dart';

void main() {
  setUpAll(visualSetUpAll);

  testWidgets('المعاينة: الأسطر الستّة كلّها، والاسم بالعربي ثمّ اليوزر', (t) async {
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
      'فولتيّة جهاز الفايبر غير طبيعيّة',
    ]) {
      expect(text(), contains(line), reason: line);
    }
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
    await t.pumpWidget(const SizedBox());
    await visualTearDown();
  });
}
