import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rad_mysvcs/core/util/order_rules.dart';

/// «الترتيب بالنقر» — القواعد نفسها بالموقع: جدول الحالات المشترك (test/fixtures/sort_cases.json — نسخة client-v2 sort_cases.json
/// حرفاً) + فحوصٌ مباشرة كفحص الموقع (sort.test.cjs).
void main() {
  final lri = String.fromCharCode(0x2066);
  final pdi = String.fromCharCode(0x2069);
  final rlm = String.fromCharCode(0x200F);

  group('جدول الحالات المشترك مع الموقع', () {
    final cases = jsonDecode(File('test/fixtures/sort_cases.json').readAsStringSync()) as List;
    for (final c in cases.cast<Map<String, dynamic>>()) {
      test('${c['name']} (${c['kind']} ${c['dir']})', () {
        final kind = OrderKind.values.byName(c['kind'] as String);
        final natural = c['natural'] == null ? null : OrderDir.values.byName(c['natural'] as String);
        final fields = [OrderField('v', 'v', kind, natural: natural)];
        final got = sortList<Object?>(List<Object?>.from(c['input'] as List), OrderValue('v', OrderDir.values.byName(c['dir'] as String)), fields, (x, _) => x);
        expect(got, c['expected']);
      });
    }
  });

  test('sortText: التشكيل والتطويل وأشكال الحروف', () {
    expect(sortText('مُـحَـمَّـد'), 'محمد');
    expect(['أحمد', 'إبراهيم', 'آمنة', 'ٱلياس'].map(sortText).toList(), ['احمد', 'ابراهيم', 'امنه', 'الياس']);
    expect(['مصطفى', 'فاطمة', 'مؤيد', 'هيئة'].map(sortText).toList(), ['مصطفي', 'فاطمه', 'مويد', 'هييه']);
    expect(['گوران', 'پشتیوان', 'چنار', 'ژیلا'].map(sortText).toList(), ['كوران', 'بشتيوان', 'جنار', 'زيلا']);
    expect(sortText('  رقم   ١٢٣  ۴ '), 'رقم 123 4');
    expect(sortText('${lri}Ali$pdi$rlm'), 'ali');
  });

  test('compareText: الأرقام بقيمتها', () {
    expect(compareText('user2', 'user10').sign, -1);
    expect(compareText('a007', 'a7'), 0);
    expect(compareText('n123456789012345678901', 'n123456789012345678902').sign, -1);
    expect(compareText('علي', 'علي حسن').sign, -1);
  });

  test('sortValueOf', () {
    expect(sortValueOf('1,250,000', OrderKind.number), 1250000);
    expect(sortValueOf('٣٥٠٠٠', OrderKind.number), 35000);
    expect(sortValueOf('—', OrderKind.number), isNull);
    expect(sortValueOf(double.nan, OrderKind.number), isNull);
    expect(sortValueOf('12abc', OrderKind.number), isNull);
    expect(sortValueOf('2026-11-22 10:00', OrderKind.date), sortValueOf('2026-11-22T10:00:00', OrderKind.date));
    expect(sortValueOf('2026-11-22', OrderKind.date), DateTime.utc(2026, 11, 22).millisecondsSinceEpoch);
    expect((sortValueOf('2026-11-22 10:00:30', OrderKind.date) as int) - (sortValueOf('2026-11-22 10:00:00', OrderKind.date) as int), 30000);
    expect((sortValueOf('2026-11-22 10:05', OrderKind.date) as int) - (sortValueOf('2026-11-22 10:00', OrderKind.date) as int), 300000);
    expect(sortValueOf('أمس', OrderKind.date), isNull);
    expect([sortValueOf('  ', OrderKind.text), sortValueOf('—', OrderKind.text), sortValueOf(null, OrderKind.text)], [null, null, null]);
  });

  test('النقرة: الأنفع ثمّ تقلب', () {
    const amount = OrderField('amount', 'المبلغ', OrderKind.number);
    const name = OrderField('name', 'الاسم', OrderKind.text);
    const date = OrderField('date', 'التاريخ', OrderKind.date, natural: OrderDir.desc);
    var v = const OrderValue('date', OrderDir.desc);
    v = nextOrder(v, amount);
    expect(v, const OrderValue('amount', OrderDir.desc));
    v = nextOrder(v, amount);
    expect(v, const OrderValue('amount', OrderDir.asc));
    v = nextOrder(v, amount);
    expect(v, const OrderValue('amount', OrderDir.desc));
    expect(nextOrder(v, name), const OrderValue('name', OrderDir.asc));
    expect(nextOrder(const OrderValue('name', OrderDir.asc), date), const OrderValue('date', OrderDir.desc));
    expect(nextOrder(const OrderValue('date', OrderDir.desc), const OrderField('x', 'x', OrderKind.date, first: OrderDir.asc)), const OrderValue('x', OrderDir.asc));
    expect(orderLine(const [date, amount], const OrderValue('amount', OrderDir.desc)), 'مرتّب حسب: المبلغ — الأكبر أوّلاً');
    expect(orderLine(const [date], const OrderValue('zz', OrderDir.desc)), isNull);
  });

  test('«حسب الشركة»: الأنفع ثمّ تقلب ثمّ الأصل', () {
    ColOrder? c;
    c = nextColOrder(c, 1, OrderDir.desc);
    expect(c, const ColOrder(1, OrderDir.desc));
    c = nextColOrder(c, 1, OrderDir.desc);
    expect(c, const ColOrder(1, OrderDir.asc));
    c = nextColOrder(c, 1, OrderDir.desc);
    expect(c, isNull);
    expect(nextColOrder(const ColOrder(0, OrderDir.asc), 2, OrderDir.desc), const ColOrder(2, OrderDir.desc));
    expect(nextColOrder(null, -1, OrderDir.asc), const ColOrder(-1, OrderDir.asc));
  });

  test('sortList: نسخةٌ والأصل كما هو، وحقلٌ غير معروف', () {
    final base = [3, 1, 2];
    const amount = OrderField('amount', 'المبلغ', OrderKind.number);
    final r1 = sortList<int>(base, const OrderValue('nope', OrderDir.asc), const [amount], (x, _) => x);
    expect(r1, [3, 1, 2]);
    expect(identical(r1, base), isFalse);
    expect(sortList<int>(base, const OrderValue('amount', OrderDir.asc), const [amount], (x, _) => x), [1, 2, 3]);
    expect(base, [3, 1, 2]);
  });

  group('الحفظ', () {
    const fields = [
      OrderField('date', 'التاريخ', OrderKind.date, natural: OrderDir.desc),
      OrderField('amount', 'المبلغ', OrderKind.number),
      OrderField('name', 'الاسم', OrderKind.text),
    ];
    const initial = OrderValue('date', OrderDir.desc);
    test('يقرأ المحفوظ ويحفظ — والمفتاح كالموقع', () async {
      SharedPreferences.setMockInitialValues({'report.v2.financial.sort': jsonEncode({'k': 'amount', 'd': 'asc'})});
      expect(OrderPrefs.rowsKey('financial'), 'report.v2.financial.sort');
      expect(await OrderPrefs.load(OrderPrefs.rowsKey('financial'), fields, initial), const OrderValue('amount', OrderDir.asc));
      await OrderPrefs.save('k5', const OrderValue('name', OrderDir.asc));
      final p = await SharedPreferences.getInstance();
      expect(jsonDecode(p.getString('k5')!), {'k': 'name', 'd': 'asc'});
    });
    test('حقلٌ لم يعد موجوداً، تالف، اتّجاهٌ غريب ⇒ الافتراض', () async {
      SharedPreferences.setMockInitialValues({
        'k2': jsonEncode({'k': 'gone', 'd': 'asc'}),
        'k3': '{bad json',
        'k4': jsonEncode({'k': 'amount', 'd': 'sideways'}),
      });
      for (final k in ['k2', 'k3', 'k4', 'missing']) {
        expect(await OrderPrefs.load(k, fields, initial), initial, reason: k);
      }
    });
    test('عمود «حسب الشركة»: الحدود والاسم والمحو', () async {
      SharedPreferences.setMockInitialValues({
        'c1': jsonEncode({'c': 5, 'd': 'asc'}),
        'c2': jsonEncode({'c': -1, 'd': 'asc'}),
        'c3': jsonEncode({'c': 1, 'd': 'x'}),
      });
      expect(await OrderPrefs.loadCol('c1', 3), isNull);
      expect(await OrderPrefs.loadCol('c2', 3), const ColOrder(-1, OrderDir.asc));
      expect(await OrderPrefs.loadCol('c3', 3), isNull);
      await OrderPrefs.saveCol('c2', null);
      expect(await OrderPrefs.loadCol('c2', 3), isNull);
      await OrderPrefs.saveCol('c4', const ColOrder(2, OrderDir.desc));
      expect(await OrderPrefs.loadCol('c4', 3), const ColOrder(2, OrderDir.desc));
    });
  });

  group('المرحلة ٣: ثلاث نقرات (قائمةٌ بلا حقلٍ افتراضيّ)', () {
    const amount = OrderField('amount', 'المبلغ', OrderKind.number);
    const name = OrderField('name', 'الاسم', OrderKind.text);
    test('الأنفع ثمّ يقلب ثمّ الأصل — كالموقع nextTriSort', () {
      OrderValue? v;
      v = nextTriOrder(v, amount);
      expect(v, const OrderValue('amount', OrderDir.desc));
      v = nextTriOrder(v, amount);
      expect(v, const OrderValue('amount', OrderDir.asc));
      v = nextTriOrder(v, amount);
      expect(v, isNull);
      expect(nextTriOrder(null, name), const OrderValue('name', OrderDir.asc));
      expect(nextTriOrder(const OrderValue('amount', OrderDir.asc), name), const OrderValue('name', OrderDir.asc), reason: 'حقلٌ آخر يبدأ من أوّله');
    });
    test('sortOrKeep: بلا ترتيبٍ نسخةٌ كما وصلت', () {
      final base = [3, 1, 2];
      final kept = sortOrKeep<int>(base, null, const [amount], (x, _) => x);
      expect(kept, [3, 1, 2]);
      expect(identical(kept, base), isFalse);
      expect(sortOrKeep<int>(base, const OrderValue('amount', OrderDir.desc), const [amount], (x, _) => x), [3, 2, 1]);
    });
    test('الحفظ: list.v2.<page>.sort كالموقع، والمحو بالأصل', () async {
      SharedPreferences.setMockInitialValues({'list.v2.managers.sort': jsonEncode({'k': 'name', 'd': 'asc'})});
      expect(OrderPrefs.listKey('managers'), 'list.v2.managers.sort');
      expect(await OrderPrefs.loadTri(OrderPrefs.listKey('managers'), const [amount, name]), const OrderValue('name', OrderDir.asc));
      await OrderPrefs.saveTri(OrderPrefs.listKey('managers'), null);
      expect(await OrderPrefs.loadTri(OrderPrefs.listKey('managers'), const [amount, name]), isNull);
      SharedPreferences.setMockInitialValues({'k': '{bad', 'k2': jsonEncode({'k': 'gone', 'd': 'asc'}), 'k3': jsonEncode({'k': 'name', 'd': 'x'})});
      for (final k in ['k', 'k2', 'k3', 'missing']) {
        expect(await OrderPrefs.loadTri(k, const [amount, name]), isNull, reason: k);
      }
    });
  });
}
