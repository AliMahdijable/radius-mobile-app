import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/server_source.dart';

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

  final root = proServerRoot();
  test('مفاتيح العميل تطابق الخادم', skip: root == null ? serverSourceSkip : false, () {
    final server = File('$root/server.js').readAsStringSync();
    final db = File('$root/database/db.js').readAsStringSync();
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

  test('الأقسام تُقرأ قبل أوّل جلب لا بعده — عدا المشتركين (لا يتبعون الأقسام)', () {
    // لو انطلق `_refreshLive` قبل `_loadSections` لخرجت النداءات كلّها
    // في أوّل فتح ثمّ أُخفيت نتائجها — إخفاءٌ بصريّ بكلفة كاملة.
    //
    // ② (١٦ نوفمبر ٢٠٢٦): المشتركون وحدهم يسبقون الأقسام — طلبهم لم يكن مبوَّباً بقسمٍ قطّ (`subscribers.view` وحده: الحلقة
    // والمدينون والجرس)، فانتظارهم الأقسام ~١ث كان انتظاراً بلا فائدة. كلّ ما سواهم ما زال بعد الأقسام.
    final init = src.substring(src.indexOf('void initState()'), src.indexOf('void _onActiveChanged()'));
    final then = RegExp(r'_loadSections\(\)\.then\(\(_\) \{([\s\S]*?)\n    \}\);').firstMatch(init);
    expect(then, isNotNull, reason: 'أوّل جلب غير مقيَّد بوصول الأقسام');
    final afterSections = then!.group(1)!;
    expect(afterSections.contains('_refreshLive(silent: false)'), isTrue,
        reason: '«كل الشركات» وأوّل فتحٍ بلا المشتركين المبكّرين يمرّان بالجلب الكامل بعد الأقسام');
    expect(afterSections.contains('_refreshRestAfterSections()'), isTrue,
        reason: 'بقيّة الرئيسيّة (واتساب/نشاطات/رصيد) يجب أن تنتظر الأقسام');
    // قبل الأقسام: المشتركون وحدهم
    final beforeSections = init.substring(0, init.indexOf('_loadSections().then'));
    expect(beforeSections.contains('_refreshLive('), isFalse, reason: 'بقي جلب كامل غير مقيَّد — يسبق التفضيلات');
    expect(beforeSections.contains('_refreshRest('), isFalse, reason: 'بقيّة الرئيسيّة تسبق التفضيلات');
    expect(beforeSections.contains('_fetchSubscribers(silent: false)'), isTrue,
        reason: 'المشتركون لم يعودوا يبدؤون فوراً (②)');
    // والمشتركون لا يقرؤون الأقسام — وإلّا صار طلبهم قبلها قراءةً لتفضيلاتٍ لم تصل
    final subs = src.substring(src.indexOf('void _fetchSubscribers('), src.indexOf('void _refreshRestAfterSections()'));
    expect(subs.contains('_shown('), isFalse, reason: 'طلب المشتركين صار مبوَّباً بقسم — لا يجوز أن يسبق الأقسام');
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

  test('تحديث صامت مبرَّد يُؤجَّل والسحب-للتحديث معفى', () {
    // أربعة مصادر تحديث قد تتلاقى؛ والسحب (silent: false) يجب أن يستجيب
    // دائماً وإلّا بدا المؤشّر يدور بلا أثر — فالتبريد كلّه داخل
    // `if (silent)`، وما دونه يتخطّاه.
    expect(src.contains('if (silent) {'), isTrue);
    expect(src.contains('if (_cooling) {'), isTrue,
        reason: 'التبريد يجب أن يقيّد الصامت وحده');
    // ⚠️ المبرَّد لا يُسقَط بل يُؤجَّل: عمليّةٌ حسّاسةٌ وقعت أثناء التبريد
    // يجب أن تنعكس حين ينتهي، وإلّا بقيت الأرقام قديمةً بعد آخر عمليّةٍ
    // في سلسلةٍ متقاربة (بلاغ: «القيم ما تتحدّث بعد التجديد»). وتُجمَع كلّ
    // الطلبات في تحديثٍ واحدٍ لاحق فلا تعود موجات النداءات المتطابقة.
    expect(src.contains('_refreshQueued = true'), isTrue,
        reason: 'الطلب المبرَّد يُؤجَّل لا يُسقَط');
    expect(
      RegExp(r'_refreshQueued && mounted[\s\S]{0,80}?_refreshLive\(silent: true\)')
          .hasMatch(src),
      isTrue,
      reason: 'لا تحديثَ لاحقاً يُنفّذ الطلب المؤجَّل — تضيع آخر حالة',
    );
  });
}
