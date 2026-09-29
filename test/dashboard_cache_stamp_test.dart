import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/dashboard_api.dart';
import 'package:rad_mysvcs/services/dashboard_cache.dart';

/// حارس ختم المدير على كاش المحفظة.
///
/// ── لماذا حارسٌ على رقمين ────────────────────────────────────────
/// `dash.cache.wallet` كان مفتاحاً عامّاً بلا وسم، ويُمسح عند الخروج
/// وحده. والمسح حزامٌ واحد: هويّةٌ تصل من جهازٍ آخر عبر iCloud Keychain
/// (`AuthStorage` تضع `synchronizable: true`) لا تمرّ بخروجٍ ولا بدخول،
/// فلا شيء يمسح تفضيلات هذا الجهاز — ويُعرض رصيدُ مديرٍ لمديرٍ آخر.
///
/// الاختبار على [DashboardCache.decodeFor] لا على `readWallet`: الثانية
/// تمرّ بقناتين أصليّتين لا تعملان في `flutter test`، والأولى هي كلّ
/// المنطق الذي يحرس العزل. فما يُحرَس هو القرار نفسه: **مَن صاحب هذا
/// الرقم؟**
void main() {
  String stamped(String adminId, {num balance = 250000, num points = 7}) =>
      jsonEncode({
        'v': 1,
        'adminId': adminId,
        'w': {'balance': balance, 'points': points},
      });

  test('ختمُ صاحبه ⇒ الرقم يعود كما كُتب', () {
    final WalletResult? w = DashboardCache.decodeFor(stamped('2'), '2');
    expect(w, isNotNull, reason: 'الكاش صار بلا فائدة لو رُفض صاحبه');
    expect(w!.balance, 250000);
    expect(w.points, 7);
  });

  test('ختمُ غيره ⇒ لا شيء — وهذا كلّ الغرض', () {
    expect(DashboardCache.decodeFor(stamped('2'), '9'), isNull);
    expect(DashboardCache.decodeFor(stamped('9'), '2'), isNull);
  });

  test('الشكل القديم (بلا ختم) يُرمى ولا يُترقّى', () {
    // ما كتبته النسخ السابقة حرفيّاً: رقمان في الجذر بلا نسبة لأحد.
    const legacy = '{"balance":250000,"points":7}';
    expect(DashboardCache.decodeFor(legacy, '2'), isNull,
        reason: 'حمولةٌ لا تُنسب لمديرٍ لا يجوز أن تُقرأ لمدير');
  });

  test('معرّفان من ساسين لا يتصادمان', () {
    // `server/sasIdentity.js`: بلا نقطتين = الساس الأصليّ. المدير ٢ هناك
    // غير المدير ٢ هنا، والختم يأخذ المعرّف كما أرسله الخادم فيرث تمييزه.
    expect(DashboardCache.decodeFor(stamped('krb:2'), '2'), isNull);
    expect(DashboardCache.decodeFor(stamped('2'), 'krb:2'), isNull);
    expect(DashboardCache.decodeFor(stamped('krb:2'), 'krb:2'), isNotNull);
  });

  test('معرّفٌ فارغ لا يفتح الباب لأحد', () {
    // `AuthApi` يقبل `''` حين لا يردّ الساس معرّفاً — ولو قُبل الفارغ
    // لتطابق مع كلّ فارغٍ آخر، أي مع مديرٍ مجهولٍ ثانٍ.
    expect(DashboardCache.decodeFor(stamped(''), ''), isNull);
    expect(DashboardCache.decodeFor(stamped('2'), ''), isNull);
  });

  test('التالف يُرفض ولا يرمي', () {
    for (final raw in const ['ليست JSON', '[]', '{}', '{"adminId":"2"}']) {
      expect(DashboardCache.decodeFor(raw, '2'), isNull, reason: raw);
    }
    // ختمٌ صحيح وحمولةٌ ليست كائناً
    expect(
      DashboardCache.decodeFor(
          jsonEncode({'v': 1, 'adminId': '2', 'w': 'x'}), '2'),
      isNull,
    );
  });
}
