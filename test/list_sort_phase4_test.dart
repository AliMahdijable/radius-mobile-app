import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/big_subscribers_api.dart';
import 'package:rad_mysvcs/api/receipts_archive_api.dart';
import 'package:rad_mysvcs/core/util/list_orders.dart';
import 'package:rad_mysvcs/core/util/order_rules.dart';
import 'package:rad_mysvcs/screens/cards/cards_screen.dart';
import 'package:rad_mysvcs/screens/employees/employees_screen.dart';
import 'package:rad_mysvcs/screens/managers/el_managers_screen.dart';
import 'package:rad_mysvcs/screens/receipts/receipts_archive_screen.dart';
import 'package:rad_mysvcs/screens/renew/renew_requests_screen.dart';
import 'package:rad_mysvcs/screens/reports/v2/report_kit.dart';
import 'package:rad_mysvcs/screens/sales/sales_screen.dart';
import 'package:rad_mysvcs/screens/tickets/tickets_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «الترتيب بالنقر» — المرحلة ٤ (المالك ٢٤ نوفمبر: «تمام ابدي ببيهن»): الموظّفون، المبيعات وموادّها، الكارتات، أرشيف الوصولات،
/// التذاكر، طلبات التفعيل — بحقول الموقع (client-v2 lib/list-sorts.ts) حرفاً، وبالبيانات نفسها التي يفحصها حزام الموقع
/// (~/work_listsort4/tests/sort4_scen.cjs) فيخرج الترتيب نفسه بالمنصّتين.

// ═══════════════ بيانات حزام الموقع نفسها ═══════════════

Map<String, dynamic> _emp(int id, String username, String fullName, String? last, String created, {bool active = true}) => {
      'id': id, 'parent_admin_id': '2', 'parent_admin_username': 'mgr', 'username': username, 'full_name': fullName, 'phone': null,
      'is_active': active, 'permissions': <String, bool>{}, 'scope_admin_id': null, 'last_login_at': last, 'created_at': created,
    };
final _emps = [
  _emp(1, 'zaid.k', 'زيد كريم', '2026-11-20 10:00:00', '2026-10-01 09:00:00'),
  _emp(2, 'ali2', 'إبراهيم علي', null, '2026-11-10 09:00:00'),
  _emp(3, 'user10', '', '2026-11-23 08:00:00', '2026-09-01 09:00:00'),
  _emp(4, 'user2', 'آمنة حسن', '2026-11-22 08:00:00', '2026-11-20 09:00:00', active: false),
];

Map<String, dynamic> _sale(int id, int total, int profit, {String? name, String? username, String status = 'done'}) => {
      'id': id, 'payment': 'cash', 'status': status, 'total': total, 'cost': total - profit, 'profit': profit,
      'customer': {'kind': username == null ? 'walkin' : 'subscriber', 'idx': username == null ? null : '$id', 'username': username, 'name': name, 'phone': null},
      'note': null, 'by': null, 'employee_id': null, 'created_at': '2026-11-${(10 + id).toString().padLeft(2, '0')}T07:00:00Z',
      'voided_at': status == 'void' ? '2026-11-15T08:00:00Z' : null, 'void_reason': status == 'void' ? 'خطأ' : null,
      'lines': [
        {'item_id': 1, 'name': 'راوتر', 'unit': 'piece', 'qty': 1, 'unit_price': total, 'unit_cost': total - profit, 'total': total, 'cost': total - profit, 'profit': profit},
      ],
    };
final _sales = [
  _sale(6, 30000, 15000, name: 'زبون سعيد'),
  _sale(5, 120000, 20000, name: 'بشير', username: 'u5'),
  _sale(4, 5000, -1000, name: 'حيدر', status: 'void'),
  _sale(3, 75000, 10000, username: 'u3'),
  _sale(2, 200000, 50000),
  _sale(1, 45000, 9000, name: 'آمنة', username: 'u1'),
];

Map<String, dynamic> _item(int id, String name, int price, num qty, int value) => {
      'id': id, 'name': name, 'code': 'C$id', 'unit': 'piece', 'unit_label': 'قطعة', 'sale_price': price, 'cost_avg': 1000, 'qty': qty,
      'stock_value': value, 'margin': 0, 'active': true, 'note': null, 'updated_at': null,
    };
final _items = [
  _item(1, 'راوتر', 45000, 3, 90000),
  _item(2, 'كيبل', 1000, 0, 0),
  _item(3, 'ONU هواوي', 60000, 12, 600000),
  _item(4, 'أداپتر', 0, 5, 10000),
];

final _profiles = [
  {'profile_id': 1, 'profile_name': 'FIBER 35', 'value': 35000, 'remaining': 5, 'qty': 10, 'used': 5, 'series': 4},
  {'profile_id': 2, 'profile_name': 'FIBER 50', 'value': 50000, 'remaining': 20, 'qty': 21, 'used': 1, 'series': 4},
  {'profile_id': 3, 'profile_name': 'FIBER 25', 'value': 25000, 'remaining': 0, 'qty': 12, 'used': 12, 'series': 4},
];
const _seriesOrder = [10, 2, 1, 12, 3, 11, 4, 9, 5, 8, 6, 7];
final _series = [
  for (final i in _seriesOrder)
    {
      'series': 'S-$i', 'type': 0, 'profile_id': (i % 3) + 1, 'profile_name': _profiles[i % 3]['profile_name'], 'value': _profiles[i % 3]['value'],
      'qty': 20, 'used': 20 - ((i * 7) % 13), 'remaining': (i * 7) % 13,
      // كلّها بتاريخٍ واحد: ترتيب «الأحدث أوّلاً» بالتطبيق يبقيها كما وصلت (التعادل بترتيبها)
      'expiration': i % 4 == 0 ? null : '2027-0${1 + (i % 9)}-15', 'expired': false, 'suspended': false, 'created_at': '2026-11-01 10:00:00',
    },
];

final _rcBase = DateTime.utc(2026, 11, 24, 9).millisecondsSinceEpoch;
const _names = ['بشير الكبيسي', 'إبراهيم علي', 'ثامر حسن', 'تقي جواد', 'جاسم محمد', 'آمنة كريم', 'حيدر سالم', 'خالد عبّاس', 'دعاء فاضل', 'ذكرى سعد'];
final _receipts = [
  for (var n = 1; n <= 100; n++)
    {
      'key': 'a:$n', 'activity_id': n, 'receipt_id': n % 3 == 0 ? n : null, 'receipt_no': n % 3 == 0 ? 1000 + n : null, 'type': 'activate',
      'at': _rcBase - n * 3600000, 'printed_at': n % 3 == 0 ? _rcBase - n * 3600000 : null, 'late': false, 'username': 'u$n', 'idx': '$n',
      'name': n % 4 == 0 ? _names[n % _names.length] : null, 'phone': null, 'amount': n % 5 == 0 ? null : 1000 * (((n * 37) % 97) + 1),
      'pay': 'cash', 'partial_amount': null, 'new_balance': null, 'package': 'FIBER 35', 'by': {'employee_id': null, 'username': 'mgr'},
      'reprints': 0, 'voided': false, 'printable': n % 5 != 0,
    },
];

final _tickets = [
  for (var k = 0; k < 45; k++)
    {
      'id': 45 - k, 'status': 'open', 'category': 'internet', 'subject': null,
      'subscriber': {'idx': '${45 - k}', 'username': 't${45 - k}', 'name': (45 - k) % 3 == 0 ? _names[(45 - k) % _names.length] : null},
      'unread': (45 - k) % 7 == 0, 'seen_by_subscriber': true, 'message_count': 1, 'last_author': 'subscriber', 'last_preview': 'النت مقطوع',
      'last_activity_at': DateTime.utc(2026, 11, 1 + (((45 - k) * 11) % 23), 10).toIso8601String(),
      'created_at': DateTime.utc(2026, 10, 1 + ((45 - k) % 28), 10).toIso8601String(), 'status_by': null, 'via': 'app', 'moved': false,
      'can_reply': true, 'can_reopen': false, 'actions': const <String>[], 'image_count': 0,
    },
];

Map<String, dynamic> _renew(int id, String status, int? amount, String? name, String created) => {
      'id': id, 'kind': 'renew', 'status': status, 'months': 1, 'package': {'id': '7', 'name': 'FIBER 35', 'same': true}, 'unit_price': 35000,
      'amount': amount, 'pay_method': 'zaincash', 'created_at': created, 'decided_at': status == 'accepted' ? created : null, 'done_at': null,
      'reject_reason': null, 'company_code': null, 'subscriber': {'idx': '$id', 'username': 'u$id', 'name': name}, 'current_package': 'FIBER 35',
      'note': null, 'via': 'app', 'image': {'available': false, 'expires_at': null}, 'decided_by': null, 'done_source': null,
    };
final _renews = [
  _renew(1, 'pending', 35000, 'بشير', '2026-11-20T06:00:00Z'),
  _renew(2, 'accepted', 50000, 'إبراهيم', '2026-11-23T06:00:00Z'),
  _renew(3, 'pending', null, null, '2026-11-21T06:00:00Z'),
  _renew(4, 'accepted', 25000, 'آمنة', '2026-11-19T06:00:00Z'),
  _renew(5, 'pending', 60000, 'ثامر', '2026-11-22T06:00:00Z'),
];

// ═══════════════ خادمٌ وهميّ ═══════════════

class _P4 implements HttpClientAdapter {
  _P4(this.inner);
  final HttpClientAdapter inner;
  final log = <RequestOptions>[];

  static ResponseBody _json(int status, Object body) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final p = o.path;
    final q = o.queryParameters;
    final get = o.method.toUpperCase() == 'GET';
    log.add(o);
    if (get && p == '/api/v2/employees') return _json(200, {'success': true, 'data': _emps});
    if (get && p == '/api/v2/el/managers') {
      return _json(200, {
        'success': true, 'enabled': true,
        'data': {'balance': 250000, 'deposit_saved': false, 'managers': [
          {'index': 11, 'name': 'زيد كريم', 'other_debt': 0, 'last_topup': {'amount': 25000, 'at': '2026-11-20T07:00:00Z', 'as_debt': false}},
          {'index': 12, 'name': 'إبراهيم علي', 'other_debt': 40000, 'last_topup': null},
          {'index': 13, 'name': 'agent10', 'other_debt': 15000, 'last_topup': {'amount': 50000, 'at': '2026-11-23T07:00:00Z', 'as_debt': true}},
          {'index': 14, 'name': 'آمنة حسن', 'other_debt': 0, 'last_topup': {'amount': 10000, 'at': '2026-11-22T07:00:00Z', 'as_debt': false}},
        ]},
      });
    }
    if (get && p == '/api/v2/employees/permissions-catalog') {
      return _json(200, {
        'success': true,
        'data': {
          'permissions': {'subscribers.view': {'category': 'subscribers', 'label': 'عرض المشتركين', 'default': true}},
          'categories': {'subscribers': {'label': 'المشتركون', 'icon': 'Users'}},
          'defaults': {'subscribers.view': true},
          'presets': <String, dynamic>{},
        },
      });
    }
    if (p == '/api/v2/portal/store') return _json(404, {'success': false});
    if (get && p == '/api/v2/sales/items') {
      return _json(200, {'success': true, 'enabled': true, 'data': _items, 'totals': {'count': 4, 'stock_value': 700000, 'out_of_stock': 1}});
    }
    if (p == '/api/v2/sales/debt-status') return _json(200, {'success': true, 'data': const []});
    if (get && p == '/api/v2/sales') {
      final full = '${q['limit']}' == '1000';
      return _json(200, {
        'success': true, 'enabled': true, 'data': full ? _sales : _sales.take(4).toList(),
        'totals': {'count': 6, 'revenue': 475000, 'cost': 367000, 'profit': 108000, 'cash': 475000, 'debt': 0}, 'unresolved': 0,
        if (!full) 'truncated': true,
      });
    }
    if (get && p == '/api/v2/cards/summary') {
      return _json(200, {
        'success': true, 'enabled': true, 'totals': {'remaining': 25, 'used': 18, 'qty': 43, 'series': _series.length},
        'profiles': _profiles, 'series': _series,
      });
    }
    if (get && p == '/api/v2/cards/purchase/options') return _json(200, {'success': true, 'enabled': false, 'hidden': true});
    if (get && p == '/api/printed-receipts/archive') {
      final c = q['cursor']?.toString();
      final start = c == null ? 0 : int.parse(c.substring(1));
      final page = _receipts.skip(start).take(40).toList();
      return _json(200, {'success': true, 'available': true, 'data': page, 'next': start + 40 < _receipts.length ? 'c${start + 40}' : null});
    }
    if (get && p == '/api/v2/portal/tickets/summary') {
      return _json(200, {'success': true, 'available': true, 'can_view': true, 'can_reply': true, 'counts': {'open': 45, 'answered': 0, 'closed': 0, 'unread': 6, 'total': 45}});
    }
    if (get && p == '/api/v2/portal/tickets') {
      final off = int.tryParse('${q['offset'] ?? 0}') ?? 0;
      final more = off + 30 < _tickets.length;
      return _json(200, {
        'success': true, 'items': _tickets.skip(off).take(30).toList(), 'counts': {'open': 45, 'answered': 0, 'closed': 0, 'unread': 6, 'total': 45},
        'has_more': more, 'next_offset': more ? off + 30 : null,
      });
    }
    if (get && p == '/api/v2/portal/renew-settings') {
      return _json(200, {'success': true, 'available': true, 'can_use': true, 'can_edit': true, 'enabled': true, 'zaincash': '0780', 'master': null, 'note': null});
    }
    if (get && p == '/api/v2/portal/renew-requests') {
      return _json(200, {'success': true, 'items': _renews, 'counts': {'pending': 3, 'accepted': 2}});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

// ═══════════════ مساعدات ═══════════════

final _bidi = RegExp('[${String.fromCharCode(0x2066)}-${String.fromCharCode(0x2069)}${String.fromCharCode(0x200e)}${String.fromCharCode(0x200f)}]');

/// أعلى كلّ نصٍّ ([labels]) على الشاشة — ترتيبها العموديّ هو ترتيب القائمة.
List<String> _orderOf(WidgetTester t, List<String> labels) {
  final tops = <String, double>{};
  for (final l in labels) {
    final f = find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll(_bidi, '').trim() == l);
    if (f.evaluate().isEmpty) continue;
    tops[l] = t.getTopLeft(f.first).dy;
  }
  final out = tops.keys.toList()..sort((a, b) => tops[a]!.compareTo(tops[b]!));
  return out;
}

List<String> _keysOrder(WidgetTester t, String prefix) {
  final found = <String, double>{};
  for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith(prefix)).evaluate()) {
    final k = (e.widget.key! as ValueKey<String>).value.substring(prefix.length);
    final box = e.renderObject;
    if (box is RenderBox && box.hasSize) found[k] = box.localToGlobal(Offset.zero).dy;
  }
  final out = found.keys.toList()..sort((a, b) => found[a]!.compareTo(found[b]!));
  return out;
}

/// تبويب «الموادّ والمخزون» بقسم المبيعات.
Future<void> _itemsTab(WidgetTester t) async {
  final ar = find.text('الموادّ والمخزون');
  final f = ar.evaluate().isNotEmpty ? ar : find.text('sales.tab_items');
  await t.tap(f.first);
  await settle(t, seconds: 1);
}

Future<void> _chip(WidgetTester t, String key) async {
  final f = find.byKey(RpSortChips.chipKey(key));
  await t.ensureVisible(f.first);
  await t.tap(f.first);
  await settle(t, seconds: 1);
}

List<Map<String, Object?>> _shape(List<OrderField> fields) => [
      for (final f in fields)
        {
          'key': f.key,
          'label': f.label,
          'kind': f.kind.name,
          if (f.first != null) 'first': f.first!.name,
          if (f.natural != null) 'natural': f.natural!.name,
        },
    ];

void main() {
  setUpAll(visualSetUpAll);
  tearDown(visualTearDown);

  // ═══════════════ الحقول كالموقع حرفاً ═══════════════
  group('الحقول كالموقع (lib/list-sorts.ts)', () {
    final web = jsonDecode(File('test/fixtures/list_sorts_phase4.json').readAsStringSync()) as Map<String, dynamic>;
    final sets = <String, List<OrderField>>{
      'EMP_SORT': empSort,
      'SALE_SORT': saleSort,
      'ITEM_SORT': itemSort,
      'CARD_STOCK_SORT': cardStockSort,
      'CARD_SERIES_SORT': cardSeriesSort,
      'RECEIPT_SORT': receiptSort,
      'TICKET_SORT': ticketSort,
      'RENEW_SORT': renewSort,
      'EL_MGR_SORT': elMgrSort,
    };
    for (final e in sets.entries) {
      test('${e.key}: المفاتيح والأسماء والنوع واتّجاه أوّل نقرة', () => expect(_shape(e.value), web[e.key]));
    }
    test('«آخر ظهور» مع «المتّصل الآن»، والحدّ، والافتراضان، ومفاتيح الحفظ', () {
      expect(_shape(empSortShown(presence: true, ledger: false)).firstWhere((f) => f['key'] == 'seen'), web['EMP_SEEN_LIVE']);
      expect(sortAllCap, web['SORT_ALL_CAP']);
      expect([saleSortDefault.key, saleSortDefault.dir.name], web['SALE_SORT_DEFAULT']);
      expect([receiptSortDefault.key, receiptSortDefault.dir.name], web['RECEIPT_SORT_DEFAULT']);
      for (final k in (web['STORAGE_KEYS'] as Map).entries) {
        expect(OrderPrefs.listKey(k.key as String), k.value);
      }
    });
    test('حقول البطاقة: بلا «المتّصل» وبلا «حساب الموظف» ثلاثة، ومعهما خمسة', () {
      expect(empSortShown(presence: false, ledger: false).map((f) => f.key), ['name', 'seen', 'created']);
      expect(empSortShown(presence: true, ledger: true).map((f) => f.key), ['name', 'seen', 'ops', 'owes', 'created']);
      expect(empSortShown(presence: false, ledger: false)[1].label, 'آخر دخول');
      expect(cardSeriesShown(created: false, expiry: true).map((f) => f.key), ['series', 'name', 'remaining', 'expiry']);
    });
  });

  // ═══════════════ الترتيب نفسه على بيانات حزام الموقع ═══════════════
  group('الترتيب كالموقع على البيانات نفسها', () {
    List<String> emp(OrderValue v, {Map<int, EmpPresence>? presence, Map<int, num>? owes}) => [
          for (final e in sortList<Map<String, dynamic>>(_emps, v, empSort, (e, k) {
            final id = e['id'] as int;
            return empSortValue(k,
                username: e['username'] as String,
                fullName: e['full_name'] as String?,
                lastLoginAt: e['last_login_at'] as String?,
                createdAt: e['created_at'] as String?,
                presence: presence?[id],
                owes: owes?[id]);
          }))
            e['username'] as String,
        ];
    test('الموظّفون', () {
      expect(emp(const OrderValue('name', OrderDir.asc)), ['user10', 'ali2', 'user2', 'zaid.k']);
      expect(emp(const OrderValue('name', OrderDir.desc)), ['zaid.k', 'user2', 'ali2', 'user10']);
      expect(emp(const OrderValue('seen', OrderDir.desc)), ['user10', 'user2', 'zaid.k', 'ali2']);
      expect(emp(const OrderValue('seen', OrderDir.asc)), ['zaid.k', 'user2', 'user10', 'ali2']);
      expect(emp(const OrderValue('created', OrderDir.desc)), ['user2', 'ali2', 'zaid.k', 'user10']);
      final pr = <int, EmpPresence>{
        1: (online: false, lastSeenAt: DateTime.utc(2026, 11, 24, 6), opsToday: 5),
        2: (online: false, lastSeenAt: null, opsToday: 0),
        3: (online: false, lastSeenAt: DateTime.utc(2026, 11, 24, 5), opsToday: null),
        // المتّصل الآن «آخر ظهوره» أقدم من غيره — يسبق رغم ذلك (لا بآخر ظهوره)
        4: (online: true, lastSeenAt: DateTime.utc(2026, 11, 24, 4), opsToday: 2),
      };
      expect(emp(const OrderValue('seen', OrderDir.desc), presence: pr), ['user2', 'zaid.k', 'user10', 'ali2']);
      expect(emp(const OrderValue('ops', OrderDir.desc), presence: pr), ['zaid.k', 'user2', 'ali2', 'user10']);
      expect(emp(const OrderValue('owes', OrderDir.desc), owes: {1: 0, 2: 25000, 3: 100000}), ['user10', 'ali2', 'zaid.k', 'user2']);
    });
    List<int> sale(OrderValue v) => [
          for (final s in sortList<Map<String, dynamic>>(_sales, v, saleSort, (s, k) {
            final c = s['customer'] as Map<String, dynamic>;
            return saleSortValue(k,
                status: s['status'] as String, total: s['total'] as num, profit: s['profit'] as num, customerName: c['name'] as String?, username: c['username'] as String?);
          }))
            s['id'] as int,
        ];
    test('المبيعات', () {
      expect(sale(saleSortDefault), [6, 5, 4, 3, 2, 1]);
      expect(sale(const OrderValue('total', OrderDir.desc)), [2, 5, 3, 1, 6, 4]);
      expect(sale(const OrderValue('profit', OrderDir.desc)), [2, 5, 6, 3, 1, 4]);
      expect(sale(const OrderValue('customer', OrderDir.asc)), [3, 1, 5, 4, 6, 2]);
      expect(sale(const OrderValue('date', OrderDir.asc)), [1, 2, 3, 4, 5, 6]);
    });
    List<String> item(OrderValue v) => [
          for (final i in sortList<Map<String, dynamic>>(_items, v, itemSort, (i, k) => itemSortValue(k,
              name: i['name'] as String, qty: i['qty'] as num, salePrice: i['sale_price'] as num, stockValue: i['stock_value'] as num)))
            i['name'] as String,
        ];
    test('الموادّ: الكمّيّة أوّل نقرة الأقلّ', () {
      expect(firstDir(itemSort[1]), OrderDir.asc);
      expect(item(const OrderValue('qty', OrderDir.asc)), ['كيبل', 'راوتر', 'أداپتر', 'ONU هواوي']);
      expect(item(const OrderValue('qty', OrderDir.desc)), ['ONU هواوي', 'أداپتر', 'راوتر', 'كيبل']);
      expect(item(const OrderValue('price', OrderDir.desc)), ['ONU هواوي', 'راوتر', 'كيبل', 'أداپتر']);
      expect(item(const OrderValue('name', OrderDir.asc)), ['ONU هواوي', 'أداپتر', 'راوتر', 'كيبل']);
    });
    test('السلاسل: الأرقام بقيمتها والانتهاء الأقرب أوّلاً والفارغ آخراً', () {
      List<String> ser(OrderValue v) => [
            for (final s in sortList<Map<String, dynamic>>(_series, v, cardSeriesSort, (s, k) => cardSeriesSortValue(k,
                series: s['series'] as String, name: s['profile_name'] as String?, remaining: s['remaining'] as num,
                createdAt: s['created_at'] as String?, expiration: s['expiration'] as String?)))
              s['series'] as String,
          ];
      expect(ser(const OrderValue('series', OrderDir.asc)).take(10), ['S-1', 'S-2', 'S-3', 'S-4', 'S-5', 'S-6', 'S-7', 'S-8', 'S-9', 'S-10']);
      final exp = ser(OrderValue('expiry', firstDir(cardSeriesSort[4])));
      expect(exp.sublist(9), ['S-12', 'S-4', 'S-8'], reason: 'بلا انتهاء آخراً بترتيبها');
    });
    test('طلبات التفعيل', () {
      List<int> rn(OrderValue? v) => [
            for (final r in sortOrKeep<Map<String, dynamic>>(_openFirst(_renews), v, renewSort, (r, k) {
              final s = r['subscriber'] as Map<String, dynamic>;
              return renewSortValue(k,
                  createdAt: DateTime.parse(r['created_at'] as String), name: s['name'] as String?, username: s['username'] as String?, amount: r['amount'] as num?);
            }))
              r['id'] as int,
          ];
      expect(rn(null), [5, 3, 1, 4, 2]);
      expect(rn(const OrderValue('amount', OrderDir.desc)), [5, 2, 1, 4, 3]);
      expect(rn(const OrderValue('name', OrderDir.asc)), [3, 2, 4, 1, 5]);
      expect(rn(const OrderValue('date', OrderDir.desc)), [2, 5, 3, 1, 4]);
    });
  });

  // ═══════════════ الشاشات ═══════════════
  Future<_P4> open(WidgetTester t, Widget Function() screen, {double width = 390, double height = 2600, double scale = 1.0, bool dark = false}) async {
    final inner = await visualSetUp(s1bSasOwner);
    final srv = _P4(inner);
    ApiClient.dio.httpClientAdapter = srv;
    BigSubscribersApi.reset();
    await pumpVisual(
      t,
      VisualDevice(dark ? '_dark' : '', Size(width, height), 2, dark: dark),
      home: (_) => screen(),
      wrap: (child) => Builder(
        builder: (ctx) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child),
      ),
    );
    await settle(t, seconds: 3);
    return srv;
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
  }

  testWidgets('الموظّفون: «رتّب حسب» بحقول البطاقة — الأنفع ثمّ يقلب ثمّ الأصل، ويُحفظ', (t) async {
    await open(t, () => const EmployeesScreen());
    final names = ['زيد كريم', 'إبراهيم علي', 'user10', 'آمنة حسن'];
    expect(find.byKey(RpSortChips.chipKey('name')), findsOneWidget);
    expect(find.byKey(RpSortChips.chipKey('seen')), findsOneWidget);
    expect(find.byKey(RpSortChips.chipKey('created')), findsOneWidget);
    expect(find.byKey(RpSortChips.chipKey('ops')), findsNothing, reason: 'بلا «المتّصل الآن»');
    expect(_orderOf(t, names), names, reason: 'كما وصلت');
    await _chip(t, 'name');
    expect(_orderOf(t, names), ['user10', 'إبراهيم علي', 'آمنة حسن', 'زيد كريم']);
    await _chip(t, 'name');
    expect(_orderOf(t, names), ['زيد كريم', 'آمنة حسن', 'إبراهيم علي', 'user10']);
    await _chip(t, 'name');
    expect(_orderOf(t, names), names, reason: 'الثالثة ترجع الأصل');
    await _chip(t, 'created');
    expect(_orderOf(t, names), ['آمنة حسن', 'إبراهيم علي', 'زيد كريم', 'user10']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('list.v2.employees.sort'), '{"k":"created","d":"desc"}');
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('مدراء ايرث لنك: «رتّب حسب» المدير وديون أخرى وآخر شحن — كالموقع', (t) async {
    await open(t, () => const ElManagersScreen());
    final names = ['زيد كريم', 'إبراهيم علي', 'agent10', 'آمنة حسن'];
    expect(_orderOf(t, names), names, reason: 'كما وصلت');
    await _chip(t, 'name');
    expect(_orderOf(t, names), ['agent10', 'إبراهيم علي', 'آمنة حسن', 'زيد كريم'], reason: 'اللاتينيّ أوّلاً، إ وآ ألف');
    await _chip(t, 'debt');
    expect(_orderOf(t, names), ['إبراهيم علي', 'agent10', 'زيد كريم', 'آمنة حسن'], reason: 'الأكثر ديناً، و«لا شيء» آخراً بترتيبها');
    await _chip(t, 'topup');
    expect(_orderOf(t, names), ['agent10', 'آمنة حسن', 'زيد كريم', 'إبراهيم علي'], reason: 'الأحدث شحناً، ومن لم يُشحن آخراً');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('list.v2.el-managers.sort'), '{"k":"topup","d":"desc"}');
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('المبيعات: «التاريخ» مجمّعٌ كما كان؛ المبلغ يجلب الفترة كلّها (1000) وقائمةٌ واحدة بتاريخ كلّ سطر', (t) async {
    final srv = await open(t, () => const SalesScreen());
    expect(_keysOrder(t, 'sale-row-'), ['6', '5', '4', '3']);
    expect(find.byKey(const ValueKey('sale-date-6')), findsNothing, reason: 'اليوم برأس مجموعته');
    expect(srv.log.where((o) => o.path == '/api/v2/sales' && '${o.queryParameters['limit']}' == '1000'), isEmpty);
    await _chip(t, 'total');
    await settle(t, seconds: 2);
    expect(srv.log.where((o) => o.path == '/api/v2/sales' && '${o.queryParameters['limit']}' == '1000'), isNotEmpty);
    expect(_keysOrder(t, 'sale-row-'), ['2', '5', '3', '1', '6', '4']);
    expect(find.byKey(const ValueKey('sale-date-2')), findsOneWidget, reason: 'قائمةٌ واحدة والتاريخ على السطر');
    await _chip(t, 'customer');
    expect(_keysOrder(t, 'sale-row-'), ['3', '1', '5', '4', '6', '2']);
    await _chip(t, 'date');
    expect(_keysOrder(t, 'sale-row-'), ['6', '5', '4', '3'], reason: 'الافتراض حرفاً (أحدث ٣٠٠)');
    expect(find.byKey(const ValueKey('sale-date-6')), findsNothing);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('الموادّ: الكمّيّة أوّل نقرة الأقلّ ثمّ الأكثر', (t) async {
    await open(t, () => const SalesScreen());
    await _itemsTab(t);
    final names = ['راوتر', 'كيبل', 'ONU هواوي', 'أداپتر'];
    expect(_orderOf(t, names), names);
    await _chip(t, 'qty');
    expect(_orderOf(t, names), ['كيبل', 'راوتر', 'أداپتر', 'ONU هواوي']);
    await _chip(t, 'qty');
    expect(_orderOf(t, names), ['ONU هواوي', 'أداپتر', 'راوتر', 'كيبل']);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('الكارتات: الباقات بالمتبقّي، والسلاسل بأرقامها قبل تقسيم الصفحات', (t) async {
    await open(t, () => const CardsScreen());
    final p = ['FIBER 35', 'FIBER 50', 'FIBER 25'];
    await _chip(t, 'remaining');
    expect(_orderOf(t, p), ['FIBER 50', 'FIBER 35', 'FIBER 25']);
    final codes = [for (var i = 1; i <= 12; i++) 'S-$i'];
    await t.ensureVisible(find.byKey(const ValueKey('cards-series-sort')));
    await t.tap(find.descendant(of: find.byKey(const ValueKey('cards-series-sort')), matching: find.byKey(RpSortChips.chipKey('series'))));
    await settle(t, seconds: 1);
    expect(_orderOf(t, codes), ['S-1', 'S-2', 'S-3', 'S-4', 'S-5', 'S-6', 'S-7', 'S-8', 'S-9', 'S-10'], reason: 'الصفحة الأولى من المرتَّبة');
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('الوصولات: المبلغ يجلب صفحات المدّة كلّها تباعاً ثمّ يرتّب', (t) async {
    final srv = await open(t, () => const ReceiptsArchiveScreen(), height: 4000);
    List<ArchiveItem> rows() => [for (final w in t.widgetList<ArchiveRowTile>(find.byType(ArchiveRowTile))) w.item];
    expect(rows().first.key, 'a:1');
    await _chip(t, 'amount');
    await settle(t, seconds: 3);
    final cursors = [for (final o in srv.log) if (o.path == '/api/printed-receipts/archive' && o.queryParameters['cursor'] != null) o.queryParameters['cursor']];
    expect(cursors, ['c40', 'c80']);
    final amounts = [for (final r in rows()) r.amount];
    final vals = amounts.whereType<num>().toList();
    expect(vals.isNotEmpty, isTrue);
    for (var i = 1; i < vals.length; i++) {
      expect(vals[i - 1] >= vals[i], isTrue);
    }
    expect(amounts.first, 97000, reason: 'أكبر مبلغٍ في المدّة كلّها لا في أوّل صفحة');
    expect(find.text('تحميل المزيد'), findsNothing);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('التذاكر: المشترك يجلب الصفحة الثانية ثمّ يرتّب، والثالثة ترجع ترتيب الخادم', (t) async {
    // ٤٥ بطاقة: شاشةٌ طويلة كفايةً لتُبنى كلّها (القائمة تبني ما يظهر وحده)
    final srv = await open(t, () => const TicketsScreen(), height: 9000);
    expect(_keysOrder(t, 'ticket-tile-').first, '45');
    await _chip(t, 'name');
    await settle(t, seconds: 2);
    expect(srv.log.any((o) => o.path == '/api/v2/portal/tickets' && '${o.queryParameters['offset']}' == '30'), isTrue);
    final order = _keysOrder(t, 'ticket-tile-');
    expect(order.length, 45);
    expect(order.take(3), ['1', '2', '4'], reason: 't1 ثمّ t2 ثمّ t4 (t3 باسمٍ عربيّ)');
    await _chip(t, 'name');
    await _chip(t, 'name');
    expect(_keysOrder(t, 'ticket-tile-').take(3), ['45', '44', '43']);
    expect(t.takeException(), isNull);
    await close(t);
  });

  testWidgets('طلبات التفعيل: «بانتظارك» أوّلاً، ثمّ المبلغ والمشترك', (t) async {
    await open(t, () => const RenewRequestsScreen());
    expect(_keysOrder(t, 'renew-tile-'), ['5', '3', '1', '4', '2']);
    await _chip(t, 'amount');
    expect(_keysOrder(t, 'renew-tile-'), ['5', '2', '1', '4', '3']);
    await _chip(t, 'name');
    expect(_keysOrder(t, 'renew-tile-'), ['3', '2', '4', '1', '5']);
    expect(t.takeException(), isNull);
    await close(t);
  });

  // ═══════════════ لا فيض ولا قصّ من أضيق هاتف إلى ٤٨٠ بخطٍّ عاديّ ومكبَّر ═══════════════
  final screens = <String, Widget Function()>{
    'employees': () => const EmployeesScreen(),
    'sales': () => const SalesScreen(),
    'items': () => const SalesScreen(),
    'cards': () => const CardsScreen(),
    'receipts': () => const ReceiptsArchiveScreen(),
    'tickets': () => const TicketsScreen(),
    'renew': () => const RenewRequestsScreen(),
    'el-managers': () => const ElManagersScreen(),
  };
  for (final s in screens.entries) {
    for (final width in [320.0, 480.0]) {
      for (final scale in [1.0, 1.2]) {
        testWidgets('${s.key} @$width ×$scale: «رتّب حسب» بلا فيض', (t) async {
          await open(t, s.value, width: width, height: 1700, scale: scale, dark: width == 320);
          if (s.key == 'items') await _itemsTab(t);
          expect(find.byType(RpSortChips), findsWidgets);
          expect(t.takeException(), isNull);
          await close(t);
        });
      }
    }
  }
}

/// «بانتظارك» أوّلاً ثمّ المقبولة، والأحدث (الرقم الأكبر) في كلٍّ — sortOpenFirst كالموقع.
List<Map<String, dynamic>> _openFirst(List<Map<String, dynamic>> l) => [...l]..sort((a, b) {
    if (a['status'] == b['status']) return (b['id'] as int).compareTo(a['id'] as int);
    return a['status'] == 'pending' ? -1 : 1;
  });
