import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارس «لا مفتاحَ يُكتب وقارئُه ميّت».
///
/// ── الحادثة ──────────────────────────────────────────────────────
/// `auth.sas4_token` عاش شهرين يُكتب عند كلّ دخولٍ وكلّ تجديد. وله
/// قارئٌ في الملفّ — `readSas4Token()` — فبدا الحقل حيّاً. لكنّ ذلك
/// القارئ نفسه كان بلا مُستدعٍ واحد في كامل `lib/` منذ حُذفت نداءات
/// الساس المباشرة (2026-08-31 `a58acd7`). قارئٌ ميّتٌ يخفي كتابةً
/// ميّتة.
///
/// وثلاثة تعليقاتٍ مفصّلة كانت تصف ما يفعله الحقل: «يُستعمل
/// للاستدعاءات المباشرة على SAS4». لم يقع ذلك قطّ. والأسوأ أنّ فرع
/// الموظّف في `AuthApi.refreshToken()` وُجد **من أجل هذه الكتابة
/// وحدها**، وكان يُعلن النجاح بعدها — فلم يكن الموظّف المنتهية جلسته
/// يُطرد إلى الدخول أبداً. حقلٌ ميّتٌ أخفى عطلاً حيّاً.
///
/// ── ولماذا حارسٌ لا مراجعة ───────────────────────────────────────
/// الكتابة بلا قراءةٍ فعليّة **لا تكسر شيئاً**: لا استثناء، ولا سطرٌ
/// في السجلّ، ولا شكوى من `dart analyze` (الدالّة العامّة ليست «غير
/// مستعملة» في نظره). يكشفها التتبّع وحده. والأخطر أنّها تُغري من
/// يأتي بعدنا: يقرأ الاسم والتعليق فيبني عليه — على حقلٍ لم يُقرأ
/// قطّ فلم يُختبَر قطّ.
///
/// القاعدة: **كلّ مفتاح `auth.*` يُكتب يجب أن يقرأه استدعاءٌ حيّ.**
/// ومن أراد مفتاحاً متروكاً للتنظيف فليتركه بلا كتابةٍ ولا قراءة —
/// يُمسَح في `clear()` وحسب (كما `_kSas4TokenLegacy`).
void main() {
  test('كلّ مفتاح auth.* يُكتب له قارئٌ يُستدعى من خارج AuthStorage', () {
    const storePath = 'lib/services/auth_storage.dart';
    final lines = File(storePath).readAsLinesSync();
    final src = lines.join('\n');

    final declared = RegExp(r"static\s+const\s+(_k\w+)\s*=\s*'(auth\.[\w.]+)'")
        .allMatches(src)
        .map((m) => (name: m.group(1)!, key: m.group(2)!))
        .toList();

    expect(declared, isNotEmpty,
        reason: 'لم يُعثر على أيّ ثابت auth.* — تغيّرت صيغة الملفّ، '
            'حدّث الحارس بدل تعطيله.');

    // تتبّعٌ سطريّ: آخر `static` مرّ بنا هو صاحب السطر الحاليّ.
    final method = RegExp(r'^\s*static\s+[\w<>?,\s]*?(\w+)\s*\(');
    final readOf = <String, Set<String>>{}; // مفتاح → دوالّ تقرؤه
    var current = '';
    for (final l in lines) {
      final m = method.firstMatch(l);
      if (m != null) current = m.group(1)!;
      for (final c in declared) {
        if (RegExp(r'_storage\.read\(\s*key:\s*' + c.name + r'\b')
            .hasMatch(l)) {
          readOf.putIfAbsent(c.name, () => <String>{}).add(current);
        }
      }
    }

    // كلّ `lib/` عدا الملفّ نفسه — هناك تُطلب الدوالّ فعلاً.
    final callers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll(r'\', '/').endsWith(storePath))
        .map((f) => f.readAsStringSync())
        .join('\n');

    bool isLive(String fn) =>
        fn.isNotEmpty &&
        !fn.startsWith('_') &&
        RegExp(r'AuthStorage\.' + fn + r'\b').hasMatch(callers);

    final dead = <String>[];
    for (final c in declared) {
      final written =
          RegExp(r'_storage\.write\(\s*key:\s*' + c.name + r'\b').hasMatch(src);
      if (!written) continue; // مفتاحٌ متروك للمسح — مقصودٌ ومشروح.
      final readers = readOf[c.name] ?? <String>{};
      if (!readers.any(isLive)) {
        dead.add('${c.name}  (${c.key})  '
            'قرّاؤه: ${readers.isEmpty ? "لا أحد" : readers.join(" · ")} — '
            'ولا مُستدعِيَ لهم في lib/');
      }
    }

    expect(
      dead,
      isEmpty,
      reason: 'مفاتيح تُكتَب ولا يقرؤها كودٌ حيّ — سرٌّ على الجهاز بلا '
          'فائدة، واسمٌ يُغري من يبني عليه:\n${dead.join('\n')}\n\n'
          'إمّا أن يُقرأ فعلاً، وإمّا أن تُحذف كتابته وقارئه ويبقى '
          'الاسم للمسح وحده (انظر `_kSas4TokenLegacy`).',
    );
  });
}
