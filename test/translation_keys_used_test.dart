import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// كلّ مفتاح ترجمةٍ مكتوبٍ حرفيّاً في `lib/` (`'a.b'.tr(` · `tr('a.b'` ·
/// `.plural(`) موجودٌ في ar.json وen.json معاً.
///
/// 🐛 مراجعة 3.0.3: شيت تأكيد الحذف/التعطيل/التفعيل الجماعيّ كان يعرض تحت
/// العنوان النصّ الخامّ «subscribers.selected_count» — مفتاحٌ غير موجود،
/// وeasy_localization تعيد المفتاح نفسه بصمت.
void main() {
  Map<String, Object?> flat(Map<String, dynamic> m, [String prefix = '']) {
    final out = <String, Object?>{};
    m.forEach((k, v) {
      final key = prefix.isEmpty ? k : '$prefix.$k';
      if (v is Map<String, dynamic>) {
        out.addAll(flat(v, key));
      } else {
        out[key] = v;
      }
    });
    return out;
  }

  Map<String, Object?> load(String lang) => flat(jsonDecode(
          File('assets/translations/$lang.json').readAsStringSync())
      as Map<String, dynamic>);

  test('لا مفتاح ترجمةٍ مفقود', () {
    final ar = load('ar');
    final en = load('en');
    const key = r'''[a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)+''';
    final dotForm = RegExp('''(['"])($key)\\1\\s*\\)?\\s*\\.\\s*(?:tr|plural)\\s*\\(''');
    final callForm = RegExp('''\\b(?:tr|plural)\\(\\s*(['"])($key)\\1''');
    bool known(String k, Map<String, Object?> lang) =>
        lang.containsKey(k) || lang.keys.any((x) => x.startsWith('$k.'));

    final missing = <String, Set<String>>{};
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in [...dotForm.allMatches(src), ...callForm.allMatches(src)]) {
        final k = m.group(2)!;
        if (!known(k, ar) || !known(k, en)) {
          (missing[k] ??= <String>{}).add(f.path);
        }
      }
    }
    expect(missing, isEmpty, reason: 'مفاتيح تظهر خامّاً للمستخدم: $missing');
  });
}
