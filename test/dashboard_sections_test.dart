import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// أقسام الرئيسيّة — الإخفاء يُسقط النداء لا الرسم فقط.
///
/// الميزة (طلب المستخدم): «الداش بورد يقدر يتحكّم بشنو يظهر». والفائدة
/// الحقيقيّة ليست ترتيب الشاشة بل **سرعة الإقلاع**: القسم المخفيّ
/// يُسقط نداءه، فمن يُخفي الإيرادات والنشاطات يسقط عنه نداءان من خمسة
/// عند كلّ فتح.
///
/// حارس مصدريّ: الشاشة تحتاج شبكةً وتوكناً فلا يبلغها اختبار سلوكيّ،
/// والخاصّية المحروسة بنيويّة — أين يقع الشرط، لا ماذا يُرسَم.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/screens/dashboard/dashboard_screen.dart').readAsStringSync();
  });

  const sections = ['subscribers', 'wallet', 'revenue', 'activities', 'wa_banner'];

  test('كلّ قسم مبوَّب في الرسم', () {
    for (final s in sections) {
      expect(src.contains("_shown('$s')"), isTrue,
          reason: 'القسم $s غير مبوَّب — يظهر مهما أخفاه المدير');
    }
  });

  test('التبويب يسبق النداء لا يتبعه', () {
    // ⚠️ جوهر الميزة: لو وقع الشرط بعد الجلب لصار إخفاءً بصريّاً
    // يكلّف نفس الشبكة — وهذا نقيض الغاية.
    for (final call in [
      'DashboardApi.fetchWhatsAppStatus()',
      'DashboardApi.fetchDailyActivations()',
      'DashboardApi.fetchWallet()',
    ]) {
      final i = src.indexOf(call);
      expect(i, greaterThan(0), reason: 'لم يُعثر على $call');
      // الشرط في الأسطر الثلاثة السابقة للنداء
      final before = src.substring((i - 220).clamp(0, i), i);
      expect(before.contains('_shown('), isTrue,
          reason: '$call يُطلَق بلا تبويب — الإخفاء لن يوفّر شيئاً');
    }
  });

  test('حالة «كلّ شيء مخفيّ» معالَجة', () {
    expect(src.contains('_AllHidden'), isTrue,
        reason: 'بلا هذا تصير الشاشة بيضاء ويظنّها المدير معطوبة');
  });

  test('قبل وصول التفضيلات كلّ شيء ظاهر', () {
    // الخطأ في هذا الاتّجاه أرحم: قسمٌ يظهر لحظةً أهون من شاشة تومض
    // فارغةً عند كلّ فتح.
    expect(src.contains('!_sectionsLoaded || !_hiddenSections.contains'), isTrue,
        reason: 'بلا هذا تومض الشاشة فارغةً قبل وصول التفضيلات');
  });

  test('مفاتيح العميل تطابق الخادم', () {
    final server = File('../server.js').existsSync()
        ? File('../server.js').readAsStringSync()
        : File('/home/ali/MyServices Raduis/server.js').readAsStringSync();
    final db = File('/home/ali/MyServices Raduis/database/db.js').readAsStringSync();
    for (final s in sections) {
      expect(db.contains("'$s'"), isTrue,
          reason: 'المفتاح $s غير معرَّف في DASHBOARD_SECTIONS — '
              'الخادم سيرفض حفظه');
    }
    expect(server.contains('DASHBOARD_SECTIONS'), isTrue);
  });
}
