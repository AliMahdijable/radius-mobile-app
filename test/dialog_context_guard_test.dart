import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// الحوار يُغلَق بسياقه هو لا بسياق الصفحة التي فتحته. `showDialog` يضعه على الـNavigator الجذر، وعلى الحاسبة لكلّ
/// قسمٍ Navigator خاصّ: `Navigator.pop(context)` بسياق الصفحة يُغلق **الصفحة** تحت الحوار ويبقى الحوار ينتظر
/// للأبد — «من احذف بجهاز يصفن البرنامج» (المالك ٢٤ أكتوبر؛ ١٧ موضعاً). على الهاتف لا فرق فلم يظهر هناك.
void main() {
  test('لا حوارٌ يُغلَق بـcontext الصفحة — builder: (ctx) و Navigator.pop(ctx)', () {
    final call = RegExp(r'\b(showDialog|showAppSheet|showModalBottomSheet|showGeneralDialog|showAdaptiveDialog)\s*(<[^>]*>)?\s*\(');
    final builder = RegExp(r'builder:\s*\(\s*([A-Za-z_]\w*)\s*(?:,\s*[A-Za-z_]\w*\s*)?\)\s*(=>|\{)');
    final pop = RegExp(r'Navigator\.pop\(\s*context\b|Navigator\.of\(\s*context\s*\)\s*\.(pop|maybePop)\b');
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      for (final m in call.allMatches(s)) {
        final open = m.end - 1;
        final close = _matchParen(s, open);
        if (close < 0) continue;
        final region = s.substring(open, close);
        final b = builder.firstMatch(region);
        if (b == null || b.group(1) == 'context') continue;
        if (pop.hasMatch(region.substring(b.end))) {
          bad.add('${f.path}:${'\n'.allMatches(s.substring(0, m.start)).length + 1}');
        }
      }
    }
    expect(bad, isEmpty, reason: 'أغلق الحوار بسياق الـbuilder:\n${bad.join('\n')}');
  });
}

/// القوس المقابل (يتخطّى النصوص والتعليقات السطريّة).
int _matchParen(String s, int i) {
  var depth = 0;
  String? quote;
  for (var j = i; j < s.length; j++) {
    final c = s[j];
    if (quote != null) {
      if (c == r'\') {
        j++;
      } else if (s.startsWith(quote, j)) {
        j += quote.length - 1;
        quote = null;
      }
      continue;
    }
    if (s.startsWith("'''", j) || s.startsWith('"""', j)) {
      quote = s.substring(j, j + 3);
      j += 2;
      continue;
    }
    if (c == "'" || c == '"') {
      quote = c;
      continue;
    }
    if (s.startsWith('//', j)) {
      final k = s.indexOf('\n', j);
      if (k < 0) return -1;
      j = k;
      continue;
    }
    if (c == '(') depth++;
    if (c == ')') {
      depth--;
      if (depth == 0) return j;
    }
  }
  return -1;
}
