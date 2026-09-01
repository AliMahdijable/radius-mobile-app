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

  // ── بلاغ 2026-09-01: «خفّيتهن كلهن وماكو شي تغيّر» ──
  //
  // الخادم كان يحفظ الأقسام الخمسة صحيحةً (تحقّقتُ من الجدول)، والعطل
  // كلّه في التطبيق: قراءةٌ واحدة عند الإنشاء، وترتيبٌ يجعل أوّل جلب
  // يسبق وصول التفضيلات.

  test('الأقسام تُقرأ قبل أوّل جلب لا بعده', () {
    // لو انطلق `_refreshLive` قبل `_loadSections` لخرجت النداءات كلّها
    // في أوّل فتح ثمّ أُخفيت نتائجها — إخفاءٌ بصريّ بكلفة كاملة.
    expect(
      RegExp(r'_loadSections\(\)\s*\.then\(\(_\)\s*\{\s*if \(mounted\) _refreshLive')
          .hasMatch(src),
      isTrue,
      reason: 'أوّل جلب غير مقيَّد بوصول الأقسام',
    );
    expect(
      RegExp(r'^\s*_refreshLive\(silent: false\);', multiLine: true).hasMatch(src),
      isFalse,
      reason: 'بقي جلب غير مقيَّد — يسبق التفضيلات',
    );
  });

  test('تبدّل النطاق يبلغ الرئيسيّة وهي مركَّبة', () {
    // الرئيسيّة تعيش في `IndexedStack` طوال الجلسة، فلا `initState`
    // ثانٍ ينقل إليها تبديل الإعدادات. الإشارة هي الجسر الوحيد.
    expect(src.contains('ViewScopeEvents.changed.addListener'), isTrue,
        reason: 'الرئيسيّة لا تسمع تبدّل النطاق');
    expect(src.contains('ViewScopeEvents.changed.removeListener'), isTrue,
        reason: 'مستمع بلا فكّ — تسرّب');
    final scope = File('lib/screens/view_scope_screen.dart').readAsStringSync();
    expect(RegExp(r'notifyChanged\(\)').allMatches(scope).length, greaterThanOrEqualTo(2),
        reason: 'الإشارة تُطلق في مفاتيح الأقسام والمدراء كليهما');
  });

  test('تحديث صامت مبرَّد والسحب-للتحديث معفى', () {
    // أربعة مصادر تحديث قد تتلاقى؛ والسحب يجب أن يستجيب دائماً وإلّا
    // بدا المؤشّر يدور بلا أثر.
    expect(src.contains('if (silent) {'), isTrue);
    expect(RegExp(r'if \(silent\) \{\s*\n\s*if \(_cooling\) return;').hasMatch(src), isTrue,
        reason: 'التبريد يجب أن يقيّد الصامت وحده');
  });
}
