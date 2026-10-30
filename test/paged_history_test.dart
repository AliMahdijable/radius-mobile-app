import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/history_page.dart';
import 'package:rad_mysvcs/screens/topup/paged_history.dart';

import 'sim_el/sim_harness.dart';

/// «آخر العمليّات» بصفحات — المالك ٣٠ أكتوبر: «خلي ماكس يظهر ١٠ ويكمل يحمل ويبحث ع رقم عمليه… حتى ان صدف وكيل عنده عمليات
/// شحن هواي ولفتره طويله متصير القائمة مزعجه». الخادم (824b597): `before` = آخر صفٍّ معروض، `q` = رقم العمليّة، `has_more`.
void main() {
  const v = SimVariant(390, dark: false);
  setUpAll(simSetUpAll);

  // ٢٣ عمليّة، الأحدث أوّلاً: «op23» … «op1»، ورقم كلٍّ 3115NN.
  final all = [for (var i = 23; i >= 1; i--) 'op$i'];
  String ref(String id) => '3115${id.substring(2).padLeft(2, '0')}';

  ({PagedHistoryController<String> c, List<String> asked}) make({Duration delay = Duration.zero}) {
    final asked = <String>[];
    late PagedHistoryController<String> c;
    c = PagedHistoryController<String>(
      idOf: (r) => r,
      debounce: const Duration(milliseconds: 400),
      fetch: ({before, query, required limit}) async {
        asked.add('before=${before ?? '-'} q=${query ?? '-'} limit=$limit');
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        var list = all;
        if (before != null) list = list.sublist(list.indexOf(before) + 1);
        if (query != null) list = list.where((r) => ref(r).contains(query)).toList();
        return HistoryPage(list.take(limit).toList(), hasMore: list.length > limit);
      },
    );
    return (c: c, asked: asked);
  }

  test('رقم العمليّة: العربيّة ⇒ لاتينيّة، «#» يُهمل، وما ليس رقماً ⇒ null (لا يُرسل)', () {
    expect(PagedHistoryController.termOf('#٣١١٥٠٤'), '311504');
    expect(PagedHistoryController.termOf(' ZC88120 '), 'ZC88120');
    expect(PagedHistoryController.termOf('#'), isNull);
    expect(PagedHistoryController.termOf(''), isNull);
    expect(PagedHistoryController.termOf("1' OR 1=1"), isNull);
    expect(PagedHistoryController.termOf('1%2'), isNull);
  });

  test('١٠ ثمّ «عرض المزيد» ما قبل آخر صفٍّ معروض — بلا تكرار حتى النهاية', () async {
    final m = make();
    await m.c.reload();
    expect([m.c.rows.length, m.c.hasMore, m.c.rows.first, m.c.rows.last], [10, true, 'op23', 'op14']);
    expect(m.c.showSearch, isTrue, reason: 'صفحةٌ كاملة ⇒ حقل البحث');
    await m.c.loadMore();
    expect([m.c.rows.length, m.c.hasMore, m.c.rows.last], [20, true, 'op4']);
    await m.c.loadMore();
    expect([m.c.rows.length, m.c.hasMore, m.c.rows.last], [23, false, 'op1']);
    expect(m.c.rows.toSet().length, 23);
    await m.c.loadMore();
    expect(m.asked, ['before=- q=- limit=10', 'before=op14 q=- limit=10', 'before=op4 q=- limit=10'],
        reason: 'لا طلب بعد النهاية');
    m.c.dispose();
  });

  testWidgets('البحث بعد توقّف الكتابة؛ ما ليس رقماً لا يُرسل؛ والمسح يرجع للقائمة كلّها', (t) async {
    final m = make();
    await m.c.reload();
    m.c.search('#٩');
    m.c.search('#٩9');
    await t.pump(const Duration(milliseconds: 300));
    expect(m.asked, hasLength(1), reason: 'لا طلب مع كلّ حرف');
    await t.pump(const Duration(milliseconds: 200));
    await t.pump();
    expect(m.asked.last, 'before=- q=99 limit=10');
    expect(m.c.rows, isEmpty, reason: 'لا رقم فيه 99');
    expect(m.c.term, '99');
    expect(m.c.visible, isTrue, reason: 'القسم يبقى ليقول «لا عمليّة برقم»');

    m.c.search('12');
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect(m.c.rows, ['op12']);

    m.c.search("x'");
    await t.pump(const Duration(seconds: 1));
    expect(m.c.badQuery, isTrue);
    expect(m.asked, hasLength(3), reason: 'المدخل الفاسد لا يُرسل');

    m.c.search('');
    await t.pump(const Duration(milliseconds: 500));
    await t.pump();
    expect([m.c.term, m.c.rows.length, m.c.hasMore], [null, 10, true]);
    m.c.dispose();
  });

  testWidgets('ردٌّ قديم بعد بحثٍ أحدث يُسقط — لا تختلط قائمتان', (t) async {
    final m = make(delay: const Duration(seconds: 2));
    unawaited(m.c.reload()); // بطيء: القائمة كلّها
    await t.pump(const Duration(milliseconds: 100));
    m.c.search('7');
    await t.pump(const Duration(milliseconds: 500)); // يبدأ البحث
    await t.pump(const Duration(seconds: 3));
    await t.pump();
    expect(m.c.rows, ['op17', 'op7'], reason: 'نتيجة البحث وحدها — ردّ «الكلّ» المتأخّر لا يكتب فوقها');
    m.c.dispose();
  });

  testWidgets('الواجهة: الحقل يظهر مع الصفحة الكاملة، «عرض المزيد» يكمل، والبحث يقول «لا عمليّة برقم …»', (t) async {
    final m = make();
    await pumpSim(
      t,
      v,
      home: (_) => Scaffold(
        body: SingleChildScrollView(
          child: PagedHistoryList<String>(history: m.c, rowBuilder: (r) => SizedBox(height: 24, child: Text(r))),
        ),
      ),
    );
    await m.c.reload();
    await t.pumpAndSettle();
    expect(find.text('ابحث برقم العمليّة'), findsOneWidget);
    expect(find.text('op14'), findsOneWidget);
    expect(find.text('op13'), findsNothing);
    await t.ensureVisible(find.text('عرض المزيد'));
    await t.tap(find.text('عرض المزيد'));
    await t.pumpAndSettle();
    expect(find.text('op4'), findsOneWidget);

    await t.enterText(find.byType(TextField), '99');
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.text('لا عمليّة برقم 99'), findsOneWidget);
    expect(find.text('عرض المزيد'), findsNothing);

    await t.enterText(find.byType(TextField), '٢٣');
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    expect(find.text('op23'), findsOneWidget);
    expect(find.text('op22'), findsNothing);
    m.c.dispose();
    await simDrain(t);
  });

  testWidgets('عمليّاتٌ قليلة (أقلّ من صفحة) ⇒ لا حقل بحث ولا «عرض المزيد»', (t) async {
    final c = PagedHistoryController<String>(
      idOf: (r) => r,
      fetch: ({before, query, required limit}) async => const HistoryPage(['a', 'b'], hasMore: false),
    );
    await pumpSim(t, v, home: (_) => Scaffold(body: PagedHistoryList<String>(history: c, rowBuilder: Text.new)));
    await c.reload();
    await t.pumpAndSettle();
    expect(find.text('a'), findsOneWidget);
    expect(find.text('ابحث برقم العمليّة'), findsNothing);
    expect(find.text('عرض المزيد'), findsNothing);
    c.dispose();
    await simDrain(t);
  });
}
