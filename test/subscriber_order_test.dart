import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_order.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/sort_sheet.dart';

/// «الترتيب بالنقر» — المرحلة ٥ (توحيد المشتركين): حقول القائمة العاديّة بقواعد كلّ القوائم — والموقع (Subscribers.tsx compareSubs)
/// بالقواعد نفسها: النصّ مطبَّعاً وأرقامه بقيمتها، الفارغ آخراً بالاتّجاهين، والتعادل بترتيب القائمة.
Subscriber _s(int id, String username,
        {String first = '', String last = '', String? exp, int? days, String? notes, int? session, String? phone, String? parent}) =>
    Subscriber.fromJson({
      'id': id,
      'username': username,
      'firstname': first,
      'lastname': last,
      if (exp != null) 'expiration': exp,
      if (days != null) 'remaining_days': days,
      if (notes != null) 'notes': notes,
      if (session != null) 'session_time': session,
      if (phone != null) 'phone': phone,
      if (parent != null) 'parent_username': parent,
    });

List<String> _users(List<Subscriber> l) => [for (final s in l) s.username];

void main() {
  final now = DateTime(2026, 11, 24, 12);
  List<String> order(List<Subscriber> l, SortField f, SortDirection d) => _users(orderSubscribers(l, f, d, now: now));

  test('اليوزر: الأرقام بقيمتها (user2 قبل user10) بلا حسّاس حالة الأحرف', () {
    final l = [_s(1, 'user10'), _s(2, 'User2'), _s(3, 'user1'), _s(4, 'ali')];
    expect(order(l, SortField.username, SortDirection.asc), ['ali', 'user1', 'User2', 'user10']);
    expect(order(l, SortField.username, SortDirection.desc), ['user10', 'User2', 'user1', 'ali']);
  });

  test('الاسم: العربيّ مطبَّعاً (إ وآ ألف، ة هاء) — ومن بلا اسمٍ بيوزره كما يُعرض', () {
    final l = [
      _s(1, 'z1', first: 'زيد', last: 'كريم'),
      _s(2, 'b2', first: 'إبراهيم', last: 'علي'),
      _s(3, 'a3', first: 'آمنة', last: 'حسن'),
      _s(4, 'x4'),
      _s(5, 'a5', first: 'احمد'),
    ];
    expect(order(l, SortField.firstname, SortDirection.asc), ['x4', 'b2', 'a5', 'a3', 'z1'], reason: 'اللاتينيّ أوّلاً ثمّ ابراهيم < احمد < امنه < زيد');
  });

  test('الانتهاء والمتبقّي: من بلا انتهاءٍ آخراً بالاتّجاهين (كان أوّلاً تصاعديّاً)', () {
    final l = [
      _s(1, 'a', exp: '2026-12-01 00:00:00'),
      _s(2, 'b'),
      _s(3, 'c', exp: '2026-11-25 10:00:00'),
      _s(4, 'd', days: 3),
    ];
    expect(order(l, SortField.expiration, SortDirection.asc), ['c', 'a', 'b', 'd']);
    expect(order(l, SortField.expiration, SortDirection.desc), ['a', 'c', 'b', 'd']);
    expect(order(l, SortField.remainingDays, SortDirection.asc), ['c', 'd', 'a', 'b'], reason: 'بلا تاريخ ⇒ بأيّامه، وبلاهما آخراً');
    expect(order(l, SortField.remainingDays, SortDirection.desc), ['a', 'd', 'c', 'b']);
  });

  test('الدين بإشارته كما كان، والجلسة: بلا جلسةٍ آخراً بالاتّجاهين، والتعادل بترتيب القائمة', () {
    final l = [_s(1, 'a', notes: '-15000'), _s(2, 'b', notes: '0'), _s(3, 'c', notes: '-40000'), _s(4, 'd', notes: '5000')];
    expect(order(l, SortField.notes, SortDirection.asc), ['c', 'a', 'b', 'd'], reason: 'الأكثر ديناً أوّلاً تصاعديّاً كما كان (افتراض «المدينون»)');
    final s = [_s(1, 'a', session: 300), _s(2, 'b'), _s(3, 'c', session: 60), _s(4, 'd', session: 300)];
    expect(order(s, SortField.sessionTime, SortDirection.asc), ['c', 'a', 'd', 'b']);
    expect(order(s, SortField.sessionTime, SortDirection.desc), ['a', 'd', 'c', 'b'], reason: 'a وd متعادلان بترتيبهما');
  });

  test('الهاتف والمدير: الفارغ آخراً بالاتّجاهين', () {
    final l = [_s(1, 'a', phone: '07801234567'), _s(2, 'b'), _s(3, 'c', phone: '07701234567')];
    expect(order(l, SortField.phone, SortDirection.asc), ['c', 'a', 'b']);
    expect(order(l, SortField.phone, SortDirection.desc), ['a', 'c', 'b']);
    final m = [_s(1, 'a', parent: 'mgr10'), _s(2, 'b'), _s(3, 'c', parent: 'mgr2')];
    expect(order(m, SortField.parentUsername, SortDirection.asc), ['c', 'a', 'b']);
  });
}
