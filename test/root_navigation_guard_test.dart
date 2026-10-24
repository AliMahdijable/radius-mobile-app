import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// استبدال التطبيق كلّه (فتح شركة، تبديل صفحة، بوّابة الحساب، الخروج) يكون على الـNavigator الجذر.
/// على الحاسبة لكلّ قسمٍ Navigator خاصّ: شاشةٌ فُتحت داخله (مثل «الصفحات») كانت تبني غلافاً كاملاً جديداً
/// **داخل** القسم مع كلّ تبديل — غلافٌ فوق غلاف (بلاغ المالك ٢٤ أكتوبر بصورة ويندوز).
void main() {
  test('لا pushAndRemoveUntil على أقرب Navigator — rootNavigator: true', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('Navigator.of(context).pushAndRemoveUntil(')) bad.add('${f.path}:${i + 1}');
      }
    }
    expect(bad, isEmpty, reason: 'استعمل Navigator.of(context, rootNavigator: true).pushAndRemoveUntil:\n${bad.join('\n')}');
  });
}
