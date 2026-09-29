import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس «كلّ مفتاحٍ يُكتَب يُمسَح».
///
/// ── الحادثة ──────────────────────────────────────────────────────
/// `AuthStorage.clear()` كان يمسح أحدَ عشرَ مفتاحاً من اثني عشر.
/// الناجي `auth.sas4_token` — توكن الساس — كُتب في `saveSession` وفي
/// كلّ تجديد، ولم يُمسَح في أيّ خروج. وبقي كذلك شهرين لأنّ لا شيء
/// يقرؤه فلا شيء ينكسر: اعتمادٌ صامتٌ في الـkeychain، وعلى iOS منسوخٌ
/// إلى iCloud (`synchronizable: true`).
///
/// ── ولماذا حارسٌ لا مراجعة ───────────────────────────────────────
/// العطل من صنفٍ لا تكشفه التجربة ولا الاختبار السلوكيّ: كلّ شيء
/// يعمل تماماً مع المفتاح الناجي. يكشفه العدُّ وحده. وقائمتا الكتابة
/// والمسح متجاورتان في الملفّ نفسه — فالسهو تكرارُه مسألةُ وقت كلّما
/// أُضيف مفتاح.
///
/// القاعدة: **كلّ ثابت `auth.*` في `AuthStorage` يجب أن يظهر داخل
/// `clear()`.** من أراد مفتاحاً يعيش بعد الخروج فليضعه خارج `auth.*`
/// (كما فعل `profiles.*` في `saved_profiles_store.dart`) — لا أن
/// يستثنيه صامتاً.
void main() {
  test('كلّ مفتاح auth.* يُمسَح في clear()', () {
    final src = File('lib/services/auth_storage.dart').readAsStringSync();

    // أسماء الثوابت التي قيمتها سلسلة تبدأ بـ`auth.`.
    final declared = RegExp(
      r"static\s+const\s+(_k\w+)\s*=\s*'(auth\.[\w.]+)'",
    ).allMatches(src).map((m) => (name: m.group(1)!, key: m.group(2)!)).toList();

    expect(declared, isNotEmpty,
        reason: 'لم يُعثر على أيّ ثابت auth.* — تغيّرت صيغة الملفّ، '
            'حدّث الحارس بدل تعطيله.');

    // جسم `clear()` وحده: من توقيعها إلى أوّل `}` على عمودها.
    final start = src.indexOf('static Future<void> clear() async {');
    expect(start, isNot(-1), reason: 'AuthStorage.clear() غير موجودة.');
    final end = src.indexOf('\n  }', start);
    expect(end, isNot(-1), reason: 'تعذّر تحديد نهاية clear().');
    final body = src.substring(start, end);

    final missing = <String>[];
    for (final c in declared) {
      if (!RegExp(r'delete\(key:\s*' + c.name + r'\s*\)').hasMatch(body)) {
        missing.add('${c.name}  (${c.key})');
      }
    }

    expect(
      missing,
      isEmpty,
      reason: 'مفاتيح تُكتَب ولا تُمسَح عند الخروج — الجلسة السابقة '
          'تبقى على الجهاز:\n${missing.join('\n')}\n\n'
          'إن كان المفتاح يجب أن يعيش بعد الخروج فانقله خارج نطاق '
          '`auth.*` (انظر `profiles.*`)، لا تستثنِه هنا.',
    );
  });
}
