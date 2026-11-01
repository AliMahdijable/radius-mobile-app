import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/national_portal_api.dart';
import 'package:rad_mysvcs/screens/national/national_widgets.dart';

/// الوطنيّ — «المزيد» لا يعلق (مراجعة ١ نوفمبر): الصفحة التالية «جارٍ» (pending) ثمّ يفشل سؤالها (503 مشغولة) ⇒ pending يُطفأ
/// والخطأ يُقال (بـ«إعادة» في الواجهة)؛ وبقاؤها «جارٍ» بعد ١٥ سؤالاً (~٦٠ث) ⇒ خطأٌ لا انتظارٌ بلا نهاية؛ والنجاح يصفّر العدّ.
void main() {
  NationalResult<NationalPage<int>> ok(int page, {int pages = 3}) =>
      NationalResult.ok(NationalPage<int>(items: [page], page: page, pageCount: pages, total: pages));
  const pending = NationalResult.ok(NationalPage<int>(items: [], pending: true));
  const busy = NationalResult<NationalPage<int>>.fail('بوّابة المشروع الوطني مشغولة الآن — أعد المحاولة بعد دقائق');

  testWidgets('جارٍ ثمّ فشل ⇒ لا pending ولا تحميل، والخطأ نصّ الخادم — و«إعادة» تكمل الصفحة نفسها', (t) async {
    final p = NationalPaged<int>();
    addTearDown(p.dispose);
    final seq = <NationalResult<NationalPage<int>>>[ok(1), pending, busy, ok(2)];
    final asked = <int>[];
    Future<NationalResult<NationalPage<int>>> fetch(int page) async {
      asked.add(page);
      return seq.removeAt(0);
    }

    await p.next(fetch, onChange: () {}, alive: () => true);
    expect([p.page, p.rows], [1, [1]]);
    await p.next(fetch, onChange: () {}, alive: () => true);
    expect(p.pending, isTrue, reason: 'الصفحة ٢ جارٍ');
    await t.pump(const Duration(seconds: 4)); // سؤالها الآليّ بعد ٤ث ⇒ 503
    await t.pump();
    expect([p.pending, p.loading, p.error], [false, false, 'بوّابة المشروع الوطني مشغولة الآن — أعد المحاولة بعد دقائق']);
    expect(p.hasMore, isTrue, reason: 'ما زالت صفحاتٌ — والواجهة تعرض الخطأ بـ«إعادة» مكان «المزيد»');
    await p.next(fetch, onChange: () {}, alive: () => true); // «إعادة»
    expect([p.page, p.rows, p.error], [2, [1, 2], null]);
    expect(asked, [1, 2, 2, 2]);
  });

  testWidgets('بقيت «جارٍ» بعد ١٥ سؤالاً ⇒ خطأٌ لا دوّارةٌ بلا نهاية', (t) async {
    final p = NationalPaged<int>();
    addTearDown(p.dispose);
    var n = 0;
    Future<NationalResult<NationalPage<int>>> fetch(int page) async {
      n += 1;
      return page == 1 ? ok(1) : pending;
    }

    await p.next(fetch, onChange: () {}, alive: () => true);
    await p.next(fetch, onChange: () {}, alive: () => true);
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(seconds: 4));
      await t.pump();
    }
    expect(p.pending, isFalse);
    expect(p.error, contains('أعد المحاولة'));
    expect(n, 1 + 1 + 15, reason: 'الأولى + الثانية + ١٥ سؤالاً آليّاً ثمّ يتوقّف');
    await t.pump(const Duration(seconds: 30));
    expect(n, 17, reason: 'لا أسئلة بعد الخطأ');
  });
}
