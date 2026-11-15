import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// «تقارير الأرصدة» — خادمٌ وهميّ على ApiClient.dio (بعقد server/balanceReports.js) للاختبارات واللقطات.
/// بياناتٌ مصطنعة وحدها: لا أسماء مشتركين حقيقيّة.

const int _day = 86400000;

/// «الآن» ثابت للحسابات: ١٥ تشرين الثاني، ظهراً بتوقيت بغداد — من سنة الجهاز (فلا تظهر السنة في التسميات).
final int balanceNowMs = DateTime.utc(DateTime.now().year, 11, 15, 9).millisecondsSinceEpoch;

/// يومٌ قبل [daysAgo] من «الآن»، الساعة [hour] بتوقيت بغداد.
int balanceStart(int daysAgo, [int hour = 9]) {
  final d = DateTime.fromMillisecondsSinceEpoch(balanceNowMs - daysAgo * _day, isUtc: true);
  return DateTime.utc(d.year, d.month, d.day, hour - 3).millisecondsSinceEpoch;
}

Map<String, dynamic> balancePeriodJson({
  required int id,
  required int start,
  int? closed,
  required num amount,
  required num cash,
  required num paidIn,
  required num debts,
  required num open,
  num late = 0,
  num income = 0,
  String? note,
  List<Map<String, dynamic>>? adjustments,
  Map<String, int>? counts,
  Map<String, num>? transfers,
}) =>
    {
      'id': id,
      'started_at_ms': start,
      'ends_at_ms': null,
      'amount': amount,
      'note': note,
      'closed_at_ms': closed,
      'sales': cash + debts,
      'cash_now': cash,
      'paid_in': paidIn,
      'debts_created': debts,
      'debts_open': open,
      'late_profit': late,
      'written_off': 0,
      'untracked': 0,
      'income_in_window': income,
      'counts': counts ?? {'cash': 26, 'credit': 16, 'partial': 1, 'payments': 6, 'activations': 43},
      'adjustments': adjustments ?? <Map<String, dynamic>>[],
      'transfers': transfers ?? {'count': 0, 'sum': 0},
    };

/// حركاتٌ منوَّعة: نقدي/آجل/جزئي بأحوال دينها، وتسديدات — الأحدث أوّلاً.
List<Map<String, dynamic>> balanceMovesJson(Map<String, dynamic> p, int count, {bool long = false, bool big = false}) {
  final out = <Map<String, dynamic>>[];
  final start = p['started_at_ms'] as int;
  final closed = p['closed_at_ms'] as int?;
  for (var i = 0; i < count; i++) {
    final at = start + (count - i) * 2 * 3600000;
    final k = i % 6;
    final user = long && i % 3 == 0 ? 'very.long.subscriber.username.number$i@some-long-network-name.iq' : 'user$i@net';
    final price = big ? 1250000000 + i * 1000 : (2 + (i % 5)) * 5000 + 20000;
    if (k == 5) {
      out.add({
        'key': 'p${900 + i}',
        'kind': 'payment',
        'at_ms': at,
        'sub': '$i',
        'username': user,
        'amount': big ? price : 25000,
        'after_close': closed != null && i % 2 == 1,
        'advance': i % 12 == 5,
        'by': i % 3 == 2 ? 'sara' : null,
      });
      continue;
    }
    final pay = (k == 0 || k == 4) ? 'cash' : (k == 2 ? 'partial' : 'credit');
    final cash = pay == 'cash' ? price : (pay == 'partial' ? (price / 2000).round() * 1000 : 0);
    final debt = price - cash;
    var state = 'none';
    String? turned;
    num remaining = 0;
    num paidIn = 0;
    num paidLate = 0;
    int? last;
    if (debt > 0) {
      final v = (i ~/ 6) % 4;
      if (v == 0) {
        state = 'paid';
        turned = 'cash';
        paidIn = debt;
        last = at + _day;
      } else if (v == 1) {
        state = 'open';
        remaining = debt;
      } else if (v == 2) {
        state = 'partly';
        turned = 'cash';
        paidIn = (debt / 2000).round() * 1000;
        remaining = debt - paidIn;
        last = at + _day;
      } else if (closed != null) {
        state = 'paid';
        turned = 'profit';
        paidLate = debt;
        last = closed + _day;
      } else {
        state = 'paid';
        turned = 'cash';
        paidIn = debt;
        last = at + 2 * _day;
      }
    }
    out.add({
      'key': 'a${500 + i}',
      'kind': 'activate',
      'at_ms': at,
      'sub': '$i',
      'username': user,
      'package': i % 3 == 0 ? 'باقة 35 ميغا الشهريّة' : 'Fiber 50',
      'price': price,
      'pay': pay,
      'cash': cash,
      'debt': debt,
      'remaining': remaining,
      'debt_state': state,
      'turned': turned,
      'paid_in': paidIn,
      'paid_late': paidLate,
      'written_off': 0,
      'untracked': 0,
      'excess': 0,
      'last_paid_at_ms': last,
      'after_close': false,
      'by': i % 5 == 4 ? 'sara' : null,
    });
  }
  return out;
}

class BalanceWrite {
  const BalanceWrite(this.method, this.path, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> body;
}

class BalancePageReq {
  const BalancePageReq(this.id, this.filter, this.q, this.offset);
  final int id;
  final String filter;
  final String q;
  final int offset;
}

class BalanceServer implements HttpClientAdapter {
  BalanceServer();

  /// مثال المالك: شحن 2,000,000، طبّله 1,750,000، ديون الفترة 600,000 ⇒ معوز 250,000.
  factory BalanceServer.ownerExample({int moves = 47, bool long = false, bool big = false, String? note, num income = 400000}) {
    final s = BalanceServer();
    final p = balancePeriodJson(id: 1, start: balanceStart(26), amount: 2000000, cash: 1450000, paidIn: 300000, debts: 900000, open: 600000, income: income, note: note);
    s.periods.add(p);
    s.moves[1] = balanceMovesJson(p, moves, long: long, big: big);
    return s;
  }

  /// جاريةٌ + بانتظار الإغلاق + مغلقةٌ بربحٍ بعد الإغلاق.
  factory BalanceServer.three({bool long = false, bool big = false}) {
    final s = BalanceServer.ownerExample(moves: 12, long: long, big: big);
    final waiting = balancePeriodJson(
        id: 2, start: balanceStart(55), amount: 1500000, cash: 900000, paidIn: 350000, debts: 700000, open: 350000, counts: {'cash': 18, 'credit': 14, 'partial': 2, 'payments': 9, 'activations': 34});
    final closed = balancePeriodJson(
      id: 3,
      start: balanceStart(88),
      closed: balanceStart(56, 12),
      amount: 1800000,
      cash: 1300000,
      paidIn: 400000,
      debts: 800000,
      open: 100000,
      late: 300000,
      adjustments: [
        {'id': 90, 'amount': 100000, 'source': 'pocket', 'note': null, 'created_at_ms': balanceStart(57)},
      ],
      counts: {'cash': 30, 'credit': 15, 'partial': 0, 'payments': 12, 'activations': 45},
    );
    s.periods.addAll([waiting, closed]);
    s.moves[2] = balanceMovesJson(waiting, 8);
    s.moves[3] = balanceMovesJson(closed, 30);
    return s;
  }

  bool enabled = true;
  bool employee = false;

  /// سؤال «هل الميزة مفتوحة؟» يفشل (عثرة شبكة) — وعدّاد أسئلته.
  bool meFail = false;
  int meReads = 0;
  double balance = 500000;
  bool balanceUnknown = false;

  /// `big` | `unavailable` | null
  String? listFail;
  final failOffsets = <int>{};
  bool shapeFail = false;
  Map<String, dynamic>? adjustFail;
  Completer<void>? holdPages;

  final periods = <Map<String, dynamic>>[];
  final moves = <int, List<Map<String, dynamic>>>{};
  Map<String, num>? totals;
  Map<String, Object>? quality;

  final writes = <BalanceWrite>[];
  final pageReqs = <BalancePageReq>[];
  int listReads = 0;
  int _nextId = 20;
  int _nextAdj = 100;

  BalanceWrite? lastWrite(String method, RegExp path) {
    for (final w in writes.reversed) {
      if (w.method == method && path.hasMatch(w.path)) return w;
    }
    return null;
  }

  static void _recalc(Map<String, dynamic> p, bool latest) {
    final adj = (p['adjustments'] as List).fold<num>(0, (s, a) => s + ((a as Map)['amount'] as num));
    final collected = (p['cash_now'] as num) + (p['paid_in'] as num);
    final amount = p['amount'] as num;
    final late = p['late_profit'] as num;
    final covered = collected + adj;
    final remaining = amount - covered > 0 ? amount - covered : 0;
    final closed = p['closed_at_ms'] != null;
    final net = collected + late - amount;
    final pocket = amount - (collected + late);
    p['collected'] = collected;
    p['adjustments_sum'] = adj;
    p['covered'] = covered;
    p['remaining'] = remaining;
    p['progress'] = amount > 0 ? ((covered / amount).clamp(0, 1) * 1000).round() / 1000 : 0;
    p['state'] = closed ? 'closed' : (latest ? 'running' : 'waiting');
    p['can_close'] = !closed && remaining <= 0.5;
    p['net'] = net;
    p['profit'] = net > 0 ? net : 0;
    p['pocket_outstanding'] = pocket <= 0 ? 0 : (pocket < adj ? pocket : adj);
  }

  Map<String, dynamic> overview() {
    final sorted = [...periods]..sort((a, b) => (b['started_at_ms'] as int).compareTo(a['started_at_ms'] as int));
    for (var i = 0; i < sorted.length; i++) {
      sorted[i]['ends_at_ms'] = i == 0 ? null : sorted[i - 1]['started_at_ms'];
      _recalc(sorted[i], i == 0);
    }
    return {
      'feature_enabled': true,
      'can_manage': true,
      'now_ms': balanceNowMs,
      'periods': sorted,
      'totals': totals ?? {'old_paid': 0, 'manual_paid': 0, 'other_paid': 0, 'advance': 0, 'closed_net': 0, 'debts_open': 0},
      'quality': quality ?? {'rows': 100, 'no_price': 0, 'no_amount': 0, 'no_snapshot': 0, 'drift': 0, 'transfers_unknown': false},
    };
  }

  static bool _keep(Map<String, dynamic> m, String filter, String q) {
    if (q.isNotEmpty && !('${m['username'] ?? ''}'.toLowerCase().contains(q.toLowerCase()))) return false;
    if (q.isNotEmpty && m['username'] == null) return false;
    if (filter == 'all') return true;
    if (filter == 'payments') return m['kind'] != 'activate';
    if (m['kind'] != 'activate') return false;
    if (filter == 'open') return (m['remaining'] as num) > 0.5;
    if (filter == 'paid') return m['debt_state'] == 'paid';
    return m['pay'] == filter;
  }

  static Map<String, int> _counts(List<Map<String, dynamic>> all) {
    final c = {'all': all.length, 'cash': 0, 'credit': 0, 'partial': 0, 'open': 0, 'paid': 0, 'payments': 0};
    for (final m in all) {
      if (m['kind'] != 'activate') {
        c['payments'] = c['payments']! + 1;
        continue;
      }
      c[m['pay'] as String] = c[m['pay'] as String]! + 1;
      if ((m['remaining'] as num) > 0.5) c['open'] = c['open']! + 1;
      if (m['debt_state'] == 'paid') c['paid'] = c['paid']! + 1;
    }
    return c;
  }

  (int, Map<String, dynamic>) _done(Map<String, dynamic> result) => (200, {'success': true, 'result': result, 'data': overview()});
  (int, Map<String, dynamic>) _refuse(String code, String message, [Map<String, dynamic> extra = const {}]) => (409, {'success': false, 'code': code, 'message': message, ...extra});

  static final _path = RegExp(r'^/api/v2/balance-reports/periods(?:/(\d+)(?:/(close|reopen|adjustments)(?:/(\d+))?)?)?$');

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final r = await _route(o);
    return ResponseBody.fromString(jsonEncode(r.$2), r.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  Future<(int, Map<String, dynamic>)> _route(RequestOptions o) async {
    const base = '/api/v2/balance-reports';
    final p = o.path;
    final m = o.method;
    final body = o.data is Map ? Map<String, dynamic>.from(o.data as Map) : <String, dynamic>{};
    if (p == '/api/v2/admin-widgets') {
      return (200, {'success': true, 'points': 0, 'balance': balanceUnknown ? 0 : balance, if (balanceUnknown) 'balance_unavailable': true});
    }
    if (p == '$base/me') {
      meReads++;
      if (meFail) return (503, {'success': false, 'message': 'الخدمة مشغولة'});
      return (200, {'success': true, 'data': {'feature_enabled': enabled, 'can_manage': !employee, 'is_employee': employee}});
    }
    if (p == base && m == 'GET') {
      listReads++;
      if (employee) return (403, {'success': false, 'code': 'MANAGER_ONLY', 'message': 'هذا القسم لمدير الصفحة وحده'});
      if (listFail == 'big') return _refuse('BALANCE_REPORT_TOO_BIG', 'حركات هذا الحساب أكثر ممّا يحسبه التقرير الآن — راسل الدعم لتجهيزه لحسابك');
      if (listFail == 'unavailable') return _refuse('BALANCE_REPORTS_UNAVAILABLE', 'تعذّر تحميل تقارير الأرصدة الآن — حاول بعد قليل');
      if (!enabled) return (200, {'success': true, 'data': {'feature_enabled': false, 'can_manage': true, 'periods': <Object>[]}});
      return (200, {'success': true, 'data': overview()});
    }
    final pm = _path.firstMatch(p);
    if (pm == null) return (404, {'success': false, 'message': 'غير موجود'});
    final id = pm.group(1) == null ? null : int.parse(pm.group(1)!);
    if (m != 'GET') writes.add(BalanceWrite(m, p, body));
    if (id == null && m == 'POST') {
      if (periods.any((x) => x['started_at_ms'] == body['started_at_ms'])) return _refuse('SAME_START', 'توجد شحنة مسجّلة بهذا التاريخ والوقت نفسه');
      final np = balancePeriodJson(id: _nextId++, start: body['started_at_ms'] as int, amount: body['amount'] as num, cash: 0, paidIn: 0, debts: 0, open: 0, note: '${body['note'] ?? ''}'.isEmpty ? null : '${body['note']}', counts: {'cash': 0, 'credit': 0, 'partial': 0, 'payments': 0, 'activations': 0});
      periods.add(np);
      moves[np['id'] as int] = [];
      return _done({'id': np['id']});
    }
    Map<String, dynamic>? period;
    for (final x in periods) {
      if (x['id'] == id) period = x;
    }
    if (period == null) return (404, {'success': false, 'code': 'PERIOD_NOT_FOUND', 'message': 'الفترة غير موجودة'});
    final sub = pm.group(2);
    if (sub == null) {
      if (m == 'GET') {
        final q = o.queryParameters;
        final filter = '${q['filter'] ?? 'all'}';
        final text = '${q['q'] ?? ''}';
        final off = int.tryParse('${q['offset'] ?? 0}') ?? 0;
        final lim = int.tryParse('${q['limit'] ?? 20}') ?? 20;
        pageReqs.add(BalancePageReq(id!, filter, text, off));
        if (holdPages != null) await holdPages!.future;
        if (failOffsets.contains(off)) {
          return shapeFail ? (200, {'success': true, 'data': {'nope': 1}}) : _refuse('BALANCE_REPORTS_UNAVAILABLE', 'تعذّر تحميل تقارير الأرصدة الآن — حاول بعد قليل');
        }
        final all = (moves[id] ?? const <Map<String, dynamic>>[]).where((x) => _keep(x, filter, text)).toList();
        overview();
        return (200, {
          'success': true,
          'data': {
            'feature_enabled': true,
            'period': period,
            'filter': filter,
            'q': text.toLowerCase(),
            'counts': _counts(moves[id] ?? const []),
            'movements': {'items': all.skip(off).take(lim).toList(), 'total': all.length, 'offset': off},
          },
        });
      }
      if (m == 'PUT') {
        if (period['closed_at_ms'] != null) return _refuse('PERIOD_CLOSED', 'الفترة مغلقة — ألغِ إغلاقها أوّلاً ثمّ عدّل');
        if (body['amount'] != null) period['amount'] = body['amount'];
        if (body['started_at_ms'] != null) period['started_at_ms'] = body['started_at_ms'];
        if (body.containsKey('note')) period['note'] = '${body['note'] ?? ''}'.isEmpty ? null : body['note'];
        return _done({'id': id});
      }
      if (m == 'DELETE') {
        periods.removeWhere((x) => x['id'] == id);
        return _done({'id': id, 'deleted': true});
      }
    }
    if (sub == 'adjustments') {
      if (m == 'POST') {
        overview();
        if (adjustFail != null) return _refuse('${adjustFail!['code']}', '${adjustFail!['message']}');
        final amount = body['amount'] as num;
        if (amount > (period['remaining'] as num) + 0.5) return _refuse('OVER_REMAINING', 'المبلغ أكبر من المعوز', {'remaining': period['remaining']});
        final a = {'id': _nextAdj++, 'amount': amount, 'source': body['source'], 'note': body['note'], 'created_at_ms': balanceNowMs};
        (period['adjustments'] as List).insert(0, a);
        (moves[id!] ??= []).insert(0, {'key': 'j${a['id']}', 'kind': 'adjust', 'at_ms': balanceNowMs, 'amount': amount, 'source': body['source'], 'note': body['note']});
        return _done({'id': a['id']});
      }
      if (m == 'DELETE') {
        final aid = int.parse(pm.group(3)!);
        (period['adjustments'] as List).removeWhere((x) => (x as Map)['id'] == aid);
        moves[id!]?.removeWhere((x) => x['key'] == 'j$aid');
        return _done({'id': aid, 'deleted': true});
      }
    }
    if (sub == 'close' && m == 'POST') {
      overview();
      if (period['can_close'] != true) return _refuse('NOT_COVERED', 'مبلغ الشحنة لم يكتمل بعد', {'remaining': period['remaining']});
      period['closed_at_ms'] = balanceNowMs;
      return _done({'id': id, 'closed': true});
    }
    if (sub == 'reopen' && m == 'POST') {
      period['closed_at_ms'] = null;
      return _done({'id': id, 'closed': false});
    }
    return (404, {'success': false, 'message': 'غير موجود'});
  }

  @override
  void close({bool force = false}) {}
}
