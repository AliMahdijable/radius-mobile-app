import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس الحظر الجماعيّ — ٢٠٢٦-٠٩-٠٣.
///
/// الحارس المفرد يقف أمام رسالةٍ واحدة والمدير يقرأ ويقرّر. أمّا البثّ
/// فمئتا رسالة بنقرة، ولا أحد يقرأ مئتَي تحذير.
///
/// ⚠️ والقياس هو ما ضبط التصميم، لا الحدس:
///   ٥٢٪ من جمهور البثّ لم يبادروا بمراسلة المدير — فاستبعادهم يُلغي
///        البثّ لا يحرسه. يُذكَرون ولا يُطرحون.
///   ٦٪  تجاهلوا ستّاً فأكثر (٢٫٢٪–١٢٫٣٪ على ستّة مدراء حقيقيّين) —
///        هؤلاء يُطرحون افتراضيّاً. نادرٌ بما يكفي ليبقى مقروءاً.
void main() {
  late String api, screen, server, db;
  setUpAll(() {
    api = File('lib/api/wa_contact_risk.dart').readAsStringSync();
    screen =
        File('lib/screens/broadcast/broadcast_screen.dart').readAsStringSync();
    const root = '/home/ali/MyServices Raduis';
    server = File('$root/server.js').readAsStringSync();
    db = File('$root/database/db.js').readAsStringSync();
  });

  test('🚨 الاستبعاد الافتراضيّ في الخادم لا في العميل وحده', () {
    // عميلٌ قديم لا يعرف الحارس يجب أن يُحمى أيضاً — والحماية التي
    // تعيش في الواجهة وحدها تسقط مع أوّل نسخةٍ لم تُحدَّث.
    expect(server.contains("const _includeHighRisk = req.body.includeHighRisk === true;"),
        isTrue);
    expect(server.contains("if (r && r.tier === 'confirm') {"), isTrue);
  });

  test('🚨 «لم يراسلك» لا يُستبعَد أبداً', () {
    // ٥٢٪ من الجمهور. استبعادُهم يُعطّل البثّ، والحارس الذي يمنع كلّ
    // شيء يُطفَأ في يومه الأوّل.
    final i = server.indexOf("if (r && r.tier === 'confirm')");
    expect(i, greaterThan(0));
    final block = server.substring(i, i + 400);
    expect(block.contains("'notice'"), isFalse,
        reason: 'درجة notice تُستبعَد — وهي نصف الجمهور');
  });

  test('🚨 الاستبعاد يُذكر في نصّ الردّ لا في الحقول وحدها', () {
    // عمليّةٌ صامتة تُنقص ٦٪ من حملة تذكيرٍ بالديون تُكتشَف بعد أسبوع.
    expect(server.contains(r'استُبعد ${excludedHighRisk} لخطر الحظر'), isTrue);
    expect(screen.contains('واستُبعد \$ex لخطر الحظر'), isTrue);
  });

  test('🚨 فشل الفحص لا يوقف البثّ', () {
    // حارسٌ يمنع مئتَي رسالة بسبب استعلامٍ متعثّر ضررٌ أكيد مقابل خطرٍ
    // محتمل.
    expect(server.contains("console.warn('⚠️ [broadcast] تعذّر فحص خطر الأرقام:"),
        isTrue);
    expect(api.contains('static const none = WaBulkRisk(total: 0'), isTrue);
    expect(api.contains('return WaBulkRisk.none;'), isTrue);
  });

  test('🚨 البحث في خريطة الخطر بالرقم المطبَّع', () {
    // مفاتيح الخريطة مطبَّعة. البحث بالخام لا يجد شيئاً **أبداً** —
    // فيمرّ الحارس صامتاً ويبدو كأنّه يعمل.
    expect(db.contains('  normalizePhoneForQueue,\n'), isTrue,
        reason: 'الدالّة غير مُصدَّرة من db.js');
    expect(server.contains('riskBy.get(db.normalizePhoneForQueue(phone))'),
        isTrue);
  });

  test('الموافقة ليست دائمة', () {
    // موافقةٌ على حملةٍ ليست موافقةً على ما بعدها.
    expect(screen.contains('bool _includeHighRisk = false;'), isTrue);
  });

  test('الحوار يفصل الرقمين', () {
    // «١٠٤ من ٢٠٠ في خطر» رقمٌ يُتجاهَل؛ «١٢ سيُستبعَدون» رقمٌ يُقرَّر
    // فيه.
    expect(screen.contains('لم تسبق لهم مراسلتك'), isTrue);
    expect(screen.contains('تجاهلوا ٦ رسائل فأكثر بلا ردّ'), isTrue);
    expect(screen.contains("Text('سيصل الآن: \$willSend'"), isTrue);
  });

  test('العدّ يُقرأ من summary لا من الجذر', () {
    // كان يُقرأ من الجذر فيرجع null دائماً، فيعرض التطبيق عدد
    // المستهدَفين بدل ما دخل الطابور فعلاً.
    final b = File('lib/api/broadcast_api.dart').readAsStringSync();
    expect(b.contains("sum['queued']"), isTrue);
    expect(b.contains("sum['excludedHighRisk']"), isTrue);
  });
}
