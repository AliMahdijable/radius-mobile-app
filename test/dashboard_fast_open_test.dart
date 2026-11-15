// حارس سرعة الرئيسيّة ودقّتها (١٦ نوفمبر ٢٠٢٦ — المالك: «ابدأ بالأول والثاني وسوي محاكاة بحيث تضمن دقه المعلومات والسرعه»).
//
// على المحاكي المعايَر (test/sim/dashboard_sim.dart — كود 185 فيه يطابق القياس الحيّ: المشتركون ٢٫٢٢ث مقابل ٢٫٢٥ث):
//   ١٨٥ (قبل)  : دافئ ٢٫٢٢ث · ساسٌ بارد ٧٫٠٢ث · أوّل فتح بارد ٧٫٠٢ث — والفحص قبل القائمة في كلّ فتح.
//   الآن (بعد): دافئ ١٫٨٤ث · ساسٌ بارد ٣٫٩٠ث · أوّل فتح بارد ٦٫٨٨ث — بلا فحصٍ للحساب المعروف.
// مقيسٌ بالمحاكي نفسه: ① وحده (بلا ②) دافئ ٢٫٠٠ث وبارد ٤٫٠٢ث، و② وحده ٢٫٠٦ث و٦٫٨٨ث — فالحدود أدناه تحمرّ إن سقط أيٌّ منهما
// (اختبار الطفرات ١٦ نوفمبر: ١٠/١٠ حرّاساً يُلتقطون).
// والأرقام المعروضة هي الحقيقة من قائمة هذا الفتح الحيّة، ولا قائمة كاملة لحسابٍ كبير أبداً.
import 'package:flutter_test/flutter_test.dart';

import 'sim/dashboard_sim.dart';

void main() {
  setUpAll(() async => visualSetUpAll());

  Future<Run> open(WidgetTester t, Profile p) async {
    final r = await simulate(t, p, 0);
    final v = violations(r, big: p.bigTotal != null);
    expect(v, isEmpty, reason: v.join(' · '));
    return r;
  }

  testWidgets('فتحٌ والساس دافئ (الحساب معروف): الأرقام ≤ ١٫٩ث بلا فحص', (t) async {
    final r = await open(t, const Profile('warm_reopen', warm));
    expect(r.checks['probe_requests'], 0, reason: 'سُئل الساس «هل الحساب كبير؟» والحساب معروفٌ صغيراً');
    expect(r.m['subs']!, lessThanOrEqualTo(1.90), reason: 'أرقام المشتركين ${r.m['subs']}ث (١٨٥: ٢٫٢٢ث)');
    expect(r.m['all']!, lessThanOrEqualTo(2.10), reason: 'الرئيسيّة كاملة ${r.m['all']}ث (١٨٥: ٢٫٤٠ث)');
    expect((r.checks['stats'] as Map)['total'], fixtureSubscribers.length);
  });

  testWidgets('فتحٌ والساس بارد (أوّل الصباح): الأرقام ≤ ٣٫٩٥ث (كانت ٧٫٠٢ث)', (t) async {
    final r = await open(t, const Profile('cold_reopen', cold));
    expect(r.checks['probe_requests'], 0);
    expect(r.m['subs']!, lessThanOrEqualTo(3.95), reason: 'أرقام المشتركين ${r.m['subs']}ث');
    expect(r.m['wallet']!, lessThanOrEqualTo(4.15), reason: 'الرصيد ${r.m['wallet']}ث (١٨٥: ٧٫٢ث)');
  });

  testWidgets('أوّل فتحٍ على الجهاز: الفحص قبل القائمة كما كان — ولا أبطأ من ١٨٥', (t) async {
    final r = await open(t, const Profile('cold_first_open', cold, storedSmall: false));
    expect(r.checks['probe_requests'], 1, reason: 'حسابٌ مجهول يجب أن يُسأل عنه الساس');
    expect(r.m['subs']!, lessThanOrEqualTo(7.02), reason: 'أبطأ من 185');
  });

  testWidgets('حسابٌ كبير: لا قائمة كاملة أبداً — بحكمٍ محفوظ أو بلا', (t) async {
    for (final stored in [false, true]) {
      final r = await open(t, Profile('big', warm, storedSmall: stored, bigTotal: 89177));
      expect(r.checks['list_requests'], 0);
      expect(r.checks['probe_requests'], 1, reason: 'الكبير يُسأل الساس دائماً');
    }
  });
}
