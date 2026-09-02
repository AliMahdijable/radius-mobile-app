import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/wa_contact_risk.dart';

/// حارس واتساب — طلب المستخدم ٢٠٢٦-٠٩-٠٢: تنبيهٌ قبل مراسلة من لم
/// يسبق أن راسلك، لأنّ ذلك يعرّض الجلسة للحظر.
void main() {
  group('مطابقة الرقم', () {
    test('🚨 بآخر تسع خانات لا حرفيّاً', () {
      // الخادم يُعيد 9647XXXXXXXXX بينما الواجهة تحمل +964 770 … أو
      // 0770…. والمطابقة الحرفيّة تُسقط الحارس صامتاً — أسوأ من غيابه،
      // لأنّه يبدو عاملاً.
      const m = {'9647701234567': WaContactRisk(tier: WaRiskTier.confirm, ignored: 8)};
      for (final form in [
        '9647701234567',
        '+964 770 123 4567',
        '07701234567',
        '00964 7701234567',
        '٧٧٠١٢٣٤٥٦٧',
      ]) {
        expect(WaContactRiskApi.riskFor(m, form).tier, WaRiskTier.confirm,
            reason: 'لم يُطابق: $form');
      }
    });

    test('رقمٌ آخر لا يُطابق', () {
      const m = {'9647701234567': WaContactRisk(tier: WaRiskTier.confirm)};
      expect(WaContactRiskApi.riskFor(m, '07709999999').tier, WaRiskTier.safe);
    });
  });

  group('التعذّر آمنٌ لا خطر', () {
    test('🚨 الافتراضيّ عند فشل السؤال = safe', () {
      // عجزُ الشبكة ليس دليلَ خطر. وتحذيرٌ بلا أساس يُفقد التحذيراتِ
      // كلَّها قيمتَها — ويُعطّل إرسالاً مشروعاً.
      expect(WaContactRisk.unknown.tier, WaRiskTier.safe);
      expect(WaContactRiskApi.riskFor(const {}, '0770123').tier,
          WaRiskTier.safe);
    });
  });

  group('اللافتة متناسبة', () {
    late String src;
    setUpAll(() =>
        src = File('lib/widgets/manual_wa_chip.dart').readAsStringSync());

    test('🚨 الآمن لا يرى شيئاً', () {
      expect(src.contains('case WaRiskTier.safe:\n        return const SizedBox.shrink();'),
          isTrue, reason: 'تحذيرٌ لمن بادرك = ضجيج محض');
    });

    test('🚨 التنبيه سطرٌ لا نافذة', () {
      // ٦٠٪ من الرسائل تذهب إلى من لم يراسل. نافذةٌ في ستّ حالاتٍ من
      // عشر تُعتاد خلال يومين فتصير ضغطةً آليّة.
      expect(src.contains("'لم يسبق أن راسلك — الإرسال متاح'"), isTrue);
      final i = src.indexOf('case WaRiskTier.notice:');
      final j = src.indexOf('case WaRiskTier.confirm:');
      final notice = src.substring(i, j);
      expect(notice.contains('showDialog'), isFalse);
      expect(notice.contains('AppColors.dangerSoftBg'), isFalse,
          reason: 'التنبيه لا يُصبَغ بلون الخطر');
    });

    test('🚨 التأكيد يذكر الرقم لا يعظ', () {
      // «أرسلتَ له ٨ رسائل ولم يردّ» يُقنع؛ «انتبه قد تُحظر» يُتجاهل.
      expect(src.contains(r'أرسلتَ له ${risk.ignored} رسالة'), isTrue);
      expect(src.contains('وبلاغٌ واحد يكفي'), isTrue);
    });

    test('وزرّ الإرسال يفقد بريقه لا وظيفته', () {
      // المنع الصارم يُسكت ٦٠٪ من النظام — إشعارات الانتهاء والتفعيل
      // والديون كلّها. فالزرّ يبقى، ويكفّ عن كونه الخيار البديهيّ.
      expect(src.contains('_risk.tier == WaRiskTier.confirm'), isTrue);
      expect(src.contains('? AppColors.textMid'), isTrue);
    });

    test('لا ينتظر الاستعلام قبل السماح', () {
      // تأخيرُ زرٍّ بانتظار استعلامٍ ثانويّ يُفسد كلّ إرسالٍ لأجل تحذيرٍ
      // يخصّ واحداً من كلّ سبعين.
      expect(src.contains('WaContactRisk _risk = WaContactRisk.unknown;'),
          isTrue);
    });
  });
}
