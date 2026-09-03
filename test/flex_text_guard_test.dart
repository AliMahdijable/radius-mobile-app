import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// حارسٌ ثابت ضدّ **نمط السحق** في كلّ ملفّات `lib/`.
///
/// اللقطة التي أرسلها المستخدم ٢٠٢٦-٠٩-٠٣ — «دي / ن / عل / ى» حرفاً في
/// كلّ سطر — لم تكن حالةً شاذّة، بل نمطاً يتكرّر: `Row` فيه طفلٌ مرن
/// بلا `maxLines` يزاحمه أطفالٌ ثابتون. المرن يُعطى **ما بقي**، وما بقي
/// قد يكون صفراً؛ وبلا `maxLines` لا يجد النصّ مفرّاً من الالتفاف
/// حرفاً حرفاً.
///
/// ⚠️ ولا يشكو `Row` من هذا أبداً: الفيض الأحمر لمن تجاوز بلا مرن،
/// أمّا مع `Expanded` فالتخطيط «ينجح» بسحق المرن. اختباراتٌ خضراء
/// وشاشةٌ منهارة.
///
/// ── ما لا يُعدّ عطلاً ─────────────────────────────────────────────
/// نصٌّ **يُقصد** له أن يلتفّ على أسطر (رسالة خطأ · تلميح · نقطة في
/// قائمة) بجانب أيقونةٍ ضيّقة. الاستثناءات أدناه بأسمائها وأسبابها —
/// وكلّ واحدة فُحصت يدويّاً وقيس ما يبقى للنصّ فيها.
void main() {
  test('🚨 لا نصّ مرنٍ بلا maxLines يزاحمه ثابتٌ عريض', () {
    // (ملفّ، مقتطف النصّ) — كلّها التفافٌ مقصود بجوار أيقونةٍ ضيّقة.
    const allowed = {
      // رسالة خطأ + أيقونة ٢٠ + زرّ «إعادة»؛ يبقى للنصّ ~٢١٠ نقطة.
      'airfiber60_live_panel.dart',
      'mimosa_live_panel.dart',
      // تلميحٌ تحت حقل الرسالة — سطران مقصودان.
      'broadcast_screen.dart',
      // `_bullet`: نقطةٌ عرضها ٤ نقاط ثمّ نصّ الميزة.
      'packages_screen.dart',
    };

    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final row in _rows(src)) {
        final kids = _splitTop(row.children);
        final fixed = kids.where((k) =>
            !_flex.hasMatch(k) && !_small.hasMatch(k) && _wide.hasMatch(k));
        if (fixed.isEmpty) continue;
        for (final k in kids) {
          if (!_flex.hasMatch(k)) continue;
          final child = _splitTop(_body(k)).where((a) => a.startsWith('child'));
          if (child.isEmpty) continue;
          final m = _textChild.matchAsPrefix(child.first);
          if (m == null) continue;
          final args = child.first.substring(
              m.end - 1, _balanced(child.first, m.end - 1) + 1);
          if (args.contains('maxLines:')) continue;
          if (args.contains('TextOverflow.ellipsis') ||
              args.contains('TextOverflow.fade')) continue;
          final name = f.path.split('/').last;
          if (allowed.contains(name)) continue;
          final line = '\n'.allMatches(src.substring(0, row.at)).length + 1;
          offenders.add('${f.path}:$line');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'نصٌّ مرن بلا maxLines يزاحمه ثابت — قابلٌ للسحق:\n'
            '${offenders.join('\n')}\n\n'
            'إمّا maxLines:1 + ellipsis إن كان تسميةً قصيرة، '
            'وإمّا انقل الثابت إلى سطرٍ مستقلّ إن كان النصّ يجب أن يلتفّ.');
  });
}

final _flex = RegExp(r'^\s*(const\s+)?(Expanded|Flexible)\s*\(');
final _small =
    RegExp(r'^\s*(const\s+)?(SizedBox|Spacer|Divider|VerticalDivider)\b');
final _wide = RegExp(
    r'\b(Text|Container|Button|Chip|_\w*Button|_\w*Chip|_\w*Badge|_\w*Pill)\s*\(');
final _textChild = RegExp(r'child\s*:\s*(const\s+)?Text\s*\(');

/// فهرس ')' المقابلة لـ'(' عند [i]، مع تخطّي النصوص الحرفيّة.
int _balanced(String s, int i) {
  var d = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == "'" || c == '"') {
      final q = c;
      i++;
      while (i < s.length && s[i] != q) {
        i += s[i] == r'\' ? 2 : 1;
      }
    } else if (c == '(') {
      d++;
    } else if (c == ')') {
      if (--d == 0) return i;
    }
    i++;
  }
  return -1;
}

String _body(String call) {
  final o = call.indexOf('(');
  final c = _balanced(call, o);
  return c < 0 ? '' : call.substring(o + 1, c);
}

/// يقسم قائمة وسائط على فواصل المستوى الأعلى وحدها.
List<String> _splitTop(String b) {
  final out = <String>[];
  final cur = StringBuffer();
  var d = 0, i = 0;
  while (i < b.length) {
    final c = b[i];
    if (c == "'" || c == '"') {
      final q = c;
      cur.write(c);
      i++;
      while (i < b.length && b[i] != q) {
        cur.write(b[i]);
        i++;
      }
      if (i < b.length) cur.write(b[i]);
      i++;
      continue;
    }
    if ('([{'.contains(c)) d++;
    if (')]}'.contains(c)) d--;
    if (c == ',' && d == 0) {
      out.add(cur.toString().trim());
      cur.clear();
    } else {
      cur.write(c);
    }
    i++;
  }
  if (cur.toString().trim().isNotEmpty) out.add(cur.toString().trim());
  return out.where((e) => e.isNotEmpty).toList();
}

class _Row {
  _Row(this.at, this.children);
  final int at;
  final String children;
}

Iterable<_Row> _rows(String s) sync* {
  for (final m in RegExp(r'\bRow\s*\(').allMatches(s)) {
    final o = m.end - 1;
    final c = _balanced(s, o);
    if (c < 0) continue;
    final args = s.substring(o + 1, c);
    final km = RegExp(r'children\s*:\s*\[').firstMatch(args);
    if (km == null) continue;
    var d = 0, i = km.end - 1;
    while (i < args.length) {
      if (args[i] == '[') d++;
      if (args[i] == ']' && --d == 0) break;
      i++;
    }
    if (i >= args.length) continue;
    yield _Row(m.start, args.substring(km.end, i));
  }
}
