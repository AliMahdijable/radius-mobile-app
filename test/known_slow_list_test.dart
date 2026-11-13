// الحساب المعروف ببطء قائمته (١٤ نوفمبر ٢٠٢٦ — المالك: «أوّل ٥٠ مشتركاً حيّين خلال ٣–٥ث والباقي وراهم»، ⛔ لا نسخة قديمة):
// يُحفظ عدد المشتركين وحده بحسب زمن القائمة الكاملة — ≥ ٣ث أو مهلة ⇒ بطيء، < ١٫٥ث ⇒ يُمسح، وبينهما لا تغيير.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/services/known_slow_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  var admin = 'ip-93-180-217-17:510';
  var clock = DateTime(2026, 11, 14, 1);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    admin = 'ip-93-180-217-17:510';
    clock = DateTime(2026, 11, 14, 1);
    KnownSlowList.adminId = () async => admin;
    KnownSlowList.now = () => clock;
  });

  test('قائمةٌ أخذت ٣ث فأكثر ⇒ يُعرف ببطئه بعدد مشتركيه؛ ثمّ قائمةٌ سريعة (< ١٫٥ث) تمسحه', () async {
    expect(await KnownSlowList.size(), isNull);
    await KnownSlowList.note(const Duration(milliseconds: 2999), 618);
    expect(await KnownSlowList.size(), isNull, reason: 'دون ٣ث لا يُعدّ بطئاً');
    await KnownSlowList.note(const Duration(seconds: 25), 618);
    expect(await KnownSlowList.size(), 618);
    await KnownSlowList.note(const Duration(milliseconds: 2000), 620);
    expect(await KnownSlowList.size(), 618, reason: 'بين ١٫٥ث و٣ث لا تغيير (لا تأرجح عند الحدّ)');
    await KnownSlowList.note(const Duration(milliseconds: 900), 620);
    expect(await KnownSlowList.size(), isNull, reason: 'السريعة تمسحه');
  });

  test('لم تصل في وقتها (null) ⇒ بطيءٌ بالعدد المعروف؛ عددٌ صفر أو كبير (≥ ٥٠٠٠) لا يُحفظ', () async {
    await KnownSlowList.note(null, 0);
    expect(await KnownSlowList.size(), isNull);
    await KnownSlowList.note(null, 5000);
    expect(await KnownSlowList.size(), isNull, reason: 'الكبير له طريقه (الصفحات) — لا قائمة كاملة بلا فحص');
    await KnownSlowList.note(null, 127);
    expect(await KnownSlowList.size(), 127);
  });

  test('لكلّ مديرٍ وحده، وينتهي بعد ٧ أيّام', () async {
    await KnownSlowList.note(const Duration(seconds: 20), 618);
    admin = 'ip-93-180-217-17:528';
    expect(await KnownSlowList.size(), isNull, reason: 'مديرٌ آخر');
    admin = 'ip-93-180-217-17:510';
    clock = clock.add(const Duration(days: 6, hours: 23));
    expect(await KnownSlowList.size(), 618);
    clock = clock.add(const Duration(hours: 2));
    expect(await KnownSlowList.size(), isNull, reason: 'أقدم من ٧ أيّام');
  });

  test('بلا هويّة لا قراءة ولا كتابة؛ والمخزّن تالف ⇒ كأنّه فارغ', () async {
    admin = '';
    await KnownSlowList.note(const Duration(seconds: 20), 618);
    expect(await KnownSlowList.size(), isNull);
    SharedPreferences.setMockInitialValues({'subs_known_slow_v1': '{not json'});
    admin = 'x:1';
    expect(await KnownSlowList.size(), isNull);
    await KnownSlowList.note(const Duration(seconds: 5), 40);
    expect(await KnownSlowList.size(), 40, reason: 'يُكتب من جديد فوق التالف');
  });

  test('ثلاثون حساباً على الأكثر — الأقدم يُرمى، ولا يُحفظ غير العدد والوقت', () async {
    for (var i = 0; i < 35; i++) {
      admin = 'co:$i';
      clock = clock.add(const Duration(minutes: 1));
      await KnownSlowList.note(const Duration(seconds: 9), 100 + i);
    }
    final p = await SharedPreferences.getInstance();
    final all = jsonDecode(p.getString('subs_known_slow_v1')!) as Map<String, dynamic>;
    expect(all.length, 30);
    expect(all.containsKey('co:0'), isFalse);
    expect(all.containsKey('co:34'), isTrue);
    expect((all['co:34'] as Map).keys.toSet(), {'size', 'at'});
  });
}
